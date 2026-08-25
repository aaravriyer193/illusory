import { Mark } from "./components/Mark";
import { surfaces } from "./components/Logos";
import { useCases } from "./components/Scenes";
import { Reveal } from "./components/Reveal";

const tools = [
  "rename", "move", "copy", "trash", "new folder", "write file", "read file",
  "shell", "type", "keystroke", "click", "double-click", "right-click", "drag",
  "scroll", "open app", "open link", "applescript", "clipboard",
];

const steps = [
  {
    n: "01",
    title: "Do the first bit yourself",
    body: "Rename two files. Start the sentence. Copy the mess. Nothing special — just begin the way you always do.",
  },
  {
    n: "02",
    title: "Press the key",
    body: "Illusory reads your screen, the focused field, what you copied and what just changed on disk. You explain nothing.",
  },
  {
    n: "03",
    title: "It finishes",
    body: "Tap and it just goes. Hold and you see the exact command or the exact renames first — release to run, let go early to cancel.",
  },
];

export default function Home() {
  return (
    <main>
      <header className="hero">
        <div className="hero-mark">
          <Mark size={112} />
        </div>

        <h1>
          Autocomplete for <em>everything that isn’t typing.</em>
        </h1>

        <p className="lede">
          You rename two files by date. You press{" "}
          <kbd className="key inline">⌥</kbd>
          <kbd className="key inline">Space</kbd>. Illusory renames the other
          forty‑eight.
        </p>
        <p className="sub">
          No chat window, no prompt to write. It reads what you were already doing
          and does the next small thing.
        </p>

        <div className="cta-row">
          <a className="cta" href="https://github.com/aaravriyer193/illusory">
            Get Illusory
          </a>
          <span className="cta-note">macOS · free · no account</span>
        </div>
      </header>

      <Reveal className="surfaces">
        <span className="eyebrow">Works in</span>
        <div className="surfaces-row">
          {surfaces.map(({ name, Logo }) => (
            <span className="surface" key={name}>
              <Logo size={19} />
              {name}
            </span>
          ))}
          <span className="surface muted">…and whatever else is in front of you</span>
        </div>
      </Reveal>

      <Reveal className="how">
        <span className="eyebrow">How it works</span>
        <div className="how-grid">
          {steps.map((step) => (
            <div className="step" key={step.n}>
              <span className="step-n">{step.n}</span>
              <h3>{step.title}</h3>
              <p>{step.body}</p>
            </div>
          ))}
        </div>

        {/* The gesture itself, as a thing you can watch happen. */}
        <div className="gesture">
          <div className="gesture-keys">
            <kbd className="key big">⌥</kbd>
            <kbd className="key big wide">Space</kbd>
          </div>
          <div className="gesture-track">
            <div className="gesture-captions">
              <span>Reading what you’re doing…</span>
              <span>rename → 2024-06-03-…</span>
              <span>Renamed 48 files.</span>
            </div>
          </div>
        </div>
      </Reveal>

      <section className="cases">
        {useCases.map(({ title, body, Scene }, i) => (
          <Reveal className="case" key={title}>
            <div className="case-copy">
              <span className="eyebrow">{String(i + 1).padStart(2, "0")}</span>
              <h2>{title}</h2>
              <p>{body}</p>
            </div>
            <div className="case-scene">
              <Scene />
            </div>
          </Reveal>
        ))}
      </section>

      <Reveal className="marquee-wrap">
        <span className="eyebrow">It can actually do</span>
        <div className="marquee">
          <div className="marquee-track">
            {[...tools, ...tools].map((tool, i) => (
              <span className="chip" key={i}>{tool}</span>
            ))}
          </div>
        </div>
      </Reveal>

      <Reveal className="rule">
        <h2>If it takes longer than a second, it’s not Illusory’s job.</h2>
        <p>
          Latency ceiling and scope ceiling are the same ceiling. One second of
          compute is about thirty seconds of your own work, and that’s the largest
          thing Illusory will ever do. It isn’t here to run your projects — it’s
          here for the busywork between you and the work you actually care about.
        </p>
      </Reveal>

      <Reveal className="rule two-up">
        <div>
          <h2>Hold to look first.</h2>
          <p>
            Tap and it just goes. Hold and you see the literal thing it’s about to
            run — the actual command, the actual renames — before you let go.
            Anything destructive always waits for a hold.
          </p>
        </div>
        <div>
          <h2>No account. No sign‑in.</h2>
          <p>
            Illusory has no login of its own. Connecting Slack, Notion or GitHub
            opens a normal consent screen and the token stays in your Keychain.
            Nothing to paste. Point it at Ollama and not even the model call leaves
            your Mac.
          </p>
        </div>
      </Reveal>

      <footer>
        <span className="footer-mark">
          <Mark size={20} spokes={28} strokeWidth={12} />
          Illusory
        </span>
        <a href="https://github.com/aaravriyer193/illusory">Source</a>
      </footer>
    </main>
  );
}
