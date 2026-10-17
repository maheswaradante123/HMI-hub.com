import "server-only";

// Tanggal hari ini di Jakarta, format YYYY-MM-DD.
export function todayJakarta(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Jakarta" }).format(new Date());
}

export const TYPE_LABEL: Record<string, string> = {
  MANUFACTURE: "Manufacture",
  RESELLER: "Reseller",
  SUPPORTING: "Supporting",
};
