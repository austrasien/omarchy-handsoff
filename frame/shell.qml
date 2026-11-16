import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Hands off: frames every screen in the theme's accent while an agent drives
// the desktop. A Quickshell instance of its own (qs -p <this dir>), so it
// keeps running while the Omarchy shell restarts.
//
// Sources, any of which lights the frame:
//   calls  Claude Code tool calls in progress (hooks/claude-code.sh), pushed
//          over IPC and mirrored in $XDG_RUNTIME_DIR/handsoff/state.json;
//   pulse  a desktop-driving command just ran (shims/ via bin/handsoff);
//   hypruse  the beacon $XDG_RUNTIME_DIR/hypruse/state.json, for clients
//          without the hook.
//
// Settings (optional), ~/.config/omarchy/handsoff.json:
//   { "visible": true, "width": 12, "hold": 4 }
ShellRoot {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"

  // ------------------------------------------------------------ settings

  property var rawConfig: ({})
  readonly property var cfg: ({
    visible: rawConfig.visible !== false,
    width: typeof rawConfig.width === "number" ? Math.max(2, Math.min(80, rawConfig.width)) : 12,
    hold: typeof rawConfig.hold === "number" ? Math.max(1, Math.min(60, rawConfig.hold)) : 4
  })

  FileView {
    path: root.home + "/.config/omarchy/handsoff.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.rawConfig = JSON.parse(text() || "{}") } catch (e) { root.rawConfig = ({}) }
    }
    onLoadFailed: root.rawConfig = ({})
  }

  // ------------------------------------------------------------ accent
  //
  // The Omarchy shell's Color singleton is not available here: read the
  // current theme's colors.toml (`accent = "#rrggbb"`). A theme switch
  // replaces the file behind the `current` link, so it is re-read now and
  // then as well as on change.

  property color accent: "#7aa2f7"
  FileView {
    id: colors
    path: root.home + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var m = /^\s*accent\s*=\s*["']?(#[0-9A-Fa-f]{6,8})/m.exec(text() || "")
      if (m) root.accent = m[1]
    }
  }
  Timer { interval: 5000; running: true; repeat: true; onTriggered: colors.reload() }

  // ------------------------------------------------------------ state

  property int calls: 0
  property real pulseTs: 0
  property real hypruseTs: 0
  property bool active: false

  function now() { return Date.now() / 1000 }
  function evaluate() {
    var t = now()
    var recent = Math.max(pulseTs, hypruseTs)
    active = cfg.visible && (calls > 0 || (recent > 0 && t - recent < cfg.hold))
  }

  IpcHandler {
    target: "handsoff"
    function calls(n: string): void {
      var v = parseInt(n) || 0
      // A call that just ended still shows the frame for a moment.
      if (v < root.calls) root.pulseTs = Math.max(root.pulseTs, root.now() - root.cfg.hold + 1.5)
      root.calls = v
      root.evaluate()
    }
    function pulse(): void { root.pulseTs = root.now(); root.evaluate() }
    function state(): string { return root.active ? "on" : "off" }
  }

  // Fallbacks: the call count as last written (after this instance
  // restarts) and the hypruse beacon (acting tools only: screenshots and
  // accessibility reads write it too).
  FileView {
    id: callsFile
    path: root.runtimeDir + "/handsoff/state.json"
    printErrors: false
    blockLoading: true
    onLoaded: {
      try {
        var s = JSON.parse(text() || "{}")
        root.calls = s.active || 0
        if (typeof s.pulse === "number") root.pulseTs = Math.max(root.pulseTs, s.pulse)
      } catch (e) {}
    }
    onLoadFailed: root.calls = 0
  }
  FileView {
    id: beacon
    path: root.runtimeDir + "/hypruse/state.json"
    printErrors: false
    blockLoading: true
    onLoaded: {
      try {
        var s = JSON.parse(text() || "{}")
        if (/^(pointer|keyboard|click_ui|use_bind|hypr|launch)/.test(s.last_action || "") && typeof s.last_ts === "number")
          root.hypruseTs = s.last_ts
      } catch (e) {}
    }
  }
  Component.onCompleted: { callsFile.reload(); evaluate() }
  Timer {
    interval: 250
    running: true
    repeat: true
    onTriggered: { beacon.reload(); root.evaluate() }
  }

  // ------------------------------------------------------------ surface
  //
  // Four thin strips per screen, always mapped: showing the frame is only an
  // opacity change, with no surface to create, and nothing full-screen for
  // the compositor to blend while it is off.

  // Hyprland stacks surfaces of one layer by map order, newest on top: the
  // day bar and day tape, also on Overlay along the side edges, cover the
  // strips whenever they map again (a desk change, a shell restart). When
  // any other layer surface maps, unmap and map the strips back on top.
  property bool mapped: true
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "openlayer" && event.data !== "handsoff") restack.restart()
    }
  }
  Timer {
    id: restack
    interval: 60
    onTriggered: { root.mapped = false; remap.restart() }
  }
  Timer { id: remap; interval: 30; onTriggered: root.mapped = true }

  component Edge: PanelWindow {
    required property var modelData
    property string side: "top"
    screen: modelData
    visible: root.cfg.visible && root.mapped
    color: "transparent"
    anchors {
      top: side !== "bottom"
      bottom: side !== "top"
      left: side !== "right"
      right: side !== "left"
    }
    implicitWidth: root.cfg.width
    implicitHeight: root.cfg.width

    WlrLayershell.namespace: "handsoff"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    // Empty input region: clicks and scrolls go through to what is under.
    mask: Region {}

    Rectangle {
      anchors.fill: parent
      color: root.accent
      // On at once, off with a short fade.
      opacity: root.active ? 1 : 0
      Behavior on opacity {
        enabled: !root.active
        NumberAnimation { duration: 180 }
      }
    }
  }

  Variants { model: Quickshell.screens; Edge { side: "top" } }
  Variants { model: Quickshell.screens; Edge { side: "bottom" } }
  Variants { model: Quickshell.screens; Edge { side: "left" } }
  Variants { model: Quickshell.screens; Edge { side: "right" } }
}
