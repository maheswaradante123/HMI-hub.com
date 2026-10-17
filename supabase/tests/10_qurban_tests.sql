-- Pengujian Qurban Cerdas: kelas harga, baris invoice, nomor dokumen, alur status, izin.
\set ON_ERROR_STOP on
create function pg_temp.u(p text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claim.sub', p, true); set local role authenticated; end $$;
create function pg_temp.fails(p_sql text, p_code text) returns boolean language plpgsql as $$
begin execute p_sql; return false;
exception when others then return sqlstate = p_code; end $$;
do $$
declare
  own constant text := '00000000-0000-0000-0000-000000000001';
  mkt constant text := '00000000-0000-0000-0000-000000000002';
  acc constant text := '00000000-0000-0000-0000-000000000004';
  prd constant text := '00000000-0000-0000-0000-000000000005';
  a uuid; b uuid; c uuid; n integer; t numeric; due numeric; s text; r record; v_no text;
begin
  perform pg_temp.u(mkt);

  -- Kelas harga: batas atas/bawah dan di bawah 350 ditolak
  assert (public.qurban_class_at(350, '2026-10-01')).buy_price = 58000, 'kelas 350';
  assert (public.qurban_class_at(599.5, '2026-10-01')).buy_price = 58000, '599,5 masih kelas 350-599';
  assert (public.qurban_class_at(718, '2026-10-01')).care_price = 58000, 'kelas 700-799';
  assert (public.qurban_class_at(827, '2026-10-01')).buy_price = 75000, 'kelas 800-899';
  assert (public.qurban_class_at(1000, '2026-10-01')).buyback_price = 95000, 'kelas 900+';
  assert (public.qurban_class_at(349, '2026-10-01')).id is null, 'di bawah 350 tidak ada harga';
  assert pg_temp.fails($q$select public.qurban_create_order('#1','Budi',340,'2026-10-04','FULL')$q$, '22023'), 'bobot 340 ditolak';

  -- Nomor sapi boleh ganda; proforma terbentuk dengan harga kelas
  a := public.qurban_create_order('#004','Bapak Dandi',827,'2026-10-04','FULL');
  b := public.qurban_create_order('#004','Bapak Lain',700,'2026-10-04','MONTHLY');
  select count(*) into n from public.qurban_orders where cow_no = '#004';
  assert n = 2, 'nomor sapi ganda diizinkan';
  select pro_no into s from public.qurban_orders where id = a;
  assert s like 'PRO-INV-001-%-26' or s like 'PRO-INV-001-%-%', 'nomor proforma: ' || s;

  -- Baris invoice FULL: beli + perawatan tiap bulan sampai 17 Mei 2027 (flat)
  select count(*) into n from public.qurban_order_lines(a);
  assert n = 1 + 8, 'FULL: 1 baris beli + 8 bulan (Okt 2026 sampai Mei 2027), dapat ' || n;
  select qty * price into t from public.qurban_order_lines(a) where line_no = 1;
  assert t = 827 * 75000, 'nilai beli 827 x 75.000';
  select qty into t from public.qurban_order_lines(a) where line_no = 2;
  assert t = 28, 'Oktober mulai tanggal 4 = 28 hari';
  select qty into t from public.qurban_order_lines(a) where line_no = 9;
  assert t = 17, 'Mei berakhir tanggal 17 = 17 hari';
  select sum(qty) into t from public.qurban_order_lines(a) where line_no > 1;
  assert t = 28 + 30 + 31 + 31 + 28 + 31 + 30 + 17, 'total hari perawatan';
  -- MONTHLY: hanya bulan pertama di invoice awal
  select count(*) into n from public.qurban_order_lines(b);
  assert n = 2, 'MONTHLY: hanya bulan pertama';

  -- Diskon hanya Owner, hanya saat proforma
  assert pg_temp.fails(format($q$select public.qurban_set_discount(%L, 1000)$q$, a), '42501'), 'marketing tidak boleh memberi diskon';
  perform pg_temp.u(own);
  perform public.qurban_set_discount(a, 1263000);
  select due_amount into due from public.v_qurban_orders where id = a;
  select total into t from public.v_qurban_orders where id = a;
  assert due = t - 1263000, 'kekurangan = total - diskon';
  assert pg_temp.fails(format($q$select public.qurban_set_discount(%L, 999999999999)$q$, a), '22023'), 'diskon melebihi total ditolak';

  -- Alur status
  perform pg_temp.u(mkt);
  assert pg_temp.fails(format($q$select public.qurban_mark_paid(%L)$q$, a), '55000'), 'tidak bisa lunas sebelum invoice';
  v_no := public.qurban_issue_invoice(a);
  assert v_no like 'INV-001-%', 'nomor invoice pertama: ' || v_no;
  assert pg_temp.fails(format($q$select public.qurban_issue_invoice(%L)$q$, a), '55000'), 'invoice tidak terbit dua kali';
  assert pg_temp.fails(format($q$select public.qurban_save_sp(%L,'A','3201010101010001','Jl','','Brahman','2026-10-06')$q$, a), '55000'), 'SP belum bisa sebelum lunas';
  perform public.qurban_mark_paid(a);

  -- Surat perjanjian: KTP 16 angka, nomor tetap saat diedit
  assert pg_temp.fails(format($q$select public.qurban_save_sp(%L,'Dandi','123','Jl. Merpati','','Brahman','2026-10-06')$q$, a), '22023'), 'KTP harus 16 angka';
  perform public.qurban_save_sp(a, 'Dandi Prasetyo', '3201010101010001', 'Jl. Merpati No. 5', '0812', 'Brahman Cross', '2026-10-06');
  select sp_jb_no into s from public.qurban_buyer_details where order_id = a;
  assert s = 'SP-JB-001-X-AMF-26', 'nomor SP-JB: ' || s;
  perform public.qurban_save_sp(a, 'Dandi P.', '3201010101010001', 'Jl. Merpati No. 5', '0812', 'Brahman Cross', '2026-11-20');
  select sp_jb_no into s from public.qurban_buyer_details where order_id = a;
  assert s = 'SP-JB-001-X-AMF-26', 'nomor SP tidak berubah saat diedit';

  -- Penimbangan, tagihan bulanan memakai bobot terakhir sebelum bulan tagihan
  perform pg_temp.u(own);
  perform public.qurban_set_discount(b, 0);
  perform pg_temp.u(mkt);
  perform public.qurban_issue_invoice(b);
  perform public.qurban_mark_paid(b);
  perform pg_temp.u(own);
  perform public.qurban_add_weighing(b, public.qurban_today(), 805, 'QC');
  perform pg_temp.u(mkt);
  v_no := public.qurban_create_bill(b);
  select * into r from public.qurban_bills where order_id = b;
  assert r.ym = '2026-11', 'tagihan pertama = bulan setelah mulai, dapat ' || r.ym;
  assert r.days = 30, 'November 30 hari';
  assert pg_temp.fails(format($q$select public.qurban_create_bill(%L)$q$, a), '55000'), 'FULL tidak punya tagihan bulanan';
  perform public.qurban_mark_bill_paid(r.id);

  -- Pilihan pemilik dan QC
  perform public.qurban_set_choice(b, 'SELL_BACK');
  assert pg_temp.fails(format($q$select public.qurban_set_choice(%L,'APA_SAJA')$q$, b), '22023'), 'pilihan tidak valid';
  perform pg_temp.u(own);
  perform public.qurban_create_qc(to_char(public.qurban_today(), 'YYYY-MM'), 'Bapak Dandi');
  assert (select count(*) from public.qurban_qc_reports) = 1, 'QC dibuat';
  perform public.qurban_create_qc(to_char(public.qurban_today(), 'YYYY-MM'), 'Bapak Dandi');
  assert (select count(*) from public.qurban_qc_reports) = 1, 'QC tidak dobel untuk bulan dan pelanggan yang sama';

  -- Pembatalan
  perform pg_temp.u(own);
  c := public.qurban_create_order('#050','Ibu Sari',400,public.qurban_today(),'FULL');
  assert pg_temp.fails(format($q$select public.qurban_cancel(%L,'')$q$, c), '22023'), 'alasan batal wajib';
  perform public.qurban_cancel(c, 'Pelanggan batal');
  assert (select status from public.qurban_orders where id = c) = 'CANCELLED', 'status batal';
  assert pg_temp.fails(format($q$select public.qurban_cancel(%L,'x')$q$, a), '55000'), 'yang lunas tidak bisa dibatalkan';

  -- Izin: accounting tidak melihat KTP kecuali berhak edit; produksi hanya penimbangan
  perform pg_temp.u(acc);
  assert (select count(*) from public.qurban_orders) >= 3, 'accounting melihat pesanan';
  assert pg_temp.fails(format($q$select public.qurban_create_order('#9','X',500,'2026-10-04','FULL')$q$), '42501'), 'accounting tidak membuat pesanan';
  perform pg_temp.u(prd);
  assert (select count(*) from public.qurban_buyer_details) = 0, 'produksi tidak melihat data KTP';
  assert (select count(*) from public.qurban_bills) = 0, 'produksi tidak melihat tagihan';
  perform public.qurban_add_weighing(b, public.qurban_today(), 810, 'Timbang kandang');
  assert pg_temp.fails(format($q$select public.qurban_issue_invoice(%L)$q$, b), '42501'), 'produksi tidak menerbitkan invoice';
  -- Tidak ada penulisan langsung ke tabel
  assert pg_temp.fails($q$insert into public.qurban_orders (cow_no, customer_nick, start_date, initial_weight, pay_mode, class_min, buy_price, care_price, buyback_price) values ('1','x','2026-10-01',500,'FULL',350,1,1,1)$q$, '42501'), 'tulis langsung ditolak';
  raise notice 'SEMUA PENGUJIAN QURBAN LULUS';
end $$;
