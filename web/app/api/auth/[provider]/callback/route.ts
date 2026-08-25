import { NextRequest, NextResponse } from "next/server";
import {
  appCallback,
  providers,
  ProviderName,
  redirectUri,
} from "@/lib/providers";

/**
 * Exchanges the authorisation code for a token and hands it to the app.
 *
 * This is the only place a client secret is ever used. The response is a small
 * HTML page rather than a bare redirect, because a `illusory://` redirect issued
 * by a server is blocked by most browsers — the hand-off has to be initiated by
 * the page itself, and the user needs something to look at if it doesn't fire.
 */
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ provider: string }> },
) {
  const { provider } = await params;
  const config = providers[provider as ProviderName];
  if (!config) {
    return NextResponse.json({ error: "Unknown provider" }, { status: 404 });
  }

  const query = request.nextUrl.searchParams;
  const state = query.get("state") ?? "";

  const denied = query.get("error");
  if (denied) {
    return handoff(provider, { provider, state, error: denied });
  }

  const code = query.get("code");
  if (!code) {
    return handoff(provider, { provider, state, error: "no_code" });
  }

  const clientId = config.clientId();
  const clientSecret = config.clientSecret();
  if (!clientId || !clientSecret) {
    return handoff(provider, { provider, state, error: "not_configured" });
  }

  const headers: Record<string, string> = {
    "Content-Type": "application/x-www-form-urlencoded",
    Accept: "application/json",
  };
  const body: Record<string, string> = {
    grant_type: "authorization_code",
    code,
    redirect_uri: redirectUri(provider as ProviderName),
  };

  if (config.basicAuth) {
    const credentials = Buffer.from(`${clientId}:${clientSecret}`).toString("base64");
    headers.Authorization = `Basic ${credentials}`;
  } else {
    body.client_id = clientId;
    body.client_secret = clientSecret;
  }

  let extracted: { token?: string; account?: string } = {};
  try {
    const response = await fetch(config.tokenUrl, {
      method: "POST",
      headers,
      body: new URLSearchParams(body).toString(),
    });
    const json = await response.json();
    extracted = await config.extract(json);
  } catch {
    return handoff(provider, { provider, state, error: "exchange_failed" });
  }

  if (!extracted.token) {
    return handoff(provider, { provider, state, error: "no_token" });
  }

  return handoff(provider, {
    provider,
    state,
    token: extracted.token,
    account: extracted.account ?? "Connected",
  });
}

function handoff(provider: string, params: Record<string, string>) {
  const target = appCallback(params);
  const ok = !params.error;
  const title = ok ? `${label(provider)} connected` : `Couldn't connect ${label(provider)}`;
  const message = ok
    ? "You can close this tab and go back to Illusory."
    : `Something went wrong: ${params.error}. Try again from Illusory's settings.`;

  return new NextResponse(page(title, message, ok ? target : null), {
    headers: { "Content-Type": "text/html; charset=utf-8" },
  });
}

function label(provider: string) {
  return provider.charAt(0).toUpperCase() + provider.slice(1);
}

function page(title: string, message: string, target: string | null) {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title} · Illusory</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Geist:wght@350;400&display=swap" rel="stylesheet">
<style>
  :root { color-scheme: dark; }
  body {
    margin: 0; min-height: 100vh; display: grid; place-items: center;
    background: #08080a; color: #f4f4f5;
    font-family: Geist, -apple-system, BlinkMacSystemFont, sans-serif; font-weight: 400;
  }
  main { text-align: center; padding: 32px; max-width: 30rem; }
  h1 { font-weight: 350; font-size: 1.5rem; margin: 1.5rem 0 0.5rem; }
  p { color: #a1a1aa; font-size: 0.95rem; line-height: 1.6; margin: 0; }
  a { color: #f4f4f5; }
</style>
</head>
<body>
<main>
  <img src="/mark.svg" width="72" height="72" alt="">
  <h1>${title}</h1>
  <p>${message}</p>
</main>
${target ? `<script>location.href = ${JSON.stringify(target)};</script>` : ""}
</body>
</html>`;
}
