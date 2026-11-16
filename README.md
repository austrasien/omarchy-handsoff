# Hands off

The mouse and keyboard are shared between you and any agent driving the
desktop: Hyprland has a single seat, so an agent's click moves *your*
pointer and its `hyprctl dispatch` switches *your* workspace. Hands off frames
every screen in the theme's accent while an agent has its hands on the
desktop, so you know to keep yours off.

- The frame shows **before** the desktop moves: the agent's call waits for it
  (150 ms, only when the frame was off).
- It is four thin strips on the Overlay layer, always mapped so showing them
  is instant, and kept above the other Overlay surfaces along the edges. They
  take no input: clicks and scrolls go through.
- It runs as its own Quickshell instance, not as a shell plugin, so it stays
  up while the Omarchy shell restarts.
- It follows the theme's accent (`accent` in the current theme's
  `colors.toml`).
- Looking is not touching: screenshots, `hyprctl clients` and other reads do
  not light it.

## What lights it

| Source | How |
|---|---|
| Claude Code Bash command naming `hyprctl dispatch`/`--batch`, `ydotool`, `wtype`, `wlrctl`, `dotool`, `xdotool` | `PreToolUse` hook: on for the whole call, sleeps included |
| Anything an agent shell runs that calls those tools, scripts included | `shims/`, first in the agent's `PATH` only: on for `hold` seconds |
| [hypruse](https://github.com/IlyasKhallouki/hypruse) acting tools (`pointer`, `keyboard`, `click_ui`, `use_bind`, `hypr`, `launch`, `sequence`) | `PreToolUse` hook, and the hypruse beacon for clients without it |

Your own shells and keybinds never see the shims: Claude Code puts them in
front of the `PATH` of its Bash tool only, through `$CLAUDE_ENV_FILE`.

## Layout

```
frame/shell.qml           the frame (qs -p frame)
bin/handsoff              pulse | begin <id> | end <id> | clear <prefix> | state
shims/                    hyprctl, ydotool, wtype, wlrctl, dotool, xdotool
hooks/claude-code.sh      Claude Code hook (SessionStart, Pre/PostToolUse, Stop, SessionEnd)
systemd/handsoff-frame.service
```

## Install

Needs `quickshell`, `jq` and `flock`.

```sh
git clone https://github.com/austrasien/omarchy-handsoff ~/src/omarchy-handsoff
ln -s ~/src/omarchy-handsoff/systemd/handsoff-frame.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now handsoff-frame.service
ln -s ~/src/omarchy-handsoff/hooks/claude-code.sh ~/.claude/hooks/handsoff.sh
```

The service file expects the clone in `~/src/omarchy-handsoff`; edit
`ExecStart` otherwise.

Register the hook in `~/.claude/settings.json`, merged into your existing
`hooks`:

```json
{
  "hooks": {
    "SessionStart": [{ "hooks": [{ "type": "command", "command": "~/.claude/hooks/handsoff.sh", "timeout": 5 }] }],
    "PreToolUse":   [{ "matcher": "Bash|mcp__hypruse__.*", "hooks": [{ "type": "command", "command": "~/.claude/hooks/handsoff.sh", "timeout": 5 }] }],
    "PostToolUse":  [{ "matcher": "Bash|mcp__hypruse__.*", "hooks": [{ "type": "command", "command": "~/.claude/hooks/handsoff.sh", "timeout": 5 }] }],
    "Stop":         [{ "hooks": [{ "type": "command", "command": "~/.claude/hooks/handsoff.sh", "timeout": 5 }] }],
    "SessionEnd":   [{ "hooks": [{ "type": "command", "command": "~/.claude/hooks/handsoff.sh", "timeout": 5 }] }]
  }
}
```

Sessions started before that get the hook but not the shims; restart them.

So that the strips do not blink when they move back on top, add to
`~/.config/hypr/hyprland.lua`:

```lua
hl.layer_rule({ match = { namespace = "^handsoff$" }, no_anim = true, animation = "none" })
```

Other agents: put `~/src/omarchy-handsoff/shims` first in their shell's
`PATH`, or call `bin/handsoff begin <id>` / `end <id>` around their actions.

## Settings

Optional, in `~/.config/omarchy/handsoff.json` (reloaded on save):

```json
{ "visible": true, "width": 12, "hold": 4 }
```

- `width`: strip thickness in pixels (2 to 80). Raise it to cover the bars.
- `hold`: seconds the frame stays after a shim or hypruse action (1 to 60).
- `visible`: `false` turns the frame off.

## Limits

- An agent talking to Hyprland's socket directly, without `hyprctl`, is not
  seen.
- The 150 ms wait is a guess at a frame or two of compositor latency.

## License

MIT
