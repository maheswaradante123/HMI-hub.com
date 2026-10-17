import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "HMI Hub",
  description: "Sistem internal PT Harmoni Mitra Inovindo",
  robots: { index: false, follow: false },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="id">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
        {/* eslint-disable-next-line @next/next/no-page-custom-font */}
        <link
          rel="stylesheet"
          href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap"
        />
      </head>
      <body style={{ ["--font-inter" as string]: "Inter" }}>{children}</body>
    </html>
  );
}
