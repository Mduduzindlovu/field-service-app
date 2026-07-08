# Phase 5 — Webhook Receiver Design

**Date:** 2026-07-08
**Status:** Approved

## Goal

When a `CaseStatusChanged__e` Platform Event fires in Salesforce, an Apex
Queueable POSTs the full enriched payload to `POST /api/cases/sync` on the
Nuxt app, which upserts the data into the `cases` Neon Postgres table.
Failed callouts are logged to `Sync_Failure__c` and retried hourly up to 5
times by a Schedulable. The Vercel URL is stable — no tunnels required.

---

## Vercel URL

`https://web-coral-seven-77.vercel.app`

---

## Schema change (`apps/web/server/db/schema.sql`)

Add `last_modified_date TIMESTAMPTZ` column to `cases` table:

```sql
ALTER TABLE cases ADD COLUMN IF NOT EXISTS
  last_modified_date TIMESTAMPTZ;
```

`last_modified_date` = when the Case was last modified in Salesforce.
`updated_at` = when Postgres last wrote the row.
These are intentionally separate: `updated_at` answers cache-staleness
questions; `last_modified_date` is the ordering guard for out-of-order
delivery. Using `updated_at` for the guard would be actively wrong — a
late-arriving retry would still get a fresh `now()` timestamp at write time,
which is precisely the failure mode the guard exists to prevent.

---

## Platform Event change

Add `Last_Modified_Date__c` (DateTime) field to `CaseStatusChanged__e`.
`CaseEventPublisher.cls` populates it from `Case.LastModifiedDate` at
publish time. This is the only source of truth for event ordering — the
Queueable trigger context cannot re-query the Case.

---

## `Sync_Failure__c` custom object

| Field | Type | Notes |
|---|---|---|
| `Case_Id__c` | Text(18) | Which Case failed |
| `Payload__c` | LongTextArea(1000) | Full JSON to replay on retry |
| `Error_Message__c` | Text(255) | HTTP status or exception message |
| `Failed_At__c` | DateTime | Original failure time |
| `Last_Retry_At__c` | DateTime | Most recent retry attempt |
| `Retry_Count__c` | Number(2,0) | Default 0; max 5 |
| `Resolved__c` | Checkbox | Default false; true on successful retry |

---

## `SyncConfig__mdt` Custom Metadata Type

Two fields:
- `Endpoint_URL__c` — Text(255)
- `Sync_Secret__c` — Text(255)

One record (`FieldServiceSync`):
- `Endpoint_URL__c` = `https://web-coral-seven-77.vercel.app/api/cases/sync`
- `Sync_Secret__c` = shared secret (also set as `SYNC_SECRET` Vercel env var)

---

## Remote Site Setting

Name: `FieldServiceNuxt`
URL: `https://web-coral-seven-77.vercel.app`
Active: true

---

## Salesforce Apex

### `CaseStatusChangedTrigger.trigger`

`after insert` on `CaseStatusChanged__e`. Enqueues one `CaseEventCallout`
passing `Trigger.new`. Thin — no logic in trigger body.

### `CaseEventCallout.cls` (Queueable, callout=true)

Receives `List<CaseStatusChanged__e>`. For each event:
1. Builds camelCase JSON payload — Queueable is explicitly responsible for
   mapping Apex `__c` field names to camelCase JSON keys:
   - `Case_Id__c` → `caseId`
   - `Case_Number__c` → `caseNumber`
   - `Subject__c` → `subject`
   - `Status__c` → `status`
   - `Assigned_Technician_Id__c` → `technicianId`
   - `Assigned_Technician_Name__c` → `technicianName`
   - `Scheduled_Date__c` → `scheduledDate`
   - `Location_Name__c` → `locationName`
   - `Latitude__c` → `latitude`
   - `Longitude__c` → `longitude`
   - `Last_Modified_Date__c` → `lastModifiedDate`
2. Reads `Endpoint_URL__c` and `Sync_Secret__c` from `SyncConfig__mdt`
3. POSTs JSON with `Content-Type: application/json` and
   `x-sync-secret: <secret>`
4. HTTP 200 → done
5. Non-200 or exception → insert `Sync_Failure__c` with full payload,
   error message, `Failed_At__c = now()`, `Retry_Count__c = 0`

### `CaseEventRetryScheduler.cls` (Schedulable)

Queries:
```apex
SELECT Id, Payload__c FROM Sync_Failure__c
WHERE Resolved__c = false AND Retry_Count__c < 5
```

For each record: re-POSTs stored `Payload__c` JSON verbatim (no Salesforce
re-query — the stored payload already contains `lastModifiedDate` from the
original Queueable, so the ordering guard is preserved on retry).
On HTTP 200: `Resolved__c = true`.
On failure: `Retry_Count__c++`, `Last_Retry_At__c = now()`.
Records at `Retry_Count__c = 5` are left unresolved for manual review.

---

## Nuxt webhook receiver (`server/api/cases/sync.post.ts`)

Validates `x-sync-secret` header → 401 if missing or wrong.

Upsert:
```sql
INSERT INTO cases (
  id, case_number, subject, status,
  technician_id, technician_name, scheduled_date,
  location_name, latitude, longitude,
  last_modified_date, updated_at
) VALUES (...)
ON CONFLICT (id) DO UPDATE SET
  status = EXCLUDED.status,
  technician_id = EXCLUDED.technician_id,
  technician_name = EXCLUDED.technician_name,
  scheduled_date = EXCLUDED.scheduled_date,
  location_name = EXCLUDED.location_name,
  latitude = EXCLUDED.latitude,
  longitude = EXCLUDED.longitude,
  last_modified_date = EXCLUDED.last_modified_date,
  updated_at = now()
WHERE cases.last_modified_date < EXCLUDED.last_modified_date
```

`ON CONFLICT (id)` matches the real deployed schema (`id TEXT PRIMARY KEY`).
Note: Phase 4 spec doc incorrectly referred to this as `case_id` — the real
column is `id`. This spec and all implementation code use `id`.

First inserts go through unconditionally — `WHERE` only applies to
`DO UPDATE`. `lastModifiedDate` is always present in the payload (never null —
`Case.LastModifiedDate` is always set in Salesforce, on both insert and update
paths).

Returns `{ ok: true }` on success. `console.error(err)` + HTTP 500 on DB
error (captured by Vercel function logs — not silent).

---

## Tests

### Nuxt (`sync.post.ts`)
- `syncsFirstInsertWithNoExistingRow` — upsert into empty table, assert row
  written with correct `last_modified_date` (not null)
- `updatesExistingRowWhenNewerEvent` — upsert with newer `lastModifiedDate`,
  assert row updated
- `ignoresStaleEventForExistingRow` — upsert with older `lastModifiedDate`,
  assert row unchanged
- `rejects401OnMissingOrWrongSecret`

### Apex
- `CaseEventCalloutTest` — mock HTTP callout via `Test.setMock`, assert
  correct JSON shape including all 11 camelCase field mappings, assert
  `Sync_Failure__c` inserted on non-200 response
- `CaseEventRetrySchedulerTest` — assert unresolved failures with
  `Retry_Count__c < 5` are re-enqueued, assert `Retry_Count__c` incremented
  on failure, assert `Resolved__c = true` on success

---

## Deployment order

1. Deploy `Last_Modified_Date__c` field on `CaseStatusChanged__e`
2. Deploy updated `CaseEventPublisher.cls`
3. Deploy `Sync_Failure__c` object + 7 fields
4. Deploy `SyncConfig__mdt` type + 2 fields + `FieldServiceSync` record
5. Deploy Remote Site Setting `FieldServiceNuxt`
6. Deploy `CaseEventCallout.cls` + `CaseStatusChangedTrigger.trigger` +
   `CaseEventRetryScheduler.cls` + test classes
7. Run Apex tests
8. Apply `last_modified_date` column migration to Neon
9. Deploy updated `schema.sql` + `sync.post.ts` to Vercel (`git push` triggers auto-deploy)
10. Set `SYNC_SECRET` Vercel env var via CLI
11. Smoke test: update a Case in Salesforce, confirm Neon row updates

---

## Out of scope

- Technician-facing UI (Phase 6)
- Salesforce auth in Nuxt (Phase 7)
- Dead-letter queue beyond `Sync_Failure__c`
- Asset trigger
- Mapbox token migration to Custom Setting
