-- HMI Hub - Nomor Production Order mengikuti tanggal publish (order_date) yang dipilih pengguna, bukan tanggal hari ini.
-- Bila tanggal publish kosong, dipakai tanggal hari ini seperti sebelumnya.
create or replace function public.prod_assign_number() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_ro text; v_core text; v_n int;
  v_roman text[] := array['I','II','III','IV','V','VI','VII','VIII','IX','X','XI','XII'];
  v_day date := coalesce(new.order_date, (now() at time zone 'Asia/Jakarta')::date);
begin
  if new.doc_number is not null then return new; end if;
  if new.ro_id is not null then
    select doc_number into v_ro from public.request_orders where id = new.ro_id;
    v_core := substring(v_ro from '^RO-(.*-[0-9]{3})-[IVX]+-[0-9]{2}$');
  end if;
  if v_core is null then
    new.doc_number := public.next_doc_number('PROD', 'PROD');
    return new;
  end if;
  select count(*) into v_n from public.production_orders where ro_id = new.ro_id;
  new.doc_number := format('PROD-%s-%s-%s', v_core, v_roman[extract(month from v_day)::int], to_char(v_day, 'YY'))
                    || case when v_n > 0 then '-R' || (v_n + 1) else '' end;
  return new;
end $$;
revoke all on function public.prod_assign_number() from public, anon, authenticated;
