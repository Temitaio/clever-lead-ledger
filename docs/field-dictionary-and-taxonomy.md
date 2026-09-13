# Clever Lead Pipeline — Field Dictionary & Taxonomy

**Scope:** `leads.csv` (206 rows) and `outreach_log.csv` (379 rows), covering leads received 4–17 May 2026 (14 days).
**Purpose:** Establish one shared vocabulary for what a lead is, what happened to it, and how we measure it, before anyone argues about whose system is broken.

---

## 1. Source fields — `leads.csv`

| Field | Type (as delivered → typed) | Definition | What the data actually shows | Cleaning rule |
|---|---|---|---|---|
| `lead_id` | text → text | Clever's identifier for a lead record. | 206 unique, no nulls. IDs are **not chronological** (L-20020 arrived 15 May, L-20148 on 4 May), which suggests IDs are assigned per ingestion batch. Contiguous ID blocks per source are therefore a batch signature. | Primary key. |
| `source` | text → text | Partner that sent the lead. | 6 partners: OfferNest 52, LeadBridge 45, AgentMatch Pro 29, SellFast Direct 27, HomeFlow 27, ListingLoop 26. **Ingestion method (API vs file transfer) is not in the data.** | Stored as delivered. Ingestion method, cost per lead and owner to be confirmed with Clever. |
| `received_at` | text → timestamp | When Clever received the lead. | Two formats (`07:34` and `7:34`), no timezone. It is unclear whether this is partner submit time or Clever ingest time — this matters for LeadBridge (see §5). | Stored as `timestamp` without timezone. Analysis **assumes America/Chicago** (Clever's HQ and published concierge hours). |
| `first_name`, `last_name` | text | Customer name. | 30 first names × 30 last names; names repeat heavily, so **name is not an identity key**. | As delivered. |
| `phone` | text → E.164 | Customer phone. Primary outreach channel and identity key. | **5 formats** evenly spread across all partners: dotted 47, E.164 44, parenthesized 41, dashed 37, digits-only 37. 3 fail NANP validity. Exact-string matching finds 1 duplicate person; normalized matching finds 10. | Kept as delivered; a generated column `phone_e164` (strip non-digits, last 10, prefix +1) sits beside it. |
| `email` | text | Customer email. | 15 nulls (7%). All unique, even for the same person across partners (different numeric suffixes), so email cannot be used for identity here. | Nullable. |
| `consent_sms` | text → enum | Whether the customer consented to SMS. | TRUE 172, FALSE 17, **null 17**. | Stored as nullable boolean. NULL is preserved and **treated as not consented** in analysis. |
| `consent_call` | text → bool | Whether the customer consented to calls. | TRUE for all 206. | Boolean. |
| `property_zip` | text | Zip of the property of interest. | Only 10 zips (10 metros across 9 states). | `char(5)`. Maps to 10 metros for local-time checks. |
| `lead_type` | text | Buyer or seller intent. | seller 150 (73%), buyer 56. | As delivered. |
| `status` | text | CRM status of the lead. | **`new` for all 206**, including the 89 leads we actually spoke to. Outreach outcomes never flow back to the lead record. | Stored as delivered. |

## 2. Source fields — `outreach_log.csv`

| Field | Type | Definition | What the data actually shows | Cleaning rule |
|---|---|---|---|---|
| `attempt_id` | text | Telecom platform ID for one call or SMS attempt. | 379 unique. | As delivered. |
| `lead_id` | text | The lead the attempt was made against. | 188 distinct; every value joins to `leads` (no orphans). | Foreign key to `leads`; the load would fail on an orphan. |
| `channel` | text | `call` or `sms`. | call 252, sms 127. | As delivered. |
| `attempted_at` | text → timestamp | When the attempt was made. | Same format and timezone ambiguity as `received_at`. 27 attempts fall between midnight and 6am in the lead's local time. | Same as `received_at`. |
| `status` | text → enum | Telecom result. | call: `completed` 92, `no_answer` 124, `voicemail` 36. sms: `delivered` 95, `failed_err30006_landline` 32. | Stored as delivered. Analysis treats `completed` as a connect and `failed_*` as not a real touch. |
| `agent_id` | text | Agent who owned the attempt. | 40 agents, 1–10 leads each. Every lead is worked by exactly one agent; duplicate people are worked by two. | As delivered. |

**Assumption to confirm:** `completed` means a live two-way conversation, not just "the call ended".

---

## 3. Derived fields (the ledger)

Not stored in the database. Computed in one Preset virtual dataset (`sql/preset_lead_outcomes.sql`), so the database stays a clean copy of what was delivered.

| Field | Definition |
|---|---|
| `person_key` | Normalized E.164 phone. The unit of customer experience. |
| `person_lead_count` / `person_lead_rank` | How many leads this person generated; order of this lead among them. |
| `is_repeat_lead` | 2nd+ lead for the same person inside the dedupe window (30 days). |
| `attempts_total`, `call_attempts`, `sms_attempts` | Counts of attempts. |
| `failed_attempts` / `reachable_attempts` | Attempts that failed at the carrier vs. attempts that could plausibly reach a human. **A failed SMS is activity, not a touch.** |
| `first_attempt_at`, `first_reachable_attempt_at`, `first_connect_at` | Key timestamps. |
| `minutes_to_first_touch` | `first_reachable_attempt_at − received_at`. The speed metric. |
| `expected_touches` | From policy: 3 if SMS permitted (call → SMS → call), else 2 (call → call). Inferred from the dominant observed pattern; to confirm. |
| `touch_sequence` | Human-readable path, e.g. `call:no_answer > sms:delivered > call:connected`. |
| `sla_status` | `met` (≤ 15 min), `late` (> 15 min), `never` (no reachable touch). |
| `primary_outcome` | See taxonomy §4. Exactly one per lead. |
| `outcome_owner` | Team accountable for that outcome. |
| `promise_kept` | See §6. The composite "did this lead get what we promise" flag. |
| Attempt-level flags: `attempt_number`, `minutes_since_received`, `minutes_since_prev_attempt`, `local_hour`, `is_quiet_hours`, `is_outside_ops_hours`, `is_sms_without_consent`, `is_after_connect` | Per-attempt timing and compliance flags. |

---

## 4. Taxonomy, layer 1 — Primary outcome (mutually exclusive, sums to 100%)

Each lead is classified by the **first** rule it matches, in this order. The order matters: it assigns each lead to the earliest point in the pipeline where it broke.

| # | Outcome | Rule | Group | Where it broke | Owner | Leads | % |
|---|---|---|---|---|---|---|---|
| 1 | **Untouched** | Zero attempts | Process failure | Ingestion / routing | Engineering (ingestion) | 18 | 8.7% |
| 2 | **Dead-end** | Attempts exist, all failed at carrier, no fallback | Process failure | Channel selection | Engineering (telecom) + Ops | 12 | 5.8% |
| 3 | **Abandoned** | Reachable, never connected, fewer touches than policy requires | Process failure | Follow-up cadence | Ops + Engineering (sequencer) | 45 | 21.8% |
| 4 | **Exhausted** | Full cadence delivered, never connected | Legitimate no-contact | Customer contactability | Partner mgmt / Marketing | 42 | 20.4% |
| 5 | **Connected** | ≥ 1 completed call | Success | — | Sales | 89 | 43.2% |

**Process failure = 1 + 2 + 3 = 75 leads (36.4%).** These are leads the system failed, as distinct from leads who simply didn't pick up. Separating *Exhausted* from *Abandoned* is the most important line in this taxonomy: it stops us from blaming lead quality for a pipeline bug, and stops us from blaming the pipeline for lead quality.

## 5. Taxonomy, layer 2 — Overlay flags (non-exclusive, any outcome can carry them)

| Flag | Rule | Category | Leads | Notes |
|---|---|---|---|---|
| `flag_late_first_touch` | First reachable touch > 15 min | Speed | 20 | All 20 are LeadBridge, one contiguous ID block (L-20187–L-20206); first touch 170–361 min vs. a 7-min median everywhere else. |
| `flag_duplicate_person` | Person generated > 1 lead | Customer experience | 20 leads / 10 people | Each pair came from two different partners, 3–30 h apart, and was worked by two different agents. 3 people had two separate conversations. All 10 pairs have **different property zips**, so they may be real second intents. |
| `flag_contact_after_connect` | Attempt made after a completed call | Customer experience | 5 | Called again after we'd already spoken to them. |
| `flag_sms_without_consent` | SMS sent where consent ≠ granted | Compliance | 10 | 4 explicit `FALSE`, 6 unknown. |
| `flag_quiet_hours_contact` | Attempt outside 8am–9pm lead-local time | Compliance | 50 leads / 73 attempts | **Depends on the timezone assumption.** Mechanism: follow-up calls fire at a fixed offset after receipt (~6 h), so an evening lead gets a 1–2am call. |
| `flag_outside_ops_hours` | Attempt outside 7am–9pm CT (published concierge hours) | Operations | 52 attempts | Either automation is dialing outside staffed hours, or the logs aren't in CT. Both are worth knowing. |
| `flag_invalid_phone` | Fails NANP validity | Data quality | 3 | |
| `flag_consent_unknown` | `consent_sms` null | Data quality | 17 | Partner-side capture gap. |
| `flag_missing_email` | Email null | Data quality | 15 | No outreach impact today. |
| `flag_status_stale` | CRM status still `new` after outreach | Data integrity | 188 | Outcomes never flow back to the lead record. |

## 6. Metric definitions

| Metric | Definition | Current |
|---|---|---|
| **Promise-Kept Rate** (north star) | % of leads where: first reachable touch ≤ SLA **and** outcome ∈ {Connected, Exhausted} **and** no SMS without consent **and** no contact after connect **and** not a duplicate person | **40.3%** |
| Process Failure Rate | % of leads in Untouched + Dead-end + Abandoned | 36.4% |
| Coverage | % of leads with ≥ 1 reachable touch | 85.4% |
| SLA Attainment | % of all leads with `sla_status = met` (untouched count as misses) | 75.7% |
| Median Time to First Touch | Median `minutes_to_first_touch`, touched leads | 8 min |
| Cadence Completion | % of reachable, unconnected leads that received the full cadence | 48% (42 of 87) |
| Connect Rate | % of leads with a completed call | 43.2% |
| Duplicate Person Rate | % of people with > 1 lead | 5.1% (10 of 196) |
| Compliance Violations | Count of SMS without consent (+ quiet-hours attempts once timezone confirmed) | 10 (+73 pending) |

Why Promise-Kept is the north star rather than connect rate: connect rate mixes things we control (did we try properly?) with things we don't (did they answer?). Promise-Kept isolates the part of the experience that is entirely Clever's responsibility, so it moves only when we get better.

## 7. Assumptions behind the metrics

| Parameter | Value | Status |
|---|---|---|
| First-touch SLA | 15 min | Assumption — brief says "within minutes" |
| Expected touches (SMS ok / no SMS) | 3 / 2 | Inferred from dominant observed pattern |
| SMS due after first call | 20 min | Observed median ~11–19 min |
| Follow-up call due after receipt | 360 min | Observed median ~310 min |
| Quiet hours (lead local) | 8am–9pm | Federal TCPA window; some states are stricter — confirm with Legal |
| Ops hours | 7am–9pm CT | Published concierge hours |
| Source timezone of logs | America/Chicago | **Assumption — top open question** |
| Dedupe window | 30 days | Assumption |
