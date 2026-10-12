# Upcoming Renewals

A Salesforce solution that identifies Service Agreements approaching expiration, creates a Renewal Task for the responsible Account Manager, and gives the team a single screen to review upcoming renewals and mark renewal work as started.

Built for the Solution Heroes Salesforce Developer Technical Assessment.

| Requirement                              | Delivered by                                                                        |
| ---------------------------------------- | ----------------------------------------------------------------------------------- |
| 1. Apex service that finds agreements    | `UpcomingRenewalsService`, `RenewalEligibility`, `ServiceAgreementSelector`         |
| 2. Trigger that creates the Renewal Task | `ServiceAgreementTrigger` → `ServiceAgreementTriggerHandler` → `RenewalTaskService` |
| 3. Lightning Web Component               | `upcomingRenewals` (label "Upcoming Renewals") + `UpcomingRenewalsController`       |
| 4. Calendar-date handling                | `RenewalEligibility` (Date arithmetic) + `RenewalClock` (injectable "today")        |
| 5. Apex tests                            | 45 Apex tests across 5 test classes, 95% coverage; 4 Jest tests for the component   |

## Documentation

Detailed documentation lives in [`docs/`](docs/) as HTML pages with an **Export to PDF** button:

- [Functional Documentation](docs/functional-documentation.html): what the solution does, business rules, assumptions.
- [Technical Documentation](docs/technical-documentation.html): how it is built, class by class.
- [Software Architecture Document](docs/architecture-document.html): architectural views, quality attributes and decision records (ADRs).

## How it works

1. A user, integration or data load saves a `Service_Agreement__c`.
2. The trigger asks `RenewalTaskService` to evaluate the saved records in bulk.
3. An agreement **requires attention** when Status is `Active`, Renewal Required is checked and the End Date is between today and today + 30 days (both inclusive).
4. For each qualifying agreement without a Renewal Task, one Task is created:
   - assigned to the Account Manager, or to the agreement owner when the Account Manager is empty or inactive;
   - due 10 calendar days before the End Date, or today if that date has already passed.
5. The Task Id is stored in `Renewal_Task_Id__c` on the agreement, so later edits never create a duplicate.
6. The **Upcoming Renewals** component lists qualifying agreements (soonest first, then highest value) and lets users select rows and click **Start Renewal**, which sets Renewal Work Status to `In Progress`.

## Architecture

```
ServiceAgreementTrigger (no logic)            upcomingRenewals (LWC)
        │                                              │
ServiceAgreementTriggerHandler                UpcomingRenewalsController (@AuraEnabled, DTO)
        │                                              │
RenewalTaskService (system automation)        UpcomingRenewalsService (user mode)
        │                                              │
        └──── RenewalEligibility (pure rules) · RenewalSettings · RenewalClock ────┘
                                       │
                 ServiceAgreementSelector · RenewalTaskSelector (all SOQL)
```

- **Thin trigger, handler, services, domain, selectors**: each class has one reason to change; SOQL lives only in selectors and DML only in services.
- **Bulk-safe**: the trigger path uses at most 2 SOQL queries and 2 DML statements per transaction, regardless of record count.
- **Configurable**: the 30-day window and 10-day lead time live in the `Renewal_Setting__mdt` Custom Metadata record `Default`.
- **Secure**: UI reads and writes run `with sharing` and in `USER_MODE`; access is granted by the `Upcoming_Renewals_User` permission set. The Task automation runs in system context on purpose (see Design decisions).

## Repository structure

```
force-app/main/default/
├── classes/            Apex classes and test classes
├── triggers/           ServiceAgreementTrigger
├── lwc/                upcomingRenewals component and Jest tests
├── objects/            Service_Agreement__c, Renewal_Setting__mdt
├── customMetadata/     Default renewal settings (30 / 10 days)
├── permissionsets/     Upcoming_Renewals_User
├── layouts/, tabs/     Service Agreement layout and tabs
├── flexipages/         Upcoming Renewals Lightning app page
scripts/apex/           Demo data seed and cleanup scripts
docs/                   Functional, technical and architecture documentation
```

## Setup

### Prerequisites

- [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) (`sf`)
- Node.js 18+ (for linting and Jest tests)
- A Salesforce org (Developer Edition, sandbox or scratch org)

### 1. Install and authorize

```bash
npm install
sf org login web --alias dev
```

### 2. Validate, then deploy

Validation is a check-only deployment that runs all local tests without changing the org. The quick deploy then promotes exactly what was validated.

```bash
sf project deploy validate --source-dir force-app --test-level RunLocalTests --target-org dev
sf project deploy quick --job-id <job-id-from-validation> --target-org dev
```

### 3. Grant access

```bash
sf org assign permset --name Upcoming_Renewals_User --target-org dev
```

### 4. Load demo data (optional)

Creates 10 agreements relative to today: 5 that qualify (and receive a Renewal Task) and 5 that do not.

```bash
sf apex run --file scripts/apex/seed-demo-data.apex --target-org dev
# remove later with:
sf apex run --file scripts/apex/delete-demo-data.apex --target-org dev
```

### 5. Open the component

The deployment includes an **Upcoming Renewals** Lightning app page and tab. Open the App Launcher (nine dots), search for **Upcoming Renewals** and open it. To pin it, edit the app's navigation bar and add the Upcoming Renewals item.

The component can also be placed on any Home, App or Record page with the Lightning App Builder (Custom components → **Upcoming Renewals**), as long as the page template has a free region.

## Running tests

```bash
# Apex tests with coverage
sf apex run test --test-level RunLocalTests --code-coverage --result-format human --target-org dev

# LWC Jest tests and lint
npm run test:unit
npm run lint
```

## Assumptions

1. **Custom object.** The standard Contract and Service Contract objects make Status and End Date derived or read-only and have no Renewal Required field, so `Service_Agreement__c` is a custom object.
2. **"Within the next 30 days"** means from today through today + 30, both inclusive. Agreements that have already ended do not qualify.
3. **Task assignee.** The Account Manager is a User lookup. When it is empty or inactive, the Task goes to the agreement owner (and, as a last resort, to the running user), so a renewal is never dropped.
4. **One Renewal Task per agreement.** Later edits, including End Date changes, do not create another Task.
5. **Due date in the past.** When End Date − 10 days has already passed, the Task is due today.
6. **"Renewal work has started"** is tracked on the agreement (`Renewal_Work_Status__c`), independent of Status, so the agreement stays visible while it is being renewed.
7. **"Today"** follows the running user's time zone (`Date.today()`).
8. **Sharing.** The object uses Public Read/Write, so an Account Manager who is not the owner can still see and update the agreement assigned to them.

## Design decisions

| Decision                                                 | Why                                                                                                                                                                                                                                                                                 |
| -------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Apex trigger instead of a Record-Triggered Flow          | Bulk duplicate detection, owner fallback and boundary-date tests are explicit and unit-testable in Apex. Declarative tools are used for the data model, validation rule, configuration and access.                                                                                  |
| Duplicate marker on the agreement (`Renewal_Task_Id__c`) | The target org does not accept custom fields on Task or Event (verified with dry-run deployments), so a unique key on Task was not possible. The service re-reads agreements with `FOR UPDATE`, skips those with a marker, and checks existing Tasks by `WhatId` as a second layer. |
| No static recursion flag                                 | Static "already ran" flags break bulk loads above 200 records. The service is idempotent instead: once the marker is set, later passes skip the record without spending queries.                                                                                                    |
| `RenewalTaskService` runs `without sharing`              | It is a system automation that must see Renewal Tasks owned by other users and stamp a system-managed field even when the editing user cannot edit it. User-facing paths enforce `USER_MODE`.                                                                                       |
| Custom Metadata for the 30 / 10 days                     | The business can tune the rules without a code release; safe defaults are used when the record is missing.                                                                                                                                                                          |
| `RenewalClock`                                           | One source of "today", so tests pin the date and cover month, year and leap-year boundaries deterministically.                                                                                                                                                                      |
| Own lightweight trigger handler                          | No external dependency; the layering is compatible with fflib or the Trigger Actions Framework if the org grows.                                                                                                                                                                    |

## Known limitations and next steps

- Agreements are evaluated when they are saved. An agreement that enters the 30-day window without being edited does not receive a Task until it is saved again; a daily Schedulable/Batchable job reusing `RenewalTaskService` would close this gap.
- Notifications for new or overdue Renewal Tasks.
- Synchronize the Renewal Task status when renewal work starts.
- Pagination in the component for very large result sets (currently up to 500 rows).
