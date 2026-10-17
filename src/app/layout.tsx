import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "HMI Internal System",
  description: "Sistem internal PT Harmoni Mitra Inovindo",
  robots: { index: false, follow: false },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="id">
      <body>{children}</body>
    </html>
  );
}
