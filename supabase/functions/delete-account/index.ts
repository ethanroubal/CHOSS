// "Delete my account" (required by the App Store for apps with sign-up). Removes the user's
// pictures from Storage, then the auth user; the database cascades to their profile, posts,
// likes, follows, comments, photos… Their videos' Mux assets are removed by a cleanup job
// (see docs/BACKEND_PLAN.md).
//
// Request (signed in): POST (no body). Response: { ok: true }

import { adminClient, currentUser, json } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  const user = await currentUser(req);
  if (!user) return json({ error: "Sign in first" }, 401);

  const db = adminClient();
  for (const bucket of ["avatars", "community-photos"]) {
    const { data: files } = await db.storage.from(bucket).list(user.id, { limit: 1000 });
    if (files?.length) {
      await db.storage.from(bucket).remove(files.map((f) => `${user.id}/${f.name}`));
    }
  }
  const { error } = await db.auth.admin.deleteUser(user.id);
  if (error) return json({ error: error.message }, 500);
  return json({ ok: true });
});
