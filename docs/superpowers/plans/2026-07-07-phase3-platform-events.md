# Phase 3 — Platform Events Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish a `CaseStatusChanged__e` Platform Event on Case insert and on changes to `Status`, `Assigned_Technician__c`, or `Scheduled_Date__c`, carrying a full enriched snapshot of the Case.

**Architecture:** A thin `after insert, after update` trigger on Case delegates to `CaseEventPublisher.cls`, which filters changed Cases, queries enriched fields (joining to `Locations__c` and `Assigned_Technician__r`), and publishes one event per Case in a single `EventBus.publish` call.

**Tech Stack:** Apex (API 66.0), Salesforce Platform Events, SFDX metadata deployment (`sf` CLI v2).

---

## File map

| File | Action | Purpose |
|---|---|---|
| `force-app/main/default/objects/CaseStatusChanged__e/CaseStatusChanged__e.object-meta.xml` | Create | Platform Event object definition |
| `force-app/main/default/objects/CaseStatusChanged__e/fields/Case_Id__c.field-meta.xml` | Create | Event field |
| `force-app/main/default/objects/CaseStatusChanged__e/fields/Case_Number__c.field-meta.xml` | Create | Event field |
| `force-app/main/default/objects/CaseStatusChanged__e/fields/Subject__c.field-meta.xml` | Create | Event field |
| `force-app/main/default/objects/CaseStatusChanged__e/fields/Status__c.field-meta.xml` | Create | Event field |
| `force-app/main/default/objects/CaseStatusChanged__e/fields/Assigned_Technician_Id__c.field-meta.xml` | Create | Event field |
| `force-app/main/default/objects/CaseStatusChanged__e/fields/Assigned_Technician_Name__c.field-meta.xml` | Create | Event field |
| `force-app/main/default/objects/CaseStatusChanged__e/fields/Scheduled_Date__c.field-meta.xml` | Create | Event field |
| `force-app/main/default/objects/CaseStatusChanged__e/fields/Location_Name__c.field-meta.xml` | Create | Event field |
| `force-app/main/default/objects/CaseStatusChanged__e/fields/Latitude__c.field-meta.xml` | Create | Event field |
| `force-app/main/default/objects/CaseStatusChanged__e/fields/Longitude__c.field-meta.xml` | Create | Event field |
| `force-app/main/default/classes/CaseEventPublisher.cls` | Create | Handler: filter, query, publish |
| `force-app/main/default/classes/CaseEventPublisher.cls-meta.xml` | Create | Class metadata |
| `force-app/main/default/classes/CaseEventPublisherTest.cls` | Create | Unit tests (4 methods) |
| `force-app/main/default/classes/CaseEventPublisherTest.cls-meta.xml` | Create | Test class metadata |
| `force-app/main/default/triggers/CaseEventTrigger.trigger` | Create | Thin trigger; delegates to handler |
| `force-app/main/default/triggers/CaseEventTrigger.trigger-meta.xml` | Create | Trigger metadata |

---

## Task 1: Platform Event object metadata

**Files:**
- Create: `force-app/main/default/objects/CaseStatusChanged__e/CaseStatusChanged__e.object-meta.xml`
- Create: `force-app/main/default/objects/CaseStatusChanged__e/fields/` (10 field files)

- [ ] **Step 1.1: Create the object metadata file**

```bash
mkdir -p force-app/main/default/objects/CaseStatusChanged__e/fields
```

Create `force-app/main/default/objects/CaseStatusChanged__e/CaseStatusChanged__e.object-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Case Status Changed</label>
    <pluralLabel>Case Status Changed</pluralLabel>
    <deploymentStatus>Deployed</deploymentStatus>
    <eventType>HighVolume</eventType>
    <publishBehavior>PublishAfterCommit</publishBehavior>
</CustomObject>
```

- [ ] **Step 1.2: Create Text fields**

Create `force-app/main/default/objects/CaseStatusChanged__e/fields/Case_Id__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Case_Id__c</fullName>
    <label>Case ID</label>
    <length>18</length>
    <type>Text</type>
</CustomField>
```

Create `force-app/main/default/objects/CaseStatusChanged__e/fields/Case_Number__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Case_Number__c</fullName>
    <label>Case Number</label>
    <length>10</length>
    <type>Text</type>
</CustomField>
```

Create `force-app/main/default/objects/CaseStatusChanged__e/fields/Subject__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Subject__c</fullName>
    <label>Subject</label>
    <length>255</length>
    <type>Text</type>
</CustomField>
```

Create `force-app/main/default/objects/CaseStatusChanged__e/fields/Status__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Status__c</fullName>
    <label>Status</label>
    <length>255</length>
    <type>Text</type>
</CustomField>
```

Create `force-app/main/default/objects/CaseStatusChanged__e/fields/Assigned_Technician_Id__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Assigned_Technician_Id__c</fullName>
    <label>Assigned Technician ID</label>
    <length>18</length>
    <type>Text</type>
</CustomField>
```

Create `force-app/main/default/objects/CaseStatusChanged__e/fields/Assigned_Technician_Name__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Assigned_Technician_Name__c</fullName>
    <label>Assigned Technician Name</label>
    <length>255</length>
    <type>Text</type>
</CustomField>
```

Create `force-app/main/default/objects/CaseStatusChanged__e/fields/Location_Name__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Location_Name__c</fullName>
    <label>Location Name</label>
    <length>255</length>
    <type>Text</type>
</CustomField>
```

- [ ] **Step 1.3: Create DateTime field**

Create `force-app/main/default/objects/CaseStatusChanged__e/fields/Scheduled_Date__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Scheduled_Date__c</fullName>
    <label>Scheduled Date</label>
    <type>DateTime</type>
</CustomField>
```

- [ ] **Step 1.4: Create Number fields for coordinates**

Create `force-app/main/default/objects/CaseStatusChanged__e/fields/Latitude__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Latitude__c</fullName>
    <label>Latitude</label>
    <precision>16</precision>
    <scale>13</scale>
    <type>Number</type>
</CustomField>
```

Create `force-app/main/default/objects/CaseStatusChanged__e/fields/Longitude__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Longitude__c</fullName>
    <label>Longitude</label>
    <precision>16</precision>
    <scale>13</scale>
    <type>Number</type>
</CustomField>
```

- [ ] **Step 1.5: Deploy the Platform Event to org**

```bash
sf project deploy start \
  --source-dir force-app/main/default/objects/CaseStatusChanged__e \
  --target-org fieldservice-dev
```

Expected: `Deploy Succeeded` with 11 components deployed (1 object + 10 fields).
If deploy fails with a metadata type error, verify the `eventType` and `publishBehavior` values are spelled exactly as above.

- [ ] **Step 1.6: Commit**

```bash
git add force-app/main/default/objects/CaseStatusChanged__e
git commit -m "feat: add CaseStatusChanged__e Platform Event definition"
```

---

## Task 2: `CaseEventPublisher` handler class (test-first)

**Files:**
- Create: `force-app/main/default/classes/CaseEventPublisher.cls`
- Create: `force-app/main/default/classes/CaseEventPublisher.cls-meta.xml`
- Create: `force-app/main/default/classes/CaseEventPublisherTest.cls`
- Create: `force-app/main/default/classes/CaseEventPublisherTest.cls-meta.xml`

- [ ] **Step 2.1: Create the test class skeleton**

Create `force-app/main/default/classes/CaseEventPublisherTest.cls`:

```apex
@isTest
private class CaseEventPublisherTest {

    @TestSetup
    static void makeData() {
        Locations__c loc = new Locations__c(
            Name = 'Test Site',
            Coordinates__Latitude__s = -33.9249,
            Coordinates__Longitude__s = 18.4241
        );
        insert loc;

        Case c = new Case(
            Subject = 'Test Case',
            Status = 'New',
            Locations__c = loc.Id
        );
        insert c;
    }

    @isTest
    static void publishesEventOnInsert() {
    }

    @isTest
    static void publishesEventOnStatusChange() {
    }

    @isTest
    static void noEventWhenUnrelatedFieldChanges() {
    }

    @isTest
    static void publishesOneEventPerChangedCaseInBulkUpdate() {
    }
}
```

Create `force-app/main/default/classes/CaseEventPublisherTest.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>66.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

- [ ] **Step 2.2: Create a stub handler so the test class compiles**

Create `force-app/main/default/classes/CaseEventPublisher.cls`:

```apex
public with sharing class CaseEventPublisher {
    public static void publish(List<Case> newCases, Map<Id, Case> oldMap) {
    }
}
```

Create `force-app/main/default/classes/CaseEventPublisher.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>66.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

- [ ] **Step 2.3: Write the `publishesEventOnInsert` test body**

Replace the empty `publishesEventOnInsert` method with:

```apex
@isTest
static void publishesEventOnInsert() {
    Locations__c loc = [SELECT Id FROM Locations__c LIMIT 1];

    Test.startTest();
    Case c = new Case(
        Subject = 'New Install',
        Status = 'New',
        Locations__c = loc.Id
    );
    insert c;
    Test.stopTest();

    List<CaseStatusChanged__e> events =
        (List<CaseStatusChanged__e>) Test.getEventBus().getPublishedMessages();

    System.assertEquals(1, events.size(), 'Expected 1 event on insert');
    System.assertEquals('New Install', events[0].Subject__c);
    System.assertEquals('New', events[0].Status__c);
    System.assertNotEquals(null, events[0].Case_Id__c);
    System.assertNotEquals(null, events[0].Latitude__c);
    System.assertNotEquals(null, events[0].Longitude__c);
}
```

Note: `Test.getEventBus().getPublishedMessages()` returns events published during the `Test.startTest()`/`Test.stopTest()` block. The trigger will call `CaseEventPublisher.publish` on insert — but we haven't wired the trigger yet, so this test will fail at the assertion until Task 3. That's expected. Leave the test as-is and move on.

- [ ] **Step 2.4: Write the `publishesEventOnStatusChange` test body**

Replace the empty `publishesEventOnStatusChange` method with:

```apex
@isTest
static void publishesEventOnStatusChange() {
    Case c = [SELECT Id FROM Case LIMIT 1];

    Test.startTest();
    c.Status = 'Working';
    update c;
    Test.stopTest();

    List<CaseStatusChanged__e> events =
        (List<CaseStatusChanged__e>) Test.getEventBus().getPublishedMessages();

    System.assertEquals(1, events.size(), 'Expected 1 event on status change');
    System.assertEquals('Working', events[0].Status__c);
}
```

- [ ] **Step 2.5: Write the `noEventWhenUnrelatedFieldChanges` test body**

Replace the empty `noEventWhenUnrelatedFieldChanges` method with:

```apex
@isTest
static void noEventWhenUnrelatedFieldChanges() {
    Case c = [SELECT Id FROM Case LIMIT 1];

    Test.startTest();
    c.Description = 'Updated description only';
    update c;
    Test.stopTest();

    List<CaseStatusChanged__e> events =
        (List<CaseStatusChanged__e>) Test.getEventBus().getPublishedMessages();

    System.assertEquals(0, events.size(), 'Expected no events for unrelated field change');
}
```

- [ ] **Step 2.6: Write the `publishesOneEventPerChangedCaseInBulkUpdate` test body**

Replace the empty `publishesOneEventPerChangedCaseInBulkUpdate` method with:

```apex
@isTest
static void publishesOneEventPerChangedCaseInBulkUpdate() {
    Locations__c loc = [SELECT Id FROM Locations__c LIMIT 1];

    // Insert 5 Cases — all with a Location so all 5 will produce events
    List<Case> cases = new List<Case>();
    for (Integer i = 0; i < 5; i++) {
        cases.add(new Case(
            Subject = 'Bulk Case ' + i,
            Status = 'New',
            Locations__c = loc.Id
        ));
    }
    insert cases;

    // Clear any insert events before the update test
    Test.getEventBus().deliver();

    Test.startTest();
    for (Case c : cases) {
        c.Status = 'Working';
    }
    update cases;
    Test.stopTest();

    List<CaseStatusChanged__e> events =
        (List<CaseStatusChanged__e>) Test.getEventBus().getPublishedMessages();

    System.assertEquals(5, events.size(),
        'Expected exactly 1 event per updated Case, got ' + events.size());
}
```

- [ ] **Step 2.7: Implement `CaseEventPublisher.publish`**

Replace `CaseEventPublisher.cls` with the full implementation:

```apex
public with sharing class CaseEventPublisher {

    public static void publish(List<Case> newCases, Map<Id, Case> oldMap) {
        List<Id> caseIdsToPublish = new List<Id>();

        for (Case c : newCases) {
            // Skip Cases with no Location — they can't populate lat/lon
            if (c.Locations__c == null) {
                continue;
            }

            if (oldMap == null) {
                // Insert context — publish for all Cases with a Location
                caseIdsToPublish.add(c.Id);
            } else {
                // Update context — publish only if a watched field changed
                Case old = oldMap.get(c.Id);
                if (c.Status != old.Status
                    || c.Assigned_Technician__c != old.Assigned_Technician__c
                    || c.Scheduled_Date__c != old.Scheduled_Date__c) {
                    caseIdsToPublish.add(c.Id);
                }
            }
        }

        if (caseIdsToPublish.isEmpty()) {
            return;
        }

        List<Case> enriched = [
            SELECT Id, CaseNumber, Subject, Status,
                   Assigned_Technician__c, Assigned_Technician__r.Name,
                   Scheduled_Date__c,
                   Locations__c, Locations__r.Name,
                   Locations__r.Coordinates__Latitude__s,
                   Locations__r.Coordinates__Longitude__s
            FROM Case
            WHERE Id IN :caseIdsToPublish
        ];

        List<CaseStatusChanged__e> events = new List<CaseStatusChanged__e>();
        for (Case c : enriched) {
            CaseStatusChanged__e evt = new CaseStatusChanged__e();
            evt.Case_Id__c               = c.Id;
            evt.Case_Number__c           = c.CaseNumber;
            evt.Subject__c               = c.Subject;
            evt.Status__c                = c.Status;
            evt.Assigned_Technician_Id__c   = c.Assigned_Technician__c;
            evt.Assigned_Technician_Name__c =
                c.Assigned_Technician__r != null ? c.Assigned_Technician__r.Name : null;
            evt.Scheduled_Date__c        = c.Scheduled_Date__c;
            evt.Location_Name__c         =
                c.Locations__r != null ? c.Locations__r.Name : null;
            evt.Latitude__c              =
                c.Locations__r != null ? c.Locations__r.Coordinates__Latitude__s : null;
            evt.Longitude__c             =
                c.Locations__r != null ? c.Locations__r.Coordinates__Longitude__s : null;
            events.add(evt);
        }

        EventBus.publish(events);
    }
}
```

- [ ] **Step 2.8: Deploy classes to org and run tests**

```bash
sf project deploy start \
  --source-dir force-app/main/default/classes/CaseEventPublisher.cls \
  --source-dir force-app/main/default/classes/CaseEventPublisher.cls-meta.xml \
  --source-dir force-app/main/default/classes/CaseEventPublisherTest.cls \
  --source-dir force-app/main/default/classes/CaseEventPublisherTest.cls-meta.xml \
  --target-org fieldservice-dev
```

Then run the tests:

```bash
sf apex run test \
  --class-names CaseEventPublisherTest \
  --result-format human \
  --wait 5 \
  --target-org fieldservice-dev
```

Expected: `publishesEventOnInsert` and `publishesEventOnStatusChange` **FAIL** (trigger not wired yet — `EventBus.publish` is never called). `noEventWhenUnrelatedFieldChanges` and `publishesOneEventPerChangedCaseInBulkUpdate` may also fail for the same reason. This is correct — tests are written before the trigger. Move on.

- [ ] **Step 2.9: Commit**

```bash
git add force-app/main/default/classes/CaseEventPublisher.cls \
        force-app/main/default/classes/CaseEventPublisher.cls-meta.xml \
        force-app/main/default/classes/CaseEventPublisherTest.cls \
        force-app/main/default/classes/CaseEventPublisherTest.cls-meta.xml
git commit -m "feat: add CaseEventPublisher handler and tests (trigger pending)"
```

---

## Task 3: `CaseEventTrigger` — wire it all together

**Files:**
- Create: `force-app/main/default/triggers/CaseEventTrigger.trigger`
- Create: `force-app/main/default/triggers/CaseEventTrigger.trigger-meta.xml`

- [ ] **Step 3.1: Create the trigger**

Create `force-app/main/default/triggers/CaseEventTrigger.trigger`:

```apex
trigger CaseEventTrigger on Case (after insert, after update) {
    CaseEventPublisher.publish(Trigger.new, Trigger.oldMap);
}
```

Create `force-app/main/default/triggers/CaseEventTrigger.trigger-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ApexTrigger xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>66.0</apiVersion>
    <status>Active</status>
</ApexTrigger>
```

- [ ] **Step 3.2: Deploy trigger to org**

```bash
sf project deploy start \
  --source-dir force-app/main/default/triggers/CaseEventTrigger.trigger \
  --source-dir force-app/main/default/triggers/CaseEventTrigger.trigger-meta.xml \
  --target-org fieldservice-dev
```

Expected: `Deploy Succeeded` with 1 trigger deployed.

- [ ] **Step 3.3: Run all tests — expect all 4 to pass**

```bash
sf apex run test \
  --class-names CaseEventPublisherTest \
  --result-format human \
  --wait 5 \
  --target-org fieldservice-dev
```

Expected output (all pass):
```
=== Test Results
TEST NAME                                              OUTCOME  MESSAGE  RUNTIME (MS)
─────────────────────────────────────────────────────────────────────────────────────
CaseEventPublisherTest.noEventWhenUnrelatedFieldChanges  Pass             ...
CaseEventPublisherTest.publishesEventOnInsert             Pass             ...
CaseEventPublisherTest.publishesEventOnStatusChange       Pass             ...
CaseEventPublisherTest.publishesOneEventPerChangedCaseInBulkUpdate  Pass  ...
```

If `publishesEventOnInsert` fails with 0 events: the trigger fires `after insert` so `Test.getEventBus().getPublishedMessages()` should capture the event published inside `Test.startTest()`/`Test.stopTest()`. If count is 0, check that the `Case` in the test has `Locations__c` set (it does — see Step 2.3) and that `CaseEventPublisher` is not returning early due to the null location guard.

If `publishesOneEventPerChangedCaseInBulkUpdate` shows 10 instead of 5: the insert fired events that weren't cleared. Add `Test.getEventBus().deliver();` after the insert and before `Test.startTest()` — this is already in the test body (Step 2.6), but confirm it's present.

- [ ] **Step 3.4: Commit**

```bash
git add force-app/main/default/triggers/CaseEventTrigger.trigger \
        force-app/main/default/triggers/CaseEventTrigger.trigger-meta.xml
git commit -m "feat: add CaseEventTrigger — Phase 3 complete"
```

---

## Task 4: Smoke test in the org

- [ ] **Step 4.1: Verify trigger fires on a real Case update**

```bash
sf apex run --target-org fieldservice-dev
```

Paste and execute this anonymous Apex to update one of the seeded Cases:

```apex
Case c = [SELECT Id, Status FROM Case WHERE Subject LIKE '%Riverside%' LIMIT 1];
c.Status = 'Working';
update c;
System.debug('Updated case: ' + c.Id);
```

Then check the event was published by querying the event bus log (Platform Events don't persist, so use the debug log):

```bash
sf apex log list --target-org fieldservice-dev
sf apex log get --log-id <most-recent-id> --target-org fieldservice-dev
```

Look for `EventBus.publish` in the log. Alternatively, subscribe to the event in the Developer Console (Setup → Platform Events → CaseStatusChanged__e → Subscribe) to confirm delivery.

- [ ] **Step 4.2: Update PROJECT_CONTEXT.md to mark Phase 3 complete**

In `PROJECT_CONTEXT.md`, change:

```
- [ ] Phase 3 — Platform Events (Case/Asset change → event)
```

to:

```
- [x] Phase 3 — Platform Events (Case/Asset change → event)
```

- [ ] **Step 4.3: Final commit**

```bash
git add PROJECT_CONTEXT.md
git commit -m "docs: mark Phase 3 complete"
```
