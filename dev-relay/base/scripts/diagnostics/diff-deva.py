#!/usr/bin/env python3
"""Deterministic reconciler core for the /diff-deva diagnostic command.

This is the thin, testable mechanics behind /diff-deva. It does ONLY the parts a
model does badly by hand and that must be reproducible:

  1. Parse the two heterogeneous trace formats:
       - a dry-run oracle trace  (`dry-run-*.trace.log`, from /dry-run-deva)
       - a real run activity log  (`activity.log`, from pipeline-session)
  2. Enforce the comparability gate on the run headers. The resolved
     config-fingerprint is the hard gate (a mismatch, or a value unestablishable
     on either side, refuses and stops); framework-version and session schema
     are advisory (a present-on-both mismatch still refuses, but a value absent
     on one side is only a warning, since real activity.logs carry no version
     and dry-run oracles persist no schema). Real-side comparability fields are
     backfilled from the run's paired session.md.
  3. Normalize both event streams into one common event algebra (the flow
     spine, plus optional side-effect predictions in `full` scope).
  4. Per-stage sequence-align (LCS) the two normalized spines and emit a
     machine-readable divergence table plus the earliest structural divergence.

Everything that needs judgement stays in the prompt (diff-deva.prompt.md):
classifying each divergence (real-bug / model-misprediction / design-violation /
explained-decision / no-oracle-coverage under instruction authority, or
implementation-drift / design-staleness under design authority), conformance
reasoning, and the written report. This core never mutates anything and never
emits a verdict about *why* a divergence exists — only *that* one exists and where.

Two authorities share these mechanics. Under the default *instruction authority*
(`retrospective`, `two-trace`, `conformance`) the oracle is a dry-run trace
interpreted from the runtime instructions at HEAD, and the config-fingerprint
gate is hard. Under *design authority* (`design-retrospective`,
`design-conformance`) the oracle is a design spine the prompt interprets from
`DESIGN-DEVA.md`; that spine carries no resolved config, so the fingerprint gate
relaxes to advisory (absent on the design side only warns; a present-on-both
mismatch still refuses). Alignment, normalization, and the event algebra are
identical across both authorities.

ROADMAP TODO (deferred, intentional): conformance today is judged by the prompt
against `guardrails.yaml`, `DESIGN-DEVA.md`, and the agent/skill files only. The
roadmap docs (`DESIGN-ROADMAP.md`, `DESIGN-ROADMAP-DETAILS.md`) are NOT yet a
normative conformance source. When they are promoted to normative, add their
digest to the conformance inputs (prompt) and, if a machine-readable roadmap
manifest is introduced, extend the comparability header fields below to include
its fingerprint. Leave this hook here until then.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Optional


SCHEMA_VERSION = 1

# --- Common event algebra -----------------------------------------------
# Spine token types shared by both trace formats. Alignment compares only
# (token_type, key); everything else (mode, reply text, outcome, timestamps)
# rides along as metadata for the model to judge.
RUN_START = "RUN_START"
STAGE_ENTER = "STAGE_ENTER"
HANDOFF_ENTER = "HANDOFF_ENTER"
HANDOFF_RETURN = "HANDOFF_RETURN"
CHECKPOINT_RESOLVED = "CHECKPOINT_RESOLVED"
MILESTONE = "MILESTONE"
RUN_COMPLETE = "RUN_COMPLETE"
BLOCK = "BLOCK"
SIDE_EFFECT = "SIDE_EFFECT"  # full scope only

SPINE_TYPES = frozenset(
    {
        RUN_START,
        STAGE_ENTER,
        HANDOFF_ENTER,
        HANDOFF_RETURN,
        CHECKPOINT_RESOLVED,
        MILESTONE,
        RUN_COMPLETE,
        BLOCK,
    }
)

# Comparability fields. config_fingerprint is the hard gate: it is the resolved
# config hash (encodes framework version + schema-affecting settings) and is the
# one field reliably reconstructable from real artifacts (oracle
# resolved-config-fingerprint vs session.md Configuration Fingerprint). It must
# match, and being unestablishable on either side refuses. framework_version and
# schema are advisory: real activity.logs never record a version, and dry-run
# oracles never persist a schema, so an unavailable value on one side is a
# warning, not a refusal -- but a genuine present-on-both mismatch still refuses.
# COMPARABILITY_FIELDS keeps a stable iteration order for the report.
HARD_COMPARABILITY_FIELDS = ("config_fingerprint",)
SOFT_COMPARABILITY_FIELDS = ("framework_version", "schema")
COMPARABILITY_FIELDS = ("framework_version", "config_fingerprint", "schema")


# --- Parsing -------------------------------------------------------------

# A real activity.log comes in two compatible shapes. Legacy lines carry an
# uppercase severity and an optional session tag:
#   <ts> [sess=<key>] <SEV> [<Component>] event=... kv...
# Current lines drop the severity and prefix a run-envelope tag instead:
#   <ts> [Run:<uuid>] [<Component>] event=... kv...
# Both the run tag, the session tag, and the severity are therefore optional;
# only the timestamp and a downstream event= field are required.
_REAL_LINE = re.compile(
    r"^(?P<ts>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)\s+"
    r"(?:\[Run:(?P<run>[^\]]+)\]\s+)?"
    r"(?:sess=(?P<sess>\S+)\s+)?"
    r"(?:(?P<sev>[A-Z]+)\s+)?"
    r"(?P<rest>.*)$"
)
_DRY_LINE = re.compile(
    r"^(?P<ts>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)\s+"
    r"(?P<sev>\S+)\s+(?P<event>\S+)\s+(?P<loc>\S+)\s+"
    r"\[(?P<ref>[^\]]*)\]\s+(?P<detail>.*?)(?:\s+::\s+reason=(?P<reason>.*))?$"
)
_KV = re.compile(r'([^\s=]+)=(?:"([^"]*)"|(\S+))')
_REAL_EVENT = re.compile(r"\bevent=(?P<event>\S+)")
_COMPONENT_TAG = re.compile(r"\[(?P<ctype>Agent|Stage|Subagent|Checkpoint):(?P<cname>[^\]]+)\]")
_VERSION_TOKEN = re.compile(r"(\d+\.\d+\.\d+(?:[-.][0-9A-Za-z]+)*)")
_SHA_TOKEN = re.compile(r"(?<![0-9a-f])([0-9a-f]{64})(?![0-9a-f])")
_SHA256 = re.compile(r"[0-9a-f]{64}")
_ORACLE_DISPOSITION = re.compile(r"registered\s+(?:\S+\s+)?(advance|revise)")
_ORACLE_REPLY = re.compile(r"reply\s+[\"']([^\"']*)[\"']")
_ORACLE_HANDOFF = re.compile(r"^(?:(?:enter|return)\s+)?([A-Za-z0-9._-]+)")
_ORACLE_MODE = re.compile(r"mode=([A-Za-z0-9._-]+)")


class TraceParseError(ValueError):
    """Raised when an input trace does not follow its canonical grammar."""


def _parse_kv(rest: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for match in _KV.finditer(rest):
        key = match.group(1)
        if key in out:
            raise TraceParseError(f"duplicate key in activity log line: {key}")
        out[key] = match.group(2) if match.group(2) is not None else match.group(3)
    return out


def parse_real_log(text: str) -> tuple[dict[str, str], list[dict[str, Any]]]:
    """Parse a real ``activity.log`` into a header dict and ordered events."""
    header: dict[str, str] = {}
    events: list[dict[str, Any]] = []
    for index, raw in enumerate(text.splitlines()):
        line = raw.rstrip()
        if not line.strip():
            continue
        match = _REAL_LINE.match(line)
        if not match:
            raise TraceParseError(f"activity log line {index + 1} is malformed")
        rest = match.group("rest")
        event_match = _REAL_EVENT.search(rest)
        if not event_match:
            raise TraceParseError(
                f"activity log line {index + 1} has no event field"
            )
        event_name = event_match.group("event")
        component = _COMPONENT_TAG.search(rest)
        ctype = component.group("ctype") if component else None
        cname = component.group("cname") if component else None
        kv = _parse_kv(rest)
        event = {
            "seq": index,
            "ts": match.group("ts"),
            "sev": match.group("sev"),
            "event": event_name,
            "stage": cname if ctype == "Stage" else kv.get("stage"),
            "cx": cname if ctype == "Checkpoint" else kv.get("checkpoint"),
            "component_type": ctype,
            "subagent": cname if ctype == "Subagent" else kv.get("subagent"),
            "kv": kv,
            "raw": line,
        }
        events.append(event)
        if event_name == "run_start":
            if "schema" in kv:
                header["schema"] = kv["schema"]
            if "mode" in kv:
                header["mode"] = kv["mode"]
            if "jira" in kv:
                header["jira"] = kv["jira"]
    return header, events


def select_real_run(
    text: str, run_number: Optional[int]
) -> tuple[dict[str, str], list[dict[str, Any]], int, int]:
    """Select one complete 1-based run envelope from an append-only activity log."""
    _, events = parse_real_log(text)
    if not any(event["event"] == "run_start" for event in events):
        raise TraceParseError("activity log has no RUN_START event")

    # Segment into run envelopes. A run_start that appears while the current
    # envelope is still open is a resume of that run, not a new envelope, so it
    # is folded in; a new envelope begins only after a completion event.
    runs: list[list[dict[str, Any]]] = []
    current: list[dict[str, Any]] = []
    current_completed = False
    for event in events:
        name = event["event"]
        if name == "run_start":
            if current and current_completed:
                runs.append(current)
                current = [event]
                current_completed = False
            elif current:
                current.append(event)
            else:
                current = [event]
                current_completed = False
            continue
        if not current:
            continue
        current.append(event)
        if name in ("run_complete", "run_archived"):
            current_completed = True
    if current:
        runs.append(current)

    for position, run in enumerate(runs):
        completions = [
            index
            for index, event in enumerate(run)
            if event["event"] in ("run_complete", "run_archived")
        ]
        if len(completions) != 1 or completions[0] != len(run) - 1:
            raise TraceParseError(
                f"activity log run {position + 1} is incomplete or has events after completion"
            )

    if run_number is None:
        if len(runs) != 1:
            raise TraceParseError(
                f"activity log contains {len(runs)} completed runs; pass --real-run 1..{len(runs)}"
            )
        selected = 1
    else:
        if run_number < 1 or run_number > len(runs):
            raise TraceParseError(
                f"--real-run must be between 1 and {len(runs)}"
            )
        selected = run_number

    selected_events = runs[selected - 1]
    start_fields = selected_events[0]["kv"]
    header = {
        key: start_fields[key]
        for key in ("schema", "mode", "jira")
        if key in start_fields
    }
    return header, selected_events, selected, len(runs)


def parse_dry_run(text: str) -> tuple[dict[str, str], list[dict[str, Any]]]:
    """Parse a dry-run oracle trace into a header dict and ordered events."""
    header: dict[str, str] = {}
    events: list[dict[str, Any]] = []
    for index, raw in enumerate(text.splitlines()):
        line = raw.rstrip()
        if not line.strip():
            continue
        if line.startswith("#"):
            body = line.lstrip("#").strip()
            if ":" in body:
                key, _, value = body.partition(":")
                header[key.strip()] = value.strip()
            continue
        match = _DRY_LINE.match(line)
        if not match:
            raise TraceParseError(f"dry-run trace line {index + 1} is malformed")
        loc = match.group("loc")
        parts = loc.split("/")
        stage = parts[0] if parts else None
        cx = None
        for part in parts[1:]:
            if re.match(r"^C\d", part):
                cx = part
        events.append(
            {
                "seq": index,
                "ts": match.group("ts"),
                "sev": match.group("sev"),
                "event": match.group("event"),
                "stage": stage,
                "cx": cx,
                "ref": match.group("ref"),
                "detail": match.group("detail"),
                "reason": match.group("reason") or "",
                "raw": line,
            }
        )
    return header, events


def require_run_start(tokens: list[dict[str, Any]], source: str) -> None:
    """Require the opening structural marker shared by every canonical trace."""
    if not any(token["type"] == RUN_START for token in tokens):
        raise TraceParseError(f"{source} has no RUN_START event")


# --- Header field extraction ---------------------------------------------

def oracle_header_fields(header: dict[str, str]) -> dict[str, Optional[str]]:
    """Pull comparability fields from a dry-run trace header."""
    version = None
    raw_version = header.get("framework-version", "")
    match = _VERSION_TOKEN.search(raw_version)
    if match:
        version = match.group(1)
    fingerprint = None
    # Prefer the standalone "resolved-config-fingerprint" header line, then a
    # legacy inline "... / resolved <sha>", then the raw fingerprint value.
    resolved_line = header.get("resolved-config-fingerprint")
    raw_fp = header.get("config-fingerprint (observed read-only)") or header.get(
        "config-fingerprint"
    )
    if resolved_line:
        token = _SHA_TOKEN.search(resolved_line)
        fingerprint = token.group(1) if token else None
    elif raw_fp:
        resolved = re.search(r"resolved\s+([0-9a-f]{6,64})", raw_fp)
        if resolved:
            fingerprint = resolved.group(1)
        else:
            token = _SHA_TOKEN.search(raw_fp)
            fingerprint = token.group(1) if token else None
    return {
        "framework_version": version,
        "config_fingerprint": fingerprint,
        "schema": header.get("schema"),
    }


def real_header_fields(header: dict[str, str]) -> dict[str, Optional[str]]:
    """Pull comparability fields from a real activity.log header."""
    return {
        "framework_version": header.get("framework_version"),
        "config_fingerprint": header.get("config_fingerprint"),
        "schema": header.get("schema"),
    }


# The real activity.log carries no comparability header, so the real-side fields
# are backfilled from the run's paired session.md (labels: Framework-Version,
# Configuration Fingerprint, Schema).
_SESSION_SCHEMA = re.compile(r"^\s*[-*]?\s*Schema\s*:\s*(\S+)", re.MULTILINE | re.IGNORECASE)
_SESSION_FP = re.compile(
    r"^\s*[-*]?\s*Config(?:uration)?[ -]?Fingerprint\s*:\s*((?-i:[0-9a-f]{64}))\s*$",
    re.MULTILINE | re.IGNORECASE,
)
_SESSION_VERSION = re.compile(
    r"^\s*[-*]?\s*Framework[ -]?Version\s*:\s*(\S+)", re.MULTILINE | re.IGNORECASE
)


def session_md_fields(text: str) -> dict[str, Optional[str]]:
    """Pull comparability fields from a run's session.md header."""
    schema = _SESSION_SCHEMA.search(text)
    fingerprint = _SESSION_FP.search(text)
    version = _SESSION_VERSION.search(text)
    return {
        "framework_version": version.group(1) if version else None,
        "config_fingerprint": fingerprint.group(1) if fingerprint else None,
        "schema": schema.group(1) if schema else None,
    }


def discover_session_md(real_path: Path) -> Optional[Path]:
    """Locate the session.md paired with a real activity.log.

    Checks a sibling session.md first (canonical cache/sessions/<KEY>/ and
    archived artifacts/sessions/<KEY>/ layouts keep them together), then only
    the canonical stores under the same repository's .github root.
    """
    resolved_real = real_path.resolve()
    github_root = next(
        (parent for parent in (resolved_real.parent, *resolved_real.parents) if parent.name == ".github"),
        None,
    )
    if github_root is None:
        return None

    key = resolved_real.parent.name
    candidates = [
        resolved_real.with_name("session.md"),
        github_root / "artifacts" / "sessions" / key / "session.md",
        github_root / "cache" / "sessions" / key / "session.md",
    ]
    for candidate in candidates:
        resolved_candidate = candidate.resolve()
        try:
            resolved_candidate.relative_to(github_root)
        except ValueError:
            continue
        if resolved_candidate.is_file():
            return resolved_candidate
    return None


def _apply_overrides(
    fields: dict[str, Optional[str]], overrides: dict[str, Optional[str]]
) -> dict[str, Optional[str]]:
    merged = dict(fields)
    for key, value in overrides.items():
        if value is not None:
            if key == "framework_version" and _VERSION_TOKEN.search(value):
                merged[key] = _VERSION_TOKEN.search(value).group(1)
            elif key == "config_fingerprint":
                merged[key] = value if _SHA256.fullmatch(value) else None
            else:
                merged[key] = value
    return merged


def comparability(
    oracle_fields: dict[str, Optional[str]],
    real_fields: dict[str, Optional[str]],
    hard_fields: tuple[str, ...] = HARD_COMPARABILITY_FIELDS,
) -> dict[str, Any]:
    """Comparability gate: config_fingerprint hard, version/schema advisory.

    Comparable when config_fingerprint is present on both sides and equal and no
    advisory field is a present-on-both mismatch. A hard field unavailable on
    either side, or any present-on-both mismatch (hard or soft), refuses. An
    advisory field unavailable on one side is recorded as a warning, not a
    refusal. Under design authority ``hard_fields`` is empty, so an absent
    config-fingerprint on the design side only warns while a present-on-both
    mismatch still refuses.
    """
    field_report: dict[str, Any] = {}
    verdict = "comparable"
    reasons: list[str] = []
    warnings: list[str] = []
    for field in COMPARABILITY_FIELDS:
        oracle_value = oracle_fields.get(field)
        real_value = real_fields.get(field)
        if field == "config_fingerprint":
            oracle_value = oracle_value if oracle_value and _SHA256.fullmatch(oracle_value) else None
            real_value = real_value if real_value and _SHA256.fullmatch(real_value) else None
        hard = field in hard_fields
        if oracle_value is not None and real_value is not None and oracle_value != real_value:
            status = "mismatch"
            verdict = "refused"
            reasons.append(f"{field}: oracle={oracle_value} vs real={real_value}")
        elif oracle_value is None or real_value is None:
            status = "unavailable"
            missing = []
            if oracle_value is None:
                missing.append("oracle")
            if real_value is None:
                missing.append("real")
            note = f"{field}: unavailable on {', '.join(missing)}"
            if hard:
                verdict = "refused"
                reasons.append(note)
            else:
                warnings.append(note)
        else:
            status = "match"
        field_report[field] = {
            "oracle": oracle_value,
            "real": real_value,
            "status": status,
        }
    return {
        "verdict": verdict,
        "fields": field_report,
        "reason": "; ".join(reasons),
        "warnings": warnings,
    }


# --- Normalization to the common algebra ---------------------------------

def _token(
    token_type: str,
    key: list[Any],
    source: dict[str, Any],
    token_class: str = "spine",
    **meta: Any,
) -> dict[str, Any]:
    # RUN_START / RUN_COMPLETE are run-level markers; MILESTONE and
    # CHECKPOINT_RESOLVED are keyed by a globally-unique checkpoint id: keep
    # them stage-agnostic so the two spines pair in the shared "(run)" bucket
    # regardless of the loc column a dry-run prints them against. Shared gates
    # (e.g. C4 spanning qa+tests, emitted with plural stages=) otherwise split.
    stage = None if token_type in (RUN_START, RUN_COMPLETE, MILESTONE, CHECKPOINT_RESOLVED) else source.get("stage")
    return {
        "type": token_type,
        "key": key,
        "class": token_class,
        "stage": stage,
        "cx": source.get("cx"),
        "seq": source.get("seq"),
        "ts": source.get("ts"),
        "source_ref": source.get("ref") or source.get("event"),
        "raw": source.get("raw"),
        "meta": {k: v for k, v in meta.items() if v is not None},
    }


def normalize_real(events: list[dict[str, Any]]) -> list[dict[str, Any]]:
    tokens: list[dict[str, Any]] = []
    for event in events:
        name = event["event"]
        kv = event["kv"]
        stage = event.get("stage")
        cx = event.get("cx")
        ctype = event.get("component_type")
        role = event.get("subagent")
        reply = kv.get("decision") or kv.get("decision-reply") or kv.get("decision_reply")
        if name == "run_start":
            tokens.append(_token(RUN_START, [], event, mode=kv.get("mode"), schema=kv.get("schema")))
        elif name == "handoff_start" or (name == "enter" and ctype == "Subagent"):
            tokens.append(
                _token(HANDOFF_ENTER, [stage, role], event, role=role, mode=kv.get("mode"))
            )
        elif name == "enter":
            if not stage:
                raise TraceParseError(
                    f"activity log line {event['seq'] + 1} has a stage enter without a stage"
                )
            tokens.append(_token(STAGE_ENTER, [stage], event, owner=kv.get("owner"), note=kv.get("note")))
        elif name in ("handoff_complete", "handoff_return", "handoff_end") or (name == "return" and ctype == "Subagent"):
            tokens.append(
                _token(HANDOFF_RETURN, [stage, role], event, role=role, outcome=kv.get("outcome"), note=kv.get("note"))
            )
        elif name in ("approved", "checkpoint_approved"):
            tokens.append(
                _token(CHECKPOINT_RESOLVED, [cx], event, disposition="advance", reply=reply)
            )
        elif name in ("rejected", "checkpoint_rejected"):
            tokens.append(
                _token(CHECKPOINT_RESOLVED, [cx], event, disposition="revise", reply=reply)
            )
        elif name == "milestone_posted":
            tokens.append(_token(MILESTONE, [cx], event))
        elif name in ("run_complete", "run_archived"):
            tokens.append(_token(RUN_COMPLETE, [], event))
        elif name == "blocked":
            tokens.append(_token(BLOCK, [stage or cx], event, note=kv.get("note") or kv.get("reason")))
        elif name == "side_effect":
            operation = kv.get("operation")
            tokens.append(
                _token(SIDE_EFFECT, [operation], event, token_class="side_effect", operation=operation, status=kv.get("status"))
            )
    return _dedupe_stage_enter(tokens)


def normalize_oracle(events: list[dict[str, Any]]) -> list[dict[str, Any]]:
    tokens: list[dict[str, Any]] = []
    handoff_roles: dict[Any, list[Any]] = {}
    for event in events:
        name = event["event"]
        ref = event.get("ref", "")
        detail = event.get("detail", "")
        stage = event.get("stage")
        cx = event.get("cx")
        if name == "WOULD-MUTATE" and ":init" in ref:
            tokens.append(_token(RUN_START, [], event))
        elif name == "WOULD-MUTATE" and "mark-in-progress" in ref:
            tokens.append(_token(STAGE_ENTER, [stage], event))
        elif name == "WOULD-MUTATE" and "Milestone-ID" in detail and cx:
            # The milestone post is the real MILESTONE analog (one per
            # checkpoint). approve-checkpoint is the separate session-persist
            # step and falls through to the side-effect branch; mapping it to
            # MILESTONE would double-count a shared gate (e.g. C4 spanning
            # qa+tests persists per stage but posts a single milestone).
            tokens.append(_token(MILESTONE, [cx], event))
        elif name == "WOULD-MUTATE":
            # Any other suppressed mutation is a side-effect prediction (full scope).
            signature = ref or detail.split()[0] if detail else ref
            tokens.append(_token(SIDE_EFFECT, [signature], event, token_class="side_effect", detail=detail))
        elif name == "HANDOFF":
            stripped = detail.strip()
            is_return = stripped.startswith("return")
            role_match = _ORACLE_HANDOFF.match(stripped)
            parsed_role = role_match.group(1) if role_match else None
            mode_match = _ORACLE_MODE.search(detail)
            mode = mode_match.group(1) if mode_match else None
            if is_return:
                # A drifted return line may carry a payload word where the
                # specialist name belongs; pair it with the matching enter.
                pending = handoff_roles.get(stage)
                role = pending.pop() if pending else parsed_role
                token_type = HANDOFF_RETURN
            else:
                role = parsed_role
                handoff_roles.setdefault(stage, []).append(role)
                token_type = HANDOFF_ENTER
            tokens.append(_token(token_type, [stage, role], event, role=role, mode=mode))
        elif name == "DECISION" and cx:
            # Only a decision carrying a gate disposition ("... == registered Cx
            # advance/revise choice") is a checkpoint resolution. Other decisions
            # logged at a checkpoint loc (e.g. a prior-art reuse call) are
            # intermediate reasoning -- the real activity.log emits no spine
            # token for them, so neither do we.
            disposition_match = _ORACLE_DISPOSITION.search(detail)
            if disposition_match:
                reply_match = _ORACLE_REPLY.search(detail)
                tokens.append(
                    _token(
                        CHECKPOINT_RESOLVED,
                        [cx],
                        event,
                        disposition=disposition_match.group(1),
                        reply=reply_match.group(1) if reply_match else None,
                    )
                )
        elif name == "BLOCK":
            tokens.append(_token(BLOCK, [stage or cx], event, detail=detail))
        elif name == "SUMMARY":
            tokens.append(_token(RUN_COMPLETE, [], event))
    return _dedupe_stage_enter(tokens)


def _dedupe_stage_enter(tokens: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Keep only the first STAGE_ENTER per stage; leave every other token."""
    seen: set[Any] = set()
    out: list[dict[str, Any]] = []
    for token in tokens:
        if token["type"] == STAGE_ENTER:
            stage_key = tuple(token["key"])
            if stage_key in seen:
                continue
            seen.add(stage_key)
        out.append(token)
    return out


# --- Alignment -----------------------------------------------------------

def _align_id(token: dict[str, Any]) -> tuple:
    return (token["type"], *[str(part) for part in token["key"]])


def align(oracle: list[dict[str, Any]], real: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Longest-common-subsequence alignment producing ordered rows.

    Each row is one of: ``match`` (present and equal on both spines),
    ``oracle_only`` (predicted but not observed), or ``real_only`` (observed but
    not predicted). Order follows the merged sequence.
    """
    oracle_ids = [_align_id(token) for token in oracle]
    real_ids = [_align_id(token) for token in real]
    rows_o, cols_r = len(oracle), len(real)
    table = [[0] * (cols_r + 1) for _ in range(rows_o + 1)]
    for i in range(rows_o - 1, -1, -1):
        for j in range(cols_r - 1, -1, -1):
            if oracle_ids[i] == real_ids[j]:
                table[i][j] = table[i + 1][j + 1] + 1
            else:
                table[i][j] = max(table[i + 1][j], table[i][j + 1])
    rows: list[dict[str, Any]] = []
    i = j = 0
    while i < rows_o and j < cols_r:
        if oracle_ids[i] == real_ids[j]:
            rows.append(_row("match", oracle[i], real[j]))
            i += 1
            j += 1
        elif table[i + 1][j] >= table[i][j + 1]:
            rows.append(_row("oracle_only", oracle[i], None))
            i += 1
        else:
            rows.append(_row("real_only", None, real[j]))
            j += 1
    while i < rows_o:
        rows.append(_row("oracle_only", oracle[i], None))
        i += 1
    while j < cols_r:
        rows.append(_row("real_only", None, real[j]))
        j += 1
    return rows


def _row(status: str, oracle: Optional[dict], real: Optional[dict]) -> dict[str, Any]:
    reference = oracle or real
    return {
        "status": status,
        "type": reference["type"],
        "key": reference["key"],
        "class": reference["class"],
        "oracle": oracle,
        "real": real,
    }


def _ordered_stages(oracle: list[dict[str, Any]], real: list[dict[str, Any]]) -> list[str]:
    order: list[str] = []
    for token in list(real) + list(oracle):
        stage = token.get("stage") or "(run)"
        if stage not in order:
            order.append(stage)
    return order


def reconcile(
    oracle_tokens: list[dict[str, Any]],
    real_tokens: list[dict[str, Any]],
    scope: str,
) -> dict[str, Any]:
    """Align global stage order and per-stage spines; report first divergence."""
    if scope == "flow":
        oracle_tokens = [t for t in oracle_tokens if t["type"] in SPINE_TYPES]
        real_tokens = [t for t in real_tokens if t["type"] in SPINE_TYPES]
    # HANDOFF_RETURN is comparable only when both spines model returns. A dry-run
    # oracle records handoff enters but never completions, so if either side
    # emits no returns, every real return is spurious "real_only" noise: drop
    # HANDOFF_RETURN from both spines and surface the uncompared count instead.
    oracle_returns = sum(1 for t in oracle_tokens if t["type"] == HANDOFF_RETURN)
    real_returns = sum(1 for t in real_tokens if t["type"] == HANDOFF_RETURN)
    handoff_returns_uncompared = 0
    if oracle_returns == 0 or real_returns == 0:
        handoff_returns_uncompared = oracle_returns + real_returns
        oracle_tokens = [t for t in oracle_tokens if t["type"] != HANDOFF_RETURN]
        real_tokens = [t for t in real_tokens if t["type"] != HANDOFF_RETURN]
    stage_order_rows = align(
        [token for token in oracle_tokens if token["type"] == STAGE_ENTER],
        [token for token in real_tokens if token["type"] == STAGE_ENTER],
    )
    stages_out: list[dict[str, Any]] = []
    divergence_candidates: list[tuple[float, int, int, str, dict[str, Any]]] = []
    for row_index, row in enumerate(stage_order_rows):
        if row["status"] == "match":
            continue
        source_sequences = [
            token.get("seq")
            for token in (row["oracle"], row["real"])
            if token is not None and isinstance(token.get("seq"), int)
        ]
        source_sequence = min(source_sequences) if source_sequences else float("inf")
        reference = row["oracle"] or row["real"]
        stage = reference["key"][0]
        divergence_candidates.append((source_sequence, -1, row_index, stage, row))
    for stage in _ordered_stages(oracle_tokens, real_tokens):
        stage_oracle = [t for t in oracle_tokens if (t.get("stage") or "(run)") == stage]
        stage_real = [t for t in real_tokens if (t.get("stage") or "(run)") == stage]
        rows = align(stage_oracle, stage_real)
        stages_out.append({"stage": stage, "rows": rows})
        for row_index, row in enumerate(rows):
            if row["status"] == "match":
                continue
            source_sequences = [
                token.get("seq")
                for token in (row["oracle"], row["real"])
                if token is not None and isinstance(token.get("seq"), int)
            ]
            source_sequence = min(source_sequences) if source_sequences else float("inf")
            divergence_candidates.append(
                (source_sequence, len(stages_out) - 1, row_index, stage, row)
            )
    first_divergence: Optional[dict[str, Any]] = None
    if divergence_candidates:
        _, _, _, stage, row = min(divergence_candidates)
        first_divergence = {
            "stage": stage,
            "status": row["status"],
            "type": row["type"],
            "key": row["key"],
        }
    oracle_end = oracle_tokens[-1] if oracle_tokens else None
    real_end = real_tokens[-1] if real_tokens else None
    return {
        "stage_order": stage_order_rows,
        "stages": stages_out,
        "first_divergence": first_divergence,
        "handoff_returns_uncompared": handoff_returns_uncompared,
        "oracle_last": {"type": oracle_end["type"], "stage": oracle_end.get("stage"), "cx": oracle_end.get("cx")}
        if oracle_end
        else None,
        "real_last": {"type": real_end["type"], "stage": real_end.get("stage"), "cx": real_end.get("cx")}
        if real_end
        else None,
    }


# --- CLI -----------------------------------------------------------------

def build_report(args: argparse.Namespace) -> tuple[dict[str, Any], int]:
    report: dict[str, Any] = {
        "schema": SCHEMA_VERSION,
        "mode": args.mode,
        "scope": args.scope,
    }
    oracle_text = Path(args.oracle).read_text(encoding="utf-8")
    try:
        oracle_header, oracle_events = parse_dry_run(oracle_text)
        oracle_tokens = normalize_oracle(oracle_events)
        require_run_start(oracle_tokens, "dry-run trace")
    except TraceParseError as error:
        report["error"] = str(error)
        return report, 2
    oracle_fields = _apply_overrides(
        oracle_header_fields(oracle_header),
        {
            "framework_version": args.oracle_version,
            "config_fingerprint": args.oracle_fingerprint,
            "schema": args.oracle_schema,
        },
    )
    report["oracle_fields"] = oracle_fields

    if args.mode in ("conformance", "design-conformance"):
        # No real run to align against; hand the normalized oracle spine to the
        # prompt. Under instruction authority it judges the spine against the
        # runtime instructions; under design authority (design-conformance) it
        # judges the spine against DESIGN-DEVA.md.
        report["comparability"] = {
            "verdict": "not-applicable",
            "fields": {},
            "reason": f"{args.mode} mode: no real run",
        }
        report["oracle_spine"] = [
            t for t in oracle_tokens if args.scope == "full" or t["type"] in SPINE_TYPES
        ]
        return report, 0

    if not args.real:
        report["error"] = (
            "modes retrospective, two-trace, and design-retrospective require "
            "--real <activity.log>"
        )
        return report, 2

    real_path = Path(args.real)
    real_text = real_path.read_text(encoding="utf-8")
    try:
        real_header, real_events, selected_run, run_count = select_real_run(
            real_text, args.real_run
        )
        real_tokens = normalize_real(real_events)
        require_run_start(real_tokens, "activity log")
    except TraceParseError as error:
        report["error"] = str(error)
        return report, 2
    report["real_run"] = {"selected": selected_run, "count": run_count}
    real_fields = real_header_fields(real_header)
    # activity.log has no comparability header; backfill from the paired
    # session.md before applying explicit CLI overrides (which always win).
    session_path = Path(args.real_session) if args.real_session else discover_session_md(real_path)
    if session_path and session_path.is_file():
        report["real_session_md"] = str(session_path)
        for key, value in session_md_fields(session_path.read_text(encoding="utf-8")).items():
            if value is not None and real_fields.get(key) is None:
                real_fields[key] = value
    real_fields = _apply_overrides(
        real_fields,
        {
            "framework_version": args.real_version,
            "config_fingerprint": args.real_fingerprint,
            "schema": args.real_schema,
        },
    )
    report["real_fields"] = real_fields

    # Design authority relaxes the config-fingerprint gate to advisory: a design
    # spine carries no resolved config, so its absence only warns.
    hard_fields = () if args.mode == "design-retrospective" else HARD_COMPARABILITY_FIELDS
    gate = comparability(oracle_fields, real_fields, hard_fields)
    report["comparability"] = gate
    if gate["verdict"] == "refused":
        # Hard refuse: do nothing else. Same-version runs only.
        return report, 3

    report.update(reconcile(oracle_tokens, real_tokens, args.scope))
    return report, 0


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Deterministic reconciler core for /diff-deva (parse, gate, align)."
    )
    parser.add_argument("--oracle", required=True, help="Dry-run oracle trace (dry-run-*.trace.log).")
    parser.add_argument("--real", help="Real run activity.log (retrospective/two-trace modes).")
    parser.add_argument(
        "--mode",
        choices=[
            "retrospective",
            "two-trace",
            "conformance",
            "design-retrospective",
            "design-conformance",
        ],
        default="retrospective",
    )
    parser.add_argument("--scope", choices=["flow", "full"], default="flow")
    parser.add_argument("--oracle-version", dest="oracle_version")
    parser.add_argument("--oracle-fingerprint", dest="oracle_fingerprint")
    parser.add_argument("--oracle-schema", dest="oracle_schema")
    parser.add_argument("--real-version", dest="real_version")
    parser.add_argument("--real-fingerprint", dest="real_fingerprint")
    parser.add_argument("--real-schema", dest="real_schema")
    parser.add_argument(
        "--real-run",
        dest="real_run",
        type=int,
        help="1-based completed run envelope to compare; required when activity.log contains multiple runs.",
    )
    parser.add_argument(
        "--real-session",
        dest="real_session",
        help="Explicit session.md for real-side comparability fields (else auto-discovered next to --real).",
    )
    args = parser.parse_args(argv)

    try:
        report, code = build_report(args)
    except FileNotFoundError as error:
        print(json.dumps({"schema": SCHEMA_VERSION, "error": f"file not found: {error.filename}"}))
        return 2
    except (OSError, UnicodeError) as error:
        print(json.dumps({"schema": SCHEMA_VERSION, "error": f"cannot read diagnostic input: {error}"}))
        return 2
    print(json.dumps(report, indent=2, sort_keys=True))
    return code


if __name__ == "__main__":
    sys.exit(main())
