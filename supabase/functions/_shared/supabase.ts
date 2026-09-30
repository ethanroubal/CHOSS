import { createClient, type SupabaseClient, type User } from "jsr:@supabase/supabase-js@2";

/** Server-side client (bypasses Row Level Security). Never send this key to the app. */
export function adminClient(): SupabaseClient {
  return createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
}

/** A client acting as the signed-in user who called the function (Row Level Security applies). */
export function userClient(req: Request): SupabaseClient {
  return createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    auth: { persistSession: false },
  });
}

/** The signed-in user, or null if the request has no valid session. */
export async function currentUser(req: Request): Promise<User | null> {
  const { data } = await userClient(req).auth.getUser();
  return data.user ?? null;
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
