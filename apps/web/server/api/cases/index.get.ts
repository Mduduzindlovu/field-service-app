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
