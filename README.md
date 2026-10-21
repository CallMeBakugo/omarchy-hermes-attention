# Hermes Attention — Omarchy bar widget

Never miss a permission prompt again. A bar widget + notification beacon for
[Hermes Agent](https://github.com/NousResearch/hermes-agent) that fires when
your agent is waiting for your approval on a command — even if you've tabbed
to another virtual desktop.

![Pending](docs/bar-pending.png)

- A **critical on-screen notification** pops the moment Hermes raises an
  approval prompt. Critical urgency means it stays until you answer it, and it
  passes through Omarchy's do-not-disturb (which explicitly trusts critical
  alerts from `notify-send`). The toast body is deliberately generic — the
  flagged command never enters process arguments or the notification
  daemon's history; it lives only in the owner-only state file and is shown
  on click by the panel.
- A **red pulsing chip** appears in the bar and keeps pulsing until the prompt
  is answered — for when you were away from the screen when the toast popped.
- Click the chip for the flagged command, the reason it was flagged, and how
  long it's been waiting. Right-click (or `S` in the panel) to silence.
- Stacked prompts update the same toast (`×2`, `×3`…) instead of spamming you.
- Auto-silences after 30 minutes with no new prompt, so a session that died
  mid-prompt can't cry wolf forever. Configurable via widget settings.
- Only fires for prompts a human actually sees — auxiliary-LLM auto-approvals
  (`surface=smart`) are filtered out.

## How it works

Three pieces, zero daemons:

1. `attention.sh` — a Hermes **shell hook** registered for the
   `pre_approval_request` and `post_approval_response` events. On a pending
   prompt it writes a JSON state file and pops the toast; on your answer it
   decrements/clears the state and closes the toast. The script is the single
   writer of the state file.
2. The **bar widget** (`bakugo.hermes-attention`) just watches that state file
   (Quickshell `FileView`, inotify) and renders the chip + panel. It runs no
   timers of its own against the network — only a stale-guard.
3. The **notification** rides Omarchy's own notification service (quickshell
   owns `org.freedesktop.Notifications`), so there is nothing extra to install.

## Install

```bash
omarchy plugin add https://github.com/CallMeBakugo/omarchy-hermes-attention
```

Then install the hook side and place the widget (the plugin adder can't do
either):

```bash
./install.sh
```

`install.sh` does three things:

- Copies `attention.sh` to `~/.hermes/agent-hooks/` (executable)
- Registers the hook for both events in `~/.hermes/config.yaml` via
  `hermes config set` (never hand-edited)
- Pre-seeds `~/.hermes/shell-hooks-allowlist.json` so the notifier never
  itself asks for permission to notify — and places the widget after your tray

After a Hermes restart, verify:

```bash
hermes hooks doctor        # both hooks healthy
hermes hooks test pre_approval_request --payload-file test-payload.json
```

(The repo ships `test-payload.json` for exactly that.)

## Remove

```bash
omarchy plugin remove bakugo.hermes-attention --yes
hermes config unset hooks.pre_approval_request
hermes config unset hooks.post_approval_response
rm -f ~/.hermes/agent-hooks/attention.sh
```

## Requirements

- [Omarchy](https://omarchy.org) 4.x (quickshell bar)
- [Hermes Agent](https://github.com/NousResearch/hermes-agent) with shell-hook
  support (`hermes hooks list` works)
- `jq`, `notify-send`, `busctl` (all stock on Omarchy)

## Widget settings

`omarchy bar set bakugo.hermes-attention <key> <value>`

| Key | Default | What it does |
|---|---|---|
| `staleMin` | `30` | Auto-silence a pending alert after N minutes without a new prompt |

IPC: `omarchy-shell bakugo.hermes-attention <open|close|toggle|silence|refresh>`.

## License

MIT
