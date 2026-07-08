# Phase 5 — Webhook Receiver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire `CaseStatusChanged__e` Platform Events through an Apex Queueable callout to a Nuxt webhook endpoint that upserts into Neon Postgres, with failure logging and scheduled retry up to 5 times.

**Architecture:** `CaseStatusChangedTrigger` (after insert on Platform Event) enqueues `CaseEventCallout` (Queueable + callout=true), which POSTs camelCase JSON to `POST /api/cases/sync` on Vercel. The Nuxt endpoint validates a shared secret and upserts with an ordering guard (`last_modified_date`). Failures log to `Sync_Failure__c`; `CaseEventRetryScheduler` retries hourly up to 5 times.

**Tech Stack:** Apex (API 66.0), Salesforce Platform Events, Custom Metadata, Nuxt 3 / Nitro, `pg` (node-postgres), Neon Postgres, Vercel.

---

## Setup: export Neon connection string

Before running any `psql` commands in this plan, export your connection string in your shell:

```bash
export NEON_DATABASE_URL="postgresql://neondb_owner:<password>@ep-aged-unit-adqbfgfu.c-2.us-east-1.aws.neon.tech/neondb?sslmode=require"
```

Store this in a local untracked file (e.g. `~/.fieldservice_env`) and `source` it — do NOT commit it. Replace `<password>` with the real value from the Neon dashboard. **Rotate the Neon password after Phase 5 is complete** — treat any password that has appeared in conversation context as burned.

---

## File map

| File | Action | Purpose |
|---|---|---|
| `force-app/main/default/objects/CaseStatusChanged__e/fields/Last_Modified_Date__c.field-meta.xml` | Create | New event field |
| `force-app/main/default/classes/CaseEventPublisher.cls` | Modify | Add `Last_Modified_Date__c` + `Locations__c` to watched fields |
| `force-app/main/default/classes/CaseEventPublisherTest.cls` | Modify | Add `publishesEventOnLocationChange` test |
| `force-app/main/default/objects/Sync_Failure__c/Sync_Failure__c.object-meta.xml` | Create | Custom object |
| `force-app/main/default/objects/Sync_Failure__c/fields/Case_Id__c.field-meta.xml` | Create | |
| `force-app/main/default/objects/Sync_Failure__c/fields/Payload__c.field-meta.xml` | Create | LongTextArea(1000) |
| `force-app/main/default/objects/Sync_Failure__c/fields/Error_Message__c.field-meta.xml` | Create | |
| `force-app/main/default/objects/Sync_Failure__c/fields/Failed_At__c.field-meta.xml` | Create | |
| `force-app/main/default/objects/Sync_Failure__c/fields/Last_Retry_At__c.field-meta.xml` | Create | |
| `force-app/main/default/objects/Sync_Failure__c/fields/Retry_Count__c.field-meta.xml` | Create | Default 0 |
| `force-app/main/default/objects/Sync_Failure__c/fields/Resolved__c.field-meta.xml` | Create | Default false |
| `force-app/main/default/objects/SyncConfig__mdt/SyncConfig__mdt.object-meta.xml` | Create | Custom Metadata Type |
| `force-app/main/default/objects/SyncConfig__mdt/fields/Endpoint_URL__c.field-meta.xml` | Create | |
| `force-app/main/default/objects/SyncConfig__mdt/fields/Sync_Secret__c.field-meta.xml` | Create | |
| `force-app/main/default/customMetadata/SyncConfig.FieldServiceSync.md-meta.xml` | Create | Record with URL + secret placeholder |
| `force-app/main/default/remoteSiteSettings/FieldServiceNuxt.remoteSite-meta.xml` | Create | Allow callouts to Vercel |
| `force-app/main/default/triggers/CaseStatusChangedTrigger.trigger` | Create | after insert on `CaseStatusChanged__e` |
| `force-app/main/default/triggers/CaseStatusChangedTrigger.trigger-meta.xml` | Create | |
| `force-app/main/default/classes/CaseEventCallout.cls` | Create | Queueable; HTTP POST + failure logging |
| `force-app/main/default/classes/CaseEventCallout.cls-meta.xml` | Create | |
| `force-app/main/default/classes/CaseEventCalloutTest.cls` | Create | Unit tests incl. full payload shape assertion |
| `force-app/main/default/classes/CaseEventCalloutTest.cls-meta.xml` | Create | |
| `force-app/main/default/classes/CaseEventRetryScheduler.cls` | Create | Schedulable; retries failures |
| `force-app/main/default/classes/CaseEventRetryScheduler.cls-meta.xml` | Create | |
| `force-app/main/default/classes/CaseEventRetrySchedulerTest.cls` | Create | Unit tests |
| `force-app/main/default/classes/CaseEventRetrySchedulerTest.cls-meta.xml` | Create | |
| `apps/web/server/db/schema.sql` | Modify | Add `last_modified_date` column |
| `apps/web/server/api/cases/sync.post.ts` | Create | Webhook receiver |

---

## Task 1: `Last_Modified_Date__c` event field + update `CaseEventPublisher`

**Files:**
- Create: `force-app/main/default/objects/CaseStatusChanged__e/fields/Last_Modified_Date__c.field-meta.xml`
- Modify: `force-app/main/default/classes/CaseEventPublisher.cls`
- Modify: `force-app/main/default/classes/CaseEventPublisherTest.cls`

- [ ] **Step 1.1: Create the field metadata**

Create `force-app/main/default/objects/CaseStatusChanged__e/fields/Last_Modified_Date__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Last_Modified_Date__c</fullName>
    <label>Last Modified Date</label>
    <type>DateTime</type>
</CustomField>
```

- [ ] **Step 1.2: Deploy the new field**

```bash
sf project deploy start \
  --source-dir force-app/main/default/objects/CaseStatusChanged__e/fields/Last_Modified_Date__c.field-meta.xml \
  --target-org fieldservice-dev
```

Expected: `Deploy Succeeded`, 1 component.

- [ ] **Step 1.3: Update `CaseEventPublisher.cls`**

Three changes:
1. Add `LastModifiedDate` to the SOQL SELECT
2. Populate `evt.Last_Modified_Date__c` from `c.LastModifiedDate`
3. Add `Locations__c` to the watched-fields diff (location reassignment must also trigger a sync)

Replace the entire file with:

```apex
public with sharing class CaseEventPublisher {

    @TestVisible
    private static List<CaseStatusChanged__e> publishedEvents = new List<CaseStatusChanged__e>();

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
                    || c.Scheduled_Date__c != old.Scheduled_Date__c
                    || c.Locations__c != old.Locations__c) {
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
                   Scheduled_Date__c, LastModifiedDate,
                   Locations__c, Locations__r.Name,
                   Locations__r.Coordinates__Latitude__s,
                   Locations__r.Coordinates__Longitude__s
            FROM Case
            WHERE Id IN :caseIdsToPublish
        ];

        List<CaseStatusChanged__e> events = new List<CaseStatusChanged__e>();
        for (Case c : enriched) {
            CaseStatusChanged__e evt = new CaseStatusChanged__e();
            evt.Case_Id__c                  = c.Id;
            evt.Case_Number__c              = c.CaseNumber;
            evt.Subject__c                  = c.Subject;
            evt.Status__c                   = c.Status;
            evt.Assigned_Technician_Id__c   = c.Assigned_Technician__c;
            evt.Assigned_Technician_Name__c =
                c.Assigned_Technician__r != null ? c.Assigned_Technician__r.Name : null;
            evt.Scheduled_Date__c           = c.Scheduled_Date__c;
            evt.Last_Modified_Date__c       = c.LastModifiedDate;
            evt.Location_Name__c            =
                c.Locations__r != null ? c.Locations__r.Name : null;
            evt.Latitude__c                 =
                c.Locations__r != null ? c.Locations__r.Coordinates__Latitude__s : null;
            evt.Longitude__c                =
                c.Locations__r != null ? c.Locations__r.Coordinates__Longitude__s : null;
            events.add(evt);
        }

        publishedEvents.addAll(events);
        EventBus.publish(events);
    }
}
```

- [ ] **Step 1.4: Add `publishesEventOnLocationChange` test to `CaseEventPublisherTest.cls`**

Add this method to the existing test class (after the existing 4 methods):

```apex
@isTest
static void publishesEventOnLocationChange() {
    Locations__c loc = [SELECT Id FROM Locations__c LIMIT 1];

    // Create a second location to reassign the case to
    Locations__c loc2 = new Locations__c(
        Name = 'New Site',
        Coordinates__Latitude__s = -33.8000,
        Coordinates__Longitude__s = 18.5000
    );
    insert loc2;

    Case c = [SELECT Id FROM Case LIMIT 1];

    Test.startTest();
    c.Locations__c = loc2.Id;
    update c;
    Test.stopTest();

    List<CaseStatusChanged__e> events = CaseEventPublisher.publishedEvents;
    System.assertEquals(1, events.size(), 'Expected 1 event on location change');
    System.assertEquals('New Site', events[0].Location_Name__c);
}
```

- [ ] **Step 1.5: Deploy and run all publisher tests**

```bash
sf project deploy start \
  --source-dir force-app/main/default/classes/CaseEventPublisher.cls \
  --source-dir force-app/main/default/classes/CaseEventPublisher.cls-meta.xml \
  --source-dir force-app/main/default/classes/CaseEventPublisherTest.cls \
  --source-dir force-app/main/default/classes/CaseEventPublisherTest.cls-meta.xml \
  --target-org fieldservice-dev

sf apex run test \
  --class-names CaseEventPublisherTest \
  --result-format human \
  --wait 5 \
  --target-org fieldservice-dev
```

Expected: all 5 tests pass (4 existing + 1 new).

- [ ] **Step 1.6: Commit**

```bash
git add force-app/main/default/objects/CaseStatusChanged__e/fields/Last_Modified_Date__c.field-meta.xml \
        force-app/main/default/classes/CaseEventPublisher.cls \
        force-app/main/default/classes/CaseEventPublisherTest.cls
git commit -m "feat: add Last_Modified_Date__c to event, Locations__c to watched fields"
git push
```

---

## Task 2: `Sync_Failure__c` custom object

**Files:** `force-app/main/default/objects/Sync_Failure__c/` (8 files)

- [ ] **Step 2.1: Create directory and object metadata**

```bash
mkdir -p force-app/main/default/objects/Sync_Failure__c/fields
```

Create `force-app/main/default/objects/Sync_Failure__c/Sync_Failure__c.object-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Sync Failure</label>
    <pluralLabel>Sync Failures</pluralLabel>
    <deploymentStatus>Deployed</deploymentStatus>
    <sharingModel>ReadWrite</sharingModel>
</CustomObject>
```

- [ ] **Step 2.2: Create field metadata files**

Create `force-app/main/default/objects/Sync_Failure__c/fields/Case_Id__c.field-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Case_Id__c</fullName>
    <label>Case ID</label>
    <length>18</length>
    <type>Text</type>
    <unique>false</unique>
    <externalId>false</externalId>
</CustomField>
```

Create `force-app/main/default/objects/Sync_Failure__c/fields/Payload__c.field-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Payload__c</fullName>
    <label>Payload</label>
    <length>1000</length>
    <type>LongTextArea</type>
    <visibleLines>5</visibleLines>
</CustomField>
```

Create `force-app/main/default/objects/Sync_Failure__c/fields/Error_Message__c.field-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Error_Message__c</fullName>
    <label>Error Message</label>
    <length>255</length>
    <type>Text</type>
    <unique>false</unique>
    <externalId>false</externalId>
</CustomField>
```

Create `force-app/main/default/objects/Sync_Failure__c/fields/Failed_At__c.field-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Failed_At__c</fullName>
    <label>Failed At</label>
    <type>DateTime</type>
</CustomField>
```

Create `force-app/main/default/objects/Sync_Failure__c/fields/Last_Retry_At__c.field-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Last_Retry_At__c</fullName>
    <label>Last Retry At</label>
    <type>DateTime</type>
</CustomField>
```

Create `force-app/main/default/objects/Sync_Failure__c/fields/Retry_Count__c.field-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Retry_Count__c</fullName>
    <label>Retry Count</label>
    <precision>2</precision>
    <scale>0</scale>
    <type>Number</type>
    <defaultValue>0</defaultValue>
    <unique>false</unique>
    <externalId>false</externalId>
</CustomField>
```

Create `force-app/main/default/objects/Sync_Failure__c/fields/Resolved__c.field-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Resolved__c</fullName>
    <label>Resolved</label>
    <type>Checkbox</type>
    <defaultValue>false</defaultValue>
</CustomField>
```

- [ ] **Step 2.3: Deploy**

```bash
sf project deploy start \
  --source-dir force-app/main/default/objects/Sync_Failure__c \
  --target-org fieldservice-dev
```

Expected: `Deploy Succeeded`, 8 components (1 object + 7 fields).

- [ ] **Step 2.4: Commit**

```bash
git add force-app/main/default/objects/Sync_Failure__c
git commit -m "feat: add Sync_Failure__c custom object"
git push
```

---

## Task 3: `SyncConfig__mdt` + Remote Site Setting + Vercel `SYNC_SECRET`

- [ ] **Step 3.1: Generate a shared secret**

```bash
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

Copy the output — this is `SYNC_SECRET`. Use it in Steps 3.3 and 3.5. Never commit the real value.

- [ ] **Step 3.2: Create `SyncConfig__mdt` object and fields**

```bash
mkdir -p force-app/main/default/objects/SyncConfig__mdt/fields
```

Create `force-app/main/default/objects/SyncConfig__mdt/SyncConfig__mdt.object-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Sync Config</label>
    <pluralLabel>Sync Configs</pluralLabel>
    <deploymentStatus>Deployed</deploymentStatus>
</CustomObject>
```

Create `force-app/main/default/objects/SyncConfig__mdt/fields/Endpoint_URL__c.field-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Endpoint_URL__c</fullName>
    <label>Endpoint URL</label>
    <length>255</length>
    <type>Text</type>
    <unique>false</unique>
    <externalId>false</externalId>
</CustomField>
```

Create `force-app/main/default/objects/SyncConfig__mdt/fields/Sync_Secret__c.field-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Sync_Secret__c</fullName>
    <label>Sync Secret</label>
    <length>255</length>
    <type>Text</type>
    <unique>false</unique>
    <externalId>false</externalId>
</CustomField>
```

- [ ] **Step 3.3: Create the `FieldServiceSync` Custom Metadata record**

```bash
mkdir -p force-app/main/default/customMetadata
```

Create `force-app/main/default/customMetadata/SyncConfig.FieldServiceSync.md-meta.xml`.
Replace `YOUR_SECRET_HERE` with the value from Step 3.1 before deploying,
but commit the file with `YOUR_SECRET_HERE` as the placeholder value:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xmlns:xsd="http://www.w3.org/2001/XMLSchema">
    <label>Field Service Sync</label>
    <protected>false</protected>
    <values>
        <field>Endpoint_URL__c</field>
        <value xsi:type="xsd:string">https://web-coral-seven-77.vercel.app/api/cases/sync</value>
    </values>
    <values>
        <field>Sync_Secret__c</field>
        <value xsi:type="xsd:string">YOUR_SECRET_HERE</value>
    </values>
</CustomMetadata>
```

Before deploying, replace `YOUR_SECRET_HERE` in the file with the real secret. After deploying, revert the file back to `YOUR_SECRET_HERE` before committing.

- [ ] **Step 3.4: Create the Remote Site Setting**

```bash
mkdir -p force-app/main/default/remoteSiteSettings
```

Create `force-app/main/default/remoteSiteSettings/FieldServiceNuxt.remoteSite-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<RemoteSiteSetting xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>Nuxt field service app on Vercel</description>
    <disableProtocolSecurity>false</disableProtocolSecurity>
    <isActive>true</isActive>
    <url>https://web-coral-seven-77.vercel.app</url>
</RemoteSiteSetting>
```

- [ ] **Step 3.5: Deploy all (with real secret in file)**

```bash
sf project deploy start \
  --source-dir force-app/main/default/objects/SyncConfig__mdt \
  --source-dir force-app/main/default/customMetadata/SyncConfig.FieldServiceSync.md-meta.xml \
  --source-dir force-app/main/default/remoteSiteSettings/FieldServiceNuxt.remoteSite-meta.xml \
  --target-org fieldservice-dev
```

Expected: `Deploy Succeeded`.

- [ ] **Step 3.6: Revert secret placeholder in file before committing**

Replace the real secret back with `YOUR_SECRET_HERE` in `SyncConfig.FieldServiceSync.md-meta.xml`, then commit:

```bash
git add force-app/main/default/objects/SyncConfig__mdt \
        force-app/main/default/customMetadata/SyncConfig.FieldServiceSync.md-meta.xml \
        force-app/main/default/remoteSiteSettings/FieldServiceNuxt.remoteSite-meta.xml
git commit -m "feat: add SyncConfig__mdt, FieldServiceSync record, and Remote Site Setting"
git push
```

- [ ] **Step 3.7: Set `SYNC_SECRET` on Vercel and redeploy**

```bash
cd apps/web && echo "YOUR_SECRET_HERE" | vercel env add SYNC_SECRET production
vercel --yes --prod
```

Replace `YOUR_SECRET_HERE` with the real secret from Step 3.1.

---

## Task 4: Nuxt schema migration + webhook receiver

**Files:**
- Modify: `apps/web/server/db/schema.sql`
- Create: `apps/web/server/api/cases/sync.post.ts`

- [ ] **Step 4.1: Apply `last_modified_date` column migration to Neon**

```bash
export PATH="/usr/local/opt/libpq/bin:$PATH"
psql "$NEON_DATABASE_URL" \
  -c "ALTER TABLE cases ADD COLUMN IF NOT EXISTS last_modified_date TIMESTAMPTZ;"
```

Expected: `ALTER TABLE`

Verify:
```bash
psql "$NEON_DATABASE_URL" -c "\d cases"
```

Expected: `last_modified_date` column present.

- [ ] **Step 4.2: Update `apps/web/server/db/schema.sql`**

Replace the entire file with:

```sql
CREATE TABLE IF NOT EXISTS cases (
  id                 TEXT PRIMARY KEY,
  case_number        TEXT NOT NULL,
  subject            TEXT,
  status             TEXT NOT NULL,
  technician_id      TEXT,
  technician_name    TEXT,
  scheduled_date     TIMESTAMPTZ,
  location_name      TEXT,
  latitude           DOUBLE PRECISION,
  longitude          DOUBLE PRECISION,
  last_modified_date TIMESTAMPTZ,
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

- [ ] **Step 4.3: Create `apps/web/server/api/cases/sync.post.ts`**

```bash
mkdir -p apps/web/server/api/cases
```

Create `apps/web/server/api/cases/sync.post.ts`:

```ts
import pool from '../../db/client'

export default defineEventHandler(async (event) => {
  // Validate shared secret
  const secret = getHeader(event, 'x-sync-secret')
  if (!secret || secret !== process.env.SYNC_SECRET) {
    throw createError({ statusCode: 401, message: 'Unauthorized' })
  }

  const body = await readBody(event)

  try {
    await pool.query(
      `INSERT INTO cases (
        id, case_number, subject, status,
        technician_id, technician_name, scheduled_date,
        location_name, latitude, longitude,
        last_modified_date, updated_at
      ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,now())
      ON CONFLICT (id) DO UPDATE SET
        status             = EXCLUDED.status,
        technician_id      = EXCLUDED.technician_id,
        technician_name    = EXCLUDED.technician_name,
        scheduled_date     = EXCLUDED.scheduled_date,
        location_name      = EXCLUDED.location_name,
        latitude           = EXCLUDED.latitude,
        longitude          = EXCLUDED.longitude,
        last_modified_date = EXCLUDED.last_modified_date,
        updated_at         = now()
      WHERE cases.last_modified_date < EXCLUDED.last_modified_date`,
      [
        body.caseId,
        body.caseNumber,
        body.subject,
        body.status,
        body.technicianId ?? null,
        body.technicianName ?? null,
        body.scheduledDate ?? null,
        body.locationName ?? null,
        body.latitude ?? null,
        body.longitude ?? null,
        body.lastModifiedDate
      ]
    )
  } catch (err) {
    console.error('[sync.post] DB error:', err)
    throw createError({ statusCode: 500, message: 'Database error' })
  }

  return { ok: true }
})
```

- [ ] **Step 4.4: Set `SYNC_SECRET` in local `.env` for dev testing**

Add to `apps/web/.env` (this file is gitignored):
```
SYNC_SECRET=<the same secret from Task 3 Step 3.1>
```

- [ ] **Step 4.5: Verify endpoint locally**

```bash
cd apps/web && npm run dev
```

In a second terminal — test auth rejection:
```bash
curl -s -X POST http://localhost:3000/api/cases/sync \
  -H "Content-Type: application/json" \
  -d '{"caseId":"test"}'
```
Expected: `{"statusCode":401,"message":"Unauthorized"}`

Test a valid upsert (replace `<secret>`):
```bash
curl -s -X POST http://localhost:3000/api/cases/sync \
  -H "Content-Type: application/json" \
  -H "x-sync-secret: <secret>" \
  -d '{
    "caseId": "500TEST000000001AAA",
    "caseNumber": "00001099",
    "subject": "Test sync",
    "status": "New",
    "technicianId": null,
    "technicianName": null,
    "scheduledDate": null,
    "locationName": "Test Site",
    "latitude": -33.9249,
    "longitude": 18.4241,
    "lastModifiedDate": "2026-07-08T10:00:00Z"
  }'
```
Expected: `{"ok":true}`

Verify row in Neon:
```bash
export PATH="/usr/local/opt/libpq/bin:$PATH"
psql "$NEON_DATABASE_URL" \
  -c "SELECT id, status, last_modified_date FROM cases WHERE id = '500TEST000000001AAA';"
```

Stop dev server. Clean up test row:
```bash
psql "$NEON_DATABASE_URL" \
  -c "DELETE FROM cases WHERE id = '500TEST000000001AAA';"
```

- [ ] **Step 4.6: Commit and deploy to Vercel**

```bash
cd /Users/tftf/git/field-service-app
git add apps/web/server/api/cases/sync.post.ts apps/web/server/db/schema.sql
git commit -m "feat: add /api/cases/sync webhook receiver and last_modified_date column"
git push
```

Vercel auto-deploys on push. Wait ~30s then verify prod health:
```bash
curl -s https://web-coral-seven-77.vercel.app/api/health
```
Expected: `{"status":"ok","db":{"ok":1}}`

---

## Task 5: `CaseEventCallout` Queueable (test-first)

**Files:**
- Create: `force-app/main/default/classes/CaseEventCallout.cls`
- Create: `force-app/main/default/classes/CaseEventCallout.cls-meta.xml`
- Create: `force-app/main/default/classes/CaseEventCalloutTest.cls`
- Create: `force-app/main/default/classes/CaseEventCalloutTest.cls-meta.xml`

- [ ] **Step 5.1: Create stub `CaseEventCallout.cls` and meta**

Create `force-app/main/default/classes/CaseEventCallout.cls`:

```apex
public with sharing class CaseEventCallout implements Queueable, Database.AllowsCallouts {
    private List<CaseStatusChanged__e> events;

    public CaseEventCallout(List<CaseStatusChanged__e> events) {
        this.events = events;
    }

    public void execute(QueueableContext ctx) {
    }
}
```

Create `force-app/main/default/classes/CaseEventCallout.cls-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>66.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

- [ ] **Step 5.2: Create `CaseEventCalloutTest.cls` with failing tests**

Create `force-app/main/default/classes/CaseEventCalloutTest.cls`:

```apex
@isTest
private class CaseEventCalloutTest {

    // Mock captures the outgoing request so tests can assert on payload shape
    private class CapturingMock implements HttpCalloutMock {
        public HttpRequest capturedRequest;
        private Integer statusCode;
        private String body;

        CapturingMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HTTPResponse respond(HTTPRequest req) {
            this.capturedRequest = req;
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            return res;
        }
    }

    private static CaseStatusChanged__e buildTestEvent() {
        CaseStatusChanged__e evt = new CaseStatusChanged__e();
        evt.Case_Id__c                  = '500fj00001k99CMAAY';
        evt.Case_Number__c              = '00001026';
        evt.Subject__c                  = 'Rooftop AC unit down';
        evt.Status__c                   = 'Working';
        evt.Assigned_Technician_Id__c   = '005fj00000IDO8cAAH';
        evt.Assigned_Technician_Name__c = 'Mduduzi Ndlovu';
        evt.Scheduled_Date__c           = Datetime.newInstance(2026, 7, 10, 9, 0, 0);
        evt.Location_Name__c            = 'Riverside Mall';
        evt.Latitude__c                 = -33.9249;
        evt.Longitude__c                = 18.4241;
        evt.Last_Modified_Date__c       = Datetime.newInstance(2026, 7, 8, 8, 0, 0);
        return evt;
    }

    @isTest
    static void postsCorrectJsonPayloadOn200() {
        CapturingMock mock = new CapturingMock(200, '{"ok":true}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(new CaseEventCallout(
            new List<CaseStatusChanged__e>{ buildTestEvent() }
        ));
        Test.stopTest();

        // Assert no failure records on success
        System.assertEquals(0,
            [SELECT Id FROM Sync_Failure__c].size(),
            'Expected no failures on 200');

        // Assert all 11 camelCase field mappings in the JSON body
        System.assertNotEquals(null, mock.capturedRequest, 'Request must have been sent');
        Map<String, Object> sent = (Map<String, Object>)
            JSON.deserializeUntyped(mock.capturedRequest.getBody());

        System.assertEquals('500fj00001k99CMAAY', sent.get('caseId'));
        System.assertEquals('00001026',            sent.get('caseNumber'));
        System.assertEquals('Rooftop AC unit down',sent.get('subject'));
        System.assertEquals('Working',             sent.get('status'));
        System.assertEquals('005fj00000IDO8cAAH',  sent.get('technicianId'));
        System.assertEquals('Mduduzi Ndlovu',      sent.get('technicianName'));
        System.assertNotEquals(null,               sent.get('scheduledDate'));
        System.assertEquals('Riverside Mall',      sent.get('locationName'));
        System.assertEquals(-33.9249,              sent.get('latitude'));
        System.assertEquals(18.4241,               sent.get('longitude'));
        System.assertNotEquals(null,               sent.get('lastModifiedDate'));

        // Assert secret header is present
        System.assertEquals(
            'application/json',
            mock.capturedRequest.getHeader('Content-Type'));
        System.assertNotEquals(null,
            mock.capturedRequest.getHeader('x-sync-secret'),
            'Secret header must be set');
    }

    @isTest
    static void insertsSyncFailureRecordOnNon200() {
        CapturingMock mock = new CapturingMock(500, 'Server Error');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(new CaseEventCallout(
            new List<CaseStatusChanged__e>{ buildTestEvent() }
        ));
        Test.stopTest();

        List<Sync_Failure__c> failures = [
            SELECT Case_Id__c, Error_Message__c, Retry_Count__c,
                   Resolved__c, Payload__c, Failed_At__c
            FROM Sync_Failure__c
        ];
        System.assertEquals(1, failures.size(), 'Expected 1 failure record');
        System.assertEquals('500fj00001k99CMAAY', failures[0].Case_Id__c);
        System.assertEquals(0,     failures[0].Retry_Count__c);
        System.assertEquals(false, failures[0].Resolved__c);
        System.assertNotEquals(null, failures[0].Payload__c,
            'Payload must be stored for retry');
        System.assertNotEquals(null, failures[0].Failed_At__c);

        // Payload must include lastModifiedDate for ordering guard on retry
        Map<String, Object> storedPayload = (Map<String, Object>)
            JSON.deserializeUntyped(failures[0].Payload__c);
        System.assertNotEquals(null, storedPayload.get('lastModifiedDate'),
            'Stored payload must include lastModifiedDate');
    }
}
```

Create `force-app/main/default/classes/CaseEventCalloutTest.cls-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>66.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

- [ ] **Step 5.3: Deploy stub + tests, confirm red**

```bash
sf project deploy start \
  --source-dir force-app/main/default/classes/CaseEventCallout.cls \
  --source-dir force-app/main/default/classes/CaseEventCallout.cls-meta.xml \
  --source-dir force-app/main/default/classes/CaseEventCalloutTest.cls \
  --source-dir force-app/main/default/classes/CaseEventCalloutTest.cls-meta.xml \
  --target-org fieldservice-dev

sf apex run test \
  --class-names CaseEventCalloutTest \
  --result-format human \
  --wait 5 \
  --target-org fieldservice-dev
```

Expected: both tests fail — stub does nothing. Correct TDD red phase.

- [ ] **Step 5.4: Implement `CaseEventCallout.cls`**

Replace the file with:

```apex
public with sharing class CaseEventCallout implements Queueable, Database.AllowsCallouts {
    private List<CaseStatusChanged__e> events;

    public CaseEventCallout(List<CaseStatusChanged__e> events) {
        this.events = events;
    }

    public void execute(QueueableContext ctx) {
        SyncConfig__mdt config = [
            SELECT Endpoint_URL__c, Sync_Secret__c
            FROM SyncConfig__mdt
            WHERE DeveloperName = 'FieldServiceSync'
            LIMIT 1
        ];

        List<Sync_Failure__c> failures = new List<Sync_Failure__c>();

        for (CaseStatusChanged__e evt : events) {
            String payload = buildPayload(evt);
            String errorMsg = sendPayload(
                payload, config.Endpoint_URL__c, config.Sync_Secret__c);

            if (errorMsg != null) {
                Sync_Failure__c failure = new Sync_Failure__c();
                failure.Case_Id__c       = evt.Case_Id__c;
                failure.Payload__c       = payload;
                failure.Error_Message__c = errorMsg;
                failure.Failed_At__c     = Datetime.now();
                failure.Retry_Count__c   = 0;
                failure.Resolved__c      = false;
                failures.add(failure);
            }
        }

        if (!failures.isEmpty()) {
            insert failures;
        }
    }

    private String buildPayload(CaseStatusChanged__e evt) {
        Map<String, Object> payload = new Map<String, Object>{
            'caseId'           => evt.Case_Id__c,
            'caseNumber'       => evt.Case_Number__c,
            'subject'          => evt.Subject__c,
            'status'           => evt.Status__c,
            'technicianId'     => evt.Assigned_Technician_Id__c,
            'technicianName'   => evt.Assigned_Technician_Name__c,
            'scheduledDate'    => evt.Scheduled_Date__c != null
                ? evt.Scheduled_Date__c.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
                : null,
            'locationName'     => evt.Location_Name__c,
            'latitude'         => evt.Latitude__c,
            'longitude'        => evt.Longitude__c,
            'lastModifiedDate' => evt.Last_Modified_Date__c != null
                ? evt.Last_Modified_Date__c.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
                : null
        };
        return JSON.serialize(payload);
    }

    // Returns null on success, error message string on failure
    private String sendPayload(String payload, String endpointUrl, String secret) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpointUrl);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('x-sync-secret', secret);
        req.setBody(payload);

        try {
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() == 200) {
                return null;
            }
            return 'HTTP ' + res.getStatusCode() + ': '
                + res.getBody().abbreviate(200);
        } catch (Exception e) {
            return e.getMessage().abbreviate(255);
        }
    }
}
```

- [ ] **Step 5.5: Deploy and run tests — expect green**

```bash
sf project deploy start \
  --source-dir force-app/main/default/classes/CaseEventCallout.cls \
  --source-dir force-app/main/default/classes/CaseEventCallout.cls-meta.xml \
  --target-org fieldservice-dev

sf apex run test \
  --class-names CaseEventCalloutTest \
  --result-format human \
  --wait 5 \
  --target-org fieldservice-dev
```

Expected: both tests pass.

- [ ] **Step 5.6: Commit**

```bash
git add force-app/main/default/classes/CaseEventCallout.cls \
        force-app/main/default/classes/CaseEventCallout.cls-meta.xml \
        force-app/main/default/classes/CaseEventCalloutTest.cls \
        force-app/main/default/classes/CaseEventCalloutTest.cls-meta.xml
git commit -m "feat: add CaseEventCallout Queueable with failure logging"
git push
```

---

## Task 6: `CaseStatusChangedTrigger` + `CaseEventRetryScheduler`

- [ ] **Step 6.1: Create `CaseStatusChangedTrigger.trigger`**

Create `force-app/main/default/triggers/CaseStatusChangedTrigger.trigger`:
```apex
trigger CaseStatusChangedTrigger on CaseStatusChanged__e (after insert) {
    System.enqueueJob(new CaseEventCallout(Trigger.new));
}
```

Create `force-app/main/default/triggers/CaseStatusChangedTrigger.trigger-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<ApexTrigger xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>66.0</apiVersion>
    <status>Active</status>
</ApexTrigger>
```

- [ ] **Step 6.2: Create `CaseEventRetryScheduler.cls`**

Create `force-app/main/default/classes/CaseEventRetryScheduler.cls`:

```apex
public with sharing class CaseEventRetryScheduler implements Schedulable {

    public void execute(SchedulableContext ctx) {
        List<Sync_Failure__c> failures = [
            SELECT Id, Payload__c, Retry_Count__c
            FROM Sync_Failure__c
            WHERE Resolved__c = false
            AND Retry_Count__c < 5
        ];

        if (failures.isEmpty()) {
            return;
        }

        SyncConfig__mdt config = [
            SELECT Endpoint_URL__c, Sync_Secret__c
            FROM SyncConfig__mdt
            WHERE DeveloperName = 'FieldServiceSync'
            LIMIT 1
        ];

        List<Sync_Failure__c> toUpdate = new List<Sync_Failure__c>();

        for (Sync_Failure__c failure : failures) {
            String errorMsg = sendPayload(
                failure.Payload__c,
                config.Endpoint_URL__c,
                config.Sync_Secret__c
            );

            failure.Last_Retry_At__c = Datetime.now();

            if (errorMsg == null) {
                failure.Resolved__c = true;
            } else {
                failure.Retry_Count__c += 1;
                failure.Error_Message__c = errorMsg;
            }

            toUpdate.add(failure);
        }

        update toUpdate;
    }

    private String sendPayload(String payload, String endpointUrl, String secret) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpointUrl);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('x-sync-secret', secret);
        req.setBody(payload);

        try {
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() == 200) {
                return null;
            }
            return 'HTTP ' + res.getStatusCode() + ': '
                + res.getBody().abbreviate(200);
        } catch (Exception e) {
            return e.getMessage().abbreviate(255);
        }
    }
}
```

Create `force-app/main/default/classes/CaseEventRetryScheduler.cls-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>66.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

- [ ] **Step 6.3: Create `CaseEventRetrySchedulerTest.cls`**

Create `force-app/main/default/classes/CaseEventRetrySchedulerTest.cls`:

```apex
@isTest
private class CaseEventRetrySchedulerTest {

    private class MockHttpResponse implements HttpCalloutMock {
        private Integer statusCode;
        private String body;
        MockHttpResponse(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            return res;
        }
    }

    private static Sync_Failure__c buildFailure(Integer retryCount) {
        return new Sync_Failure__c(
            Case_Id__c       = '500fj00001k99CMAAY',
            Payload__c       = '{"caseId":"500fj00001k99CMAAY","status":"New",'
                             + '"lastModifiedDate":"2026-07-08T08:00:00Z"}',
            Error_Message__c = 'HTTP 500',
            Failed_At__c     = Datetime.now().addHours(-1),
            Retry_Count__c   = retryCount,
            Resolved__c      = false
        );
    }

    @isTest
    static void resolvesFailureOnSuccessfulRetry() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(200, '{"ok":true}'));
        Sync_Failure__c failure = buildFailure(1);
        insert failure;

        Test.startTest();
        new CaseEventRetryScheduler().execute(null);
        Test.stopTest();

        Sync_Failure__c updated = [
            SELECT Resolved__c, Retry_Count__c, Last_Retry_At__c
            FROM Sync_Failure__c WHERE Id = :failure.Id
        ];
        System.assertEquals(true, updated.Resolved__c, 'Should be resolved on 200');
        System.assertNotEquals(null, updated.Last_Retry_At__c);
    }

    @isTest
    static void incrementsRetryCountOnFailedRetry() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(500, 'Server Error'));
        Sync_Failure__c failure = buildFailure(2);
        insert failure;

        Test.startTest();
        new CaseEventRetryScheduler().execute(null);
        Test.stopTest();

        Sync_Failure__c updated = [
            SELECT Resolved__c, Retry_Count__c
            FROM Sync_Failure__c WHERE Id = :failure.Id
        ];
        System.assertEquals(false, updated.Resolved__c);
        System.assertEquals(3, updated.Retry_Count__c,
            'Retry count should increment on failure');
    }

    @isTest
    static void skipsFailuresAtMaxRetries() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(200, '{"ok":true}'));
        Sync_Failure__c failure = buildFailure(5);
        insert failure;

        Test.startTest();
        new CaseEventRetryScheduler().execute(null);
        Test.stopTest();

        Sync_Failure__c updated = [
            SELECT Resolved__c, Retry_Count__c
            FROM Sync_Failure__c WHERE Id = :failure.Id
        ];
        System.assertEquals(false, updated.Resolved__c,
            'Should not resolve record at max retries');
        System.assertEquals(5, updated.Retry_Count__c,
            'Retry count should not increment past 5');
    }
}
```

Create `force-app/main/default/classes/CaseEventRetrySchedulerTest.cls-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>66.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

- [ ] **Step 6.4: Deploy all and run all tests**

```bash
sf project deploy start \
  --source-dir force-app/main/default/triggers/CaseStatusChangedTrigger.trigger \
  --source-dir force-app/main/default/triggers/CaseStatusChangedTrigger.trigger-meta.xml \
  --source-dir force-app/main/default/classes/CaseEventRetryScheduler.cls \
  --source-dir force-app/main/default/classes/CaseEventRetryScheduler.cls-meta.xml \
  --source-dir force-app/main/default/classes/CaseEventRetrySchedulerTest.cls \
  --source-dir force-app/main/default/classes/CaseEventRetrySchedulerTest.cls-meta.xml \
  --target-org fieldservice-dev

sf apex run test \
  --class-names CaseEventCalloutTest,CaseEventRetrySchedulerTest,CaseEventPublisherTest \
  --result-format human \
  --wait 5 \
  --target-org fieldservice-dev
```

Expected: all tests pass.

- [ ] **Step 6.5: Schedule the retry job**

```bash
sf apex run --target-org fieldservice-dev
```

Paste and execute:
```apex
String cronExp = '0 0 * * * ?';
System.schedule('CaseEventRetryScheduler', cronExp, new CaseEventRetryScheduler());
System.debug('Scheduler registered');
```

- [ ] **Step 6.6: Commit**

```bash
git add force-app/main/default/triggers/CaseStatusChangedTrigger.trigger \
        force-app/main/default/triggers/CaseStatusChangedTrigger.trigger-meta.xml \
        force-app/main/default/classes/CaseEventRetryScheduler.cls \
        force-app/main/default/classes/CaseEventRetryScheduler.cls-meta.xml \
        force-app/main/default/classes/CaseEventRetrySchedulerTest.cls \
        force-app/main/default/classes/CaseEventRetrySchedulerTest.cls-meta.xml
git commit -m "feat: add CaseStatusChangedTrigger and CaseEventRetryScheduler"
git push
```

---

## Task 7: End-to-end smoke test + mark Phase 5 complete

- [ ] **Step 7.1: Update a real Case and confirm Neon row updates**

```bash
sf apex run --target-org fieldservice-dev
```

Paste:
```apex
Case c = [SELECT Id, Status FROM Case
          WHERE Subject = 'Rooftop AC unit down' LIMIT 1];
c.Status = 'Closed';
update c;
System.debug('Updated: ' + c.Id);
```

Wait ~5 seconds then query Neon:
```bash
export PATH="/usr/local/opt/libpq/bin:$PATH"
psql "$NEON_DATABASE_URL" \
  -c "SELECT id, status, last_modified_date, updated_at FROM cases;"
```

Expected: a row with `status = 'Closed'` and a recent `updated_at`.

- [ ] **Step 7.2: Mark Phase 5 complete in `PROJECT_CONTEXT.md`**

Change:
```
- [ ] Phase 5 — Webhook receiver (Platform Event → Postgres sync)
```
to:
```
- [x] Phase 5 — Webhook receiver (Platform Event → Postgres sync)
```

- [ ] **Step 7.3: Rotate the Neon password**

Go to the Neon dashboard → Settings → Reset password. Update `apps/web/.env`
and the Vercel `DATABASE_URL` env var with the new connection string:

```bash
cd apps/web && vercel env rm DATABASE_URL production
echo "<new-connection-string>" | vercel env add DATABASE_URL production
vercel --yes --prod
```

- [ ] **Step 7.4: Final commit**

```bash
git add PROJECT_CONTEXT.md
git commit -m "docs: mark Phase 5 complete"
git push
```
