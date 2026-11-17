# Patient appointment query refactor

## Before implementation

The baseline is `db037d7932b13fc4d735106e0fa199815fb2d22c`. `GET /api/patient-details/:id/history` reaches `DeskController#patient_history`, which checks the staff clinic and patient before `PatientWorkspaceHistory#appointments` requests 26 keys, renders up to 25 rows, and binds the next cursor to the request scope. `GET /api/patient-details/:id` and `GET /api/work/:id` reach `CaseDetailQuery#patient_fields`, which asks for the earliest scheduled source appointment strictly after clinic-local wall time and renders its outreach and revision details.

History takes the date from the patient's source appointment in the selected clinic even when a tracked revision is newer. Without a source appointment in that scope it uses the greatest tracked date. Filters and the strict descending `(start_at, appointment_id)` cursor apply to the chosen date. Row assembly preserves its own tracked revision selection, including the highest visit ID fallback and recorded facts when source is missing.

The intended relations use the same `Appointment` mirror and `Visit` scopes. Use a typed range for the upcoming lookup, and for history compare two ordered, bounded scalar projections. One reads source keys and dates. The second excludes tracked IDs with a scoped source and uses a grouped maximum for tracked dates. A past or cursor cutoff must suppress a tracked ID when its maximum fails the upper bound, even when an older revision would pass. Combine the bounded projections by the existing composite order and hydrate the selected IDs. Check whether the last source key can exclude older tracked candidates before grouping. The schema and its existing indexes are fixed.

## Implementation

- Upcoming lookup uses a negated inclusive range to keep the strict clinic wall-time boundary, with the scheduled scope and chronological `start_at, id` order. Case detail still owns the response and uses the same appointment lookup for the patient and work routes.
- History selection reads both candidate sets in repeatable read so a mirror refresh between the projections cannot change source precedence. When the source supplies 26 keys, tracked candidates must outrank its last key to matter. The merge sorts up to 52 keys by the existing composite order and returns at most 26 for the caller to hydrate. History cursor binding and encoding stay with the caller.
- Tracked candidates join through `Visit#appointment` and qualify only when the source row is absent or belongs to a different patient or clinic. The scoped exclusion subquery removes IDs with any revision beyond the past or cursor end. The ordered projection can stop when it supplies a full page of distinct keys or runs out of rows. When repeated revisions fill the projection, Rails generates `MAX(start_at)` by appointment and limits the ranked groups. The `maximum_start_at` order uses the alias produced by the installed Active Record `maximum` calculation.
- Row assembly preloads the patient's display name for source-only records. The chosen visit and the full list of revisions use the existing serializer behavior. For an appointment absent from the patient and clinic source scope, the visit with the largest local ID still supplies the recorded fields even when a different visit supplies the greatest date used for pagination.
- Appointment and Visit map to `pms.appointments` and `desk.visits` in the application database. `PmsRecord` marks mirror records read-only. The query adds no stored derivation or writes. On the private replica, the provisioned `pms_reader` login had `SELECT` on each of the three PMS tables and lacked `INSERT`, `UPDATE`, `DELETE`, and `TRUNCATE` on all three. The provided setup seeded both test databases using its normal path.

The relation syntax was checked against the [Rails 8.1 query guide](https://guides.rubyonrails.org/v8.1/active_record_querying.html#filtering-records) and [Active Record query methods](https://api.rubyonrails.org/v8.1.3/classes/ActiveRecord/QueryMethods.html), and the generated statement and alias were checked on 8.1.3.1.

## Checks and workloads

The cursor test traverses a past page boundary with 27 synthetic appointment IDs at exactly the same microsecond, including two tracked-only IDs and 26 duplicate revision dates for one of them. It asserts exact descending ID order without duplication and tests the section and patient access restrictions. The source and visit test asserts the patient-details and history results at the wall-time boundary and one microsecond later. It also tests a newer tracked revision for a completed source appointment, different patient and clinic ownership on both sides, a missing source with different pagination and serialized visit dates, a direct appointment filter, and preservation of confirmation fields. The existing work-route test compares both entry points for the same patient.

The workload ran Rack GETs after signing in as staff 11 at clinic 1 with the existing `test_helper` and workload probe. Time was frozen at November 5, 2026 at 10 AM in Chicago. The mixed patient (8000000) has 54 completed source appointments at the same past timestamp, two scheduled sources tied just after the wall-time boundary, and one scheduled source exactly at that boundary. Four visits include a newer revision of a completed source, an orphan with a newer pagination date and an older confirmed visit, and an orphan at the past cursor tie. A second patient (8000001) has 54 past tracked-only appointments at distinct dates one second apart. Growth adds 5,000 older source rows with matching visits, 5,000 older tracked-only IDs for the mixed patient, and 5,000 older tracked-only IDs for the second patient. Added dates begin 40 days before the reference time and run backward one second per ID.

The original query was measured before the application edit. The paired run then executed the baseline and the patch against the same fixture at each size, with `ANALYZE` outside each measured request. The probe measured 11 warmed complete calls per endpoint and variant, excluding fixture setup and assertions. The SQL plans were collected separately with `EXPLAIN (ANALYZE, BUFFERS)`. The comparisons assert HTTP 200, exact body and cursor equality, the expected ordering and confirmation behavior, and zero application writes. The timings include routing, controller scopes, the query, serialization, and test transport on Windows Ruby 3.4.10 and PostgreSQL 17.11. The baseline ran first and machine load was uncontrolled. The medians describe this run and varied across repeats.

## Results on the local patch

`ruby test/patient_workspace_test.rb` from `backend` passed 4 tests and 50 assertions in 22.3 seconds including setup. The paired rerun with the workspace tests passed 5 tests and 564 assertions in 62.9 seconds including setup. An unpinned Rack GET for patient 103 returned HTTP 200 and one history row, with `BEGIN ISOLATION LEVEL REPEATABLE READ` and `COMMIT` observed around key selection.

The production query blob is `27b14d31870a59d5fe0f5b67aad98cc8270572cc` and the test blob is `fa3f019995e058b6ba352b2ffbd1f9fde642abad`. The baseline and patch produced byte-identical bodies on every measured request, including both past pages under growth. The past tie includes the completed source without applying its newer tracked confirmation. Upcoming history includes the orphan in date order with its recorded confirmation. Patient detail chooses source appointment `8100101`, the lower ID of two scheduled appointments tied just past 10 AM. All measured requests recorded zero write statements.

Each pair below is baseline → patch. Executed statements include transaction control and exclude Rails cache hits. Rows count results returned by executed reads, and Rails records count models instantiated, including from cached results.

| Fixture | GET request | Executed statements | Cache hits | Rows returned | Rails records | Median ms | Body bytes |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Small | Mixed past, first page | 16 → 18 | 24 → 1 | 61 → 61 | 59 → 35 | 140.19 → 62.13 | 7,932 |
| Grown | Mixed past, first page | 16 → 18 | 24 → 1 | 61 → 61 | 59 → 35 | 184.14 → 79.94 | 7,932 |
| Small | Mixed past, cursor page | 7 → 10 | 25 → 0 | 56 → 56 | 55 → 30 | 140.39 → 36.95 | 7,704 |
| Grown | Mixed past, cursor page | 7 → 10 | 25 → 0 | 56 → 56 | 55 → 30 | 179.00 → 64.67 | 7,704 |
| Small | Mixed upcoming history | 16 → 18 | 1 → 1 | 14 → 13 | 12 → 11 | 85.59 → 41.69 | 1,141 |
| Grown | Mixed upcoming history | 16 → 18 | 1 → 1 | 14 → 13 | 12 → 11 | 172.29 → 65.01 | 1,141 |
| Small | Mixed patient detail | 18 → 18 | 1 → 1 | 12 → 12 | 7 → 7 | 66.73 → 30.70 | 1,920 |
| Grown | Mixed patient detail | 18 → 18 | 1 → 1 | 12 → 12 | 7 → 7 | 84.65 → 52.45 | 1,920 |
| Small | Tracked-only past | 15 → 18 | 0 → 0 | 58 → 58 | 32 → 32 | 92.16 → 45.62 | 8,979 |
| Grown | Tracked-only past | 15 → 18 | 0 → 0 | 58 → 58 | 32 → 32 | 114.61 → 78.97 | 8,979 |

The largest read remained 26 rows for each past page. The mixed past page instantiates 24 fewer records on the first request and 25 fewer on the cursor request by preloading the patient. The tracked-only page incurs one more read and two transaction-control statements to select independently ranked keys in one snapshot. The mixed first page and upcoming history offset the extra read elsewhere in row loading. The patient-details query has the same statement and row counts, with an equivalent indexed wall-time predicate generated by Rails.

### PostgreSQL plans and repair

- In the mixed workload the baseline sent 61 rows through its append before deduplicating and ranking history. That grew to 15,061 for the same first page, cursor page, and upcoming response. On the grown fixture with current table statistics, the patch's backward source index scans passed 56 and 32 scoped rows to incremental sort for the two past pages. The tracked index scan used both date bounds and returned one and zero matching visits, respectively. On an earlier grown run with stale fixture statistics, PostgreSQL chose a bitmap and sort for the source projection and passed 5,055 and 5,031 scoped rows into those sorts.
- The first implementation grouped all eligible tracked visits. On the grown tracked-only fixture, 5,054 visits went into the aggregate. In the same three-variant comparison, the grouped-only and ordered variants had median caller times of 197.93 and 133.55 ms respectively, with 18 statements, 58 returned rows, and 32 models each. The ordered variant's grown visit index supplied 27 qualifying rows to the sort and returned 26 to Rails. The final rerun confirmed that plan. Repeated revisions still need the grouped calculation when 26 raw keys contain fewer than 26 distinct appointments. A diagnostic rerun of the focused cursor fixture observed the grouped maximum twice while passing the exact order and uniqueness assertions.
- The tracked-only source projection returned zero from a sequential scan that rejected 577 mirror rows on the small fixture and 5,577 on the grown fixture. The database cannot prove absence from the selected patient scope using the existing `appointment_window` index, whose columns are `clinic_id` and `start_at`. Within a timestamp tie it also lacks ID order. A patient-keyed access path that can order by timestamp and ID within the clinic scope would address this source-side limitation. The replica definition and the mirror both retain the existing schema. The returned revisions and their hydration also carry their existing cost for each selected appointment.
- The existing visit hydration for the mixed first page selected the same two revisions in both sizes and versions. A follow-up plan check showed its sequential scan rejecting 276 visits on the small fixture and 15,276 on the grown fixture in both versions. The visit appointment-ID index covers only current visits, while the response includes historical revisions for each selected ID.

### Active Record query check

Executed from `backend` with `ruby bin/rails runner -e test ../.refactor-harness/quality/check_active_record_queries.rb`. The baseline had 11 findings in `patient_appointments_query.rb`. The final audit reported zero there. The whole-application command still exits 1 with the same 19 findings outside the patch. The source trace covers the changed relations directly, including the framework-generated maximum, join, exclusion subquery, and both range predicates. The HTTP path still reaches existing findings in patient authorization, case issue ordering, freshness reporting, and the follow-up issue lookup used during row assembly.

| Existing location relative to `backend` | Baseline and final findings |
| --- | --- |
| `app/controllers/desk_controller.rb` | 105 `where` |
| `app/models/follow_up_issue.rb` | 11 `where` |
| `app/models/source_sync.rb` | 9 `select_value` |
| `app/queries/case_detail_query.rb` | 46 `Arel` |
| `app/queries/operations_query.rb` | 71, 96, 97, 146, 152, 153 `Arel` and 82 `where` |
| `app/services/database.rb` | 30, 31, 35, 40, 57 `execute` and 64 `raw_connection` |
| `app/services/pms_snapshot.rb` | 109, 136 `Arel` |

## Scoped grade

**REVISE for the strict database growth criterion.** HTTP equivalence, clinic and revision boundaries, bounded keys transferred and hydrated under the measured growth, and the plain Active Record rule for the changed query pass. The mixed-page selection uses the existing date indexes to avoid the added historical work when statistics are current. The tracked-only source scan and the visit hydration scan still grow with unrelated rows. The fixed mirror and visit indexes lack the access paths needed to guarantee a patient-scoped page seek and an all-revision appointment lookup. This is a scoped self-review at `db037d7` plus the blobs above.
