# Historical V2.8.5.1.1 original refactor results

These are completed historical results from Appointment Flow Performance Benchmark V1.0.0. They compare original `db037d7`, saved refactor `235c16d`, and integration `0468e58`. All 108 backend files match between the saved refactor and the integration after line-ending normalization.

The earlier integration was superseded. The later fresh candidate has separate evaluation and remains ungraded by this record. The evaluator procedure, test inputs, executable probes, and grading instructions are stored outside the public repository. The tables below show observed results.

| Measured workflow | Caller or page | Completed evidence |
|---|---|---|
| First mirror population and ticket creation | Background `ReminderRunner.tick`; tickets appear on `/front-desk?clinic=1`. | 48 measured first/retry operations across the two builds. Each of the 24 first ticks began with zero app patient and appointment mirror rows, visits, tickets, and messages. Persisted outcomes matched. Every retry created zero tickets or sends. |
| Staff appointment load | `GET /api/appointments?clinic=1`; page `/appointments?clinic=1`. | Ten paired cases, 20 requests. Status, response bodies, and IDs matched. No request writes. |
| Patient details and appointment history | `GET /api/patient-details/:id` and its `/history?section=appointments` tab. | Ten paired response cases matched. Candidate compatibility checks passed 11 tests and 136 assertions. The candidate request benchmark passed 199 assertions. No request writes. |
| Guarantor authorization | The same patient detail and appointment-history callers. | Both builds passed 349 assertions. All 32 paired response cases matched. There were 96 timed requests per build and no request writes. |

## Cold mirror and ticket work

These counters were identical in both builds. Database statements include the separate source connection. Rails rows count results returned through Active Record. PMS bytes count the source JSON transfer. Affected rows count writes across the complete tick.

| Observed case | Statements | Rails rows | Affected rows | PMS bytes | New tickets | New sends |
|---|---:|---:|---:|---:|---:|---:|
| 24 appointments, first tick | 239 | 171 | 202 | 8,893 | 16 | 16 |
| Unchanged retry | 88 | 264 | 1 | 8,893 | 0 | 0 |
| 24 appointments with 2,000 extra source patients, first tick | 239 | 171 | 2,202 | 393,743 | 16 | 16 |
| Same larger source, retry | 88 | 264 | 1 | 393,743 | 0 | 0 |
| 96 relevant appointments, first tick | 815 | 651 | 802 | 35,437 | 64 | 64 |
| 96 appointments, retry | 232 | 1,032 | 1 | 35,437 | 0 | 0 |

The historical patient-read refactor left this work equal to the original. Source transfer and mirror writes still increased with extra source patients. First-time workflow statements still increased with relevant visits.

[All cold measurements](../benchmarks/Benchmark_V1.0.0_Historical_V2.8.5.1.1_Cold_Tickets_Raw.csv) · [Cold measurement summaries](../benchmarks/Benchmark_V1.0.0_Historical_V2.8.5.1.1_Cold_Tickets_Medians.csv)

## Staff appointment work

| Observed response | Statements in both builds | Rails rows in both builds |
|---|---:|---:|
| Upcoming view, four visits | 8 | 8 |
| Dated view, four visits | 12 | 24 |
| Upcoming view, 184 visits | 8 | 188 |
| Dated view, 24 visits | 12 | 124 |

The staff appointment query's work counters stayed equal. The single-sample timings leave latency unresolved. This group did not capture query plans.

[Staff request measurements](../benchmarks/Benchmark_V1.0.0_Historical_V2.8.5.1.1_Staff_Appointments.csv)

## Patient read work

The table shows the larger recorded dataset. Buffers count shared PostgreSQL hit and read accesses from captured SELECT plans. Statements cover the complete request. All requests recorded zero writes and matching response bodies and cursors.

| Request | Original statements | Refactor statements | Original buffers | Refactor buffers | Original Rails objects | Refactor Rails objects |
|---|---:|---:|---:|---:|---:|---:|
| Past history, first page | 16 | 19 | 522 | 31 | 59 | 35 |
| Past history, next page | 7 | 12 | 510 | 29 | 55 | 30 |
| Upcoming history | 16 | 19 | 521 | 29 | 12 | 11 |
| Patient details | 18 | 20 | 288 | 24 | 7 | 7 |
| Tracked-only past history | 15 | 20 | 695 | 23 | 32 | 32 |

The refactor used more statements and fewer database page accesses. The query source check reported zero new findings and 17 inherited findings outside the changed production files. These focused results do not give every application workflow a new grade.

[Patient request measurements](../benchmarks/Benchmark_V1.0.0_Historical_V2.8.5.1.1_Patient_Requests.csv)

## Guarantor read work

Each arrow shows the smaller and larger recorded datasets. The caller-visible result stayed fixed.

| Detail response condition | Original statements | Refactor statements | Original rows | Refactor rows | Original buffers | Refactor buffers |
|---|---:|---:|---:|---:|---:|---:|
| Authorized historical ward | 14 | 23 | 9 | 37 | 77 to 489 | 60 to 61 |
| Activity only at another clinic | 3 | 11 | 2 | 30 | 57 to 462 | 43 to 44 |
| Revoked PMS link | 3 | 11 | 2 | 30 | 47 to 462 | 49 to 50 |
| Authorized replacement | 14 | 20 | 9 | 11 | 77 to 440 | 42 to 48 |

For the authorized guarantor's appointment history, statements increased from four to 16 and returned rows increased from three to 31. Database page accesses grew from 72 to 589 in the original and from 53 to 54 in the refactor. The refactor controlled scan growth while increasing round trips and returned permission rows.

[Guarantor measurements](../benchmarks/Benchmark_V1.0.0_Historical_V2.8.5.1.1_Guarantor.csv)

## Evidence limits

The variants ran under concurrent Windows host load. Timing differences changed direction between cases. Original patient timing controls and candidate timing records were collected at different times. The recorded work counters and plans support the narrower findings above.

The patient and guarantor groups verified matching external PMS schema checksums. The cold group checked matching external PMS column definitions. The app-owned mirror received the refactor indexes. The original external schema remained intact.

An initial cold-ticket inspector used an invalid message-item field. The corrected inspector passed on both builds. Aborted logs and complete evaluator records remain preserved outside this repository.

Results remain per-workflow measurements. The fresh candidate requires its own final evaluation.

[Result provenance and dataset checksums](../benchmarks/Benchmark_V1.0.0_Historical_V2.8.5.1.1_Result.json)
