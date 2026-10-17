"use client";

import { useActionState } from "react";
import { saveRolePermissions, type RoleState } from "@/app/(app)/role/actions";
import { ACTIONS, ACTION_LABEL } from "@/lib/modules";

export function RoleForm({ roleId, modules, granted }: {
  roleId: string; modules: { module: string; label: string; perms: Record<string, string> }[]; granted: string[];
}) {
  const [state, action, pending] = useActionState<RoleState, FormData>(saveRolePermissions.bind(null, roleId), {});
  const has = new Set(granted);
  return (
    <form action={action} className="space-y-4">
      <div className="overflow-x-auto rounded-lg border border-line bg-surface">
        <table className="w-full text-left text-lg">
          <thead className="border-b border-line bg-background"><tr>
            <th scope="col" className="px-4 py-3">Modul</th>
            {ACTIONS.map((a) => <th key={a} scope="col" className="px-3 py-3 text-center">{ACTION_LABEL[a]}</th>)}
          </tr></thead>
          <tbody>
            {modules.map((m) => (
              <tr key={m.module} className="border-b border-line last:border-0">
                <th scope="row" className="px-4 py-3 font-normal">{m.label}</th>
                {ACTIONS.map((a) => (
                  <td key={a} className="px-3 py-3 text-center">
                    <input type="checkbox" name="perm" value={m.perms[a]} defaultChecked={has.has(m.perms[a])} aria-label={`${m.label}: ${ACTION_LABEL[a]}`} className="h-6 w-6" />
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {state.error && <p role="alert" className="rounded-md bg-danger-bg px-4 py-3 text-danger">{state.error}</p>}
      <button type="submit" disabled={pending} className="rounded-md bg-brand px-8 py-3 text-lg font-semibold text-white hover:bg-brand-dark disabled:opacity-60">{pending ? "Menyimpan..." : "Simpan izin"}</button>
    </form>
  );
}
