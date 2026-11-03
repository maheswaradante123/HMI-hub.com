-- Migrasi data: Master Sapi Qurban Cerdas 2026-2027 (Google Sheet) -> menu Qurban (Master Pesanan).
-- Jalankan SEKALI di Supabase SQL Editor setelah migrasi 0030. Atomik: gagal sama sekali atau berhasil seluruhnya.
-- Dibuat oleh scripts/gen_qurban_master.py.
do $mig$
declare
  d jsonb := $json$__DATA__$json$::jsonb;
  s jsonb := $json$__SEQ__$json$::jsonb;
  e jsonb; b jsonb;
  v_id uuid; v_cls public.qurban_price_classes; v_end date := public.qurban_setting('care_end')::date;
  v_dup text; v_start date; v_w numeric; v_ym text; v_first date;
  n_o integer := 0; n_b integer := 0;
begin
  if exists (select 1 from public.qurban_orders where is_legacy) then
    raise exception 'Data master sapi sudah pernah dimasukkan (sudah ada pesanan arsip). Skrip ini tidak dijalankan lagi.';
  end if;
  select string_agg(x.cow || ' ' || x.nick || ' (' || x.start_d || ')', '; ') into v_dup
    from (select j->>'cow' as cow, j->>'nick' as nick, j->>'start' as start_d from jsonb_array_elements(d) j) x
    join public.qurban_orders o on o.cow_no = x.cow and o.customer_nick = x.nick and o.start_date = x.start_d::date and o.deleted_at is null;
  if v_dup is not null then
    raise exception 'Pesanan berikut sudah ada di aplikasi dengan nomor sapi, pelanggan, dan tanggal mulai yang sama: %. Hapus atau batalkan dulu, atau hubungi saya.', v_dup;
  end if;

  for e in select * from jsonb_array_elements(d) loop
    v_start := (e->>'start')::date; v_w := (e->>'weight')::numeric;
    v_cls := public.qurban_class_at(v_w, public.qurban_today());
    if v_cls.id is null then
      raise exception 'Bobot % Kg (sapi % %) di bawah 350 Kg: tidak ada kelas harga', v_w, e->>'cow', e->>'nick';
    end if;
    insert into public.qurban_orders (cow_no, customer_nick, start_date, initial_weight, pay_mode, class_min, class_max,
           buy_price, care_price, buyback_price, discount, status, pro_no, pro_date, inv_no, inv_date, due_date, paid_at,
           is_legacy, sp_jb_no, sp_pl_no)
    values (e->>'cow', e->>'nick', v_start, v_w, e->>'mode', v_cls.min_kg, v_cls.max_kg,
            (e->>'buy_price')::numeric, (e->>'care_price')::numeric, v_cls.buyback_price, (e->>'discount')::numeric, e->>'status',
            nullif(e->>'pro_no', ''), nullif(e->>'buy_date', '')::date,
            nullif(e->>'inv_no', ''), case when nullif(e->>'inv_no', '') is not null then (e->>'buy_date')::date end,
            case when nullif(e->>'inv_no', '') is not null then (e->>'buy_date')::date end,
            case when e->>'status' = 'PAID' then ((e->>'buy_date') || ' 12:00+07')::timestamptz end,
            true, nullif(e->>'sp_jb', ''), nullif(e->>'sp_pl', ''))
    returning id into v_id;
    insert into public.qurban_weighings (order_id, weigh_date, weight, note) values (v_id, v_start, v_w, 'Timbang awal (arsip)');
    n_o := n_o + 1;

    for b in select * from jsonb_array_elements(e->'bills') loop
      v_ym := b->>'ym'; v_first := (v_ym || '-01')::date;
      insert into public.qurban_bills (order_id, bill_no, ym, days, rate, basis_weight, bill_date, due_date, status, paid_at, is_legacy)
      values (v_id, b->>'no', v_ym, coalesce((b->>'days')::integer, public.qurban_days(v_ym, v_start, v_end)), (e->>'care_price')::numeric, v_w,
              v_first, v_first + 7, b->>'status',
              case when b->>'status' = 'PAID' then (v_first::text || ' 12:00+07')::timestamptz end, true);
      n_b := n_b + 1;
    end loop;
  end loop;

  -- Nomor baru dari aplikasi melanjutkan urutan nomor di sheet (tidak bentrok dengan nomor lama).
  insert into public.qurban_sequences (kind, ym, last_number)
  select x->>'kind', x->>'ym', (x->>'n')::integer from jsonb_array_elements(s) x
  on conflict (kind, ym) do update set last_number = greatest(public.qurban_sequences.last_number, excluded.last_number);

  raise notice 'Selesai: % pesanan arsip, % tagihan bulanan.', n_o, n_b;
end
$mig$;
