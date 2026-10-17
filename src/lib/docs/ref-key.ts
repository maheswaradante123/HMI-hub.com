export const refKey = (f: { ref?: string; refStatus?: string[] }) => `${f.ref}|${(f.refStatus ?? []).join(",")}`;
