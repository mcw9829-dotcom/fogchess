# Security update 1 — v1.55

Game rules, board/piece art, UI layout, and normal gameplay polling are unchanged.

## Administrator access

Administrator APIs accept only `X-Admin-Key`. URL `key` and JSON body `key` no longer authenticate. Both existing Godot and classic administrator clients already use the header. The classic client discards old URL credentials instead of converting them to a header. API responses use `Cache-Control: no-store` and `Referrer-Policy: no-referrer`.

Five failed administrator attempts from one client lock it for ten minutes. The counter survives application restarts. Administrator traffic also has a 120-request/minute budget. Key rotation uses Fly Secrets over stdin; the key is never committed or passed as a process argument. A Windows DPAPI encrypted local recovery copy is kept outside the repository, in the desktop project's ignored `.dev-data/security/admin-key.dpapi`. The separate local copy helper decrypts only when the owner runs it.

## Request budgets

Budgets are persistent, atomic, anchored at the first accepted request, and do not extend when blocked. Denied requests return HTTP 429 with `Retry-After` and a message understood by existing clients.

| Endpoint | Budget |
|---|---|
| Login | 60 per IP / 5 minutes; 12 per normalized account name / 5 minutes |
| Signup | 10 per IP / hour |
| Recovery code | 5 per IP / 10 minutes |
| Password change, recovery reissue | Shared 20 per IP / 5 minutes; 10 per session / 5 minutes |
| Room join, spectator join | Shared 30 per IP / minute and 200 per IP / hour |
| Matchmaking join | 60 per IP / minute |
| Feedback submission | 6 per IP / minute, plus the existing cooldown |

These count accepted attempts, including successful ones. Shared-network users share the IP budget. State polling, move hints, actions, matchmaking status, leaving, and logout are not changed. Existing account password-failure limits remain in place in addition to the new persistent request budgets.

The SQLite store defaults to `security.sqlite3` beside the account DB. Fly explicitly places it at `/data/security.sqlite3`, on the existing volume. Subjects are SHA-256 digests; no raw IP, account name, password, or session token is stored. Expired rows are removed and active rows are capped at 20,000. Storage errors fail protected requests closed with 503 rather than bypassing limits. This design fits the current single-Machine deployment; multi-Machine scaling requires a shared limiter.

## Proxy boundary

Socket addresses are used by default. `X-Forwarded-For` is never trusted. On Fly, `FOG_TRUST_FLY_PROXY=1` plus the runtime `FLY_APP_NAME` permit `Fly-Client-IP` only from the exact IPv4 default gateway found in `/proc/net/route`. The server continues to bind IPv4. This matches the observed Fly Proxy peer and avoids trusting the entire private network. For other deployments an operator may explicitly set `FOG_TRUSTED_PROXY_CIDRS`.

Duplicate or invalid forwarded addresses fall back to the socket address. If adding a CDN or changing the listener/proxy topology, revalidate this boundary before changing trust configuration.

## Verification

`python -m pytest -q` includes real HTTP checks for header-only administrator authentication, persistent/concurrent budgets, expiry, spoofed headers, malformed bodies, successful account/room flows, and database failure handling.

Fog tests check hidden pieces and internal credentials are absent from player responses, `reveal=1` cannot reveal ordinary matches, enemy move hints remain unavailable, hidden occupancy does not alter candidate moves, live replay access is denied, and spectators receive only eligible delayed frames. Unauthorized actors cannot mutate pieces; a valid action still succeeds, and repeating it cannot advance the turn twice. Existing game-rule, settlement, bush visibility, spectator, and replay tests remain in the full suite.

This is a bounded first update, not a complete security audit or DDoS defense. Short-lived administrator sessions, password-hash migration, hashed account sessions, and backup/restore automation remain later work.
