# Evidence for the AI grading and repair loop

The recorded loops produced useful repairs. The evidence does not establish a consistent improvement in readability or total performance across fresh builds.

| Experiment | Recorded result | What it supports |
|---|---|---|
| V2.5.1.0.0 and V2.5.1.1.0 full builds | The performance-only build won both earlier blind source reviews. The loop build completed additional verified repairs and took 54.4 minutes, compared with 46.0 minutes. | A loop can find defects while producing code that reviewers prefer less. One paired build cannot establish its average effect. |
| V2.8.5.1.1 original refactor | The measured patient-workflow score increased from 87 to 96 after an externally directed benchmark repair round. | Benchmark feedback improved the measured read. This was another repair round under the same loop-enabled harness. |
| V2.8.5.1.1 full build | The first and final checkpoints each passed 42 of 44 independent outcome checks. | The internal loop missed two weekly-count failures. |
| V2.9.5.1.1 full build | Independent review found a held-contact run reading 5,031 rows on a grown fixture. The repaired run read 21 rows and kept five holds and zero sends. An intermediate repair caused staff callback failures, which a later round corrected. | A concrete challenge found wasted work and verified a repair. Repairs can introduce regressions, so the next check must cover their effects. |

[V2.5 paired comparison](V2.5_Variant_Comparison.md) · [V2.8.5 validation](V2.8.5_Harness_Validation.md) · [V2.9.5.1.1 result](V2.9.5.1.1_Harness_Upgrade_Report.md)

## Candidate loop revision 2

Integrate Appointment Flow Performance Benchmark V1.0.0 into the evaluator's grade, repair, and regrade sequence. Keep private case definitions and historical solutions outside the builder's initial context. Freeze its first output before the evaluator supplies concrete failures. Record the result of each repair against the exact revision checked.

The builder receives the general performance, correctness, and readability criteria. The evaluator supplies task-specific measurements after the first freeze. A required check that fails cannot support PASS. An unsupported group or missing measurement must remain visible with its scope and reason.

Preserve the same base, performance guidance, and existing-code guidance when comparing loop revisions. V2.10.6.1.1 is the loop-1 control. V2.10.6.2.1 is the loop-2 candidate. The directed V2.10.6.2.1 trial received benchmark information. A controlled comparison of loop revisions 1 and 2 remains unverified.

Record initial output, repair count, final output, elapsed time, regressions, and independent outcomes. Use the same assignment, model, effort, tools, and fixtures. Repeat a controlled comparison before claiming the loop reliably improves future builds.
