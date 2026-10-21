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

# Everything this script creates (state file, temp files) holds approval
# commands and session identifiers: keep it owner-only.
umask 077

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hermes-attention"
STATE="$STATE_DIR/state.json"
mkdir -p -m 700 "$STATE_DIR"
chmod 700 "$STATE_DIR" 2>/dev/null || true
[ -f "$STATE" ] && chmod 600 "$STATE"

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
    # The toast body is STATIC on purpose: command and description text
    # never travel through any process's argv (visible via ps) and never
    # land in the notification daemon's history. The full text lives only
    # in the 0600 state file, shown on click by the bar widget's panel.
    id=$(notify-send -u critical -i dialog-warning "${replace[@]}" -p -- \
      "Canari needs your approval" \
      "An agent is waiting - open the attention panel for the command" \
      2>/dev/null || echo 0)

    # Sensitive strings (command, description, pattern/session keys) are
    # written to 0600 temp files and bound with --rawfile, so they appear
    # in no process arguments; only filename placeholders do.
    tf() { local t; t=$(mktemp "$STATE_DIR/.XXXXXX"); printf '%s' "$1" > "$t"; printf '%s' "$t"; }
    cmdf=$(tf "$command_txt")  descf=$(tf "$description")
    pkf=$(tf "$pattern_keys")  skf=$(tf "$session_key")  sff=$(tf "$surface")

    jq -n --argjson count "$count" \
      --argjson since "$since" --argjson notifId "${id:-0}" \
      --rawfile command "$cmdf" --rawfile description "$descf" \
      --rawfile patternKeys "$pkf" --rawfile sessionKey "$skf" \
      --rawfile surface "$sff" \
      '{pending:true,count:$count,command:$command,description:$description,
        patternKeys:$patternKeys,sessionKey:$sessionKey,surface:$surface,
        since:$since,notifId:$notifId}' > "$STATE"
    rm -f "$cmdf" "$descf" "$pkf" "$skf" "$sff"
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
