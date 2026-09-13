# How to read the dashboard

**Clever Lead Lifecycle Ledger** · [open the dashboard](https://clever-lead-ledger.vercel.app/)

A five-minute guide to what each chart shows, what the numbers mean, and the two or three things worth clicking.

---

## Start here: what this is

The dashboard is **one interface into a lead-state model**, not the product itself. The model answers four questions for every lead:

1. What *should* have happened?
2. What *did* happen?
3. What is *late or broken*?
4. What happens *next*?

Every chart below is a different cut of those four answers. The two tables at the bottom are the model itself, one row per lead.

**The data is the fictionalized extract supplied with the assessment:** 206 leads and 379 outreach attempts, received 4-17 May 2026. "Now" is pinned to the last timestamp in that data, which is why most overdue items read 24h+. In production that clock is live.

---

## Band 1: the six shared metrics

One vocabulary that Sales, Ops, Product and Engineering can all reconcile to. Read them left to right: north star, then its two drivers, then the business outcome, then the guardrail.

| Card | Reads | What it answers | How to read it |
|---|---|---|---|
| **1. Lead Handling Success Rate** | 56% | Did Clever do everything it was supposed to do? | **The north star.** First touch inside 15 minutes, *and* we either connected or completed the full cadence. It moves only when *we* get better |
| **2. Process Failure Rate** | 36% | How many leads did our process fail? | 75 of 206. These are failures we control, as distinct from customers who did not answer |
| **3. First-Touch SLA** | 76% | Did we act quickly enough? | Untouched leads count as misses, deliberately |
| **4. Cadence Completion** | 48% | Did we finish the promised sequence? | Of the 87 reachable leads we never connected with, only 42 got the full cadence |
| **5. Connect Rate** | 43% | Did we actually reach the customer? | **An outcome, not a health measure.** It moves with lead quality, which is exactly why it is not the north star |
| **6. Critical Exceptions** | 65 | Are we creating legal or customer risk? | Unique leads, not a sum of overlapping flags |

> **The question this band is designed to survive:** "Why does an Exhausted lead count as success if you never spoke to anyone?" Because the north star measures what Clever controls. We reached out on time and completed the approved cadence; whether the customer answers shows up separately in Connect Rate. Otherwise a weak lead source makes the operational system look broken.

---

## Band 2: where leads end up, and where they sit now

### Where all 206 leads end up

Five outcomes, mutually exclusive, summing to 100%.

| Outcome | Leads | Means |
|---|---|---|
| Untouched | 18 | No outreach attempt was ever made |
| Dead-end | 12 | Attempts existed, but no reachable channel succeeded |
| Abandoned | 45 | Outreach started and stopped before the cadence finished |
| Exhausted | 42 | Full cadence delivered, customer never responded |
| Connected | 89 | At least one completed call |

**The line that matters is between Abandoned and Exhausted.** Exhausted means the system did its job and nobody picked up. Abandoned means the system stopped trying. Collapse them into "no contact" and a pipeline bug hides behind a lead-quality excuse. That distinction is the whole reason this taxonomy exists.

### Where every lead sits in the lifecycle

The same 206 leads by *current* stage, stacked by whether their next action is complete or overdue. Received → Routed → First touch → Follow-up → Outcome.

Read the red: leads stuck at **Received** never reached the dialer, and leads stuck at **Routed** hit a channel that could not work.

---

## Band 3: what to fix now

### Exception queue

Every lead whose next expected action is overdue, oldest first. The columns are the point:

| Column | Shows |
|---|---|
| `critical_exception` | What kind of failure this is |
| `what_happened` | The actual sequence of calls and texts |
| `next_expected_action` | The specific thing to do about it |
| `hours_overdue` | How long it has been waiting |
| `likely_investigation_area` | Where to look, deliberately an area rather than a team |

A real row reads: *L-20169 · Routed · Unrecoverable contact path · text:failed (landline) > text:failed (landline) > text:failed (landline) · Call instead: the SMS path is unusable · 271 hours.*

**This is the part that turns BI into an operational product.** In production it refreshes live and the recommended action becomes a button.

---

## Band 4: the ledger itself

### The Lead Lifecycle Ledger

One row per lead, all 206. The column order follows the four questions:

| Question | Columns |
|---|---|
| What should have happened? | `expected_cadence` |
| What did happen? | `what_happened` |
| What is late or broken? | `sla_status`, `next_action_status`, `hours_overdue` |
| What happens next? | `next_expected_action`, `likely_investigation_area` |

**The last two columns are the argument.** `crm_status_today` reads `new` for all 206 leads, including the 89 we spoke to. `lifecycle_status_should_be` shows what it ought to say: connected 89, needs_attention 73, nurture 42, merged 2. The business record never learns the outcome, which is what makes silent failure structurally easy.

### Partner scorecard

The same six metrics cut by partner. Scan the Process failure column: this is where you see whether a problem is global or source-specific.

---

## Three things worth clicking

**1. Click the "Abandoned" bar.** Cross-filtering is on, so the ledger below filters to those 45 leads. Read the `what_happened` column: most show one call and nothing after, or a call and a text with no second call. The cadence stops mid-sequence, across many agents and every partner.

**2. Filter Partner to OfferNest.** The untouched block appears: consecutive lead IDs over six days, while that partner's other leads the same days were worked normally. Ingested, never routed.

**3. Sort the ledger by `sla_status`, then filter Partner to LeadBridge.** The late first touches cluster in one contiguous block: 3 to 6 hours, against a 7-minute median everywhere else. It looks like a batched delivery rather than a dialer problem, which is why the proposal instruments it before redesigning anything.

---

## The filters

Five, at the top of the dashboard. They apply to every chart.

| Filter | Use it to ask |
|---|---|
| **Partner** | Is this problem global or source-specific? |
| **Received date** | Did something change on a particular day? |
| **Outcome** | Show me only the leads that failed this way |
| **Next action status** | Show me only what is overdue |
| **SMS consent** | Does the failure pattern differ by channel permission? |

One finding worth reproducing with that last filter: leads **with** SMS consent fail more often than leads that declined it, because the text branch is where the dead-ends and most abandoned cadences live.

---

## Assumptions behind the numbers

Four, all confirmable in a 20-minute conversation. They are stated here rather than buried because they set the thresholds everything else keys off.

| Assumption | Used | If it is wrong |
|---|---|---|
| First-touch SLA is 15 minutes | Drives metrics 1 and 3 | Thresholds shift; the ranking of problems does not |
| Cadence is call → text → call | Defines Abandoned vs Exhausted | The split between those two buckets moves |
| `completed` means a live conversation | Drives Connect Rate | Connect rate is overstated |
| Log timestamps are US Central | Drives the quiet-hours flag | The 50 flagged leads may shrink substantially |

Full definitions, including the exact SQL behind every metric, are in [`docs/kpi-taxonomy.md`](./kpi-taxonomy.md).

---

## How it is built

Neon Postgres holds the two source tables exactly as delivered. All of the outcome logic lives in one version-controlled query, [`sql/ledger_v2.sql`](../sql/ledger_v2.sql), saved in Preset as the `lead_lifecycle_ledger` dataset. Every chart reads that one dataset, so **every number on screen traces back to a single query** rather than to ad-hoc chart-level logic.

The public link is a small page on Vercel that requests a short-lived visitor token, so reviewers need no login and the API key never leaves the server.
