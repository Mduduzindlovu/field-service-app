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
