# Hands off

The mouse and keyboard are shared between you and any agent driving the
desktop: Hyprland has a single seat, so an agent's click moves *your*
pointer. This Omarchy shell plugin frames every screen in the theme's accent
while an agent has its hands on the desktop, so you know to keep yours off.

- The frame is four thin strips on the Overlay layer, above windows and bars,
  always mapped so that showing them is instant. They take no input: clicks
  and scrolls go through to what is under them.
- It follows the theme's accent, shows at once and fades out (no fade with
  `omarchy toggle animations` off).
- Looking is not touching: screenshots and accessibility reads do not light it.

## What lights it

1. **[hypruse](https://github.com/)** acting tools. hypruse rewrites a beacon,
   `$XDG_RUNTIME_DIR/hypruse/state.json`, on every tool call; the frame shows
   for `hold` seconds after a `pointer`, `keyboard`, `click_ui`, `use_bind`,
   `hypr` or `launch` call. (In `HYPRUSE_READONLY` mode none of these exist,
   so the frame never shows.)
2. **Claude Code**, through the hook in `hooks/claude-code.sh`, for shell
   commands that drive the desktop (`hyprctl dispatch` / `--batch`, `ydotool`,
   `wtype`, `wlrctl`, `dotool`, `xdotool`) and for hypruse's acting tools.
   The frame stays on while the call runs. Read-only `hyprctl` calls
   (`activeworkspace`, `clients`...) do not count.

   The hook tells the plugin over IPC and waits 150 ms before letting the
   call go, so the frame is up *before* the desktop moves; the hypruse beacon
   alone only shows it after the first action.

While the shell restarts (`omarchy restart shell`) there is no frame.

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
    "PreToolUse":  [{ "matcher": "Bash|mcp__hypruse__.*", "hooks": [{ "type": "command", "command": "~/.claude/hooks/handsoff.sh", "timeout": 5 }] }],
    "PostToolUse": [{ "matcher": "Bash|mcp__hypruse__.*", "hooks": [{ "type": "command", "command": "~/.claude/hooks/handsoff.sh", "timeout": 5 }] }],
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
