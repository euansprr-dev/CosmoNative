-- Durable discovery thumbnails (July 2026).
-- Scraped CDN thumbnail URLs (Instagram especially) expire within weeks; the
-- worker now mirrors each post's thumbnail to Supabase Storage at scrape time
-- (atom-images/<user>/discover-thumbs/) and records the durable URL here.
-- Run once in the Supabase SQL editor. The worker degrades gracefully (warns
-- once, keeps serving CDN URLs) until this column exists.

alter table public.social_discovered_posts
  add column if not exists thumbnail_storage_url text;
