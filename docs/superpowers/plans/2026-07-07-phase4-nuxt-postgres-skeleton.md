# Phase 4 — Nuxt 3 + Neon Postgres Skeleton Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scaffold a Nuxt 3 app at `apps/web/` with a Neon Postgres connection, a `cases` table, and a `/api/health` endpoint that proves the connection works.

**Architecture:** `apps/web/` is a standalone Nuxt 3 project — no npm workspaces, no changes to the Salesforce root. A `pg` Pool singleton in `server/db/client.ts` is imported directly by server API routes. The `cases` table schema lives in `server/db/schema.sql` and is applied manually via `psql` or the Neon console.

**Tech Stack:** Nuxt 3, Node.js, `pg` (node-postgres), Neon hosted Postgres.

---

## File map

| File | Action | Purpose |
|---|---|---|
| `apps/web/package.json` | Create | Nuxt 3 app manifest |
| `apps/web/nuxt.config.ts` | Create | Nuxt config with runtimeConfig |
| `apps/web/app.vue` | Create | Minimal root component |
| `apps/web/.env.example` | Create | Documents required env vars |
| `apps/web/.gitignore` | Create | Ignores `.env`, `.nuxt`, `node_modules` |
| `apps/web/server/db/client.ts` | Create | `pg` Pool singleton |
| `apps/web/server/db/schema.sql` | Create | `cases` table DDL |
| `apps/web/server/api/health.get.ts` | Create | `GET /api/health` endpoint |

---

## Prerequisites (manual, before Task 1)

The implementer must do these manually before starting:

1. **Create a Neon account** at https://neon.tech (free tier)
2. **Create a new Neon project** — any name, region closest to you
3. **Copy the connection string** from the Neon dashboard (looks like `postgres://user:pass@ep-xxx.us-east-2.aws.neon.tech/neondb?sslmode=require`)
4. **Verify Node.js ≥ 18** is installed: `node --version`

---

## Task 1: Scaffold the Nuxt 3 app

**Files:**
- Create: `apps/web/package.json`
- Create: `apps/web/nuxt.config.ts`
- Create: `apps/web/app.vue`
- Create: `apps/web/.env.example`
- Create: `apps/web/.gitignore`

- [ ] **Step 1.1: Create the directory**

```bash
mkdir -p /Users/tftf/git/field-service-app/apps/web
```

- [ ] **Step 1.2: Create `apps/web/package.json`**

```json
{
  "name": "field-service-web",
  "private": true,
  "version": "0.1.0",
  "scripts": {
    "dev": "nuxt dev",
    "build": "nuxt build",
    "preview": "nuxt preview"
  },
  "dependencies": {
    "nuxt": "^3.13.0",
    "pg": "^8.13.0"
  },
  "devDependencies": {
    "@types/pg": "^8.11.10"
  }
}
```

- [ ] **Step 1.3: Create `apps/web/nuxt.config.ts`**

```ts
export default defineNuxtConfig({
  runtimeConfig: {
    databaseUrl: process.env.DATABASE_URL
  }
})
```

- [ ] **Step 1.4: Create `apps/web/app.vue`**

```vue
<template>
  <div>
    <h1>Field Service App</h1>
  </div>
</template>
```

- [ ] **Step 1.5: Create `apps/web/.env.example`**

```
DATABASE_URL=postgres://user:password@host/dbname?sslmode=require
```

- [ ] **Step 1.6: Create `apps/web/.gitignore`**

```
.env
.nuxt/
.output/
node_modules/
```

- [ ] **Step 1.7: Install dependencies**

```bash
cd /Users/tftf/git/field-service-app/apps/web && npm install
```

Expected: `node_modules/` created, no errors. May take 30-60 seconds.

- [ ] **Step 1.8: Verify Nuxt starts**

```bash
cd /Users/tftf/git/field-service-app/apps/web && npm run dev
```

Expected output includes:
```
Nuxt 3.x.x with Nitro
  ➜ Local:    http://localhost:3000/
```

Visit `http://localhost:3000` — should show "Field Service App". Stop the server with `Ctrl+C`.

- [ ] **Step 1.9: Verify Salesforce root tooling is unaffected**

```bash
cd /Users/tftf/git/field-service-app && npm run lint && npm test
```

Expected: lint and tests pass exactly as before (no change to Salesforce files).

- [ ] **Step 1.10: Commit**

```bash
cd /Users/tftf/git/field-service-app && git add apps/web/package.json apps/web/nuxt.config.ts apps/web/app.vue apps/web/.env.example apps/web/.gitignore
git commit -m "feat: scaffold Nuxt 3 app at apps/web"
```

If git is not available, skip and note it.

---

## Task 2: Database schema and connection

**Files:**
- Create: `apps/web/server/db/schema.sql`
- Create: `apps/web/server/db/client.ts`

- [ ] **Step 2.1: Create the directory**

```bash
mkdir -p /Users/tftf/git/field-service-app/apps/web/server/db
```

- [ ] **Step 2.2: Create `apps/web/server/db/schema.sql`**

```sql
CREATE TABLE IF NOT EXISTS cases (
  id               TEXT PRIMARY KEY,
  case_number      TEXT NOT NULL,
  subject          TEXT,
  status           TEXT NOT NULL,
  technician_id    TEXT,
  technician_name  TEXT,
  scheduled_date   TIMESTAMPTZ,
  location_name    TEXT,
  latitude         DOUBLE PRECISION,
  longitude        DOUBLE PRECISION,
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

- [ ] **Step 2.3: Apply the schema to Neon**

Option A — via `psql` (if installed):

```bash
psql "$DATABASE_URL" -f /Users/tftf/git/field-service-app/apps/web/server/db/schema.sql
```

Expected: `CREATE TABLE`

Option B — via Neon console:
- Open the Neon dashboard → SQL Editor
- Paste the contents of `schema.sql` and run it
- Expected: `CREATE TABLE` success message

Verify the table exists:

```bash
psql "$DATABASE_URL" -c "\dt"
```

Expected output includes `cases` in the table list.

- [ ] **Step 2.4: Create `apps/web/.env` with your Neon connection string**

Create `apps/web/.env` (this file is gitignored):

```
DATABASE_URL=postgres://your-actual-connection-string-from-neon?sslmode=require
```

Replace the value with the actual connection string from the Neon dashboard.

- [ ] **Step 2.5: Create `apps/web/server/db/client.ts`**

```ts
import pg from 'pg'

const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false }
})

export default pool
```

- [ ] **Step 2.6: Commit**

```bash
cd /Users/tftf/git/field-service-app && git add apps/web/server/db/schema.sql apps/web/server/db/client.ts
git commit -m "feat: add cases schema and pg pool client"
```

If git is not available, skip and note it.

---

## Task 3: Health endpoint and end-to-end verification

**Files:**
- Create: `apps/web/server/api/health.get.ts`

- [ ] **Step 3.1: Create the `server/api` directory**

```bash
mkdir -p /Users/tftf/git/field-service-app/apps/web/server/api
```

- [ ] **Step 3.2: Create `apps/web/server/api/health.get.ts`**

```ts
import pool from '../db/client'

export default defineEventHandler(async () => {
  const result = await pool.query('SELECT 1 AS ok')
  return { status: 'ok', db: result.rows[0] }
})
```

- [ ] **Step 3.3: Start dev server and verify the endpoint**

```bash
cd /Users/tftf/git/field-service-app/apps/web && npm run dev
```

In a second terminal:

```bash
curl http://localhost:3000/api/health
```

Expected response:

```json
{"status":"ok","db":{"ok":1}}
```

If the response is a 500 error, check:
1. `apps/web/.env` exists and contains a valid `DATABASE_URL`
2. The Neon project is active (free tier projects pause after inactivity — click "Resume" in the dashboard)
3. `ssl: { rejectUnauthorized: false }` is present in `client.ts`

Stop the server with `Ctrl+C`.

- [ ] **Step 3.4: Update `PROJECT_CONTEXT.md` to mark Phase 4 complete**

In `PROJECT_CONTEXT.md`, change:

```
- [ ] Phase 4 — Next.js + Postgres skeleton
```

to:

```
- [x] Phase 4 — Nuxt 3 + Postgres skeleton (Neon)
```

- [ ] **Step 3.5: Final commit**

```bash
cd /Users/tftf/git/field-service-app && git add apps/web/server/api/health.get.ts PROJECT_CONTEXT.md
git commit -m "feat: add health endpoint — Phase 4 complete"
```

If git is not available, skip and note it.
