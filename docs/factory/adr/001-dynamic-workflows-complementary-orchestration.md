# ADR 001: Dynamic Workflows as Complementary Orchestration

## Status
Proposed

## Date
2026-05-29

## Context

Anthropic has introduced **Dynamic Workflows** in Claude Code (Research Preview).
The model plans the decomposition of a task itself, writes an orchestration script
at runtime, and fans work out across many parallel subagents. Results are
cross-validated by adversarial agents before being merged; the run iterates until
answers converge. Activated via the Claude Code setting `ultracode`.

This raises the question of whether the deterministic Stage 3 pipeline
(`scripts/run-pipeline.sh`) should be replaced by Dynamic Workflows.

The **core principle of the Factory** is:

> Deterministic scripts orchestrate non-deterministic agent steps –
> never the other way around. Bash calls agents. Agents do not call Bash pipelines.

Dynamic Workflows is conceptually the opposite: the agent orchestrates itself,
the control flow is generated at runtime rather than being prescribed by humans.
A decision with long-term architectural consequences for the template – hence this ADR.

## Decision

Dynamic Workflows is **not** introduced as a replacement for the deterministic
pipeline, but as **complementary orchestration for a clearly scoped task type**:
large, exploratory, parallelizable work (e.g. codebase-wide bug hunts, security
sweeps, mass migrations).

The deterministic, governed feature pipeline (`run-pipeline.sh`) remains the
backbone for the standard flow "one feature at a time".

## Alternatives

### Option A: Full replacement (Dynamic Workflows instead of pipeline)
**Pros:**
- Better per-task planning by a strong model rather than a rigid script
- Built-in adversarial verification – stronger than a single review pass
- Built-in checkpointing / resume for long-running tasks

**Cons:**
- Directly contradicts the documented core principle
- Non-deterministic control flow → poor reproducibility, audit problem
  in regulated environments ("why did it run differently this time?")
- Hard quality gates become softer: a model-orchestrated run *can* execute the
  gates, but whether a failure is a hard stop becomes a model decision
- Research Preview, enterprise-disabled by default, admin-controlled → a template
  whose orchestration depends on this is not runnable for many users
- Parallel fan-out costs ("tens to hundreds of subagents") are hard to predict

### Option B: Complement (Dynamic Workflows for bulk/audit tasks)
**Pros:**
- Retains determinism, hard gates, and audit trail for the feature flow
- Leverages Dynamic Workflows' strengths exactly where they fit
- No dependency of the core pipeline on a preview feature
- Clear expectation of which mechanism is responsible for what

**Cons:**
- Two orchestration models in the template (higher conceptual load)
- Requires clear documentation on when to choose which path

### Option C: Do nothing (ignore Dynamic Workflows)
**Pros:**
- No effort, no new complexity

**Cons:**
- Leaves a real quality and speed gain on the table for bulk tasks
- Teams will use the feature ad hoc anyway – better documented than uncontrolled

## Rationale

Dynamic Workflows and the deterministic pipeline solve **different problems**
and do not compete directly:

- The pipeline is built for **one feature with governance** – reproducibility,
  hard gates, and a Git audit trail are the actual value there, independent of
  model capability.
- Dynamic Workflows shines at **large, exploratory, parallel** – tasks for which
  a fixed 6-step script is the wrong tool anyway.

Determinism is also the product promise of the template ("deterministic,
reproducible, observable"). Abandoning that to make a preview feature the default
that many users cannot activate would be a poor trade.

Option B retains the strengths of both worlds and is reversible: should Dynamic
Workflows prove stable and superior, a later ADR can redefine the roles.

## Consequences

**Positive:**
- The core pipeline remains deterministic, auditable, and free of preview dependencies
- Bulk/audit work gets a suitable, documented path
- The decision is reversible and tied to real-world experience

**Negative / Trade-offs:**
- Two orchestration paths must be explained and maintained
- Dynamic Workflows is Research Preview – availability (enterprise: admin-controlled)
  and behavior may change; concrete integration deferred until stabilization

## Next Steps (not part of this ADR)

- Optional skill (e.g. `/audit` or `/migrate`) that deliberately triggers a Dynamic
  Workflow for bulk tasks – as a separate, small MR once the feature leaves preview.
- Short section in the README explaining the choice "pipeline vs. Dynamic Workflow".
