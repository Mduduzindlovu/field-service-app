# Phase 3 — Platform Events Design

**Date:** 2026-07-07
**Status:** Approved

## Goal

Publish a Salesforce Platform Event whenever a Case is created or whenever
a Case's `Status`, `Assigned_Technician__c`, or `Scheduled_Date__c` changes.
The event carries a full enriched snapshot so the Phase 5 webhook receiver
can update the Postgres cache without a follow-up API call to Salesforce.

Asset changes are out of scope for this phase.

---

## Platform Event: `CaseStatusChanged__e`

**Publish Behavior:** `PublishAfterCommit`

| Field API name | Type | Notes |
|---|---|---|
| `Case_Id__c` | Text(18) | Salesforce record ID |
| `Case_Number__c` | Text(10) | Human-readable case number |
| `Subject__c` | Text(255) | Case subject |
| `Status__c` | Text(255) | Current status value |
| `Assigned_Technician_Id__c` | Text(18) | User ID (nullable) |
| `Assigned_Technician_Name__c` | Text(255) | User name (nullable) |
| `Scheduled_Date__c` | DateTime | Scheduled date/time (nullable) |
| `Location_Name__c` | Text(255) | `Locations__r.Name` |
| `Latitude__c` | Number(16,13) | `Locations__r.Coordinates__Latitude__s` |
| `Longitude__c` | Number(16,13) | `Locations__r.Coordinates__Longitude__s` |

---

## New files

| Path | Purpose |
|---|---|
| `force-app/main/default/triggers/CaseEventTrigger.trigger` | Thin trigger; delegates to handler |
| `force-app/main/default/triggers/CaseEventTrigger.trigger-meta.xml` | Trigger metadata |
| `force-app/main/default/classes/CaseEventPublisher.cls` | Builds and publishes events |
| `force-app/main/default/classes/CaseEventPublisher.cls-meta.xml` | Class metadata |
| `force-app/main/default/classes/CaseEventPublisherTest.cls` | Unit tests |
| `force-app/main/default/classes/CaseEventPublisherTest.cls-meta.xml` | Test class metadata |
| `force-app/main/default/objects/CaseStatusChanged__e/` | Platform Event object metadata |
| `force-app/main/default/objects/CaseStatusChanged__e/fields/` | One `.field-meta.xml` per event field |

---

## Trigger (`CaseEventTrigger`)

Fires `after insert, after update` on Case. Delegates immediately to
`CaseEventPublisher.publish(Trigger.new, Trigger.oldMap)`. No logic in the
trigger body itself.

On insert, `Trigger.oldMap` is null — the handler treats this as "all fields
changed" and publishes for every inserted Case that has a Location set.

---

## Handler (`CaseEventPublisher`)

```
static void publish(List<Case> newCases, Map<Id, Case> oldMap):

  1. Build list of Cases to publish:
       - If oldMap is null (insert context):
           include Cases where Locations__c != null
       - If oldMap is not null (update context):
           include Cases where Locations__c != null AND at least one of
           Status, Assigned_Technician__c, Scheduled_Date__c changed

  2. If list is empty, return early

  3. Query enriched fields for those Case IDs:
       SELECT Id, CaseNumber, Subject, Status,
              Assigned_Technician__c, Assigned_Technician__r.Name,
              Scheduled_Date__c,
              Locations__c, Locations__r.Name,
              Locations__r.Coordinates__Latitude__s,
              Locations__r.Coordinates__Longitude__s
       FROM Case WHERE Id IN :changedIds

  4. Build one CaseStatusChanged__e per queried Case

  5. EventBus.publish(events)  // single DML call, bulk-safe
```

Key invariant: only Cases with a Location set ever produce an event. Cases
without a Location are silently skipped at step 1.

---

## Tests (`CaseEventPublisherTest`)

All tests use `@TestSetup` to create a shared `Locations__c` record with
coordinates.

| Method | What it tests |
|---|---|
| `publishesEventOnInsert` | Insert one Case with a Location; assert one event published with correct payload |
| `publishesEventOnStatusChange` | Update `Status`; assert one event with correct payload via `Test.getEventBus().getPublishedMessages()` |
| `noEventWhenUnrelatedFieldChanges` | Update `Description` only; assert zero events published |
| `publishesOneEventPerChangedCaseInBulkUpdate` | Insert 5 Cases **all with a Location**, update all 5 in one DML statement, assert exactly 5 events — all 5 have a Location so count is unambiguous |

Note: "N records changed" equals "N events" only when all N have a Location.
The bulk test is written this way deliberately to keep the assertion clear.

---

## Deployment

A single `sf project deploy start --target-org fieldservice-dev` handles
ordering automatically for this metadata set. Run Apex tests after deploy
to confirm >75% coverage.

---

## Out of scope

- Asset trigger (deferred to a follow-up phase)
- Platform Event subscriber / CometD / Pub Sub API listener (Phase 5)
- Bulk seed of existing Cases into Postgres (not needed — `after insert`
  fires on any future Case creation; historical Cases will sync naturally
  on their next update)
- Moving the Mapbox token to a Custom Setting (separate cleanup task)
