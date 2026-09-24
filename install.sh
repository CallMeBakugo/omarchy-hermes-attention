#!/usr/bin/env bash
# Install the Hermes attention hook + bar widget placement.
# Run from the repo root after `omarchy plugin add`-ing this repo.
set -euo pipefail

cd "$(dirname "$0")"

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
HOOK_DEST="$HERMES_HOME/agent-hooks/attention.sh"
HOOK_CMD="$HOOK_DEST"   # allowlist + config key on the exact command string

echo "==> Installing hook script"
mkdir -p "$HERMES_HOME/agent-hooks"
cp attention.sh "$HOOK_DEST"
chmod +x "$HOOK_DEST"

echo "==> Registering hook events (pre_approval_request, post_approval_response)"
hermes config set hooks.pre_approval_request "[{\"command\":\"$HOOK_CMD\"}]" --force
hermes config set hooks.post_approval_response "[{\"command\":\"$HOOK_CMD\"}]" --force

echo "==> Pre-seeding shell-hooks allowlist (so the notifier never prompts)"
ALLOWLIST="$HERMES_HOME/shell-hooks-allowlist.json"
if [ -f "$ALLOWLIST" ]; then
  # Merge: keep existing approvals, add ours if missing
  tmp=$(mktemp)
  jq --arg cmd "$HOOK_CMD" \
    '.approvals += (select(.approvals | map(select(.event == "pre_approval_request" and .command == $cmd)) | length == 0) | [{"event":"pre_approval_request","command":$cmd}])
    | .approvals += (select(.approvals | map(select(.event == "post_approval_response" and .command == $cmd)) | length == 0) | [{"event":"post_approval_response","command":$cmd}])' \
    "$ALLOWLIST" > "$tmp" && cat "$tmp" > "$ALLOWLIST" && rm -f "$tmp"
else
  cat > "$ALLOWLIST" <<EOF
{
  "approvals": [
    { "event": "pre_approval_request", "command": "$HOOK_CMD" },
    { "event": "post_approval_response", "command": "$HOOK_CMD" }
  ]
}
EOF
fi

echo "==> Placing widget on the bar"
omarchy bar put bakugo.hermes-attention --section right --after omarchy.tray || \
  echo "    (widget may already be placed; skipping)"

echo
echo "Done. Restart your Hermes session, then verify:"
echo "  hermes hooks doctor"
echo "  hermes hooks test pre_approval_request --payload-file test-payload.json"
