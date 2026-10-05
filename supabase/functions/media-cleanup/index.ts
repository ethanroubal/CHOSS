// Removes media nobody can see any more (queued by the database, see
// migrations/20261005000000_media_cleanup.sql). Run hourly by pg_cron:
//   1. marks uploads abandoned for a day as failed (which queues them),
//   2. deletes queued Mux videos (or cancels unfinished uploads),
//   3. deletes queued Storage files (replaced profile pictures).
//
// Request: POST with header x-cleanup-secret: <CLEANUP_SECRET>. Response: what it removed.
// Secrets: CLEANUP_SECRET, MUX_TOKEN_ID, MUX_TOKEN_SECRET (plus the SUPABASE_* ones).
// Deploy with --no-verify-jwt (set in config.toml): the shared secret authenticates the caller.

import { adminClient, json } from "../_shared/supabase.ts";

/** Gives up on an item after this many failed tries (it's logged, then dropped). */
const MAX_ATTEMPTS = 10;

Deno.serve(async (req) => {
  const secret = Deno.env.get("CLEANUP_SECRET");
  if (!secret || req.headers.get("x-cleanup-secret") !== secret) {
    return json({ error: "forbidden" }, 403);
  }
  const db = adminClient();

  // 1. Abandoned uploads.
  const { data: swept, error: sweepError } = await db.rpc("sweep_stale_uploads");
  if (sweepError) console.error("sweep_stale_uploads", sweepError.message);

  // 2. Mux.
  const muxAuth = `Basic ${btoa(`${Deno.env.get("MUX_TOKEN_ID")}:${Deno.env.get("MUX_TOKEN_SECRET")}`)}`;
  const { data: muxJobs } = await db.from("mux_cleanup")
    .select("kind,mux_id,attempts").order("queued_at").limit(200);
  let muxRemoved = 0;
  for (const job of muxJobs ?? []) {
    const url = job.kind === "asset"
      ? `https://api.mux.com/video/v1/assets/${job.mux_id}`
      : `https://api.mux.com/video/v1/uploads/${job.mux_id}/cancel`;
    const res = await fetch(url, {
      method: job.kind === "asset" ? "DELETE" : "PUT",
      headers: { Authorization: muxAuth },
    });
    await res.body?.cancel();
    // Gone already (404), or an upload that can't be cancelled any more (it became an asset,
    // which is queued separately, or timed out): nothing left to do.
    const done = res.ok || res.status === 404 || (job.kind === "upload" && res.status >= 400 && res.status < 500
      && res.status !== 401 && res.status !== 403 && res.status !== 429);
    if (done || job.attempts + 1 >= MAX_ATTEMPTS) {
      if (!done) console.error(`Giving up on Mux ${job.kind} ${job.mux_id}: HTTP ${res.status}`);
      await db.from("mux_cleanup").delete().eq("kind", job.kind).eq("mux_id", job.mux_id);
      if (done) muxRemoved++;
    } else {
      await db.from("mux_cleanup").update({ attempts: job.attempts + 1 })
        .eq("kind", job.kind).eq("mux_id", job.mux_id);
    }
  }

  // 3. Storage.
  const { data: files } = await db.from("storage_cleanup")
    .select("bucket,path,attempts").order("queued_at").limit(500);
  let filesRemoved = 0;
  const byBucket = new Map<string, { path: string; attempts: number }[]>();
  for (const file of files ?? []) {
    byBucket.set(file.bucket, [...(byBucket.get(file.bucket) ?? []), file]);
  }
  for (const [bucket, items] of byBucket) {
    const paths = items.map((item) => item.path);
    const { error } = await db.storage.from(bucket).remove(paths);
    if (!error) {
      await db.from("storage_cleanup").delete().eq("bucket", bucket).in("path", paths);
      filesRemoved += paths.length;
    } else {
      console.error(`Storage remove (${bucket})`, error.message);
      for (const item of items) {
        if (item.attempts + 1 >= MAX_ATTEMPTS) {
          await db.from("storage_cleanup").delete().eq("bucket", bucket).eq("path", item.path);
        } else {
          await db.from("storage_cleanup").update({ attempts: item.attempts + 1 })
            .eq("bucket", bucket).eq("path", item.path);
        }
      }
    }
  }

  return json({ abandonedUploads: swept ?? 0, muxRemoved, filesRemoved });
});
