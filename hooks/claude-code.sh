#!/usr/bin/env bash
# Claude Code hook: tells the austraz.handsoff shell plugin when a Bash call
# drives the desktop (hyprctl dispatch, ydotool, wtype, wlrctl, dotool,
# xdotool), so the accent frame shows while it runs.
#
#   PreToolUse  (Bash)  matching command -> mark <session>-<tool_use_id>
#   PostToolUse (Bash)  -> unmark that call
#   Stop / SessionEnd   -> unmark everything of the session (a failed call
#                          gets no PostToolUse)
#
# State for the plugin: $XDG_RUNTIME_DIR/handsoff/state.json {"active": n}.
# Marks older than 15 min are dropped (a Bash call cannot last that long).
# Must stay silent on stdout.

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
    cmd=$(jq -r '.tool_input.command // ""' <<<"$input" 2>/dev/null)
    drives_desktop "$cmd" || exit 0
    [[ -n $tool_id ]] && : >"$MARKS/$session-$tool_id"
    ;;
  PostToolUse)
    [[ -n $tool_id ]] && rm -f "$MARKS/$session-$tool_id"
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
) 9>"$DIR/lock"
exit 0
