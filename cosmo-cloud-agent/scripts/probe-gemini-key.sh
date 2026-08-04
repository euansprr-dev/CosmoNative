#!/bin/bash
# Verify a Gemini key can actually run tier-1 reel video understanding
# BEFORE it goes near Railway.
#
#   ./scripts/probe-gemini-key.sh <key>      # test a candidate key
#   ./scripts/probe-gemini-key.sh            # test whatever Railway has now
#
# Why this exists (Aug 4 2026): GEMINI_API_KEY was set and well-formed, but the
# Google project behind it was denied — every inference call 403'd and the
# worker rode the tier-2/3 fallback in silence for weeks. models.list still
# returned 200, so the key LOOKED healthy. Only the two calls tier 1 actually
# makes tell the truth, so this probes those.
set -euo pipefail

KEY="${1:-}"
if [ -z "$KEY" ]; then
  echo "→ no key argument; reading GEMINI_API_KEY from Railway"
  KEY=$(railway variables --kv | grep '^GEMINI_API_KEY=' | cut -d= -f2-)
fi
[ -n "$KEY" ] || { echo "✗ no key to test"; exit 1; }

API=https://generativelanguage.googleapis.com
MODEL="${GEMINI_VIDEO_MODEL:-gemini-3-flash-preview}"
echo "→ testing key ${KEY:0:6}… against $MODEL"
fail=0

# 1. models.list — cheap liveness. Passes even on a denied project, so it can
#    only ever DISPROVE the key, never bless it. Kept to separate "bad key"
#    from "denied project".
code=$(curl -s -o /tmp/probe-models.json -w "%{http_code}" "$API/v1beta/models?key=$KEY")
if [ "$code" = 200 ]; then
  echo "  ✓ models.list 200 (key is valid and recognised)"
else
  echo "  ✗ models.list $code — key itself is bad:"
  sed "s|$KEY|<REDACTED>|g" /tmp/probe-models.json | head -c 300; echo
  fail=1
fi

# 2. generateContent — the call every tier-1 request ends in. THIS is the gate.
code=$(curl -s -o /tmp/probe-gen.json -w "%{http_code}" -X POST \
  "$API/v1beta/models/$MODEL:generateContent?key=$KEY" \
  -H "Content-Type: application/json" \
  -d '{"contents":[{"parts":[{"text":"say ok"}]}]}')
if [ "$code" = 200 ]; then
  echo "  ✓ generateContent 200 (inference allowed)"
else
  echo "  ✗ generateContent $code:"
  sed "s|$KEY|<REDACTED>|g" /tmp/probe-gen.json | head -c 300; echo
  fail=1
fi

# 3. Files API resumable start — tier 1 uploads the video here first, so a key
#    that passes step 2 but fails here still can't do video.
code=$(curl -s -o /tmp/probe-files.json -w "%{http_code}" -X POST \
  "$API/upload/v1beta/files?key=$KEY" \
  -H "X-Goog-Upload-Protocol: resumable" \
  -H "X-Goog-Upload-Command: start" \
  -H "X-Goog-Upload-Header-Content-Length: 1024" \
  -H "X-Goog-Upload-Header-Content-Type: video/mp4" \
  -H "Content-Type: application/json" \
  -d '{"file":{"display_name":"probe"}}')
if [ "$code" = 200 ]; then
  echo "  ✓ files upload start 200 (video path open)"
else
  echo "  ✗ files upload start $code:"
  sed "s|$KEY|<REDACTED>|g" /tmp/probe-files.json | head -c 300; echo
  fail=1
fi

rm -f /tmp/probe-models.json /tmp/probe-gen.json /tmp/probe-files.json
if [ "$fail" = 0 ]; then
  echo "✅ tier 1 will work with this key."
else
  echo "❌ tier 1 will NOT work — the worker would fall back to tier 2/3 silently."
  echo "   'denied access' on 2/3 but a 200 on 1 = the Google PROJECT is blocked,"
  echo "   not the key. A new key on that same project fails identically."
  exit 1
fi
