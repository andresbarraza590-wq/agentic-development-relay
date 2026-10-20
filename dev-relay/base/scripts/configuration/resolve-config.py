#!/usr/bin/env python3
"""Materialize, verify, and read the canonical runtime configuration snapshot."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import os
import posixpath
import re
import sys
import tempfile
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:
    print(
        json.dumps(
            {
                "mode": "startup",
                "status": "blocked",
                "snapshot_path": ".github/cache/config/resolved-config.json",
                "failures": ["PyYAML is required; install .github/scripts/requirements.txt"],
            },
            sort_keys=True,
        )
    )
    raise SystemExit(2)


SCHEMA_VERSION = 1
DEFAULT_PATH = Path(".github/config/default-config.yaml")
TEAM_PATH = Path(".github/config/team-config.yaml")
GUARDRAILS_PATH = Path(".github/config/guardrails.yaml")
AGENT_COMMANDS_PATH = Path(".github/config/agent-commands.yaml")
SNAPSHOT_PATH = Path(".github/cache/config/resolved-config.json")
RECOVERY_PATH = Path(".github/cache/config/resolved-config.prior.json")
SOURCE_PATHS = (DEFAULT_PATH, TEAM_PATH)
PROTECTED_CONFIG_PATHS = (DEFAULT_PATH, GUARDRAILS_PATH)
PROTECTED_CONFIG_BASELINE_PATH = Path(".github/cache/config/protected-config-baseline.json")
PROTECTED_KEYS = frozenset({"governance", "pipeline", "config_resolution"})
MCP_SERVER_REQUIRED_FIELDS = {
    "name": str,
    "prefix": str,
    "test_call": str,
    "required": bool,
    "description": str,
}
SETUP_TIMEOUT_KEYS = (
    "mcp_initialize_seconds",
    "mcp_method_seconds",
    "mcp_server_seconds",
    "sage_command_seconds",
    "external_phase_seconds",
)
ARCHITECTURE_PATHS = (
    ("metadata_file",),
    ("drift_scan", "baseline_manifest"),
)
ARCHITECTURE_REFRESH_POLICIES = frozenset(
    {"architecture-significant-change", "any-change", "manual"}
)
COMMAND_KEYS = frozenset(
    {"build", "test", "integration_test", "lint", "coverage", "run"}
)
STORY_CRITERIA_WEIGHTS = frozenset({"high", "medium", "low"})
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
UTC_TIMESTAMP_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
SETUP_REPORT_PATH = Path(".github/cache/sessions/setup-validation.md")
MAX_CONFIG_DEPTH = 64


class ResolutionError(ValueError):
    """Raised when source configuration violates the resolution contract."""


@contextmanager
def materialization_lock(workspace: Path):
    """Hold a non-blocking, process-safe lock for one workspace publication."""
    lock_path = workspace / SNAPSHOT_PATH.parent / ".resolve-config.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    lock_file = lock_path.open("a+b")
    acquired = False
    try:
        if lock_path.stat().st_size == 0:
            lock_file.write(b"\0")
            lock_file.flush()
        lock_file.seek(0)
        try:
            if os.name == "nt":
                import msvcrt

                msvcrt.locking(lock_file.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl

                fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            raise ResolutionError(
                "configuration materialization is already in progress"
            ) from error
        acquired = True
        yield
    finally:
        if acquired:
            lock_file.seek(0)
            if os.name == "nt":
                import msvcrt

                msvcrt.locking(lock_file.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                import fcntl

                fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        lock_file.close()


class UniqueKeySafeLoader(yaml.SafeLoader):
    """Safe YAML loader that rejects duplicate mapping keys."""

    def construct_mapping(self, node: yaml.nodes.MappingNode, deep: bool = False) -> dict[Any, Any]:
        """Construct one mapping after proving every key is unique."""
        keys: set[Any] = set()
        for key_node, _ in node.value:
            key = self.construct_object(key_node, deep=deep)
            try:
                duplicate = key in keys
            except TypeError as error:
                raise yaml.constructor.ConstructorError(
                    "while constructing a mapping",
                    node.start_mark,
                    "found an unhashable mapping key",
                    key_node.start_mark,
                ) from error
            if duplicate:
                raise yaml.constructor.ConstructorError(
                    "while constructing a mapping",
                    node.start_mark,
                    f"found duplicate key: {key!r}",
                    key_node.start_mark,
                )
            keys.add(key)
        return super().construct_mapping(node, deep=deep)


def sha256_bytes(content: bytes) -> str:
    """Compute the lowercase SHA-256 digest of byte content.

    Args:
        content: Bytes to hash.

    Returns:
        The hexadecimal SHA-256 digest.
    """
    return hashlib.sha256(content).hexdigest()


def verify_protected_config_baseline(workspace: Path) -> list[str]:
    """Check protected config files against the installer-recorded baseline.

    ``default-config.yaml`` and ``guardrails.yaml`` are install-protected: the
    installer establishes their SHA-256 baseline at install time in the
    base tier, and no overlay tier may override them. This catches a change to
    either file's bytes *after* installation - accidental or intentional -
    before any pipeline stage trusts them.

    An unestablished baseline (a workspace installed before this check
    existed) is not itself a failure; it degrades gracefully rather than
    blocking every pre-existing install. A baseline that exists but cannot be
    read, or a byte mismatch against a protected file, is always a failure.

    Returns:
        Failure descriptions, one per problem found; empty when verified or
        when no baseline has been established yet.
    """
    baseline_path = workspace / PROTECTED_CONFIG_BASELINE_PATH
    if not baseline_path.is_file():
        return []
    try:
        baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        return [f"protected-config baseline could not be read: {error}"]
    files = baseline.get("files") if isinstance(baseline, dict) else None
    if not isinstance(files, dict):
        return ["protected-config baseline is malformed: missing files object"]

    failures: list[str] = []
    for relative_path in PROTECTED_CONFIG_PATHS:
        name = relative_path.name
        expected = files.get(name)
        if not isinstance(expected, str) or not SHA256_PATTERN.fullmatch(expected):
            failures.append(f"protected-config baseline is missing a valid hash for {name}")
            continue
        target = workspace / relative_path
        try:
            actual = sha256_bytes(target.read_bytes())
        except FileNotFoundError:
            failures.append(f"protected config file is missing: {name}")
            continue
        except OSError as error:
            failures.append(f"cannot read protected config file {name}: {error}")
            continue
        if actual != expected:
            failures.append(
                f"protected config file has changed since installation: {name} "
                f"(expected {expected}, found {actual})"
            )
    return failures


def read_source_bundle(workspace: Path) -> dict[Path, bytes | None]:
    """Read each canonical source once for consistent resolution and hashing."""
    source_bundle: dict[Path, bytes | None] = {}
    for relative_path in SOURCE_PATHS:
        absolute_path = workspace / relative_path
        try:
            source_bundle[relative_path] = absolute_path.read_bytes()
        except FileNotFoundError:
            source_bundle[relative_path] = None
        except OSError as error:
            raise ResolutionError(f"cannot read {relative_path}: {error}") from error
    return source_bundle


def append_fingerprint_entry(
    combined: bytearray, normalized_path: str, content: bytes | None
) -> None:
    """Append one unambiguous path, presence, and content fingerprint entry."""
    path_bytes = normalized_path.encode("utf-8")
    content_bytes = content if content is not None else b""
    combined.extend(len(path_bytes).to_bytes(8, "big"))
    combined.extend(path_bytes)
    combined.append(1 if content is not None else 0)
    combined.extend(len(content_bytes).to_bytes(8, "big"))
    combined.extend(content_bytes)


def source_metadata_from_bundle(
    source_bundle: dict[Path, bytes | None],
) -> tuple[list[dict[str, Any]], str]:
    """Describe the canonical configuration sources and fingerprint their state.

    Missing optional sources contribute a stable marker to the combined
    fingerprint so their creation or removal invalidates an existing snapshot.

    Args:
        source_bundle: Canonical source paths mapped to bytes or absence.

    Returns:
        A tuple containing ordered source records and their combined SHA-256
        fingerprint.
    """
    records: list[dict[str, Any]] = []
    combined = bytearray()
    for relative_path in SOURCE_PATHS:
        normalized_path = relative_path.as_posix()
        source_content = source_bundle[relative_path]
        present = source_content is not None
        append_fingerprint_entry(combined, normalized_path, source_content)
        records.append(
            {
                "path": normalized_path,
                "present": present,
                "sha256": sha256_bytes(source_content) if source_content is not None else None,
            }
        )
    return records, sha256_bytes(bytes(combined))


def source_metadata(workspace: Path) -> tuple[list[dict[str, Any]], str]:
    """Read and fingerprint the canonical configuration sources."""
    return source_metadata_from_bundle(read_source_bundle(workspace))


def load_mapping(content: bytes | None, path: Path, *, required: bool) -> dict[str, Any] | None:
    """Load a UTF-8 YAML document whose root is a mapping.

    Args:
        content: Immutable YAML source bytes, or absence.
        path: Source path used in diagnostics.
        required: Whether a missing file violates the resolution contract.

    Returns:
        The loaded mapping, or ``None`` when an optional source is absent.

    Raises:
        ResolutionError: If a required source is missing, the source cannot be
            parsed, or its root is not a mapping.
    """
    if content is None:
        if required:
            raise ResolutionError(f"required configuration source is missing: {path}")
        return None
    try:
        loaded = yaml.load(content.decode("utf-8"), Loader=UniqueKeySafeLoader)
    except (UnicodeError, yaml.YAMLError) as error:
        raise ResolutionError(f"cannot parse {path}: {error}") from error
    if not isinstance(loaded, dict):
        raise ResolutionError(f"configuration root must be a mapping: {path}")
    validate_json_domain(loaded)
    return loaded


def validate_json_domain(
    value: Any,
    path: tuple[str, ...] = (),
    active_containers: set[int] | None = None,
    depth: int = 0,
) -> None:
    """Require an acyclic, bounded structure representable by standard JSON."""
    if depth > MAX_CONFIG_DEPTH:
        raise ResolutionError(
            f"configuration nesting exceeds {MAX_CONFIG_DEPTH} at {format_path(path)}"
        )
    if isinstance(value, float) and not math.isfinite(value):
        raise ResolutionError(f"configuration number must be finite at {format_path(path)}")
    if value is None or isinstance(value, (str, bool, int, float)):
        return
    if not isinstance(value, (dict, list)):
        raise ResolutionError(
            f"configuration value must be JSON-compatible at {format_path(path)}"
        )

    active = active_containers if active_containers is not None else set()
    identity = id(value)
    if identity in active:
        raise ResolutionError(f"configuration aliases must not form a cycle at {format_path(path)}")
    active.add(identity)
    try:
        if isinstance(value, dict):
            for key, child in value.items():
                if not isinstance(key, str):
                    raise ResolutionError(
                        f"configuration key must be a string at {format_path(path)}"
                    )
                validate_json_domain(child, path + (key,), active, depth + 1)
        else:
            for index, child in enumerate(value):
                validate_json_domain(child, path + (str(index),), active, depth + 1)
    finally:
        active.remove(identity)


def json_values_equal(left: Any, right: Any) -> bool:
    """Compare JSON-domain values without Python's bool/int coercion."""
    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(
            json_values_equal(left[key], right[key]) for key in left
        )
    if isinstance(left, list):
        return len(left) == len(right) and all(
            json_values_equal(left_item, right_item)
            for left_item, right_item in zip(left, right)
        )
    return left == right


def value_kind(value: Any) -> str:
    """Return the configuration type name used in merge diagnostics.

    Args:
        value: Configuration value to classify.

    Returns:
        A stable YAML-oriented kind name, or the Python type name for an
        unsupported value.
    """
    if isinstance(value, dict):
        return "mapping"
    if isinstance(value, list):
        return "sequence"
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, (int, float)):
        return "number"
    if isinstance(value, str):
        return "string"
    return type(value).__name__


def validate_team_delta(value: Any, path: tuple[str, ...] = ()) -> None:
    """Validate that a team delta stays within its permitted override surface.

    Args:
        value: Team configuration value to validate recursively.
        path: Current configuration path, used for recursive diagnostics.

    Raises:
        ResolutionError: If a key is not a string, a protected key is
            overridden, or an MCP server is added outside the ``additional``
            collection.
    """
    if isinstance(value, dict):
        for key, child in value.items():
            if not isinstance(key, str):
                raise ResolutionError(f"configuration key must be a string at {format_path(path)}")
            child_path = path + (key,)
            if key in PROTECTED_KEYS:
                raise ResolutionError(f"team configuration cannot override {format_path(child_path)}")
            if child_path == ("setup_validation", "timeouts"):
                raise ResolutionError(
                    "team configuration cannot override setup_validation.timeouts"
                )
            if path == ("mcp_servers",) and key != "additional":
                raise ResolutionError(
                    "team MCP servers may be added only through mcp_servers.additional"
                )
            validate_team_delta(child, child_path)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            validate_team_delta(child, path + (str(index),))


def validate_mcp_server_record(
    server: Any, item_path: str, name: Any
) -> None:
    """Validate one MCP server record consumed by Setup Validator and its report."""
    if not isinstance(server, dict):
        raise ResolutionError(f"{item_path} must be a mapping")
    if not isinstance(name, str) or not name.strip():
        raise ResolutionError(f"{item_path}.name must be a non-empty string")
    if name != name.strip() or any(character in name for character in "=\r\n"):
        raise ResolutionError(
            f"{item_path}.name must not have surrounding whitespace or contain '=', carriage returns, or newlines"
        )
    for field, expected_type in MCP_SERVER_REQUIRED_FIELDS.items():
        if field == "name":
            continue
        value = server.get(field)
        if expected_type is bool:
            if not isinstance(value, bool):
                raise ResolutionError(f"{item_path}.{field} must be a boolean")
        elif not isinstance(value, expected_type) or not value.strip():
            raise ResolutionError(f"{item_path}.{field} must be a non-empty string")


def validate_mcp_servers(baseline: dict[str, Any], team: dict[str, Any] | None) -> None:
    """Validate baseline and additive MCP records before publication."""
    baseline_servers = baseline.get("mcp_servers", {})
    if not isinstance(baseline_servers, dict):
        raise ResolutionError("mcp_servers must be a mapping")
    known_names: set[str] = set()
    for name, server in baseline_servers.items():
        item_path = f"mcp_servers.{name}"
        validate_mcp_server_record(server, item_path, name)
        if name in known_names:
            raise ResolutionError(f"duplicate MCP server name: {name}")
        known_names.add(name)

    if team is None:
        return
    team_servers = team.get("mcp_servers")
    if not isinstance(team_servers, dict) or "additional" not in team_servers:
        return

    additions = team_servers["additional"]
    if not isinstance(additions, list):
        raise ResolutionError("mcp_servers.additional must be a sequence")

    for index, server in enumerate(additions):
        item_path = f"mcp_servers.additional.{index}"
        name = server.get("name") if isinstance(server, dict) else None
        validate_mcp_server_record(server, item_path, name)
        assert isinstance(name, str)
        if name in known_names:
            raise ResolutionError(f"duplicate MCP server name: {name}")
        known_names.add(name)


def validate_architecture_config(config: dict[str, Any]) -> None:
    """Validate architecture controls consumed from the runtime snapshot."""
    architecture = config.get("architecture")
    if architecture is None:
        return
    if not isinstance(architecture, dict):
        raise ResolutionError("architecture must be a mapping")
    if not isinstance(architecture.get("auto_context"), bool):
        raise ResolutionError("architecture.auto_context must be a boolean")
    refresh_on = architecture.get("refresh_on")
    if refresh_on not in ARCHITECTURE_REFRESH_POLICIES:
        allowed = ", ".join(sorted(ARCHITECTURE_REFRESH_POLICIES))
        raise ResolutionError(f"architecture.refresh_on must be one of: {allowed}")
    for path in ARCHITECTURE_PATHS:
        value: Any = architecture
        for segment in path:
            value = value.get(segment) if isinstance(value, dict) else None
        dotted = "architecture." + ".".join(path)
        if not isinstance(value, str) or not value.strip():
            raise ResolutionError(f"{dotted} must be a non-empty string")
        normalized = value.replace("\\", "/")
        pure_path = Path(normalized)
        if (
            pure_path.is_absolute()
            or not normalized.startswith(".github/")
            or ".." in pure_path.parts
            or pure_path.suffix.lower() != ".json"
        ):
            raise ResolutionError(
                f"{dotted} must be a workspace-relative .github/*.json path"
            )
    metadata_path = posixpath.normpath(
        architecture["metadata_file"].replace("\\", "/")
    ).casefold()
    baseline_path = posixpath.normpath(
        architecture["drift_scan"]["baseline_manifest"].replace("\\", "/")
    ).casefold()
    if metadata_path == baseline_path:
        raise ResolutionError(
            "architecture.metadata_file and architecture.drift_scan.baseline_manifest "
            "must be distinct paths"
        )
    drift_scan = architecture.get("drift_scan")
    if not isinstance(drift_scan, dict):
        raise ResolutionError("architecture.drift_scan must be a mapping")
    for key in ("enabled", "require_consent"):
        if not isinstance(drift_scan.get(key), bool):
            raise ResolutionError(f"architecture.drift_scan.{key} must be a boolean")
    for key in ("changed_files_threshold", "changed_repos_threshold"):
        value = drift_scan.get(key)
        if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
            raise ResolutionError(
                f"architecture.drift_scan.{key} must be a positive integer"
            )
    significant_paths = drift_scan.get("significant_paths")
    if not isinstance(significant_paths, list) or not significant_paths or not all(
        isinstance(path, str) and path.strip() for path in significant_paths
    ):
        raise ResolutionError(
            "architecture.drift_scan.significant_paths must be a non-empty sequence of strings"
        )


def require_string_list(value: Any, path: str, *, allow_empty: bool = True) -> None:
    """Require a unique sequence of non-empty strings."""
    if not isinstance(value, list) or (not allow_empty and not value):
        raise ResolutionError(f"{path} must be a sequence of non-empty strings")
    if not all(isinstance(item, str) and item.strip() for item in value):
        raise ResolutionError(f"{path} must be a sequence of non-empty strings")
    if len({item.casefold() for item in value}) != len(value):
        raise ResolutionError(f"{path} must not contain duplicates")


def validate_runtime_config(config: dict[str, Any]) -> None:
    """Validate every operational section before snapshot publication."""
    resolution = config.get("config_resolution")
    if not isinstance(resolution, dict):
        raise ResolutionError("config_resolution must be a mapping")
    if resolution.get("schema_version") != SCHEMA_VERSION:
        raise ResolutionError(f"config_resolution.schema_version must be {SCHEMA_VERSION}")
    if resolution.get("resolved_file") != SNAPSHOT_PATH.as_posix():
        raise ResolutionError(
            f"config_resolution.resolved_file must be {SNAPSHOT_PATH.as_posix()}"
        )

    commands = config.get("commands")
    if not isinstance(commands, dict) or not isinstance(commands.get("resolution"), str) or not commands["resolution"].strip():
        raise ResolutionError("commands.resolution must be a non-empty string")

    setup_validation_values(config)

    extensions = config.get("required_extensions")
    if not isinstance(extensions, dict) or set(extensions) != {"always", "recommended"}:
        raise ResolutionError("required_extensions must define exactly always and recommended")
    require_string_list(extensions["always"], "required_extensions.always")
    require_string_list(extensions["recommended"], "required_extensions.recommended")

    prerequisites = config.get("ide_prerequisites")
    ai_coauthor = prerequisites.get("ai_coauthor") if isinstance(prerequisites, dict) else None
    if not isinstance(ai_coauthor, dict):
        raise ResolutionError("ide_prerequisites.ai_coauthor must be a mapping")
    if not isinstance(ai_coauthor.get("required"), bool):
        raise ResolutionError("ide_prerequisites.ai_coauthor.required must be a boolean")
    if ai_coauthor.get("required_mode") not in {"all"}:
        raise ResolutionError("ide_prerequisites.ai_coauthor.required_mode must be all")
    vscode = ai_coauthor.get("vscode")
    intellij = ai_coauthor.get("intellij")
    if not isinstance(vscode, dict) or not all(
        isinstance(vscode.get(key), str) and vscode[key].strip()
        for key in ("setting_key", "required_value", "repository_enforcement_file")
    ):
        raise ResolutionError("ide_prerequisites.ai_coauthor.vscode is malformed")
    require_string_list(vscode.get("accepted_values"), "ide_prerequisites.ai_coauthor.vscode.accepted_values", allow_empty=False)
    if vscode["required_value"] not in vscode["accepted_values"]:
        raise ResolutionError("ide_prerequisites.ai_coauthor.vscode.required_value must be accepted")
    if not isinstance(intellij, dict) or not isinstance(intellij.get("plugin_name"), str) or not intellij["plugin_name"].strip():
        raise ResolutionError("ide_prerequisites.ai_coauthor.intellij is malformed")
    require_string_list(intellij.get("accepted_enforcement_modes"), "ide_prerequisites.ai_coauthor.intellij.accepted_enforcement_modes", allow_empty=False)
    require_string_list(intellij.get("repository_fallback_files"), "ide_prerequisites.ai_coauthor.intellij.repository_fallback_files", allow_empty=False)

    styles = config.get("language_style_defaults")
    if not isinstance(styles, dict) or not isinstance(styles.get("coding"), dict) or not isinstance(styles.get("terraform"), dict):
        raise ResolutionError("language_style_defaults must define coding and terraform mappings")

    documentation = config.get("documentation")
    if not isinstance(documentation, dict):
        raise ResolutionError("documentation must be a mapping")
    require_string_list(documentation.get("architecture"), "documentation.architecture")

    refinement = config.get("story_refinement")
    if not isinstance(refinement, dict):
        raise ResolutionError("story_refinement must be a mapping")
    require_string_list(refinement.get("required_fields"), "story_refinement.required_fields", allow_empty=False)
    criteria = refinement.get("scored_criteria")
    if not isinstance(criteria, list) or not criteria:
        raise ResolutionError("story_refinement.scored_criteria must be a non-empty sequence")
    for index, criterion in enumerate(criteria):
        path = f"story_refinement.scored_criteria.{index}"
        if not isinstance(criterion, dict):
            raise ResolutionError(f"{path} must be a mapping")
        if criterion.get("weight") not in STORY_CRITERIA_WEIGHTS:
            raise ResolutionError(f"{path}.weight must be high, medium, or low")
        for key in ("name", "check"):
            if not isinstance(criterion.get(key), str) or not criterion[key].strip():
                raise ResolutionError(f"{path}.{key} must be a non-empty string")
        if "fail_words" in criterion:
            require_string_list(criterion["fail_words"], f"{path}.fail_words")
    threshold = refinement.get("pass_threshold")
    if not isinstance(threshold, (int, float)) or isinstance(threshold, bool) or not 0 <= threshold <= 1:
        raise ResolutionError("story_refinement.pass_threshold must be between 0 and 1")

    validate_architecture_config(config)


def validate_command_manifest(content: bytes | None) -> str:
    """Validate the optional command manifest and return its presence-aware hash."""
    combined = bytearray()
    append_fingerprint_entry(combined, AGENT_COMMANDS_PATH.as_posix(), content)
    if content is None:
        return sha256_bytes(bytes(combined))
    manifest = load_mapping(content, AGENT_COMMANDS_PATH, required=True)
    assert manifest is not None
    if set(manifest) != {"commands"} or not isinstance(manifest["commands"], dict):
        raise ResolutionError("agent-commands.yaml must contain only a commands mapping")
    commands = manifest["commands"]
    unknown = set(commands) - COMMAND_KEYS
    missing = COMMAND_KEYS - set(commands)
    if unknown or missing:
        raise ResolutionError(
            "agent-commands.yaml commands must define exactly: " + ", ".join(sorted(COMMAND_KEYS))
        )
    for key, value in commands.items():
        if not isinstance(value, str):
            raise ResolutionError(f"agent-commands.yaml commands.{key} must be a string")
        if "\r" in value or "\n" in value:
            raise ResolutionError(f"agent-commands.yaml commands.{key} must be a single-line string")
    if commands["test"].casefold() == "skip":
        raise ResolutionError("agent-commands.yaml commands.test cannot be skip")
    return sha256_bytes(bytes(combined))


def format_path(path: tuple[str, ...]) -> str:
    """Format a configuration path for a human-readable diagnostic.

    Args:
        path: Configuration path segments.

    Returns:
        A dotted path, or ``<root>`` when no segments are present.
    """
    return ".".join(path) if path else "<root>"


def merge_values(base: Any, team: Any, path: tuple[str, ...] = ()) -> Any:
    """Deep-merge a validated team value over a baseline value.

    Mappings merge recursively. All other compatible values, including
    sequences, are replaced as complete values. Returned values are deep copies
    so neither input is mutated.

    Args:
        base: Baseline configuration value.
        team: Team value to merge over the baseline.
        path: Current configuration path, used for recursive diagnostics.

    Returns:
        The merged, independently owned configuration value.

    Raises:
        ResolutionError: If the team value erases a non-null baseline value or
            changes the value kind at an existing path.
    """
    if team is None and base is not None:
        raise ResolutionError(f"team configuration cannot erase {format_path(path)} with null")

    base_kind = value_kind(base)
    team_kind = value_kind(team)
    if base_kind != team_kind:
        raise ResolutionError(
            f"type conflict at {format_path(path)}: baseline is {base_kind}, team is {team_kind}"
        )

    if isinstance(base, dict):
        merged = copy.deepcopy(base)
        for key, team_value in team.items():
            child_path = path + (key,)
            if key in merged:
                merged[key] = merge_values(merged[key], team_value, child_path)
            else:
                merged[key] = copy.deepcopy(team_value)
        return merged
    return copy.deepcopy(team)


def resolve_source_bundle(source_bundle: dict[Path, bytes | None]) -> dict[str, Any]:
    """Load, validate, and merge the workspace configuration sources.

    Args:
        source_bundle: Canonical source paths mapped to bytes or absence.

    Returns:
        The baseline configuration with an allowed team delta merged over it.

    Raises:
        ResolutionError: If a source is invalid, a team override is forbidden,
            or the team lowers the story-refinement threshold.
    """
    baseline = load_mapping(source_bundle[DEFAULT_PATH], DEFAULT_PATH, required=True)
    team = load_mapping(source_bundle[TEAM_PATH], TEAM_PATH, required=False)
    assert baseline is not None
    validate_mcp_servers(baseline, team)
    if team is None:
        validate_runtime_config(baseline)
        return baseline

    validate_team_delta(team)
    baseline_story_refinement = baseline.get("story_refinement", {})
    team_story_refinement = team.get("story_refinement", {})
    baseline_threshold = (
        baseline_story_refinement.get("pass_threshold")
        if isinstance(baseline_story_refinement, dict)
        else None
    )
    team_threshold = (
        team_story_refinement.get("pass_threshold")
        if isinstance(team_story_refinement, dict)
        else None
    )
    if team_threshold is not None:
        if not isinstance(baseline_threshold, (int, float)) or isinstance(baseline_threshold, bool):
            raise ResolutionError("baseline story_refinement.pass_threshold must be numeric")
        if not isinstance(team_threshold, (int, float)) or isinstance(team_threshold, bool):
            raise ResolutionError("team story_refinement.pass_threshold must be numeric")
        if team_threshold < baseline_threshold:
            raise ResolutionError("team story_refinement.pass_threshold cannot be lowered")
    resolved = merge_values(baseline, team)
    validate_runtime_config(resolved)
    return resolved


def resolve_sources(workspace: Path) -> dict[str, Any]:
    """Read, validate, and merge the workspace configuration sources."""
    return resolve_source_bundle(read_source_bundle(workspace))


def result(mode: str, status: str, workspace: Path, **fields: Any) -> dict[str, Any]:
    """Build the stable JSON response envelope for a resolver operation.

    Args:
        mode: Resolver operation that produced the response.
        status: Outcome status for the operation.
        workspace: Workspace associated with the operation. This parameter is
            retained for a consistent result-construction interface.
        **fields: Operation-specific fields to add to the response.

    Returns:
        A JSON-serializable response mapping.
    """
    payload = {
        "mode": mode,
        "status": status,
        "snapshot_path": SNAPSHOT_PATH.as_posix(),
    }
    payload.update(fields)
    return payload


def _load_verified_snapshot(
    workspace: Path, mode: str = "verify"
) -> tuple[dict[str, Any], dict[str, Any] | None]:
    """Load and verify one snapshot image against one current source bundle.

    Args:
        workspace: Workspace root containing the snapshot and source files.
        mode: Operation name to include in the response envelope.

    Returns:
        A resolver response and the exact parsed snapshot it verified. The
        snapshot is returned only when the response is ``current``.
    """
    snapshot_path = workspace / SNAPSHOT_PATH
    if not snapshot_path.is_file():
        return (
            result(mode, "missing", workspace, failures=["resolved snapshot does not exist"]),
            None,
        )
    try:
        snapshot = json.loads(snapshot_path.read_text(encoding="utf-8"))
    except OSError as error:
        return (
            result(mode, "blocked", workspace, failures=[f"cannot read snapshot: {error}"]),
            None,
        )
    except (UnicodeError, json.JSONDecodeError) as error:
        return (
            result(mode, "malformed", workspace, failures=[f"cannot parse snapshot: {error}"]),
            None,
        )

    failures: list[str] = []
    if not isinstance(snapshot, dict):
        failures.append("snapshot root must be an object")
    else:
        if snapshot.get("schema_version") != SCHEMA_VERSION:
            failures.append(f"schema_version must be {SCHEMA_VERSION}")
        generated_at = snapshot.get("generated_at")
        if not isinstance(generated_at, str) or not UTC_TIMESTAMP_PATTERN.fullmatch(generated_at):
            failures.append("generated_at must be a UTC ISO-8601 timestamp")
        if not isinstance(snapshot.get("config"), dict):
            failures.append("config must be an object")
        fingerprint = snapshot.get("source_fingerprint")
        if not isinstance(fingerprint, str) or not SHA256_PATTERN.fullmatch(fingerprint):
            failures.append("source_fingerprint must be lowercase SHA-256")

        source_bundle = read_source_bundle(workspace)
        current_sources, current_fingerprint = source_metadata_from_bundle(source_bundle)
        snapshot_sources = snapshot.get("sources")
        if not valid_source_records(snapshot_sources):
            failures.append("sources must contain both ordered canonical source records")
        elif snapshot_sources != current_sources:
            failures.append("source records do not match current configuration files")
        if fingerprint != current_fingerprint:
            failures.append("source fingerprint does not match current configuration files")
        try:
            current_config = resolve_source_bundle(source_bundle)
        except ResolutionError as error:
            failures.append(f"current configuration sources are invalid: {error}")
        else:
            if not json_values_equal(snapshot.get("config"), current_config):
                failures.append("config does not match current resolved configuration")

    if failures:
        source_drift = any(
            failure in {
                "source records do not match current configuration files",
                "source fingerprint does not match current configuration files",
            }
            or failure.startswith("current configuration sources are invalid:")
            for failure in failures
        )
        structural = any(
            failure.startswith(
                ("snapshot", "schema_version", "generated_at", "source_fingerprint", "sources")
            )
            for failure in failures
        ) or "config must be an object" in failures or (
            "config does not match current resolved configuration" in failures
            and not source_drift
        )
        status = "malformed" if structural else "stale"
        return result(mode, status, workspace, failures=failures), None
    return (
        result(
            mode,
            "current",
            workspace,
            source_fingerprint=snapshot["source_fingerprint"],
        ),
        snapshot,
    )


def _verify_snapshot(workspace: Path, mode: str = "verify") -> dict[str, Any]:
    """Verify a snapshot's structure and correspondence with current sources."""
    verified, _ = _load_verified_snapshot(workspace, mode)
    return verified


def verify_snapshot(workspace: Path, mode: str = "verify") -> dict[str, Any]:
    """Verify a snapshot without allowing operation failures to escape."""
    try:
        return _verify_snapshot(workspace, mode)
    except (OSError, UnicodeError, ResolutionError, KeyError, TypeError) as error:
        return result(mode, "blocked", workspace, failures=[f"cannot verify snapshot: {error}"])


def valid_source_records(records: Any) -> bool:
    """Check whether snapshot source records match the canonical schema.

    Args:
        records: Candidate source-record collection.

    Returns:
        ``True`` when records are complete, ordered, and structurally valid;
        otherwise ``False``.
    """
    if not isinstance(records, list) or len(records) != len(SOURCE_PATHS):
        return False
    for record, expected_path in zip(records, SOURCE_PATHS):
        if not isinstance(record, dict):
            return False
        if set(record) != {"path", "present", "sha256"}:
            return False
        if record["path"] != expected_path.as_posix() or not isinstance(record["present"], bool):
            return False
        digest = record["sha256"]
        if record["present"]:
            if not isinstance(digest, str) or not SHA256_PATTERN.fullmatch(digest):
                return False
        elif digest is not None:
            return False
    return True


def setup_validation_values(config: dict[str, Any]) -> tuple[float, list[str]]:
    """Validate and return the setup-cache TTL and fingerprint inputs."""
    setup_validation = config.get("setup_validation")
    if not isinstance(setup_validation, dict):
        raise ResolutionError("setup_validation must be a mapping")
    ttl_hours = setup_validation.get("cache_ttl_hours")
    timeouts = setup_validation.get("timeouts")
    fingerprint_inputs = setup_validation.get("fingerprint_inputs")
    if (
        not isinstance(ttl_hours, (int, float))
        or isinstance(ttl_hours, bool)
        or ttl_hours <= 0
    ):
        raise ResolutionError("setup_validation.cache_ttl_hours must be a positive number")
    if not isinstance(timeouts, dict) or set(timeouts) != set(SETUP_TIMEOUT_KEYS):
        raise ResolutionError(
            "setup_validation.timeouts must define exactly: "
            + ", ".join(SETUP_TIMEOUT_KEYS)
        )
    for key in SETUP_TIMEOUT_KEYS:
        value = timeouts[key]
        if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
            raise ResolutionError(
                f"setup_validation.timeouts.{key} must be a positive integer"
            )
    if max(
        timeouts["mcp_initialize_seconds"],
        timeouts["mcp_method_seconds"],
    ) > timeouts["mcp_server_seconds"]:
        raise ResolutionError(
            "setup_validation.timeouts.mcp_server_seconds must be at least each MCP operation timeout"
        )
    if max(
        timeouts["mcp_server_seconds"],
        timeouts["sage_command_seconds"],
    ) > timeouts["external_phase_seconds"]:
        raise ResolutionError(
            "setup_validation.timeouts.external_phase_seconds must be at least each family timeout"
        )
    if not isinstance(fingerprint_inputs, list) or not fingerprint_inputs or not all(
        isinstance(path, str) and path and path == path.strip()
        for path in fingerprint_inputs
    ):
        raise ResolutionError(
            "setup_validation.fingerprint_inputs must be a non-empty sequence of unique non-empty paths"
        )
    normalized_inputs: list[str] = []
    normalized_identities: set[str] = set()
    for configured_path in fingerprint_inputs:
        relative_path = Path(configured_path)
        if relative_path.is_absolute() or ".." in relative_path.parts:
            raise ResolutionError(
                f"setup validation input must be workspace-relative: {configured_path}"
            )
        normalized_path = relative_path.as_posix()
        identity = normalized_path.casefold()
        if identity in normalized_identities:
            raise ResolutionError(
                "setup_validation.fingerprint_inputs must be a non-empty sequence of unique non-empty paths"
            )
        normalized_identities.add(identity)
        normalized_inputs.append(normalized_path)
    return ttl_hours, normalized_inputs


def _materialize_locked(workspace: Path) -> dict[str, Any]:
    """Resolve configuration and atomically publish a verified snapshot.

    A temporary file is flushed, read back, and replaced into the canonical
    location only after source resolution and serialization succeed. An existing
    valid snapshot therefore remains intact when publication is blocked.

    Args:
        workspace: Workspace root containing the source configuration.

    Returns:
        A resolver response with ``current`` status and the source fingerprint
        on success, or ``blocked`` status with failure details.
    """
    protected_config_failures = verify_protected_config_baseline(workspace)
    if protected_config_failures:
        return result("materialize", "blocked", workspace, failures=protected_config_failures)
    try:
        source_bundle = read_source_bundle(workspace)
        resolved = resolve_source_bundle(source_bundle)
        sources, fingerprint = source_metadata_from_bundle(source_bundle)
        try:
            command_content = (workspace / AGENT_COMMANDS_PATH).read_bytes()
        except FileNotFoundError:
            command_content = None
        command_manifest_fingerprint = validate_command_manifest(command_content)
        _, fingerprint_inputs = setup_validation_values(resolved)
        setup_fingerprint = setup_input_fingerprint(workspace, fingerprint_inputs)
    except (OSError, ResolutionError, TypeError) as error:
        return result("materialize", "blocked", workspace, failures=[str(error)])

    snapshot = {
        "schema_version": SCHEMA_VERSION,
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        "source_fingerprint": fingerprint,
        "sources": sources,
        "config": resolved,
    }
    target = workspace / SNAPSHOT_PATH
    recovery_path = workspace / RECOVERY_PATH
    temporary_path: Path | None = None
    publication_error: Exception | None = None
    recovery_created = False
    candidate_published = False
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        if recovery_path.exists():
            raise ResolutionError(
                "prior snapshot recovery is pending at "
                f"{RECOVERY_PATH.as_posix()}; restore or remove it before retry"
            )
        previous_snapshot = target.read_bytes() if target.is_file() else None
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            newline="\n",
            dir=target.parent,
            prefix=f".{target.name}.",
            suffix=".tmp",
            delete=False,
        ) as temporary:
            temporary_path = Path(temporary.name)
            json.dump(
                snapshot,
                temporary,
                indent=2,
                sort_keys=True,
                ensure_ascii=True,
                allow_nan=False,
            )
            temporary.write("\n")
            temporary.flush()
            os.fsync(temporary.fileno())

        staged = json.loads(temporary_path.read_text(encoding="utf-8"))
        if not json_values_equal(staged, snapshot):
            raise ResolutionError("staged snapshot failed read-back verification")
        if read_source_bundle(workspace) != source_bundle:
            raise ResolutionError("configuration sources changed during materialization; retry")
        if previous_snapshot is not None:
            write_recovery_snapshot(recovery_path, previous_snapshot)
            recovery_created = True
        os.replace(temporary_path, target)
        temporary_path = None
        candidate_published = True
        if read_source_bundle(workspace) != source_bundle:
            if recovery_created:
                os.replace(recovery_path, target)
                recovery_created = False
            else:
                target.unlink(missing_ok=True)
            candidate_published = False
            raise ResolutionError(
                "configuration sources changed after publication; prior snapshot restored"
            )
        if recovery_created:
            recovery_path.unlink()
            recovery_created = False
    except (OSError, UnicodeError, json.JSONDecodeError, ResolutionError, TypeError) as error:
        publication_error = error

    if temporary_path is not None:
        try:
            temporary_path.unlink(missing_ok=True)
        except OSError as error:
            if publication_error is None:
                publication_error = error
            else:
                publication_error = ResolutionError(
                    f"{publication_error}; temporary cleanup failed: {error}"
                )
    if recovery_created and not candidate_published:
        try:
            recovery_path.unlink(missing_ok=True)
            recovery_created = False
        except OSError as error:
            publication_error = ResolutionError(
                f"{publication_error}; recovery cleanup failed: {error}"
            )
    if publication_error is not None:
        return result(
            "materialize",
            "blocked",
            workspace,
            failures=[f"cannot publish snapshot: {publication_error}"],
        )

    return result(
        "materialize",
        "current",
        workspace,
        source_fingerprint=fingerprint,
        setup_input_fingerprint=setup_fingerprint,
        report_fingerprints={
            "Config-Fingerprint": setup_fingerprint,
            "Resolved-Config-Fingerprint": fingerprint,
        },
        command_manifest_fingerprint=command_manifest_fingerprint,
    )


def write_recovery_snapshot(recovery_path: Path, previous_snapshot: bytes) -> None:
    """Atomically preserve the prior canonical bytes for publication recovery."""
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb",
            dir=recovery_path.parent,
            prefix=f".{recovery_path.name}.",
            suffix=".tmp",
            delete=False,
        ) as temporary:
            temporary_path = Path(temporary.name)
            temporary.write(previous_snapshot)
            temporary.flush()
            os.fsync(temporary.fileno())
        os.replace(temporary_path, recovery_path)
        temporary_path = None
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def materialize(workspace: Path) -> dict[str, Any]:
    """Serialize and publish one verified workspace configuration generation."""
    try:
        with materialization_lock(workspace):
            return _materialize_locked(workspace)
    except (OSError, ResolutionError) as error:
        return result("materialize", "blocked", workspace, failures=[str(error)])


def _read_section(workspace: Path, section: str) -> dict[str, Any]:
    """Read a dotted section from a current resolved snapshot.

    Args:
        workspace: Workspace root containing the resolved snapshot.
        section: Dot-delimited path beneath the snapshot's ``config`` object.

    Returns:
        A ``current`` response containing the requested value, or the snapshot
        verification/blocking response when the section cannot be read.
    """
    verified, snapshot = _load_verified_snapshot(workspace, mode="read")
    if verified["status"] != "current":
        return verified
    assert snapshot is not None
    current: Any = snapshot["config"]
    for part in section.split("."):
        if not isinstance(current, dict) or part not in current:
            return result(
                "read",
                "blocked",
                workspace,
                source_fingerprint=verified["source_fingerprint"],
                failures=[f"requested configuration section is missing: {section}"],
            )
        current = current[part]
    return result(
        "read",
        "current",
        workspace,
        source_fingerprint=verified["source_fingerprint"],
        section=section,
        value=current,
    )


def read_section(workspace: Path, section: str) -> dict[str, Any]:
    """Read a named section without allowing snapshot races to escape."""
    try:
        return _read_section(workspace, section)
    except OSError as error:
        return result(
            "read",
            "blocked",
            workspace,
            failures=[f"cannot read snapshot: {error}"],
        )
    except (
        UnicodeError,
        json.JSONDecodeError,
        ResolutionError,
        KeyError,
        TypeError,
    ) as error:
        return result("read", "blocked", workspace, failures=[f"cannot read snapshot: {error}"])


def setup_input_fingerprint(workspace: Path, paths: list[str]) -> str:
    """Fingerprint ordered workspace-relative setup-validation inputs."""
    combined = bytearray()
    for configured_path in paths:
        relative_path = Path(configured_path)
        if relative_path.is_absolute() or ".." in relative_path.parts:
            raise ResolutionError(
                f"setup validation input must be workspace-relative: {configured_path}"
            )
        normalized_path = relative_path.as_posix()
        try:
            content = (workspace / relative_path).read_bytes()
        except FileNotFoundError:
            content = None
        append_fingerprint_entry(combined, normalized_path, content)
    return sha256_bytes(bytes(combined))


def verify_setup_cache(workspace: Path) -> dict[str, Any]:
    """Verify that the cached setup PASS is current for its configured inputs."""
    try:
        verified, snapshot = _load_verified_snapshot(workspace, mode="verify-setup-cache")
        if verified["status"] != "current":
            return verified
        assert snapshot is not None
        protected_config_failures = verify_protected_config_baseline(workspace)
        if protected_config_failures:
            return result(
                "verify-setup-cache",
                "stale",
                workspace,
                failures=protected_config_failures,
            )

        ttl_hours, fingerprint_inputs = setup_validation_values(snapshot["config"])

        report_path = workspace / SETUP_REPORT_PATH
        report = report_path.read_text(encoding="utf-8-sig")
        if re.search(r"(?m)^Result:\s+(?:✅\s+)?PASS(?:\s|$)", report) is None:
            raise ResolutionError("setup validation report does not contain the PASS marker")

        validated_match = re.search(r"(?m)^Validated-At:\s*(\S+)\s*$", report)
        fingerprint_match = re.search(
            r"(?m)^Config-Fingerprint:\s*([0-9a-f]{64})\s*$", report
        )
        if validated_match is None:
            raise ResolutionError("setup validation report is missing Validated-At")
        if fingerprint_match is None:
            raise ResolutionError("setup validation report is missing Config-Fingerprint")
        if UTC_TIMESTAMP_PATTERN.fullmatch(validated_match.group(1)) is None:
            raise ResolutionError("setup validation report has an invalid Validated-At")

        configured_servers: dict[str, bool] = {}
        mcp_servers = snapshot["config"]["mcp_servers"]
        for name, server in mcp_servers.items():
            if name != "additional":
                configured_servers[name] = server["required"]
        for server in mcp_servers.get("additional", []):
            configured_servers[server["name"]] = server["required"]

        probe_matches = re.findall(
            r"(?m)^MCP-Probe:\s*([^=\r\n]+?)=(PASS|FAILED)\s*$",
            report,
        )
        probe_results: dict[str, str] = {}
        for name, status in probe_matches:
            name = name.strip()
            if name in probe_results:
                raise ResolutionError(
                    f"setup validation report has duplicate MCP probe evidence: {name}"
                )
            probe_results[name] = status
        if set(probe_results) != set(configured_servers):
            raise ResolutionError(
                "setup validation report MCP probe evidence does not match configured servers"
            )
        failed_required = sorted(
            name
            for name, required in configured_servers.items()
            if required and probe_results[name] != "PASS"
        )
        if failed_required:
            raise ResolutionError(
                "setup validation report has failed required MCP probes: "
                + ", ".join(failed_required)
            )

        jira_probe = re.search(
            r"(?m)^Jira-Probe:\s*getJiraInstancesAndProjectsForCurrentUser=PASS "
            r"\(readable project visible\)\s*$",
            report,
        )
        if jira_probe is None:
            raise ResolutionError(
                "setup validation report is missing successful Jira project-discovery evidence"
            )

        gt_assist_probe = re.search(
            r"(?m)^GT-Assist-Probe:\s*"
            r"ListUsecases=(PASS|FAILED);\s*"
            r"Global Technology=(FOUND|ABSENT|UNKNOWN);\s*"
            r"AskGTAssist=(PASS|FAILED|NOT_RUN)\s*$",
            report,
        )
        valid_gt_assist_sequences = {
            ("PASS", "FOUND", "PASS"),
            ("PASS", "FOUND", "FAILED"),
            ("PASS", "ABSENT", "NOT_RUN"),
            ("FAILED", "UNKNOWN", "NOT_RUN"),
        }
        if gt_assist_probe is None:
            raise ResolutionError(
                "setup validation report is missing valid <INTERNAL_KNOWLEDGE_ASSISTANT> functional probe evidence"
            )
        gt_sequence = gt_assist_probe.groups()
        if gt_sequence not in valid_gt_assist_sequences:
            raise ResolutionError(
                "setup validation report is missing valid <INTERNAL_KNOWLEDGE_ASSISTANT> functional probe evidence"
            )

        validated_at = datetime.strptime(
            validated_match.group(1), "%Y-%m-%dT%H:%M:%SZ"
        ).replace(tzinfo=timezone.utc)
        age_hours = (datetime.now(timezone.utc) - validated_at).total_seconds() / 3600
        if age_hours < 0 or age_hours > ttl_hours:
            raise ResolutionError("setup validation report is expired or future-dated")

        current_fingerprint = setup_input_fingerprint(workspace, fingerprint_inputs)
        if fingerprint_match.group(1) != current_fingerprint:
            raise ResolutionError("setup validation input fingerprint does not match")
    except FileNotFoundError:
        return result(
            "verify-setup-cache",
            "stale",
            workspace,
            failures=["setup cache is not current: setup validation report is missing"],
        )
    except OSError as error:
        return result(
            "verify-setup-cache",
            "blocked",
            workspace,
            failures=[f"setup cache could not be read: {error}"],
        )
    except (
        UnicodeError,
        json.JSONDecodeError,
        KeyError,
        TypeError,
        ValueError,
    ) as error:
        return result(
            "verify-setup-cache",
            "stale",
            workspace,
            failures=[f"setup cache is not current: {error}"],
        )

    return result(
        "verify-setup-cache",
        "current",
        workspace,
        source_fingerprint=verified["source_fingerprint"],
        setup_input_fingerprint=current_fingerprint,
        report_fingerprints={
            "Config-Fingerprint": current_fingerprint,
            "Resolved-Config-Fingerprint": verified["source_fingerprint"],
        },
    )


def parse_args() -> argparse.Namespace:
    """Parse and validate command-line arguments.

    Returns:
        Parsed resolver mode, optional section, and workspace path.

    Raises:
        SystemExit: If arguments are invalid or inconsistent with the selected
            mode.
    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "mode", choices=("materialize", "verify", "read", "verify-setup-cache")
    )
    parser.add_argument("section", nargs="?", help="Dotted configuration path for read mode")
    parser.add_argument("--workspace", type=Path, default=Path.cwd(), help="Workspace root")
    args = parser.parse_args()
    if args.mode == "read" and not args.section:
        parser.error("read mode requires a section")
    if args.mode != "read" and args.section:
        parser.error("a section is valid only in read mode")
    return args


def main() -> int:
    """Run the selected resolver operation and print its JSON response.

    Returns:
        Zero when the operation returns ``current`` status; otherwise two.
    """
    args = parse_args()
    workspace = args.workspace.resolve()
    if args.mode == "materialize":
        payload = materialize(workspace)
    elif args.mode == "verify":
        payload = verify_snapshot(workspace)
    elif args.mode == "verify-setup-cache":
        payload = verify_setup_cache(workspace)
    else:
        payload = read_section(workspace, args.section)
    print(
        json.dumps(
            payload,
            indent=2,
            sort_keys=True,
            ensure_ascii=True,
            allow_nan=False,
        )
    )
    return 0 if payload["status"] == "current" else 2


if __name__ == "__main__":
    raise SystemExit(main())
