# Harness versions

[Paired runs](runs/README.md)

The original application is the historical control.

| Version | What changed | Evidence | Archive |
|---|---|---|---|
| Original appointment-flow | Historical product baseline built over roughly a week. | [Measured control](reports/V2.6_Run_Report.md) | [Archive](snapshots/Appointment-Flow-V1.zip) |
| V2 | Chosen as the code-quality baseline after inspecting real workflows. | [Historical source review](reports/Appointment_Flow_All_Versions_Review.md) | [Archive](packages/Apex_Appointment_Flow_Harness_V2.zip) |
| V2.1 | Added query selectivity, explicit workflow stages, and meaningful failure contracts. | [Historical build](reports/Appointment_Flow_Harness_Progress.md) | [Archive](packages/Apex_Appointment_Flow_Harness_V2.1.zip) |
| V2.1.1 | Packaged the first AI grade, repair, and regrade loop. | [Skipped in testing](reports/Appointment_Flow_Harness_Progress.md) | [Archive](packages/Apex_Appointment_Flow_Harness_V2.1.1.zip) |
| V2.2 | Revised simplification guidance after meaningful service stages disappeared. | [Historical build](reports/Appointment_Flow_Harness_Regression_Log.md) | [Archive](packages/Apex_Appointment_Flow_Harness_V2.2.zip) |
| V2.3.0.0.0 | Made entry points, private stages, and failure paths explicit. | [Historical build](reports/Appointment_Flow_All_Versions_Review.md) | [Archive](packages/Apex_Appointment_Flow_Harness_V2.3.0.0.0.zip) |
| V2.4.0.0.0 | Revised review wording and separated reference implementations from builder inputs. | [Historical build](reports/Appointment_Flow_Harness_Progress.md) | [Archive](packages/Apex_Appointment_Flow_Harness_V2.4.0.0.0.zip) |
| V2.4.1.1.0 | Added performance checks and AI grading to the V2.4 base. | [Historical build and scoped measurements](reports/Appointment_Flow_All_Versions_Review.md) | [Archive](packages/Apex_Appointment_Flow_Harness_V2.4.1.1.0.zip) |
| V2.5.0.0.0 | Returned to the V2 base and controlled the standalone launch settings. | [Standalone benchmark](reports/V2.5_Family_Ranking_and_Benchmarks.md) | [Archive](packages/Apex_Appointment_Flow_Harness_V2.5.0.0.0.zip) |
| V2.5.1.0.0 | Added growth measurements and audited query paths against the Rails guide. | [Standalone benchmark](reports/V2.5.1.0.0_Active_Record_Audit.md) | [Archive](packages/Apex_Appointment_Flow_Harness_V2.5.1.0.0.zip) |
| V2.5.1.1.0 | Required AI grading, repair, and regrading in the performance variant. | [Standalone benchmark](reports/V2.5_Variant_Comparison.md) | [Archive](packages/Apex_Appointment_Flow_Harness_V2.5.1.1.0.zip) · [Variant input](packages/Apex_Appointment_Flow_Harness_V2.5.1.1.0-variant-input.zip) |
| V2.6.1.1.0 | Measured growing work during implementation and verified a disposable rule change. | [Matched rebuild and follow-up](reports/V2.6_Run_Report.md) | [Archive](packages/Apex_Appointment_Flow_Harness_V2.6.1.1.0.zip) |
| V2.6.1.2 | Separated structure changes from query changes and required equivalent responses. | [Scoped refactor overlay](reports/V2.6.1.2_Staff_Appointments_Result.md) | [Archive](packages/Apex_Appointment_Flow_Harness_V2.6.1.2-overlay.zip) |
| V2.7.1.1.0 | Set Rails ownership rules and tightened evidence for plain Active Record. | [Matched rebuild](reports/V2.7_Clean_Room_Comparison.md) | [Archive](packages/Apex_Appointment_Flow_Harness_V2.7.1.1.0.zip) |
| V2.7.1.1.1 | Applied the V2.7 rules to an existing appointment controller. | [Scoped refactor overlay](reports/V2.7_Staff_Appointments_Refactor.md) | [Archive](packages/Apex_Appointment_Flow_Harness_V2.7.1.1.1-overlay.zip) |
| V2.7.2.1.0 | Added checks for late filtering, per-item work, response size, and repeat effects. | [Rebuild and isolated refactors](reports/V2.7.2_Refactor_Isolation_Comparison.md) | [Archive](packages/Apex_Appointment_Flow_Harness_V2.7.2.1.0.zip) |
| V2.7.3.1.0 | Made query representation and its update owner an early design decision. | [Working full-rebuild baseline](reports/V2.7.3_Performance_Experiment.md) | [Archive](packages/Apex_Appointment_Flow_Harness_V2.7.3.1.0.zip) |
| V2.7.4.1.0 | Checked authoritative recipients and shared work outside the current view. | [Matched rebuild; authored SQL failed the standard](reports/V2.7.4_Candidate.md) | [Archive](packages/Apex_Appointment_Flow_Harness_V2.7.4.1.0.zip) |
| V2.7.5.1.0 | Made authored SQL a separate gate and moved query checks into each slice. | [Scoped original-app refactor and index trial](reports/PATIENT_APPOINTMENTS_MIRROR_INDEX.md) | [Archive](packages/Apex_Appointment_Flow_Harness_V2.7.5.1.0.zip) |
| V2.8.4.1.0 | Added an explicit check for the event that sets a time-dependent decision. | [Packaged design, build unverified](reports/Harness_Autonomous_Experiment_Plan.md) | [Archive](packages/Apex_Appointment_Flow_Harness_V2.8.4.1.0.zip) |
| V2.8.5.1.1 | Restored the Active Record check. Added query plan checks for builds and refactors. | [Validation report](reports/V2.8.5_Harness_Validation.md) | [Harness ZIP](packages/Apex_Appointment_Flow_Harness_V2.8.5.1.1.zip) · [Rebuild ZIP](runs/V2.8.5.1.1-rebuild.zip) · [Refactor ZIP](runs/V2.8.5.1.1-refactor.zip) |
| V2.9.5.1.1 | Added mandatory ACTION → CONSTRAINTS → VERIFICATION → REPORTING, ASD-STE100 writing principles, and a task execution quality criterion. The matched benchmark passed 44 of 44 outcomes and scored 68/100 on the standard workload. | [Upgrade report](reports/V2.9.5.1.1_Harness_Upgrade_Report.md) · [Matched result](reports/V2.9.5.1.1_Full_Benchmark.md) | [Harness ZIP](packages/Apex_Appointment_Flow_Harness_V2.9.5.1.1.zip) · [Rebuild ZIP](runs/V2.9.5.1.1-rebuild.zip) · [Benchmark ZIP](benchmarks/V2.9.5.1.1_Full_Benchmark.zip) |
| V3 | Parallel early harness with broader Rails and React guides. | [Historical source review](reports/Appointment_Flow_All_Versions_Review.md) | [Archive](packages/Apex_Appointment_Flow_Harness_V3.zip) |
| V3.1.1 | Added structured AI review to the V3 family. The preserved input was labeled V4. | [Historical source review](reports/Appointment_Flow_All_Versions_Review.md) | [Archive](packages/Apex_Appointment_Flow_Harness_V3.1.1.zip) |
| V2.10.6.1.1 | Packaged portable instructions for audits, refactors, features, and builds. | Packaged design. | [Harness ZIP](packages/Apex_Appointment_Flow_Harness_V2.10.6.1.1.zip) |
| V2.10.6.2.1 | Added stronger review and benchmark repair evidence. | Directed full build refactor. The benchmark reached the builder. | [Harness ZIP](packages/Apex_Appointment_Flow_Harness_V2.10.6.2.1.zip) · [Loop evidence](reports/AI_Loop_Evidence.md) |
| V2.10.6.3.1 | Separated project-owned repair checks from held-out evaluation. | Archived full-build export `9a5dbce` and original refactor `e27aca2`. Separate clean-room freezes `9c71028` and `5f2500c` have a paired comparison against the original. | [Harness ZIP](packages/Apex_Appointment_Flow_Harness_V2.10.6.3.1.zip) · [Clean-room comparison](reports/V2.10.6.3.1_Clean_Room_Comparison.md) |

Forward version format is `V<family>.<base revision>.<performance>.<AI loop>.<existing-code revision>`.
Older labels retain their original meanings. Refactor overlays supplement a base harness. The V2.5.1.1.0 variant input has a distinct checksum.
