#!/bin/bash
# Re-kick every swipe the worker left stranded while OpenRouter's balance was
# empty (Aug 29 – Sept 4 2026): 'partial' / 'needs_manual_retry' /
# 'extraction_failed', plus 'complete' rows that never got an insight pass and
# 'pending' rows nothing is going to pick up. Each kick is cheap: transcripts
# are banked (priorTranscript skips vision), mirrored carousels download
# nothing, so a pass is one Apify run + one classification call.
#
#   ./scripts/rekick-stuck-swipes.sh                 # since 2026-08-28, kick
#   ./scripts/rekick-stuck-swipes.sh --dry-run       # list only
#   ./scripts/rekick-stuck-swipes.sh --since 2026-08-01
#
# Run AFTER deploying (railway up from the Mac repo root). Kicks are spaced so
# the worker never runs more than a couple of passes at once — the /process
# route has no concurrency bound of its own.
set -euo pipefail
cd "$(dirname "$0")/.."

SINCE="2026-08-28T00:00:00Z"
DRY=0
SPACING="${KICK_SPACING_SECONDS:-40}"
while [ $# -gt 0 ]; do
  case "$1" in
    --since) SINCE="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) echo "unknown arg $1"; exit 1 ;;
  esac
done

eval "$(railway variables --json | python3 -c "
import sys, json
d = json.load(sys.stdin)
print('SB_URL=' + d['SUPABASE_URL'])
print('SB_KEY=' + d['SUPABASE_SERVICE_ROLE_KEY'])
print('CUID=' + d['COSMO_USER_ID'])
")"

LIST=$(curl -s "$SB_URL/rest/v1/atoms?select=uuid,title,updated_at,created_at,metadata,structured&user_id=eq.$CUID&type=eq.research&is_deleted=eq.false&metadata->>isSwipeFile=eq.true&updated_at=gte.$SINCE&order=created_at.asc&limit=200" \
  -H "apikey: $SB_KEY" -H "Authorization: Bearer $SB_KEY" | python3 -c "
import sys, json, datetime
rows = json.load(sys.stdin)
now = datetime.datetime.now(datetime.timezone.utc)
for r in rows:
    m = r.get('metadata') or {}
    s = r.get('structured') or {}
    if isinstance(m, str): m = json.loads(m)
    if isinstance(s, str):
        try: s = json.loads(s)
        except Exception: s = {}
    status = m.get('processingStatus')
    url = m.get('url') or s.get('sourceUrl') or ''
    if not any(k in url for k in ('instagram.com', 'youtube.com', 'youtu.be', 'twitter.com', 'x.com')): continue
    if (m.get('swipeKind') or 'post') != 'post': continue
    an = (s.get('swipeAnalysis') or {}) if isinstance(s, dict) else {}
    has_insight = bool(an.get('keyInsight')) or bool(an.get('hookType'))
    upd = datetime.datetime.fromisoformat(r['updated_at'].replace('Z', '+00:00'))
    age_min = (now - upd).total_seconds() / 60
    reason = None
    if status in ('partial', 'needs_manual_retry', 'extraction_failed'): reason = status
    elif status == 'complete' and not has_insight: reason = 'complete-without-insight'
    elif status in ('pending', 'extracting', 'transcribing', 'analyzing') and age_min > 30: reason = f'{status}-stale-{int(age_min)}m'
    if reason:
        print(f\"{r['uuid']}\t{reason}\t{(r.get('title') or '')[:48]}\")
")

COUNT=$(printf '%s\n' "$LIST" | grep -c . || true)
echo "→ $COUNT swipe(s) to re-kick (updated since $SINCE):"
printf '%s\n' "$LIST" | awk -F'\t' '{ printf "   %s  %-26s  %s\n", substr($1,1,8), $2, $3 }'
[ "$DRY" = "1" ] && exit 0
[ "$COUNT" = "0" ] && exit 0

i=0
while IFS=$'\t' read -r uuid reason title; do
  [ -z "$uuid" ] && continue
  i=$((i + 1))
  code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    https://cosmonative-production.up.railway.app/api/swipes/process \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $SB_KEY" \
    -d "{\"swipeUUID\": \"$uuid\"}")
  echo "[$i/$COUNT] kicked ${uuid:0:8} ($reason) → HTTP $code"
  [ "$i" -lt "$COUNT" ] && sleep "$SPACING"
done <<< "$LIST"
echo "✓ done — watch: railway logs --lines 200"
