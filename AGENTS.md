# BUMP agent instructions

Read [.agents/00-start-here.md](.agents/00-start-here.md) before working in this
repo, then read the relevant area note listed in [.agents/README.md](.agents/README.md).
The area notes record design decisions, current commands, and known limits.
Check the current code and branch state before relying on historical status
entries. Update the relevant note and append a factual entry to
`.agents/90-worklog.md` after meaningful changes.

Never place API keys or tokens in the repo. User instructions for the current
task take precedence over historical workflow notes.


## BUMP server URL (keep the app's default current)

The backend runs on the Mac and is exposed through a Cloudflare quick tunnel.
The tunnel URL changes every time `cloudflared` restarts, and the app's
default server lives in the build setting `BUMP_API_BASE_URL`
(`ios/UWBBumpTest.xcodeproj/project.pbxproj`, Debug and Release).

Whenever the server is down or the tunnel has restarted:

1. Start both, each in its own terminal:
   ```sh
   cd backend && npm start
   cloudflared tunnel --protocol http2 --url http://localhost:8787
   ```
2. Copy the new `https://<name>.trycloudflare.com` URL the tunnel prints.
3. Replace BOTH `BUMP_API_BASE_URL` values in `project.pbxproj` with it.
4. Check it: `curl https://<name>.trycloudflare.com/healthz` should show
   `"grokConfigured":true,"relay":true`.
5. Tell the user to rebuild and reinstall (or set the Server URL override in
   Testing tools on each phone).

The xAI key is in `backend/.env` (git-ignored). Never commit it.
