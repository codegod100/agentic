#!/usr/bin/env bash
# Create or update the weekly Buildkite schedule for the agentic mirror pipeline.
#
# Usage:
#   BUILDKITE_API_TOKEN=bkua_... ./scripts/setup-buildkite-schedule.sh
#
# Optional:
#   BUILDKITE_ORG_SLUG=nandi
#   BUILDKITE_PIPELINE_SLUG=agentic-n45Zp8   # auto-discovered when unset
#   SCHEDULE_CRONLINE='17 6 * * 1'           # Mondays 06:17 UTC (matches GHA update-packages)
set -euo pipefail

ORG="${BUILDKITE_ORG_SLUG:-nandi}"
CRON="${SCHEDULE_CRONLINE:-17 6 * * 1}"
LABEL="${SCHEDULE_LABEL:-Weekly GitHub mirror}"
BRANCH="${SCHEDULE_BRANCH:-main}"
RID_SUFFIX="n45Zp8"

log()  { printf '==> %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ -n "${BUILDKITE_API_TOKEN:-}" ]] || die "BUILDKITE_API_TOKEN is required"

auth=(-H "Authorization: Bearer ${BUILDKITE_API_TOKEN}")

discover_pipeline() {
  if [[ -n "${BUILDKITE_PIPELINE_SLUG:-}" ]]; then
    printf '%s' "$BUILDKITE_PIPELINE_SLUG"
    return
  fi
  local slug
  slug="$(
    curl -fsS "${auth[@]}" \
      "https://api.buildkite.com/v2/organizations/${ORG}/pipelines" \
      | python3 -c "
import json, sys
rid_suffix = sys.argv[1]
for p in json.load(sys.stdin):
    slug = p.get('slug') or ''
    name = (p.get('name') or '').lower()
    if rid_suffix.lower() in slug.lower() or 'agentic' in name:
        print(slug)
        break
" "$RID_SUFFIX"
  )"
  [[ -n "$slug" ]] || die "could not find agentic pipeline in org ${ORG}; set BUILDKITE_PIPELINE_SLUG"
  printf '%s' "$slug"
}

PIPELINE="$(discover_pipeline)"
log "pipeline: ${ORG}/${PIPELINE}"

existing="$(
  curl -fsS "${auth[@]}" \
    "https://api.buildkite.com/v2/organizations/${ORG}/pipelines/${PIPELINE}/schedules" \
    | python3 -c '
import json, sys
label = sys.argv[1]
for s in json.load(sys.stdin):
    if s.get("label") == label:
        print(s["id"])
        break
' "$LABEL"
)"

payload="$(python3 -c '
import json, sys
label, branch, cron = sys.argv[1:4]
print(json.dumps({
    "label": label,
    "branch": branch,
    "commit": "HEAD",
    "message": label,
    "cronline": cron,
    "enabled": True,
    "env": {"FORCE_MIRROR": "true"},
}))
' "$LABEL" "$BRANCH" "$CRON")"

if [[ -n "$existing" ]]; then
  log "updating schedule ${existing}"
  curl -fsS -X PATCH "${auth[@]}" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "https://api.buildkite.com/v2/organizations/${ORG}/pipelines/${PIPELINE}/schedules/${existing}" \
    | python3 -m json.tool
else
  log "creating schedule"
  curl -fsS -X POST "${auth[@]}" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "https://api.buildkite.com/v2/organizations/${ORG}/pipelines/${PIPELINE}/schedules" \
    | python3 -m json.tool
fi

log "done (${CRON} on ${BRANCH})"
