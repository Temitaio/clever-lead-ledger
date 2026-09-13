# Publishing the dashboard as a public link

Three systems, in this order: **GitHub** (stores two files) → **Vercel** (serves them) → **Preset** (allows the embed).

Total time: about 40 minutes the first time. You need a GitHub account and a Vercel account; both are free and Vercel signs in with GitHub.

There is no command line in this guide. Everything is done in the browser.

---

## Before you start: what these two files do

| File | Job |
|---|---|
| `index.html` | The page a reviewer opens. It loads Preset's embed library and puts the dashboard in an iframe. |
| `api/guest-token.js` | A tiny server function. It holds your Preset API key, asks Preset for a 5-minute visitor pass, and hands only that pass to the browser. The key itself never leaves the server. |

The `api/` folder name matters. Vercel automatically treats any file inside `api/` as a server function, which is why the URL becomes `/api/guest-token`.

---

## Part 1 — Preset: get the two IDs and an API key (10 min)

### 1a. Turn on embedding for the dashboard

1. Open the dashboard: https://e4e965ae.us2a.app.preset.io/superset/dashboard/clever-lead-lifecycle-ledger/
2. Top right, click the **⋯** menu → **Embed dashboard**.
3. A dialog appears with an **Allowed Domains** box. Leave it **empty for now** — you do not know your Vercel address yet. You will come back in Part 4.
4. Click **Enable embedding**.
5. Copy the **UUID** it shows you. This is your *embedded dashboard ID*. Paste it somewhere safe.

> If you do not see "Embed dashboard" in the menu, embedding is not enabled on your plan tier. Stop here and use the fallback at the bottom of this guide.

### 1b. Create an API key

This is in **Preset Manager**, not the workspace.

1. Go to https://manage.app.preset.io
2. Click your profile (bottom left or top right, depending on the layout) → **API Keys**.
3. Click **Generate API key**.
4. Copy **both** values: the **Name** (also called token) and the **Secret**. The secret is shown once.

### 1c. Find your team and workspace slugs

These two are the fiddliest values to find, because Preset shows them in different places depending on how you navigate. Try these in order.

**Method 1: the workspace slug is in your dashboard URL.**

Your workspace address is:

```
https://e4e965ae.us2a.app.preset.io
        ^^^^^^^^ ^^^^
        workspace  region
```

So your **workspace slug is very likely `e4e965ae`**, and your region is `us2a`. Note this down as a candidate.

**Method 2: read it off Preset Manager.**

1. Go to https://manage.app.preset.io
2. Click into your workspace tile, then look at the address bar. Preset uses several URL shapes, so you may see any of:
   - `.../teams/<team>/workspaces/<workspace>/...`
   - `.../workspaces/<workspace>/...`
   - a plain `.../home` with no slugs at all
3. If you see slugs, use them. If you only see `/home`, try Method 3.

**Method 3: ask Preset's own API.**

While logged into Preset Manager, open a new tab and visit:

```
https://manage.app.preset.io/api/v1/teams/
```

If it returns JSON, look for a `name` field on your team. That value is the **team slug**. It usually looks machine-generated, something like `1a2b3c4d` or `acme-corp`, not your display name.

Then visit:

```
https://manage.app.preset.io/api/v1/teams/<team-slug>/workspaces/
```

and look for the `name` field on your workspace. That is the **workspace slug**.

**If you cannot find them, do not guess for long.** The slugs only matter for one line in the function, and the test in Part 5 tells you precisely when they are wrong: a 404 from `/api/guest-token` means the team or workspace slug is off. Deploy with your best candidates, run the test, and adjust the environment variable in Vercel if it 404s. Changing an environment variable and redeploying takes about 30 seconds.

**At the end of Part 1 you should have five values:** embedded dashboard ID, API key name, API key secret, team slug, workspace slug.

---

## Part 2 — GitHub: put the files in a repository (10 min)

1. Go to https://github.com and sign in.
2. Click the **+** in the top right → **New repository**.
3. Name it `clever-lead-ledger`. Leave it **Public** or set **Private**; either works with Vercel.
4. Do **not** add a README or .gitignore. Click **Create repository**.
5. On the empty repository page, click **uploading an existing file**.
6. Drag in `index.html` and `package.json` from the `embed` folder.
7. **The `api` folder needs care.** Dragging a folder works in Chrome; if it does not, do this instead:
   - Click **Create new file** (or in the upload screen, use the file name box).
   - In the filename box type exactly: `api/guest-token.js` — typing the slash creates the folder.
   - Paste the contents of `guest-token.js` into the editor.
8. Click **Commit changes**.

Your repository should now show:

```
index.html
package.json
api/guest-token.js
```

If `api/guest-token.js` is sitting at the root as `guest-token.js`, the function will not work. It must be inside `api/`.

---

## Part 3 — Vercel: deploy (10 min)

1. Go to https://vercel.com/signup and choose **Continue with GitHub**. Authorize it.
2. On the dashboard, click **Add New → Project**.
3. Your GitHub repositories are listed. Find `clever-lead-ledger` and click **Import**.
   - If it is not listed, click **Adjust GitHub App Permissions** and grant access to that repository.
4. On the configure screen:
   - **Framework Preset:** leave as **Other**. Do not pick one.
   - **Build and Output Settings:** leave everything blank. There is no build step.
   - **Environment Variables:** this is the important part. Add these five, one at a time. Name on the left, value on the right, then **Add** after each.

| Name | Value |
|---|---|
| `PRESET_API_TOKEN` | the API key **Name** from step 1b |
| `PRESET_API_SECRET` | the API key **Secret** from step 1b |
| `PRESET_TEAM` | the team slug from step 1c |
| `PRESET_WORKSPACE` | the workspace slug from step 1c |
| `PRESET_DASHBOARD_ID` | the embedded dashboard UUID from step 1a |

5. Click **Deploy**. It takes about a minute.
6. When it finishes you get a URL like `https://clever-lead-ledger.vercel.app`. **Copy it.**

---

## Part 4 — Wire the two ends together (5 min)

Two things still point at nothing.

### 4a. Put the dashboard ID into the page

1. In GitHub, open `index.html` and click the **pencil** icon to edit.
2. Find this line near the bottom:
   ```js
   id: "PASTE_EMBEDDED_DASHBOARD_ID",
   ```
3. Replace `PASTE_EMBEDDED_DASHBOARD_ID` with your UUID, keeping the quotes:
   ```js
   id: "a1b2c3d4-5678-90ab-cdef-1234567890ab",
   ```
4. Commit. Vercel redeploys automatically within a minute.

The `supersetDomain` line is already filled in with your workspace.

### 4b. Allow your Vercel domain in Preset

1. Back in Preset → dashboard → **⋯ → Embed dashboard**.
2. In **Allowed Domains**, enter your Vercel host **without** `https://`:
   ```
   clever-lead-ledger.vercel.app
   ```
3. Save.

This has to match exactly. A mismatch here is the single most common reason the iframe stays blank.

---

## Part 5 — Test it

Test in this order. Each step isolates a different failure.

1. **The function:** open `https://your-app.vercel.app/api/guest-token`
   - You want: `{"token":"eyJ..."}`
   - `{"error":"Preset auth failed (401)"}` → wrong API key name or secret.
   - `{"error":"Guest token request failed (404)"}` → wrong team or workspace slug. Go back to step 1c, try the next method, update the variable in Vercel (**Settings → Environment Variables**), then **Deployments → ⋯ → Redeploy**.
   - `{"error":"Guest token request failed (400)"}` → wrong dashboard UUID.
2. **The page:** open `https://your-app.vercel.app` in a **private window**, so you know you are not seeing it because you are logged into Preset.
   - Dashboard renders → done.
   - Blank area where the dashboard should be → the allowed domain does not match. Recheck 4b.
   - Header shows but nothing below → open the browser console (F12) and read the error.

### Where to see errors

In Vercel: your project → **Logs** tab → click the `/api/guest-token` request. Anything the function printed with `console.error` appears there.

---

## After it works

- **The URL is public.** Anyone with the link can view the dashboard without logging in. That is the intent here; the data is fictional and the token only opens this one dashboard.
- **Tokens expire every 5 minutes**, and the embed library quietly fetches a new one. Reviewers can leave the tab open as long as they like.
- **Neon may sleep** on the free tier. The first load after a quiet spell can take a few seconds while the database wakes.
- **Test the link yourself the morning you submit.** Trial expiry is the one failure you cannot fix in the moment.

---

## Fallback, if any of this stalls

You do not need Vercel to share the dashboard. In Preset: **Settings → Users → Invite**, add the reviewer's email as a **Viewer**, and send them the dashboard URL directly. It takes two minutes, requires no code, and asks them to accept an invite.

It is less polished than a public link. It is also impossible to get wrong, which matters more on a deadline.
