import pool from '../db/client'

export default defineEventHandler(async () => {
  const result = await pool.query('SELECT 1 AS ok')
  return { status: 'ok', db: result.rows[0] }
})
