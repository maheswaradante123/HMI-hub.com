-- Persiapan migrasi RO/Production Order lama:
-- 1) satu produk boleh muncul di beberapa baris dalam satu RO/PO (mis. kirim bertahap per tanggal),
-- 2) pilihan jenis pengemasan ditambah 'Vacuum 3 Kg' dan 'Wrap' (dipakai di dokumen lama).
alter table public.ro_items drop constraint if exists ro_items_ro_id_product_id_key;
alter table public.po_items drop constraint if exists po_items_po_id_product_id_key;

alter table public.ro_items drop constraint if exists ro_items_packaging_chk;
alter table public.ro_items add constraint ro_items_packaging_chk check (packaging is null or packaging in
  ('Vacuum 1 Kg','Vacuum 3 Kg','Vacuum 4 Kg','Tray + Wrap','Wrap + Vacuum 4 Kg','Wrap'));

alter table public.po_items drop constraint if exists po_items_packaging_chk;
alter table public.po_items add constraint po_items_packaging_chk check (packaging is null or packaging in
  ('Vacuum 1 Kg','Vacuum 3 Kg','Vacuum 4 Kg','Tray + Wrap','Wrap + Vacuum 4 Kg','Wrap'));

-- Satuan tambahan untuk produk jasa dan sapi utuh.
insert into public.units (code, name) values ('EKOR','Ekor'), ('LS','Lumpsum') on conflict do nothing;
