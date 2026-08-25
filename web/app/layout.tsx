import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Illusory — One key. AI finishes what you started.",
  description:
    "Press one key, anywhere on your Mac. Illusory looks at what you're doing and does the rest.",
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
