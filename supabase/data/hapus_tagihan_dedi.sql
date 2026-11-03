-- Menghapus tagihan bulanan Dedi Trimulyanto #192 yang belum dibayar (dibuat saat uji coba dengan tarif kelas),
-- lalu mengembalikan nomor urut invoice ke nomor terbesar yang masih terpakai supaya tidak ada nomor yang loncat.
-- Jalankan SETELAH 0031_qurban_tarif_tetap.sql. Tagihan yang sudah Lunas tidak disentuh.
do $$
declare
  v_order uuid;
  v_n integer;
  r record;
  v_max integer;
begin
  select id into v_order from public.qurban_orders
   where cow_no = '#192' and customer_nick = 'Dedi Trimulyanto' and deleted_at is null;
  if v_order is null then raise exception 'Pesanan Dedi Trimulyanto #192 tidak ditemukan'; end if;

  create temp table _hapus on commit drop as
    select id, bill_no, to_char(bill_date, 'YYYY-MM') as ym from public.qurban_bills
     where order_id = v_order and status = 'ISSUED' and not is_legacy;
  select count(*) into v_n from _hapus;
  delete from public.qurban_bills where id in (select id from _hapus);
  raise notice 'Tagihan dihapus: % (%)', v_n, (select string_agg(bill_no, ', ' order by bill_no) from _hapus);

  -- nomor urut per bulan kembali ke nomor terbesar yang masih dipakai invoice atau tagihan lain
  for r in select distinct ym from _hapus loop
    select coalesce(max(substring(no from 5 for 3)::integer), 0) into v_max from (
      select inv_no as no from public.qurban_orders where inv_no ~ '^INV-[0-9]{3}-' and (inv_date is not null and to_char(inv_date, 'YYYY-MM') = r.ym)
      union all
      select bill_no from public.qurban_bills where bill_no ~ '^INV-[0-9]{3}-' and to_char(bill_date, 'YYYY-MM') = r.ym
    ) x;
    update public.qurban_sequences set last_number = v_max where kind = 'INV' and ym = r.ym and last_number > v_max;
    raise notice 'Nomor urut invoice % kembali ke %', r.ym, v_max;
  end loop;
end $$;
