-- Run from the folder containing the CSVs:  psql "$DATABASE_URL" -f sql/schema.sql -f sql/load.sql
\copy leads (lead_id, source, received_at, first_name, last_name, phone, email, consent_sms, consent_call, property_zip, lead_type, status) FROM 'leads.csv' WITH (FORMAT csv, HEADER true)
\copy outreach_attempts (attempt_id, lead_id, channel, attempted_at, status, agent_id) FROM 'outreach_log.csv' WITH (FORMAT csv, HEADER true)
SELECT 'leads' AS table_name, count(*) FROM leads
UNION ALL SELECT 'outreach_attempts', count(*) FROM outreach_attempts;
