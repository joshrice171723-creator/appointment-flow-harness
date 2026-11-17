# Harness experiment completion criteria

Compare the current Rails and React harness candidate with the previous version on the same workload. Use the standards below to decide which version to keep. Preserve the existing harness rules, including plain Active Record for application queries. The AI owns execution, verification, and grading. Joshua reviews the code when a final candidate is ready.

## Current experiment

The two V2.7.2.1.0 original-app refactors have been compared against the frozen original. The first included historical guidance. The second excluded that guidance and added explicit search boundaries. The two-file scope limited both attempts. The V2.7.2.1.0 and V2.7.3.1.0 full rebuilds have frozen and their shared workload has been measured. Their blind reviews found material correctness and performance gaps. Scoped refactors reduced repeated reads, batched first-time writes, and repaired recipient eligibility on historical contacts. The last scoped trial passed all 44 external checks. The V2.7.4.1.0 matched rebuild comparison is complete. Keep V2.7.3.1.0 as the working baseline. V2.7.4.1.0 passed four additional checks and reduced database work, but its application queries depend on handwritten SQL. The baseline's recipient-safety and growth gaps remain open. [Original refactor comparison](V2.7.2_Refactor_Isolation_Comparison.md) · [Full rebuild and focused refactors](V2.7.3_Performance_Experiment.md) · [V2.7.4 comparison decision](V2.7.4_Candidate.md)

## Evaluation

| Harness area | Standard for adoption |
|---|---|
| Base revision | Required outcomes hold through normal Rails entry points, including consequential failures. A reader can trace the workflow, find the rule owner, and see what persists or rolls back. For a time-dependent decision, identify the event that sets the clock and test a boundary where choosing another event changes the result. |
| Performance | Use standard Active Record for application queries. Compare correct outcomes and measure the whole caller using the workloads below. Explain material scans, transfers, per-item queries and writes, and repeated work. |
| AI loop | The reviewer verifies material findings, repairs them, and checks the affected behavior on the exact revision being graded. Record what the review caught and what it changed. |
| Refactor | Preserve public behavior and keep the change within the requested scope. A plausible follow-up rule change reaches a clear owner and preserves neighboring behavior. Run the same focused checks before and after. |

Plain Active Record is the application-query standard because it keeps Rails code easier to read and maintain. Judge performance among designs that meet that standard. Treat handwritten SQL, embedded SQL expressions, and Arel used to implement application queries as gaps, even when they improve a benchmark. Review the underlying query logic if a helper or view contains it.

### Focused performance evidence

Choose one normal workflow. Establish its exact result and persisted effects, then compare these workloads where they apply.

| Workload | What to measure |
|---|---|
| Small first run | Establish the cost of producing the result and creating initial state. |
| More unrelated data | Keep the result fixed. Grow records that can enter a material shared prerequisite, including data within its actual scope. |
| More eligible work | Check how database operations grow with useful work and whether equivalent writes can be batched safely. |
| Repeat or retry | Check repeated reads, duplicate effects, and writes that change zero rows. Exercise overlap and lock behavior when concurrent calls are part of the workflow. |

Record SQL statements, rows returned, rows affected by writes, Active Record objects loaded, and whole-operation elapsed time separately. Measure payload size when result width matters. Inspect executed plans when a small result can hide a broad scan. Repeat timing samples under comparable conditions, and keep first-run and repeat timings separate.

## Controlled iteration

1. Preserve the current package, source snapshots, launch receipts, and raw measurements.
2. Discover general problems from measured operations and source review. Verify framework claims with the installed Rails version and official sources.
3. Choose a small harness change tied to an observed failure mechanism. Prefer changes that alter implementation decisions while the workflow is being built.
4. When a regression has a clear owner in existing code, test the proposed mechanism as a scoped refactor first. Allow the actual rule owner and its tests within scope. Measure against the frozen starting commit and preserve the unchanged business behavior. Use that evidence to decide whether to launch a fresh full rebuild with the same assignment, model, effort, and tools. Keep historical implementations and external comparison cases outside clean-room builder context.
5. Freeze the initial result and the post-review result. Run external checks against exact revisions and explain what the repair loop changed.
6. Retain improvements supported by behavior and cost evidence. Reject or revise changes that introduce material regressions.

Log any degradation with its compared revisions, measured behavior and workload, and what the next iteration should avoid. Record source-only observations and changes in launch conditions so the result can be interpreted accurately. [Regression log](Appointment_Flow_Harness_Regression_Log.md)

Use the same final external fixtures across compared builds. When a new case exposes a gap, apply it to the earlier candidate as well. Distinguish a diagnostic retry from another independent build. Do not repeatedly rerun passing suites without a source change or unresolved concern.

During a focused trial, run the checks that exercise the changed behavior. After freeze, run the shared outcome and workload checks in one isolated database, clearing fixture tables between scenarios. Capture query plans separately where a measured difference needs an explanation. Save independent code review and full rebuilds for changes whose focused evidence justifies the extra time. Carry forward exact-revision results when a later checkpoint changes documentation alone.

## Stopping rule

Finish the current matched comparison and judge each harness area by its evidence. If one specific material gap could change which version to keep, run one focused before-and-after trial. A typical focused check uses one workflow with a passing control and a case that exposes the issue. Use the deeper workloads above for performance. Then record the version decision, tradeoffs, regressions, and any unresolved gaps in the report and dashboard. Ask Joshua to read the code once the evidence supports a final candidate.

## External review context

David's review of db037d7 raises full PMS reads, whole-clinic recipient checks, retry scope, indistinguishable failures, and disproportionate complexity. Translate these into general evaluation scenarios. Verify each finding against the code and contract. Joshua disputes the no-show interpretation in item 1, so that question requires specification evidence before it becomes a requirement. [Written review](https://github.com/joshrice171723-creator/appointment-flow/issues/2)
