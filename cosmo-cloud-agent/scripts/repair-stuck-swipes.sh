#!/bin/bash
# One-shot repair for the swipes the OLD worker left stuck at 'partial'
# (insight pass failed every time — Sonnet 5 adaptive thinking ate the whole
# max_tokens budget on long transcripts; fixed in src/swipes/analyze.ts).
#
# Run AFTER deploying cosmo-cloud-agent (`railway up` from the Mac repo root).
# Each kick is analysis-only: the transcript is already banked, priorTranscript
# skips vision entirely, so this costs five cheap classification calls.
set -euo pipefail

KEY=$(railway variables --json | python3 -c "import json,sys; print(json.load(sys.stdin)['SUPABASE_SERVICE_ROLE_KEY'])")

STUCK=(
  4B1EBDF4-3D54-4E9D-BBE8-5A889CB7AD8F
  E709D8A3-B172-4642-A710-A2C1B1555AF0
  A90D01C8-9B60-472B-9619-9EC93A9E47A3
  493DC3E6-934F-4A07-A413-8CF5E06767FD
  87AF1B99-FCEE-4D2B-8E60-76D340F3896C
)

for uuid in "${STUCK[@]}"; do
  status=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    https://cosmonative-production.up.railway.app/api/swipes/process \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $KEY" \
    -d "{\"swipeUUID\": \"$uuid\"}")
  echo "kicked ${uuid:0:8} → HTTP $status"
  sleep 2
done

echo "Watch: railway logs | grep -E 'insight|complete|🧹'"
