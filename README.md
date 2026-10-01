# server-host.eu Discord runtime

This is the persistent Node.js + discord.js service for the iOS builder. It verifies incoming bot credentials, encrypts each bot token with AES-256-GCM before writing it to the server-only `bot_secrets` table, runs Discord gateway clients, registers enabled slash commands, executes saved workflow steps, and stores logs/status in Supabase. The server never returns bot tokens to clients. The iOS client sends a bot token only once over HTTPS while connecting it; the app does not save it locally.

## One-time Supabase setup

1. In the Supabase dashboard for the configured project, open **SQL Editor** and run `supabase/schema.sql`.
2. Enable **Apple** under Authentication providers and configure the Apple Services ID / bundle ID, team ID, key ID and private key according to Supabase's Apple provider instructions. Keep the Apple private key in Supabase only.
3. Copy the Supabase **service-role secret** from Project Settings → API Keys into the Node host's secret environment as `SUPABASE_SERVICE_ROLE_KEY`. It is not a publishable key; never put it in the iOS app or commit it.
4. Generate a separate server-only encryption key using `openssl rand -base64 32` and set it as `BOT_TOKEN_ENCRYPTION_KEY`. Keep a protected backup: changing or losing it makes existing encrypted bot credentials unreadable.

The schema enables RLS and owner policies for user data. The `bot_secrets` table deliberately grants no access to `anon` or `authenticated`; only the server's service-role client reads/writes it, and every server operation first verifies the Supabase access token and scopes queries to that owner.

## Persistent hosting

Deploy the entire `server-host-backend` folder to a Node.js 20+ host that runs a long-lived process (not static hosting or a short-lived serverless function). Configure the environment variables from `.env.example` in the host's secret manager, install dependencies with `npm install`, and start with `npm start`. Put the service behind HTTPS and use the host's process supervisor / always-on setting so it restarts after a host restart. The runtime restores bots marked desired-online when the process starts. `GET /api/health` is an unauthenticated liveness check.

After deploying, update `apiBaseURL` in the iOS client to the service's HTTPS origin. The current project has not been deployed to a Node host because no persistent host was selected or provided.

## API routes

All routes below `/api` except `/api/health` require `Authorization: Bearer <Supabase access token>`.

- `POST /api/discord/validate` — accepts `{ "bot_token": "..." }`, calls Discord's current-user API, and returns bot profile metadata only.
- `GET /api/bots` — returns the signed-in owner's bot projects and command workflows.
- `POST /api/bots` — accepts `{ "bot": <project>, "bot_token": "..." }`, revalidates ownership against Discord, encrypts and stores the token, and returns the token-free project.
- `PUT /api/bots/:id` — saves bot settings, commands, and workflow steps.
- `POST /api/bots/:id/action` — accepts `{ "action": "start" | "stop" | "restart" }`.
- `GET /api/bots/:id/status` and `GET /api/bots/:id/logs` — return owner-scoped runtime state and recent event records.
- `DELETE /api/bots/:id` — stops the runtime, then cascades project, secret, workflow, variable, status, and log removal.

The runtime requests Discord's `Guilds` and `GuildMembers` intents. Set the corresponding bot intent in Discord Developer Portal, and invite the bot with the permissions required by the workflow actions you use. HTTP Request steps require HTTPS and block private/local IP destinations.
