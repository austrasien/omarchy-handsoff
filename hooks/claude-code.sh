#!/usr/bin/env bash
# Claude Code hook: tells the austraz.handsoff shell plugin when a tool call
# drives the desktop, so the accent frame shows while it runs:
#   - Bash commands with hyprctl dispatch/--batch, ydotool, wtype, wlrctl,
#     dotool or xdotool;
#   - hypruse acting tools (pointer, keyboard, click_ui, use_bind, hypr,
#     launch, sequence).
#
#   PreToolUse   matching call -> mark <session>-<tool_use_id>, tell the
#                plugin, and give the frame a moment to show before the call
#   PostToolUse  -> unmark that call
#   Stop / SessionEnd   -> unmark everything of the session (a failed call
#                          gets no PostToolUse)
#
# The count goes to the plugin over IPC (omarchy-shell austraz.handsoff calls
# n) and to $XDG_RUNTIME_DIR/handsoff/state.json {"active": n}, which the
# plugin reads back after a shell restart.
# Marks older than 15 min are dropped (a Bash call cannot last that long).
# Must stay silent on stdout.

export PATH="/usr/share/omarchy/bin:/usr/bin:/usr/local/bin:${PATH:-}"

DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/handsoff"
MARKS="$DIR/marks"
mkdir -p "$MARKS" 2>/dev/null || exit 0

input=$(cat)
event=$(jq -r '.hook_event_name // ""' <<<"$input" 2>/dev/null)
session=$(jq -r '.session_id // "x"' <<<"$input" 2>/dev/null | tr -cd 'A-Za-z0-9_-')
tool_id=$(jq -r '.tool_use_id // ""' <<<"$input" 2>/dev/null | tr -cd 'A-Za-z0-9_-')

drives_desktop() {
  grep -qE '(^|[^[:alnum:]_-])(hyprctl[^|;&]*[[:space:]](dispatch|--batch|-b)([[:space:]]|$)|ydotool|wtype|wlrctl|dotool|xdotool)' <<<"$1"
}

case "$event" in
  PreToolUse)
    tool=$(jq -r '.tool_name // ""' <<<"$input" 2>/dev/null)
    case "$tool" in
      mcp__hypruse__pointer|mcp__hypruse__keyboard|mcp__hypruse__click_ui|mcp__hypruse__use_bind|mcp__hypruse__hypr|mcp__hypruse__launch|mcp__hypruse__sequence) ;;
      Bash)
        cmd=$(jq -r '.tool_input.command // ""' <<<"$input" 2>/dev/null)
        drives_desktop "$cmd" || exit 0
        ;;
      *) exit 0 ;;
    esac
    [[ -n $tool_id ]] && : >"$MARKS/$session-$tool_id"
    ;;
  PostToolUse)
    [[ -n $tool_id && -e "$MARKS/$session-$tool_id" ]] || exit 0
    rm -f "$MARKS/$session-$tool_id"
    ;;
  Stop|SessionEnd)
    rm -f "$MARKS/$session-"* 2>/dev/null
    ;;
  *) exit 0 ;;
esac

(
  flock -w 2 9 || exit 0
  find "$MARKS" -type f -mmin +15 -delete 2>/dev/null
  n=$(find "$MARKS" -type f | wc -l)
  printf '{"active": %d}\n' "$n" >"$DIR/state.json.tmp" && mv "$DIR/state.json.tmp" "$DIR/state.json"
  timeout 1 omarchy-shell -q austraz.handsoff calls "$n" >/dev/null 2>&1
) 9>"$DIR/lock"

# Let the compositor draw the frame before the call takes the desktop.
[[ $event == PreToolUse ]] && sleep 0.15
exit 0
