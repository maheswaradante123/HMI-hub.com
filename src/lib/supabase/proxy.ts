import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

// Menyegarkan sesi login di setiap request dan mengarahkan tamu ke /login.
// Halaman /login sendiri yang mengalihkan user valid ke beranda.
// Ini hanya lapis pertama. Izin modul tetap dicek di server (lib/auth.ts)
// dan di database (RLS).
export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll: () => request.cookies.getAll(),
        setAll: (items) => {
          items.forEach(({ name, value }) => request.cookies.set(name, value));
          response = NextResponse.next({ request });
          items.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options),
          );
        },
      },
    },
  );

  // getClaims memeriksa tanda tangan token secara lokal (tanpa memanggil server
  // Auth di setiap halaman), jadi jauh lebih cepat dari getUser.
  const { data: claimsData } = await supabase.auth.getClaims();
  const user = claimsData?.claims?.sub ? { id: claimsData.claims.sub } : null;

  const isLogin = request.nextUrl.pathname.startsWith("/login");

  if (!user && !isLogin) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.search = "";
    return NextResponse.redirect(url);
  }
  return response;
}
