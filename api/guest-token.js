// Vercel serverless function: GET /api/guest-token
// Returns a short-lived (5 min) Preset guest token that can view ONE dashboard.
// Secrets stay here on the server; the browser only ever sees the guest token.
//
// Env vars (Vercel -> Project -> Settings -> Environment Variables):
//   PRESET_API_TOKEN      API key name   (Preset Manager -> API Keys)
//   PRESET_API_SECRET     API key secret
//   PRESET_TEAM           team slug      (in Preset Manager URLs)
//   PRESET_WORKSPACE      workspace slug (first part of the workspace URL)
//   PRESET_DASHBOARD_ID   embedded dashboard UUID (from the dashboard's Embed dialog)

const PRESET_API = "https://api.app.preset.io/v1";

// Reuse the Preset access token while the function instance is warm.
let cached = { jwt: null, expiresAt: 0 };

async function getPresetAccessToken() {
  if (cached.jwt && Date.now() < cached.expiresAt) return cached.jwt;

  const res = await fetch(`${PRESET_API}/auth/`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      name: process.env.PRESET_API_TOKEN,
      secret: process.env.PRESET_API_SECRET,
    }),
  });
  if (!res.ok) throw new Error(`Preset auth failed (${res.status})`);

  const body = await res.json();
  cached = {
    jwt: body.payload.access_token,
    expiresAt: Date.now() + 60 * 60 * 1000, // access tokens last a few hours; refresh hourly
  };
  return cached.jwt;
}

module.exports = async (req, res) => {
  try {
    const { PRESET_TEAM, PRESET_WORKSPACE, PRESET_DASHBOARD_ID } = process.env;
    const jwt = await getPresetAccessToken();

    const tokenRes = await fetch(
      `${PRESET_API}/teams/${PRESET_TEAM}/workspaces/${PRESET_WORKSPACE}/guest-token/`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${jwt}` },
        body: JSON.stringify({
          user: { username: "clever-reviewer", first_name: "Clever", last_name: "Reviewer" },
          resources: [{ type: "dashboard", id: PRESET_DASHBOARD_ID }],
          rls: [],
        }),
      }
    );
    if (!tokenRes.ok) {
      throw new Error(`Guest token request failed (${tokenRes.status}): ${await tokenRes.text()}`);
    }

    const body = await tokenRes.json();
    const token = body?.data?.payload?.token ?? body?.payload?.token;
    if (!token) throw new Error("Guest token missing from Preset response");

    res.setHeader("Cache-Control", "no-store");
    res.status(200).json({ token });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
};
