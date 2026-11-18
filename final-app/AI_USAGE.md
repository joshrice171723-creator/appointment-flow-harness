# AI usage

This record was compiled from the project history with AI assistance.

Josh wrote `DECISIONS.md`.

## Tools used and their roles

| Tool | Role |
| --- | --- |
| Codex | Interpreting the brief, exploring approaches, writing Rails/React code and synthetic data, refactoring, tests, debugging, and drafting technical documentation. |
| Codex subagents | Separate frontend, backend, readability, and review tasks during earlier passes. These were AI agents, not other developers. |
| Muse | An additional AI review of the packaged work. Josh brought its findings back to Codex and asked it to check the audit against the code. |
| Gemini | Additional AI assistance during development. |
| RubyMine | Opening the active checkout, reading and navigating Rails code and routes, and viewing app output in the Run console while comparing behavior in Chrome. |
| PowerShell, PostgreSQL, Docker, and Playwright/Chrome | Running setup, builds, database checks, backend tests, scale measurements, and browser checks. These are verification tools, not independent AI reviewers. |

Josh set the product and engineering direction, reviewed the app and its code, and evaluated proposed changes against the assessment. The implementation was written for this exercise with synthetic data; it was not copied from a current or former employer. Josh used several agents to obtain additional feedback.

## Why RubyMine became part of the workflow

Josh used RubyMine and Chrome to verify the active checkout directly. RubyMine brought the project files, controller navigation, Git changes, run configuration, and Rails request output into one development environment. Tracing a browser request through its route, controller action, and server output made it possible to compare what the code did with what the app showed.

Reading the code in RubyMine exposed concerns that the AI's earlier reviews had not resolved: the responsibilities combined in DeskController, the behavior hidden behind a custom transaction helper, and the difficulty scanning the routes file. RubyMine became a practical way for Josh to inspect, question, and direct the work. It was a development and inspection tool, not another AI reviewer or proof that the code was readable.

## Reusing the rubric

Josh plans to use the human code-quality rubric on future projects, beyond this take-home. The rubric now treats clear controller responsibilities and easy-to-find routes as part of the standard for readable code. The reusable standard is whether a human engineer can find entry points, understand responsibilities, and trace and change behavior. Project-specific examples and exclusions should be adapted before reviewing another project; the rubric's evidence requirements still apply.

## How Josh used AI during development

1. **Meta-prompting / reverse prompting.** Josh asked AI to help construct better prompts for deep investigations, including edge cases, untested assumptions, and questions that could expose gaps in the design.
2. **Requirements audits.** Josh asked AI to compare the implementation and submission documents against the assessment and flag missing requirements or contradictions.
3. **Adversarial review.** Josh explicitly asked AI to challenge his choices and look for ways the system could fail, rather than assume the current design was correct or simply approve it.
4. **Multi-agent review.** Josh used other agents to double-check implementations, proposed fixes, and earlier findings. Josh also asked one agent to verify another agent's criticism against the code.
5. **Iterative refinement.** Josh repeated the build, review, correct, and verify cycle, including removing work that did not justify its complexity.
6. **Rubric-guided evaluation.** Josh used the [human code-quality rubric](docs/ai-harness/apex-human-code-quality-rubric-2026-11-06.md) to set a written standard for readability, maintainability, correctness, and proportion. Josh challenged high grades when the evidence did not support them.
7. **Edge-case analysis.** Josh asked AI to investigate ambiguous replies, shared numbers, missing records, guardians, permissions, time zones, and other situations that could break the expected workflow.
8. **Regression testing.** Josh used AI to help turn demonstrated defects into tests and check that corrections did not break existing behavior.
9. **Performance benchmarking.** Josh used AI to help run and interpret scale checks, measure processing times, and verify that repeated reminder runs did not send duplicates.
10. **Consistency reviews.** Josh asked AI to find disagreements between the code, screens, documentation, fixtures, tests, and observed behavior.
11. **Decision challenges and research.** Josh used AI to question technical choices and investigate whether the reasoning behind them held up, including vendor eligibility and the source-system boundary.
12. **Evidence-based verification.** Josh asked for code references, reproducible examples, and executed checks to support findings. An AI score or several agents agreeing was feedback, not proof.
13. **Human-directed oversight.** Josh set the product direction, questioned assumptions, reviewed results, and corrected or rejected suggestions.
14. **Implementation assistance.** Alongside these review techniques, Josh used AI to help write and revise code, tests, synthetic data, and technical documentation. AI helped implement the project as well as review it.

## Product and engineering decisions Josh led

These examples show how Josh evaluated AI suggestions, tested assumptions, and made decisions about what belonged in the final app.

### Scope and the examiner's experience

1. **The demo clock.** Josh questioned why the examiner needed to understand a second clock when real sync timestamps were displayed beside simulated dates. Initially Josh asked for advancing the day to update fake PMS outcomes, then rejected the whole time-travel feature as unnecessary complexity. Setup now generates dates relative to the current time, and runtime uses real time. The old clock controls and outcome simulator are no longer relevant to the final workflow; frozen time remains useful in tests.

2. **Growing the clinic hierarchy.** Josh originally explored organizations, clinics, locations, partner leadership, and feature pilots to see the possibilities. Josh later decided the extra hierarchy weakened alignment with the supplied schema and asked to remove the location table and related behavior. This was a deliberate scope reduction, not an AI-only invention. The final app uses clinics directly.

3. **Putting the full workload in the demo.** Josh rejected making the examiner navigate 60 clinics merely to demonstrate scale. Josh chose two clinics for interactive review and a separate performance test using the stated workload. The large fixture remains relevant to measurement, but not to normal dropdowns or the walkthrough.

4. **An extra Reviewer persona.** Josh questioned why a fourth identity had been added when the assignment named three audiences. Josh requested three distinct entrances for Patient, Front desk, and Leadership, and removed patient-simulator links from staff screens. The simulator is intentionally separate so reviewers can experience the patient side without confusing it with a staff action.

5. **Extra dashboards and controls.** Josh removed communication-cost reporting, feature-pilot/settings controls, the general Demo Tools section, and time-spent entry. Some supported earlier explorations, but did not earn their place in this small confirmation tool. Cost remains a vendor-selection consideration; an expense-reporting feature does not.

6. **Passwords and typed Reset confirmation.** After an audit recommendation, Codex added a reset token, credential checks, and session hashing. Josh rejected the examiner friction: this is a disposable assessment with synthetic data. Josh also rejected typing RESET. The in-app reset was later removed. Ordinary request protection and the source database permission boundary remain. The removed gate is evidence of evaluating an audit suggestion against the actual assignment rather than accepting it automatically.

7. **Promotional copy and unnecessary mobile work.** Josh rejected hero copy, slogans, and product pitches inside a working tool. Josh also stopped AI from treating mobile support as unfinished work. The accepted target is standard desktop monitors with functional labels, useful tooltips, and keyboard access.

### Respecting the supplied source and real data problems

8. **Building more of the PMS than requested.** Josh repeatedly challenged booking, rescheduling screens, and suggestions of a PMS editing website. Developers control the synthetic seed; Appointment Flow only reads the source. Josh first asked for two apps and an API to make that boundary obvious. The later audit simplified that demonstration to one Rails app reading two databases with a SELECT-only source role. The boundary remains; the extra service is no longer needed.

9. **An extra attendance/outcomes model.** Codex argued that showing leadership results required another table and introduced arrival times and synthetic outcome overlays. Josh returned to the supplied statuses, chose broken = rescheduled and unscheduled = canceled as demo assumptions, and removed the extra tables. On-time reporting and runtime-invented outcomes became irrelevant because the source does not supply arrival timestamps. Those status meanings remain assumptions to confirm, and the resulting completion measure cannot establish exact no-show reduction.

10. **Uniform phone numbers and unsafe cleanup.** Josh noticed that the seed did not exercise the brief's free-text phone field. Josh requested punctuation variants, country prefixes, missing data, and junk, plus malformed email cases. Josh rejected wording suggesting the app could force PMS staff to enter clean data. The system must preserve the source, normalize recognizable formatting, reject unsafe destinations, and use another permitted channel when available.

11. **Hiding the original invalid number.** Josh identified that the staff view hid the original PMS entry behind the message "No valid phone number." The staff view now shows the original entry and separately indicates whether it can be used for SMS. Rejecting it for automatic delivery should not erase information staff need to inspect.

12. **Contacting a child or overlooking the guarantor.** Josh explicitly required following the minor's guarantor link and using the adult's contact information even if the child had their own number. The implementation also checks adult authorization and channel permissions. If the birthdate is missing, the system cannot determine whether the patient is a child or an adult, so automatic outreach is blocked and the front desk gets a task to fix the birthdate instead.

13. **A patient link revealing details.** Josh challenged the early name-bearing appointment page and the complexity of a confirmation portal. Josh requested simple SMS and email simulations with free-text input. Names, procedures, and confirmation links were removed from the reminder content; clinic/date/time remain. This was a privacy-risk and scope correction, not an independently established legal finding about HIPAA.

14. **Unrealistic or hard-to-follow fixtures.** Josh rejected mixed real-looking and demo names, large generated patient numbers embedded in names, and alphabetical sorting that put 130 after 13. Josh chose the same Demo Patient name for all patients, actual database IDs to distinguish them, and numeric selection order. Josh also limited patient reuse while preserving multiple visits in one week.

15. **Empty histories behind impressive totals.** Josh noticed very few resolved cases and missing conversations despite leadership showing many replies or confirmations. Josh asked for historical messages, reviewed declines, unclear responses, and resolved follow-ups supporting the demonstration, including roughly 10% historical negative replies in Austin's messaging cohort. Phoenix stays comparison-only. A direct YES does not require a resolved staff ticket; a staff-handled concern should have a traceable outcome.

### Outreach and the work staff actually need to do

16. **Checking everything every 30 seconds.** Josh challenged repeated full pulls and the idea that front-desk staff might need to run a rescan manually. Josh asked how new appointments would enter the sending backlog. The app now refreshes automatically every five minutes and runs a daily clinic send batch at 10 AM with catch-up before 6 PM. Appointments and send history provide the backlog. The earlier estimate equating daily appointment volume with snapshot size was also corrected; those are different quantities.

17. **Testing the first reminder cadence.** Josh explored Friday bulk outreach and grouped weekly visits, briefly considered a rolling window, then asked for an audit that treated none of those decisions as automatically correct. The accepted policy became day-7 SMS, unanswered day-6 email, unanswered day-3 request, and day-1 reminder/request. Earlier weekly grouping is no longer the current behavior and must not imply that one ambiguous YES confirms several appointments.

18. **Keeping the day-before courtesy reminder.** Josh explicitly wanted a day-before courtesy reminder even when the patient had confirmed early. Josh distinguished that message from another confirmation request and gave recent emergency bookings as a reason to avoid unnecessary repetition. Codex initially placed email on the wrong day and included a reply request in the confirmed courtesy template; Josh corrected both. The final schedule balances message cost with usable reminders rather than minimizing sends alone.

19. **Treating every YES-containing message as confirmation.** Josh wanted simple affirmative variants recognized, but "yes but call me," NO, and unclear wording routed to staff. Josh also required the tester to type arbitrary text rather than use only fixed buttons. Later matching checks addressed shared numbers and multiple appointments so the selected simulator screen could not stand in for a real, unambiguous reply match.

20. **Mixing a decline, cancellation, and no-show.** Josh questioned a row showing Replied NO beside a no-show outcome and explained the expected staff follow-up. The correction separates what the patient said from what staff/PMS recorded. NO needs review; it does not itself modify the booking or establish whether the patient attended. The later status assumptions also limit which attendance claims the report can make.

21. **Past appointments remaining in the active queue.** Josh pointed out that calling about an already completed or missed appointment does not help fill that upcoming chair. Josh explicitly excluded post-visit recovery even though a larger patient-flow product could support it. Past or otherwise finished work leaves the active queue, while its history and any unrelated upcoming appointment work remain.

22. **Unclear reasons for Needs attention.** An earlier discussion excluded no-contact cases; Josh later explicitly requested visible blocked-contact work alongside appointment follow-up. Josh required distinct pills for a reply needing review, no response within 48 hours, and reminders blocked by missing/unsafe data. Josh's latest refinement adds reason filters and a dynamic "appointment in X hrs" label, with nearest unanswered appointments first. The label changes; the 48-hour entry rule does not.

23. **Duplicate forms and irrelevant ownership labels.** Josh challenged separate contact-attempt and outcome forms that repeated the same selector and notes. They became one form where an attempt keeps work open and a final outcome closes the relevant issue. Josh also rejected "Unassigned" on resolved cards: historical work should identify the resolver and outcome, including automatic closure, rather than reuse an active-ownership label.

24. **Arbitrary deadlines and fragmented activity.** Josh asked what a due timestamp meant when passing it did not change anything and it appeared unrelated to the appointment. The UI now emphasizes the appointment time and reason for action; internal timestamps can still order work. Josh also combined Message receipts with the activity log and requested a date-driven appointment view, replies, separate PMS outcomes, and the provider name staff need on a call.

### Judging and directing the AI's work

25. **The Rails migration losing the original experience.** Josh chose Rails and React for the implementation and checked that the rewrite retained the earlier Flask board, visual status distinctions, detail layout, and leadership comparison. Josh's reference was the earlier product experience, not just a checklist against the brief. Codex restored those concepts; changing frameworks was not a reason to lower usability.

26. **Making execution paths easier to follow.** Josh asked for readable Active Record code and found that several revisions still used dense SQL or left old code paths in place. Josh extended the review from one query to the frontend and backend and evaluated how the pieces worked together. The review found that splitting code into services, models, and serializers had not made the request flow clear. Later work removed internal flattened hashes, circular coordinator delegation, duplicate paths, and vague names. Remaining SQL is deliberately at database-specific boundaries. The standard is whether a human can trace and change the behavior.

27. **Verifying another agent's audit against the code.** Josh sent packages to Muse, then asked Codex to audit Muse's findings against the actual code. Muse retracted the batch-marker failure claim after the transaction boundary was established. Proposed timestamp/truncation protections did not already exist, and a 45-day import window was unsafe with missing-row retirement. Other findings, including read-only GET screens, outage behavior, language handling, and readability, drove changes. An external AI review was another source to examine, not an authority to follow blindly.

28. **Keeping the send window consistent.** Muse caught one path using 9 AM while another used 10 AM after earlier reviews said the work was ready. Josh explicitly authorized one 10 AM–6 PM constant, a drift regression, named policy/lock constants, and clearer names. This correction matters because the AI's earlier confidence did not establish rule consistency.

29. **Stale and dead code surviving cleanup.** Josh requested a dedicated audit and then removal of the confirmed leftovers. Codex deleted an unused pending-change method, an unused event scope, and unused CSS, and reused the shared setup lock. A completed refactor must remove superseded code and stale instructions, not just add the new path.

30. **Separating controller responsibilities.** In RubyMine, Josh identified that DeskController handled front-desk, patient, and leadership requests, and that a shared transaction helper made the request flow harder to follow. He set a clearer boundary for each area. Codex separated the front-desk, patient, leadership, and workspace entry points. In the current code, ApplicationController handles CSRF, access failures, and shared error responses. RecordFollowUp owns the staff follow-up transaction, and ReceiveReply owns the patient reply transaction. The review showed why passing tests and rubric scores alone could not settle whether the code was easy to follow.

31. **Making routes easier to find and review.** Josh identified route discoverability as the next issue after the controller split. Codex separated browser-page routes from API routes and grouped the current API by workspace selection, front desk, patient inbox, and leadership. The reusable rubric now checks whether an engineer can find entry points and see which controller owns them, without prescribing a fixed format or controller count.

32. **Moving database setup to Rails migrations and Ruby seeds.** While reviewing setup in RubyMine, Josh found that SQL scripts combined schema changes, upgrade steps, and demo data. He directed Codex to use versioned Rails migrations for schema changes and Ruby seeds for synthetic data, giving each responsibility a clear place.

    Josh chose to retire the upgrade paths for older copies of the demo. For this disposable assessment, he prioritized a setup that reviewers could rebuild directly. Synthetic source records belong in the replica seed, while clinic settings and staff come from configuration. Messages, replies, and follow-up history are generated through the application’s normal workflows so reviewers can trace the examples back to the code that creates them.

    The replica retains the assignment’s supplied tables, and the running application accesses it through a SELECT-only connection. PostgreSQL-specific setup SQL remains for tasks such as creating database accounts and granting permissions. Rails migrations and Ruby seeds now own the table definitions and example data.

33. **Setting performance targets and leading the test audit.** The initial backend test phase took **13 minutes 44 seconds**. Josh called for a performance audit and set a one-minute target for the entire command, including startup and database setup. When the initial diagnosis focused on the cost of one reset, he brought the focus back to the cumulative cost across the suite. The audit found that 52 test setups rebuilt the entire demo.

    - **Seeding and fixture setup.** Codex reduced seeding overhead and replaced repeated rebuilds with copies of a saved baseline. All 79 tests passed, but the full command still took **8 minutes 10 seconds**, well above the target Josh had set.
    - **Test-by-test code review.** Josh directed a review of each test to find avoidable work without waiting for timing results. It found repeated deletes and inserts across 16 tables, redundant cleanup, and seed tests that rebuilt the same data. Codex changed most tests to reuse one seeded state and roll back their changes, while keeping dedicated paths for real commits, concurrent workers, and full resets. All 82 tests passed in **1 minute 54 seconds** end to end.
    - **Test environment and startup.** Josh set a stretch goal of under 30 seconds. Codex disabled Rails code reloading during tests, reused identical responses, and simplified startup. The fastest complete run passed all 82 tests in **53.1 seconds**, an 89% reduction in elapsed time from the earlier **8 minutes 10 seconds**. A repeat of the standard command took **76.5 seconds**. Separate Ruby workers and a boot cache did not beat the best serial run and stayed out of the project. The best run met the one-minute target; the 30-second goal was not reached. The [performance audit](TEST_PERFORMANCE_AUDIT.md) records the timings and run conditions.

34. **Replacing the in-process reminder thread with Sidekiq.** Josh challenged keeping automatic reminders in a thread inside the web server and asked for a minimal Sidekiq implementation to better reflect production background-job processing. The direction was to preserve the existing UI and reminder rules while moving execution into a separate worker, with explicit retries and failure handling. Codex added one job, Redis, and a five-minute schedule, removed the old thread, and updated Docker setup. All 85 backend tests passed, including retry and duplicate-delivery checks; a live source outage also produced a Redis retry that completed after recovery. This adds a worker and Redis to operate; it does not by itself establish production readiness.

35. **Removing duplicate callback counts.** Josh spotted that the Operations report showed two YES-like replies sent to the front desk, one asking for a call, and that same callback again as staff work. Josh pushed back when Codex proposed hiding the two rows while keeping their backend counters. Josh directed the removal of both report fields and the callback-only classification. A plain YES can still confirm an eligible appointment, and a YES with a request still goes to staff review when there is a current appointment to review.

36. **Catching misleading appointment links in reply review.** While trying the patient reply workflow, Josh noticed that sending “test test” produced two follow-up items that made it look like the reply had already been matched to an appointment. The items also hid the reply text. Josh asked Codex to trace the behavior before changing the code. The appointment links represented possible matches, and the existing form recorded appointment outcomes without letting staff clarify which appointment the reply concerned. Josh directed Codex to show one review task per reply, display the actual text and possible appointments, and let staff record whether the reply applied to one, both, or remained unclear. The practice management system stays read-only. The build and migrations completed, and automated testing remained paused at Josh’s request.

37. **Challenging the leadership page's performance and the proposed fix.** Josh noticed slow month-detail loading and said that showing the table before its numbers arrived had made the experience feel worse. He challenged the inconsistent timings, asked Codex to trace every API call before blaming CPU, and asked for a concrete way to reduce the work. He proposed a `LeadershipReport` snapshot updated by the five-minute worker, questioned whether a fixed ID would keep returning the first report, and suggested rebuilding only when source data changed. The discussion distinguished source appointment changes from app-side messages, replies, follow-ups, and time passing, which also affect the report.

    Josh then asked whether the demonstrated database aggregation could use Active Record and chose live calculation instead of saved reports. He also questioned whether preloading every month's detail was necessary if the backend became fast enough. Codex replaced record-by-record appointment and issue counting with grouped Active Record queries, limited reply events to the patient events used by reporting, projected message links without constructing full models, and reused clinic time zones. Month selection still requests its detail. No reporting table, cache, worker, or dependency was added. Josh requested before/after measurements, completion of the deferred tests, and this record of his pushback. The [performance report](docs/performance.md#leadership-report-performance-evidence) records the measurements and their limits.

38. **Building review guides from the supplied books.** Josh asked Codex to turn selected passages into practical guidance for Rails and React. Codex drafted the guides and linked their review criteria to the relevant book passages and framework documentation. Josh directed Codex to make both checklists usable by an AI reviewer through source traces and executed checks, with unverified criteria marked explicitly. See the [Rails guide](docs/ai-harness/Ruby-and-Rails-Coding-Guide.md) and [frontend guide](docs/ai-harness/Frontend-Coding-Guide.md).

39. **Tracing Rails writes and the patient workspace.** Codex gave source reconciliation, reply handling, and staff actions distinct entry points and added request checks for what persists when a staff action is rejected after a successful source refresh. Codex also separated the backend and frontend directories and brought staff follow-up, appointment history, and local patient detail verification into one patient workspace. The contact workflow holds reminders when verified details conflict with the PMS. On the frontend, Codex traced delayed reads and uncertain writes, and added browser cases for preserving drafts and keeping feedback tied to the correct record.

40. **Investigating the slow seed test.** Codex traced the extra work to a test replaying 135 historical appointments through the reminder, reply, and staff-action workflows. It reduced that test to six representative appointments covering backup email, confirmation, no response, staff resolution, and repeat setup. The change was verified in later suite runs. The test's individual speedup was not measured.

41. **Profiling the 4,000-message batch.** Josh set a 30-second target. Codex traced repeated reconciliation work and grouped appointment locks, lookups, and inserts while retaining validation and the transaction. The [performance report](docs/performance.md#reminder-batch-and-setup) records the result and the unmet target.

42. **Regrading after a targeted readability change.** Josh asked Codex to apply the original rubric in a disposable checkout. Codex made confirmation and follow-up closure visible to their callers and checked visit eligibility under the row lock. The [code quality history](docs/code-quality-history.md) records the AI review scores and the checks run on each revision.

## Other issues found through review and checks

The later audit found that imported calendar changes could still be shown with an older visit's confirmation before reconciliation, that valid BIGINT clinic IDs could fail in a lock call, and that a later decline could remain in the Confirmed filter. Codex added regressions and corrected those paths. These were defects found after earlier passing checks, not new product features Josh wanted to add.

Other checks caught stale success feedback after switching patients, a delayed reply response affecting the wrong selected conversation, malformed snapshot handling, backup-email timing, and a fresh-install test trying to reset a source database before it existed. The fixes kept display wording separate from reason codes and resolver attribution, preserved cached data after failed imports, and made the test setup handle a genuinely empty installation.

The new work-type/countdown browser test initially left an automatic refresh request in flight during teardown. Codex fixed the test cleanup and reran it. This was a test-lifecycle issue, not evidence that the patient inbox had stopped working.

## Research used during the discussions

Josh asked AI to help investigate reminder timing, vendor costs and agreements, and human code quality. The research informed questions and tradeoffs rather than supplying a universal dental cadence or an official hiring score. Provider eligibility and terms still need checking before production.

- [Reminder timing study](https://www.ajmc.com/view/optimizing-number-and-timing-of-appointment-reminders-a-randomized-trial)
- [HHS appointment-reminder guidance](https://www.hhs.gov/hipaa/for-professionals/faq/are-appointment-reminders-allowed-under-hipaa-without-authorization/index.html)
- [Twilio eligible services](https://www.twilio.com/content/dam/twilio-com/global/en/other/hipaa/pdf/HIPAA-Eligible-Services.pdf) and [account requirements](https://www.twilio.com/docs/iam/twilio-editions/hippa)
- [AWS eligible services](https://aws.amazon.com/compliance/hipaa-eligible-services-reference/)
- [SendGrid policy](https://www.twilio.com/docs/sendgrid/ui/account-and-settings/hipaa-compliant)

Josh asked for a human readability rubric informed by engineering guidance, then used its criteria to direct reviews and corrections. The [rubric](docs/ai-harness/apex-human-code-quality-rubric-2026-11-06.md) is included with the submission. It evaluates reader effort, ownership of business rules, traceability, and ease of change.

## Final readability review and corrections

- AI consolidated the case and calendar reply presentation, replaced implicit staff-action hashes with explicit inputs, and made critical reply tests state their own contact and appointment relationships.
- AI made the importer own its transaction and added failure locations to runner logs without including exception messages that could contain patient text.
- Josh clarified that the demo should grant messaging permission until revoked. Imports now create missing grants in the app database without restoring revoked channels or clearing STOP records. Guardian authorization remains a separate check.
- Josh required another adversarial review, executed checks, and a comparison of the extracted final package with the verified files.

## What the checks establish

Josh asked for backend tests, browser checks at both supported desktop sizes, scale measurements in disposable databases, and verification of extracted review packages. A passing checkout and a tested ZIP are different evidence; a code change after packaging requires a new package check.

Passing tests do not establish production readiness or a real reduction in no-shows. The benchmark uses fake delivery, source imports still read full tables, and reporting grows with retained history. Real provider delivery needs durable reconciliation because an external send cannot roll back with the application database.
