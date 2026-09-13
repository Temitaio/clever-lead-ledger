# Every Lead Accounted For

**Clever Real Estate — Senior Product Manager (Communication Systems) trial assessment**
Joshua Agbabiaka · September 2026

---

## The three links

| | What it is | Link |
|---|---|---|
| **1** | **The proposal** (4 pages, PDF) | https://drive.google.com/drive/folders/1KK1f1-Q_q_pG-xwx4wVtHOhBYZhVESC8?usp=sharing |
| **2** | **The working prototype** - live lead ledger dashboard | https://clever-lead-ledger.vercel.app/ |
| **3** | **This repository** - diagrams, taxonomy, SQL, and the code behind the dashboard | you are here |

The proposal is also in this repo under [`/proposal`](./proposal) if the Drive link gives you trouble.

---

## The diagnosis, in one paragraph

Clever can see successful component events: an API accepts a lead, a call is placed, a text is delivered. It cannot see whether a lead received the promised experience. That is how every system can look green while customers are still missed. In the supplied extract, only **56%** of leads received the expected handling, while **36%** were failed by the process rather than by customers who did not answer.

The deliverable is not another dashboard. It is a **lead-state model** that answers, for any lead: what should have happened, what did happen, what is late or broken, and what happens next. The dashboard in link 2 is one interface into that model.

---

## What is in this repository

### `/proposal`
The four-page proposal and the live-session agenda, both as PDF.

### `/diagrams`
Every diagram in the proposal, as PNG for reading and SVG for scaling.

| File | What it shows |
|---|---|
| `reconciliation` | 206 leads received → 188 entered outreach → 379 attempts logged, and where all 206 ended up. Every attempt reconciles to a known lead, so the leakage is in treatment, not record linkage. |
| `lifecycle_compact` | The five lifecycle stages, what leaks at each, and the three stages that leave no record today |
| `cost_cards` | What the leakage costs: recoverable volume, revenue at risk, compliance exposure, partner trust |
| `execution_phases` | Discovery → Define → Delivery → Launch → Monitor → Iterate, with timing and ownership |
| `prototype_architecture` | How the prototype is wired: Postgres → Preset → public page |
| `target_architecture` | The month-3 target state: one event stream, one ledger, alerts on absence |

### `/docs`
- **`dashboard-manual.md`** — how to read the dashboard: what each chart shows, three things worth clicking, and the assumptions behind the numbers. Start here if you are opening link 2.
- **`kpi-taxonomy.md`** — **the governing document.** Every metric, bucket and field name on the dashboard, with the exact SQL expression used to compute it. If a number on the dashboard and a number in the proposal ever disagree, this decides which is right.
- **`field-dictionary-and-taxonomy.md`** — the earlier working analysis: every source field, what it actually contains, and the cleaning rule applied.
- **`DEPLOY.md`** — how the public dashboard link is published.

### `/sql`
- **`schema.sql`** — the two-table Postgres schema. Deliberately a clean copy of what was delivered: the messiness (five phone formats, null consent, every status stuck on `new`) is preserved, because it is the evidence.
- **`load.sql`** — loads the two CSVs.
- **`ledger_v2.sql`** — the ledger itself. One row per lead, with the outcome taxonomy, the six metrics, the exception logic, and the next expected action. Every number on the dashboard traces to this query.

### Root
`index.html`, `api/guest-token.js`, `package.json` — the page that serves the dashboard publicly. The Preset API key stays server-side; each visitor gets a short-lived token scoped to one dashboard.

---

## The six shared metrics

| Layer | Metric | Question it answers | In the extract |
|---|---|---|---|
| North star | **Lead Handling Success Rate** | Did Clever do everything it was supposed to do? | **56%** |
| Reliability | Process Failure Rate | How many leads did our process fail? | 36% |
| Speed | First-Touch SLA | Did we act quickly enough? | 76% |
| Follow-up | Cadence Completion | Did we finish the promised sequence? | 48% |
| Business outcome | Connect Rate | Did we actually reach the customer? | 43% |
| Guardrail | Critical Exceptions | Are we creating legal or customer risk? | 65 leads |

**Lead Handling Success** = first touch inside SLA, and Clever either connected or completed the cadence. Two conditions, not five, so the number stays explainable when it moves. Connect Rate is deliberately *not* the north star: it moves with lead quality, which Clever does not control.

## The five outcomes

Every lead lands in exactly one, assigned at the earliest point it broke.

| Outcome | Rule | Leads |
|---|---|---|
| Untouched | No outreach attempt at all | 18 |
| Dead-end | Attempts existed; no reachable channel succeeded | 12 |
| Abandoned | Started, never completed expected cadence | 45 |
| Exhausted | Full cadence completed; customer never responded | 42 |
| Connected | At least one completed call | 89 |

Separating **Abandoned** from **Exhausted** prevents pipeline failure from being mistaken for poor lead quality. It is the most important line in the taxonomy.

---

## Assumptions, stated plainly

The extract shows *where* the experience breaks. It does not establish every root cause. Four working assumptions are marked throughout and are the first things I would confirm:

1. **First-touch SLA of 15 minutes.** The brief says "within minutes"; the exact target is Clever's to set.
2. **Cadence of call → text → call**, inferred from the dominant observed pattern.
3. **`completed` means a live conversation.** If it only means the call ended cleanly, the connect rate is overstated.
4. **Log timestamps are US Central.** The quiet-hours finding depends on this.

---

## Reproducing it

```bash
# 1. Load the data into any Postgres (Neon, Supabase, local)
psql "$DATABASE_URL" -f sql/schema.sql -f sql/load.sql   # run next to leads.csv and outreach_log.csv

# 2. Check the load
#    expect: leads 206, outreach_attempts 379

# 3. Paste sql/ledger_v2.sql into your BI tool as a virtual dataset
#    expect: 56% / 36% / 76% / 48% / 43% / 65, and outcomes 18 / 12 / 45 / 42 / 89
```

The source CSVs are not committed here, since they are Clever's assessment material rather than mine to republish.

---

*Built on the fictionalized extract supplied with the assessment: 206 leads and 379 outreach attempts, received 4-17 May 2026.*
