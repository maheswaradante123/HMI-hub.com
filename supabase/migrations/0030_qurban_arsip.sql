-- HMI Internal System - Migrasi 0030: arsip pesanan Qurban Cerdas dari Master Sapi (Google Sheet)
-- Pesanan lama memakai nomor invoice/kontrak dari sheet, dan satu nomor boleh dipakai beberapa sapi milik pembeli yang sama.
-- Karena itu keunikan nomor hanya berlaku untuk dokumen yang dibuat aplikasi (bukan arsip).

alter table public.qurban_orders
  add column is_legacy boolean not null default false,
  add column sp_jb_no  text,      -- nomor Surat Perjanjian Jual Beli dari sheet (arsip)
  add column sp_pl_no  text;      -- nomor Surat Perjanjian Pemeliharaan dari sheet (arsip)
alter table public.qurban_bills add column is_legacy boolean not null default false;

alter table public.qurban_orders drop constraint qurban_orders_pro_no_key;
alter table public.qurban_orders drop constraint qurban_orders_inv_no_key;
alter table public.qurban_bills  drop constraint qurban_bills_bill_no_key;
create unique index qurban_orders_pro_no_uniq on public.qurban_orders(pro_no) where not is_legacy;
create unique index qurban_orders_inv_no_uniq on public.qurban_orders(inv_no) where not is_legacy;
create unique index qurban_bills_bill_no_uniq on public.qurban_bills(bill_no) where not is_legacy;

-- Arsip tidak boleh diubah statusnya lewat jalur normal ke arah yang salah: penanda arsip tidak bisa dilepas.
create or replace function public.qurban_legacy_guard() returns trigger
language plpgsql as $$
begin
  if old.is_legacy and not new.is_legacy then
    raise exception 'Penanda arsip tidak bisa dilepas' using errcode = '22023';
  end if;
  return new;
end $$;
create trigger qurban_orders_legacy_guard before update on public.qurban_orders
  for each row execute function public.qurban_legacy_guard();

-- Tampilan pesanan ikut membawa kolom baru (o.* dibaca saat tampilan dibuat).
drop view public.v_qurban_orders;
create view public.v_qurban_orders with (security_invoker = true) as
select o.*,
       t.total,
       (t.total - o.discount - o.down_payment) as due_amount,
       coalesce((select w.weight from public.qurban_weighings w where w.order_id = o.id order by w.weigh_date desc, w.created_at desc limit 1), o.initial_weight) as last_weight,
       (select count(*) from public.qurban_bills b where b.order_id = o.id and b.status <> 'CANCELLED') as bill_count
  from public.qurban_orders o
 cross join lateral (select coalesce(sum(l.qty * l.price), 0) as total from public.qurban_order_lines(o.id) l) t
 where o.deleted_at is null;
grant select on public.v_qurban_orders to authenticated;
