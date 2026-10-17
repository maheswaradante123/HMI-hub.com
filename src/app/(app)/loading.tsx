// Tampil seketika saat berpindah halaman, selagi server menyiapkan isi halaman.
export default function Loading() {
  return (
    <div className="max-w-5xl animate-pulse" aria-busy="true" aria-label="Memuat halaman">
      <div className="h-8 w-64 rounded-lg skel" />
      <div className="mt-3 h-4 w-40 rounded skel" />
      <div className="mt-8 rounded-lg border border-line bg-surface p-6">
        <div className="h-5 w-32 rounded skel" />
        <div className="mt-5 grid gap-3 sm:grid-cols-3">
          <div className="h-20 rounded-xl bg-field" />
          <div className="h-20 rounded-xl bg-field" />
          <div className="h-20 rounded-xl bg-field" />
        </div>
        <div className="mt-5 h-40 rounded-xl bg-field" />
      </div>
    </div>
  );
}
