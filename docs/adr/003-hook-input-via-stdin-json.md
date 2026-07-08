# ADR 003: Hook Input via stdin JSON, Centrally Parsed in check.sh

## Status
Accepted

## Date
2026-06-12

## Context

The Factory wires deterministic guardrails into Claude Code via hooks
(`.claude/settings.json` → `scripts/checks/check.sh`). The original wiring passed
the tool input as a positional argument expanded from an environment variable:

```
bash scripts/checks/check.sh pre-tool "$CLAUDE_TOOL_INPUT"
```

This never worked. **Claude Code does not set a `$CLAUDE_TOOL_INPUT` (or
`$CLAUDE_TOOL_RESULT`) environment variable.** Per the official hook documentation,
command hooks receive their payload **as JSON via stdin**; for a Bash tool the
executed command lives at `.tool_input.command`. The available environment
variables are limited (e.g. `CLAUDE_PROJECT_DIR`) and do not include the tool input.

Consequently `"$CLAUDE_TOOL_INPUT"` expanded to an empty string, `check.sh` received
no input, every downstream `grep` matched nothing, and the entire `pre-tool` hook
path was dead on arrival — silently. Any check built on this wiring (branch-name
guard, git-context guard, and all future pre-tool checks) was wirkungslos.

Because the input contract governs *every* hook-driven check now and in the future,
the fix is a binding, hard-to-reverse convention rather than a local bugfix — hence
this ADR (ADR-trigger category per ADR-002).

## Decision

1. **stdin JSON is the only input channel.** Hooks are wired without pseudo-arguments
   (`bash scripts/checks/check.sh pre-tool`); the JSON payload arrives on stdin.
2. **`check.sh` is the single parsing point.** It reads stdin once and extracts the
   command via `jq -r '.tool_input.command // empty'`. Sub-checks receive the plain
   command string as `$1` and never parse JSON themselves.
3. **Fail open, never block on plumbing.** If stdin is a terminal (manual invocation),
   carries no data, or `jq` is unavailable, the input stays empty and checks are
   skipped — the user is never blocked by the guard infrastructure itself.
4. **Optional sub-checks are skipped if absent, not errored.** A missing check script
   (e.g. a feature not yet present on the current branch) is a no-op, so the plumbing
   fix is independent of the feature MRs that add individual checks.

## Alternatives

### Option A: Keep an environment variable (`$CLAUDE_TOOL_INPUT`)
**Pros:** No change to the existing positional-argument shape.
**Cons:** The variable does not exist in Claude Code — this is the broken status quo.
Rejected: it cannot work.

### Option B: Each sub-check parses stdin itself
**Pros:** `check.sh` stays a thin router.
**Cons:** stdin can only be consumed once; duplicated jq-parsing across scripts invites
drift and subtle bugs. Rejected in favour of a single source of truth.

### Option C: Regex over the raw JSON string (no jq)
**Pros:** No `jq` dependency.
**Cons:** Fragile against quoting/escaping and JSON field ordering; the previous
`grep '"git"'` style is exactly the brittleness we are removing. Rejected; `jq` is the
correct tool, with graceful degradation when it is absent.

## Rationale

Centralised, structured parsing (Option B's single point + Option C's correct tool)
gives one place to reason about the contract, clean inputs for every sub-check, and a
guard layer that fails open instead of either hanging or silently doing nothing. The
"skip if absent" rule decouples this plumbing fix from the feature MRs that introduce
individual checks, so it can merge first and stand on its own.

## Consequences

**Positive:**
- The pre-tool / post-tool hook path actually executes; guards are no longer dead.
- A single, documented input contract for all current and future checks.
- Plumbing fix is independent of feature MRs (missing checks are no-ops).

**Negative / Trade-offs:**
- Introduces a `jq` dependency for tool-input parsing (degrades gracefully: no jq →
  checks skip rather than fail).
- Sub-checks must follow the contract (consume `$1`, not stdin); deviating scripts that
  try to read stdin again will find it already consumed.
