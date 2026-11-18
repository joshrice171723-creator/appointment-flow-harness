# Appointment Flow harness experiment

I tested coding instructions on a Rails and React app for appointment reminders. The experiment measured behavior, database work, and how easy the code was to read and change.

[Performance](#performance-highlight) · [Clean-room comparison](#clean-room-build-and-regression-repair) · [Run the app](#final-product--curated-original-refactor) · [Versions and evidence](#versions-and-evidence)

## Performance highlight

The **V2.7.4.1.0 Active Record refactor scored 94/100**. The original app scored **48/100** on the same 16-case workload.

| Application | Revision | Database work score |
| --- | --- | ---: |
| Original Appointment Flow | Original control | 48/100 |
| V2.7.4.1.0 full build | `860fa23` | 91/100 |
| V2.7.4.1.0 directed Active Record refactor | `6c9e20a` | **94/100** |

The directed refactor started from the 91-point full build. It passed all 44 behavior checks and the plain Active Record check. The full build passed the behavior checks. Its SQL views and functions failed the Active Record check.

The score measures database work on equivalent cases. The measured calls started with stored contact keys already populated. The score excludes the work to create those keys. A full readability and changeability review of `6c9e20a` remains open. [Scorecard and metric weights](reports/DATABASE_RUN_SCORES.md#standard-application-workload) · [Refactor evidence](reports/V2.7.4.1.0_Readability_Assessment.md)

## Clean-room build and regression repair

The V2.10.6.3.1 harness supplied the instructions, written requirements, and ten reference screenshots. Workbench was added later. It recorded task scope, check results, and repair rounds.

### Verified repairs

The comparison of `9c71028` with the original `db037d7` found three problems. The paired rerun verified these repairs at `5f2500c`.

| Problem | Verified repair |
| --- | --- |
| A delayed YES could confirm the wrong appointment. | An ambiguous YES goes to staff review. |
| Reply review stayed open after all candidate appointments ended. | The review closes. The app keeps the reply history. |
| Staff confirmation closed a separate contact conflict. | The conflict stays open until the app reconciles it. |

The repair kept the Day 6 backup email rule. The minimum lead time for a catch-up confirmation request remains open.

### Reminder workload

| Reminder workload | Original `db037d7` | Repaired rebuild `5f2500c` |
| --- | ---: | ---: |
| Distinct simulated sends across 60 clinics | 4,000 | 4,000 |
| Write statements on the first tick | 12,127 | 420 |
| Duplicate sends across two repeats | 0 | 0 |

The rebuild used **96.5% fewer write statements** on the first tick. The original stores extra records for each send and reads a smaller appointment window. The rebuild reads the clinic’s full appointment history. These counts apply to this reminder workload. Frontend parity is still open. [Paired results and limits](reports/V2.10.6.3.1_Clean_Room_Comparison.md)

## Final product · curated original refactor

The published app `50b69ee` combines improvements on the original app. It passed all 60 cases in the V1.1.0 evaluation. It has a separate history from the clean-room build.

| Operation | Measure | Original | Published app |
| --- | --- | ---: | ---: |
| First reminder run with 96 appointments | Database statements | 815 | 658 |
| Retry with 2,000 extra source patients | App rows returned | 264 | 248 |
| Clinic calendar with 20 extra eligible appointments | Database statements | 12 | 11 |
| Upcoming patient history with extra records | PostgreSQL buffer accesses in captured reads | 521 | 163 |

The backend suite passed 131 tests with 1,984 assertions. The frontend build and Compose configuration check passed. The app reads the fixed PMS schema and stores its own workflow data separately. [Run the app](final-app/README.md) · [Download the app](final-app/Appointment-Flow-Curated-Refactor.zip) · [Source and checksums](final-app/provenance.json)

## How to read the measurements

- **Check the behavior first.** Match the inputs, responses, and saved results before comparing cost.
- **Check the workload.** The 16-case scorecard, 60-case evaluation, and 4,000-send run measure different work.
- **Check the metric.** Statement counts measure how often the app calls the database. Row counts measure how much data it reads or changes. Elapsed time depends on the test conditions.
- **Check the revision.** A result applies to the exact build in its record. V1.1.0 includes original-app workflows that some rebuilds did not implement. Use its case results to see that coverage. Compare cost on cases with equivalent results. [Archived V1.1.0 results](benchmarks/Appointment_Flow_V1.1.0_Results.csv)

## Versions and evidence

| To find | Open |
| --- | --- |
| Harness versions and naming rules | [Version catalog](VERSIONS.md) |
| Harness inputs and application outputs | [Paired run downloads](runs/README.md) |
| Benchmark files and how to read them | [Evidence index](reports/EVIDENCE_INDEX.md) |
| Historical performance and check coverage | [Score tables](reports/DATABASE_RUN_SCORES.md) |
| Issues found and repairs made | [Regression log](reports/Appointment_Flow_Harness_Regression_Log.md) |
| Searchable experiment records | [Dashboard](dashboard/index.html) |
| AI and author contributions | [AI usage](AI_USAGE.md) |

The public archives omit the company’s assessment PDF. Check the archive hash before using a download. [Archive checksums](SHA256SUMS.txt)
