-- Pengujian RBAC + RLS. Jalankan setelah mock, migrasi, dan seed.
\set ON_ERROR_STOP on

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001','owner@test'),
  ('00000000-0000-0000-0000-000000000002','marketing@test'),
  ('00000000-0000-0000-0000-000000000003','purchasing@test'),
  ('00000000-0000-0000-0000-000000000004','accounting@test'),
  ('00000000-0000-0000-0000-000000000005','produksi@test'),
  ('00000000-0000-0000-0000-000000000006','kasir@test'),
  ('00000000-0000-0000-0000-000000000007','nonaktif@test'),
  ('00000000-0000-0000-0000-000000000008','tanpaprofil@test');

insert into public.user_profiles (id, full_name, role_id, is_active)
select u.id, split_part(u.email,'@',1), r.id, (u.email <> 'nonaktif@test')
  from auth.users u
  join public.roles r on r.code = case split_part(u.email,'@',1)
    when 'owner' then 'OWNER' when 'marketing' then 'MARKETING'
    when 'purchasing' then 'PURCHASING' when 'accounting' then 'ACCOUNTING'
    when 'produksi' then 'PRODUKSI' when 'kasir' then 'KASIR'
    when 'nonaktif' then 'MARKETING' end
 where u.email <> 'tanpaprofil@test';

do $$ begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
  assert public.has_permission('ro','create'),              'marketing: ro create';
  assert public.has_permission('production_order','edit'),  'marketing: production_order edit';
  assert public.has_permission('production_order','create'),'marketing: PO create (keputusan Owner)';
  assert not public.has_permission('pricing','edit'),       'marketing: pricing edit harus ditolak';
  assert not public.has_permission('invoice','view'),       'marketing: invoice view harus ditolak';
end $$;

do $$ begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',true);
  assert public.has_permission('production_order','view'),       'produksi: PO view';
  assert not public.has_permission('production_order','create'), 'produksi: PO create harus ditolak';
  assert public.has_permission('carcass_weighing','create'),     'produksi: karkas create';
  assert public.has_permission('pricing','view'),                'produksi: pricing view';
  assert not public.has_permission('pricing','edit'),            'produksi: pricing edit harus ditolak';
end $$;

do $$ begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);
  assert public.has_permission('carcass_weighing','view'),        'purchasing: karkas view';
  assert not public.has_permission('carcass_weighing','edit'),    'purchasing: karkas edit ditolak (matriks)';
  assert public.has_permission('pricing','create'),               'purchasing: pricing create';
  assert not public.has_permission('purchase_request','approve'), 'purchasing: approve PR ditolak';
  assert not public.has_permission('invoice','create'),           'purchasing: invoice create ditolak (hanya lihat)';
end $$;

do $$ begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000004',true);
  assert public.has_permission('purchase_request','view'),         'accounting: PR view';
  assert not public.has_permission('purchase_request','approve'),  'accounting: approve PR ditolak';
  assert public.has_permission('invoice','delete'),                'accounting: invoice cancel';
  assert not public.has_permission('user','view'),                 'accounting: admin user ditolak';
end $$;

do $$ begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000006',true);
  assert public.has_permission('stock','edit'),       'kasir: stock edit';
  assert not public.has_permission('pricing','edit'), 'kasir: pricing edit ditolak';
end $$;

do $$ begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  assert public.has_permission('purchase_request','approve'), 'owner: approve PR';
  assert public.has_permission('audit_log','view'),           'owner: audit log';
end $$;

do $$ begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000007',true);
  assert not public.has_permission('ro','view'), 'nonaktif ditolak';
end $$;
do $$ begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000008',true);
  assert not public.has_permission('dashboard','view'), 'tanpa profil ditolak';
end $$;
do $$ begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','',true);
  assert not public.has_permission('dashboard','view'), 'tanpa login ditolak';
end $$;
do $$ begin
  set local role anon;
  begin
    perform public.has_permission('dashboard','view');
    raise exception 'anon seharusnya tidak boleh memanggil has_permission';
  exception when insufficient_privilege then null;
  end;
end $$;

insert into public.user_permission_overrides (user_id, permission_id, is_granted)
select '00000000-0000-0000-0000-000000000002', id, true
  from public.permissions where module='pricing' and action='edit';
insert into public.user_permission_overrides (user_id, permission_id, is_granted)
select '00000000-0000-0000-0000-000000000002', id, false
  from public.permissions where module='ro' and action='create';
do $$ begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
  assert public.has_permission('pricing','edit'),  'override grant berlaku';
  assert not public.has_permission('ro','create'), 'override revoke berlaku';
  assert public.has_permission('ro','edit'),       'izin role lain tetap';
end $$;

do $$
declare n int; ok1 boolean; ok2 boolean;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);
  select count(*), bool_or(module='purchase_request' and action='edit'),
         bool_or(module='purchase_request' and action='approve')
    into n, ok1, ok2 from public.my_permissions();
  assert n > 10 and ok1 and not ok2, 'my_permissions purchasing tidak sesuai';
end $$;

do $$
declare n int;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
  select count(*) into n from public.user_profiles;
  assert n = 1, 'marketing hanya lihat profil sendiri, dapat ' || n;
  update public.user_profiles set role_id=(select id from public.roles where code='OWNER')
   where id='00000000-0000-0000-0000-000000000002';
  get diagnostics n = row_count;
  assert n = 0, 'marketing tidak boleh ubah role sendiri';
  begin
    insert into public.roles(code,name) values ('HACK','Hack');
    raise exception 'marketing seharusnya tidak bisa membuat role';
  exception when insufficient_privilege then null;
  end;
  select count(*) into n from public.audit_logs;
  assert n = 0, 'marketing tidak boleh baca audit log';
end $$;

do $$
declare n int;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  select count(*) into n from public.user_profiles;
  assert n = 7, 'owner lihat semua profil, dapat ' || n;
  begin
    delete from public.user_profiles where id='00000000-0000-0000-0000-000000000002';
    raise exception 'owner seharusnya tidak bisa menghapus profil';
  exception when insufficient_privilege then null;
  end;
  update public.user_profiles set full_name='Marketing Baru'
   where id='00000000-0000-0000-0000-000000000002';
  select count(*) into n from public.audit_logs
   where table_name='user_profiles' and action='UPDATE'
     and old_values->>'full_name'='marketing' and new_values->>'full_name'='Marketing Baru'
     and user_id='00000000-0000-0000-0000-000000000001';
  assert n = 1, 'audit UPDATE harus tercatat dengan pelaku';
end $$;

do $$ begin
  begin
    update public.audit_logs set action='INSERT' where id=(select min(id) from public.audit_logs);
    raise exception 'audit_logs seharusnya tidak bisa diubah';
  exception when raise_exception then
    if sqlerrm not like 'audit_logs tidak boleh%' then raise; end if;
  end;
end $$;

-- Matriks Owner: Kasir tidak lagi identik dengan Produksi.
do $$ begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000006',true);
  assert public.has_permission('noncarcass_sale','create'),  'kasir: penjualan toko create';
  assert not public.has_permission('packing_list','create'), 'kasir: packing list hanya lihat';
  assert public.has_permission('stock','edit'),              'kasir: stok edit';
  assert not public.has_permission('purchase_request','approve'), 'kasir: approve PR ditolak';
end $$;

\echo SEMUA PENGUJIAN LULUS
