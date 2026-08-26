import { NextRequest, NextResponse } from "next/server";

/**
 * Inference for shipped builds.
 *
 * A downloaded app has no `.env`, so it has no key — and embedding one in the
 * bundle would just publish it, the same reason the OAuth secrets live here. The
 * app posts its prompt, this forwards it to OpenRouter with the server-side key,
 * and only the completion goes back.
 *
 * Nothing is logged or stored: the screenshot and prompt pass straight through.
 */
export const maxDuration = 30;

const MODEL = process.env.ILLUSORY_MODEL ?? "xiaomi/mimo-v2.5";
const MAX_TOKENS = 1200;
/** Roughly a 1200px JPEG plus prompt, with headroom. Anything larger is not us. */
const MAX_BODY = 3_000_000;

export async function POST(request: NextRequest) {
  const key = process.env.OPENROUTER_API_KEY;
  if (!key) {
    return NextResponse.json(
      { error: "Model is not configured on the server" },
      { status: 503 },
    );
  }

  let payload: {
    system?: string;
    user?: string;
    image?: string;
    maxTokens?: number;
  };
  try {
    const raw = await request.text();
    if (raw.length > MAX_BODY) {
      return NextResponse.json({ error: "Request too large" }, { status: 413 });
    }
    payload = JSON.parse(raw);
  } catch {
    return NextResponse.json({ error: "Bad request" }, { status: 400 });
  }

  const { system, user, image } = payload;
  if (!system || !user) {
    return NextResponse.json({ error: "Missing prompt" }, { status: 400 });
  }

  // Vision models take content as parts; text-only models reject that shape, so
  // only switch when there is an image.
  const content = image
    ? [
        { type: "text", text: user },
        { type: "image_url", image_url: { url: `data:image/jpeg;base64,${image}` } },
      ]
    : user;

  try {
    const response = await fetch(
      "https://openrouter.ai/api/v1/chat/completions",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${key}`,
          "Content-Type": "application/json",
          "HTTP-Referer": "https://illusory.fulmina.re",
          "X-Title": "Illusory",
        },
        body: JSON.stringify({
          model: MODEL,
          max_tokens: Math.min(payload.maxTokens ?? 900, MAX_TOKENS),
          temperature: 0.1,
          // Reasoning models spend the whole budget thinking and return empty
          // content, which reads to the user as Illusory being broken.
          reasoning: { enabled: false },
          messages: [
            { role: "system", content: system },
            { role: "user", content },
          ],
        }),
      },
    );

    if (!response.ok) {
      const detail = (await response.text()).slice(0, 200);
      return NextResponse.json(
        { error: `Model error ${response.status}: ${detail}` },
        { status: 502 },
      );
    }

    const json = await response.json();
    const text = json?.choices?.[0]?.message?.content;
    if (typeof text !== "string" || !text.trim()) {
      return NextResponse.json({ error: "Model returned nothing" }, { status: 502 });
    }
    return NextResponse.json({ content: text.trim() });
  } catch {
    return NextResponse.json({ error: "Could not reach the model" }, { status: 502 });
  }
}
