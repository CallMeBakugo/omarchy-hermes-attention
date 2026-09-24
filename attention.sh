#!/usr/bin/env bash
# Canari's attention beacon - bridges Hermes approval prompts to the
# desktop. Registered in ~/.hermes/config.yaml under hooks: for
# pre_approval_request and post_approval_response.
#
#   pre  (surface != smart): write a pending state file and pop a critical
#         notification (stays until answered; bypasses Omarchy DND because
#         it is urgency=critical sent from app_name notify-send - do NOT
#         add a -a flag, that would break the DND bypass).
#   post (surface != smart): decrement/clear the state and close the toast.
#   --clear                 : force-clear (bar widget right-click / stale).
#
# The state file is the single source of truth for the
# bakugo.hermes-attention bar widget; only this script writes it.
# In-place writes (>) keep the inode stable so FileView watchers survive.

set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hermes-attention"
STATE="$STATE_DIR/state.json"
mkdir -p "$STATE_DIR"

clip() { local s=$1 n=$2; [ ${#s} -gt "$n" ] && printf '%s...' "${s:0:$n}" || printf '%s' "$s"; }

read_state_field() { # $1 = jq path
  if [ -f "$STATE" ]; then jq -r "$1 // 0" "$STATE" 2>/dev/null || printf 0; else printf 0; fi
}

close_notification() {
  local id
  id=$(read_state_field '.notifId')
  if [ "$id" -gt 0 ] 2>/dev/null; then
    busctl --user call org.freedesktop.Notifications /org/freedesktop/Notifications \
      org.freedesktop.Notifications CloseNotification u "$id" >/dev/null 2>&1 || true
  fi
}

clear_state() {
  close_notification
  printf '{"pending":false}' > "$STATE"
}

if [ "${1:-}" = "--clear" ]; then clear_state; exit 0; fi

payload=$(cat) || exit 0
event=$(jq -r '.hook_event_name // empty' <<<"$payload" 2>/dev/null || true)

field() { # $1 = key; event kwargs live in .extra, fall back to top level
  jq -r --arg k "$1" \
    'try ((.extra[$k] // .[$k] // "")) catch "" | if type=="array" then join(",") else tostring end' \
    <<<"$payload" 2>/dev/null || printf ''
}

surface=$(field surface)

case "$event" in
  pre_approval_request)
    [ "$surface" = "smart" ] && exit 0   # auxiliary-LLM auto-decision: no human is waiting
    command_txt=$(clip "$(field command)" 500)
    description=$(clip "$(field description)" 240)
    pattern_keys=$(field pattern_keys)
    session_key=$(field session_key)

    prev_pending=false; prev_count=0; since=$(date +%s)
    if [ -f "$STATE" ]; then
      prev_pending=$(jq -r '.pending // false' "$STATE" 2>/dev/null || echo false)
      prev_count=$(jq -r '.count // 0' "$STATE" 2>/dev/null || echo 0)
    fi
    if [ "$prev_pending" = "true" ]; then
      count=$((prev_count + 1))
    else
      count=1
    fi
    # `since` resets on every prompt: fresh activity means the session is
    # alive, so the widget's stale timer must restart with it.

    prev_id=$(read_state_field '.notifId')
    replace=()
    if [ "$prev_pending" = "true" ] && [ "$prev_id" -gt 0 ] 2>/dev/null; then
      replace=(-r "$prev_id")
    fi

    # No -a flag on purpose: app_name must stay "notify-send" for the
    # Omarchy notifications service to let critical alerts through DND.
    id=$(notify-send -u critical -i dialog-warning "${replace[@]}" -p -- \
      "Canari needs your approval" \
      "$(printf '%s\n%s' "$description" "$command_txt")" 2>/dev/null || echo 0)

    jq -n --argjson count "$count" --arg command "$command_txt" \
      --arg description "$description" --arg patternKeys "$pattern_keys" \
      --arg sessionKey "$session_key" --arg surface "$surface" \
      --argjson since "$since" --argjson notifId "${id:-0}" \
      '{pending:true,count:$count,command:$command,description:$description,
        patternKeys:$patternKeys,sessionKey:$sessionKey,surface:$surface,
        since:$since,notifId:$notifId}' > "$STATE"
    ;;

  post_approval_response)
    [ "$surface" = "smart" ] && exit 0
    [ -f "$STATE" ] || exit 0
    pending=$(jq -r '.pending // false' "$STATE" 2>/dev/null || echo false)
    [ "$pending" = "true" ] || exit 0
    count=$(jq -r '.count // 1' "$STATE" 2>/dev/null || echo 1)
    if [ "$count" -gt 1 ]; then
      jq --argjson c "$((count - 1))" '.count=$c' "$STATE" > "$STATE.tmp" \
        && cat "$STATE.tmp" > "$STATE" && rm -f "$STATE.tmp"
    else
      clear_state
    fi
    ;;

  *) exit 0 ;;
esac
