<p align="center">
  <img src="assets/illusory-mark.svg" width="132" alt="Illusory">
</p>

<h1 align="center">Illusory</h1>
<p align="center">One key. AI finishes what you started.</p>

---

Press one key, anywhere on your Mac. Illusory looks at what you're doing and does
the rest.

- Rename two files the way you like them → it renames the other forty-eight.
- Type *"logo's attached"* in Slack → the logo gets attached.
- Paste a mess of data → it turns into a table.

No chat window, no prompt to write. You already showed it what you wanted by doing
the first bit yourself.

## The one rule

> If it takes longer than a second, it's not Illusory's job.

Latency ceiling and scope ceiling are the same ceiling. One second of compute is
about thirty seconds of your own work, and that is the largest thing Illusory will
ever do. It is not here to run your projects.

This is the product, not a limitation. Trust scales inversely with scope: a tool
that does one small step is verifiable at a glance, which is why you keep using it.

## The gesture

**Hold** to preview — Illusory reads context and shows what it is about to do.
**Release** to commit. **Escape** to abort. The sweep animation is not decoration;
it is the window in which you can still say no.

## No account

Illusory has no sign-in and no OAuth of its own. The secrets in `.env` authorise
Illusory against *your* workspaces, and only when you choose to connect one.

## Running it

```bash
cd app && swift run
```

Then hold **⌥Space**. The mark appears in the menu-bar strip beside the notch.

## Layout

| Path | What |
| --- | --- |
| `app/` | The macOS app (SwiftUI + AppKit, agent app — no dock icon) |
| `assets/logo_gen.py` | The mark, generated parametrically |
| `assets/*.svg` | Emitted mark set: primary, small, mono, favicon |

## Phases

1. **Core** — hotkey, context capture, intent inference, executors for files, text
   and terminal. The one-second rule enforced from day one.
2. **Integrations** — Notion, Slack, GitHub.
3. **Ship** — notarized build, landing page, launch.
