# illusory.fulmina.re

The landing page, and the OAuth broker the Mac app talks to.

The broker is not optional plumbing. A distributed desktop binary cannot keep a
secret — anyone can pull it out of the `.app` in a minute — so the client secrets
live here as server environment variables, and this site does the code-for-token
exchange. Only the finished user token goes back to the Mac, through the
`illusory://` URL scheme, straight into the Keychain.

It also solves Slack, which rejects `http://localhost` redirect URLs outright and
has no loopback exemption. With this site there is a real HTTPS callback, so all
three providers work for any user with nothing to paste.

## Deploy

```bash
vercel --cwd web
```

Then in Vercel → Project → Settings → Domains, add `illusory.fulmina.re`.

## Environment variables

Set these in Vercel → Project → Settings → Environment Variables, for Production
(and Preview if you want to test there). Nothing here belongs in the Mac app's
`.env` — these are Illusory's own credentials, not the user's.

| Variable | From |
| --- | --- |
| `SLACK_CLIENT_ID` | api.slack.com/apps → your app → Basic Information |
| `SLACK_CLIENT_SECRET` | same page, Show |
| `NOTION_CLIENT_ID` | notion.so/my-integrations → your integration → Secrets |
| `NOTION_CLIENT_SECRET` | same page |
| `GITHUB_CLIENT_ID` | github.com/settings/developers → OAuth Apps |
| `GITHUB_CLIENT_SECRET` | same page, Generate a new client secret |

`ILLUSORY_SITE` only needs setting if the site is not on
`https://illusory.fulmina.re`.

## Redirect URIs to register

Each provider needs its callback registered, or consent fails before it starts.

| Provider | Where | Value |
| --- | --- | --- |
| Slack | OAuth & Permissions → Redirect URLs | `https://illusory.fulmina.re/api/auth/slack/callback` |
| Notion | Integration → OAuth Domain & URIs | `https://illusory.fulmina.re/api/auth/notion/callback` |
| GitHub | OAuth App → Authorization callback URL | `https://illusory.fulmina.re/api/auth/github/callback` |

Notion additionally requires a company name, homepage, privacy policy, terms and
support email before it will let an integration go public. The homepage is this
site; the rest still need writing.

## The flow

1. The app opens `/api/auth/<provider>/start?state=<nonce>`.
2. This site redirects to the provider's consent screen.
3. The provider returns to `/api/auth/<provider>/callback` with a code.
4. The callback exchanges it for a token using the secret, server-side.
5. It renders a page that redirects to
   `illusory://auth?provider=…&state=…&token=…&account=…`.
6. The app checks the nonce matches one it issued, then stores the token.

Step 6 is why the nonce exists: a callback Illusory did not ask for is ignored
rather than trusted.

## Local development

```bash
npm --prefix web run dev
```

Do not run `next build` while the dev server is up — both write to `.next` and
the dev server's chunks get clobbered.
