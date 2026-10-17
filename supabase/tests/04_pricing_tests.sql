-- Pengujian Phase 6 (Pricing Toko). Jalankan setelah 01 sampai 03.
\set ON_ERROR_STOP on

do $$
declare
  mkt  constant text := '00000000-0000-0000-0000-000000000002';
  pur  constant text := '00000000-0000-0000-0000-000000000003';
  acc  constant text := '00000000-0000-0000-0000-000000000004';
  prod constant text := '00000000-0000-0000-0000-000000000005';
  own  constant text := '00000000-0000-0000-0000-000000000001';
  v_abc uuid; v_sup uuid; v_top uuid; v_pisau uuid; v_id uuid; v_n int;
  v_buy numeric; v_sell numeric; v_sup_seen uuid; v_to date; v_from date;
begin
  select id into v_abc   from public.products  where code = 'RS-ABC-SAOS';
  select id into v_top   from public.products  where code = 'MF-TOPSIDE';
  select id into v_pisau from public.products  where code = 'SP-PISAU';
  select id into v_sup   from public.suppliers where code = 'SUP-RESELLER-A';
  update public.products set is_active = false where id = v_pisau;

  select count(*) into v_n from public.product_prices; assert v_n = 7, 'seed harga, dapat ' || v_n;

  -- Visibilitas harga beli per role
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', mkt, true);
  select buy_price, sell_price, supplier_id into v_buy, v_sell, v_sup_seen from public.v_product_prices where product_id = v_abc;
  assert v_buy is null and v_sup_seen is null, 'marketing tidak boleh lihat harga beli/supplier';
  assert v_sell = 13000, 'marketing lihat harga jual';
  perform set_config('request.jwt.claim.sub', prod, true);
  select buy_price into v_buy from public.v_product_prices where product_id = v_abc;
  assert v_buy is null, 'produksi tidak boleh lihat harga beli';
  perform set_config('request.jwt.claim.sub', pur, true);
  select buy_price, supplier_id into v_buy, v_sup_seen from public.v_product_prices where product_id = v_abc;
  assert v_buy = 10000 and v_sup_seen = v_sup, 'purchasing lihat harga beli dan supplier';
  perform set_config('request.jwt.claim.sub', acc, true);
  select buy_price into v_buy from public.v_product_prices where product_id = v_abc;
  assert v_buy = 10000, 'accounting lihat harga beli';

  -- Tidak bisa membaca/menulis tabel langsung
  begin perform 1 from public.product_prices; raise exception 'select langsung seharusnya ditolak';
  exception when insufficient_privilege then null; end;
  begin update public.product_prices set sell_price = 1; raise exception 'update langsung seharusnya ditolak';
  exception when insufficient_privilege then null; end;
  begin insert into public.product_prices (product_id, sell_price, effective_from) values (v_abc, 1, current_date);
    raise exception 'insert langsung seharusnya ditolak';
  exception when insufficient_privilege then null; end;
  set local role anon;
  begin perform 1 from public.v_product_prices; raise exception 'anon tidak boleh membaca harga';
  exception when insufficient_privilege then null; end;
  set local role authenticated;

  -- Yang tidak berizin tidak bisa mengubah harga
  foreach v_id in array array[mkt::uuid, prod::uuid, acc::uuid] loop
    perform set_config('request.jwt.claim.sub', v_id::text, true);
    begin perform public.set_product_price(v_abc, null, null, 15000, current_date + 60);
      raise exception 'role % seharusnya tidak bisa ubah harga', v_id;
    exception when insufficient_privilege then null; end;
  end loop;

  -- Purchasing menetapkan harga berlaku tanggal depan
  perform set_config('request.jwt.claim.sub', pur, true);
  v_from := current_date + 30;
  v_id := public.set_product_price(v_abc, v_sup, 11000, 14000, v_from, 'Kenaikan dari supplier');
  reset role;
  select effective_to into v_to from public.product_prices where product_id = v_abc and sell_price = 13000;
  assert v_to = v_from - 1, 'harga lama ditutup sehari sebelum harga baru berlaku';
  select count(*) into v_n from public.product_prices where product_id = v_abc; assert v_n = 2, 'harga lama tetap tersimpan';
  set local role authenticated; perform set_config('request.jwt.claim.sub', pur, true);
  select sell_price into v_sell from public.v_current_prices where product_id = v_abc;
  assert v_sell = 13000, 'harga masa depan belum berlaku hari ini';

  -- Aturan tanggal
  begin perform public.set_product_price(v_abc, v_sup, 12000, 15000, v_from);
    raise exception 'tanggal sama seharusnya ditolak';
  exception when invalid_parameter_value then null; end;
  begin perform public.set_product_price(v_abc, v_sup, 12000, 15000, current_date);
    raise exception 'tanggal lebih awal seharusnya ditolak';
  exception when invalid_parameter_value then null; end;
  begin perform public.set_product_price(v_abc, null, null, null, current_date + 90);
    raise exception 'tanpa harga seharusnya ditolak';
  exception when invalid_parameter_value then null; end;
  begin perform public.set_product_price(v_abc, null, null, -5, current_date + 90);
    raise exception 'harga negatif seharusnya ditolak';
  exception when invalid_parameter_value or check_violation then null; end;
  begin perform public.set_product_price(v_abc, null, null, 1000, null);
    raise exception 'tanpa tanggal seharusnya ditolak';
  exception when invalid_parameter_value then null; end;
  begin perform public.set_product_price(v_pisau, null, null, 1000, current_date);
    raise exception 'produk nonaktif seharusnya ditolak';
  exception when no_data_found then null; end;
  begin perform public.set_product_price(gen_random_uuid(), null, null, 1000, current_date);
    raise exception 'produk tidak ada seharusnya ditolak';
  exception when no_data_found then null; end;

  -- Koreksi: batalkan harga terakhir
  select id into v_id from public.v_product_prices where product_id = v_abc and sell_price = 13000;
  begin perform public.void_product_price(v_id, 'salah');
    raise exception 'harga yang bukan terakhir tidak boleh dibatalkan';
  exception when object_not_in_prerequisite_state then null; end;
  select id into v_id from public.v_product_prices where product_id = v_abc and sell_price = 14000;
  begin perform public.void_product_price(v_id, '  ');
    raise exception 'alasan kosong seharusnya ditolak';
  exception when invalid_parameter_value then null; end;
  perform set_config('request.jwt.claim.sub', prod, true);
  begin perform public.void_product_price(v_id, 'salah ketik');
    raise exception 'produksi tidak boleh membatalkan';
  exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claim.sub', pur, true);
  perform public.void_product_price(v_id, 'Salah ketik, seharusnya 14.500');
  begin perform public.void_product_price(v_id, 'lagi');
    raise exception 'batalkan dua kali seharusnya ditolak';
  exception when object_not_in_prerequisite_state then null; end;
  reset role;
  select effective_to into v_to from public.product_prices where product_id = v_abc and sell_price = 13000;
  assert v_to is null, 'harga sebelumnya dibuka kembali';
  select count(*) into v_n from public.product_prices where product_id = v_abc and voided_at is not null and void_reason like 'Salah ketik%';
  assert v_n = 1, 'baris batal tetap ada dengan alasan';
  set local role authenticated; perform set_config('request.jwt.claim.sub', pur, true);

  -- Setelah dibatalkan, harga yang benar bisa dimasukkan pada tanggal yang sama
  v_id := public.set_product_price(v_abc, v_sup, 11000, 14500, v_from);
  select count(*) into v_n from public.v_product_prices where product_id = v_abc; assert v_n = 3, 'riwayat 3 baris termasuk yang batal, dapat ' || v_n;

  -- Produk manufacture tanpa harga beli
  v_id := public.set_product_price(v_top, null, null, 140000, current_date + 10);

  -- Izin pricing tanpa izin biaya: boleh harga jual, tidak boleh harga beli
  reset role;
  insert into public.user_permission_overrides (user_id, permission_id, is_granted)
    select mkt::uuid, id, true from public.permissions where module = 'pricing' and action in ('create','edit')
  on conflict (user_id, permission_id) do update set is_granted = true;
  set local role authenticated; perform set_config('request.jwt.claim.sub', mkt, true);
  begin perform public.set_product_price(v_abc, null, 9000, null, current_date + 120);
    raise exception 'tanpa izin biaya tidak boleh isi harga beli';
  exception when insufficient_privilege then null; end;
  begin perform public.set_product_price(v_abc, v_sup, null, 16000, current_date + 120);
    raise exception 'tanpa izin biaya tidak boleh isi supplier';
  exception when insufficient_privilege then null; end;
  perform public.set_product_price(v_abc, null, null, 16000, current_date + 120);

  -- Pelindung di tingkat tabel (pemilik database pun tidak bisa menimpa/hapus)
  reset role;
  begin update public.product_prices set sell_price = 1 where product_id = v_top;
    raise exception 'update harga langsung seharusnya ditolak';
  exception when raise_exception then
    if sqlerrm not like 'harga hanya boleh diubah%' then raise; end if; end;
  begin delete from public.product_prices where product_id = v_top;
    raise exception 'hapus riwayat harga seharusnya ditolak';
  exception when raise_exception then
    if sqlerrm not like 'riwayat harga tidak boleh dihapus%' then raise; end if; end;
  begin insert into public.product_prices (product_id, sell_price, effective_from, effective_to)
      values (v_top, 1, current_date + 10, current_date + 20);
    raise exception 'periode tumpang tindih seharusnya ditolak';
  exception when exclusion_violation then null; end;
  perform set_config('hmi.price_fn', 'on', true);
  begin update public.product_prices set sell_price = 1 where product_id = v_top;
    raise exception 'nilai harga seharusnya tidak bisa diubah walau lewat fungsi';
  exception when raise_exception then
    if sqlerrm not like 'nilai harga yang sudah tercatat%' then raise; end if; end;
  perform set_config('hmi.price_fn', 'off', true);

  -- Audit trail
  select count(*) into v_n from public.audit_logs
   where table_name = 'product_prices' and action = 'UPDATE' and new_values->>'void_reason' like 'Salah ketik%' and user_id = pur::uuid;
  assert v_n = 1, 'audit pembatalan harga tercatat dengan pelaku';
  select count(*) into v_n from public.audit_logs
   where table_name = 'product_prices' and action = 'INSERT' and user_id = pur::uuid;
  assert v_n >= 2, 'audit penetapan harga tercatat';
end $$;

\echo SEMUA PENGUJIAN PHASE 6 LULUS
