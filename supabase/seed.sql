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
-- PR per barang (migrasi 0021): Accounting melihat semua PR; Purchasing dan Accounting boleh unduh PDF/Excel PR
select pg_temp.g('ACCOUNTING','purchase_request_all','{view}');
select pg_temp.g('PURCHASING','purchase_request','{export}');
select pg_temp.g('ACCOUNTING','purchase_request','{export}');


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
select pg_temp.gq('ACCOUNTING','cpj_journal','{view,create,edit,delete,export}');
select pg_temp.gq('PURCHASING','cpj_journal','{view}');

-- ===============================================================
-- Seed Phase 4: master data dummy
-- ===============================================================
insert into public.units (code, name) values
  ('KG','Kilogram'), ('PCS','Pcs'), ('PACK','Pack'), ('BOX','Box'), ('ROLL','Roll')
on conflict do nothing;

insert into public.product_categories (code, name) values
  ('DAGING','Daging'), ('TULANG','Tulang'), ('JEROHAN','Jerohan'),
  ('BUMBU','Bumbu dan Saus'), ('ALAT','Peralatan'), ('KEMASAN','Kemasan')
on conflict do nothing;

insert into public.cow_types (code, name) values ('BX','BX') on conflict do nothing;

insert into public.non_carcass_types (code, name) values
  ('BUNTUT','Buntut'), ('KEPALA','Kepala'), ('JEROHAN','Jerohan'),
  ('KAKI','Kaki'), ('KULIT','Kulit')
on conflict do nothing;

insert into public.cost_types (code, name) values
  ('TRANSPORT','Transport'), ('FEE','Fee'), ('POTONG','Biaya Potong'),
  ('BONING','Biaya Boning'), ('TIDAK_LANGSUNG','Ongkos Tidak Langsung'),
  ('RESELLER','Reseller'), ('BONUS_BO','Bonus Back Office'), ('BONUS_JUAL','Bonus Penjualan')
on conflict do nothing;

insert into public.payment_methods (code, name) values
  ('TRANSFER','Transfer Bank'), ('TUNAI','Tunai'), ('KOPRA','KOPRA')
on conflict do nothing;

insert into public.warehouses (code, name) values
  ('GD-TOKO','Gudang Toko') on conflict do nothing;

insert into public.locations (warehouse_id, code, name)
select w.id, v.code, v.name
  from public.warehouses w,
       (values ('CHILLER','Chiller'), ('FREEZER','Freezer'), ('RAK','Rak Kering')) as v(code, name)
 where w.code = 'GD-TOKO'
on conflict do nothing;

insert into public.accounts (code, name, type, account_ref) values
  ('KAS-TOKO','Kas Toko','CASH', null),
  ('BANK-A','Rekening Bank Dummy','BANK','DUMMY-0000')
on conflict do nothing;

insert into public.customers (code, name, type, payment_term_days) values
  ('HOTEL-A','Hotel A','HOREKA',14),
  ('RESTO-A','Restaurant A','HOREKA',7),
  ('CATERING-A','Catering A','HOREKA',14),
  ('JAGAL-A','Pembeli Non-Karkas A','NON_CARCASS_BUYER',0)
on conflict do nothing;

insert into public.suppliers (code, name, type) values
  ('SUP-SAPI-A','Supplier Sapi A','COW'),
  ('SUP-RESELLER-A','Supplier Reseller A','RESELLER'),
  ('SUP-SUPPORT-A','Supplier Supporting A','SUPPORTING')
on conflict do nothing;

insert into public.products (code, name, product_type, category_id, unit_id, min_stock)
select v.code, v.name, v.ptype, c.id, u.id, v.min_stock
  from (values
    ('MF-TOPSIDE','Topside','MANUFACTURE','DAGING','KG', 20),
    ('MF-SENGKEL','Sengkel','MANUFACTURE','DAGING','KG', 15),
    ('MF-HAS-DALAM','Has Dalam','MANUFACTURE','DAGING','KG', 10),
    ('MF-TULANG-SOP','Tulang Sop','MANUFACTURE','TULANG','KG', 10),
    ('RS-BUMBU-BAMBOE','Bumbu Bamboe','RESELLER','BUMBU','PCS', 24),
    ('RS-FIESTA','Fiesta','RESELLER','BUMBU','PACK', 12),
    ('RS-ABC-SAOS','ABC Saos','RESELLER','BUMBU','PCS', 24),
    ('SP-PLASTIK-VACUUM','Plastik Vacuum','SUPPORTING','KEMASAN','ROLL', 5),
    ('SP-SARUNG-TANGAN','Sarung Tangan','SUPPORTING','ALAT','BOX', 3),
    ('SP-PISAU','Pisau','SUPPORTING','ALAT','PCS', 2)
  ) as v(code, name, ptype, cat, unit, min_stock)
  join public.product_categories c on c.code = v.cat
  join public.units u on u.code = v.unit
on conflict do nothing;

-- ===============================================================
-- Seed Phase 6: harga dummy (berlaku sejak 1 Oktober 2026)
-- ===============================================================
insert into public.product_prices (product_id, supplier_id, buy_price, sell_price, effective_from, note)
select p.id, s.id, v.buy, v.sell, date '2026-10-01', 'Harga awal (data contoh)'
  from (values
    ('MF-TOPSIDE',      null,             null,   138000),
    ('MF-SENGKEL',      null,             null,   118000),
    ('MF-HAS-DALAM',    null,             null,   175000),
    ('MF-TULANG-SOP',   null,             null,    45000),
    ('RS-ABC-SAOS',     'SUP-RESELLER-A', 10000,   13000),
    ('RS-BUMBU-BAMBOE', 'SUP-RESELLER-A',  8000,   10500),
    ('RS-FIESTA',       'SUP-RESELLER-A', 22000,   27000)
  ) as v(code, sup, buy, sell)
  join public.products p on p.code = v.code
  left join public.suppliers s on s.code = v.sup
 where not exists (select 1 from public.product_prices x where x.product_id = p.id);
