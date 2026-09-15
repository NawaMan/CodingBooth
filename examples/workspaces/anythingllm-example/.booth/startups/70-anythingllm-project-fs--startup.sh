#!/bin/bash
set -e
# Configured by: booth config --no-tui --overwrite --select shell-history/anythingllm+expose+autostart+project-fs+passwordless

# filesystem-agent is not a default skill. Without it, @agent only has
# document/RAG tools and "list files" reports an empty workspace.
PORT=${ANYTHINGLLM_PORT:-3001}
export PORT
(
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    curl -fsS --max-time 2 "http://127.0.0.1:$PORT/api/ping" >/dev/null 2>&1 && break
    sleep 2
  done
  node -e '
const http = require("http");
const port = process.env.PORT || process.argv[1] || "3001";
function req(method, path, body) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const opts = { hostname: "127.0.0.1", port, path, method, headers: {} };
    if (data) {
      opts.headers["Content-Type"] = "application/json";
      opts.headers["Content-Length"] = Buffer.byteLength(data);
    }
    const r = http.request(opts, (res) => {
      let b = "";
      res.on("data", (c) => (b += c));
      res.on("end", () => {
        try { resolve(JSON.parse(b || "{}")); } catch { resolve({}); }
      });
    });
    r.on("error", reject);
    if (data) r.write(data);
    r.end();
  });
}
(async () => {
  const cur = await req("GET", "/api/admin/system-preferences-for?labels=default_agent_skills");
  let skills = (cur.settings && cur.settings.default_agent_skills) || [];
  if (!Array.isArray(skills)) skills = [];
  if (!skills.includes("filesystem-agent")) skills.push("filesystem-agent");
  await req("POST", "/api/admin/system-preferences", { default_agent_skills: skills.join(",") });
  console.log("AnythingLLM project-fs: filesystem-agent skill enabled");
})().catch((e) => console.log("AnythingLLM project-fs: could not enable skill:", e.message));
' "$PORT"
) >/tmp/anythingllm-project-fs.log 2>&1 &
echo "AnythingLLM project-fs: enabling filesystem-agent in the background (log: /tmp/anythingllm-project-fs.log)"
