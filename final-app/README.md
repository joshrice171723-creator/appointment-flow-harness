# Appointment Flow

A Rails and React app for appointment confirmations and staff follow-up. The app reads a separate PMS replica through a read-only connection. It stores its own cases, confirmations, and messages. The demo uses synthetic patients and simulated deliveries.

This application combines measured changes from the [harness experiment](../README.md). The source record identifies the original application, the refactor base, and the exact evaluated revision. [Source record](provenance.json)

## Run the app

Install Docker with Compose. Run these commands from this directory.

```sh
docker compose up --build -d
docker compose ps -a
```

Open [Appointment Flow](http://localhost:8174/). The first startup creates the local databases and seeds the demo. The setup container exits when it succeeds. The app, worker, Redis, and database continue to run.

Open **Front desk**, select **Austin** and **Taylor Morgan**, and open a **No reply** follow-up. Note the patient. Open the same patient in the **Patient** workspace to see their simulated reminders and replies.

The scheduled worker reads the source, reconciles visits, and opens follow-up work. The staff appointment screens read from the app's mirror. The history page shows previous appointments and confirmation records.

```sh
docker compose logs setup app worker
docker compose --profile test run --rm test
docker compose down
```

The test service uses separate test databases. `docker compose down` stops the stack and keeps the local demo data.

## Find the workflow owners

| Workflow | Code |
| --- | --- |
| Read the external PMS and refresh the app mirror | [PMS replica](backend/app/services/pms_replica.rb), [snapshot import](backend/app/services/pms_snapshot.rb) |
| Select a clinic batch and record deliveries | [Reminder runner](backend/app/services/reminder_runner.rb), [reminder flow](backend/app/services/reminder_flow.rb), [reminder sender](backend/app/services/reminder_sender.rb) |
| Open, close, or reopen a follow-up | [Follow-up workflow](backend/app/services/follow_up_workflow.rb) |
| Look up patient access and guarantor permission | [Desk controller](backend/app/controllers/desk_controller.rb) |
| Select and load a page of appointment history | [Patient appointment query](backend/app/queries/patient_appointments_query.rb) |

The [app decisions](DECISIONS.md) describe the behavior. The [experiment README](../README.md) links to the measured comparison and identifies which earlier runs informed the changes.
