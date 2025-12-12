# Configure Logging and Telemetry (RRA-Pilot)

## Overview

RRA uses [NebulaLogger](https://github.com/jongpie/NebulaLogger) for logging and tracking telemetry.

### Design goals

`NebulaLogger` is a configurable framework which ultimately stores data in
custom tables, and uses PlatformEvents to transmit logging to external sources.
`NebulaLogger` can be configured for log retention, as well as exporting logs
to users (via emailing reports). We are leveraging `NebulaLogger` and its
advanced functionality to provide logging and debugging capabilities.

### Our implementation

We specifically use Nebula as it's installed by default, do not create custom fields, and write all our data into the standard Message field, JSON-serialized.

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
   Note that by default `NebulaLogger` locks everything down, even system administrators might not have these permissions.

## Prerequisites

You need to install NebulaLogger.
