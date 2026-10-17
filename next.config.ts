import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  /* config options here */
  // Semua halaman bergantung pada sesi login masing-masing user,
  // jadi tidak ada yang bisa di-prerender atau di-cache bersama.
  cacheComponents: false,
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
