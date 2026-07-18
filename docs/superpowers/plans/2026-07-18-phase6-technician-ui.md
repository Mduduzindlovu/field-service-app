# Phase 6 — Technician UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a single technician-facing page in the Nuxt 3 app showing a filtered list of assigned open cases alongside a Mapbox GL JS map with interactive pins, sourced from the Postgres cache.

**Architecture:** SSR `useAsyncData` fetches cases from a new `GET /api/cases` endpoint on first load. Client-side Mapbox GL JS initialises on mount and plots pins. A 30-second `setInterval` re-fetches and merges updates into reactive state, keeping sidebar and map in sync without a full reload. Layout: fixed left nav rail (~60px dark) + white sidebar (~350px) + map filling the rest.

**Tech Stack:** Nuxt 3, Vue 3 Composition API, Mapbox GL JS (npm), `pg` (node-postgres), Neon Postgres, Vercel.

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `apps/web/server/api/cases/index.get.ts` | Create | `GET /api/cases?technicianId=xxx` — queries Postgres, returns case array |
| `apps/web/pages/cases.vue` | Create | Technician page — SSR data, nav rail, sidebar, Mapbox map, bottom overlay |
| `apps/web/app.vue` | Modify | Wrap with `<NuxtPage />` so the router works |
| `apps/web/nuxt.config.ts` | Modify | No change needed — Nuxt auto-detects `pages/` directory |
| `apps/web/package.json` | Modify | Add `mapbox-gl` and `@types/mapbox-gl` dependencies |

---

## Task 1: Install `mapbox-gl` dependency

**Files:**
- Modify: `apps/web/package.json`

- [ ] **Step 1.1: Install the package**

```bash
cd apps/web && npm install mapbox-gl && npm install --save-dev @types/mapbox-gl
```

Expected: `package.json` now lists `"mapbox-gl"` in `dependencies` and `"@types/mapbox-gl"` in `devDependencies`.

- [ ] **Step 1.2: Verify the import resolves**

```bash
node -e "require('mapbox-gl'); console.log('ok')"
```

Expected: `ok` (no error). If it errors, run `npm install` again.

- [ ] **Step 1.3: Commit**

```bash
cd /Users/tftf/git/field-service-app
git add apps/web/package.json apps/web/package-lock.json
git commit -m "chore: add mapbox-gl dependency to Nuxt app"
```

---

## Task 2: `GET /api/cases` server endpoint

**Files:**
- Create: `apps/web/server/api/cases/index.get.ts`

Note: `apps/web/server/api/cases/` already exists (contains `sync.post.ts`). Just add the new file.

- [ ] **Step 2.1: Create the endpoint**

Create `apps/web/server/api/cases/index.get.ts`:

```ts
import pool from '../../db/client'

export default defineEventHandler(async (event) => {
  const query = getQuery(event)
  const technicianId = query.technicianId as string | undefined

  try {
    let result
    if (technicianId) {
      result = await pool.query(
        `SELECT id, case_number, subject, status,
                technician_id, technician_name, scheduled_date,
                location_name, latitude, longitude
         FROM cases
         WHERE technician_id = $1
           AND status != 'Closed'
         ORDER BY scheduled_date ASC NULLS LAST`,
        [technicianId]
      )
    } else {
      result = await pool.query(
        `SELECT id, case_number, subject, status,
                technician_id, technician_name, scheduled_date,
                location_name, latitude, longitude
         FROM cases
         WHERE status != 'Closed'
         ORDER BY scheduled_date ASC NULLS LAST`
      )
    }

    return result.rows.map((row) => ({
      id: row.id,
      caseNumber: row.case_number,
      subject: row.subject,
      status: row.status,
      technicianId: row.technician_id,
      technicianName: row.technician_name,
      scheduledDate: row.scheduled_date ?? null,
      locationName: row.location_name,
      latitude: row.latitude ?? null,
      longitude: row.longitude ?? null,
    }))
  } catch (err) {
    console.error('[cases/index.get] DB error:', err)
    throw createError({ statusCode: 500, message: 'Database error' })
  }
})
```

- [ ] **Step 2.2: Start dev server and test the endpoint**

```bash
cd apps/web && npm run dev
```

In a second terminal — test without filter:

```bash
curl -s "http://localhost:3000/api/cases" | head -c 500
```

Expected: a JSON array (may be empty `[]` if no non-Closed cases in DB, or array of case objects).

Test with a technician ID (use the real ID from your DB — check with):

```bash
export PATH="/usr/local/opt/libpq/bin:$PATH"
psql "$NEON_DATABASE_URL" -c "SELECT DISTINCT technician_id, technician_name FROM cases LIMIT 5;"
```

Then:

```bash
curl -s "http://localhost:3000/api/cases?technicianId=<ID_FROM_ABOVE>" | head -c 500
```

Expected: JSON array filtered to that technician's non-Closed cases.

Test DB error resilience — stop dev server; it's sufficient to verify the query runs.

- [ ] **Step 2.3: Commit**

```bash
cd /Users/tftf/git/field-service-app
git add apps/web/server/api/cases/index.get.ts
git commit -m "feat: add GET /api/cases endpoint with technicianId filter"
```

---

## Task 3: Update `app.vue` to support routing

**Files:**
- Modify: `apps/web/app.vue`

Currently `app.vue` has a hardcoded `<h1>`. It needs to render `<NuxtPage />` so the `pages/` router works.

- [ ] **Step 3.1: Replace `app.vue`**

Replace the entire file `apps/web/app.vue` with:

```vue
<template>
  <NuxtPage />
</template>
```

- [ ] **Step 3.2: Verify routing works**

With dev server running (`npm run dev` in `apps/web`):

```bash
curl -s http://localhost:3000/ | head -c 200
```

Expected: some HTML (even a 404 page is fine — it means the router is active). The old `<h1>Field Service App</h1>` should no longer appear at `/`.

- [ ] **Step 3.3: Commit**

```bash
cd /Users/tftf/git/field-service-app
git add apps/web/app.vue
git commit -m "feat: replace app.vue stub with NuxtPage router shell"
```

---

## Task 4: `pages/cases.vue` — skeleton with SSR data fetch and sidebar

**Files:**
- Create: `apps/web/pages/cases.vue`

Build incrementally: sidebar first (no map), then add map in Task 5.

- [ ] **Step 4.1: Create `pages/cases.vue` with SSR fetch and sidebar**

Create `apps/web/pages/cases.vue`:

```vue
<script setup lang="ts">
interface Case {
  id: string
  caseNumber: string
  subject: string | null
  status: string
  technicianId: string | null
  technicianName: string | null
  scheduledDate: string | null
  locationName: string | null
  latitude: number | null
  longitude: number | null
}

const route = useRoute()
const technicianId = computed(() => route.query.technicianId as string | undefined)

const { data: cases, error, refresh } = await useAsyncData<Case[]>(
  'cases',
  () => $fetch('/api/cases', {
    query: technicianId.value ? { technicianId: technicianId.value } : {}
  }),
  { default: () => [] }
)

// 30-second polling
onMounted(() => {
  const interval = setInterval(async () => {
    try {
      await refresh()
    } catch {
      // silently ignore poll failures — existing data stays on screen
    }
  }, 30_000)
  onUnmounted(() => clearInterval(interval))
})

const selectedCaseId = ref<string | null>(null)

function selectCase(id: string) {
  selectedCaseId.value = id
}

function dismissOverlay() {
  selectedCaseId.value = null
}

const selectedCase = computed(() =>
  cases.value?.find((c) => c.id === selectedCaseId.value) ?? null
)

function statusBadgeClass(status: string): string {
  const map: Record<string, string> = {
    New: 'badge-new',
    Working: 'badge-working',
    Escalated: 'badge-escalated',
    Closed: 'badge-closed',
  }
  return map[status] ?? 'badge-default'
}

function formatDate(d: string | null): string {
  if (!d) return 'Not scheduled'
  return new Date(d).toLocaleString('en-ZA', {
    dateStyle: 'medium',
    timeStyle: 'short',
  })
}
</script>

<template>
  <div class="app-shell">
    <!-- Nav rail -->
    <nav class="nav-rail">
      <div class="nav-logo">
        <svg width="24" height="24" viewBox="0 0 24 24" fill="none">
          <rect width="24" height="24" rx="4" fill="#4F6AF5" />
          <path d="M6 12h12M12 6v12" stroke="white" stroke-width="2" stroke-linecap="round" />
        </svg>
      </div>
      <div class="nav-icons">
        <button class="nav-btn nav-btn--active" title="Cases">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none">
            <path d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" />
          </svg>
        </button>
        <button class="nav-btn" title="Map">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none">
            <path d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-1.447-.894L15 9m0 8V9M9 7l6 2" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" />
          </svg>
        </button>
        <button class="nav-btn" title="Settings">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none">
            <path d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" stroke="currentColor" stroke-width="1.5" />
            <path d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" stroke="currentColor" stroke-width="1.5" />
          </svg>
        </button>
      </div>
    </nav>

    <!-- Sidebar -->
    <aside class="sidebar">
      <div class="sidebar-header">
        <h1 class="sidebar-title">Field Cases</h1>
        <p v-if="technicianId" class="sidebar-subtitle">{{ technicianId }}</p>
        <p v-else class="sidebar-subtitle">All technicians</p>
      </div>

      <div v-if="error" class="sidebar-empty">
        Unable to load cases
      </div>

      <div v-else-if="!cases || cases.length === 0" class="sidebar-empty">
        No cases available yet
      </div>

      <ul v-else class="case-list">
        <li
          v-for="c in cases"
          :key="c.id"
          class="case-card"
          :class="{ 'case-card--selected': c.id === selectedCaseId }"
          @click="selectCase(c.id)"
        >
          <div class="case-card-header">
            <span class="case-number">{{ c.caseNumber }}</span>
            <span class="badge" :class="statusBadgeClass(c.status)">{{ c.status }}</span>
          </div>
          <p class="case-subject">{{ c.subject ?? '(No subject)' }}</p>
          <p class="case-meta">{{ c.locationName ?? 'Unknown location' }}</p>
          <p class="case-meta">{{ formatDate(c.scheduledDate) }}</p>
          <p class="case-meta case-meta--technician">{{ c.technicianName ?? '—' }}</p>
        </li>
      </ul>
    </aside>

    <!-- Map area -->
    <main class="map-area">
      <div id="map" class="map-container" />

      <!-- Bottom overlay -->
      <div v-if="selectedCase" class="map-overlay">
        <div class="map-overlay-inner">
          <button class="overlay-close" @click="dismissOverlay">✕</button>
          <div class="overlay-header">
            <span class="case-number">{{ selectedCase.caseNumber }}</span>
            <span class="badge" :class="statusBadgeClass(selectedCase.status)">{{ selectedCase.status }}</span>
          </div>
          <p class="overlay-subject">{{ selectedCase.subject ?? '(No subject)' }}</p>
          <p class="overlay-meta">{{ selectedCase.locationName ?? 'Unknown location' }}</p>
          <p class="overlay-meta">{{ formatDate(selectedCase.scheduledDate) }}</p>
          <p class="overlay-meta">{{ selectedCase.technicianName ?? '—' }}</p>
        </div>
      </div>
    </main>
  </div>
</template>

<style scoped>
/* Layout */
.app-shell {
  display: flex;
  height: 100vh;
  overflow: hidden;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
}

/* Nav rail */
.nav-rail {
  width: 60px;
  background: #1a1d23;
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 16px 0;
  gap: 8px;
  flex-shrink: 0;
}
.nav-logo {
  margin-bottom: 16px;
}
.nav-icons {
  display: flex;
  flex-direction: column;
  gap: 4px;
  width: 100%;
  align-items: center;
}
.nav-btn {
  width: 40px;
  height: 40px;
  border-radius: 8px;
  border: none;
  background: transparent;
  color: #8b95a3;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: background 0.15s, color 0.15s;
}
.nav-btn:hover {
  background: #2a2d35;
  color: #e2e8f0;
}
.nav-btn--active {
  background: #2a2d35;
  color: #4F6AF5;
}

/* Sidebar */
.sidebar {
  width: 350px;
  flex-shrink: 0;
  background: #ffffff;
  border-right: 1px solid #e8ecf0;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}
.sidebar-header {
  padding: 20px 20px 12px;
  border-bottom: 1px solid #e8ecf0;
}
.sidebar-title {
  font-size: 20px;
  font-weight: 700;
  color: #1a1d23;
  margin: 0 0 2px;
}
.sidebar-subtitle {
  font-size: 12px;
  color: #8b95a3;
  margin: 0;
  font-family: monospace;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.sidebar-empty {
  padding: 40px 20px;
  color: #8b95a3;
  font-size: 14px;
  text-align: center;
}

/* Case list */
.case-list {
  list-style: none;
  margin: 0;
  padding: 8px 0;
  overflow-y: auto;
  flex: 1;
}
.case-card {
  padding: 14px 20px;
  border-bottom: 1px solid #f0f2f5;
  cursor: pointer;
  transition: background 0.1s;
}
.case-card:hover {
  background: #f8f9fb;
}
.case-card--selected {
  border-left: 3px solid #4F6AF5;
  background: #f0f3ff;
}
.case-card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 4px;
}
.case-number {
  font-weight: 700;
  font-size: 14px;
  color: #1a1d23;
}
.case-subject {
  font-size: 13px;
  color: #3d4452;
  margin: 0 0 4px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.case-meta {
  font-size: 12px;
  color: #8b95a3;
  margin: 0 0 2px;
}
.case-meta--technician {
  margin-top: 4px;
  font-style: italic;
}

/* Badges */
.badge {
  font-size: 10px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  padding: 2px 8px;
  border-radius: 12px;
}
.badge-new { background: #dbeafe; color: #1d4ed8; }
.badge-working { background: #fef3c7; color: #b45309; }
.badge-escalated { background: #fee2e2; color: #dc2626; }
.badge-closed { background: #f1f5f9; color: #64748b; }
.badge-default { background: #f1f5f9; color: #64748b; }

/* Map area */
.map-area {
  flex: 1;
  position: relative;
  overflow: hidden;
}
.map-container {
  width: 100%;
  height: 100%;
}

/* Bottom overlay */
.map-overlay {
  position: absolute;
  bottom: 0;
  left: 0;
  right: 0;
  z-index: 10;
  padding: 0 16px 16px;
  pointer-events: none;
}
.map-overlay-inner {
  background: #ffffff;
  border-radius: 12px 12px 8px 8px;
  box-shadow: 0 -2px 20px rgba(0,0,0,0.15);
  padding: 16px 20px;
  position: relative;
  pointer-events: all;
  max-width: 500px;
}
.overlay-close {
  position: absolute;
  top: 12px;
  right: 12px;
  background: none;
  border: none;
  font-size: 16px;
  color: #8b95a3;
  cursor: pointer;
  line-height: 1;
  padding: 4px;
}
.overlay-close:hover { color: #1a1d23; }
.overlay-header {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 6px;
}
.overlay-subject {
  font-size: 15px;
  font-weight: 600;
  color: #1a1d23;
  margin: 0 0 6px;
}
.overlay-meta {
  font-size: 13px;
  color: #8b95a3;
  margin: 0 0 2px;
}

/* Reset global margin/padding */
:global(body) {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}
</style>
```

- [ ] **Step 4.2: Verify sidebar renders**

With dev server running in `apps/web`:

```bash
curl -s "http://localhost:3000/cases" | grep "Field Cases"
```

Expected: the string `Field Cases` appears in the HTML (SSR-rendered).

Also open `http://localhost:3000/cases?technicianId=<your_technician_id>` in a browser and confirm:
- Nav rail visible (dark left strip)
- Sidebar shows "Field Cases" header + case cards (or "No cases available yet" if DB is empty)
- No JS errors in browser console

- [ ] **Step 4.3: Commit**

```bash
cd /Users/tftf/git/field-service-app
git add apps/web/pages/cases.vue apps/web/app.vue
git commit -m "feat: add cases page with SSR sidebar and nav rail"
```

---

## Task 5: Add Mapbox GL JS map with pins and sync

**Files:**
- Modify: `apps/web/pages/cases.vue`

Add the Mapbox initialisation block. Mapbox must only run client-side.

- [ ] **Step 5.1: Add Mapbox imports and map initialisation to `cases.vue`**

Add the following to the `<script setup>` block in `apps/web/pages/cases.vue`, immediately after the `dismissOverlay` function:

```ts
// ── Mapbox ────────────────────────────────────────────────────────────────────
// Replace with your real public Mapbox token (starts with pk.)
// Find it at https://account.mapbox.com → Tokens
// TODO: move to Nuxt runtime config before any non-demo use
const MAPBOX_TOKEN = 'pk.YOUR_MAPBOX_PUBLIC_TOKEN_HERE'

const mapRef = ref<HTMLDivElement | null>(null)
let mapInstance: import('mapbox-gl').Map | null = null
const markers: Map<string, import('mapbox-gl').Marker> = new Map()

const CAPE_TOWN: [number, number] = [18.4241, -33.9249]

function getCasesWithCoords(caseList: Case[]) {
  return caseList.filter((c) => c.latitude !== null && c.longitude !== null)
}

function initMap(caseList: Case[]) {
  if (!mapRef.value) return

  // Dynamic import — client-side only
  import('mapbox-gl').then((mapboxgl) => {
    mapboxgl.default.accessToken = MAPBOX_TOKEN

    mapInstance = new mapboxgl.default.Map({
      container: mapRef.value!,
      style: 'mapbox://styles/mapbox/light-v11',
      center: CAPE_TOWN,
      zoom: 11,
    })

    mapInstance.on('load', () => {
      plotPins(caseList, mapboxgl.default)
      fitToCases(caseList)
    })
  })
}

function plotPins(caseList: Case[], mapboxgl: typeof import('mapbox-gl').default) {
  if (!mapInstance) return

  // Remove stale markers
  const newIds = new Set(caseList.map((c) => c.id))
  for (const [id, marker] of markers.entries()) {
    if (!newIds.has(id)) {
      marker.remove()
      markers.delete(id)
    }
  }

  for (const c of caseList) {
    if (c.latitude === null || c.longitude === null) continue

    if (markers.has(c.id)) {
      // Update position in case it changed
      markers.get(c.id)!.setLngLat([c.longitude, c.latitude])
      continue
    }

    const el = document.createElement('div')
    el.className = 'map-pin'
    el.style.cssText = `
      width: 14px; height: 14px; border-radius: 50%;
      background: #4F6AF5; border: 2px solid #fff;
      box-shadow: 0 1px 4px rgba(0,0,0,0.3); cursor: pointer;
    `

    const marker = new mapboxgl.Marker({ element: el })
      .setLngLat([c.longitude, c.latitude])
      .addTo(mapInstance!)

    el.addEventListener('click', () => {
      selectCase(c.id)
      scrollSidebarToCase(c.id)
    })

    markers.set(c.id, marker)
  }

  // Highlight selected
  highlightSelectedPin()
}

function highlightSelectedPin() {
  for (const [id, marker] of markers.entries()) {
    const el = marker.getElement()
    if (el) {
      el.style.background = id === selectedCaseId.value ? '#e53e3e' : '#4F6AF5'
      el.style.transform = id === selectedCaseId.value ? 'scale(1.4)' : 'scale(1)'
    }
  }
}

function fitToCases(caseList: Case[]) {
  if (!mapInstance) return
  const withCoords = getCasesWithCoords(caseList)
  if (withCoords.length === 0) return

  if (withCoords.length === 1) {
    mapInstance.flyTo({ center: [withCoords[0].longitude!, withCoords[0].latitude!], zoom: 13 })
    return
  }

  import('mapbox-gl').then((mapboxgl) => {
    const bounds = new mapboxgl.default.LngLatBounds()
    for (const c of withCoords) {
      bounds.extend([c.longitude!, c.latitude!])
    }
    mapInstance!.fitBounds(bounds, { padding: 60 })
  })
}

function flyToCase(c: Case) {
  if (!mapInstance || c.latitude === null || c.longitude === null) return
  mapInstance.flyTo({ center: [c.longitude, c.latitude], zoom: 14, duration: 800 })
}

function scrollSidebarToCase(id: string) {
  nextTick(() => {
    const el = document.querySelector(`[data-case-id="${id}"]`)
    if (el) el.scrollIntoView({ behavior: 'smooth', block: 'nearest' })
  })
}

// Re-plot pins when cases update from poll
watch(cases, (newCases) => {
  if (!mapInstance || !newCases) return
  import('mapbox-gl').then((mapboxgl) => {
    plotPins(newCases, mapboxgl.default)
  })
})

// Highlight pin when selection changes
watch(selectedCaseId, () => {
  highlightSelectedPin()
  if (selectedCaseId.value) {
    const c = cases.value?.find((x) => x.id === selectedCaseId.value)
    if (c) flyToCase(c)
  }
})

onMounted(() => {
  if (cases.value) initMap(cases.value)
})

onUnmounted(() => {
  mapInstance?.remove()
  mapInstance = null
  markers.clear()
})
```

- [ ] **Step 5.2: Wire `data-case-id` attributes onto sidebar cards**

In the `<template>` section of `cases.vue`, find the `<li>` tag for case cards and add the `data-case-id` attribute:

Replace:
```vue
<li
  v-for="c in cases"
  :key="c.id"
  class="case-card"
  :class="{ 'case-card--selected': c.id === selectedCaseId }"
  @click="selectCase(c.id)"
>
```

With:
```vue
<li
  v-for="c in cases"
  :key="c.id"
  :data-case-id="c.id"
  class="case-card"
  :class="{ 'case-card--selected': c.id === selectedCaseId }"
  @click="selectCase(c.id); flyToCase(c)"
>
```

- [ ] **Step 5.3: Wire the map container ref**

In the `<template>`, find:
```vue
<div id="map" class="map-container" />
```

Replace with:
```vue
<div ref="mapRef" id="map" class="map-container" />
```

- [ ] **Step 5.4: Verify map renders**

With dev server running, open `http://localhost:3000/cases?technicianId=<your_id>` in a browser:
- Map should render in the right panel (light-v11 style)
- Case pins (blue dots) should appear at case coordinates
- Clicking a pin should highlight the matching sidebar card and show the bottom overlay
- Clicking a sidebar card should fly the map to that pin and show the bottom overlay
- Clicking ✕ on the overlay should dismiss it

Check browser console for any errors.

- [ ] **Step 5.5: Commit**

```bash
cd /Users/tftf/git/field-service-app
git add apps/web/pages/cases.vue
git commit -m "feat: add Mapbox map with pins, selection sync, and bottom overlay"
```

---

## Task 6: Deploy to Vercel and mark Phase 6 complete

- [ ] **Step 6.1: Push to trigger Vercel auto-deploy**

```bash
cd /Users/tftf/git/field-service-app
git push
```

Wait ~60 seconds then verify prod:

```bash
curl -s "https://web-coral-seven-77.vercel.app/api/cases" | head -c 300
```

Expected: JSON array from the production DB.

Also open `https://web-coral-seven-77.vercel.app/cases?technicianId=<your_id>` in a browser and confirm the full page works in production.

- [ ] **Step 6.2: Mark Phase 6 complete in `PROJECT_CONTEXT.md`**

In `PROJECT_CONTEXT.md`, change:
```
- [ ] Phase 6 — Technician-facing Next.js pages + Mapbox
```
to:
```
- [x] Phase 6 — Technician-facing Next.js pages + Mapbox
```

- [ ] **Step 6.3: Final commit**

```bash
cd /Users/tftf/git/field-service-app
git add PROJECT_CONTEXT.md
git commit -m "docs: mark Phase 6 complete"
git push
```
