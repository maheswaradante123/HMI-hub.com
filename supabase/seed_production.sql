-- HMI Internal System - seed Phase 3 (data dummy untuk development)
insert into public.departments (name) values
  ('Owner'), ('Marketing'), ('Purchasing'), ('Accounting'),
  ('Produksi Toko'), ('Kasir'), ('Kandang'), ('GA')
on conflict (name) do nothing;

insert into public.roles (code, name, description, is_superuser) values
  ('OWNER',      'Owner',         'Akses penuh; juga berfungsi sebagai PPIC dan approver PR', true),
  ('MARKETING',  'Marketing',     'RO, customer, Production Order',                            false),
  ('PURCHASING', 'Purchasing',    'PR, supplier, pricing, analisa pembelian, penimbangan karkas', false),
  ('ACCOUNTING', 'Accounting',    'Operasional (lihat) dan keuangan penuh',                    false),
  ('PRODUKSI',   'Produksi Toko', 'Packing list, penimbangan karkas, stok',                    false),
  ('KASIR',      'Kasir',         'Stok dan harga untuk operasional toko',                     false)
on conflict (code) do nothing;

insert into public.permissions (module, action)
select m.module, a.action
from unnest(array[
  'dashboard','ro','customer','production_order','packing_list','delivery',
  'stock','stock_opname','carcass_weighing','purchase_request','purchase_request_all','supplier',
  'pricing','pricing_cost','purchase_analysis','noncarcass_sale','invoice','crj','cpj',
  'salary','product','master_data','report','user','role','audit_log'
]) as m(module)
cross join unnest(array['view','create','edit','delete','approve','export']) as a(action)
on conflict (module, action) do nothing;

create or replace function pg_temp.grant_perm(p_role text, p_module text, p_actions text[])
returns void language sql as $$
  insert into public.role_permissions (role_id, permission_id)
  select r.id, p.id
    from public.roles r, public.permissions p
   where r.code = p_role and p.module = p_module and p.action = any(p_actions)
  on conflict do nothing;
$$;

-- OWNER: is_superuser, tidak perlu baris role_permissions.

select pg_temp.grant_perm('MARKETING','dashboard',        '{view}');
select pg_temp.grant_perm('MARKETING','customer',         '{view,create,edit}');
select pg_temp.grant_perm('MARKETING','ro',               '{view,create,edit}');
select pg_temp.grant_perm('MARKETING','production_order', '{view,create,edit}');
select pg_temp.grant_perm('MARKETING','packing_list',     '{view}');
select pg_temp.grant_perm('MARKETING','delivery',         '{view}');
select pg_temp.grant_perm('MARKETING','pricing',          '{view}');
select pg_temp.grant_perm('MARKETING','stock',            '{view}');
select pg_temp.grant_perm('MARKETING','purchase_request', '{view,create}');
select pg_temp.grant_perm('MARKETING','product',          '{view}');
select pg_temp.grant_perm('MARKETING','report',           '{view}');

select pg_temp.grant_perm('PURCHASING','dashboard',         '{view}');
select pg_temp.grant_perm('PURCHASING','purchase_request',  '{view,create,edit}');
select pg_temp.grant_perm('PURCHASING','purchase_request_all','{view}');
select pg_temp.grant_perm('PURCHASING','supplier',          '{view,create,edit}');
select pg_temp.grant_perm('PURCHASING','pricing',           '{view,create,edit}');
select pg_temp.grant_perm('PURCHASING','pricing_cost',      '{view}');
select pg_temp.grant_perm('PURCHASING','purchase_analysis', '{view,create,edit,export}');
select pg_temp.grant_perm('PURCHASING','carcass_weighing',  '{view,create,edit}');
select pg_temp.grant_perm('PURCHASING','noncarcass_sale',   '{view,create,edit}');
select pg_temp.grant_perm('PURCHASING','customer',          '{view}');   -- memilih pembeli non-karkas
select pg_temp.grant_perm('PURCHASING','stock',             '{view}');
select pg_temp.grant_perm('PURCHASING','cpj',               '{view}');
select pg_temp.grant_perm('PURCHASING','product',           '{view,create,edit}');
select pg_temp.grant_perm('PURCHASING','master_data',       '{view,create,edit}');
select pg_temp.grant_perm('PURCHASING','report',            '{view,export}');

select pg_temp.grant_perm('ACCOUNTING', m, '{view}')
from unnest(array[
  'dashboard','ro','customer','production_order','packing_list','delivery',
  'stock','stock_opname','carcass_weighing','purchase_request','purchase_request_all','supplier',
  'pricing','pricing_cost','purchase_analysis','noncarcass_sale','product','master_data'
]) as m;
select pg_temp.grant_perm('ACCOUNTING', m, '{view,create,edit,delete,export}')
from unnest(array['invoice','crj','cpj','salary']) as m;
select pg_temp.grant_perm('ACCOUNTING','report','{view,export}');
-- Accounting boleh menambah dan mengubah master umum (jenis biaya, satuan, rekening, dst).
select pg_temp.grant_perm('ACCOUNTING','master_data','{create,edit}');

select pg_temp.grant_perm('PRODUKSI','dashboard',        '{view}');
select pg_temp.grant_perm('PRODUKSI','ro',               '{view}');
select pg_temp.grant_perm('PRODUKSI','production_order', '{view}');
select pg_temp.grant_perm('PRODUKSI','packing_list',     '{view,create,edit}');
select pg_temp.grant_perm('PRODUKSI','delivery',         '{view}');
select pg_temp.grant_perm('PRODUKSI','carcass_weighing', '{view,create,edit}');
select pg_temp.grant_perm('PRODUKSI','pricing',          '{view}');
select pg_temp.grant_perm('PRODUKSI','stock',            '{view,create,edit}');
select pg_temp.grant_perm('PRODUKSI','stock_opname',     '{view,create,edit}');
select pg_temp.grant_perm('PRODUKSI','purchase_request', '{view,create}');
select pg_temp.grant_perm('PRODUKSI','product',          '{view}');
select pg_temp.grant_perm('PRODUKSI','customer',         '{view}');   -- nama customer di packing list

-- KASIR: izin sama persis dengan PRODUKSI (keputusan Owner).
insert into public.role_permissions (role_id, permission_id)
select k.id, rp.permission_id
  from public.roles k
  join public.roles p on p.code = 'PRODUKSI'
  join public.role_permissions rp on rp.role_id = p.id
 where k.code = 'KASIR'
on conflict do nothing;

-- Revisi: matriks RBAC sesuai gambar Owner (sama dengan migrasi 0010)
-- Hapus izin lama non-Owner pada modul yang diatur matriks
delete from public.role_permissions rp using public.roles r, public.permissions p
 where rp.role_id = r.id and rp.permission_id = p.id and r.code <> 'OWNER'
   and p.module in ('customer','ro','production_order','packing_list','carcass_weighing','purchase_request','supplier','pricing','purchase_analysis','stock','stock_opname','noncarcass_sale','invoice','report');

create or replace function pg_temp.g(p_role text, p_module text, p_actions text[]) returns void language sql as $f$
  insert into public.role_permissions (role_id, permission_id) select r.id, p.id from public.roles r, public.permissions p
   where r.code = p_role and p.module = p_module and p.action = any(p_actions) on conflict do nothing;
$f$;

select pg_temp.g('MARKETING','customer','{view,create,edit}');
select pg_temp.g('ACCOUNTING','customer','{view}');
select pg_temp.g('MARKETING','ro','{view,create,edit}');
select pg_temp.g('ACCOUNTING','ro','{view}');
select pg_temp.g('PRODUKSI','ro','{view}');
select pg_temp.g('MARKETING','production_order','{view,create,edit}');
select pg_temp.g('ACCOUNTING','production_order','{view}');
select pg_temp.g('PRODUKSI','production_order','{view,edit}');
select pg_temp.g('KASIR','production_order','{view}');
select pg_temp.g('MARKETING','packing_list','{view}');
select pg_temp.g('ACCOUNTING','packing_list','{view}');
select pg_temp.g('PRODUKSI','packing_list','{view,create,edit}');
select pg_temp.g('KASIR','packing_list','{view}');
select pg_temp.g('PURCHASING','carcass_weighing','{view}');
select pg_temp.g('ACCOUNTING','carcass_weighing','{view}');
select pg_temp.g('PRODUKSI','carcass_weighing','{view,create,edit}');
select pg_temp.g('KASIR','carcass_weighing','{view}');
select pg_temp.g('MARKETING','purchase_request','{view,create}');
select pg_temp.g('PURCHASING','purchase_request','{view,create,edit}');
select pg_temp.g('ACCOUNTING','purchase_request','{view}');
select pg_temp.g('PRODUKSI','purchase_request','{view,create}');
select pg_temp.g('KASIR','purchase_request','{view,create}');
select pg_temp.g('PURCHASING','supplier','{view,create,edit}');
select pg_temp.g('ACCOUNTING','supplier','{view}');
select pg_temp.g('MARKETING','pricing','{view}');
select pg_temp.g('PURCHASING','pricing','{view,create,edit}');
select pg_temp.g('ACCOUNTING','pricing','{view}');
select pg_temp.g('PRODUKSI','pricing','{view}');
select pg_temp.g('KASIR','pricing','{view}');
select pg_temp.g('PURCHASING','purchase_analysis','{view,create,edit,export}');
select pg_temp.g('ACCOUNTING','purchase_analysis','{view}');
select pg_temp.g('MARKETING','stock','{view}');
select pg_temp.g('MARKETING','stock_opname','{view}');
select pg_temp.g('PURCHASING','stock','{view}');
select pg_temp.g('PURCHASING','stock_opname','{view}');
select pg_temp.g('ACCOUNTING','stock','{view}');
select pg_temp.g('ACCOUNTING','stock_opname','{view}');
select pg_temp.g('PRODUKSI','stock','{view,create,edit}');
select pg_temp.g('PRODUKSI','stock_opname','{view,create,edit}');
select pg_temp.g('KASIR','stock','{view,create,edit}');
select pg_temp.g('KASIR','stock_opname','{view,create,edit}');
select pg_temp.g('MARKETING','noncarcass_sale','{view}');
select pg_temp.g('ACCOUNTING','noncarcass_sale','{view}');
select pg_temp.g('PRODUKSI','noncarcass_sale','{view}');
select pg_temp.g('KASIR','noncarcass_sale','{view,create,edit}');
select pg_temp.g('PURCHASING','invoice','{view}');
select pg_temp.g('ACCOUNTING','invoice','{view,create,edit,delete,approve,export}');
select pg_temp.g('MARKETING','report','{view}');
select pg_temp.g('PURCHASING','report','{view}');
select pg_temp.g('ACCOUNTING','report','{view,export}');

-- Persetujuan PR hanya Owner (kolom Approve di matriks)
delete from public.role_permissions rp using public.roles r, public.permissions p
 where rp.role_id=r.id and rp.permission_id=p.id and r.code<>'OWNER' and p.action='approve' and p.module='purchase_request';


-- Qurban Cerdas: izin awal (sama dengan migrasi 0012; aman dijalankan ulang).
-- Role belum ada saat migrasi dijalankan pada database baru, jadi diulang di sini.
create or replace function pg_temp.gq(p_role text, p_module text, p_actions text[]) returns void language sql as $f$
  insert into public.role_permissions (role_id, permission_id) select r.id, p.id from public.roles r, public.permissions p
   where r.code = p_role and p.module = p_module and p.action = any(p_actions) on conflict do nothing;
$f$;
select pg_temp.gq('MARKETING','qurban','{view,create,edit,export}');
select pg_temp.gq('MARKETING','qc_report','{view}');
select pg_temp.gq('ACCOUNTING','qurban','{view,edit,export}');
select pg_temp.gq('ACCOUNTING','qc_report','{view}');
select pg_temp.gq('PRODUKSI','qc_report','{view,create}');
select pg_temp.gq('ACCOUNTING','store_income','{view,create,edit,delete,export}');
select pg_temp.gq('MARKETING','delivery_order','{view,create,edit,export}');
select pg_temp.gq('PRODUKSI','delivery_order','{view,create,edit,export}');
select pg_temp.gq('ACCOUNTING','delivery_order','{view,export}');

