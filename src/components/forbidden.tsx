export function Forbidden({ roleName, what }: { roleName: string; what: string }) {
  return (
    <div className="max-w-2xl">
      <h1 className="text-3xl font-bold">Akses ditolak</h1>
      <p className="mt-3 rounded-md bg-danger-bg px-4 py-3 text-danger">
        Role Anda ({roleName}) tidak memiliki izin untuk membuka {what}. Hubungi Owner jika Anda memerlukan akses.
      </p>
    </div>
  );
}
