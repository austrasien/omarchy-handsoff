#!/usr/bin/env bash
# Claude Code hook for Hands off. One command for every event:
#
#   SessionStart  put shims/ first in the PATH of this session's Bash tool
#                 (through $CLAUDE_ENV_FILE), so any hyprctl dispatch,
#                 ydotool, wtype... it runs, even from a script, lights the
#                 frame
#   PreToolUse    a hypruse acting tool, or a Bash command that drives the
#                 desktop by name: frame on for the whole call (a command
#                 with sleeps between dispatches stays framed)
#   PostToolUse   that call is over
#   Stop / SessionEnd  clear what is left of the session (a failed call
#                 gets no PostToolUse)
#
# Needs jq. Must stay silent on stdout.

export PATH="/usr/bin:/usr/local/bin:${PATH:-}"

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
HANDSOFF="$ROOT/bin/handsoff"

input=$(cat)
IFS=$'\t' read -r event session tool_id tool < <(
  jq -r '[.hook_event_name // "", .session_id // "", .tool_use_id // "", .tool_name // ""] | @tsv' <<<"$input" 2>/dev/null
)
session=$(tr -cd 'A-Za-z0-9_-' <<<"$session")
tool_id=$(tr -cd 'A-Za-z0-9_-' <<<"$tool_id")
[[ -n $session ]] || exit 0

drives_desktop() {
  grep -qE '(^|[^[:alnum:]_-])(hyprctl[^|;&]*[[:space:]](dispatch|--batch|-b)([[:space:]]|$)|ydotool|wtype|wlrctl|dotool|xdotool)' <<<"$1"
}

case "$event" in
  SessionStart)
    [[ -n ${CLAUDE_ENV_FILE:-} ]] &&
      printf 'export PATH="%s:$PATH"\n' "$ROOT/shims" >>"$CLAUDE_ENV_FILE"
    ;;
  PreToolUse)
    [[ -n $tool_id ]] || exit 0
    case "$tool" in
      mcp__hypruse__pointer|mcp__hypruse__keyboard|mcp__hypruse__click_ui|mcp__hypruse__use_bind|mcp__hypruse__hypr|mcp__hypruse__launch|mcp__hypruse__sequence) ;;
      Bash)
        drives_desktop "$(jq -r '.tool_input.command // ""' <<<"$input" 2>/dev/null)" || exit 0
        ;;
      *) exit 0 ;;
    esac
    "$HANDSOFF" begin "$session-$tool_id" >/dev/null 2>&1
    ;;
  PostToolUse)
    [[ -n $tool_id ]] && "$HANDSOFF" end "$session-$tool_id" >/dev/null 2>&1
    ;;
  Stop|SessionEnd)
    "$HANDSOFF" clear "$session-" >/dev/null 2>&1
    ;;
esac
exit 0
