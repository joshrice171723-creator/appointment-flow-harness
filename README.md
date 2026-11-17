# Appointment Flow harness experiment

I tested how different coding instructions changed the Rails and React apps AI agents produced. I evaluated readability, ease of change, correct behavior, and database work.

[Paired runs](runs/README.md) · [Harness versions](VERSIONS.md) · [Dashboard](dashboard/index.html) · [AI usage](AI_USAGE.md) · [Regressions](reports/Appointment_Flow_Harness_Regression_Log.md)

[Reminder benchmark](#the-reminder-benchmark) · [Correctness and Active Record](#the-working-baseline-and-the-query-rule) · [How the versions were judged](#how-i-decided-which-version-was-better)

![Matched reminder workload and later decisions. Statements fell from 119 to 18 for the same 24 reminders. The later build passed four more checks and failed the Active Record rule. A scoped index change cut buffer hits from 176 to 3 for two visit records.](dashboard/experiment-results.png)

**28 run bundles** pair the recovered instructions with the application output. The index marks verified inputs, historical matches, and interrupted builds. [Browse the paired runs](runs/README.md)

## What improved

### The reminder benchmark

Each build sent the same 24 synthetic reminders and passed the same 16 checks. The original app is the historical baseline.

| Version | Execution environment | Database statements for 24 reminders |
|---|---|---:|
| Original appointment-flow | Historical app | 119 |
| V2.5.0.0.0 | Standalone Codex | 161 |
| V2.5.1.0.0 | Standalone Codex | 26 |
| V2.5.1.1.0 | Standalone Codex | 40 |
| V2.6.1.1.0 | Standalone Codex | 18 |

- **85% fewer statements in V2.6.1.1.0.** Grouping equivalent writes brought the batch down from the original’s 119 statements to 18.
- **Query count can hide growth.** V2.5.1.0.0 still sent the same two reminders in 26 statements after adding 600 later appointments. Rows returned to Rails rose from 13 to 1,213. [Run report](reports/V2.6_Run_Report.md) · [Matched workload](benchmarks/V2.6_Compared_Workload.csv)

### The working baseline and the query rule

| Build | Behavior checks | Statements for two reminders with 600 later appointments | Decision |
|---|---:|---:|---|
| Original appointment-flow | Unmeasured on this suite | — | Historical baseline |
| V2.7.3.1.0 | 40 of 44 | 1,228 | Working full-rebuild baseline |
| V2.7.4.1.0 | 44 of 44 | 16 | Authored SQL in views and functions failed the Active Record rule |

[Matched comparison and decision](reports/V2.7.4_Candidate.md)

### The refactor on the original app

- **V2.7.5.1.0 checked where the query logic lives.** The refactor replaced handwritten SQL in the patient appointment query with standard Active Record.
- **Both app-owned indexes earned their place.** Fetching the same two visits went from 176 PostgreSQL buffer hits to three on the grown fixture. The external PMS schema stayed fixed.
- **All 330 measured requests preserved responses and cursors.** The full request still earned REVISE because patient authorization and one upcoming-history join scanned unrelated rows. [Query refactor](reports/PATIENT_APPOINTMENTS_REFACTOR.md) · [Index follow-up](reports/PATIENT_APPOINTMENTS_MIRROR_INDEX.md) · [Request metrics](benchmarks/V2.7.5_Patient_Appointment_Index_Workload.csv)

## How I decided which version was better

1. Compare the same caller, input, response, and persisted effects on frozen revisions. Use controlled rebuilds and scoped refactors to answer different questions.
2. Measure statements, rows returned, records loaded, writes, and elapsed time separately. Add unrelated history, grow eligible work, and replay the same request where appropriate.
3. Trace the entry point to the business rule and failure boundary. Test a small rule change in a disposable copy to see where a developer would make it.
4. Verify standard Active Record at the application query source. Rails-generated SQL is expected. Trace through schema objects so a model mapped to a handwritten query view cannot pass by appearance.
5. Record what the AI review fixed, where it missed a regression, and what the independent checks established. A scoped pass only establishes the behavior exercised in that scope.

One build per variant gives evidence about those builds. Host settings and the builder’s design choices also affect the result. The [version history](VERSIONS.md) marks historical observations, measured runs, prepared runs, and packaged proposals.

## Explore and reproduce

- Open `dashboard/index.html` in a browser from a local clone. The shared comparison starts with the original app. Later trials appear under Harness versions.
- Use the [version catalog](VERSIONS.md) for harness archives and [frozen application builds](snapshots/FROZEN_BUILDS.md) for the recorded revisions. Compare public archives against [SHA-256 checksums](SHA256SUMS.txt).
- Use the [launch prompt](reports/V2.5_Launch_Prompt.md), [benchmark CSVs](benchmarks/), and linked run reports to identify the workload and frozen checkpoints.
- The company-supplied take-home PDF is omitted from public files and nested archives. The public exports include the author’s code and screenshots. Original preflight expects the original reference inputs. The archive manifest records separate digests for source inputs and published exports.
