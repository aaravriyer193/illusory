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
    // The list endpoint, not /releases/latest: that one silently excludes
    // pre-releases, so an early build would send everyone to a page instead of
    // a download without anything looking broken.
    const response = await fetch(
      `https://api.github.com/repos/${REPO}/releases?per_page=10`,
      {
        headers: {
          Accept: "application/vnd.github+json",
          "User-Agent": "illusory-site",
        },
        next: { revalidate },
      },
    );
    if (!response.ok) return NextResponse.redirect(RELEASES);

    const releases: Array<{
      draft: boolean;
      assets?: Array<{ name: string; browser_download_url: string }>;
    }> = await response.json();

    for (const release of releases) {
      if (release.draft) continue;
      const asset = (release.assets ?? []).find((a) =>
        a.name.toLowerCase().endsWith(".zip"),
      );
      if (asset) return NextResponse.redirect(asset.browser_download_url);
    }

    // Releases exist but none carry a build yet; the releases page beats a 404.
    return NextResponse.redirect(RELEASES);
  } catch {
    return NextResponse.redirect(RELEASES);
  }
}
