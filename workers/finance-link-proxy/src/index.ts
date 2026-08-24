/**
 * Finance link proxy — Coinbase OAuth behind server-side secrets.
 * Tokens returned to the macOS client are AES-GCM wrapped with WRAP_KEY.
 */

export interface Env {
  COINBASE_CLIENT_ID: string;
  COINBASE_CLIENT_SECRET: string;
  WRAP_KEY: string;
  APP_ATTEST_HEADER?: string;
  COINBASE_REDIRECT_URI?: string;
}

const RATE_WINDOW_MS = 60_000;
const RATE_MAX = 60;
const rateBuckets = new Map<string, { count: number; resetAt: number }>();

function checkRateLimit(ip: string): Response | null {
  const now = Date.now();
  let bucket = rateBuckets.get(ip);
  if (!bucket || now >= bucket.resetAt) {
    bucket = { count: 0, resetAt: now + RATE_WINDOW_MS };
    rateBuckets.set(ip, bucket);
  }
  bucket.count += 1;
  if (bucket.count > RATE_MAX) {
    return json({ error: "rate_limit_exceeded" }, 429, {
      "Retry-After": String(Math.ceil((bucket.resetAt - now) / 1000)),
    });
  }
  return null;
}

async function importWrapKey(raw: string): Promise<CryptoKey> {
  const bytes = Uint8Array.from(atob(raw.trim()), (c) => c.charCodeAt(0));
  if (bytes.length !== 32) {
    throw new Error("WRAP_KEY must decode to 32 bytes (AES-256)");
  }
  return crypto.subtle.importKey("raw", bytes, "AES-GCM", false, ["encrypt", "decrypt"]);
}

function b64(bytes: ArrayBuffer | Uint8Array): string {
  const u8 = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let s = "";
  for (const b of u8) s += String.fromCharCode(b);
  return btoa(s);
}

function unb64(s: string): Uint8Array {
  const bin = atob(s.trim());
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function wrapToken(env: Env, plaintext: string): Promise<string> {
  const key = await importWrapKey(env.WRAP_KEY);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, new TextEncoder().encode(plaintext));
  const packed = new Uint8Array(iv.length + ct.byteLength);
  packed.set(iv, 0);
  packed.set(new Uint8Array(ct), iv.length);
  return b64(packed);
}

async function unwrapToken(env: Env, wrapped: string): Promise<string> {
  const key = await importWrapKey(env.WRAP_KEY);
  const packed = unb64(wrapped);
  if (packed.length < 13) throw new Error("invalid wrapped token");
  const iv = packed.slice(0, 12);
  const ct = packed.slice(12);
  const pt = await crypto.subtle.decrypt({ name: "AES-GCM", iv }, key, ct);
  return new TextDecoder().decode(pt);
}

function json(body: unknown, status = 200, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...extra },
  });
}

function clientIP(request: Request): string {
  return request.headers.get("CF-Connecting-IP") ?? request.headers.get("X-Forwarded-For")?.split(",")[0]?.trim() ?? "unknown";
}

function requireAttest(request: Request, env: Env): Response | null {
  if (!env.APP_ATTEST_HEADER) return null;
  const got = request.headers.get("X-College-Attest");
  if (got !== env.APP_ATTEST_HEADER) {
    return json({ error: "unauthorized" }, 401);
  }
  return null;
}

async function readJSON<T = Record<string, unknown>>(request: Request): Promise<T> {
  try {
    return (await request.json()) as T;
  } catch {
    throw new HttpError(400, "invalid_json");
  }
}

class HttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

async function resolveAccessToken(env: Env, body: { access_token?: string; wrapped_access_token?: string }): Promise<string> {
  if (body.wrapped_access_token) return unwrapToken(env, body.wrapped_access_token);
  if (body.access_token) return body.access_token;
  throw new HttpError(400, "missing_access_token");
}

interface CoinbaseAccountDTO {
  uuid: string;
  name: string;
  currency: string;
  balance: number;
  payloadJSON?: string;
}

interface CoinbaseTransactionDTO {
  externalID: string;
  accountUUID: string;
  title: string;
  amount: number;
  currency: string;
  transactionType: "income" | "expense";
  date: string;
  payloadJSON?: string;
}

interface CoinbaseSyncSnapshot {
  accounts: CoinbaseAccountDTO[];
  transactions: CoinbaseTransactionDTO[];
}

const COINBASE_AUTH = "https://www.coinbase.com/oauth/authorize";
const COINBASE_TOKEN = "https://api.coinbase.com/oauth/token";
const COINBASE_API = "https://api.coinbase.com";

function coinbaseRedirectUri(request: Request, env: Env): string {
  if (env.COINBASE_REDIRECT_URI) return env.COINBASE_REDIRECT_URI;
  const url = new URL(request.url);
  return `${url.origin}/coinbase/callback`;
}

async function handleCoinbaseAuthorize(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const state = url.searchParams.get("state") ?? crypto.randomUUID();
  const redirectUri = url.searchParams.get("redirect_uri") ?? coinbaseRedirectUri(request, env);
  const scope =
    url.searchParams.get("scope") ??
    "wallet:accounts:read,wallet:transactions:read,wallet:user:read,offline_access";

  const auth = new URL(COINBASE_AUTH);
  auth.searchParams.set("response_type", "code");
  auth.searchParams.set("client_id", env.COINBASE_CLIENT_ID);
  auth.searchParams.set("redirect_uri", redirectUri);
  auth.searchParams.set("scope", scope);
  auth.searchParams.set("state", state);

  return Response.redirect(auth.toString(), 302);
}

async function handleCoinbaseCallback(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  const err = url.searchParams.get("error");
  const appRedirect = url.searchParams.get("app_redirect") ?? "college://finance/coinbase/callback";

  if (err) {
    return Response.redirect(`${appRedirect}?error=${encodeURIComponent(err)}&state=${encodeURIComponent(state ?? "")}`, 302);
  }
  if (!code) throw new HttpError(400, "missing_code");

  const redirectUri = coinbaseRedirectUri(request, env);
  const tokenRes = await fetch(COINBASE_TOKEN, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      grant_type: "authorization_code",
      code,
      client_id: env.COINBASE_CLIENT_ID,
      client_secret: env.COINBASE_CLIENT_SECRET,
      redirect_uri: redirectUri,
    }),
  });
  const tokenData = (await tokenRes.json()) as {
    access_token?: string;
    refresh_token?: string;
    expires_in?: number;
    error?: string;
  };
  if (!tokenRes.ok || !tokenData.access_token) {
    throw new HttpError(tokenRes.status, tokenData.error ?? "coinbase_token_error");
  }

  const wrappedAccess = await wrapToken(env, tokenData.access_token);
  const wrappedRefresh = tokenData.refresh_token ? await wrapToken(env, tokenData.refresh_token) : undefined;

  const dest = new URL(appRedirect);
  dest.searchParams.set("state", state ?? "");
  dest.searchParams.set("wrapped_access_token", wrappedAccess);
  if (wrappedRefresh) dest.searchParams.set("wrapped_refresh_token", wrappedRefresh);
  if (tokenData.expires_in != null) dest.searchParams.set("expires_in", String(tokenData.expires_in));

  return Response.redirect(dest.toString(), 302);
}

async function coinbaseGet(accessToken: string, path: string): Promise<unknown> {
  const res = await fetch(`${COINBASE_API}${path}`, {
    headers: { Authorization: `Bearer ${accessToken}`, Accept: "application/json" },
  });
  const data = await res.json();
  if (!res.ok) {
    const msg = (data as { errors?: { message?: string }[] }).errors?.[0]?.message ?? "coinbase_api_error";
    throw new HttpError(res.status, msg);
  }
  return data;
}

async function handleCoinbaseSync(request: Request, env: Env): Promise<Response> {
  const body = await readJSON<{ wrapped_access_token?: string; access_token?: string }>(request);
  const accessToken = await resolveAccessToken(env, body);

  const accountsResp = (await coinbaseGet(accessToken, "/v2/accounts?limit=100")) as {
    data: Record<string, unknown>[];
  };

  const snapshot: CoinbaseSyncSnapshot = { accounts: [], transactions: [] };

  for (const row of accountsResp.data ?? []) {
    const bal = row.balance as Record<string, unknown> | undefined;
    const currency = String(bal?.currency ?? "");
    const amount = Number(bal?.amount ?? 0);
    const uuid = String(row.id ?? row.uuid ?? "");

    snapshot.accounts.push({
      uuid,
      name: String(row.name ?? currency),
      currency,
      balance: amount,
      payloadJSON: JSON.stringify(row),
    });

    const txResp = (await coinbaseGet(accessToken, `/v2/accounts/${uuid}/transactions?limit=50`)) as {
      data: Record<string, unknown>[];
    };
    for (const tx of txResp.data ?? []) {
      const txAmount = Number((tx.amount as Record<string, unknown>)?.amount ?? 0);
      const txCurrency = String((tx.amount as Record<string, unknown>)?.currency ?? currency);
      snapshot.transactions.push({
        externalID: `coinbase:${tx.id ?? tx.resource_path}`,
        accountUUID: uuid,
        title: String(tx.type ?? "transaction"),
        amount: Math.abs(txAmount),
        currency: txCurrency,
        transactionType: txAmount >= 0 ? "income" : "expense",
        date: String(tx.created_at ?? ""),
        payloadJSON: JSON.stringify(tx),
      });
    }
  }

  return json({ snapshot });
}

async function handleCoinbaseRevoke(request: Request, env: Env): Promise<Response> {
  const body = await readJSON<{ wrapped_access_token?: string; access_token?: string }>(request);
  const accessToken = await resolveAccessToken(env, body);

  const res = await fetch(COINBASE_TOKEN + "/revoke", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ token: accessToken }),
  });
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    const msg = (data as { error?: string }).error ?? "coinbase_revoke_failed";
    throw new HttpError(res.status, msg);
  }
  return json({ revoked: true });
}

type Handler = (request: Request, env: Env) => Promise<Response>;

const routes: Record<string, Record<string, Handler>> = {
  POST: {
    "/coinbase/sync": handleCoinbaseSync,
    "/coinbase/revoke": handleCoinbaseRevoke,
  },
  GET: {
    "/coinbase/authorize": handleCoinbaseAuthorize,
    "/coinbase/callback": handleCoinbaseCallback,
  },
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, X-College-Attest",
        },
      });
    }

    const limited = checkRateLimit(clientIP(request));
    if (limited) return limited;

    const attest = requireAttest(request, env);
    if (attest) return attest;

    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";

    if (path === "/" && request.method === "GET") {
      return json({ service: "finance-link-proxy", status: "ok", providers: ["coinbase"] });
    }

    const handler = routes[request.method]?.[path];
    if (!handler) {
      return json({ error: "not_found", path }, 404);
    }

    try {
      return await handler(request, env);
    } catch (e) {
      if (e instanceof HttpError) {
        return json({ error: e.message }, e.status);
      }
      console.error(e);
      return json({ error: "internal_error" }, 500);
    }
  },
};
