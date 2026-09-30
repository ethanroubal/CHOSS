// Starts posting a send: creates the post (hidden until its video is ready) and a Mux direct
// upload URL. The app uploads the video file straight to Mux with that URL (a background
// upload, so it survives the app being closed); Mux transcodes it and calls mux-webhook.
//
// Request (signed in):  POST { placeId?, climbId?, routeName?, discipline, sendStyle,
//                              proposedGradeSystem?, proposedGradeValue?, caption? }
// Response:             { postId, uploadUrl }
//
// Secrets: MUX_TOKEN_ID, MUX_TOKEN_SECRET (plus the SUPABASE_* ones Supabase provides).

import { adminClient, currentUser, json, userClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  const user = await currentUser(req);
  if (!user) return json({ error: "Sign in first" }, 401);

  const body = await req.json().catch(() => null);
  if (!body?.discipline) return json({ error: "discipline is required" }, 400);

  // Insert as the user, so Row Level Security checks everything they're allowed to set.
  const { data: post, error } = await userClient(req)
    .from("posts")
    .insert({
      author_id: user.id,
      place_id: body.placeId ?? null,
      climb_id: body.climbId ?? null,
      route_name: body.routeName ?? "",
      discipline: body.discipline,
      send_style: body.sendStyle ?? "redpoint",
      proposed_grade_system: body.proposedGradeSystem ?? null,
      proposed_grade_value: body.proposedGradeValue ?? null,
      caption: body.caption ?? "",
    })
    .select("id")
    .single();
  if (error || !post) return json({ error: error?.message ?? "Couldn't create the post" }, 400);

  const auth = btoa(`${Deno.env.get("MUX_TOKEN_ID")}:${Deno.env.get("MUX_TOKEN_SECRET")}`);
  const mux = await fetch("https://api.mux.com/video/v1/uploads", {
    method: "POST",
    headers: { Authorization: `Basic ${auth}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      cors_origin: "*",
      new_asset_settings: {
        playback_policy: ["public"],
        passthrough: post.id,          // comes back in the webhook, to find the post
        max_resolution_tier: "1080p",
      },
    }),
  });
  if (!mux.ok) {
    await adminClient().from("posts").update({ video_status: "failed" }).eq("id", post.id);
    return json({ error: "Video service unavailable, try again" }, 502);
  }
  const upload = (await mux.json()).data;

  await adminClient().from("posts").update({ mux_upload_id: upload.id }).eq("id", post.id);
  return json({ postId: post.id, uploadUrl: upload.url });
});
