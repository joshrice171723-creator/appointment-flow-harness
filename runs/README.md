# Paired runs

Each run ZIP has the harness input and the application output. The evidence column shows what the records verify. The public ZIPs exclude the company PDF.

See the [version catalog](../VERSIONS.md) for design packages V2.1.1 and V2.8.4.1.0. The [historical source archive](../snapshots/Appointment-Flow-All-Versions-Source.zip) includes the older V26 snapshot. Its harness input remains unverified.

| Run | Scope | Evidence | Download |
|---|---|---|---|
| Original appointment-flow | Historical product control | Includes the preserved project guidance. No single frozen launch input is documented | [Paired ZIP](Original.zip) |
| V2 | Historical source and harness | Archived input manifest matches the saved application workspace | [Paired ZIP](V2.zip) |
| V2.1 | Historical source and harness | Input manifest matches the nested harness preserved with the application | [Paired ZIP](V2.1.zip) |
| V2.2 | Historical source and harness | Version-associated archives. No matching launch receipt was recovered | [Paired ZIP](V2.2.zip) |
| V2.3.0.0.0 | Historical source and harness | Archived input manifest matches the saved application workspace | [Paired ZIP](V2.3.0.0.0.zip) |
| V2.4.0.0.0 | Historical source and harness | Version-associated archives. No matching launch receipt was recovered | [Paired ZIP](V2.4.0.0.0.zip) |
| V2.4.1.1.0 | Historical source and harness | Archived input manifest matches the saved application workspace | [Paired ZIP](V2.4.1.1.0.zip) |
| V3 | Historical source and harness | Input manifest matches the nested harness preserved with the application | [Paired ZIP](V3.zip) |
| V3.1.1 | Historical source and harness | Archived input manifest matches the saved application workspace | [Paired ZIP](V3.1.1.zip) |
| V2.5.0.0.0 | Standalone full rebuild | Input manifest matches the launched workspace. The application is the recorded frozen build | [Paired ZIP](V2.5.0.0.0.zip) |
| V2.5.1.0.0 | Standalone full rebuild | Input manifest matches the launched workspace. The application is the recorded frozen build | [Paired ZIP](V2.5.1.0.0.zip) |
| V2.5.1.1.0 | Standalone full rebuild | Input manifest matches the launched workspace. The application is the recorded frozen build | [Paired ZIP](V2.5.1.1.0.zip) |
| V2.6.1.1.0 | Standalone full rebuild | Input manifest matches the launched workspace. The application is the recorded frozen build | [Paired ZIP](V2.6.1.1.0.zip) |
| V2.7.1.1.0 | Standalone full rebuild | Input manifest matches the launched workspace. The application is the recorded frozen build | [Paired ZIP](V2.7.1.1.0.zip) |
| V2.7.2.1.0 | Standalone full rebuild | Input manifest matches the launched workspace. The application is the recorded frozen build | [Paired ZIP](V2.7.2.1.0.zip) |
| V2.7.3.1.0 | Standalone full rebuild | Input manifest matches the launched workspace. The application is the recorded frozen build | [Paired ZIP](V2.7.3.1.0.zip) |
| V2.7.4.1.0 | Standalone full rebuild | Input manifest matches the launched workspace. The application is the recorded frozen build | [Paired ZIP](V2.7.4.1.0.zip) |
| V2.6.1.2-staff-refactor | Staff appointment refactor | Preserved launch prompt and guidance paired with the completed source | [Paired ZIP](V2.6.1.2-staff-refactor.zip) |
| V2.7.1.1.1-staff-refactor | Staff appointment controller refactor | Preserved launch prompt and guidance paired with the completed source | [Paired ZIP](V2.7.1.1.1-staff-refactor.zip) |
| V2.7.2-original-refactor | Original-app refactor with historical guidance present | Preserved launch prompt and guidance paired with the completed source | [Paired ZIP](V2.7.2-original-refactor.zip) |
| V2.7.2-original-isolated | Original-app refactor with prior guidance excluded | Preserved launch prompt and guidance paired with the completed source | [Paired ZIP](V2.7.2-original-isolated.zip) |
| V2.7.3-refresh | Scoped refresh refactor | Preserved launch prompt and guidance paired with the completed source | [Paired ZIP](V2.7.3-refresh.zip) |
| V2.7.3-cold-write | cold_writes | Preserved launch prompt and guidance paired with the completed source | [Paired ZIP](V2.7.3-cold-write.zip) |
| V2.7.4-recipient | recipient_decision | Preserved launch prompt and guidance paired with the completed source | [Paired ZIP](V2.7.4-recipient.zip) |
| V2.7.5.1.0 query refactor | Patient appointment query before the index follow-up | Launch prompt and supplied guidance match recorded input hashes. Ten paired HTTP responses matched | [Paired ZIP](V2.7.5.1.0-query-refactor.zip) |
| V2.7.5.1.0 | Patient appointment refactor and app-owned index follow-up | Follow-up guidance hashes match. All 330 request measurements had matching bodies and cursors | [Paired ZIP](V2.7.5.1.0-mirror-followup.zip) |
| V2.4.1.1.0 paired trial | Earlier matched rebuild attempt | Partial application source from an interrupted trial. No completed benchmark | [Paired ZIP](V2.4.1.1.0-paired-interrupted.zip) |
| V2.5.1.1.0 paired trial | Earlier matched rebuild attempt | Partial application source from an interrupted trial. No completed benchmark | [Paired ZIP](V2.5.1.1.0-paired-interrupted.zip) |
| V2.8.5.1.1-rebuild | Standalone full rebuild | The app passed its own rubric and 42 of 44 separate checks. The contact query still grows with source data | [Paired ZIP](V2.8.5.1.1-rebuild.zip) |
| V2.8.5.1.1-refactor | Patient appointment read refactor on the original app | Response bodies and cursors matched. One upcoming-history query still scans the mirror | [Paired ZIP](V2.8.5.1.1-refactor.zip) |
| V2.8.5.1.1-refactor-repair | Focused patient history query repair on the original app | The tested patient reads passed. All response bodies and cursors matched. The external PMS schema stayed the same | [Paired ZIP](V2.8.5.1.1-refactor-repair.zip) |
| V2.9.5.1.1-rebuild | Standalone full rebuild | The input manifest and prompt match the launch receipt. Includes first and final source checkpoints plus the observed checks | [Paired ZIP](V2.9.5.1.1-rebuild.zip) |
| V2.10.6.3.1-full-build | full build | Archived export `9a5dbce`, evaluated on V1.1.0. See the separate paired run for the repaired clean-room freeze `5f2500c`. | [Paired ZIP](V2.10.6.3.1-full-build.zip) · [Clean-room comparison](../reports/V2.10.6.3.1_Clean_Room_Comparison.md) |
| V2.10.6.3.1-original-refactor | original refactor | Frozen original-app refactor. Evaluated on V1.1.0. | [Paired ZIP](V2.10.6.3.1-original-refactor.zip) |
| V2.10.6.2.1-full-build-refactor | full build refactor | Directed refactor with benchmark exposure. Use it to study repair. Its frozen revision has no independent V1.1.0 score. | [Paired ZIP](V2.10.6.2.1-full-build-refactor.zip) |
