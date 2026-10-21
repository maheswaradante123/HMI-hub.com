-- HMI Internal System - Migrasi 0029: notifikasi email per langkah dokumen
-- Alur: perpindahan status dicatat (doc_status_history / pr_items) -> trigger menaruh email di kotak keluar
-- (notification_outbox) untuk setiap user aktif yang BERIZIN melakukan langkah berikutnya -> aplikasi mengirim
-- lewat SMTP. Penerima mengikuti role dan izin user (termasuk override), jadi tidak ada daftar penerima manual.
-- Kegagalan membuat notifikasi tidak pernah menggagalkan perpindahan status.

-- ---------------------------------------------------------------
-- Aturan: saat dokumen mencapai status X, beri tahu user yang punya izin (module, action)
-- ---------------------------------------------------------------
create table public.notification_rules (
  id          bigint generated always as identity primary key,
  source      text not null default 'DOC' check (source in ('DOC','PR')),
  doc_type    text,                       -- kode di doc_registry (source DOC); kosong untuk PR
  to_status   text not null,
  module      text not null,
  action      text not null check (action in ('view','create','edit','delete','approve','export')),
  title       text not null,              -- judul singkat (subjek email)
  todo        text not null,              -- apa yang perlu dilakukan penerima
  is_active   boolean not null default true,
  unique (source, doc_type, to_status, module, action)
);
alter table public.notification_rules enable row level security;
create policy notification_rules_select on public.notification_rules for select to authenticated using (true);
grant select on public.notification_rules to authenticated;

-- ---------------------------------------------------------------
-- Preferensi per user (default: menerima)
-- ---------------------------------------------------------------
create table public.notification_prefs (
  user_id       uuid primary key references public.user_profiles(id),
  email_enabled boolean not null default true,
  updated_at    timestamptz not null default now()
);
alter table public.notification_prefs enable row level security;
create policy notification_prefs_select on public.notification_prefs for select to authenticated using (user_id = auth.uid());
grant select on public.notification_prefs to authenticated;

create or replace function public.set_my_email_notif(p_on boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or not exists (select 1 from public.user_profiles where id = auth.uid() and is_active) then
    raise exception 'Tidak diizinkan' using errcode = '42501';
  end if;
  insert into public.notification_prefs (user_id, email_enabled) values (auth.uid(), p_on)
  on conflict (user_id) do update set email_enabled = excluded.email_enabled, updated_at = now();
end $$;
revoke all on function public.set_my_email_notif(boolean) from public, anon;
grant execute on function public.set_my_email_notif(boolean) to authenticated;

-- ---------------------------------------------------------------
-- Kotak keluar email (tidak bisa dibaca langsung oleh user)
-- ---------------------------------------------------------------
create table public.notification_outbox (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  actor_id    uuid,                        -- yang memicu perpindahan status
  recipient_id uuid not null,
  to_email    text not null,
  doc_type    text,
  doc_id      uuid,
  doc_number  text,
  to_status   text,
  subject     text not null,
  message     text not null,               -- teks polos; aplikasi membuat HTML-nya
  qty         integer not null default 1,  -- jumlah barang (email PR yang digabung)
  status      text not null default 'pending' check (status in ('pending','sending','sent','failed')),
  attempts    integer not null default 0,
  claimed_at  timestamptz,
  sent_at     timestamptz,
  error       text
);
create index notification_outbox_pending_idx on public.notification_outbox(actor_id, status) where status in ('pending','sending');
alter table public.notification_outbox enable row level security;   -- tanpa kebijakan: hanya lewat fungsi di bawah

-- ---------------------------------------------------------------
-- Apakah user tertentu berizin (module, action)? Sama persis dengan has_permission, tetapi untuk user lain.
-- ---------------------------------------------------------------
create or replace function public.notif_can(p_uid uuid, p_module text, p_action text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  v_role_id uuid; v_superuser boolean; v_role_on boolean; v_user_on boolean; v_perm uuid; v_override boolean;
begin
  select r.id, r.is_superuser, r.is_active, p.is_active into v_role_id, v_superuser, v_role_on, v_user_on
    from public.user_profiles p join public.roles r on r.id = p.role_id where p.id = p_uid;
  if not found or not v_user_on or not v_role_on then return false; end if;
  select id into v_perm from public.permissions where module = p_module and action = p_action;
  if v_perm is not null then
    select o.is_granted into v_override from public.user_permission_overrides o where o.user_id = p_uid and o.permission_id = v_perm;
    if found then return v_override; end if;
  end if;
  if v_superuser then return true; end if;
  if v_perm is null then return false; end if;
  return exists (select 1 from public.role_permissions rp where rp.role_id = v_role_id and rp.permission_id = v_perm);
end $$;
revoke all on function public.notif_can(uuid, text, text) from public, anon, authenticated;

-- Menaruh satu email untuk setiap penerima yang berhak. Bila p_unit diisi (mis. 'barang'), pemanggilan berulang dalam
-- satu transaksi untuk dokumen, status, dan penerima yang sama digabung menjadi satu email berjumlah p_qty.
create or replace function public.notif_enqueue(p_rule public.notification_rules, p_doc_type text, p_doc_id uuid, p_doc_no text,
  p_who text, p_note text, p_qty integer default 1, p_unit text default null) returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_n integer := 0;
  u record; o_id bigint; o_qty integer;
  v_subject text;
  v_msg text;
  v_total integer;
begin
  v_subject := p_rule.title || coalesce(': ' || nullif(p_doc_no, ''), '');
  for u in
    select p.id, au.email from public.user_profiles p
      join auth.users au on au.id = p.id
     where p.is_active and au.email is not null and btrim(au.email) <> ''
       and p.id is distinct from v_actor
       and coalesce((select e.email_enabled from public.notification_prefs e where e.user_id = p.id), true)
       and public.notif_can(p.id, p_rule.module, p_rule.action)
  loop
    v_total := p_qty;
    o_id := null;
    if p_unit is not null then
      select x.id, x.qty into o_id, o_qty from public.notification_outbox x
       where x.recipient_id = u.id and x.doc_id = p_doc_id and x.to_status = p_rule.to_status
         and x.created_at = now() and x.status = 'pending' limit 1;
      if o_id is not null then v_total := o_qty + p_qty; end if;
    end if;
    v_msg := p_rule.title || coalesce(' (' || nullif(p_doc_no, '') || ')', '') || E'.\n'
          || coalesce(p_who, '') || case when p_who is not null then E'\n' else '' end
          || case when p_unit is not null then v_total || ' ' || p_unit || E'.\n' else '' end
          || case when nullif(btrim(coalesce(p_note, '')), '') is not null then 'Catatan: ' || btrim(p_note) || E'\n' else '' end
          || 'Yang perlu dilakukan: ' || p_rule.todo;
    if o_id is not null then
      update public.notification_outbox set qty = v_total, message = v_msg where id = o_id;
    else
      insert into public.notification_outbox (actor_id, recipient_id, to_email, doc_type, doc_id, doc_number, to_status, subject, message, qty)
      values (v_actor, u.id, u.email, p_doc_type, p_doc_id, p_doc_no, p_rule.to_status, v_subject, v_msg, v_total);
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end $$;
revoke all on function public.notif_enqueue(public.notification_rules, text, uuid, text, text, text, integer, text) from public, anon, authenticated;

-- ---------------------------------------------------------------
-- Pemicu dokumen: setiap baris riwayat status baru
-- ---------------------------------------------------------------
create or replace function public.notif_on_doc_status() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  rule public.notification_rules%rowtype;
  reg public.doc_registry%rowtype;
  j jsonb; v_no text; v_cust text; v_who text;
begin
  begin
    if new.from_status is null then return null; end if;   -- dokumen baru dibuat, bukan langkah alur
    if not exists (select 1 from public.notification_rules where source = 'DOC' and doc_type = new.doc_type and to_status = new.to_status and is_active) then
      return null;
    end if;
    select * into reg from public.doc_registry where doc_type = new.doc_type;
    if not found then return null; end if;
    execute format('select to_jsonb(t) from public.%I t where id = $1', reg.table_name) into j using new.doc_id;
    v_no := j->>'doc_number';
    if j ? 'customer_id' and nullif(j->>'customer_id', '') is not null then
      select name into v_cust from public.customers where id = (j->>'customer_id')::uuid;
    end if;
    select full_name into v_who from public.user_profiles where id = new.changed_by;
    v_who := case when v_cust is not null then 'Customer: ' || v_cust || '. ' else '' end
          || case when v_who is not null then 'Diproses oleh ' || v_who || '.' else '' end;
    for rule in select * from public.notification_rules
                 where source = 'DOC' and doc_type = new.doc_type and to_status = new.to_status and is_active
    loop
      perform public.notif_enqueue(rule, new.doc_type, new.doc_id, v_no, nullif(btrim(v_who), ''), new.note);
    end loop;
  exception when others then
    raise warning 'notifikasi dilewati: %', sqlerrm;
  end;
  return null;
end $$;
revoke all on function public.notif_on_doc_status() from public, anon, authenticated;
create trigger doc_status_history_notify after insert on public.doc_status_history
  for each row execute function public.notif_on_doc_status();

-- ---------------------------------------------------------------
-- Pemicu Purchase Request: perubahan status barang PR (satu email per lembar per status per proses)
-- ---------------------------------------------------------------
create or replace function public.notif_on_pr_items() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  rule public.notification_rules%rowtype;
  g record; v_who text;
begin
  begin
    select full_name into v_who from public.user_profiles where id = auth.uid();
    for g in
      select n.status as to_status, p.id as pr_id, p.doc_number, count(*) as cnt
        from new_t n join old_t o on o.id = n.id and o.status is distinct from n.status
        join public.purchase_requests p on p.id = n.pr_id
       group by n.status, p.id, p.doc_number
    loop
      for rule in select * from public.notification_rules where source = 'PR' and to_status = g.to_status and is_active loop
        perform public.notif_enqueue(rule, 'PR', g.pr_id, g.doc_number,
          case when v_who is not null then 'Diproses oleh ' || v_who || '.' else null end, null, g.cnt::integer, 'barang');
      end loop;
    end loop;
  exception when others then
    raise warning 'notifikasi PR dilewati: %', sqlerrm;
  end;
  return null;
end $$;
revoke all on function public.notif_on_pr_items() from public, anon, authenticated;
create trigger pr_items_notify after update on public.pr_items
  referencing old table as old_t new table as new_t
  for each statement execute function public.notif_on_pr_items();

-- ---------------------------------------------------------------
-- Pengiriman: aplikasi mengambil email yang dipicu oleh user itu sendiri, lalu melaporkan hasilnya.
-- ---------------------------------------------------------------
create or replace function public.notif_claim(p_limit integer default 50)
returns table (id bigint, to_email text, doc_type text, doc_id uuid, doc_number text, to_status text, subject text, message text)
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return; end if;
  return query
  with c as (
    select o.id from public.notification_outbox o
     where o.actor_id = auth.uid() and o.attempts < 3 and o.created_at > now() - interval '2 days'
       and (o.status = 'pending' or (o.status = 'sending' and o.claimed_at < now() - interval '5 minutes'))
     order by o.id limit greatest(1, least(p_limit, 200)) for update skip locked
  )
  update public.notification_outbox o set status = 'sending', attempts = o.attempts + 1, claimed_at = now()
    from c where o.id = c.id
  returning o.id, o.to_email, o.doc_type, o.doc_id, o.doc_number, o.to_status, o.subject, o.message;
end $$;
revoke all on function public.notif_claim(integer) from public, anon;
grant execute on function public.notif_claim(integer) to authenticated;

create or replace function public.notif_finish(p_id bigint, p_ok boolean, p_error text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.notification_outbox
     set status = case when p_ok then 'sent' when attempts >= 3 then 'failed' else 'pending' end,
         sent_at = case when p_ok then now() else null end,
         error = case when p_ok then null else left(coalesce(p_error, 'gagal'), 300) end
   where id = p_id and actor_id = auth.uid() and status = 'sending';
end $$;
revoke all on function public.notif_finish(bigint, boolean, text) from public, anon;
grant execute on function public.notif_finish(bigint, boolean, text) to authenticated;

-- Surel milik user sendiri (untuk email uji di halaman Notifikasi)
create or replace function public.my_email() returns text
language sql stable security definer set search_path = public as $$
  select au.email::text from auth.users au join public.user_profiles p on p.id = au.id and p.is_active where au.id = auth.uid();
$$;
revoke all on function public.my_email() from public, anon;
grant execute on function public.my_email() to authenticated;

-- ---------------------------------------------------------------
-- Aturan awal (alur RO -> Production Order -> Packing List -> Surat Jalan -> Invoice -> Pembayaran)
-- ---------------------------------------------------------------
insert into public.notification_rules (source, doc_type, to_status, module, action, title, todo) values
 ('DOC','RO',  'CONFIRMED', 'production_order', 'create',  'RO baru dikonfirmasi',               'Buat Production Order untuk RO ini.'),
 ('DOC','PROD','SUBMITTED', 'production_order', 'approve', 'Production Order menunggu persetujuan', 'Tinjau, lalu setujui atau tolak.'),
 ('DOC','PROD','APPROVED',  'packing_list',     'create',  'Production Order disetujui',         'Siapkan dan kemas barang, lalu buat Packing List.'),
 ('DOC','PROD','REJECTED',  'production_order', 'edit',    'Production Order ditolak',           'Baca alasannya, perbaiki, lalu ajukan lagi.'),
 ('DOC','PL',  'PACKED',    'delivery_order',   'create',  'Packing List selesai dikemas',       'Terbitkan Surat Jalan untuk pengiriman ini.'),
 ('DOC','DO',  'SENT',      'delivery_order',   'edit',    'Surat Jalan diterbitkan',            'Pantau pengiriman dan tandai diterima setelah barang sampai.'),
 ('DOC','DO',  'RECEIVED',  'invoice',          'create',  'Barang sudah diterima customer',     'Buat dan terbitkan Invoice.'),
 ('DOC','INV', 'ISSUED',    'crj',              'create',  'Invoice diterbitkan',                'Pantau pembayaran dan catat penerimaan (CRJ) saat dana masuk.'),
 ('DOC','JCP', 'WAITING',   'cpj_journal',      'approve', 'Cash Payment Journal menunggu ACC', 'Tinjau, lalu ACC atau kembalikan ke draf.'),
 ('DOC','JCP', 'ACC',       'cpj_journal',      'edit',    'Cash Payment Journal di-ACC',        'Dana dirilis; selesaikan realisasinya.'),
 ('DOC','JCP', 'DRAFT',     'cpj_journal',      'edit',    'Cash Payment Journal dikembalikan ke draf', 'Baca catatan Owner, perbaiki, lalu ajukan lagi.');
insert into public.notification_rules (source, doc_type, to_status, module, action, title, todo) values
 ('PR', null, 'SUBMITTED', 'purchase_request', 'approve', 'Barang PR menunggu persetujuan', 'Tinjau, lalu setujui atau tolak.'),
 ('PR', null, 'APPROVED',  'purchase_request', 'edit',    'Barang PR disetujui',            'Proses pembelian barang yang disetujui.'),
 ('PR', null, 'REJECTED',  'purchase_request', 'edit',    'Barang PR ditolak',              'Buka lembar PR untuk melihat alasannya.');
