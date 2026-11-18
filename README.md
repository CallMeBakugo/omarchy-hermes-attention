# Hermes Attention

See when Hermes Agent needs you to approve a command, even from another workspace. A pulsing Omarchy badge and a persistent desktop notification draw your attention to the pending request. Click the badge to read the command, the reason it was flagged, and when the request arrived.

![Hermes Attention showing clear and pending states](preview.png)

## Install

Requires Omarchy 4.x, [Hermes Agent](https://github.com/NousResearch/hermes-agent) with shell hooks, and the `jq`, `notify-send`, and `busctl` commands.

```sh
omarchy plugin add https://github.com/CallMeBakugo/omarchy-hermes-attention.git --enable
git clone https://github.com/CallMeBakugo/omarchy-hermes-attention.git
cd omarchy-hermes-attention
bash install.sh
```

Add the installed hook's absolute path to both event lists under `hooks` in your Hermes `config.yaml`. Merge these entries with any existing hooks. Your Hermes home is `~/.hermes` unless you set `HERMES_HOME`.

```yaml
hooks:
  pre_approval_request:
    - command: "/absolute/path/to/.hermes/agent-hooks/attention.sh"
  post_approval_response:
    - command: "/absolute/path/to/.hermes/agent-hooks/attention.sh"
```

Restart Hermes, approve its first-use prompt for the hook when requested, then run `hermes hooks doctor` to check the setup. The included `test-payload.json` can be used with `hermes hooks test pre_approval_request --payload-file test-payload.json`.

## Use

- Left-click the badge to inspect the pending prompt.
- Right-click or press **S** in the panel to silence the badge and its notification. Approval decisions stay in Hermes.
- Pending prompts share one notification. The badge returns to its clear state when the last prompt is answered.
- Alerts go quiet after 30 minutes without a new prompt. Change the timeout with `omarchy bar set bakugo.hermes-attention staleMin 15`.

The desktop notification contains a generic message. Command details are kept in an owner-only local state file and shown in the flyout. Prompts handled by Hermes' automatic approval surface are filtered out.

## Remove

```sh
omarchy plugin remove bakugo.hermes-attention --yes
```

Remove this script's two entries from your Hermes hook configuration, revoke its approval if applicable, and delete the installed `agent-hooks/attention.sh` file. Keep any unrelated hooks.

[MIT license](LICENSE).
