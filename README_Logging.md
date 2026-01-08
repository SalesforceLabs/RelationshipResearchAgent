# Configure Logging and Telemetry (RRA-Pilot)

## Overview

At the pilot stage, we're distributing the source code, and therefore
not able to use namespaced backend components. To compensate for that,
RRA uses [NebulaLogger](https://github.com/jongpie/NebulaLogger) for logging and tracking telemetry.

### Design goals

NebulaLogger is a configurable framework which ultimately stores data in
custom tables, and uses PlatformEvents to transmit logging to external sources.
We use it as an interim solution for telemetry until we can use namespaced telemetry components
directly. We might continue supporting Nebula in future releases.

### Our implementation

Since our implementation of telemetry on Nebula is temporary in nature,
we avoid deep customization. We specifically use Nebula as it's installed,
do not create custom fields, and write all our data into the standard Message
field, JSON-serialized.

The telemetry data then can be transmitted to RRA team by creating a standard
daily report over Log Entity table and configuring its delivery via an email.

## Default configuration

See [Nebula's documentation](https://github.com/jongpie/NebulaLogger) about installing
Nebula package.

Once it's installed, RRA will try to log data into Nebula if it's available.
It will be necessary to configure the report to extract data from Nebula Logger.
By default, Nebula package is installed with all fields protected.

1. Determine the user who will have permissions to run the report. Note the user's profile.
1. Setup -> Object Manager -> Log Entry -> Fields & Relationships
   For `Entry Scenario` and `Message` fields - make them visible to the profile of that user.

## Prerequisites

You need to install NebulaLogger.

## Step by step Nebula installation instructions for a production database

- The following is true in January 2026. For the latest instructions, consult [Nebula's documentation](https://github.com/jongpie/NebulaLogger)
- Navigate to [Nebula's homepage](https://github.com/jongpie/NebulaLogger) and click `Install Unlocked Package in Production` (or follow the instructions under `Install Unlocked Package in Sandbox`).
- Both Managed and Unlocked packages are supported. Managed package does not allow ad-hoc bug fixing and customizations, therefore we recommend Unlocked package.
- Install the package for Admins only.
- Once installed, use AppLauncher to launch Nebula Logger.
- You open `Event Stream` page to monitor entries. For telemetry, look for entries like `"eventName":"RRAClientAsync.execute-Call","mode":"telemetry","durationMs":889,"count":1}`

### Export telemetry data via report on Nebula log table

- `App Launcher` -> `Reports` -> `New Report`
- Filter by `Category`: `All`. Locate `Logs with Log Entries`. Click `Start Report`.
- Add `Message` column. On `Filters` tab, add a condition for `Message` field: operator `contains`, value `telemetry`.
- On `Filters` tab, add a condition for field `Log: Created Date`. Set `Range`=`Yesterday`.
- Save the report as `RRA Nebula Telemetry` in your provate folder.
- Click `Reports` in the top menu. Select the report and click an arrow on the right to expand the menu. Click `Subscribe`. Use Daily frequency, you can set time as `8:00 AM`.
- You will be receiving emails with exported report.

## Fallback: Nebula-independent implementation

RRA currently also saves telemetry data in its own log table. This functionality
will be removed in future releases.

To receive data from that log table, create and configure a report

### Export telemetry data via report on RRA log table

- `App Launcher` -> `Reports` -> `New Report`
- Filter by `Category`: `All`. Locate `RRA Logs`. Click `Start Report`.
- Set `Show me` to `All rra logs`.
- Add `Category` and `Log` columns. Add a filter for field: `Category`, operator: `starts with`, value: `RRATelemetry:`.
- On `Filters` tab, add a condition for field `RRA Logs: Created Date`. Set `Range`=`Yesterday`.
- Save the report as `RRA Native Telemetry` in your provate folder.
- Click `Reports` in the top menu. Select the report and click an arrow on the right to expand the menu. Click `Subscribe`. Use Daily frequency, you can set time as `8:00 AM`.
- You will be receiving emails with exported report.
