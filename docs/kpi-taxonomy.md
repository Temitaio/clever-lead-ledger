# KPI Taxonomy and Data Dictionary

**Clever Lead Lifecycle Ledger**
Joshua Agbabiaka · September 2026 · Version 1.0

This is the governing document for the dashboard. Every metric, bucket and field name on screen is defined here, with the exact expression used to compute it. If a number on the dashboard and a number in the proposal ever disagree, this document decides which is right.

**Scope:** the fictionalized extract supplied with the assessment. 206 leads and 379 outreach attempts, received 4-17 May 2026.

---

## 1. Design principles

Four rules govern everything below.

1. **Measure the lead, not the event.** A placed call and a delivered text are system successes. Neither tells you whether a person was reached. Every metric here is defined at the lead level.
2. **One lead, one outcome.** The five outcomes are mutually exclusive and sum to 100%. Anything else can be argued with.
3. **Separate what we control from what we do not.** Process health metrics move only when Clever changes. Business outcomes move with lead quality too. They are never mixed in one number.
4. **Every number traces to a query.** All logic lives in `sql/ledger_v2.sql`. Nothing is computed by hand.

---

## 2. Source layer

Two tables, loaded from the supplied CSVs and kept as delivered. The messiness is preserved deliberately: it is evidence, not noise.

### 2.1 `leads`

| Field | Type | Definition | Notes on the actual data |
|---|---|---|---|
| `lead_id` | text, PK | Clever's identifier for a lead | 206 unique. Not chronological, which suggests IDs are assigned per ingestion batch |
| `source` | text | Partner that sent the lead | 6 partners. Ingestion method (API vs file) is **not** in the data |
| `received_at` | timestamp | When Clever received the lead | No timezone. Unclear whether partner submit time or Clever ingest time |
| `first_name`, `last_name` | text | Customer name | Names repeat heavily, so name is **not** an identity key |
| `phone` | text | Customer phone | **5 different formats** across all partners |
| `phone_e164` | text, generated | Normalized phone: strip non-digits, keep last 10, prefix `+1` | The identity key. Raw matching finds 1 duplicate person; normalized finds 10 |
| `email` | text, nullable | Customer email | 15 nulls. All unique even for the same person, so unusable for identity |
| `consent_sms` | boolean, nullable | SMS consent | TRUE 172, FALSE 17, **NULL 17**. NULL is treated as *not consented* |
| `consent_call` | boolean | Call consent | TRUE for all 206 |
| `property_zip` | char(5) | Zip of the property | 10 zips across 9 states. Maps to timezone for quiet-hours checks |
| `lead_type` | text | buyer or seller | seller 150, buyer 56 |
| `status` | text | CRM status | **`new` for all 206**, including the 89 with completed calls |

### 2.2 `outreach_attempts`

| Field | Type | Definition | Notes on the actual data |
|---|---|---|---|
| `attempt_id` | text, PK | Telecom platform ID for one attempt | 379 unique |
| `lead_id` | text, FK | The lead attempted | 188 distinct. **Every value joins to a lead; no orphan records** |
| `channel` | text | `call` or `sms` | 252 calls, 127 texts |
| `attempted_at` | timestamp | When the attempt was made | Same timezone ambiguity as `received_at` |
| `status` | text | Telecom result | call: `completed` 92, `no_answer` 124, `voicemail` 36. sms: `delivered` 95, `failed_err30006_landline` 32 |
| `agent_id` | text | Agent who owned the attempt | 40 agents |

### 2.3 Event semantics

What each logged event *means*, and what it should trigger. This translation layer is the thing missing from Clever's systems today.

| Logged event | Is it a touch? | Is it contact? | Action it should trigger |
|---|---|---|---|
| `call: completed` | Yes | **Yes** | Stop outreach, hand to agent match, write status back |
| `call: no_answer` | Yes | No | Continue cadence |
| `call: voicemail` | Yes | No | Continue cadence |
| `sms: delivered` | Yes | No | Continue cadence |
| `sms: failed_err30006_landline` | **No** | No | Switch to a call immediately. Never retry SMS |
| *no event before deadline* | — | — | **Alert.** This is the failure no monitoring catches today |

---

## 3. Policy parameters

These four values drive every threshold. They are **assumptions**, not settled facts, and are the first things to confirm with Clever. All are set in one CTE at the top of `ledger_v2.sql`, so changing a rule is a one-line edit.

| Parameter | Value used | Basis | Confidence |
|---|---|---|---|
| First-touch SLA | 15 minutes | Brief says "within minutes" | To confirm |
| Expected cadence, SMS permitted | call → text → call (3 touches) | Dominant observed pattern | Inferred |
| Expected cadence, SMS not permitted | call → call (2 touches) | Same, minus the text | Inferred |
| Text due after first call | 20 minutes | Observed median 11-19 min | Inferred |
| Second call due after receipt | 360 minutes | Observed median ~310 min | Inferred |
| Quiet hours | 08:00-21:00, lead local time | Federal TCPA window; some states stricter | To confirm with Legal |
| Log timezone | US Central | Clever HQ and published concierge hours | **To confirm; the quiet-hours finding depends on it** |
| `completed` means | a live conversation | Assumption | **To confirm** |

---

## 4. Taxonomy layer 1: outcome (mutually exclusive)

Each lead is classified by the **first** rule it matches, in this order. The order matters: it assigns each lead to the earliest point where it broke.

| # | Outcome | Rule | Group | Where it broke | Leads |
|---|---|---|---|---|---|
| 1 | **Untouched** | `attempts = 0` | Process failure | Ingestion / routing | 18 |
| 2 | **Dead-end** | `reachable_attempts = 0` | Process failure | Channel selection | 12 |
| 3 | **Abandoned** | reachable, not connected, `reachable_attempts < expected_touches` | Process failure | Follow-up scheduling | 45 |
| 4 | **Exhausted** | reachable, not connected, full cadence delivered | Completed, no response | Contactability | 42 |
| 5 | **Connected** | `first_connect_at IS NOT NULL` | Connected | — | 89 |

`reachable_attempts` counts attempts that could plausibly reach a human. **A failed SMS to a landline is activity, not a touch.**

> **Separating Abandoned from Exhausted is the most important line in this taxonomy.** Exhausted means the system did its job and the customer did not answer. Abandoned means the system stopped trying. Collapsed into "no contact", a pipeline bug hides behind a lead-quality excuse.

**Process failure** = Untouched + Dead-end + Abandoned = 75 leads (36%).

## 5. Taxonomy layer 2: lifecycle stage (where the lead sits now)

| # | Stage | Rule | Leads |
|---|---|---|---|
| 1 | Received | no attempts yet | 18 |
| 2 | Routed | attempted, but no reachable channel succeeded | 12 |
| 3 | First touch | exactly one reachable attempt | 20 |
| 4 | Follow-up | two or more reachable attempts, not connected | 67 |
| 5 | Outcome | connected | 89 |

Stages 1, 2 and 5 leave **no record** in Clever's systems today. That absence is why these failures are invisible rather than merely unfixed.

## 6. Taxonomy layer 3: critical exception (guardrail)

Assigned by first match, so each lead carries **at most one** exception. The count is therefore unique leads, never a sum of overlapping flags.

| Exception | Rule | Leads |
|---|---|---|
| No outreach | outcome is Untouched | 18 |
| Consent violation | any text sent where consent is not TRUE | 10 |
| Unrecoverable contact path | outcome is Dead-end | 12 |
| Duplicate / over-contact | same person on 2+ leads, or contacted after a connect | 25 |
| None | — | 141 |

**Total unique leads with an exception: 65.**

### Non-exclusive risk flags

Separate from the exception above, a lead can carry any number of these. Useful for filtering, not for headline counts.

| Flag | Rule | Leads |
|---|---|---|
| `flag_late_first_touch` | first reachable touch later than SLA | 20 |
| `flag_duplicate_journey` | person appears on more than one lead | 20 |
| `flag_repeat_lead` | the 2nd+ lead for that person | 10 |
| `flag_consent_violation` | text sent without affirmative consent | 10 |
| `flag_contact_after_connect` | attempt after a completed call | 5 |
| `flag_quiet_hours_risk` | attempt outside 08:00-21:00 lead local | 50 |
| `flag_unusable_contact` | missing email or phone failing NANP validity | 18 |

`flag_quiet_hours_risk` depends on the log timezone assumption and is labelled as risk, not violation, for that reason.

## 7. Taxonomy layer 4: next expected action

What the ledger says should happen next. Derived, not stored, so it cannot drift from the outcome.

| Outcome / condition | Next expected action | Due at |
|---|---|---|
| Untouched | Route and place the first call | `received_at` + SLA |
| Dead-end | Call instead: the SMS path is unusable | last attempt + 5 min |
| Abandoned, no text yet, SMS permitted | Send the follow-up text | first attempt + 20 min |
| Abandoned, otherwise | Place the follow-up call | `received_at` + 360 min |
| Consent violation | Stop texting: review consent capture | immediate |
| Contacted after connect | Close out: already connected | immediate |
| Duplicate journey | Suppress duplicate outreach, keep both opportunities | immediate |
| Exhausted | None: cadence complete, no response | — |
| Connected | None: connected | — |

`next_action_status` compares the due time to now: **Complete**, **Not yet due**, **Overdue**, **Overdue 1h+**, **Overdue 24h+**.

> In the extract, "now" is pinned to the last timestamp in the data (17 May 2026). In production this clock is live, which is what makes the queue actionable rather than historical.

## 8. Taxonomy layer 5: lifecycle status (what the CRM should say)

The CRM reads `new` for all 206 leads. The ledger derives what it should be, and this is what a writeback would set.

| Status | Rule | Leads |
|---|---|---|
| `connected` | outcome is Connected | 89 |
| `nurture` | outcome is Exhausted: full cadence, no response | 42 |
| `merged` | a repeat lead for a person already in the system | 2 |
| `needs_attention` | any process failure | 73 |

Repeat leads that connected are reported as `connected` rather than `merged`, because the more informative state wins.

---

## 9. The six metrics

Exact expressions, as used on the dashboard.

### North star: Lead Handling Success Rate — **56%**
```sql
AVG(CASE WHEN handling_success THEN 1.0 ELSE 0 END)
-- handling_success = sla_status = 'Met'
--                    AND primary_outcome IN ('4. Exhausted','5. Connected')
```
Did Clever do everything it was supposed to do? Two conditions, not five, so the number stays explainable when it moves. Untouched, Dead-end and Abandoned all fail. Exhausted and Connected pass **only if** the first touch met SLA, which is why 115 of the 131 completed leads qualify.

### Reliability: Process Failure Rate — **36%**
```sql
AVG(CASE WHEN outcome_group = 'Process failure' THEN 1.0 ELSE 0 END)
```
How many leads did our process fail? Isolates failures Clever controls.

### Speed: First-Touch SLA Attainment — **76%**
```sql
AVG(CASE WHEN sla_status = 'Met' THEN 1.0 ELSE 0 END)
```
Did we act quickly enough? Untouched leads count as misses, deliberately. Median time to first touch is 7 minutes when it works, which is why the median is not the headline: it hides the zeros.

### Follow-up: Cadence Completion — **48%**
```sql
SUM(CASE WHEN cadence_complete THEN 1 ELSE 0 END) * 1.0
  / NULLIF(SUM(CASE WHEN cadence_eligible THEN 1 ELSE 0 END), 0)
-- eligible = reachable and never connected  (87 leads)
-- complete = eligible and reachable_attempts >= expected_touches  (42 leads)
```
Did we finish the promised sequence? Connected leads are excluded, since stopping after a connect is correct behaviour, not an incomplete cadence.

### Business outcome: Connect Rate — **43%**
```sql
AVG(CASE WHEN primary_outcome = '5. Connected' THEN 1.0 ELSE 0 END)
```
Did we actually reach the customer? **Deliberately not the north star.** It moves with lead quality, which Clever does not control. A weak lead source would make the operational system look broken.

### Guardrail: Critical Exceptions — **65 leads**
```sql
SUM(CASE WHEN is_critical_exception THEN 1 ELSE 0 END)
```
Are we creating legal or customer risk? Unique leads, not summed flags.

### Counter-metrics

Any target gets gamed. These are watched alongside, not reported as headlines.

| Target | How it could be gamed | Watch alongside |
|---|---|---|
| First-Touch SLA | A 3-second "touch" call to stop the clock | Average call duration, connect rate |
| Cadence Completion | Firing texts to tick the box | Texts per connect |
| Quiet-hours guard | — | Connect rate may dip *by design* before it rises |

---

## 10. Derived field reference

The full `lead_lifecycle_ledger` dataset, grouped by purpose. One row per lead.

**Identity and origin:** `lead_id`, `source`, `received_at`, `received_date`, `lead_type`, `property_zip`, `sms_consent`, `agent_id`

**Activity counts:** `attempts`, `reachable_attempts`, `calls`, `texts`, `failed_attempts`, `agents`

**Timestamps:** `first_attempt_at`, `first_touch_at`, `first_connect_at`, `last_attempt_at`, `minutes_to_first_touch`, `lead_age_hours`, `as_of`

**What should have happened:** `expected_cadence`, `expected_touches`, `sla_minutes`

**What did happen:** `what_happened` — the readable sequence, e.g. `call:no answer > text:delivered > call:connected`

**Classification:** `current_stage`, `primary_outcome`, `outcome_group`, `sla_status`, `first_touch_bucket`, `handling_success`, `cadence_eligible`, `cadence_complete`

**What is late or broken:** `next_action_due_at`, `next_action_status`, `hours_overdue`, `critical_exception`, `is_critical_exception`, plus the seven `flag_*` fields

**What happens next:** `next_expected_action`, `likely_investigation_area`, `lifecycle_status_should_be`

**Naming conventions:** `flag_*` is a boolean risk overlay. `is_*` is a boolean classification. `*_at` is a timestamp. `*_status` is a small enumerated set. Numeric prefixes on enumerated values (`1. Received`) exist so charts sort in pipeline order rather than alphabetically.

---

## 11. Ownership and change control

| Element | Owner | Changes when |
|---|---|---|
| Policy parameters (§3) | Product, with Sales and Legal | Clever confirms the real SLA, cadence and consent rules |
| Outcome taxonomy (§4) | Product | Only with explicit agreement across Sales, Ops and Engineering |
| Metric definitions (§9) | Product | Versioned here first, then in the dataset |
| Field names (§10) | Data | Additive changes only; renames break saved charts |
| `likely_investigation_area` | — | Intentionally an *area*, not a team. Team ownership is Clever's to assign |

**Why this document exists.** The week-1 deliverable in the proposal is agreement, not a dashboard. Without one shared definition of a missed lead, every later fix becomes an argument about whose number is right. This is that definition, written down and versioned.
