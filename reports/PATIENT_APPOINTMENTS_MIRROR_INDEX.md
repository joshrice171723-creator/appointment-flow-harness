# Patient appointment history indexes

## Scope and database ownership

This follow-up starts at `db037d7932b13fc4d735106e0fa199815fb2d22c` with appointment query blob `27b14d31870a59d5fe0f5b67aad98cc8270572cc` and workspace test blob `fa3f019995e058b6ba352b2ffbd1f9fde642abad`. The prior review records the query refactor and its behavioral contract. Appointment query, workspace test, [prior review](PATIENT_APPOINTMENTS_REFACTOR.md)

Pages 2–3 of the PMS assignment define `appointments.id`, `clinic_id`, `patient_id`, and `start_at`. The timestamp represents clinic wall time. `PmsReplica` reads the external database through the reader connection. `PmsSnapshot` copies supplied fields to the application database. Before and after the probe, the disposable external database exposed the same primary key and `appointment_window` index. Its `pms_reader` could select from all three PMS tables and lacked insert, update, delete, and truncate privileges on each. PMS assignment, PmsReplica, PmsSnapshot

The Rails migration builds two nonunique B-tree indexes in the application database. `appointment_patient_history` indexes the mirror by `(clinic_id, patient_id, start_at, id)`. It supports the equality scope, date range, and chronological or reverse-chronological order. `visit_appointment` indexes `desk.visits(appointment_id)` across all revisions. Hydration filters by clinic and patient and sorts the matched revisions by descending visit ID. PostgreSQL uses the existing partial `visit_current` index for the current-visit lookup in patient detail. Rails migration, hydration query

## Paired request measurements

The prior run removed its temporary fixture driver. I reconstructed the workload from its review and saved request traces and used the same Rails workload probe and standard test fixture. The reconstruction matches the prior table counts, date boundaries, page ordering, and cursor-page body hash. Other body hashes compare within this run because synthetic record details and generated tokens can differ across runs. Rails workload probe

Staff member 11 signs in to clinic 1 through Rack. Time is frozen at November 5, 2026 at 10 AM Chicago time. Mixed patient 8000000 has 54 completed source appointments at the previous day's tied wall timestamp, two scheduled just after the boundary, one scheduled at it, and four visit revisions. The visits exercise a newer revision of a completed source row, an orphan with separate pagination and serialized dates, and an orphan at the past tie. Patient 8000001 has 54 past tracked-only IDs one second apart. Growth adds 5,000 older source appointments with corresponding visits, 5,000 older mixed-patient tracked-only IDs, and 5,000 older tracked-only patient IDs. The additional dates start 40 days before the reference wall time and run backward one second per ID. App table totals are 577 appointments and 278 visits before growth and 5,577 appointments and 15,278 visits after it.

Each size used the existing indexes, then the mirror index, then both indexes on the same records. The probe recorded 11 warmed calls per request and variant, for 330 measured GETs. It timed routing, authorization, queries, and serialization in Rack on Windows Ruby 3.4.10, Active Record 8.1.3.1, and PostgreSQL 17.11. Fixture writes, `ANALYZE`, index builds, assertions, and plan capture were outside the timed requests. Index variants ran in a fixed order, with uncontrolled machine load. Median request times are descriptive. For example, the grown mixed first page ranged from 120–158 ms on the baseline and 123–363 ms with both indexes, even though its measured hydration work fell.

Every measured request returned HTTP 200. Bodies and cursor values matched byte for byte across variants and sizes, including page two fetched with page one's cursor. Assertions checked the exact two-page ID order, the orphan's recorded confirmation and revision order, and the scheduled appointment selected one microsecond after clinic wall time. All 330 calls recorded zero write statements and zero affected rows. Counts below apply to every size and variant. Executed statements include transaction control and exclude cache hits.

| GET request | Statements | Cache hits | Rows returned | Largest read | Rails records | Body bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Mixed past, first page | 18 | 1 | 61 | 26 | 35 | 7,893 |
| Mixed past, cursor page | 10 | 0 | 56 | 26 | 30 | 7,704 |
| Mixed upcoming history | 18 | 1 | 13 | 2 | 11 | 1,146 |
| Mixed patient detail | 18 | 1 | 12 | 1 | 7 | 1,920 |
| Tracked-only past | 18 | 0 | 58 | 26 | 32 | 9,079 |

| GET request | Small median ms, baseline → mirror → both | Grown median ms, baseline → mirror → both |
| --- | ---: | ---: |
| Mixed past, first page | 139.56 → 109.28 → 95.73 | 135.13 → 136.97 → 155.13 |
| Mixed past, cursor page | 115.65 → 72.39 → 80.29 | 113.19 → 94.36 → 112.44 |
| Mixed upcoming history | 104.15 → 78.12 → 96.76 | 142.88 → 134.92 → 108.22 |
| Mixed patient detail | 108.83 → 80.38 → 79.62 | 139.17 → 107.14 → 84.98 |
| Tracked-only past | 126.75 → 147.77 → 113.33 | 196.33 → 214.84 → 126.51 |

## PostgreSQL execution plans

The plans came from `EXPLAIN (ANALYZE, BUFFERS)` on SQL and bind values captured from the actual GETs. Both tables had current fixture statistics. The table gives statement execution time and shared buffer hits for each plan, excluding planning.

| Read | Fixture | Baseline | Mirror index | Both indexes |
| --- | --- | --- | --- | --- |
| Tracked-only source keys | Small | Seq scan rejects 577, 9 hits, 0.446 ms | Backward index-only scan returns 0, 2 hits, 0.079 ms | Backward index-only scan returns 0, 2 hits, 0.096 ms |
| Tracked-only source keys | Grown | Seq scan rejects 5,577, 71 hits, 2.832 ms | Backward index-only scan returns 0, 2 hits, 0.100 ms | Backward index-only scan returns 0, 2 hits, 0.084 ms |
| Mixed first-page visit hydration | Small | Seq scan rejects 276 and returns 2, 8 hits, 0.240 ms | Seq scan rejects 276 and returns 2, 8 hits, 0.284 ms | Bitmap index and heap scans fetch 2, 2 hits, 0.125 ms |
| Mixed first-page visit hydration | Grown | Seq scan rejects 15,276 and returns 2, 176 hits, 9.234 ms | Seq scan rejects 15,276 and returns 2, 176 hits, 10.568 ms | Bitmap index and heap scans fetch 2, 3 hits, 0.169 ms |
| Tracked-only visit hydration | Small | Seq scan rejects 252 and returns 26, 8 hits, 0.273 ms | Seq scan rejects 252 and returns 26, 8 hits, 0.280 ms | Bitmap index and heap scans fetch 26, 3 hits, 0.192 ms |
| Tracked-only visit hydration | Grown | Seq scan rejects 15,252 and returns 26, 176 hits, 8.044 ms | Seq scan rejects 15,252 and returns 26, 176 hits, 8.302 ms | Bitmap index and heap scans fetch 26, 5 hits, 0.208 ms |

The tracked-only source scan uses all three scope predicates and performs zero heap fetches at both sizes. For the mixed first and cursor pages, PostgreSQL chooses a scoped bitmap scan and sort on the small fixture and a backward index-only scan with no sort on the grown fixture. The grown source scan produces 26 keys per past page. The cursor scan rejects 23 entries at the tied timestamp before producing those keys. The baseline grown `appointment_window` scan passed 56 and 32 rows to incremental sort and rejected 151 and 169 outside the selected patient or cursor scope, respectively. The grown upcoming source branch reads two index keys, and patient detail uses a forward scan for its first scheduled match.

The mirror-only trial still scans the complete visit table during hydration. Adding the visit index lets the grown mixed first page fetch the same two historical revisions in three shared hits and the tracked-only page fetch the same 26 in five hits. The added indexes occupy 48 KiB and 16 KiB on the small fixture and 288 KiB and 352 KiB on the grown fixture, respectively. PostgreSQL maintains the indexes on inserts and updates to their keys.

### Remaining growth

- Patient authorization in `DeskController` reaches the clinic-wide membership subqueries in `ContactProfilesQuery`. With both indexes, the appointment subplan reads the entire mirror, checks 577 → 5,577 rows, and feeds 317 → 5,317 clinic matches into the membership test. For the tracked-only patient the visit subplan also scans 278 → 15,278 clinic visits. The authorization statement returns one patient. Its shared hits rise from 20 to 254 for that request. DeskController, ContactProfilesQuery
- The tracked projection on mixed upcoming history joins two eligible visit rows to the mirror to detect absent or reassigned source rows. The small plan makes two source primary-key probes. On the grown fixture, all three variants use a `Hash Right Join` and sequentially read all 5,577 mirror appointments to return the same one tracked key. The separate upcoming source projection reads two keys with the new index. Tracked projection
- The tracked-only past projection switches from sorting 54 tracked candidates on the small fixture to using the existing `visit_clinic` date index on the grown fixture. It sends 27 qualifying visits through the grown join and stops after 26 keys. This plan bounds the older tracked rows added by this fixture.

## Scoped regrade

**PASS for the two targeted scans, HTTP behavior, and the plain Active Record query in the selected slice. REVISE for full-request database growth.** The scoped source seek and revision hydration keep their results under the measured growth. The patient authorization scans and the mixed upcoming tracked projection still perform material work proportional to the fixture growth. Addressing those paths would require a separate query and plan review.

The paired probe and existing workspace tests passed together with 5 tests and 1,179 assertions, zero failures, and zero errors. The command took 154.8 seconds including boot, fixtures, all three index variants, and plan collection.

The final migration applied during clean disposable schema setup and rolled back and reapplied successfully on 520 mirror appointments and 220 visits. Index definitions and row counts were verified through Rails. The existing workspace tests passed again with 4 tests and 50 assertions, including the tied cursor, clinic access, and patient and work entry points. This command took 51.8 seconds including setup. The schema snapshot takes the migration version and two index definitions from the Rails dump. The dump also rendered the clinic state type as a string and omitted some existing check constraint names. Schema snapshot

The Active Record audit ran against the migrated app database from `backend` using `ruby bin/rails runner -e test ../.refactor-harness/quality/check_active_record_queries.rb`. The selected query had zero findings. The command exited 1 with the same 19 existing findings recorded in the prior review.

| Existing location relative to `backend` | Findings |
| --- | --- |
| `app/controllers/desk_controller.rb` | 105 `where` |
| `app/models/follow_up_issue.rb` | 11 `where` |
| `app/models/source_sync.rb` | 9 `select_value` |
| `app/queries/case_detail_query.rb` | 46 `Arel` |
| `app/queries/operations_query.rb` | 71, 96, 97, 146, 152, 153 `Arel` and 82 `where` |
| `app/services/database.rb` | 30, 31, 35, 40, 57 `execute` and 64 `raw_connection` |
| `app/services/pms_snapshot.rb` | 109, 136 `Arel` |
