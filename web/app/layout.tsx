import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Illusory — Autocomplete for everything that isn't typing.",
  description:
    "Press one key, anywhere on your Mac. Illusory reads what you were already doing and finishes it — files, apps, anything.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <head>
        <link rel="icon" href="/mark.svg" />
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link
          rel="preconnect"
          href="https://fonts.gstatic.com"
          crossOrigin="anonymous"
        />
        {/* 350 for headings, 400 for body — the same two weights as the app. */}
        <link
          href="https://fonts.googleapis.com/css2?family=Geist:wght@350;400&display=swap"
          rel="stylesheet"
        />
      </head>
      <body>{children}</body>
    </html>
  );
}
