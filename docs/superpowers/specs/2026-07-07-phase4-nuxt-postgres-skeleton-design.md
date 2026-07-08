# Phase 4 — Nuxt 3 + Neon Postgres Skeleton Design

**Date:** 2026-07-07
**Status:** Approved

## Goal

Stand up a self-contained Nuxt 3 app at `apps/web/` with a Neon Postgres
connection and a `cases` table. Provides the infrastructure foundation for
Phase 5 (webhook receiver) and Phase 6 (technician pages). No UI, no
Salesforce connection, no data in this phase.

---

## Monorepo approach

`apps/web/` is a standalone Nuxt 3 project with its own `package.json` and
`node_modules`. The Salesforce root (`package.json`, `eslint.config.js`,
Husky hooks) is untouched. No npm workspaces, no Turborepo.

---

## Repo structure

```
field-service-app/
  apps/
    web/
      server/
        db/
          client.ts             ← pg Pool singleton
          schema.sql            ← authoritative schema DDL
        api/
          health.get.ts         ← GET /api/health
      app.vue                   ← minimal root component
      nuxt.config.ts
      package.json
      .env                      ← gitignored
      .env.example              ← committed
  force-app/                    ← unchanged
```

---

## Database schema (`server/db/schema.sql`)

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

`id` is the Salesforce 18-char Case ID. Used as upsert conflict target in
Phase 5. `updated_at` is set by the application on each write.

---

## DB client (`server/db/client.ts`)

```ts
import pg from 'pg'

const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false }
})

export default pool
```

`ssl: { rejectUnauthorized: false }` is required for Neon. Singleton pool
imported directly by server routes.

---

## Health endpoint (`server/api/health.get.ts`)

```ts
import pool from '../db/client'

export default defineEventHandler(async () => {
  const result = await pool.query('SELECT 1 AS ok')
  return { status: 'ok', db: result.rows[0] }
})
```

`GET /api/health` → `{ "status": "ok", "db": { "ok": 1 } }` confirms Nuxt
is running and Neon is reachable.

---

## Environment

**`.env`** (gitignored):
```
DATABASE_URL=postgres://...neon.tech/neondb?sslmode=require
```

**`.env.example`** (committed):
```
DATABASE_URL=postgres://user:password@host/dbname?sslmode=require
```

**`nuxt.config.ts`**:
```ts
export default defineNuxtConfig({
  runtimeConfig: {
    databaseUrl: process.env.DATABASE_URL
  }
})
```

`DATABASE_URL` read via `process.env` in `db/client.ts` — loaded
automatically by Nuxt in dev from `.env`.

---

## Success criteria

1. `cd apps/web && npm run dev` starts without errors
2. `GET http://localhost:3000/api/health` returns `{ "status": "ok", "db": { "ok": 1 } }`
3. `cases` table exists in Neon (verified via Neon console or `psql`)
4. Salesforce root tooling unaffected (`npm test`, `npm run lint` still work)

---

## Out of scope

- Any UI pages (Phase 6)
- Webhook receiver (Phase 5)
- Authentication
- Salesforce API connection
- Production deployment
