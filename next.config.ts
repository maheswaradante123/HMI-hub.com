import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  /* config options here */
  // Semua halaman bergantung pada sesi login masing-masing user,
  // jadi tidak ada yang bisa di-prerender atau di-cache bersama.
  cacheComponents: false,
  // Logo, tanda tangan, dan templat Word dibaca dari disk oleh pembuat dokumen.
  outputFileTracingIncludes: {
    "/qurban/export/[kind]/[id]": ["./src/lib/export/assets/**/*", "./src/lib/export/templates/**/*", "./src/lib/export/fonts/**/*"],
    // Nama rute bisa memuat grup "(app)", jadi dipasang di semua bentuknya agar font dan gambar PDF selalu ikut terbawa.
    "/d/[slug]/[id]/export": ["./src/lib/export/assets/**/*", "./src/lib/export/fonts/**/*"],
    "/d/[slug]/[id]/export/route": ["./src/lib/export/assets/**/*", "./src/lib/export/fonts/**/*"],
    "/(app)/d/[slug]/[id]/export": ["./src/lib/export/assets/**/*", "./src/lib/export/fonts/**/*"],
    "/(app)/d/[slug]/[id]/export/route": ["./src/lib/export/assets/**/*", "./src/lib/export/fonts/**/*"],
    "/purchase-request/[id]/export": ["./src/lib/export/assets/**/*", "./src/lib/export/fonts/**/*"],
    "/purchase-request/[id]/export/route": ["./src/lib/export/assets/**/*", "./src/lib/export/fonts/**/*"],
    "/(app)/purchase-request/[id]/export": ["./src/lib/export/assets/**/*", "./src/lib/export/fonts/**/*"],
    "/(app)/purchase-request/[id]/export/route": ["./src/lib/export/assets/**/*", "./src/lib/export/fonts/**/*"],
    "/purchase-request/**/*": ["./src/lib/export/assets/**/*", "./src/lib/export/fonts/**/*"],
    "/d/**/*": ["./src/lib/export/assets/**/*", "./src/lib/export/fonts/**/*"],
  },
  serverExternalPackages: ["exceljs", "jszip"],
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

export default nextConfig;
