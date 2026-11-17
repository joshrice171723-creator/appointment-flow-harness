# AI usage in the Appointment Flow harness experiment

This record describes how Joshua Rice and Codex developed, tested, and revised the engineering harness. It records Joshua’s direction, AI contributions, and the evidence available for each run.


## Purpose and roles

Joshua’s objective was to find out whether the harness produces Rails and React code a developer can read, change, and run efficiently. The Appointment Flow assessment gave the builds a common product. Joshua preferred V2’s code quality even though V1 was the more mature application after about a week of iteration. He wanted human readability, ease of change, and performance to drive the harness decisions.

- **Joshua Rice** set the goals, supplied the versions and reference code, ran the rebuilds in RubyMine, challenged the AI’s conclusions, and chose which ideas to test next.
- **Codex in this conversation** inspected the packages, the available build receipts and source, and David’s GitHub review. It drafted and packaged harness instructions, wrote a comparison prompt, and verified the generated archives.
- **Coding and review agents in RubyMine** implemented and reviewed the apps. Statements about their tests or review are attributed to their recorded results. The V2.3 build log identifies its implementer as Codex GPT-6 and leaves the exact model variant unknown.

## How the harness evolved

### Compare builds, then extract general rules

Codex reviewed the V1, V2, V3, and former V4 packages. Its initial overall ranking put V1 first because of the mature application and operational workflow. Joshua corrected the evaluation target to code quality. V2 became the baseline for the next harness revisions.

The initial review also traced a defect in the former V4 build. If a PMS appointment was reassigned to another patient at the same clinic, its old notification history could appear in the new patient’s demo inbox. V2 and V3 explicitly rejected that identity change. This was a source finding. It shaped the discussion about whether a reviewer should exercise a workflow across its writes and visible result.

David’s review of V1 at `db037d7`, in GitHub issue #2, gave the discussion concrete examples. Joshua disputed finding #1 and focused on the general engineering lessons from the other questions.

| Review question | Harness lesson |
|---|---|
| The PMS refresh repeatedly read entire tables. | Inspect the volume of data that grows over time, the call frequency, and what happens when a read times out. |
| The shared-recipient check loaded clinic patient profiles to answer a yes-or-no question. | Express the result the caller needs in Active Record. Use scoped existence checks, filtering, or aggregation where the effective values are queryable. Inspect rows loaded as well as query count. |
| A failed clinic could trigger a retry of work across clinics. | Trace completed work, repeated work, and duplicate protection on retry. |
| Unrelated failures mapped to one exception type and HTTP response. | Identify expected failures at the right boundary. Preserve the cause and make the caller’s recovery path distinguishable. |

Source inspection showed that V2’s shared-contact test covered the intended confirmation outcome while the implementation still loaded clinic patients and visit history. Joshua redirected the work from replaying David’s individual findings to teaching a general query and review discipline. Other examples included a monthly range that could use ordinary Active Record, repeated aggregates per clinic, and sorting an association after preloading it.

### Use one service to understand the desired code

Joshua supplied successive versions of the PMS refresh service. The saved comparison contains the original `SourceRefresh`, the middle `SourceRefreshProposal`, and `SourceRefreshProposalV3` starting at line 230. Joshua preferred the third. Codex drafted the RubyMine prompt that requested the third review-only proposal.

Working through that example made the standard more concrete:

- Let the public entry point show the order of reads, validation, and writes. Use named private steps for the business decisions and substantial work they own.
- Use plain verbs for custom methods. Preserve familiar framework contracts such as `update!` when a failed save must abort the operation.
- Reject invalid inputs before unnecessary loading where consistency allows. Scope and reuse records the operation needs.
- Make transaction ownership visible. Handle expected dependency errors where their origin is known, preserve the cause, and handle recovery at the operation boundary.
- Use a savepoint for an intentional recovery path. Persist a failure marker at the transaction boundary where it can survive rollback.

The third proposal was a design reference. Its caller integration and runtime cost were outside the comparison. Codex extracted it into `SourceRefreshProposalV3.txt` and gave Joshua a read-only prompt asking the builder to compare the actual services, review results, and documented tradeoffs. Joshua supplied the builder’s reply after freeze.

### Revise the harness and review the output

| Version | What changed | Evidence and finding |
|---|---|---|
| **V2.1** | Added guidance for efficient Active Record, readable workflows, clear transaction and failure behavior, and source-based independent review. | Built in RubyMine. Its recorded final gate passed 26 backend tests and 86 assertions. The browser smoke passed. There were service-like classes under `app/models`, and one workflow controller combined staff actions, contact verification, and reporting. |
| **V2.1.1** | Added AI grading and repair. The agent grades, fixes, reruns checks, and regrades until the required criteria and final checks pass. Evidence belongs in `review/RUBRIC_RESULTS.md`. | Archive preflight passed. Joshua confirmed this branch had yet to be build-tested. |
| **V2.2** | Revised the tested V2.1 base. Added explicit Rails responsibility boundaries, an early trace of the first write path, a route-map review, and phase timing. | Built and frozen. The source had focused controllers and service classes. Several services still mixed meaningful decisions and writes inside one large method. The independent review found and verified safety fixes, while the service-readability gap remained. The build log records about 50 minutes 32 seconds from captured Stage 0 start to freeze, with gaps in intermediate timestamps. |
| **V2.3.0.0.0** | Strengthened service guidance and required a success and rejection trace. The next test package kept the V2.3 number and added instructions to start with optional skills, style modes, and review plugins off. | Archive preflight passed. The finished app's recorded gate passed all eight checks, including 24 Rails tests, 67 assertions, three React tests, and browser smoke. The final gate took 218.119 seconds. The build log records about 45 minutes to freeze with approximate and overlapping phases. The pasted `RefreshSource` still combined several responsibilities in a single private import helper, prompting the follow-up comparison. |

**Important setup differences.** The V2.2 build log records that Joshua disabled Ponytail during the run. The V2.3 log records that required host guidance still included Ponytail full and that a preliminary memory lookup occurred before the clean-room exclusion was read. Optional plugins were unused in that run. Those records leave the effect of the harness wording, host guidance, and session setup unresolved. The archive, app checks, and a developer’s assessment of the code provide different evidence. A passing gate establishes its covered checks.

### What the V2.3 follow-up review established

The builder compared frozen commit `6ac2c79` with the supplied proposal after the build. It reported that all 103 files in the frozen implementation manifest still matched. Codex in this conversation verified the commit identity and read the current source and both review receipts.

- The simplify receipt traces `ProcessReply`. The independent AI review gives its detailed success and failure trace to `RecordFollowUp`. It also inspects the importer and identifies appointment revision reuse and repeated database work. Repairs include fresh revision IDs, bulk lookups, and changed-only saves.
- The earlier pasted `RefreshSource` did per-appointment lookups. The frozen version loads contacts and visits once into hashes. It still reads the clinic’s full history under lock and repeats some contact reconciliation in Ruby. Those costs remain unbenchmarked.
- `RefreshSource#import` still combines contact verification, wall-time interpretation, revision decisions, and visit writes. The builder found no recorded decision justifying that grouping. The outer rescue can also classify local SQL failures as PMS read failures. Tests exercised rollback for replies and staff actions, with mid-import rollback left unverified in the review.
- The reference and final build make different policy choices, including clinic scope and how appointment identity changes are treated. The comparison was about how clearly each implementation expresses its decisions and failure guarantees.

The builder proposed a coverage table for every multi-step workflow. A tighter next experiment is a brief inventory of material workflows with targeted traces where an operation crosses data or transaction boundaries. For each material workflow, identify the main stages, the method that owns each decision, and one concrete rejection or write-failure path where it matters. Reuse existing evidence where it covers the relevant guarantee. This is a proposed harness change. V2.3 already asked for representative traces, and this run exposed the coverage that approach left open. The host’s Ponytail guidance remains an experimental variable, with no evidence tying it to the importer’s particular structure.

## Versioning and next experiments

Joshua chose version numbers to identify harness revisions. The forward format being discussed is `V<family>.<base revision>.<performance revision>.<AI loop revision>.<existing-code revision>`. Existing historical labels retain their documented meanings. The former V4 review package was first labeled V3.1 and then corrected to V3.1.1 because it added structured AI review to the V3 family. Codex updated its archive name, extraction folder, project title, manifest, and checksums, and verified all 173 ZIP members. The original V4 input ZIP and saved launch inputs identify the historical build.

Joshua wants one harness that infers the workflow from the request. A fresh build uses the clean-room instructions. A refactor preserves required behavior and verifies it against an existing revision. Feature delivery allows the requested behavior change and scopes restructuring to the work it needs. The dedicated performance component, shared workflow selection, and existing-code editions remain proposed in this record.

The planned order was to evaluate the full V2.3 rebuild first, then add the AI rubric and repair loop in a comparable full rebuild if the base result warranted it. After that, test refactoring against a fixed Git revision and finally test a feature request in an existing app. Use the same launch prompt, agent configuration, and shared evaluation where possible. Compare query and row growth on representative paths, test a small rule change after freeze, and record the effort and verified repairs from each grading round.

## Evidence and maintenance

Package preflight used the original verifier and the regenerated SHA-256 manifest, including the brief and all ten screenshots. Build and review evidence came from each experiment’s `notes/BUILD_LOG.md`, `review/INDEPENDENT_REVIEW.md`, `review/FREEZE_CHECKLIST.md`, and recorded gate or browser output where available. Codex used PowerShell, Python archive and hashing tools, source search, and the GitHub connector to collect and verify the material in this record.

### Harness artifacts

| Archive version | SHA-256 |
|---|---|
| V2.1 | `16174378b8a1d84d30fedd1efdeb685da546153eddf0eb919adb8d36a570086d` |
| V2.1.1 | `8728904680ff1329044cd5f387c6ca08b3c41d9721af5bdb50ca66792b0b474e` |
| V2.2 | `d24c4c22e0eb9d263f678f0989ce47028a09cd1392bfcd7c72e5d4fc315c2419` |
| V2.3.0.0.0 test package | `395c05e1011ea4eae58ecfaa47723a5ea9ef383c074cca135ad6181d5d3e5920` |

The V2.3 test package superseded a preflight-only draft with the same name. The digest identifies the package that contains the success-and-rejection review and the optional-skills setup. These are harness archive hashes. Application snapshots have their own records.

### Shared launch prompt

Codex supplied this wording for comparable rebuilds, based on the original V2 launch. The historical V2 and V3 launches used different wording.

```text
Execute the rebuild. Require the attached harness to pass its preflight verification first.

The goal is to build the Rails + React assessment application from scratch, using the harness to enforce code quality. Follow RUN_THIS_IN_RUBYMINE.md and proceed with implementation after preflight.
```

When adding a run, record the parent harness ZIP and checksum, exact launch prompt, model and host guidance, source revision or snapshot, actual test and review outcomes, and any changes to scope or setup. Report unknown information as unknown. Any candidate-authored assessment decisions remain Joshua’s responsibility.

## Query enforcement and the original-app refactor

Joshua clarified that Rails should generate SQL through standard Active Record. Handwritten application query strings and business rules implemented in SQL views or functions should fail the harness check. Codex added an executable query check and a separate review criterion. A negative control verified that the check detects models backed by handwritten views. A positive control verified that it accepts ordinary Active Record.

Joshua authorized a disposable clone of the original app. He required the builder to read the original AI usage and decisions, preserve public behavior, and keep the external PMS schema fixed. The app-owned database and mirror could support the workflow with their own indexes. Codex cloned the default branch and disabled pushing in that clone. In the first pass the old guidance stayed in the tree as archived context. A command-log audit found no direct reads of those files. The follow-up excluded the old guide directory from its working tree.

The AI builder replaced SQL strings in the patient appointment query, captured evidence for both cursor pages, and left clinic-wide scans visible in the grade. A second AI run used a reconstructed fixture to compare existing indexes, a mirror index, and both app-owned indexes on the same input within that run. All 330 measured requests matched across variants. The follow-up measured scans and index plans, tested migration rollback and reapply, and left the full-request performance grade at REVISE. Codex independently ran the focused suite and compared external schema dumps. The proposed patient access rewrite shown afterward was kept as a comment for manual review and did not enter these measurements.

Joshua authorized publication of his code and screenshots and kept the other company’s PDF private. The public archive records the original and export checksums separately. The public reports describe completed evidence, design-only packages, and prepared runs. The public dashboard keeps the original app in the comparison.

## Pairing the published runs

- Joshua asked for the instructions and resulting app in the same downloadable bundle. Codex traced the saved manifests, launch prompts, and frozen source to 28 pairs.
- The V2.5.1.1.0 standalone run used the alternate input archive. Codex verified its manifest against the build workspace.
- Two earlier matched builds ended before benchmarking. Their saved outputs remain available with an interrupted status.
- Joshua requested a quicker visual summary and removal of the unmeasured RubyMine AIR rows. The README now leads to the matched reminder benchmark, later behavior checks, and the original-app refactor.
