WITH policy AS (
    SELECT 15   AS sla_minutes,        -- first touch within 15 minutes
           20   AS sms_due_minutes,    -- text follows the first call
           360  AS call2_due_minutes,  -- second call follows receipt
           8    AS quiet_start,
           21   AS quiet_end
),
lead_tz AS (
    SELECT l.*,
           CASE l.property_zip
               WHEN '85032' THEN 'America/Phoenix'
               WHEN '89108' THEN 'America/Los_Angeles'
               WHEN '28269' THEN 'America/New_York' WHEN '30318' THEN 'America/New_York'
               WHEN '32801' THEN 'America/New_York' WHEN '43215' THEN 'America/New_York'
               ELSE 'America/Chicago'
           END AS lead_timezone
    FROM leads l
),
att AS (
    SELECT o.*, l.consent_sms, l.lead_timezone,
           o.status LIKE 'failed%' AS is_failed,
           min(o.attempted_at) FILTER (WHERE o.status = 'completed') OVER (PARTITION BY o.lead_id) AS first_connect_at,
           extract(hour FROM (o.attempted_at AT TIME ZONE 'America/Chicago') AT TIME ZONE l.lead_timezone) AS local_hour
    FROM outreach_attempts o JOIN lead_tz l USING (lead_id)
),
agg AS (
    SELECT lead_id,
           count(*)                                        AS attempts,
           count(*) FILTER (WHERE NOT is_failed)           AS reachable_attempts,
           count(*) FILTER (WHERE channel = 'call')        AS calls,
           count(*) FILTER (WHERE channel = 'sms')         AS texts,
           count(*) FILTER (WHERE is_failed)               AS failed_attempts,
           min(attempted_at)                               AS first_attempt_at,
           min(attempted_at) FILTER (WHERE NOT is_failed)  AS first_touch_at,
           min(first_connect_at)                           AS first_connect_at,
           max(attempted_at)                               AS last_attempt_at,
           (array_agg(agent_id ORDER BY attempted_at))[1]  AS agent_id,
           count(DISTINCT agent_id)                        AS agents,
           bool_or(channel = 'sms' AND consent_sms IS NOT TRUE) AS consent_violation,
           bool_or(attempted_at > first_connect_at)        AS contact_after_connect,
           bool_or(local_hour < 8 OR local_hour >= 21)     AS quiet_hours_risk,
           string_agg(
               CASE channel WHEN 'call' THEN 'call' ELSE 'text' END || ':' ||
               CASE status WHEN 'completed' THEN 'connected'
                           WHEN 'no_answer' THEN 'no answer'
                           WHEN 'voicemail' THEN 'voicemail'
                           WHEN 'delivered' THEN 'delivered'
                           ELSE 'failed (landline)' END,
               ' > ' ORDER BY attempted_at) AS what_happened
    FROM att GROUP BY lead_id
),
person AS (
    SELECT phone_e164, count(*) AS leads_for_person, min(received_at) AS first_seen
    FROM leads GROUP BY 1
),
asof AS (SELECT max(attempted_at) AS as_of FROM outreach_attempts),
base AS (
    SELECT
        l.lead_id, l.source, l.received_at, CAST(l.received_at AS DATE) AS received_date,
        l.lead_type, l.property_zip, l.status AS crm_status_today,
        CASE l.consent_sms WHEN true THEN 'Yes' WHEN false THEN 'No' ELSE 'Not captured' END AS sms_consent,
        COALESCE(g.attempts,0) AS attempts, COALESCE(g.reachable_attempts,0) AS reachable_attempts,
        COALESCE(g.calls,0) AS calls, COALESCE(g.texts,0) AS texts,
        COALESCE(g.failed_attempts,0) AS failed_attempts,
        COALESCE(g.agents,0) AS agents, g.agent_id,
        g.first_attempt_at, g.first_touch_at, g.first_connect_at, g.last_attempt_at,
        COALESCE(g.what_happened, 'no attempt logged') AS what_happened,
        CASE WHEN l.consent_sms THEN 3 ELSE 2 END AS expected_touches,
        CASE WHEN l.consent_sms THEN 'call > text > call' ELSE 'call > call' END AS expected_cadence,
        round(extract(epoch FROM g.first_touch_at - l.received_at)/60)::int AS minutes_to_first_touch,
        round(extract(epoch FROM (SELECT as_of FROM asof) - l.received_at)/3600)::int AS lead_age_hours,
        COALESCE(g.consent_violation,false)     AS flag_consent_violation,
        COALESCE(g.contact_after_connect,false) AS flag_contact_after_connect,
        COALESCE(g.quiet_hours_risk,false)      AS flag_quiet_hours_risk,
        (p.leads_for_person > 1)                AS flag_duplicate_journey,
        (p.leads_for_person > 1 AND l.received_at > p.first_seen) AS flag_repeat_lead,
        (l.email IS NULL OR NOT (right(regexp_replace(l.phone,'\D','','g'),10) ~ '^[2-9]\d{2}[2-9]\d{6}$')) AS flag_unusable_contact,
        (SELECT as_of FROM asof) AS as_of
    FROM leads l
    LEFT JOIN agg g USING (lead_id)
    JOIN person p   USING (phone_e164)
),
scored AS (
    SELECT b.*, pol.sla_minutes,
        CASE
            WHEN b.attempts = 0                 THEN '1. Received'
            WHEN b.reachable_attempts = 0       THEN '2. Routed'
            WHEN b.first_connect_at IS NOT NULL THEN '5. Outcome'
            WHEN b.reachable_attempts = 1       THEN '3. First touch'
            ELSE '4. Follow-up'
        END AS current_stage,
        CASE
            WHEN b.attempts = 0                 THEN '1. Untouched'
            WHEN b.reachable_attempts = 0       THEN '2. Dead-end'
            WHEN b.first_connect_at IS NOT NULL THEN '5. Connected'
            WHEN b.reachable_attempts < b.expected_touches THEN '3. Abandoned'
            ELSE '4. Exhausted'
        END AS primary_outcome,
        CASE
            WHEN b.first_touch_at IS NULL THEN 'No touch'
            WHEN b.minutes_to_first_touch <= pol.sla_minutes THEN 'Met'
            ELSE 'Late'
        END AS sla_status,
        CASE
            WHEN b.first_touch_at IS NULL          THEN '6. No touch'
            WHEN b.minutes_to_first_touch <= 5     THEN '1. Under 5 min'
            WHEN b.minutes_to_first_touch <= 15    THEN '2. 5-15 min'
            WHEN b.minutes_to_first_touch <= 60    THEN '3. 15-60 min'
            WHEN b.minutes_to_first_touch <= 240   THEN '4. 1-4 hrs'
            ELSE '5. Over 4 hrs'
        END AS first_touch_bucket,
        CASE
            WHEN b.attempts = 0
                THEN b.received_at + make_interval(mins => pol.sla_minutes)
            WHEN b.reachable_attempts = 0
                THEN b.last_attempt_at + interval '5 minutes'
            WHEN b.first_connect_at IS NOT NULL THEN NULL
            WHEN b.reachable_attempts < b.expected_touches AND b.texts = 0 AND b.expected_touches = 3
                THEN b.first_attempt_at + make_interval(mins => pol.sms_due_minutes)
            WHEN b.reachable_attempts < b.expected_touches
                THEN b.received_at + make_interval(mins => pol.call2_due_minutes)
            ELSE NULL
        END AS next_action_due_at
    FROM base b CROSS JOIN policy pol
)
SELECT s.*,
    CASE
        WHEN s.primary_outcome IN ('1. Untouched','2. Dead-end','3. Abandoned') THEN 'Process failure'
        WHEN s.primary_outcome = '4. Exhausted' THEN 'Completed, no response'
        ELSE 'Connected'
    END AS outcome_group,
    (s.sla_status = 'Met' AND s.primary_outcome IN ('4. Exhausted','5. Connected')) AS handling_success,
    (s.reachable_attempts > 0 AND s.first_connect_at IS NULL) AS cadence_eligible,
    (s.reachable_attempts > 0 AND s.first_connect_at IS NULL
        AND s.reachable_attempts >= s.expected_touches)        AS cadence_complete,
    (s.sla_status = 'Late')                                    AS flag_late_first_touch,
    CASE
        WHEN s.primary_outcome = '1. Untouched' THEN 'Route and place the first call'
        WHEN s.primary_outcome = '2. Dead-end'  THEN 'Call instead: the SMS path is unusable'
        WHEN s.primary_outcome = '3. Abandoned' AND s.texts = 0 AND s.expected_touches = 3
                                                THEN 'Send the follow-up text'
        WHEN s.primary_outcome = '3. Abandoned' THEN 'Place the follow-up call'
        WHEN s.flag_consent_violation           THEN 'Stop texting: review consent capture'
        WHEN s.flag_contact_after_connect       THEN 'Close out: already connected'
        WHEN s.flag_duplicate_journey           THEN 'Suppress duplicate outreach, keep both opportunities'
        WHEN s.primary_outcome = '4. Exhausted' THEN 'None: cadence complete, no response'
        ELSE 'None: connected'
    END AS next_expected_action,
    CASE
        WHEN s.next_action_due_at IS NULL THEN 'Complete'
        WHEN s.as_of > s.next_action_due_at + interval '24 hours' THEN 'Overdue 24h+'
        WHEN s.as_of > s.next_action_due_at + interval '1 hour'   THEN 'Overdue 1h+'
        WHEN s.as_of > s.next_action_due_at                       THEN 'Overdue'
        ELSE 'Not yet due'
    END AS next_action_status,
    CASE WHEN s.next_action_due_at IS NOT NULL AND s.as_of > s.next_action_due_at
         THEN round(extract(epoch FROM s.as_of - s.next_action_due_at)/3600)::int END AS hours_overdue,
    CASE
        WHEN s.primary_outcome = '1. Untouched' THEN 'No outreach'
        WHEN s.flag_consent_violation           THEN 'Consent violation'
        WHEN s.primary_outcome = '2. Dead-end'  THEN 'Unrecoverable contact path'
        WHEN s.flag_duplicate_journey OR s.flag_contact_after_connect THEN 'Duplicate / over-contact'
        ELSE 'None'
    END AS critical_exception,
    (s.primary_outcome IN ('1. Untouched','2. Dead-end')
        OR s.flag_consent_violation OR s.flag_duplicate_journey OR s.flag_contact_after_connect) AS is_critical_exception,
    CASE s.primary_outcome
        WHEN '1. Untouched' THEN 'Ingestion / routing'
        WHEN '2. Dead-end'  THEN 'Channel selection'
        WHEN '3. Abandoned' THEN 'Follow-up scheduling'
        WHEN '4. Exhausted' THEN 'Lead quality / contactability'
        ELSE 'None'
    END AS likely_investigation_area,
    CASE
        WHEN s.primary_outcome = '5. Connected' THEN 'connected'
        WHEN s.primary_outcome = '4. Exhausted' THEN 'nurture'
        WHEN s.flag_repeat_lead                 THEN 'merged'
        ELSE 'needs_attention'
    END AS lifecycle_status_should_be
FROM scored s
