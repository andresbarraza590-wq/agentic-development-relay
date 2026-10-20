---
name: configuration-resolution
description: "Resolve and validate runtime pipeline configuration. Use when Setup Validator materializes the canonical default/team deep merge, or when a consumer verifies and reads the resolved configuration snapshot."
---

# Configuration Resolution

Own the deterministic runtime resolution of pipeline configuration. Setup Validator is the only snapshot writer; every other agent and skill is a read-only consumer.

## Modes

- **`materialize`** — validate the sources, resolve them, and atomically publish the snapshot. Only Setup Validator may use this mode. Blocks without publishing when `default-config.yaml` or `guardrails.yaml` no longer matches the installer-recorded protected-config baseline.
- **`verify`** — validate the snapshot envelope and compare its source fingerprint with the current source files. Never write in this mode.
- **`read`** — run `verify`, then return the requested configuration section. Never return a section from an invalid or stale snapshot.
- **`verify-setup-cache`** — run `verify`, then validate the setup report's PASS marker, UTC age, and configured input fingerprint. Also re-checks the protected-config baseline on every call, so a cache hit can never mask a post-install change to either protected file; a mismatch returns `stale` instead of `current`, forcing Setup Validator to re-materialize (which then blocks with the exact tamper detail). Never write in this mode.

## Executable

Run the installed resolver from the workspace root:

```powershell
python .github/scripts/configuration/resolve-config.py materialize
python .github/scripts/configuration/resolve-config.py verify
python .github/scripts/configuration/resolve-config.py read story_refinement
python .github/scripts/configuration/resolve-config.py verify-setup-cache
```

The script is the sole implementation of parsing, validation, merge, hashing, and publication. Do not reproduce those operations in model reasoning or shell snippets. It emits JSON and exits `0` only for `status: current`; all other statuses exit `2`. PyYAML is declared in `.github/scripts/requirements.txt`; a missing dependency is a setup blocker.

## Canonical Paths

- Baseline: `.github/config/default-config.yaml`
- Optional team delta: `.github/config/team-config.yaml`
- Resolved snapshot: `.github/cache/config/resolved-config.json`
- Governance: `.github/config/guardrails.yaml` (separate; never merged into the snapshot)
- Protected-config baseline: `.github/cache/config/protected-config-baseline.json` — installer-recorded SHA-256 of `default-config.yaml` and `guardrails.yaml`, written once per base install and never touched afterward; its absence is not itself a failure (a workspace installed before this check existed), but a present baseline that no longer matches either file's bytes always blocks.

Resolve every path from the workspace root. The snapshot is workspace-scoped, not Jira-scoped, and must never be stored in a story session.

## Resolution Contract

1. Parse YAML with a structured YAML parser. Do not merge YAML as text.
2. Require the baseline document to exist and require both source roots, when present, to be mappings.
3. If the team delta is absent, resolve the baseline alone and record the source as absent. Absence is not an error.
4. Recursively merge mapping keys. An unspecified baseline key survives.
5. A team scalar replaces the baseline scalar only when both values have compatible types and the path is permitted.
6. A team sequence replaces the baseline sequence. Never concatenate sequences implicitly; additive behavior must use an explicit extension key such as `mcp_servers.additional`.
7. A key present only in the team delta is added unless the path is protected.
8. Reject a mapping/scalar/sequence type conflict rather than guessing intent. Reject a null team value when it would erase a non-null baseline value.
9. Reject `governance`, `pipeline`, and `config_resolution` anywhere in the team delta. Governance and the pipeline registry remain owned by `.github/config/guardrails.yaml`; resolver behavior remains owned by the base.
10. Under `mcp_servers`, permit team additions only through `mcp_servers.additional`; reject replacement of baseline server entries.
11. Reject a team value that lowers `story_refinement.pass_threshold` below the baseline. A team may keep or raise it.
12. Do not infer repository membership from configuration. When `routing_repos.inventory_file` is configured, the referenced inventory remains the sole membership source.

Any validation or merge failure blocks materialization. Preserve the last valid snapshot for diagnostics, but do not report it as current and do not publish a replacement.

Materialization holds one process-safe, workspace-scoped publication lock from the initial source read through canonical replacement and final source verification. An overlapping writer returns `blocked` without changing the snapshot. Before replacing an existing generation, durably preserve its exact bytes at `.github/cache/config/resolved-config.prior.json`; refuse another publication while that recovery file is unresolved. Verify the source bundle immediately before and after atomic replacement. Post-publication drift atomically moves the recovery file back to the canonical path (or removes an invalid first publication) before returning `blocked`. Delete the recovery file only after the candidate verifies or rollback succeeds; if rollback fails, retain the prior bytes there and return an explicit recovery blocker.

## Source Fingerprint

Compute `source_fingerprint` from these ordered paths:

1. `.github/config/default-config.yaml`
2. `.github/config/team-config.yaml`

For each path, append an 8-byte big-endian path length, its normalized `/` path encoded as UTF-8, a one-byte presence marker, an 8-byte big-endian content length, and its raw bytes when present. An absent file uses presence marker `0` and zero content length; a present file uses marker `1`, including when it is empty. SHA-256 hash the combined byte stream and render lowercase hexadecimal.

For each source, also record its individual lowercase SHA-256 hash. Use `null` when the optional source is absent.

## Snapshot Schema

Publish UTF-8 JSON with this envelope:

```json
{
  "schema_version": 1,
  "generated_at": "2026-01-01T12:00:00Z",
  "source_fingerprint": "<lowercase-sha256>",
  "sources": [
    {
      "path": ".github/config/default-config.yaml",
      "present": true,
      "sha256": "<lowercase-sha256>"
    },
    {
      "path": ".github/config/team-config.yaml",
      "present": false,
      "sha256": null
    }
  ],
  "config": {}
}
```

`generated_at` is a UTC ISO-8601 timestamp. `config` is the resolved mapping. Serialize object keys in stable lexical order so identical inputs produce equivalent configuration content; timestamp differences do not affect freshness.

## Materialize Procedure

1. Run `python .github/scripts/configuration/resolve-config.py materialize` from the workspace root.
2. Parse the JSON result and require exit code `0` with `status: current`.
3. Treat any other exit code or status as a blocker and report its `failures`.

Do not publish a PASS setup report unless materialization and read-back verification both succeed.

## Verify and Read Procedure

1. Run the executable in `verify` mode, or in `read <dotted-section>` mode for a named value.
2. Parse the JSON result and require exit code `0` with `status: current`.
3. On `missing`, `malformed`, `stale`, or `blocked`, stop and direct the developer to select **Do It** in the Chat agent/mode picker and choose option 1, **Validate my environment**. Never fall back to reading or merging the YAML sources in a consumer.
4. In `read` mode, consume only the returned `value`. A missing requested key is a configuration error; never invent a default.

In `verify-setup-cache` mode, the executable additionally requires:

1. `.github/cache/sessions/setup-validation.md` contains canonical `Result: PASS` or legacy `Result: ✅ PASS`;
2. `Validated-At` is valid UTC and no older than `setup_validation.cache_ttl_hours`;
3. `Config-Fingerprint` matches the ordered `setup_validation.fingerprint_inputs` fingerprint;
4. exactly one `MCP-Probe: <name>=<PASS|FAILED>` line exists for every configured MCP server, with no unknown or duplicate names, and every server configured with `required: true` records `PASS`;
5. `Jira-Probe` records `getJiraInstancesAndProjectsForCurrentUser=PASS (readable project visible)`; and
6. `GT-Assist-Probe` records one valid attempted catalog/query sequence from the Setup Validator method-level evidence gate.

The setup-input fingerprint uses the same length-delimited path, explicit presence marker, length-delimited content encoding in configured order, then computes lowercase SHA-256. A missing, malformed, expired, future-dated, or mismatched report returns `stale`. Missing, duplicate, unknown, or `NOT_PROBED` MCP evidence; a failed required MCP probe; Jira registration-only evidence; an omitted <INTERNAL_KNOWLEDGE_ASSISTANT> call; or malformed/crossed <INTERNAL_KNOWLEDGE_ASSISTANT> states also return `stale` even when the report says `Result: PASS`.

## Output

Return:

- mode (`startup`, `materialize`, `verify`, `read`, or `verify-setup-cache`); `startup` is emitted only when the resolver cannot load a required runtime dependency,
- status (`current`, `missing`, `malformed`, `stale`, or `blocked`),
- snapshot path,
- source fingerprint when available,
- setup-input fingerprint from `materialize` and successful `verify-setup-cache` modes,
- `report_fingerprints`, keyed by the exact `Config-Fingerprint` and `Resolved-Config-Fingerprint` report labels so Setup Validator copies the mapping without translating field names,
- requested section for `read` mode, or
- exact validation failures and the setup-validation redirection.

## Constraints

- Setup Validator is the only writer.
- Deva may invoke only `verify-setup-cache` as a mechanical setup precondition. It never invokes `materialize` or `read`, merges configuration, or passes configuration objects between agents.
- Consumers never read `default-config.yaml` or `team-config.yaml` for operational values.
- `guardrails.yaml` is always read separately by its consumers.
- Never store secrets, credentials, or source file contents in resolver diagnostics.
