/**
 * OAuth configuration for the services Illusory can act through.
 *
 * The client secrets live here, on the server, and never reach the Mac app. A
 * distributed desktop binary cannot keep a secret — anyone can pull it out in a
 * minute — so the code-for-token exchange happens in this Vercel function and only
 * the finished user token is handed back to the app.
 */

export type ProviderName = "slack" | "notion" | "github";

export interface Provider {
  authorizeUrl: string;
  tokenUrl: string;
  clientId: () => string | undefined;
  clientSecret: () => string | undefined;
  /** Extra params on the consent URL — scopes differ in shape per provider. */
  authorizeParams: Record<string, string>;
  /** Basic-auth the token request instead of posting credentials in the body. */
  basicAuth?: boolean;
  /** Pull the user token and a human label out of the token response. */
  extract: (body: any) => Promise<{ token?: string; account?: string }>;
}

export const SITE =
  process.env.ILLUSORY_SITE ?? "https://illusory.fulmina.re";

export const providers: Record<ProviderName, Provider> = {
  slack: {
    authorizeUrl: "https://slack.com/oauth/v2/authorize",
    tokenUrl: "https://slack.com/api/oauth.v2.access",
    clientId: () => process.env.SLACK_CLIENT_ID,
    clientSecret: () => process.env.SLACK_CLIENT_SECRET,
    authorizeParams: {
      // User scopes, not bot scopes: Illusory acts as you, so messages come from
      // your account and it can see the channels you can already see.
      user_scope:
        "channels:history,groups:history,chat:write,files:write,search:read,users:read",
    },
    extract: async (body) => ({
      token: body?.authed_user?.access_token,
      account: body?.team?.name,
    }),
  },

  notion: {
    authorizeUrl: "https://api.notion.com/v1/oauth/authorize",
    tokenUrl: "https://api.notion.com/v1/oauth/token",
    clientId: () => process.env.NOTION_CLIENT_ID,
    clientSecret: () => process.env.NOTION_CLIENT_SECRET,
    authorizeParams: { owner: "user", response_type: "code" },
    basicAuth: true,
    extract: async (body) => ({
      token: body?.access_token,
      account: body?.workspace_name ?? body?.owner?.user?.name,
    }),
  },

  github: {
    authorizeUrl: "https://github.com/login/oauth/authorize",
    tokenUrl: "https://github.com/login/oauth/access_token",
    clientId: () => process.env.GITHUB_CLIENT_ID,
    clientSecret: () => process.env.GITHUB_CLIENT_SECRET,
    authorizeParams: { scope: "repo read:user gist" },
    extract: async (body) => {
      const token = body?.access_token;
      if (!token) return {};
      // GitHub's token response carries no identity, so ask who it belongs to.
      const res = await fetch("https://api.github.com/user", {
        headers: { Authorization: `Bearer ${token}`, "User-Agent": "Illusory" },
      });
      const user = res.ok ? await res.json() : null;
      return { token, account: user?.login };
    },
  },
};

export function redirectUri(provider: ProviderName) {
  return `${SITE}/api/auth/${provider}/callback`;
}

/** Everything the app understands comes back on this scheme. */
export function appCallback(params: Record<string, string>) {
  const query = new URLSearchParams(params).toString();
  return `illusory://auth?${query}`;
}
