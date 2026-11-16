import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// While an agent drives the shared seat (hypruse acting tools: pointer,
// keyboard, click_ui, use_bind), every screen gets a frame in the theme
// accent on the Overlay layer, above bars and windows, so the human at the
// desk knows to keep their hands off. The frame never takes input.
//
// Source: hypruse's activity beacon, $XDG_RUNTIME_DIR/hypruse/state.json,
// rewritten on every tool call ({pid, started, last_action, last_ts}) and
// removed when hypruse exits. Observation calls (screenshot, ui, ...) touch
// it too, so only acting ones count.
//
// Settings (optional) in ~/.config/omarchy/handsoff.json:
//   { "visible": true, "width": 12, "hold": 4 }
// `hold` is how many seconds the frame stays after the last action.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  readonly property string beaconPath: runtimeDir + "/hypruse/state.json"
  readonly property string configPath: home + "/.config/omarchy/handsoff.json"

  property var rawConfig: ({})
  readonly property var cfg: ({
    visible: rawConfig.visible !== false,
    width: typeof rawConfig.width === "number" ? Math.max(2, Math.min(80, rawConfig.width)) : 12,
    hold: typeof rawConfig.hold === "number" ? Math.max(1, Math.min(60, rawConfig.hold)) : 4
  })

  FileView {
    path: root.configPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.rawConfig = JSON.parse(text() || "{}") } catch (e) { root.rawConfig = ({}) }
    }
    onLoadFailed: root.rawConfig = ({})
  }

  // ------------------------------------------------------------ beacon

  property real lastActTs: 0
  property bool active: false

  function isActing(action) {
    return /^(pointer|keyboard|click_ui|use_bind|hypr|launch)/.test(action || "")
  }

  // The beacon is replaced by rename on every write (and may not exist):
  // a light poll is more reliable than a file watch here.
  FileView {
    id: beacon
    path: root.beaconPath
    printErrors: false
    blockLoading: true
    onLoaded: {
      try {
        var s = JSON.parse(text() || "{}")
        if (root.isActing(s.last_action) && typeof s.last_ts === "number")
          root.lastActTs = s.last_ts
      } catch (e) {}
      root.evaluate()
    }
    onLoadFailed: { root.lastActTs = 0; root.evaluate() }
  }

  // Second source: Claude Code's handsoff.sh hook counts Bash calls that
  // drive the desktop (hyprctl dispatch, ydotool, wtype...) while they run.
  property int shellCalls: 0
  property real shellLastTs: 0
  FileView {
    id: hookState
    path: root.runtimeDir + "/handsoff/state.json"
    printErrors: false
    blockLoading: true
    onLoaded: {
      var n = 0
      try { n = JSON.parse(text() || "{}").active || 0 } catch (e) {}
      root.shellCalls = n
      if (n > 0) root.shellLastTs = Date.now() / 1000
      root.evaluate()
    }
    onLoadFailed: { root.shellCalls = 0; root.evaluate() }
  }

  function evaluate() {
    var now = Date.now() / 1000
    var viaHypruse = lastActTs > 0 && (now - lastActTs) < cfg.hold
    // A short call still shows the frame for a moment.
    var viaShell = shellCalls > 0 || (shellLastTs > 0 && (now - shellLastTs) < 1.5)
    active = cfg.visible && (viaHypruse || viaShell)
  }

  Timer {
    interval: 250
    running: true
    repeat: true
    // evaluate() too: an unchanged or missing file emits nothing, and the
    // hold times still run out.
    onTriggered: { beacon.reload(); hookState.reload(); root.evaluate() }
  }

  // Pushed by hooks/claude-code.sh, so the frame is up before the command
  // runs (the file above is the fallback after a shell restart).
  IpcHandler {
    target: "austraz.handsoff"
    function calls(n: string): void {
      var v = parseInt(n) || 0
      root.shellCalls = v
      if (v > 0) root.shellLastTs = Date.now() / 1000
      root.evaluate()
    }
    function state(): string { return root.active ? "on" : "off" }
  }

  // ------------------------------------------------------------ surface
  //
  // Four thin strips per screen, always mapped: showing the frame is only an
  // opacity change, with no surface to create (which can lag), and nothing
  // full-screen for the compositor to blend while it is off.

  component Edge: PanelWindow {
    required property var modelData
    property string side: "top"
    screen: modelData
    visible: root.cfg.visible
    color: "transparent"
    anchors {
      top: side !== "bottom"
      bottom: side !== "top"
      left: side !== "right"
      right: side !== "left"
    }
    implicitWidth: root.cfg.width
    implicitHeight: root.cfg.width

    WlrLayershell.namespace: "austraz-handsoff"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    // Empty input region: clicks and scrolls go through to what is under.
    mask: Region {}

    Rectangle {
      anchors.fill: parent
      color: Color.accent
      // On at once, off with a short fade.
      opacity: root.active ? 1 : 0
      Behavior on opacity {
        enabled: !root.active && !Style.reduceMotion
        NumberAnimation { duration: 180 }
      }
    }
  }

  Variants { model: Quickshell.screens; Edge { side: "top" } }
  Variants { model: Quickshell.screens; Edge { side: "bottom" } }
  Variants { model: Quickshell.screens; Edge { side: "left" } }
  Variants { model: Quickshell.screens; Edge { side: "right" } }
}
