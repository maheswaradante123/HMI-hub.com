-- HMI Hub - Cash Payment Journal (CPJ mingguan): jurnal pengeluaran kas dengan kolom rencana dan realisasi.
-- Dokumen baru, terpisah dari CPJ lama (pembayaran per PR). Baris bisa ditarik dari item Purchase Request atau diketik manual.
-- Alur: DRAFT -> WAITING (diajukan ke Owner) -> ACC (Owner menyetujui, dana dirilis) -> REALIZED (realisasi diisi).
-- Setelah di-ACC, kolom rencana terkunci; hanya realisasi (harga, qty, bukti) yang boleh diisi.
-- Nomor: CPJ-{minggu ke- dalam bulan, 3 angka}-{bulan romawi}-{YY}; nomor realisasi di cetakan: R-{nomor}.
-- Saat REALIZED, PR yang barangnya sudah diterima (RECEIVED) otomatis menjadi PAID.

insert into public.permissions (module, action)
select 'cpj_journal', a.action
from unnest(array['view','create','edit','delete','approve','export']) as a(action)
on conflict (module, action) do nothing;

create or replace function pg_temp.g(p_role text, p_module text, p_actions text[]) returns void language sql as $f$
  insert into public.role_permissions (role_id, permission_id) select r.id, p.id from public.roles r, public.permissions p
   where r.code = p_role and p.module = p_module and p.action = any(p_actions) on conflict do nothing;
$f$;
select pg_temp.g('ACCOUNTING','cpj_journal','{view,create,edit,delete,export}');
select pg_temp.g('PURCHASING','cpj_journal','{view}');

create table public.cash_journals (
  id              uuid primary key default gen_random_uuid(),
  doc_number      text unique,
  journal_date    date not null default (now() at time zone 'Asia/Jakarta')::date,
  initiator_name  text,
  initiator_title text,
  approver_name   text,
  approver_title  text,
  pay_note        text,
  notes           text,
  plan_hash       text,
  approved_on     date,
  realized_on     date,
  status          text not null default 'DRAFT' check (status in ('DRAFT','WAITING','ACC','REALIZED','VOID')),
  created_at timestamptz not null default now(), created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(), updated_by uuid references auth.users(id),
  deleted_at timestamptz
);
create table public.cash_journal_lines (
  id          uuid primary key default gen_random_uuid(),
  journal_id  uuid not null references public.cash_journals(id),
  line_no     integer not null,
  trans_date  date,
  ac          text,
  code        text,
  description text not null check (btrim(description) <> ''),
  price       numeric(18,2) not null default 0 check (price >= 0),
  qty         numeric(14,3) not null default 1 check (qty >= 0),
  unit        text,
  flag        text not null default 'NONE' check (flag in ('NONE','NON_CPJ','OVER','REJECTED','INCOMING')),
  pr_item_id  uuid references public.pr_items(id),
  real_price  numeric(18,2) check (real_price >= 0),
  real_qty    numeric(14,3) check (real_qty >= 0),
  proof       text,
  unique (journal_id, line_no)
);
create index cash_journal_lines_journal_idx on public.cash_journal_lines(journal_id);
create index cash_journal_lines_pr_item_idx on public.cash_journal_lines(pr_item_id);

-- save_doc mengisi kolom yang tidak dikirim dengan NULL; nilai bawaan dipulihkan di sini.
create or replace function public.jcp_line_defaults() returns trigger
language plpgsql as $$
begin
  new.flag  := coalesce(nullif(btrim(new.flag), ''), 'NONE');
  new.price := coalesce(new.price, 0);
  new.qty   := coalesce(new.qty, 1);
  new.ac    := nullif(btrim(coalesce(new.ac, '')), '');
  new.code  := nullif(btrim(coalesce(new.code, '')), '');
  new.unit  := nullif(btrim(coalesce(new.unit, '')), '');
  new.proof := nullif(btrim(coalesce(new.proof, '')), '');
  return new;
end $$;
create trigger cash_journal_lines_defaults before insert on public.cash_journal_lines
  for each row execute function public.jcp_line_defaults();

select public.attach_doc_standard('cash_journals', 'JCP', 'CPJ', 'cpj_journal');
select public.attach_child_standard('cash_journal_lines', 'cpj_journal');

-- Nomor mingguan: minggu ke-1 dimulai tanggal 1 (Senin sebagai awal minggu, sama dengan Purchase Request di preview).
-- Jika minggu itu sudah punya jurnal lain, nomor diberi akhiran -2, -3, dst.
create or replace function public.cpj_week_of(p_date date) returns integer
language sql immutable as $$
  select ((extract(day from p_date)::int - 1 + ((extract(dow from date_trunc('month', p_date))::int + 6) % 7)) / 7) + 1
$$;
create or replace function public.jcp_assign_number() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_roman text[] := array['I','II','III','IV','V','VI','VII','VIII','IX','X','XI','XII'];
  v_base  text;
  v_n     integer;
begin
  if new.doc_number is not null then return new; end if;
  v_base := format('CPJ-%s-%s-%s', lpad(public.cpj_week_of(new.journal_date)::text, 3, '0'),
                   v_roman[extract(month from new.journal_date)::int], to_char(new.journal_date, 'YY'));
  perform pg_advisory_xact_lock(hashtext(v_base));
  select count(*) into v_n from public.cash_journals where doc_number = v_base or doc_number like v_base || '-%';
  new.doc_number := case when v_n = 0 then v_base else v_base || '-' || (v_n + 1) end;
  return new;
end $$;
revoke all on function public.jcp_assign_number() from public, anon, authenticated;
drop trigger cash_journals_docno on public.cash_journals;
create trigger cash_journals_docno before insert on public.cash_journals
  for each row execute function public.jcp_assign_number();

-- Tanggal ACC dan tanggal realisasi dicatat otomatis; hanya Owner (izin approve) yang bisa membawa jurnal ke ACC.
create or replace function public.jcp_before() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    if new.status = 'ACC' then new.approved_on := (now() at time zone 'Asia/Jakarta')::date; end if;
    if new.status = 'REALIZED' then
      new.realized_on := (now() at time zone 'Asia/Jakarta')::date;
      if not exists (select 1 from public.cash_journal_lines where journal_id = new.id) then
        raise exception 'Jurnal tanpa baris tidak bisa direalisasi' using errcode = '22023';
      end if;
    end if;
    if new.status = 'WAITING' and not exists (select 1 from public.cash_journal_lines where journal_id = new.id) then
      raise exception 'Isi minimal satu baris sebelum diajukan ke Owner' using errcode = '22023';
    end if;
  end if;
  return new;
end $$;
revoke all on function public.jcp_before() from public, anon, authenticated;
create trigger cash_journals_check before update on public.cash_journals
  for each row execute function public.jcp_before();

-- Realisasi selesai -> PR yang barangnya sudah diterima menjadi PAID (dengan riwayat). Batal setelah realisasi -> kembali RECEIVED.
create or replace function public.jcp_on_status() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if new.status = 'REALIZED' and old.status = 'ACC' then
    for r in
      select distinct p.id from public.cash_journal_lines l
        join public.pr_items i on i.id = l.pr_item_id
        join public.purchase_requests p on p.id = i.pr_id
       where l.journal_id = new.id and p.status = 'RECEIVED'
    loop
      update public.purchase_requests set status = 'PAID' where id = r.id;
      insert into public.pr_status_history (pr_id, from_status, to_status, note, changed_by)
      values (r.id, 'RECEIVED', 'PAID', 'Dibayar lewat ' || new.doc_number, auth.uid());
    end loop;
  elsif new.status = 'VOID' and old.status = 'REALIZED' then
    for r in
      select distinct p.id from public.cash_journal_lines l
        join public.pr_items i on i.id = l.pr_item_id
        join public.purchase_requests p on p.id = i.pr_id
       where l.journal_id = new.id and p.status = 'PAID'
         and not exists (
           select 1 from public.cash_journal_lines l2
             join public.cash_journals j2 on j2.id = l2.journal_id and j2.status = 'REALIZED' and j2.deleted_at is null and j2.id <> new.id
             join public.pr_items i2 on i2.id = l2.pr_item_id
            where i2.pr_id = p.id)
         and not exists (select 1 from public.cash_payments c where c.pr_id = p.id and c.status = 'POSTED')
    loop
      update public.purchase_requests set status = 'RECEIVED' where id = r.id;
      insert into public.pr_status_history (pr_id, from_status, to_status, note, changed_by)
      values (r.id, 'PAID', 'RECEIVED', 'Jurnal ' || new.doc_number || ' dibatalkan', auth.uid());
    end loop;
  end if;
  return null;
end $$;
revoke all on function public.jcp_on_status() from public, anon, authenticated;
create trigger cash_journals_status after update of status on public.cash_journals
  for each row execute function public.jcp_on_status();

-- Setelah simpan: kunci kolom rencana. Saat DRAFT sidik jari rencana diperbarui; saat ACC rencana harus sama dengan yang di-ACC.
-- Satu item PR tidak boleh ada di dua jurnal yang masih berlaku.
create or replace function public.jcp_after_save(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_status text;
  v_hash   text;
  v_old    text;
  v_dup    text;
begin
  select status, plan_hash into v_status, v_old from public.cash_journals where id = p_id;
  select md5(coalesce(string_agg(concat_ws('|', l.line_no, l.trans_date, l.ac, l.code, l.description, l.price, l.qty, l.unit, l.flag, l.pr_item_id), E'\n' order by l.line_no), ''))
    into v_hash from public.cash_journal_lines l where l.journal_id = p_id;
  if v_status = 'DRAFT' then
    update public.cash_journals set plan_hash = v_hash where id = p_id;
  elsif v_status = 'ACC' and v_hash is distinct from v_old then
    raise exception 'Jurnal sudah di-ACC Owner: kolom rencana tidak boleh diubah, hanya realisasi dan bukti' using errcode = '55000';
  end if;
  select j.doc_number into v_dup
    from public.cash_journal_lines l
    join public.cash_journal_lines o on o.pr_item_id = l.pr_item_id and o.journal_id <> l.journal_id
    join public.cash_journals j on j.id = o.journal_id and j.status <> 'VOID' and j.deleted_at is null
   where l.journal_id = p_id and l.pr_item_id is not null
   limit 1;
  if v_dup is not null then
    raise exception 'Item Purchase Request sudah dipakai di jurnal %', v_dup using errcode = '23505';
  end if;
end $$;
revoke all on function public.jcp_after_save(uuid) from public, anon, authenticated;

insert into public.doc_registry (doc_type, table_name, module, header_cols, editable_statuses, children, after_save_fn) values
 ('JCP','cash_journals','cpj_journal',
  '{journal_date,initiator_name,initiator_title,approver_name,approver_title,pay_note,notes}',
  '{DRAFT,ACC}',
  '[{"key":"lines","table":"cash_journal_lines","fk":"journal_id","cols":["trans_date","ac","code","description","price","qty","unit","flag","pr_item_id","real_price","real_qty","proof"]}]',
  'jcp_after_save');
insert into public.doc_rules (doc_type, from_status, to_status, module, action, needs_note, label) values
 ('JCP','DRAFT','WAITING','cpj_journal','edit',false,'Ajukan ke Owner'),
 ('JCP','WAITING','ACC','cpj_journal','approve',false,'ACC (dana dirilis)'),
 ('JCP','WAITING','DRAFT','cpj_journal','approve',true,'Kembalikan ke draf'),
 ('JCP','ACC','REALIZED','cpj_journal','edit',false,'Selesaikan realisasi'),
 ('JCP','DRAFT','VOID','cpj_journal','edit',true,'Batalkan'),
 ('JCP','WAITING','VOID','cpj_journal','delete',true,'Batalkan jurnal'),
 ('JCP','ACC','VOID','cpj_journal','delete',true,'Batalkan jurnal'),
 ('JCP','REALIZED','VOID','cpj_journal','delete',true,'Batalkan jurnal');

-- Item PR yang bisa ditarik ke jurnal: PR disetujui / dipesan / diterima, belum dipakai di jurnal lain yang masih berlaku.
create or replace function public.cpj_pullable_pr_items()
returns table (pr_item_id uuid, pr_number text, pr_status text, item_name text, qty numeric, unit text, price numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_permission('cpj_journal','create') and not public.has_permission('cpj_journal','edit') then
    raise exception 'Tidak berhak' using errcode = '42501';
  end if;
  return query
  select i.id, p.doc_number, p.status, i.item_name, i.qty, u.name::text, coalesce(i.estimated_price, 0)::numeric
    from public.pr_items i
    join public.purchase_requests p on p.id = i.pr_id and p.deleted_at is null and p.status in ('APPROVED','ORDERED','RECEIVED')
    join public.units u on u.id = i.unit_id
   where not exists (
     select 1 from public.cash_journal_lines l join public.cash_journals j on j.id = l.journal_id and j.status <> 'VOID' and j.deleted_at is null
      where l.pr_item_id = i.id)
   order by p.doc_number, i.line_no;
end $$;
revoke all on function public.cpj_pullable_pr_items() from public, anon;
grant execute on function public.cpj_pullable_pr_items() to authenticated;
