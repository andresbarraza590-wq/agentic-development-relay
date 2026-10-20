"""Unit tests for deterministic runtime configuration resolution."""

import importlib.util
import json
import re
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock


SCRIPT_PATH = Path(__file__).with_name("resolve-config.py")
SPEC = importlib.util.spec_from_file_location("resolve_config", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
RESOLVER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = RESOLVER
SPEC.loader.exec_module(RESOLVER)


class ResolveConfigTests(unittest.TestCase):
    """Verify configuration merging, snapshot publication, and validation."""

    def setUp(self):
        """Create an isolated workspace with a valid baseline configuration."""
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.workspace = Path(self.temporary_directory.name)
        self.config_directory = self.workspace / ".github" / "config"
        self.config_directory.mkdir(parents=True)
        self.write_yaml(
            "default-config.yaml",
            """
config_resolution: {schema_version: 1, resolved_file: .github/cache/config/resolved-config.json}
story_refinement: {pass_threshold: 0.6, required_fields: [description], scored_criteria: [{name: Scope defined, weight: high, check: Description contains scope}]}
commands:
  resolution: >
    Use configured commands and
    never guess missing values.
mcp_servers:
  jira:
    prefix: mcp_jira
    test_call: probe
    required: true
    description: Jira integration
setup_validation:
  cache_ttl_hours: 744
  timeouts:
    mcp_initialize_seconds: 30
    mcp_method_seconds: 30
    mcp_server_seconds: 60
    sage_command_seconds: 20
    external_phase_seconds: 180
  fingerprint_inputs:
    - .github/config/agent-commands.yaml
    - .vscode/settings.json
required_extensions:
  always: []
  recommended: [github.copilot]
ide_prerequisites:
  ai_coauthor:
    required: true
    required_mode: all
    vscode:
      setting_key: git.addAICoAuthor
      accepted_values: [all]
      required_value: all
      repository_enforcement_file: .vscode/settings.json
    intellij:
      plugin_name: GitHub Copilot
      accepted_enforcement_modes: [ide_native]
      repository_fallback_files: [.gitmessage]
language_style_defaults:
  coding: {docstring_style: google}
  terraform: {naming: {resources: snake_case}}
documentation:
  architecture: []
architecture:
  auto_context: true
  metadata_file: .github/artifacts/architecture-metadata.json
  refresh_on: architecture-significant-change
  drift_scan:
    enabled: true
    baseline_manifest: .github/artifacts/repo-inventory.json
    changed_files_threshold: 25
    changed_repos_threshold: 3
    significant_paths: ["**/*.tf"]
    require_consent: true
""".lstrip(),
        )

    def tearDown(self):
        """Remove the isolated workspace and its generated snapshot files."""
        self.temporary_directory.cleanup()

    def write_yaml(self, name, content):
        """Write a configuration source into the isolated workspace.

        Args:
            name: File name beneath the workspace configuration directory.
            content: UTF-8 YAML content to write.
        """
        (self.config_directory / name).write_text(content, encoding="utf-8")

    def write_command_manifest(self, content):
        """Write the optional command manifest beneath the canonical path."""
        self.write_yaml("agent-commands.yaml", content)

    def test_command_manifest_rejects_duplicate_keys_and_test_skip(self):
        """Reject ambiguous command data and preserve mandatory test semantics."""
        valid_prefix = (
            "commands:\n"
            "  build: ''\n"
            "  integration_test: ''\n"
            "  lint: ''\n"
            "  coverage: ''\n"
            "  run: ''\n"
        )
        cases = (
            (valid_prefix + "  test: pytest\n  test: other\n", "duplicate key"),
            (valid_prefix + "  test: skip\n", "commands.test cannot be skip"),
        )
        for content, expected in cases:
            with self.subTest(expected=expected):
                self.write_command_manifest(content)
                materialized = RESOLVER.materialize(self.workspace)
                self.assertEqual("blocked", materialized["status"])
                self.assertIn(expected, materialized["failures"][0])

    def test_command_manifest_fingerprint_changes_with_content(self):
        """Return a deterministic presence-aware fingerprint for command data."""
        self.write_command_manifest(
            "commands:\n"
            "  build: ''\n"
            "  test: pytest\n"
            "  integration_test: ''\n"
            "  lint: ''\n"
            "  coverage: ''\n"
            "  run: ''\n"
        )
        first = RESOLVER.materialize(self.workspace)
        self.assertEqual("current", first["status"], first)
        self.assertRegex(first["command_manifest_fingerprint"], r"^[0-9a-f]{64}$")

        self.write_command_manifest(
            (self.config_directory / "agent-commands.yaml")
            .read_text(encoding="utf-8")
            .replace("pytest", "pytest -q")
        )
        second = RESOLVER.materialize(self.workspace)
        self.assertEqual("current", second["status"], second)
        self.assertNotEqual(
            first["command_manifest_fingerprint"],
            second["command_manifest_fingerprint"],
        )

    def test_runtime_config_rejects_invalid_operational_range(self):
        """Reject malformed consumed settings before publishing a snapshot."""
        baseline = (self.config_directory / "default-config.yaml").read_text(
            encoding="utf-8"
        )
        self.write_yaml(
            "default-config.yaml",
            baseline.replace("changed_files_threshold: 25", "changed_files_threshold: 0"),
        )

        materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("blocked", materialized["status"])
        self.assertIn("must be a positive integer", materialized["failures"][0])

    def test_materialize_merges_team_delta_and_read_returns_named_section(self):
        """Verify materialization merges allowed team values for named reads."""
        self.write_yaml(
            "team-config.yaml",
            "story_refinement:\n"
            "  pass_threshold: 0.8\n"
            "  required_fields: [description, acceptance_criteria]\n"
            "mcp_servers:\n"
            "  additional:\n"
            "    - name: wiki\n"
            "      prefix: mcp_wiki\n"
            "      test_call: search\n"
            "      required: false\n"
            "      description: Internal documentation\n",
        )

        materialized = RESOLVER.materialize(self.workspace)
        read_result = RESOLVER.read_section(self.workspace, "story_refinement")

        self.assertEqual("current", materialized["status"], materialized)
        self.assertEqual("current", read_result["status"])
        self.assertEqual(0.8, read_result["value"]["pass_threshold"])
        self.assertEqual(
            ["description", "acceptance_criteria"],
            read_result["value"]["required_fields"],
        )
        snapshot = json.loads(
            (self.workspace / RESOLVER.SNAPSHOT_PATH).read_text(encoding="utf-8")
        )
        self.assertIn("jira", snapshot["config"]["mcp_servers"])
        self.assertEqual("wiki", snapshot["config"]["mcp_servers"]["additional"][0]["name"])

    def test_mcp_additional_must_be_a_sequence(self):
        """Reject an additive MCP value that is not a sequence."""
        self.write_yaml("team-config.yaml", "mcp_servers:\n  additional: invalid\n")

        materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("blocked", materialized["status"])
        self.assertIn("must be a sequence", materialized["failures"][0])

    def test_mcp_additional_items_must_be_mappings(self):
        """Reject an additive MCP sequence containing a scalar item."""
        self.write_yaml("team-config.yaml", "mcp_servers:\n  additional: [wiki]\n")

        materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("blocked", materialized["status"])
        self.assertIn("must be a mapping", materialized["failures"][0])

    def test_baseline_mcp_records_require_consumer_fields(self):
        """Reject malformed baseline MCP records before snapshot publication."""
        baseline = (self.config_directory / "default-config.yaml").read_text(encoding="utf-8")
        self.write_yaml(
            "default-config.yaml",
            baseline.replace(
                "    test_call: probe\n",
                "",
                1,
            ),
        )

        materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("blocked", materialized["status"])
        self.assertIn("mcp_servers.jira.test_call must be a non-empty string", materialized["failures"][0])

    def test_baseline_mcp_names_must_match_probe_line_grammar(self):
        """Reject keyed baseline names that cannot round-trip through setup reports."""
        baseline = (self.config_directory / "default-config.yaml").read_text(encoding="utf-8")
        self.write_yaml(
            "default-config.yaml",
            baseline.replace("  jira:\n", "  jira=prod:\n", 1),
        )

        materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("blocked", materialized["status"])
        self.assertIn("must not have surrounding whitespace", materialized["failures"][0])

    def test_mcp_additional_requires_consumer_fields(self):
        """Reject an additive MCP record missing a required probe field."""
        self.write_yaml(
            "team-config.yaml",
            """
mcp_servers:
  additional:
  - name: wiki
    prefix: mcp_wiki
    required: false
    description: Internal documentation
""".lstrip(),
        )

        materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("blocked", materialized["status"])
        self.assertIn("test_call must be a non-empty string", materialized["failures"][0])

    def test_mcp_additional_required_must_be_boolean(self):
        """Reject an additive MCP record with a string required flag."""
        self.write_yaml(
            "team-config.yaml",
            "mcp_servers:\n"
            "  additional:\n"
            "    - name: wiki\n"
            "      prefix: mcp_wiki\n"
            "      test_call: search\n"
            "      required: \"false\"\n"
            "      description: Internal documentation\n",
        )

        materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("blocked", materialized["status"])
        self.assertIn("required must be a boolean", materialized["failures"][0])

    def test_mcp_additional_names_must_be_unique(self):
        """Reject additive MCP records that duplicate a baseline server name."""
        self.write_yaml(
            "team-config.yaml",
            """
mcp_servers:
  additional:
  - name: jira
    prefix: mcp_other_jira
    test_call: getJiraDetails
    required: true
    description: Duplicate Jira integration
""".lstrip(),
        )

        materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("blocked", materialized["status"])
        self.assertIn("duplicate MCP server name: jira", materialized["failures"][0])

    def test_mcp_additional_name_must_match_probe_line_grammar(self):
        """Reject names that cannot round-trip through MCP-Probe report lines."""
        for name in ("wiki=prod", " wiki", "wiki ", "wiki\nprod"):
            with self.subTest(name=name):
                self.write_yaml(
                    "team-config.yaml",
                    "mcp_servers:\n"
                    "  additional:\n"
                    f"    - name: {json.dumps(name)}\n"
                    "      prefix: mcp_wiki\n"
                    "      test_call: search\n"
                    "      required: false\n"
                    "      description: Internal documentation\n",
                )

                materialized = RESOLVER.materialize(self.workspace)

                self.assertEqual("blocked", materialized["status"])
                self.assertIn("must not have surrounding whitespace", materialized["failures"][0])

    def test_mcp_additional_name_allows_internal_spaces(self):
        """Keep human-readable names that the probe grammar can round-trip."""
        self.write_yaml(
            "team-config.yaml",
            "mcp_servers:\n"
            "  additional:\n"
            "    - name: Team Wiki\n"
            "      prefix: mcp_wiki\n"
            "      test_call: search\n"
            "      required: false\n"
            "      description: Internal documentation\n",
        )

        materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("current", materialized["status"], materialized)

    def test_setup_timeouts_are_positive_ordered_integers(self):
        """Reject non-positive or internally inconsistent setup deadlines."""
        baseline = (self.config_directory / "default-config.yaml").read_text(encoding="utf-8")
        for old, new, expected in (
            ("mcp_method_seconds: 30", "mcp_method_seconds: 0", "must be a positive integer"),
            ("mcp_server_seconds: 60", "mcp_server_seconds: 20", "must be at least each MCP operation timeout"),
            ("external_phase_seconds: 180", "external_phase_seconds: 10", "must be at least each family timeout"),
        ):
            self.write_yaml("default-config.yaml", baseline.replace(old, new))

            materialized = RESOLVER.materialize(self.workspace)

            self.assertEqual("blocked", materialized["status"])
            self.assertIn(expected, materialized["failures"][0])

    def test_team_cannot_weaken_setup_timeouts(self):
        """Keep external-validation deadlines under framework ownership."""
        self.write_yaml(
            "team-config.yaml",
            "setup_validation:\n  timeouts:\n    mcp_method_seconds: 300\n",
        )

        materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("blocked", materialized["status"])
        self.assertIn(
            "cannot override setup_validation.timeouts",
            materialized["failures"][0],
        )

    def test_architecture_paths_are_runtime_overridable_but_sandboxed(self):
        """Accept sanctioned runtime paths and reject paths outside .github."""
        self.write_yaml(
            "team-config.yaml",
            "architecture:\n"
            "  metadata_file: .github/custom/architecture.json\n"
            "  refresh_on: any-change\n"
            "  drift_scan:\n"
            "    baseline_manifest: .github/custom/inventory.json\n",
        )

        materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("current", materialized["status"], materialized)
        read_result = RESOLVER.read_section(self.workspace, "architecture")
        self.assertEqual(".github/custom/architecture.json", read_result["value"]["metadata_file"])
        self.assertEqual("any-change", read_result["value"]["refresh_on"])

        self.write_yaml(
            "team-config.yaml",
            "architecture:\n  metadata_file: ../architecture.json\n",
        )
        blocked = RESOLVER.materialize(self.workspace)
        self.assertEqual("blocked", blocked["status"])
        self.assertIn("workspace-relative .github/*.json path", blocked["failures"][0])

        self.write_yaml(
            "team-config.yaml",
            "architecture:\n"
            "  metadata_file: .github/custom/SAME.json\n"
            "  drift_scan:\n"
            "    baseline_manifest: .github/custom/same.json\n",
        )
        alias = RESOLVER.materialize(self.workspace)
        self.assertEqual("blocked", alias["status"])
        self.assertIn("must be distinct paths", alias["failures"][0])

        self.write_yaml(
            "team-config.yaml",
            "architecture:\n"
            "  metadata_file: .github/custom/architecture.json\n"
            "  drift_scan:\n"
            "    baseline_manifest: .github/custom/./architecture.json\n",
        )
        lexical_alias = RESOLVER.materialize(self.workspace)
        self.assertEqual("blocked", lexical_alias["status"])
        self.assertIn("must be distinct paths", lexical_alias["failures"][0])

    def test_snapshot_filesystem_failure_is_blocked(self):
        """Snapshot read failures are operational blockers."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        with mock.patch.object(Path, "read_text", side_effect=PermissionError("denied")):
            verified = RESOLVER.verify_setup_cache(self.workspace)

        self.assertEqual("blocked", verified["status"])
        self.assertIn("cannot read snapshot", verified["failures"][0])

    def test_missing_setup_report_is_stale(self):
        """Verify an absent setup report requests normal revalidation."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])

        verified = RESOLVER.verify_setup_cache(self.workspace)

        self.assertEqual("stale", verified["status"])
        self.assertIn("setup validation report is missing", verified["failures"][0])

    def test_setup_report_filesystem_failure_is_blocked(self):
        """Setup report read failures are blockers rather than stale evidence."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        original_read_text = Path.read_text

        def read_text(path, *args, **kwargs):
            if path == self.workspace / RESOLVER.SETUP_REPORT_PATH:
                raise PermissionError("denied")
            return original_read_text(path, *args, **kwargs)

        with mock.patch.object(Path, "read_text", autospec=True, side_effect=read_text):
            verified = RESOLVER.verify_setup_cache(self.workspace)

        self.assertEqual("blocked", verified["status"])
        self.assertIn("setup cache could not be read", verified["failures"][0])

    def test_read_section_filesystem_failure_has_read_envelope(self):
        """Read-mode I/O failures retain the read operation envelope."""
        with mock.patch.object(
            RESOLVER, "_load_verified_snapshot", side_effect=PermissionError("denied")
        ):
            read_result = RESOLVER.read_section(self.workspace, "architecture")

        self.assertEqual("read", read_result["mode"])
        self.assertEqual("blocked", read_result["status"])
        self.assertIn("cannot read snapshot", read_result["failures"][0])

    def test_verify_reports_stale_after_source_change(self):
        """Verify source changes make an existing snapshot stale."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        self.write_yaml(
            "default-config.yaml",
            (self.config_directory / "default-config.yaml").read_text(encoding="utf-8")
            + "team:\n  name: changed\n",
        )

        verified = RESOLVER.verify_snapshot(self.workspace)

        self.assertEqual("stale", verified["status"])

    def test_source_fingerprint_distinguishes_missing_from_literal_marker(self):
        missing_bundle = RESOLVER.read_source_bundle(self.workspace)
        optional_source_path = RESOLVER.SOURCE_PATHS[1]
        missing_bundle[optional_source_path] = None
        literal_bundle = dict(missing_bundle)
        literal_bundle[optional_source_path] = b"<missing>"

        _, missing_fingerprint = RESOLVER.source_metadata_from_bundle(missing_bundle)
        _, literal_fingerprint = RESOLVER.source_metadata_from_bundle(literal_bundle)

        self.assertNotEqual(missing_fingerprint, literal_fingerprint)

    def test_materialize_generation_uses_one_source_bundle(self):
        """Verify generation resolves and fingerprints the same byte bundle."""
        original_resolver = RESOLVER.resolve_source_bundle
        original_metadata = RESOLVER.source_metadata_from_bundle
        with mock.patch.object(
            RESOLVER,
            "resolve_source_bundle",
            wraps=original_resolver,
        ) as resolve_source_bundle, mock.patch.object(
            RESOLVER,
            "source_metadata_from_bundle",
            wraps=original_metadata,
        ) as source_metadata_from_bundle:
            materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("current", materialized["status"])
        generation_resolve_bundle = resolve_source_bundle.call_args_list[0].args[0]
        generation_metadata_bundle = source_metadata_from_bundle.call_args_list[0].args[0]
        self.assertIs(generation_resolve_bundle, generation_metadata_bundle)

    def test_protected_override_blocks_without_replacing_valid_snapshot(self):
        """Verify a protected override cannot replace a valid snapshot."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        snapshot_path = self.workspace / RESOLVER.SNAPSHOT_PATH
        previous_snapshot = snapshot_path.read_bytes()
        self.write_yaml("team-config.yaml", "config_resolution:\n  schema_version: 2\n")

        materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("blocked", materialized["status"])
        self.assertEqual(previous_snapshot, snapshot_path.read_bytes())

    def test_source_drift_during_materialize_preserves_valid_snapshot(self):
        """Verify publication-time source drift preserves the previous snapshot."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        snapshot_path = self.workspace / RESOLVER.SNAPSHOT_PATH
        previous_snapshot = snapshot_path.read_bytes()
        original_bundle = RESOLVER.read_source_bundle(self.workspace)
        changed_bundle = dict(original_bundle)
        changed_bundle[RESOLVER.DEFAULT_PATH] += b"\n"

        with mock.patch.object(
            RESOLVER,
            "read_source_bundle",
            side_effect=[original_bundle, changed_bundle],
        ):
            materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("blocked", materialized["status"])
        self.assertIn("sources changed", materialized["failures"][0])
        self.assertEqual(previous_snapshot, snapshot_path.read_bytes())

    def test_source_drift_after_replace_restores_valid_snapshot(self):
        """Verify post-publication drift restores the prior canonical bytes."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        snapshot_path = self.workspace / RESOLVER.SNAPSHOT_PATH
        previous_snapshot = snapshot_path.read_bytes()
        original_bundle = RESOLVER.read_source_bundle(self.workspace)
        changed_bundle = dict(original_bundle)
        changed_bundle[RESOLVER.DEFAULT_PATH] += b"\n"

        with mock.patch.object(
            RESOLVER,
            "read_source_bundle",
            side_effect=[original_bundle, original_bundle, changed_bundle],
        ):
            materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("blocked", materialized["status"])
        self.assertIn("changed after publication", materialized["failures"][0])
        self.assertEqual(previous_snapshot, snapshot_path.read_bytes())
        self.assertFalse((self.workspace / RESOLVER.RECOVERY_PATH).exists())

    def test_rollback_failure_retains_prior_recovery_bytes(self):
        """Verify a failed rollback never destroys the last valid generation."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        snapshot_path = self.workspace / RESOLVER.SNAPSHOT_PATH
        recovery_path = self.workspace / RESOLVER.RECOVERY_PATH
        previous_snapshot = snapshot_path.read_bytes()
        original_bundle = RESOLVER.read_source_bundle(self.workspace)
        changed_bundle = dict(original_bundle)
        changed_bundle[RESOLVER.DEFAULT_PATH] += b"\n"
        original_replace = RESOLVER.os.replace

        def fail_recovery_replace(source, destination):
            if Path(source) == recovery_path and Path(destination) == snapshot_path:
                raise PermissionError("rollback denied")
            return original_replace(source, destination)

        # Pin a distinct clock so the un-rolled-back candidate cannot collide with
        # the prior snapshot's second-resolution generated_at on a fast machine.
        later_clock = mock.Mock(wraps=datetime)
        later_clock.now.return_value = datetime(2030, 1, 1, tzinfo=timezone.utc)

        with mock.patch.object(
            RESOLVER,
            "read_source_bundle",
            side_effect=[original_bundle, original_bundle, changed_bundle],
        ), mock.patch.object(
            RESOLVER.os, "replace", side_effect=fail_recovery_replace
        ), mock.patch.object(RESOLVER, "datetime", later_clock):
            materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("blocked", materialized["status"])
        self.assertIn("rollback denied", materialized["failures"][0])
        self.assertEqual(previous_snapshot, recovery_path.read_bytes())
        self.assertNotEqual(previous_snapshot, snapshot_path.read_bytes())

    def test_concurrent_materializer_is_blocked_without_replacing_snapshot(self):
        """Verify a second writer cannot enter the workspace publication boundary."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        snapshot_path = self.workspace / RESOLVER.SNAPSHOT_PATH
        previous_snapshot = snapshot_path.read_bytes()

        with RESOLVER.materialization_lock(self.workspace):
            materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("blocked", materialized["status"])
        self.assertIn("already in progress", materialized["failures"][0])
        self.assertEqual(previous_snapshot, snapshot_path.read_bytes())

    def test_staged_type_substitution_preserves_valid_snapshot(self):
        """Reject staged JSON whose value compares equal only through type coercion."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        snapshot_path = self.workspace / RESOLVER.SNAPSHOT_PATH
        previous_snapshot = snapshot_path.read_bytes()
        original_loads = json.loads

        def substitute_boolean_with_integer(value):
            staged = original_loads(value)
            staged["config"]["mcp_servers"]["jira"]["required"] = 1
            return staged

        with mock.patch.object(
            RESOLVER.json,
            "loads",
            side_effect=substitute_boolean_with_integer,
        ):
            materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("blocked", materialized["status"])
        self.assertIn("staged snapshot failed", materialized["failures"][0])
        self.assertEqual(previous_snapshot, snapshot_path.read_bytes())

    def test_invalid_setup_inputs_preserve_valid_snapshot(self):
        """Verify invalid setup inputs block before replacing a valid snapshot."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        snapshot_path = self.workspace / RESOLVER.SNAPSHOT_PATH
        previous_snapshot = snapshot_path.read_bytes()
        baseline = (self.config_directory / "default-config.yaml").read_text(encoding="utf-8")
        self.write_yaml(
            "default-config.yaml",
            baseline.replace(
                "  fingerprint_inputs:\n"
                "    - .github/config/agent-commands.yaml\n"
                "    - .vscode/settings.json\n",
                "  fingerprint_inputs: invalid\n",
            ),
        )

        materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("blocked", materialized["status"])
        self.assertIn("must be a non-empty sequence of unique", materialized["failures"][0])
        self.assertEqual(previous_snapshot, snapshot_path.read_bytes())

    def test_empty_or_duplicate_setup_inputs_preserve_valid_snapshot(self):
        """Reject empty and duplicate fingerprint identities before publication."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        snapshot_path = self.workspace / RESOLVER.SNAPSHOT_PATH
        previous_snapshot = snapshot_path.read_bytes()
        baseline = (self.config_directory / "default-config.yaml").read_text(encoding="utf-8")

        for fingerprint_inputs in (
            "[]",
            "['   ']",
            "[' .vscode/settings.json']",
            "['.vscode/settings.json ']",
            "[.vscode/settings.json, .vscode/settings.json]",
            "[.vscode/settings.json, .vscode\\\\settings.json]",
            "[.vscode/settings.json, .VSCODE/SETTINGS.JSON]",
        ):
            start = baseline.index("  fingerprint_inputs:")
            end = baseline.index("required_extensions:", start)
            self.write_yaml(
                "default-config.yaml",
                baseline[:start]
                + f"  fingerprint_inputs: {fingerprint_inputs}\n"
                + baseline[end:],
            )

            materialized = RESOLVER.materialize(self.workspace)

            self.assertEqual("blocked", materialized["status"])
            self.assertIn("non-empty sequence of unique", materialized["failures"][0])
            self.assertEqual(previous_snapshot, snapshot_path.read_bytes())

    def test_setup_input_read_failure_preserves_valid_snapshot(self):
        """Verify setup-input read failures return a blocker before publication."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        snapshot_path = self.workspace / RESOLVER.SNAPSHOT_PATH
        previous_snapshot = snapshot_path.read_bytes()
        with mock.patch.object(
            RESOLVER,
            "setup_input_fingerprint",
            side_effect=PermissionError("setup input denied"),
        ):
            materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("blocked", materialized["status"])
        self.assertIn("setup input denied", materialized["failures"][0])
        self.assertEqual(previous_snapshot, snapshot_path.read_bytes())

    def test_verify_reports_malformed_for_incomplete_source_envelope(self):
        """Verify incomplete source metadata makes a snapshot malformed."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        snapshot_path = self.workspace / RESOLVER.SNAPSHOT_PATH
        snapshot = json.loads(snapshot_path.read_text(encoding="utf-8"))
        snapshot["sources"] = snapshot["sources"][:1]
        snapshot_path.write_text(json.dumps(snapshot), encoding="utf-8")

        verified = RESOLVER.verify_snapshot(self.workspace)

        self.assertEqual("malformed", verified["status"])

    def test_malformed_envelope_takes_precedence_over_source_drift(self):
        """Verify source changes cannot hide structural snapshot corruption."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        snapshot_path = self.workspace / RESOLVER.SNAPSHOT_PATH
        snapshot = json.loads(snapshot_path.read_text(encoding="utf-8"))
        snapshot["sources"] = snapshot["sources"][:1]
        snapshot_path.write_text(json.dumps(snapshot), encoding="utf-8")
        self.write_yaml(
            "default-config.yaml",
            (self.config_directory / "default-config.yaml").read_text(encoding="utf-8")
            + "team:\n  name: changed\n",
        )

        verified = RESOLVER.verify_snapshot(self.workspace)

        self.assertEqual("malformed", verified["status"])

    def test_non_object_config_takes_precedence_over_invalid_current_sources(self):
        """Verify source failures cannot hide a structurally invalid config payload."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        snapshot_path = self.workspace / RESOLVER.SNAPSHOT_PATH
        snapshot = json.loads(snapshot_path.read_text(encoding="utf-8"))
        snapshot["config"] = []
        snapshot_path.write_text(json.dumps(snapshot), encoding="utf-8")
        self.write_yaml("team-config.yaml", "config_resolution:\n  schema_version: 2\n")

        verified = RESOLVER.verify_snapshot(self.workspace)

        self.assertEqual("malformed", verified["status"])

    def test_verify_rejects_tampered_resolved_config(self):
        """Verify snapshot content must equal the merge identified by its sources."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        snapshot_path = self.workspace / RESOLVER.SNAPSHOT_PATH
        snapshot = json.loads(snapshot_path.read_text(encoding="utf-8"))
        snapshot["config"]["story_refinement"]["pass_threshold"] = 0.1
        snapshot_path.write_text(json.dumps(snapshot), encoding="utf-8")

        verified = RESOLVER.verify_snapshot(self.workspace)

        self.assertEqual("malformed", verified["status"])
        self.assertIn(
            "config does not match current resolved configuration",
            verified["failures"],
        )

    def test_verify_rejects_boolean_replaced_by_integer(self):
        """Reject Python-equal snapshot values whose JSON types differ."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        snapshot_path = self.workspace / RESOLVER.SNAPSHOT_PATH
        snapshot = json.loads(snapshot_path.read_text(encoding="utf-8"))
        snapshot["config"]["architecture"]["auto_context"] = 1
        snapshot_path.write_text(json.dumps(snapshot), encoding="utf-8")

        verified = RESOLVER.verify_snapshot(self.workspace)

        self.assertEqual("malformed", verified["status"])
        self.assertIn(
            "config does not match current resolved configuration",
            verified["failures"],
        )

    def test_duplicate_yaml_key_is_rejected(self):
        """Reject ambiguous YAML mappings instead of accepting the last key."""
        self.write_yaml(
            "team-config.yaml",
            "custom:\n  value: first\ncustom:\n  value: second\n",
        )

        materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("blocked", materialized["status"])
        self.assertIn("duplicate key", materialized["failures"][0])

    def test_recursive_yaml_alias_is_rejected(self):
        """Reject cyclic YAML aliases before recursive validation or merge."""
        self.write_yaml(
            "team-config.yaml",
            "custom: &recursive\n  child: *recursive\n",
        )

        materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("blocked", materialized["status"])
        self.assertIn("must not form a cycle", materialized["failures"][0])

    def test_non_finite_yaml_number_is_rejected(self):
        """Reject YAML numbers that standard JSON cannot represent."""
        self.write_yaml("team-config.yaml", "custom:\n  value: .inf\n")

        materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("blocked", materialized["status"])
        self.assertIn("must be finite", materialized["failures"][0])

    def test_excessive_configuration_depth_is_rejected(self):
        """Reject structures deeper than the bounded resolver contract."""
        value = {}
        current = value
        for index in range(RESOLVER.MAX_CONFIG_DEPTH + 1):
            current["child"] = {}
            current = current["child"]

        with self.assertRaisesRegex(RESOLVER.ResolutionError, "nesting exceeds"):
            RESOLVER.validate_json_domain(value)

    def test_sequence_replacement_does_not_concatenate(self):
        """Verify team sequences replace compatible baseline sequences."""
        self.write_yaml(
            "team-config.yaml",
            "story_refinement:\n  required_fields: [acceptance_criteria]\n",
        )

        materialized = RESOLVER.materialize(self.workspace)
        read_result = RESOLVER.read_section(self.workspace, "story_refinement.required_fields")

        self.assertEqual("current", materialized["status"])
        self.assertEqual(["acceptance_criteria"], read_result["value"])

    def test_type_conflict_blocks_without_replacing_valid_snapshot(self):
        """Verify a mapping/scalar conflict preserves the previous snapshot."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        snapshot_path = self.workspace / RESOLVER.SNAPSHOT_PATH
        previous_snapshot = snapshot_path.read_bytes()
        self.write_yaml("team-config.yaml", "story_refinement: disabled\n")

        materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("blocked", materialized["status"])
        self.assertEqual(previous_snapshot, snapshot_path.read_bytes())

    def test_null_erasure_blocks_without_replacing_valid_snapshot(self):
        """Verify null cannot erase a non-null baseline value."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        snapshot_path = self.workspace / RESOLVER.SNAPSHOT_PATH
        previous_snapshot = snapshot_path.read_bytes()
        self.write_yaml("team-config.yaml", "story_refinement:\n  pass_threshold: null\n")

        materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("blocked", materialized["status"])
        self.assertEqual(previous_snapshot, snapshot_path.read_bytes())

    def test_nested_protected_key_is_rejected(self):
        """Verify protected resolver keys cannot be hidden below another mapping."""
        self.write_yaml("team-config.yaml", "custom:\n  pipeline:\n    enabled: false\n")

        materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("blocked", materialized["status"])

    def test_lowered_refinement_threshold_is_rejected(self):
        """Verify a team delta cannot weaken the baseline refinement threshold."""
        self.write_yaml("team-config.yaml", "story_refinement:\n  pass_threshold: 0.5\n")

        materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("blocked", materialized["status"])

    def test_missing_read_section_is_blocked(self):
        """Verify named reads never invent a missing configuration section."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])

        read_result = RESOLVER.read_section(self.workspace, "documentation.missing")

        self.assertEqual("blocked", read_result["status"])

    def test_verify_source_permission_failure_returns_blocked_result(self):
        """Verify source permission failures stay inside the JSON contract."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        with mock.patch.object(
            RESOLVER,
            "read_source_bundle",
            side_effect=PermissionError("source denied"),
        ):
            verified = RESOLVER.verify_snapshot(self.workspace)

        self.assertEqual("blocked", verified["status"])
        self.assertIn("source denied", verified["failures"][0])

    def test_materialize_cleanup_failure_returns_blocked_result(self):
        """Verify temp cleanup errors do not escape or replace structured output."""
        with mock.patch.object(
            RESOLVER.os,
            "replace",
            side_effect=PermissionError("replace denied"),
        ), mock.patch.object(
            Path,
            "unlink",
            side_effect=PermissionError("cleanup denied"),
        ):
            materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("blocked", materialized["status"])
        self.assertIn("replace denied", materialized["failures"][0])
        self.assertIn("cleanup denied", materialized["failures"][0])

    def test_read_snapshot_failure_returns_blocked_result(self):
        """Verify a snapshot read failure returns a structured blocker."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        with mock.patch.object(
            RESOLVER,
            "_load_verified_snapshot",
            side_effect=FileNotFoundError("snapshot disappeared"),
        ):
            read_result = RESOLVER.read_section(self.workspace, "story_refinement")

        self.assertEqual("blocked", read_result["status"])
        self.assertIn("snapshot disappeared", read_result["failures"][0])

    def test_read_consumes_the_snapshot_returned_by_verification(self):
        """Verify named reads do not reopen a replaceable snapshot path."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        original_loader = RESOLVER._load_verified_snapshot
        with mock.patch.object(
            RESOLVER,
            "_load_verified_snapshot",
            wraps=original_loader,
        ) as load_verified_snapshot:
            read_result = RESOLVER.read_section(self.workspace, "story_refinement")

        self.assertEqual("current", read_result["status"])
        load_verified_snapshot.assert_called_once_with(self.workspace, mode="read")

    def write_setup_report(self, validated_at):
        """Write a PASS report matching the current configured setup inputs."""
        fingerprint = RESOLVER.setup_input_fingerprint(
            self.workspace,
            [".github/config/agent-commands.yaml", ".vscode/settings.json"],
        )
        report_path = self.workspace / RESOLVER.SETUP_REPORT_PATH
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(
            "\n".join(
                [
                    "Step 0a Setup Validation Report",
                    f"Validated-At: {validated_at}",
                    f"Config-Fingerprint: {fingerprint}",
                    "MCP-Probe: jira=PASS",
                    "Jira-Probe: getJiraInstancesAndProjectsForCurrentUser=PASS (readable project visible)",
                    "GT-Assist-Probe: ListUsecases=PASS; Global Technology=FOUND; AskGTAssist=PASS",
                    "Result: PASS (0 blockers, 0 warnings)",
                ]
            ),
            encoding="utf-8",
        )

    def test_setup_input_fingerprint_distinguishes_missing_from_literal_marker(self):
        input_path = self.workspace / "optional-input.txt"
        missing_fingerprint = RESOLVER.setup_input_fingerprint(
            self.workspace, ["optional-input.txt"]
        )
        input_path.write_bytes(b"<missing>")

        literal_fingerprint = RESOLVER.setup_input_fingerprint(
            self.workspace, ["optional-input.txt"]
        )

        self.assertNotEqual(missing_fingerprint, literal_fingerprint)

    def test_verify_setup_cache_accepts_current_matching_pass(self):
        """Verify a fresh PASS with matching inputs is current."""
        materialized = RESOLVER.materialize(self.workspace)
        self.assertEqual("current", materialized["status"])
        self.assertEqual(
            RESOLVER.setup_input_fingerprint(
                self.workspace,
                [".github/config/agent-commands.yaml", ".vscode/settings.json"],
            ),
            materialized["setup_input_fingerprint"],
        )
        self.assertNotEqual(
            materialized["source_fingerprint"],
            materialized["setup_input_fingerprint"],
        )
        self.assertEqual(
            {
                "Config-Fingerprint": materialized["setup_input_fingerprint"],
                "Resolved-Config-Fingerprint": materialized["source_fingerprint"],
            },
            materialized["report_fingerprints"],
        )
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        self.write_setup_report(now)

        verified = RESOLVER.verify_setup_cache(self.workspace)

        self.assertEqual("current", verified["status"])
        self.assertEqual(
            materialized["setup_input_fingerprint"],
            verified["setup_input_fingerprint"],
        )
        self.assertEqual(
            materialized["report_fingerprints"],
            verified["report_fingerprints"],
        )

    def test_verify_setup_cache_rejects_source_fingerprint_in_config_field(self):
        """Reject the historical source/setup fingerprint identity swap."""
        materialized = RESOLVER.materialize(self.workspace)
        self.assertEqual("current", materialized["status"])
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        self.write_setup_report(now)
        report_path = self.workspace / RESOLVER.SETUP_REPORT_PATH
        report = report_path.read_text(encoding="utf-8")
        report_path.write_text(
            re.sub(
                r"(?m)^Config-Fingerprint: [0-9a-f]{64}$",
                f"Config-Fingerprint: {materialized['source_fingerprint']}",
                report,
            ),
            encoding="utf-8",
        )

        verified = RESOLVER.verify_setup_cache(self.workspace)

        self.assertEqual("stale", verified["status"])
        self.assertIn(
            "setup validation input fingerprint does not match",
            verified["failures"][0],
        )

    def test_verify_setup_cache_accepts_legacy_emoji_pass(self):
        """Verify an existing emoji-marked PASS remains current."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        self.write_setup_report(now)
        report_path = self.workspace / RESOLVER.SETUP_REPORT_PATH
        report = report_path.read_text(encoding="utf-8")
        report_path.write_text(
            report.replace("Result: PASS", "Result: ✅ PASS"), encoding="utf-8"
        )

        verified = RESOLVER.verify_setup_cache(self.workspace)

        self.assertEqual("current", verified["status"])

    def test_verify_setup_cache_rejects_expired_pass(self):
        """Verify a PASS older than the configured 31-day TTL is stale."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        expired = (datetime.now(timezone.utc) - timedelta(days=32)).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        )
        self.write_setup_report(expired)

        verified = RESOLVER.verify_setup_cache(self.workspace)

        self.assertEqual("stale", verified["status"])

    def test_verify_setup_cache_rejects_changed_input(self):
        """Verify a configured input change invalidates an existing PASS."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        self.write_setup_report(now)
        settings = self.workspace / ".vscode" / "settings.json"
        settings.parent.mkdir(parents=True)
        settings.write_text("{}", encoding="utf-8")

        verified = RESOLVER.verify_setup_cache(self.workspace)

        self.assertEqual("stale", verified["status"])

    def test_rematerialize_after_setup_input_change_refreshes_pass_fingerprint(self):
        """Verify a setup auto-fix can publish a current PASS after rematerialization."""
        initial = RESOLVER.materialize(self.workspace)
        self.assertEqual("current", initial["status"])
        settings = self.workspace / ".vscode" / "settings.json"
        settings.parent.mkdir(parents=True)
        settings.write_text('{"git.addAICoAuthor": "all"}', encoding="utf-8")

        refreshed = RESOLVER.materialize(self.workspace)
        self.assertEqual("current", refreshed["status"])
        self.assertNotEqual(
            initial["setup_input_fingerprint"],
            refreshed["setup_input_fingerprint"],
        )
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        report_path = self.workspace / RESOLVER.SETUP_REPORT_PATH
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(
            "\n".join(
                [
                    "Step 0a Setup Validation Report",
                    f"Validated-At: {now}",
                    "Config-Fingerprint: "
                    f"{refreshed['report_fingerprints']['Config-Fingerprint']}",
                    "MCP-Probe: jira=PASS",
                    "Jira-Probe: getJiraInstancesAndProjectsForCurrentUser=PASS (readable project visible)",
                    "GT-Assist-Probe: ListUsecases=PASS; Global Technology=FOUND; AskGTAssist=PASS",
                    "Result: PASS (0 blockers, 0 warnings)",
                ]
            ),
            encoding="utf-8",
        )

        verified = RESOLVER.verify_setup_cache(self.workspace)

        self.assertEqual("current", verified["status"])
        self.assertEqual(
            refreshed["report_fingerprints"],
            verified["report_fingerprints"],
        )

    def test_verify_setup_cache_rejects_pass_without_required_metadata(self):
        """Verify the PASS marker alone cannot authorize an incomplete report."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        report_path = self.workspace / RESOLVER.SETUP_REPORT_PATH
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text("Result: PASS", encoding="utf-8")

        verified = RESOLVER.verify_setup_cache(self.workspace)

        self.assertEqual("stale", verified["status"])
        self.assertIn("missing Validated-At", verified["failures"][0])

    def test_verify_setup_cache_rejects_unproven_jira_project_visibility(self):
        """Reject a PASS without authenticated Jira project discovery."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        self.write_setup_report(now)
        report_path = self.workspace / RESOLVER.SETUP_REPORT_PATH
        report = report_path.read_text(encoding="utf-8")
        report_path.write_text(
            report.replace(
                "Jira-Probe: getJiraInstancesAndProjectsForCurrentUser=PASS (readable project visible)",
                "Jira-Probe: tool-registration-only=PASS",
            ),
            encoding="utf-8",
        )

        verified = RESOLVER.verify_setup_cache(self.workspace)

        self.assertEqual("stale", verified["status"])
        self.assertIn("Jira project-discovery evidence", verified["failures"][0])

    def test_verify_setup_cache_rejects_skipped_gt_assist_probe(self):
        """Reject a PASS that never attempted the configured <INTERNAL_KNOWLEDGE_ASSISTANT> methods."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        self.write_setup_report(now)
        report_path = self.workspace / RESOLVER.SETUP_REPORT_PATH
        report = report_path.read_text(encoding="utf-8")
        report_path.write_text(
            report.replace(
                "GT-Assist-Probe: ListUsecases=PASS; Global Technology=FOUND; AskGTAssist=PASS",
                "GT-Assist-Probe: ListUsecases=NOT_RUN; Global Technology=UNKNOWN; AskGTAssist=NOT_RUN",
            ),
            encoding="utf-8",
        )

        verified = RESOLVER.verify_setup_cache(self.workspace)

        self.assertEqual("stale", verified["status"])
        self.assertIn("<INTERNAL_KNOWLEDGE_ASSISTANT> functional probe evidence", verified["failures"][0])

    def test_verify_setup_cache_accepts_valid_degraded_gt_assist_sequence(self):
        """Allow a non-blocking <INTERNAL_KNOWLEDGE_ASSISTANT> call failure only after it was attempted."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        self.write_setup_report(now)
        report_path = self.workspace / RESOLVER.SETUP_REPORT_PATH
        report = report_path.read_text(encoding="utf-8")
        report_path.write_text(
            report.replace(
                "GT-Assist-Probe: ListUsecases=PASS; Global Technology=FOUND; AskGTAssist=PASS",
                "GT-Assist-Probe: ListUsecases=PASS; Global Technology=FOUND; AskGTAssist=FAILED",
            ),
            encoding="utf-8",
        )

        verified = RESOLVER.verify_setup_cache(self.workspace)

        self.assertEqual("current", verified["status"])

    def test_verify_setup_cache_rejects_gt_assist_host_safety_skip(self):
        """Reject synthetic evidence that says the <INTERNAL_KNOWLEDGE_ASSISTANT> probe was not attempted."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        self.write_setup_report(now)
        report_path = self.workspace / RESOLVER.SETUP_REPORT_PATH
        report = report_path.read_text(encoding="utf-8")
        report_path.write_text(
            report.replace(
                "GT-Assist-Probe: ListUsecases=PASS; Global Technology=FOUND; AskGTAssist=PASS",
                "GT-Assist-Probe: ListUsecases=FAILED; Global Technology=UNKNOWN; "
                "AskGTAssist=NOT_RUN; reason=NOT_PROBED_HOST_DEADLINE_UNAVAILABLE",
            ),
            encoding="utf-8",
        )

        verified = RESOLVER.verify_setup_cache(self.workspace)

        self.assertEqual("stale", verified["status"])
        self.assertIn("<INTERNAL_KNOWLEDGE_ASSISTANT> functional probe evidence", verified["failures"][0])

    def test_verify_setup_cache_accepts_attempted_gt_assist_catalog_failure(self):
        """Accept an actual non-blocking <INTERNAL_KNOWLEDGE_ASSISTANT> catalog call failure."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        self.write_setup_report(now)
        report_path = self.workspace / RESOLVER.SETUP_REPORT_PATH
        report = report_path.read_text(encoding="utf-8")
        report_path.write_text(
            report.replace(
                "GT-Assist-Probe: ListUsecases=PASS; Global Technology=FOUND; AskGTAssist=PASS",
                "GT-Assist-Probe: ListUsecases=FAILED; Global Technology=UNKNOWN; "
                "AskGTAssist=NOT_RUN",
            ),
            encoding="utf-8",
        )

        verified = RESOLVER.verify_setup_cache(self.workspace)

        self.assertEqual("current", verified["status"])

    def test_verify_setup_cache_accepts_failed_optional_mcp_probe(self):
        """Accept attempted optional failure as graceful-degradation evidence."""
        self.write_yaml(
            "team-config.yaml",
            "mcp_servers:\n"
            "  additional:\n"
            "    - name: Team Wiki\n"
            "      prefix: mcp_wiki\n"
            "      test_call: search\n"
            "      required: false\n"
            "      description: Optional wiki\n",
        )
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        self.write_setup_report(now)
        report_path = self.workspace / RESOLVER.SETUP_REPORT_PATH
        report = report_path.read_text(encoding="utf-8")
        report_path.write_text(
            report.replace(
                "MCP-Probe: jira=PASS",
                "MCP-Probe: jira=PASS\nMCP-Probe: Team Wiki=FAILED",
            ),
            encoding="utf-8",
        )

        verified = RESOLVER.verify_setup_cache(self.workspace)

        self.assertEqual("current", verified["status"])

    def test_verify_setup_cache_rejects_missing_configured_mcp_probe(self):
        """Reject PASS when a configured MCP family has no attempted evidence."""
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        self.write_setup_report(now)
        report_path = self.workspace / RESOLVER.SETUP_REPORT_PATH
        report = report_path.read_text(encoding="utf-8")
        report_path.write_text(
            report.replace("MCP-Probe: jira=PASS\n", ""),
            encoding="utf-8",
        )

        verified = RESOLVER.verify_setup_cache(self.workspace)

        self.assertEqual("stale", verified["status"])
        self.assertIn("does not match configured servers", verified["failures"][0])

    def write_protected_config_baseline(self):
        """Record a baseline matching the current on-disk protected config files."""
        files = {}
        for relative_path in RESOLVER.PROTECTED_CONFIG_PATHS:
            target = self.workspace / relative_path
            files[relative_path.name] = RESOLVER.sha256_bytes(target.read_bytes())
        baseline_path = self.workspace / RESOLVER.PROTECTED_CONFIG_BASELINE_PATH
        baseline_path.parent.mkdir(parents=True, exist_ok=True)
        baseline_path.write_text(
            json.dumps({"schema": 1, "files": files}), encoding="utf-8"
        )

    def test_protected_config_baseline_missing_is_not_a_failure(self):
        """An unestablished baseline degrades gracefully rather than blocking."""
        self.assertEqual([], RESOLVER.verify_protected_config_baseline(self.workspace))

    def test_protected_config_baseline_passes_when_hashes_match(self):
        """A matching baseline for both protected files verifies cleanly."""
        self.write_yaml("guardrails.yaml", "governance:\n  never: []\n")
        self.write_protected_config_baseline()

        self.assertEqual([], RESOLVER.verify_protected_config_baseline(self.workspace))

    def test_protected_config_baseline_detects_tampered_guardrails(self):
        """Detect a hand-edit to guardrails.yaml after the baseline is recorded."""
        self.write_yaml("guardrails.yaml", "governance:\n  never: []\n")
        self.write_protected_config_baseline()
        self.write_yaml("guardrails.yaml", "governance:\n  never: []\n  # tampered\n")

        failures = RESOLVER.verify_protected_config_baseline(self.workspace)

        self.assertEqual(1, len(failures))
        self.assertIn("guardrails.yaml", failures[0])
        self.assertIn("changed since installation", failures[0])

    def test_protected_config_baseline_detects_missing_protected_file(self):
        """Detect a protected file removed after the baseline is recorded."""
        self.write_yaml("guardrails.yaml", "governance:\n  never: []\n")
        self.write_protected_config_baseline()
        (self.config_directory / "guardrails.yaml").unlink()

        failures = RESOLVER.verify_protected_config_baseline(self.workspace)

        self.assertEqual(["protected config file is missing: guardrails.yaml"], failures)

    def test_protected_config_baseline_rejects_malformed_baseline(self):
        """A present but unreadable baseline is a failure, not a silent pass."""
        self.write_yaml("guardrails.yaml", "governance:\n  never: []\n")
        baseline_path = self.workspace / RESOLVER.PROTECTED_CONFIG_BASELINE_PATH
        baseline_path.parent.mkdir(parents=True, exist_ok=True)
        baseline_path.write_text("not json", encoding="utf-8")

        failures = RESOLVER.verify_protected_config_baseline(self.workspace)

        self.assertEqual(1, len(failures))
        self.assertIn("protected-config baseline could not be read", failures[0])

    def test_materialize_blocks_when_protected_config_tampered(self):
        """Verify materialize preserves the last valid snapshot on tamper."""
        self.write_yaml("guardrails.yaml", "governance:\n  never: []\n")
        self.write_protected_config_baseline()
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        snapshot_path = self.workspace / RESOLVER.SNAPSHOT_PATH
        previous_snapshot = snapshot_path.read_bytes()
        self.write_yaml("guardrails.yaml", "governance:\n  never: []\n  # tampered\n")

        materialized = RESOLVER.materialize(self.workspace)

        self.assertEqual("blocked", materialized["status"])
        self.assertIn("changed since installation", materialized["failures"][0])
        self.assertEqual(previous_snapshot, snapshot_path.read_bytes())

    def test_verify_setup_cache_is_stale_when_protected_config_tampered(self):
        """Verify a tampered protected file forces revalidation, not a cache hit."""
        self.write_yaml("guardrails.yaml", "governance:\n  never: []\n")
        self.write_protected_config_baseline()
        self.assertEqual("current", RESOLVER.materialize(self.workspace)["status"])
        self.write_yaml("guardrails.yaml", "governance:\n  never: []\n  # tampered\n")

        verified = RESOLVER.verify_setup_cache(self.workspace)

        self.assertEqual("stale", verified["status"])
        self.assertIn("changed since installation", verified["failures"][0])


if __name__ == "__main__":
    unittest.main()
