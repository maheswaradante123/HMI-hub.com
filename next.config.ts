import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  /* config options here */
  // Semua halaman bergantung pada sesi login masing-masing user,
  // jadi tidak ada yang bisa di-prerender atau di-cache bersama.
  cacheComponents: false,
  // Logo, tanda tangan, dan templat Word dibaca dari disk oleh pembuat dokumen.
  outputFileTracingIncludes: {
    "/qurban/export/[kind]/[id]": ["./src/lib/export/assets/**/*", "./src/lib/export/templates/**/*", "./src/lib/export/fonts/**/*"],
    "/d/[slug]/[id]/export": ["./src/lib/export/assets/**/*", "./src/lib/export/fonts/**/*"],
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
