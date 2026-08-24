# finance-link-proxy

Cloudflare Worker that proxies **Coinbase OAuth** so API secrets never ship in the macOS app. Access tokens returned to the client are **AES-256-GCM wrapped** with `WRAP_KEY`.

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/coinbase/authorize` | Redirect to Coinbase OAuth |
| GET | `/coinbase/callback` | Exchange code → wrapped tokens → app redirect |
| POST | `/coinbase/sync` | Fetch normalized account/transaction snapshot |
| POST | `/coinbase/revoke` | Revoke OAuth token |

## Secrets (wrangler)

| Name | Required | Description |
| --- | --- | --- |
| `COINBASE_CLIENT_ID` | yes | Coinbase OAuth client ID |
| `COINBASE_CLIENT_SECRET` | yes | Coinbase OAuth client secret |
| `WRAP_KEY` | yes | Base64-encoded 32-byte AES key for token wrapping |
| `APP_ATTEST_HEADER` | no | If set, requests must include matching `X-College-Attest` |
| `COINBASE_REDIRECT_URI` | no | Override OAuth callback URL (defaults to worker `/coinbase/callback`) |

## Local dev

```bash
cd workers/finance-link-proxy
cp .dev.vars.example .dev.vars   # fill in secrets
npm install
npm run dev
```

Configure the proxy URL in College → Settings → Finance → Connections.

## Coinbase OAuth setup

1. Create an OAuth application in the [Coinbase Developer Portal](https://www.coinbase.com/cloud).
2. Set redirect URI to `https://<your-worker>/coinbase/callback`.
3. Request view-only scopes: `wallet:accounts:read`, `wallet:transactions:read`, `wallet:user:read`, `offline_access`.
