-- Percepat my_permissions(): sebelumnya memanggil has_permission() untuk setiap
-- baris izin (sekitar 150 kali, tiap panggilan beberapa query) di setiap halaman.
-- Versi ini satu query set-based dengan aturan yang sama persis:
--   1) override per user menang, 2) superuser lolos, 3) selain itu cek role_permissions.
-- User atau role nonaktif tidak mendapat izin apa pun.
create or replace function public.my_permissions()
returns table (module text, action text)
language sql stable security definer
set search_path = public
as $$
  with me as (
    select r.id as role_id, r.is_superuser
      from public.user_profiles p
      join public.roles r on r.id = p.role_id
     where p.id = auth.uid() and p.is_active and r.is_active
  )
  select p.module, p.action
    from me
   cross join public.permissions p
    left join public.user_permission_overrides o
           on o.user_id = auth.uid() and o.permission_id = p.id
   where case
           when o.permission_id is not null then o.is_granted
           when me.is_superuser then true
           else exists (
             select 1 from public.role_permissions rp
              where rp.role_id = me.role_id and rp.permission_id = p.id
           )
         end;
$$;

revoke all on function public.my_permissions() from public, anon;
grant execute on function public.my_permissions() to authenticated;
