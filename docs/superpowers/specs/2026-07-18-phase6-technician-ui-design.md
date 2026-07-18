# Phase 6 — Technician-Facing UI Design Spec

**Date:** 2026-07-18
**Status:** Approved

---

## Goal

Build a single technician-facing page in the existing Nuxt 3 app (`apps/web/`) that shows a filtered list of assigned open cases alongside a Mapbox GL JS map with interactive pins. Data comes from the Postgres cache populated in Phase 5.

---

## Architecture & Data Flow

**Approach:** SSR data fetch with client-side Mapbox init and client-side polling.

**Server API endpoint:** `GET /api/cases/index.get.ts`
- Accepts `technicianId` query param
- Queries Postgres `cases` table: `WHERE technician_id = $1 AND status != 'Closed'`
- Returns array of case objects
- If `technicianId` is missing, returns all non-closed cases (no filter — demo acceptable)
- Returns empty array (not an error) when no matches

**Page:** `pages/cases.vue`
- SSR: `useAsyncData` calls the API endpoint with `technicianId` from `useRoute().query`
- Hydrates sidebar list from initial SSR data
- On mount (client-side only): Mapbox GL JS initialises against a `<div>` and plots pins
- `setInterval` (30s) calls `$fetch` on the same endpoint client-side, merges result into reactive state, updates sidebar and map pins
- Technician ID read from `?technicianId=005xxx` query param

---

## Layout

Full-viewport split layout, no page scroll.

### Left nav rail (~60px, dark background)
- Icon-only vertical navigation — static placeholder icons for the demo
- Matches the professional look of the inspiration design

### Sidebar (~350px, white)
- Header: "Field Cases" + technician ID as subtitle
- Scrollable list of case cards
- Each card shows:
  - Case number (bold) + status badge (top-right, colour-coded)
  - Subject
  - Location name
  - Scheduled date (formatted, or "Not scheduled" if null)
  - Technician name
- Selected card: blue highlight border, scrolls into view on pin click
- Card click: map flies to pin, opens bottom overlay
- Empty state: "No cases available yet" message

### Status badge colours
| Status | Colour |
|--------|--------|
| New | Blue |
| Working | Yellow |
| Escalated | Red |
| Closed | Grey |

### Map (fills remaining space)
- Mapbox GL JS, client-side only (`if (process.client)`)
- Style: `mapbox://styles/mapbox/light-v11`
- Default centre: Cape Town (`[-33.9249, 18.4241]`), zoom 11
- On load: fits bounding box of all case coordinates (if any)
- Each case with lat/lon = a map pin marker
- Pin click: flies to pin, opens bottom overlay, highlights sidebar card
- Selected pin: distinct colour vs unselected

### Bottom map overlay
- Slides up when a pin or sidebar card is selected
- Shows full case detail: case number, subject, status, location name, scheduled date, technician name
- Dismissible (close button or click outside)

---

## Mapbox token

Hardcoded in `pages/cases.vue` for this phase (same pattern as `CaseMapPage.page`). Comment notes it should move to Nuxt runtime config before any non-demo use.

---

## Error Handling & Edge Cases

| Scenario | Behaviour |
|----------|-----------|
| Missing `technicianId` param | No filter — return all non-closed cases |
| DB error on SSR fetch | `useAsyncData` error state → "Unable to load cases" in sidebar; map renders empty |
| No cases for technician | Map centred on Cape Town default; sidebar shows "No cases available yet" |
| Case with null lat/lon | Excluded from map pins; still shown in sidebar list |
| 30s poll fetch fails | Silently ignored — existing data stays on screen, no error flash |

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `apps/web/pages/cases.vue` | Create | Main technician page (SSR + client Mapbox + poll) |
| `apps/web/server/api/cases/index.get.ts` | Create | `GET /api/cases?technicianId=xxx` → Postgres query |
| `apps/web/app.vue` | Modify | Add nav rail shell around `<NuxtPage />` |
| `apps/web/nuxt.config.ts` | Modify | Enable `pages: true` |
| `apps/web/package.json` | Modify | Add `mapbox-gl` npm dependency |

No new DB migrations required — existing `cases` table has all needed columns.

---

## Success Criteria

- `GET /api/cases?technicianId=xxx` returns correct filtered rows from Postgres
- Page loads with SSR-rendered sidebar list
- Mapbox map renders with pins for cases that have coordinates
- Clicking a pin highlights the sidebar card and shows the bottom overlay
- Clicking a sidebar card flies the map to that pin and shows the bottom overlay
- 30s poll updates the sidebar and map without a full page reload
- Empty state renders correctly (map + "No cases available yet")
- No crashes when lat/lon is null on a case
