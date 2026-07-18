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
  () => `cases-${technicianId.value ?? 'all'}`,
  () => $fetch('/api/cases', {
    query: technicianId.value ? { technicianId: technicianId.value } : {}
  }),
  { default: () => [], watch: [technicianId] }
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

      <div v-else-if="cases.length === 0" class="sidebar-empty">
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
          <button class="overlay-close" aria-label="Dismiss" @click="dismissOverlay">✕</button>
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
