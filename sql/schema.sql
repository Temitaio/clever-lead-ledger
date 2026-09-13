-- =============================================================================
-- Clever lead pipeline — clean raw layer
-- Two tables, typed and constrained, values kept as delivered.
-- The messiness (5 phone formats, null consent, stale status) is deliberately
-- preserved: it is the evidence, not noise to scrub away.
-- Timestamps are stored without timezone because the source files carry none.
-- =============================================================================

DROP TABLE IF EXISTS outreach_attempts;
DROP TABLE IF EXISTS leads;

CREATE TABLE leads (
    lead_id        text        PRIMARY KEY,
    source         text        NOT NULL,
    received_at    timestamp   NOT NULL,
    first_name     text        NOT NULL,
    last_name      text        NOT NULL,
    phone          text        NOT NULL,
    phone_e164     text        GENERATED ALWAYS AS
                               ('+1' || right(regexp_replace(phone, '\D', '', 'g'), 10)) STORED,
    email          text,
    consent_sms    boolean,             -- NULL = consent not captured by partner
    consent_call   boolean     NOT NULL,
    property_zip   char(5)     NOT NULL,
    lead_type      text        NOT NULL CHECK (lead_type IN ('buyer', 'seller')),
    status         text        NOT NULL
);

CREATE TABLE outreach_attempts (
    attempt_id     text        PRIMARY KEY,
    lead_id        text        NOT NULL REFERENCES leads (lead_id),
    channel        text        NOT NULL CHECK (channel IN ('call', 'sms')),
    attempted_at   timestamp   NOT NULL,
    status         text        NOT NULL,
    agent_id       text        NOT NULL
);

CREATE INDEX ON leads (source, received_at);
CREATE INDEX ON leads (phone_e164);
CREATE INDEX ON outreach_attempts (lead_id, attempted_at);

COMMENT ON TABLE  leads                     IS 'Leads received from partner sources, one row per lead_id, as delivered.';
COMMENT ON COLUMN leads.received_at         IS 'Timezone not specified in source; unclear if partner submit time or Clever ingest time.';
COMMENT ON COLUMN leads.phone               IS 'As delivered: 5 different formats across all partners.';
COMMENT ON COLUMN leads.phone_e164          IS 'Normalized phone, used to match the same person across partners.';
COMMENT ON COLUMN leads.consent_sms         IS 'TRUE / FALSE / NULL (not captured). NULL should not be treated as consent.';
COMMENT ON COLUMN leads.status              IS 'CRM status. Every row is "new", even leads already contacted.';
COMMENT ON TABLE  outreach_attempts         IS 'Call and SMS attempts from the telecom platform, one row per attempt.';
COMMENT ON COLUMN outreach_attempts.status  IS 'call: completed | no_answer | voicemail. sms: delivered | failed_err30006_landline.';
