// Mux calls this as a video moves through processing. When it's ready, the post gets its
// playback id and becomes visible in feeds.
//
// Mux dashboard -> Settings -> Webhooks: point it at
//   https://<project>.supabase.co/functions/v1/mux-webhook
// and store its signing secret as MUX_WEBHOOK_SECRET. Deploy with --no-verify-jwt (Mux
// doesn't send a Supabase session; the signature check below authenticates it instead).

import { adminClient, json } from "../_shared/supabase.ts";

async function validSignature(header: string | null, body: string): Promise<boolean> {
  const secret = Deno.env.get("MUX_WEBHOOK_SECRET");
  if (!header || !secret) return false;
  const parts = Object.fromEntries(header.split(",").map((p) => p.split("=") as [string, string]));
  const timestamp = Number(parts.t);
  if (!timestamp || Math.abs(Date.now() / 1000 - timestamp) > 300) return false;  // 5 min window
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${parts.t}.${body}`));
  const expected = Array.from(new Uint8Array(mac)).map((b) => b.toString(16).padStart(2, "0")).join("");
  return expected === parts.v1;
}

Deno.serve(async (req) => {
  const raw = await req.text();
  if (!(await validSignature(req.headers.get("mux-signature"), raw))) {
    return json({ error: "bad signature" }, 401);
  }
  const event = JSON.parse(raw);
  const data = event.data ?? {};
  const db = adminClient();

  switch (event.type) {
    case "video.upload.asset_created":
      await db.from("posts")
        .update({ mux_asset_id: data.asset_id, video_status: "processing" })
        .eq("mux_upload_id", data.id);
      break;

    case "video.asset.ready": {
      const [w, h] = String(data.aspect_ratio ?? "").split(":").map(Number);
      await db.from("posts")
        .update({
          mux_asset_id: data.id,
          mux_playback_id: data.playback_ids?.[0]?.id ?? null,
          video_duration: data.duration ?? null,
          video_aspect_ratio: w && h ? w / h : null,
          video_status: "ready",
        })
        .eq("id", data.passthrough);
      break;
    }

    case "video.asset.errored":
      await db.from("posts").update({ video_status: "failed" }).eq("id", data.passthrough);
      break;
  }
  return json({ ok: true });
});
