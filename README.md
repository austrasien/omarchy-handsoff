# Hands off

The mouse and keyboard are shared between you and any agent driving the
desktop: Hyprland has a single seat, so an agent's click moves *your*
pointer. This Omarchy shell plugin frames every screen in the theme's accent
while an agent has its hands on the desktop, so you know to keep yours off.

- The frame sits on the Overlay layer, above windows and bars, and takes no
  input: clicks and scrolls go through to what is under it.
- It follows the theme's accent and fades in and out (no fade with
  `omarchy toggle animations` off).
- Looking is not touching: screenshots and accessibility reads do not light it.

## What lights it

1. **[hypruse](https://github.com/)** acting tools. hypruse rewrites a beacon,
   `$XDG_RUNTIME_DIR/hypruse/state.json`, on every tool call; the frame shows
   for `hold` seconds after a `pointer`, `keyboard`, `click_ui`, `use_bind`,
   `hypr` or `launch` call. (In `HYPRUSE_READONLY` mode none of these exist,
   so the frame never shows.)
2. **Claude Code shell commands** that drive the desktop, through the hook in
   `hooks/claude-code.sh`: `hyprctl dispatch` / `--batch`, `ydotool`, `wtype`,
   `wlrctl`, `dotool`, `xdotool`. The frame stays on while such a command runs.
   Read-only `hyprctl` calls (`activeworkspace`, `clients`...) do not count.

## Install

```sh
git clone https://github.com/austrasien/omarchy-handsoff ~/.config/omarchy/plugins/austraz.handsoff
```

Add `{ "id": "austraz.handsoff" }` to the `plugins` list of
`~/.config/omarchy/shell.json`, then `omarchy restart shell`.

For the Claude Code hook (needs `jq` and `flock`), link it and register it in
`~/.claude/settings.json`:

```sh
ln -s ~/.config/omarchy/plugins/austraz.handsoff/hooks/claude-code.sh ~/.claude/hooks/handsoff.sh
```

```json
{
  "hooks": {
    "PreToolUse":  [{ "matcher": "Bash", "hooks": [{ "type": "command", "command": "~/.claude/hooks/handsoff.sh", "timeout": 5 }] }],
    "PostToolUse": [{ "matcher": "Bash", "hooks": [{ "type": "command", "command": "~/.claude/hooks/handsoff.sh", "timeout": 5 }] }],
    "Stop":        [{ "hooks": [{ "type": "command", "command": "~/.claude/hooks/handsoff.sh", "timeout": 5 }] }],
    "SessionEnd":  [{ "hooks": [{ "type": "command", "command": "~/.claude/hooks/handsoff.sh", "timeout": 5 }] }]
  }
}
```

Merge these into your existing `hooks` rather than replacing them.

## Settings

Optional, in `~/.config/omarchy/handsoff.json` (reloaded on save):

```json
{ "visible": true, "width": 12, "hold": 4 }
```

- `width`: frame thickness in pixels (2 to 80). Raise it to cover the bars.
- `hold`: seconds the frame stays after the last hypruse action (1 to 60).
- `visible`: `false` turns the plugin off.

## License

MIT
