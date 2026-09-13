# Ingestion and Routing Failure Modes

**Clever Lead Lifecycle Ledger** · supporting note
Joshua Agbabiaka · September 2026

The proposal identifies *where* leads fall through. This note names the failure classes that could produce each pattern, and the engineering pattern that prevents or exposes each one.

**These are hypotheses matched to symptoms, not diagnoses.** The supplied extract cannot distinguish, for example, a dual-write failure from an over-matching eligibility filter: both produce a lead row with zero outreach attempts. Where that ambiguity exists it is stated, along with the evidence that would resolve it.

---

## The cadence we assumed

Every reference below to an incomplete or abandoned cadence rests on this, so it is stated first.

| | Assumed |
|---|---|
| With SMS consent | **3 touches**: call → text → call |
| Without SMS consent | **2 touches**: call → call |
| Text timing | about 20 minutes after the first call |
| Second call timing | about 6 hours after receipt |
| First-touch SLA | 15 minutes |

**Basis: the dominant observed sequence, not a stated policy.** The path `call:no answer > text:delivered > call:connected` occurs 34 times in the extract, and the timings above are the observed medians (11-19 minutes for the text, roughly 310 minutes for the second call). A lead is classified Abandoned when it received fewer reachable touches than this.

**Sensitivity.** Among reachable, unconnected leads the touch counts are 20 / 39 / 28 for one, two and three touches, so the modal count is two. If Clever's real cadence is two touches, 25 leads reclassify from Abandoned to Exhausted and the headline numbers move materially: process failure from 36% to 24%, north star from 56% to 66%.

The counter-evidence is the sequence rather than the count. The 25 two-touch leads are precisely the first two steps of the 34-lead canonical path, stopped short. If the designed cadence were two touches, a third call would not appear in that identical pattern. **This is the first thing to confirm with Clever, and the numbers above are what changes if the assumption is wrong.**

---

## 1. Ingestion failure classes

| Class | Symptom | Observed in the extract | Prevention pattern |
|---|---|---|---|
| **Dual-write failure** | Lead row commits, queue publish fails. Record exists, work never queued | Best fit for the **18 untouched leads** | **Transactional outbox**: write the row and the outbox event in one transaction, publish asynchronously from the outbox |
| **Silent partial batch** | File arrives truncated. 500 rows sent, 480 landed, nobody notices | Not provable without partner-side counts | **Manifest with expected row count**; reject or alert on mismatch |
| **Duplicate delivery** | Partner retries, or the same person arrives through two partners | **10 people on 20 leads**, each pair from two different partners | **Idempotency key** on `(partner, partner_lead_id)` for true retries; **separate identity resolution** for cross-partner people |
| **Silent validation drop** | Malformed record fails a schema check and disappears | Cannot be seen: dropped records leave no trace | **Dead letter queue** with alerting on depth and age, plus replay |
| **Schema drift** | Partner adds or renames a field; parser silently nulls it | 17 leads have no SMS consent value, 15 no email | **Schema contract with versioning**; reject unknown shapes rather than coercing |
| **No provenance** | Cannot tell when a lead was ingested, or which batch it arrived in | The **LeadBridge 3-6 hour delay** is undiagnosable for exactly this reason | Stamp **`ingested_at`, `batch_id`, source offset** on every record |

### A note on delivery method

The extract does not state which partners send by API and which by file. It is weakly inferable: eight OfferNest leads have receipt times falling exactly on the hour, unlike every other lead in the dataset. That is a batch-delivery signature and a reasonable hypothesis to raise, not a conclusion.

---

## 2. Routing and scheduling failure classes

| Class | Symptom | Observed in the extract | Prevention pattern |
|---|---|---|---|
| **Poison message discarded** | An unprocessable lead is consumed and dropped rather than parked | Possible cause of the untouched block | **DLQ with replay.** Never silently discard |
| **Consumer lag** | Leads sit in the queue past SLA while throughput looks healthy | Possible cause of the LeadBridge delay | Alert on **oldest message age**, not throughput |
| **Over-matching eligibility filter** | A suppression list, DNC check or business-hours gate skips leads silently | Alternative explanation for the untouched block | **Mandatory `skip_reason`** on every decision not to act. No silent drops |
| **Assignment gap** | No agent available for a territory, so the lead is never assigned | Not distinguishable from other untouched causes | **Fallback queue** plus an unassigned-leads alert |
| **At-most-once delivery** | Consumer crashes mid-processing and the message is lost | Possible cause of the untouched block | **At-least-once delivery with idempotent consumers** |
| **Non-durable timers** | Follow-up scheduled in memory and lost on restart or redeploy | Best fit for the **45 abandoned cadences**, which span 25 of 40 agents and all six partners | **Durable scheduled jobs.** Store the expected next action and its deadline as state rather than implying it from a timer |
| **Stop signal not propagated** | Outreach continues after a connection | **5 leads called again after a completed call** | Explicit **state machine with terminal states**; idempotent cancel |
| **Capability blindness** | Texting a landline | **12 dead-end leads, 32 wasted attempts**, all with call consent available | **Line-type lookup at ingestion**; channel fallback inside the state machine |
| **Retry storm on terminal errors** | Carrier error 30006 retried two or three times. It will never succeed | Every one of the 12 dead-end leads | Classify errors as **retryable or terminal**; circuit-break on terminal |
| **Timezone-naive scheduling** | A fixed offset from receipt fires at 2am in the lead's local time | **73 attempts outside 8am-9pm local, 27 between midnight and 6am**, pending confirmation of the log timezone | Schedule inside the **lead's local window**, not at a fixed delay from receipt |
| **Consent state not enforced at send time** | A text goes out where consent is absent or unknown | **10 leads**, 4 explicit refusals and 6 unknown | Evaluate consent **at send time**, not at enqueue time. Treat unknown as no |
| **No outcome writeback** | The business record never learns what happened | **All 206 leads still read `new`**, including the 89 with completed calls | **Event-driven status update** from the ledger to the CRM |

---

## 3. The four patterns that cut across all of it

Individually the fixes above are small. What makes them durable is that each is either prevented or made visible by one of these four, which is why the proposal leads with the ledger rather than with a list of bug fixes.

**1. Idempotency keys, everywhere.** Retries become safe, duplicate partner deliveries collapse, and a redelivered message cannot produce a second outreach sequence.

**2. Dead letter queues with replay.** Nothing is ever silently discarded. A lead that cannot be processed is parked, visible, and recoverable, rather than absent.

**3. Reconciliation per hop, per partner.** Partner sent N → ingested N → routed N → attempted N. Any difference becomes an explicit exception instead of silence. This is what would have caught the untouched block on day one.

**4. Deadline-based alerting, which is the ledger's real job.** You cannot alert on an event that never happened unless something knows it was supposed to happen. Each system knows only its own events, so none of them can tell that an event is missing. The ledger holds the expected state transition and its deadline; the dashboard and the alerts are consumers of that model.

---

## 4. What would separate these hypotheses

The single highest-value instrumentation change is a **mandatory `skip_reason` on every decision not to act.** It converts "nothing happened" into "we chose not to act, and here is why", which distinguishes an eligibility filter from a lost message without any further investigation.

Beyond that, in order of diagnostic value:

| Add | Distinguishes |
|---|---|
| `ingested_at` and `batch_id` | Partner delivery delay from internal processing delay |
| `routed_at` and destination | Ingestion failure from routing failure |
| Queue depth and oldest-message age | Consumer lag from lost messages |
| DLQ depth and contents | Validation drops from dual-write failures |
| Scheduled-job audit log | Non-durable timers from deliberate cadence stops |

---

*Context: the fictionalized extract supplied with the assessment, 206 leads and 379 outreach attempts received 4-17 May 2026. Metric and taxonomy definitions are in [`kpi-taxonomy.md`](./kpi-taxonomy.md).*
