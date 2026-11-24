# DezPMS architecture (read when needed)

## Stack

Frappe v16 + `payments`. React 19 SPA at `/DezPMS`. MariaDB. Optional
ERPNext / Frappe HR on the same site — not a dependency.

```
Staff UI / REST token / Claude / copilot
        │
        ▼
DezPMS.<module>.<fn>   @whitelist + @require_roles
        │
        ▼
pricing · folio ledger · availability · policy
        │
        ▼
MariaDB  +  Agent Action Log
```

## MCP

- Hosted: `POST /mcp` Streamable HTTP, JSON-RPC 2.0, Bearer from OAuth 2.1
  (PKCE S256, scope `DezPMS.mcp`, grant = user + property).
- Versions: `2025-11-25`, `2025-03-26`, `2024-11-05`.
- Methods: `initialize`, `ping`, `tools/list`, `tools/call`.
- `call_tool` sets `frappe.flags.DezPMS_agent_call` (skips cashier PIN;
  identity is the OAuth user) and logs `mcp_<name>` when mutating.
- Stdio: `mcp/DezPMS_mcp.py` with `DezPMS_URL` + API key. Same `TOOLS` list.
- Connect UI: **DezPMS Agent → Connect your AI**. Localhost/`http` disables
  Connect Claude (Anthropic cannot reach you).

Registry: `DezPMS/mcp_tools.py` (`TOOLS`, `GROUP_MODULE`, `TOOL_COUNT`).
Docs: `docs-site/gen_mcp_tools.py` → `mcp-tools.md`.

## REST

`POST /api/method/DezPMS.<module>.<fn>`
`Authorization: token <api_key>:<api_secret>`

Response `{ "message": <value> }`. Generate keys on Developers or
Connect your AI (role-scoped). Regenerators: `docs-site/gen_api.py`.

Webhooks: `DezPMS.payments.razorpay_webhook`,
`DezPMS.channel_manager.webhook`, `DezPMS.whatsapp.webhook`.

## Stay lifecycle

Quote → book (desk `create_booking` / public `public_api.book`) →
optional hold / host approve → pre-check-in token → check-in (folio
opens) → charges/payments/POS/HK → night audit → check-out → close
folio (invoice number assigned once).

Instant public book snapshots the payment policy. Request-to-book does
not hold inventory until confirmed.

## Hard money rules

- Rate guardrails: `set_room_rate` cannot leave the owner's floor/ceiling.
- Hurdle rates: demand premium + minimum sell rate by occupancy.
- Folios are append-only (Guest / Deposit / AR / Package). Voids are
  reversals. Close requires zero balance (or part-settle).
- Cashier: open session + optional PIN for humans; agents bypass PIN
  and stay on the activity log.
- Localization pack picks tax split and currency words. India GST slabs
  are per night from the tariff.

## Local bench (this workspace)

```
# containers
cd /Users/azzax/Workspace/agenticpms/frappe_docker
docker compose -f .devcontainer/docker-compose.yml -p DezPMS-dev up -d

# Frappe :8000
docker exec -d -w /workspace/development/frappe-bench DezPMS-dev-frappe-1 \
  bash -c "bench serve --port 8000 >> /tmp/bench-serve.log 2>&1"

# SPA :5173
cd /Users/azzax/Workspace/agenticpms/DezPMS/frontend && npm run dev
```

| Surface | URL |
| --- | --- |
| Vite SPA | http://localhost:5173 |
| Frappe | http://DezPMS.localhost:8000 |
| Public demo | https://demo.DezPMSpms.com/DezPMS |
| Nightly | https://nightly.DezPMSpms.com |

Demo users are seeded (`DezPMS.scripts.seed_users`) and printed on the
demo login screen. Do not use the playground as a live hotel.

```
bench --site DezPMS.localhost migrate
bench --site DezPMS.localhost execute DezPMS.scripts.seed_demo.execute
```

## Scheduler (hooks.py)

Hourly ARI push; 03:00 night audit; 09:00 pre-arrival links; every 15 min
HK escalation + hold expiry; 08:30 banquet reminders; 04:15 demo reset
(no-op unless `DezPMS_demo_mode`).

## Related docs in-repo

- `CONTRIBUTING.md` — branches, commits, PR gates
- `RELEASING.md` — patch-first trains
- `docs-dev.md` — local Docker notes (some version labels lag)
- `docs-site/` — what we publish to DezPMSpms.com/docs
