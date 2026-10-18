-- HMI Hub - Nota Penjualan Non-Karkas: satu nota aktif untuk satu sapi (penimbangan karkas).
-- Nota yang dibatalkan (VOID) atau dihapus tidak dihitung, jadi sapi yang sama bisa dibuatkan nota baru.
do $$
begin
  if exists (select 1 from public.noncarcass_sales where cw_id is not null and status <> 'VOID' and deleted_at is null group by cw_id having count(*) > 1) then
    raise notice 'Ada sapi dengan lebih dari satu nota non-karkas aktif; batasan satu nota per sapi tidak dipasang. Batalkan nota gandanya lalu jalankan ulang migrasi ini.';
  else
    create unique index if not exists noncarcass_sales_cw_active_uq on public.noncarcass_sales (cw_id)
      where cw_id is not null and status <> 'VOID' and deleted_at is null;
  end if;
end $$;
