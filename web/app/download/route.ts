import { NextResponse } from "next/server";

/**
 * Sends people to the current build.
 *
 * The site never hardcodes a version: it asks GitHub for the latest release and
 * redirects to its zip. Publishing a release is then the only step in shipping —
 * the download button updates itself, and can never point at a build that no
 * longer exists.
 */
const REPO = process.env.ILLUSORY_REPO ?? "aaravriyer193/illusory";
const RELEASES = `https://github.com/${REPO}/releases/latest`;

export const revalidate = 300;

export async function GET() {
  try {
    const response = await fetch(
      `https://api.github.com/repos/${REPO}/releases/latest`,
      {
        headers: {
          Accept: "application/vnd.github+json",
          "User-Agent": "illusory-site",
        },
        next: { revalidate },
      },
    );
    if (!response.ok) return NextResponse.redirect(RELEASES);

    const release = await response.json();
    const asset = (release.assets ?? []).find((a: { name: string }) =>
      a.name.toLowerCase().endsWith(".zip"),
    );

    // No asset yet means a release exists but the build hasn't been attached;
    // the releases page is a better landing spot than a 404.
    return NextResponse.redirect(asset?.browser_download_url ?? RELEASES);
  } catch {
    return NextResponse.redirect(RELEASES);
  }
}
