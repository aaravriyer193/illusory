<p align="center">
  <img src="assets/illusory-mark.svg" width="120" alt="Illusory">
</p>

<h1 align="center">Illusory</h1>
<p align="center">Autocomplete for everything that isn't typing.</p>

<p align="center">
  <a href="https://illusory.fulmina.re">illusory.fulmina.re</a> ·
  <a href="https://github.com/aaravriyer193/illusory/releases/latest">Download</a>
</p>

---

You rename two files by date. You press **⌥ Space**. Illusory renames the other
forty-eight.

There is no chat window and no prompt to write. It looks at what you were already
doing — the file you just changed, the sentence you just typed, what you copied a
moment ago — and does the next small thing.

## Install

1. Download **Illusory.zip** from [the latest release](https://github.com/aaravriyer193/illusory/releases/latest).
2. Unzip it and drag **Illusory.app** into your Applications folder.
3. Open it. It lives in your menu bar — there is no dock icon and no window.

The first launch asks for two permissions. Illusory cannot work without either,
and macOS will not let it ask twice, so it is worth granting both when prompted:

| Permission | Why |
| --- | --- |
| **Accessibility** | To read the window, the focused field and the buttons on screen — and to type and click for you |
| **Screen Recording** | To see what you are looking at |

If you miss a prompt, both live in **System Settings → Privacy & Security**.

## Using it

Press **⌥ Space**.

- **Tap** and Illusory just goes.
- **Hold** and it shows you exactly what it is about to do — the real command, the
  real list of renames — and runs it when you let go.

Anything destructive always waits for a hold, never a tap. While it is working the
mark in your menu bar spins and becomes a **stop button**: one click cancels.

### Things it does

- Rename, move, copy and organise files
- Fill in fields, finish sentences, rewrite a selection
- Click buttons and links in any app
- Run a shell command
- Turn a pasted mess into a table

If it isn't sure, it says *"Nothing obvious to finish"* and does nothing. That is
on purpose: guessing wrong is worse than doing nothing.

## Settings

Click the mark in the menu bar → **Connections & Settings**.

**Model.** *Default* is a fast hosted model and needs no setup. Choose **Ollama**
to run everything on your own machine instead — nothing leaves your Mac at all,
not even the screenshot. You will need [Ollama](https://ollama.com) running with a
vision model such as `qwen2.5vl:7b`.

**Connections.** Slack, Notion and GitHub. Connecting opens a normal consent page
in your browser; the token is stored in your Mac's Keychain. Illusory has no
account of its own and there is nothing to sign up for.

**Gesture.** How long a hold has to be before it counts as a hold rather than a
tap.

## What it can see, and what it keeps

Illusory only looks when you press the key. It reads the frontmost window, the
focused field, your clipboard, what changed recently in the folder you are working
in, and a screenshot of your screen.

None of it is stored. There is no history, no account and no server belonging to
Illusory that your context passes through — the only thing that leaves your Mac is
one model request, and on Ollama not even that.

## Building it yourself

```bash
./scripts/bundle.sh && open build/Illusory.app
```

Needs Xcode command line tools and an `OPENROUTER_API_KEY` in `.env` (see
`.env.example`). `scripts/release.sh` produces the signed, zipped build that ships.

The website and the OAuth broker live in [`web/`](web/README.md).
