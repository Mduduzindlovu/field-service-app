# AGENTS.md

Compact ramp-up guide for AI agents working in this repo.

## Project overview

Portfolio Salesforce DX project. Scenario: HVAC/equipment maintenance company dispatching technicians to service Cases against Assets at Locations. Salesforce is the system of record. A Next.js field-technician interface (Phases 3-7) is planned but not yet built.

See `PROJECT_CONTEXT.md` for full phase breakdown.

## Org

- Default alias: `fieldservice-dev`
- Username: `mduduzindlovu61.07bb472ea639@agentforce.com`
- Type: Developer Edition
- Source API version: `66.0`

## Key commands

```bash
# Deploy / retrieve
sf project deploy start --target-org fieldservice-dev
sf project retrieve start --target-org fieldservice-dev

# Lint (LWC + Aura JS only)
npm run lint

# Unit tests (LWC Jest)
npm test                      # or: npm run test:unit
npm run test:unit:watch
npm run test:unit:coverage

# Format (writes in place)
npm run prettier

# Format check (CI-safe, no writes)
npm run prettier:verify
```

Describe an object's fields when SOQL or metadata field names are uncertain:
```bash
sf sobject describe --sobject <ObjectApiName> --target-org fieldservice-dev
```

## Pre-commit hooks

Husky runs `lint-staged` automatically on every commit:
1. `prettier --write` on all source files
2. `eslint` on all LWC/Aura JS
3. `sfdx-lwc-jest --bail --findRelatedTests --passWithNoTests` on changed LWC files

Commits fail on ESLint errors. Format violations are auto-fixed before the lint check.

## Architecture: active vs dead code

| Path | Status | Notes |
|------|--------|-------|
| `force-app/main/default/pages/CaseMapPage.page` | **Active** | Real map UI; loaded via VF controller |
| `force-app/main/default/classes/CaseMapVFController.cls` | **Active** | Thin wrapper; serializes case JSON for the VF page |
| `force-app/main/default/classes/CaseMapController.cls` | **Active** | `@AuraEnabled` Apex; queries Cases with location data |
| `force-app/main/default/triggers/CaseEventTrigger.trigger` | **Active** | Phase 3: fires `after insert, after update` on Case |
| `force-app/main/default/classes/CaseEventPublisher.cls` | **Active** | Phase 3: publishes `CaseStatusChanged__e` events |
| `force-app/main/default/lwc/caseMapConsole/` | **Dead** | Failed LWC attempt; stub test only; safe to delete |

## Apex testing gotcha: Platform Event assertions

`Test.getEventBus().getPublishedMessages()` **does not exist** in this org's API version — it will cause a compile error. Use the `@TestVisible static List<SObject> publishedEvents` accumulator pattern instead (see `CaseEventPublisher.cls` for the reference implementation).

## Why Mapbox lives in Visualforce, not LWC

Both LWS (Lightning Web Security) and Locker Service break Mapbox GL JS. LWS is **deliberately disabled** at Setup → Session Settings → "Use Lightning Web Security for Lightning web components" = OFF. Do not re-enable — it will break the map. This is a known, intentional trade-off.

The active map is the Visualforce page, not the LWC component.

## Data model gotchas

Field API names differ from labels in confusing ways. Always verify with `sf sobject describe` rather than guessing from labels.

| Field / Object | API name | Common mistake |
|----------------|----------|----------------|
| Service Location object | `Locations__c` | Plural label mismatch; do NOT rename |
| Case → location lookup | `Locations__c` | Same name as the object — intentional |
| Asset → location lookup | `Service_Location__c` | NOT `Location__c` or `Locations__c` |
| Geolocation latitude | `Coordinates__Latitude__s` | Sub-field on `Locations__c` object |
| Geolocation longitude | `Coordinates__Longitude__s` | Sub-field on `Locations__c` object |

The SOQL in `CaseMapController.cls` is the authoritative reference for these field paths.

## Static resources

The Mapbox GL JS v3.17.0 bundle is deployed to the org as a static resource named `mapboxgl` (zip). It is **not tracked** in `force-app/main/default/staticresources/`. To update it, retrieve the resource first before editing:
```bash
sf project retrieve start --metadata StaticResource:mapboxgl --target-org fieldservice-dev
```

The mapbox-gl files at the repo root (`mapbox-gl.js`, etc.) are local copies; the deployed version lives in the org's static resources.

## Hardcoded Mapbox token

A public Mapbox token is hardcoded in both `CaseMapPage.page` and `caseMapConsole.js`. Move to a Custom Setting before any production or public use.

## Nuxt 3 app (`apps/web/`)

Standalone Nuxt 3 project — no npm workspaces, no Turborepo. Run from its own directory:

```bash
cd apps/web && npm run dev    # start dev server on :3000
```

- DB client: `apps/web/server/db/client.ts` — `pg` Pool singleton, `ssl: { rejectUnauthorized: false }` required for Neon
- Schema: `apps/web/server/db/schema.sql` — authoritative DDL; apply via `psql "$DATABASE_URL" -f schema.sql`
- Health check: `GET http://localhost:3000/api/health` → `{"status":"ok","db":{"ok":1}}`
- Env: `apps/web/.env` (gitignored) must contain `DATABASE_URL=<neon-connection-string>`
- Neon project: `ep-aged-unit-adqbfgfu.c-2.us-east-1.aws.neon.tech` / database `neondb`
- `psql` available at `/usr/local/opt/libpq/bin/psql` (installed via `brew install libpq`)

## No TypeScript, no CI, no .env (Salesforce root)

- All Salesforce JS is plain ES modules; no `tsconfig` at repo root.
- No `.github/workflows/` — no automated CI.
- Prettier config: no trailing commas; LWC HTML uses `lwc` parser.
