-- Pengujian Phase 4. Jalankan setelah 01_access_tests.sql (memakai user uji yang sama).
\set ON_ERROR_STOP on

-- Seed terisi dan tipe produk terpisah
do $$
declare n int;
begin
  select count(*) into n from public.products where product_type='MANUFACTURE'; assert n = 4, 'manufacture ' || n;
  select count(*) into n from public.products where product_type='RESELLER';    assert n = 3, 'reseller ' || n;
  select count(*) into n from public.products where product_type='SUPPORTING'; assert n = 3, 'supporting ' || n;
  select count(*) into n from public.cost_types;                               assert n = 9, 'cost_types ' || n;
  select count(*) into n from public.customers where type='HOREKA';            assert n = 3, 'horeka ' || n;
end $$;

-- Constraint data
do $$ begin
  begin
    insert into public.products (code,name,product_type,unit_id)
    select 'X1','X','LAINNYA',id from public.units limit 1;
    raise exception 'tipe produk tidak valid seharusnya ditolak';
  exception when check_violation then null; end;

  begin
    insert into public.units (code,name) values ('kg','Kilogram Lagi');
    raise exception 'kode huruf kecil seharusnya ditolak';
  exception when check_violation then null; end;

  begin
    insert into public.units (code,name) values ('KG2','kilogram');
    raise exception 'nama ganda (beda huruf besar/kecil) seharusnya ditolak';
  exception when unique_violation then null; end;

  begin
    insert into public.units (code,name) values ('KG','Lain');
    raise exception 'kode ganda seharusnya ditolak';
  exception when unique_violation then null; end;

  begin
    insert into public.products (code,name,product_type,unit_id,min_stock)
    select 'NEG','Negatif','RESELLER',id,-1 from public.units limit 1;
    raise exception 'min_stock negatif seharusnya ditolak';
  exception when check_violation then null; end;

  begin
    insert into public.customers (code,name,type,payment_term_days) values ('NEG','Neg','HOREKA',-1);
    raise exception 'termin negatif seharusnya ditolak';
  exception when check_violation then null; end;
end $$;

-- Marketing: boleh kelola customer, hanya lihat produk, tidak lihat supplier/rekening
do $$
declare n int;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
  insert into public.customers (code,name,type) values ('CUST-MKT','Customer Marketing','HOREKA');
  update public.customers set phone='0812' where code='CUST-MKT';
  select count(*) into n from public.products;  assert n = 10, 'marketing lihat produk, dapat ' || n;
  select count(*) into n from public.suppliers; assert n = 0, 'marketing tidak boleh lihat supplier';
  select count(*) into n from public.accounts;  assert n = 0, 'marketing tidak boleh lihat rekening';
  select count(*) into n from public.units;     assert n = 8, 'semua user lihat satuan';
  begin
    insert into public.products (code,name,product_type,unit_id)
    select 'MKT-P','P','RESELLER',id from public.units limit 1;
    raise exception 'marketing seharusnya tidak bisa membuat produk';
  exception when insufficient_privilege then null; end;
  update public.products set min_stock = 999 where code='MF-TOPSIDE';
  get diagnostics n = row_count;
  assert n = 0, 'marketing tidak boleh ubah produk';
end $$;

-- Purchasing: kelola supplier, tidak bisa ubah master umum
do $$
declare n int;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);
  insert into public.suppliers (code,name,type) values ('SUP-PUR','Supplier Purchasing','COW');
  select count(*) into n from public.suppliers; assert n = 4, 'purchasing lihat supplier, dapat ' || n;
  insert into public.cost_types (code,name) values ('BIAYA-PUR','Biaya dari Purchasing');
  insert into public.products (code,name,product_type,unit_id)
    select 'PUR-P','Produk Purchasing','RESELLER',id from public.units where code='PCS';
  update public.products set min_stock = 6 where code='PUR-P';
  get diagnostics n = row_count;
  assert n = 1, 'purchasing boleh ubah produk';
  begin
    delete from public.products where code='PUR-P';
    raise exception 'purchasing tidak boleh menghapus produk';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.customers (code,name,type) values ('PUR-C','Cust','HOREKA');
    raise exception 'purchasing seharusnya tidak bisa membuat customer';
  exception when insufficient_privilege then null; end;
end $$;

-- Produksi: lihat produk saja
do $$
declare n int;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',true);
  select count(*) into n from public.products; assert n >= 10, 'produksi lihat produk';
  update public.products set name='Hack' where code='MF-TOPSIDE';
  get diagnostics n = row_count;
  assert n = 0, 'produksi tidak boleh ubah produk';
end $$;

-- Accounting: lihat rekening, tidak bisa mengubah
do $$
declare n int;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000004',true);
  select count(*) into n from public.accounts; assert n = 2, 'accounting lihat rekening, dapat ' || n;
  insert into public.cost_types (code,name) values ('BIAYA-ACC','Biaya dari Accounting');
  update public.accounts set name='Kas Toko Utama' where code='KAS-TOKO';
  get diagnostics n = row_count;
  assert n = 1, 'accounting boleh ubah master umum';
  begin
    insert into public.products (code,name,product_type,unit_id)
    select 'ACC-P','P','RESELLER',id from public.units limit 1;
    raise exception 'accounting seharusnya tidak bisa membuat produk';
  exception when insufficient_privilege then null; end;
end $$;

-- Owner: kelola semua, tambah jenis biaya, nonaktifkan, tidak bisa menghapus
do $$
declare n int; actor uuid;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  insert into public.cost_types (code,name) values ('BARU','Biaya Baru');
  update public.products set is_active=false where code='SP-PISAU';
  select updated_by into actor from public.products where code='SP-PISAU';
  assert actor = '00000000-0000-0000-0000-000000000001', 'updated_by harus terisi pengguna';
  select created_by into actor from public.cost_types where code='BARU';
  assert actor = '00000000-0000-0000-0000-000000000001', 'created_by harus terisi pengguna';
  begin
    delete from public.products where code='SP-PISAU';
    raise exception 'delete produk seharusnya ditolak';
  exception when insufficient_privilege then null; end;
  -- created_by tidak bisa dipalsukan lewat update
  update public.products set created_by = '00000000-0000-0000-0000-000000000002' where code='MF-SENGKEL';
  select created_by into actor from public.products where code='MF-SENGKEL';
  assert actor is distinct from '00000000-0000-0000-0000-000000000002', 'created_by tidak boleh diubah';
  -- audit trail perubahan produk
  select count(*) into n from public.audit_logs
   where table_name='products' and action='UPDATE'
     and old_values->>'is_active'='true' and new_values->>'is_active'='false'
     and user_id='00000000-0000-0000-0000-000000000001';
  assert n = 1, 'audit nonaktifkan produk harus tercatat';
end $$;

\echo SEMUA PENGUJIAN PHASE 4 LULUS
