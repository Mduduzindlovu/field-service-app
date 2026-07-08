CREATE TABLE IF NOT EXISTS cases (
  id                 TEXT PRIMARY KEY,
  case_number        TEXT NOT NULL,
  subject            TEXT,
  status             TEXT NOT NULL,
  technician_id      TEXT,
  technician_name    TEXT,
  scheduled_date     TIMESTAMPTZ,
  location_name      TEXT,
  latitude           DOUBLE PRECISION,
  longitude          DOUBLE PRECISION,
  last_modified_date TIMESTAMPTZ,
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
