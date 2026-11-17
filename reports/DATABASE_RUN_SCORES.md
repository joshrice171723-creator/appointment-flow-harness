# Database performance and automation scores

Performance measures database work on shared cases. Automation measures six kinds of recorded checks for that run. Check the behavior result and Active Record rule before choosing a build.

- **Performance (1–100).** For each measured cost, divide the smallest observed cost plus one by the run's cost plus one. The table states the metric weights. Average the weighted ratios over shared cases with the same recorded result. A score of 100 means the run matched the lowest measured work on every scored measure in that table. Round to whole points. Different tables use different workloads.
- **Automation (1–100).** Count the recorded check types. Each of the six types has equal weight. The score applies to the measured scope. Checking an operation records coverage even if it detects a failure. A missing record leaves a gap in the score.
- **Comparable outcomes.** Exclude a case from a cost ranking when any included result differs or lacks a required count. Full behavior totals remain visible where recorded. Some older adapters compare returned counts rather than exact bodies. Patient and staff refactor comparisons use exact response hashes.
- **Timing and transfer size.** The source files include timings and PMS bytes when captured. Timing varies across runs. PMS bytes enter a score only if the cohort records comparable counts.

Scored automation checks are Automated caller, Work counters, Growth fixture, Output and write effects, Executed query plans, Active Record source check.

## Standard application workload

Scored 16 of 16 shared cases. rails read rows 35%, affected rows 20%, write statements 15%, sql statements 15%, models loaded 15%.

| Run or stage | Performance | Automation | Outcome or scope |
|---|---:|---:|---|
| V2.7.4 Active Record rewrite | 94 | 83 | Saved diagnostic rewrite. 44 of 44 behavior checks and plain Active Record check passed |
| V2.7.4 final | 91 | 83 | 44 of 44 behavior checks. Failed the plain Active Record rule |
| V2.7.4 initial | 91 | 67 | Before repair |
| V2.5.1.1.0 standalone | 79 | 67 | Shared cases |
| V2.6.1.1.0 standalone | 75 | 67 | Shared cases |
| V2.8.5 final rebuild | 73 | 83 | 42 of 44 checks. Active Record source check passed |
| V2.8.5 first rebuild | 73 | 67 | First build checkpoint. 42 of 44 checks |
| V2.8.5 reviewed rebuild | 73 | 67 | Reviewed checkpoint before final freeze |
| V2.7.2 initial | 69 | 67 | Before repair |
| V2.9.5.1.1 full rebuild | 68 | 83 | 44 of 44 checks. Active Record source check passed |
| V2.5.1.0.0 standalone | 67 | 67 | Shared cases |
| V2.7.1.1.0 | 66 | 67 | Shared cases |
| V2.7.2 final | 64 | 67 | 25 of 25 independent behavior checks passed |
| V2.7.3 cold-write trial | 62 | 67 | Scoped write experiment |
| V2.7.4 scoped recipient | 62 | 67 | Separate recipient trial |
| V2.7.3 scoped refresh | 60 | 67 | Scoped refresh experiment |
| V2.5.0.0.0 standalone | 59 | 67 | Shared cases |
| V2.7.3 final | 58 | 83 | 40 of 44 independent behavior checks passed |
| V2.7.3 initial | 58 | 67 | Before repair |
| Original appointment-flow | 48 | 67 | Shared cases |

[V2.7_Compared_Workload](../benchmarks/V2.7_Compared_Workload.csv), [V2.7.2_Initial_Standard_Workload](../benchmarks/V2.7.2_Initial_Standard_Workload.csv), [V2.7.2_Final_Standard_Workload](../benchmarks/V2.7.2_Final_Standard_Workload.csv), [V2.7.3_Matched_Initial_Workload](../benchmarks/V2.7.3_Matched_Initial_Workload.csv), [V2.7.3_Matched_Final_Workload](../benchmarks/V2.7.3_Matched_Final_Workload.csv), [V2.7.3_Scoped_Refresh_Standard_Workload](../benchmarks/V2.7.3_Scoped_Refresh_Standard_Workload.csv), [V2.7.3_Cold_Write_Refactor_Workload](../benchmarks/V2.7.3_Cold_Write_Refactor_Workload.csv), [V2.7.4_Matched_Initial_Workload](../benchmarks/V2.7.4_Matched_Initial_Workload.csv), [V2.7.4_Matched_Final_Workload](../benchmarks/V2.7.4_Matched_Final_Workload.csv), [V2.7.4_Scoped_Recipient_Workload](../benchmarks/V2.7.4_Scoped_Recipient_Workload.csv), [V2.8.5_Rebuild_Workload](../benchmarks/V2.8.5_Rebuild_Workload.csv), [V2.9.5.1.1_Matched_Workload](../benchmarks/V2.9.5.1.1_Matched_Workload.csv), [summary](../benchmarks/recovered/v274-ar-bench/v274-active-record-4trl7opm/summary.csv), [summary](../benchmarks/recovered/v285-rebuild-first-benchmark/appointment-flow_v2.8.5.1.1-verified-hw_vzu4s/summary.csv), [summary](../benchmarks/recovered/v285-rebuild-reviewed-benchmark/appointment-flow_v2.8.5.1.1-verified-e8ak1r_6/summary.csv)

## Expanded recipient, history, and standard cases

Scored 38 of 44 shared cases. rails read rows 35%, affected rows 20%, write statements 15%, sql statements 15%, models loaded 15%.

| Run or stage | Performance | Automation | Outcome or scope |
|---|---:|---:|---|
| V2.7.4 Active Record rewrite | 96 | 83 | Saved diagnostic rewrite. 44 of 44 behavior checks and plain Active Record check passed |
| V2.7.4 final | 94 | 83 | 44 of 44 behavior checks. Failed the plain Active Record rule |
| V2.7.4 initial | 94 | 67 | Before repair |
| V2.8.5 final rebuild | 78 | 83 | 42 of 44 checks. Active Record source check passed |
| V2.8.5 first rebuild | 78 | 67 | First build checkpoint. 42 of 44 checks |
| V2.8.5 reviewed rebuild | 78 | 67 | Reviewed checkpoint before final freeze |
| V2.9.5.1.1 full rebuild | 72 | 83 | 44 of 44 checks. Active Record source check passed |
| V2.7.4 scoped recipient | 70 | 67 | Separate recipient trial |
| V2.7.3 final | 67 | 83 | 40 of 44 independent behavior checks passed |
| V2.7.3 initial | 67 | 67 | Before repair |

[V2.7.3_Matched_Initial_Workload](../benchmarks/V2.7.3_Matched_Initial_Workload.csv), [V2.7.3_Matched_Final_Workload](../benchmarks/V2.7.3_Matched_Final_Workload.csv), [V2.7.4_Matched_Initial_Workload](../benchmarks/V2.7.4_Matched_Initial_Workload.csv), [V2.7.4_Matched_Final_Workload](../benchmarks/V2.7.4_Matched_Final_Workload.csv), [V2.7.4_Scoped_Recipient_Workload](../benchmarks/V2.7.4_Scoped_Recipient_Workload.csv), [V2.8.5_Rebuild_Workload](../benchmarks/V2.8.5_Rebuild_Workload.csv), [V2.9.5.1.1_Matched_Workload](../benchmarks/V2.9.5.1.1_Matched_Workload.csv), [summary](../benchmarks/recovered/v274-ar-bench/v274-active-record-4trl7opm/summary.csv), [summary](../benchmarks/recovered/v285-rebuild-first-benchmark/appointment-flow_v2.8.5.1.1-verified-hw_vzu4s/summary.csv), [summary](../benchmarks/recovered/v285-rebuild-reviewed-benchmark/appointment-flow_v2.8.5.1.1-verified-e8ak1r_6/summary.csv)

## Original-app staff appointment refactors

Scored 21 of 22 shared cases. rails read rows 55%, sql statements 30%, models loaded 15%.

| Run or stage | Performance | Automation | Outcome or scope |
|---|---:|---:|---|
| Isolated refactor | 98 | 67 | 21 of 22 responses matched the original |
| First refactor | 78 | 67 | 22 of 22 responses matched the original |
| Original | 73 | 67 | 22 of 22 responses matched the original |

[V2.7.2_Refactor_Comparison](../benchmarks/V2.7.2_Refactor_Comparison.csv)

## Original-app patient details and appointment history

Scored 10 of 10 shared cases. explained buffers 60%, statements 15%, rows returned 10%, records loaded 15%.

| Run or stage | Performance | Automation | Outcome or scope |
|---|---:|---:|---|
| Final | 96 | 100 | Exact responses and cursor match |
| First | 87 | 83 | Exact responses and cursor match |
| Regraded | 87 | 100 | Exact responses and cursor match |
| Previous | 66 | 83 | Exact responses and cursor match |
| Original | 57 | 100 | Original has handwritten SQL in the measured scope |

[V2.8.5_Patient_Appointments_Workload](../benchmarks/V2.8.5_Patient_Appointments_Workload.csv)

## Patient history index trial

Scored 10 of 10 shared cases. statements 30%, rows returned 50%, models loaded 20%.

| Run or stage | Performance | Automation | Outcome or scope |
|---|---:|---:|---|
| baseline | 100 | 83 | This score uses the measured request counters. The report also has executed plan comparisons. |
| both | 100 | 83 | This score uses the measured request counters. The report also has executed plan comparisons. |
| mirror | 100 | 83 | This score uses the measured request counters. The report also has executed plan comparisons. |

[V2.7.5_Patient_Appointment_Index_Workload](../benchmarks/V2.7.5_Patient_Appointment_Index_Workload.csv)

## V2.6 staff screen, grown confirmed filter

Scored 1 of 1 shared cases. rails read rows 65%, sql statements 35%.

| Run or stage | Performance | Automation | Outcome or scope |
|---|---:|---:|---|
| V2.6 frozen | 100 | 67 | The measured response stayed the same. |
| V2.6.1.2 refactor | 74 | 67 | The measured response stayed the same. |
| Ruby review array trial | 22 | 67 | The measured response stayed the same. |

[V2.6.1.2_Staff_Appointments_Result](../benchmarks/../reports/V2.6.1.2_Staff_Appointments_Result.md)

## V2.7 staff screen, grown review filter

Scored 1 of 1 shared cases. rails read rows 65%, sql statements 35%.

| Run or stage | Performance | Automation | Outcome or scope |
|---|---:|---:|---|
| V2.6 frozen | 100 | 67 | The measured response stayed the same. |
| V2.7 private methods and per-day counts | 74 | 67 | The measured response stayed the same. |
| Group by timestamp and combine in Ruby | 37 | 67 | The measured response stayed the same. |

[V2.7_Staff_Appointments_Refactor](../benchmarks/../reports/V2.7_Staff_Appointments_Refactor.md)

## V2.9.5.1.1 fixed-output growth check

Scored 4 of 4 shared cases. statements 15%, rows read 35%, active record instances 15%, write statements 15%, affected rows 20%.

| Run or stage | Performance | Automation | Outcome or scope |
|---|---:|---:|---|
| small | 100 | 100 | Same build at two sizes. Separate from earlier rebuild workloads. |
| grown | 91 | 100 | Same build at two sizes. Separate from earlier rebuild workloads. |

[V2.9.5.1.1_HTTP_Workload](../benchmarks/V2.9.5.1.1_HTTP_Workload.csv)

## Original reminder job with additional PMS patients

Scored 2 of 2 shared cases. replica json bytes 35%, rails read rows 20%, affected rows 20%, write statements 15%, sql statements 10%.

| Run or stage | Performance | Automation | Outcome or scope |
|---|---:|---:|---|
| mixed | 100 | 67 | Same original job. The first tick opens 16 tickets and the retry opens zero. |
| mixed_extra_patients | 57 | 67 | Same original job. The first tick opens 16 tickets and the retry opens zero. |

[Original_Reminder_Job_PMS_Workload](../benchmarks/Original_Reminder_Job_PMS_Workload.csv)

## Every paired run

Each score links to its own comparison context. The run index records earlier historical, source-only, and interrupted work.

| Run bundle | Recorded performance and automation |
|---|---|
| [Original appointment-flow](../runs/Original.zip) | 48 performance and 67 automation in Standard application workload; 73 performance and 67 automation in Original-app staff appointment refactors; 57 performance and 100 automation in Original-app patient details and appointment history; 57 performance and 67 automation in Original reminder job with additional PMS patients |
| [V2](../runs/V2.zip) | Unranked. Saved evidence has no matched dataset for this run. |
| [V2.1](../runs/V2.1.zip) | Unranked. Saved evidence has no matched dataset for this run. |
| [V2.2](../runs/V2.2.zip) | Unranked. Saved evidence has no matched dataset for this run. |
| [V2.3.0.0.0](../runs/V2.3.0.0.0.zip) | Unranked. Saved evidence has no matched dataset for this run. |
| [V2.4.0.0.0](../runs/V2.4.0.0.0.zip) | Unranked. Saved evidence has no matched dataset for this run. |
| [V2.4.1.1.0](../runs/V2.4.1.1.0.zip) | Unranked. Saved evidence has no matched dataset for this run. |
| [V3](../runs/V3.zip) | Unranked. Saved evidence has no matched dataset for this run. |
| [V3.1.1](../runs/V3.1.1.zip) | Unranked. Saved evidence has no matched dataset for this run. |
| [V2.5.0.0.0](../runs/V2.5.0.0.0.zip) | 59 performance and 67 automation in Standard application workload |
| [V2.5.1.0.0](../runs/V2.5.1.0.0.zip) | 67 performance and 67 automation in Standard application workload |
| [V2.5.1.1.0](../runs/V2.5.1.1.0.zip) | 79 performance and 67 automation in Standard application workload |
| [V2.6.1.1.0](../runs/V2.6.1.1.0.zip) | 75 performance and 67 automation in Standard application workload; 100 performance and 67 automation in V2.6 staff screen, grown confirmed filter; 100 performance and 67 automation in V2.7 staff screen, grown review filter |
| [V2.7.1.1.0](../runs/V2.7.1.1.0.zip) | 66 performance and 67 automation in Standard application workload |
| [V2.7.2.1.0](../runs/V2.7.2.1.0.zip) | 64 performance and 67 automation in Standard application workload |
| [V2.7.3.1.0](../runs/V2.7.3.1.0.zip) | 58 performance and 83 automation in Standard application workload; 67 performance and 83 automation in Expanded recipient, history, and standard cases |
| [V2.7.4.1.0](../runs/V2.7.4.1.0.zip) | 91 performance and 83 automation in Standard application workload; 94 performance and 83 automation in Expanded recipient, history, and standard cases |
| [V2.6.1.2-staff-refactor](../runs/V2.6.1.2-staff-refactor.zip) | 74 performance and 67 automation in V2.6 staff screen, grown confirmed filter |
| [V2.7.1.1.1-staff-refactor](../runs/V2.7.1.1.1-staff-refactor.zip) | 74 performance and 67 automation in V2.7 staff screen, grown review filter |
| [V2.7.2-original-refactor](../runs/V2.7.2-original-refactor.zip) | 78 performance and 67 automation in Original-app staff appointment refactors |
| [V2.7.2-original-isolated](../runs/V2.7.2-original-isolated.zip) | 98 performance and 67 automation in Original-app staff appointment refactors |
| [V2.7.3-refresh](../runs/V2.7.3-refresh.zip) | 60 performance and 67 automation in Standard application workload |
| [V2.7.3-cold-write](../runs/V2.7.3-cold-write.zip) | 62 performance and 67 automation in Standard application workload |
| [V2.7.4-recipient](../runs/V2.7.4-recipient.zip) | 62 performance and 67 automation in Standard application workload; 70 performance and 67 automation in Expanded recipient, history, and standard cases |
| [V2.7.5.1.0 query refactor](../runs/V2.7.5.1.0-query-refactor.zip) | 100 performance and 83 automation in Patient history index trial |
| [V2.7.5.1.0](../runs/V2.7.5.1.0-mirror-followup.zip) | 66 performance and 83 automation in Original-app patient details and appointment history |
| [V2.4.1.1.0 paired trial](../runs/V2.4.1.1.0-paired-interrupted.zip) | Unranked. Saved evidence has no matched dataset for this run. |
| [V2.5.1.1.0 paired trial](../runs/V2.5.1.1.0-paired-interrupted.zip) | Unranked. Saved evidence has no matched dataset for this run. |
| [V2.8.5.1.1-rebuild](../runs/V2.8.5.1.1-rebuild.zip) | 73 performance and 83 automation in Standard application workload; 78 performance and 83 automation in Expanded recipient, history, and standard cases |
| [V2.8.5.1.1-refactor](../runs/V2.8.5.1.1-refactor.zip) | 87 performance and 100 automation in Original-app patient details and appointment history |
| [V2.8.5.1.1-refactor-repair](../runs/V2.8.5.1.1-refactor-repair.zip) | 96 performance and 100 automation in Original-app patient details and appointment history |
| [V2.9.5.1.1-rebuild](../runs/V2.9.5.1.1-rebuild.zip) | 68 performance and 83 automation in Standard application workload; 72 performance and 83 automation in Expanded recipient, history, and standard cases; 91 performance and 100 automation in V2.9.5.1.1 fixed-output growth check |

## Designs and historical snapshots

V2.1.1 and V2.8.4.1.0 are packaged designs without verified completed runs. V26 is a historical app snapshot with an unverified harness input. Their archived evidence is in the [version catalog](../VERSIONS.md).
