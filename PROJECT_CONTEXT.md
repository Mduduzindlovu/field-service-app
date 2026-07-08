# Field Service Dispatch App — Project Context

## What this is
A portfolio project demonstrating Salesforce admin/LWC skills combined with a full-stack Next.js + Mapbox build. Scenario: an HVAC/equipment maintenance company dispatches technicians to service Cases against Assets at Locations.

Salesforce is the system of record. A Next.js app (not yet built) will eventually serve as the field technician's mobile interface, syncing via Platform Events into a Postgres cache to avoid hammering Salesforce API limits.

## Current status: Phase 2 complete (of 7)
- [x] Phase 1 — Salesforce data model
- [x] Phase 2 — Dispatcher console (map view of open Cases)
- [x] Phase 3 — Platform Events (Case/Asset change → event)
- [x] Phase 4 — Nuxt 3 + Postgres skeleton (Neon)
- [x] Phase 5 — Webhook receiver (Platform Event → Postgres sync)
- [ ] Phase 6 — Technician-facing Next.js pages + Mapbox
- [ ] Phase 7 — Write-back (technician completes job → Salesforce REST update)

## Org details
- Salesforce Developer Edition org, alias `fieldservice-dev` in `sf` CLI
- Username: `mduduzindlovu61.07bb472ea639@agentforce.com`
- **Lightning Web Security (LWS) is currently DISABLED** at Setup → Session Settings. This was a deliberate change made to get Mapbox working — see "Known issue" below before re-enabling it.

## Data model
| Object | Type | Key fields | Notes |
|---|---|---|---|
| `Locations__c` | Custom | `Address__c` (Text), `Coordinates__c` (Geolocation), `Account__c` (Lookup→Account) | Label is "Service Location" — **label was changed from "Location" to avoid collision with Salesforce's standard `Location` object**, which caused major debugging pain early on. Object API name stayed `Locations__c` (plural) despite the label change — this mismatch is intentional, don't "fix" it. |
| Asset (standard) | Standard | `Service_Location__c` (Lookup→`Locations__c`), `Health_Status__c` (Picklist: Operational/Needs Service/Down) | Note the field is `Service_Location__c`, NOT `Location__c` — named differently from Case's equivalent field due to how the collision got resolved. |
| Case (standard) | Standard | `Locations__c` (Lookup→`Locations__c`), `Assigned_Technician__c` (Lookup→User), `Scheduled_Date__c` (DateTime) | Note the field is literally named `Locations__c` (same name as the object it points to) — also a byproduct of the naming collision fix. |

**If extending this model:** always verify field API names and `referenceTo` with `sf sobject describe --sobject <Object> --target-org fieldservice-dev` before writing SOQL. Screenshots of Setup UI have been unreliable during this build (label/API name mismatches aren't visible in list views) — the CLI describe output is the source of truth.

## Apex classes
- **`CaseMapController.cls`** — `@AuraEnabled(cacheable=true)` method `getOpenCases()`, returns a flattened `CaseMapRecord` wrapper (caseId, caseNumber, subject, status, locationName, latitude, longitude, technicianName) for all non-Closed Cases with a Location set. This is the shared query logic.
- **`CaseMapVFController.cls`** — thin wrapper around `CaseMapController.getOpenCases()`, serializes to JSON for consumption by the Visualforce page (see below).

## Known issue: Mapbox GL JS cannot run in a standard LWC
**Do not attempt to move the map back into `caseMapConsole` (LWC) without reading this first.**

Mapbox GL JS requires a Web Worker (for vector tile parsing) and a full WebGL2 context. Both Salesforce LWC sandboxing models fail it:
- **Lightning Web Security (LWS)** — blocks Worker creation outright (`Cannot create Worker with ...`). Confirmed via direct testing, not theoretical.
- **Locker Service** (the fallback when LWS is disabled) — allows the Worker but returns a broken/proxied WebGL2 context, causing `Cannot read properties of undefined (reading 'RGBA8')` inside Mapbox's internal `Painter.setup`.

**Working solution implemented:** the map lives in a **Visualforce page** (`CaseMapPage.page`) with its own controller (`CaseMapVFController.cls`), embedded into the Lightning App Page via the standard Visualforce component in App Builder. Visualforce isn't wrapped by LWS/Locker, so Mapbox runs unrestricted there.

- `caseMapConsole` (LWC) still exists in the codebase from earlier attempts but is **not used** in the active page — safe to delete, or keep as a documented dead-end.
- The Next.js technician app (Phase 6) will use Mapbox GL JS normally — this constraint is Salesforce-LWC-specific and doesn't apply there.

## Static Resources
- **`mapboxgl`** — zip containing `mapbox-gl.js`, `mapbox-gl.css`, `mapbox-gl-csp.js`, `mapbox-gl-csp-worker.js` (v3.17.0). The CSP/worker files were needed for an earlier LWC attempt and are unused by the current Visualforce solution, but left in place in case of future LWC experiments. The Visualforce page uses the plain `mapbox-gl.js`/`mapbox-gl.css` files.

## Mapbox account
- Public token is currently hardcoded directly in `CaseMapPage.page` (`pk.eyJ1...`). **This should move to a Custom Setting or Custom Metadata Type before this is treated as anything beyond a personal portfolio demo** — it's a public token (safe to expose client-side by Mapbox's own design) but hardcoding is still sloppy practice worth cleaning up later.

## Test data
4 seeded records via Salesforce CLI bulk data import (`sf data import bulk`), Cape Town-area coordinates:
- Riverside Mall (Down)
- Harbor Warehouse (Needs Service)
- Pinebrook Offices (Working)
- Oakview School (Needs Service)

All linked to the same test User (Mduduzi Ndlovu) as `Assigned_Technician__c`.

## Local project structure
```
field-service-app/
  force-app/main/default/
    classes/
      CaseMapController.cls
      CaseMapVFController.cls
    lwc/
      caseMapConsole/        ← dead code, see "Known issue" above
    pages/
      CaseMapPage.page       ← active map implementation
```

## Next step (Phase 3)
Add a Platform Event definition and a trigger on Case (and likely Asset) that publishes it on status/assignment change. This event will eventually be consumed by a webhook receiver in the Next.js app (Phase 5) to keep a Postgres cache in sync without polling the Salesforce API.
