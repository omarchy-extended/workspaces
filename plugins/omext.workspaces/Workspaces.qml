import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  // omext workspaces (omarchy-extended), from Omarchy's own workspaces widget:
  // the workspaces are all still there, and used when one is wanted, but they
  // keep out of the way. The bar shows the first, and another only while
  // something is on it (or it's the one in front); a number with windows on it
  // carries their count, small and raised, and hovering it drops down a list
  // of them (a click there brings one up). Nothing switches workspace by
  // accident: no scroll over the bar, no click that changes a layout.
  //
  // Its settings (~/.config/omext/workspaces.json; omext core's Settings reads,
  // watches and writes it):
  //   always      the workspaces every screen's bar always shows: [1] (the
  //               default), [1, 2, 3, 4, 5], ...; 1 to 10
  //   scroll      true: a scroll over the numbers goes to the next or the one before
  //   superScroll true: Super + scroll wheel does too (hypr/workspaces.lua; false
  //               takes those keys off)
  //   counts      false: no window counts beside the numbers
  //   list        false: no list of a workspace's windows when it's pointed at
  readonly property string coreDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy/plugins/omext.core"
  Loader { id: coreOwn; Component.onCompleted: setSource("file://" + root.coreDir + "/Settings.qml", { name: "workspaces" }) }
  readonly property var config: coreOwn.item ? coreOwn.item.values : ({})
  readonly property var always: {
    var a = Array.isArray(config.always) ? config.always.map(n => parseInt(n)).filter(n => n >= 1 && n <= root.slots) : []
    return a.length ? a : [1]
  }
  readonly property bool showCounts: config.counts !== false
  readonly property bool showList: config.list !== false
  // Which app a window is: omext core's rule, as on the taskbar and in Start.
  Loader {
    id: coreApps
    source: "file://" + root.coreDir + "/Apps.qml"
  }
  // Windows in a dock (pinned, or tagged omext-docked) belong to no workspace
  // and are left out.
  function windowsOn(workspace) {
    if (!workspace) return []
    var out = [], values = workspace.toplevels.values
    for (var i = 0; i < values.length; i++) {
      var t = values[i], ipc = t.lastIpcObject || {}
      var tags = ipc.tags || []
      if (ipc.pinned || tags.indexOf("omext-docked") !== -1) continue
      var cls = (t.wayland && t.wayland.appId) || ipc["class"] || ipc.initialClass || ""
      var e = !cls ? null : coreApps.item ? coreApps.item.ofClass(cls) : DesktopEntries.heuristicLookup(cls)
      out.push({
        address: ipc.address || ("0x" + t.address),
        app: e && e.name ? e.name : cls,
        icon: e && e.icon ? Quickshell.iconPath(e.icon, true) : Quickshell.iconPath("application-x-executable", true),
        title: t.title || ipc.title || cls
      })
    }
    return out
  }

  // The list drops down from the number hovered, and stays while the pointer
  // is on either.
  property Item listFor: null
  property var listWindows: []
  property bool numberHovered: false
  function hoverNumber(button, on) {
    if (on && !root.showList) return
    if (on && button.windows.length) {
      root.listFor = button
      root.listWindows = button.windows
      root.numberHovered = true
      listClose.stop()
    } else if (root.listFor === button) {
      root.numberHovered = false
      listClose.restart()
    }
  }
  Timer {
    id: listClose
    interval: 250
    onTriggered: if (!root.numberHovered && !windowList.containsMouse) root.listFor = null
  }

  PopupCard {
    id: windowList
    bar: root.bar
    anchorItem: root.listFor || root
    triggerMode: "hover"
    open: root.listFor !== null
    contentWidth: Style.space(360)
    contentHeight: windowList.fittedContentHeight(listColumn.implicitHeight)
    onContainsMouseChanged: if (!containsMouse) listClose.restart()

    Column {
      id: listColumn
      width: parent.width
      spacing: Style.space(2)
      Repeater {
        model: root.listWindows
        Rectangle {
          id: row
          required property var modelData
          width: listColumn.width
          height: Style.space(30)
          radius: Style.space(4)
          color: rowHit.containsMouse ? Commons.Util.alpha(Commons.Color.foreground, 0.08) : "transparent"
          IconImage {
            id: rowIcon
            x: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            implicitSize: Style.space(18)
            source: row.modelData.icon
          }
          Text {
            anchors { left: rowIcon.right; leftMargin: Style.space(8); right: parent.right; rightMargin: Style.space(6); verticalCenter: parent.verticalCenter }
            elide: Text.ElideRight
            text: row.modelData.title && row.modelData.title !== row.modelData.app && row.modelData.title.indexOf(row.modelData.app) === -1
              ? row.modelData.app + " \u2014 " + row.modelData.title : (row.modelData.title || row.modelData.app)
            color: Commons.Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
          MouseArea {
            id: rowHit
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.dispatch("hl.dsp.focus({ window = \"address:" + row.modelData.address + "\" })")
              root.listFor = null
            }
          }
        }
      }
    }
  }

  // Every monitor has workspaces 1-10 of its own, which Hyprland numbers in a
  // block of ten per monitor: 1-10, 11-20, and so on (see
  // default/hypr/monitor-workspaces.lua). Each bar shows its own monitor's block,
  // numbered 1-10, and the one that monitor shows, whichever monitor has focus.
  readonly property int slots: 10

  readonly property var monitor: {
    var window = root.QsWindow.window
    var screen = window ? window.screen : null
    return screen ? Hyprland.monitorFor(screen) : Hyprland.focusedMonitor
  }
  readonly property string monitorName: root.monitor ? root.monitor.name : ""

  // Connector -> block, from the file Hyprland keeps them in.
  property var blocks: ({})

  function readBlocks(text) {
    var next = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var fields = lines[i].split("\t")
      if (fields.length >= 3 && fields[1] !== "") next[fields[1]] = parseInt(fields[0], 10)
    }
    root.blocks = next
  }

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/monitor-workspaces"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.readBlocks(text())
    onLoadFailed: root.readBlocks("")
  }

  function blockOf(id) {
    return Math.floor((id - 1) / root.slots)
  }

  function slotOf(id) {
    return (id - 1) % root.slots + 1
  }

  function activeWorkspaceId() {
    return root.monitor && root.monitor.activeWorkspace ? root.monitor.activeWorkspace.id : -1
  }

  // Until Hyprland has written the file, the workspace a monitor shows is in
  // its own block.
  readonly property int block: {
    var block = root.blocks[root.monitorName]
    if (block !== undefined) return block
    var active = root.activeWorkspaceId()
    return active > 0 ? root.blockOf(active) : 0
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  // The ones set to show always (the first, by default), and the rest only
  // while something is on them, or they're the one in front: no row of empty
  // workspaces to land on by mistake. After them come workspaces that are only
  // visiting: those of a monitor that is unplugged, which had no room to join
  // this one's.
  function workspaceIds() {
    var base = root.block * root.slots
    var ids = root.always.map(function(slot) { return base + slot })
    var active = root.activeWorkspaceId()
    var guests = []
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id <= 0) continue
      if (root.blockOf(id) === root.block) {
        if (ids.indexOf(id) === -1 && (id === active || root.windowsOn(values[i]).length > 0)) ids.push(id)
      } else if (values[i].monitor && values[i].monitor.name === root.monitorName) {
        guests.push(id)
      }
    }

    ids.sort(function(left, right) { return left - right })
    guests.sort(function(left, right) { return left - right })
    return ids.concat(guests)
  }

  function dispatch(expression) {
    if (root.bar) root.bar.run("hyprctl dispatch " + Util.shellQuote(expression))
  }

  function focusWorkspace(id) {
    if (root.blockOf(id) === root.block) {
      root.dispatch("o.workspaces.focus(" + root.slotOf(id) + ", \"" + root.monitorName + "\")")
    } else {
      root.dispatch("hl.dsp.focus({ workspace = \"" + id + "\" })")
    }
  }

  // A scroll over the row switches workspace only if asked for (scroll): a
  // touchpad swipe across the bar did it by accident, and new windows then
  // opened somewhere else. A wheel notch moves one entry along the row, and a
  // touchpad adds up its smaller deltas until they make a notch's worth.
  property real wheelAccumulator: 0

  function scrollWorkspaces(delta) {
    if (root.config.scroll !== true) return
    var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
    root.wheelAccumulator = wheel.remainder
    if (wheel.steps === 0) return

    // Holds at either end rather than wrapping, so a touchpad swipe that runs
    // long stops on the last workspace.
    var ids = root.workspaceIds()
    var index = ids.indexOf(root.activeWorkspaceId())
    if (index === -1) return
    var target = ids[Util.clamp(index - wheel.steps, 0, ids.length - 1)]
    if (target !== ids[index]) root.focusWorkspace(target)
  }

  // The workspace each monitor shows carries its layout: a square tiles, a
  // circle scrolls, and a triangle floats. It only shows the layout: a click
  // never changes it (this desktop floats, and a stray click tiled it).
  property string activeMode: "dwindle"
  property bool modeStale: false

  function modeGlyph(mode) {
    if (mode === "scrolling") return "󰝥"
    if (mode === "floating") return "󰔶"
    return "󱓻"
  }

  // A layout only changes through the layout commands, which ask for a refresh,
  // or a config reload, so each workspace's mode is read once and cached rather
  // than running the script on every workspace switch.
  property var modeCache: ({})
  property int modeGeneration: 0
  property int modeProcWorkspace: -1
  property int modeProcGeneration: 0

  function showActiveMode() {
    var mode = root.modeCache[root.activeWorkspaceId()]
    if (mode !== undefined) root.activeMode = mode
    else readMode()
  }

  function readMode() {
    if (modeProc.running) {
      root.modeStale = true
      return
    }
    var id = root.activeWorkspaceId()
    if (id === -1) return
    root.modeProcWorkspace = id
    root.modeProcGeneration = root.modeGeneration
    modeProc.command = ["omarchy-hyprland-workspace-layout-current", String(id)]
    modeProc.running = true
  }

  function refresh() {
    root.modeCache = ({})
    root.modeGeneration++
    readMode()
  }

  Component.onCompleted: { refresh(); Hyprland.refreshToplevels() }
  onMonitorChanged: root.showActiveMode()

  Connections {
    target: root.monitor
    function onActiveWorkspaceChanged() { root.showActiveMode() }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (name === "configreloaded") root.refresh()
      // Quickshell credits every workspace switch to the focused monitor, as
      // the event doesn't say which one switched, and misses the workspace a
      // monitor falls back to when its own is moved away. Moving workspaces
      // between monitors switches the others, so ask Hyprland for the truth.
      // A workspace that changes number is only learned by asking too. Every
      // bar shares what Hyprland answers, so one asks after a plain switch.
      // Windows opened, closed, moved, pinned or retitled: their icons and
      // titles (and whether a dock has them) come from asking again.
      if (["openwindow", "closewindow", "movewindowv2", "pin", "windowtitlev2", "changefloatingmode"].indexOf(name) !== -1)
        refreshWindows.restart()
      var switched = name === "workspacev2" && root.monitor !== null && root.monitor.focused
      if (switched || name === "moveworkspacev2" || name === "changeworkspaceid") {
        Hyprland.refreshMonitors()
        Hyprland.refreshWorkspaces()
      }
    }
  }

  Timer { id: refreshWindows; interval: 150; onTriggered: Hyprland.refreshToplevels() }

  Process {
    id: modeProc
    stdout: StdioCollector {
      onStreamFinished: {
        var mode = text.trim()
        // A read that started before a refresh may predate the change.
        if (!mode || root.modeProcGeneration !== root.modeGeneration) return
        root.modeCache[root.modeProcWorkspace] = mode
        if (root.modeProcWorkspace === root.activeWorkspaceId()) root.activeMode = mode
      }
    }
    onExited: {
      if (!root.modeStale) return
      root.modeStale = false
      // Deferred: the process still reports running while it signals exit.
      Qt.callLater(root.showActiveMode)
    }
  }

  // Super + L and the default layout change the mode without a focus change,
  // so they ask every bar to read it again.
  ShellIpc {
    target: "omarchy.workspaces"

    function refresh(): void { root.broadcast("refresh") }
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        id: button
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property var windows: root.windowsOn(workspace)
        readonly property bool occupied: windows.length > 0
        readonly property bool shown: root.monitor !== null && root.monitor.activeWorkspace !== null && root.monitor.activeWorkspace.id === modelData
        readonly property int slot: root.slotOf(modelData)
        readonly property bool firstGuest: root.blockOf(modelData) !== root.block && index > 0 && root.blockOf(root.workspaceIds()[index - 1]) === root.block
        required property int index

        // A gap sets visiting workspaces apart from the monitor's own.
        Layout.leftMargin: firstGuest && !root.vertical ? Style.space(6) : 0
        Layout.topMargin: firstGuest && root.vertical ? Style.space(6) : 0

        bar: root.bar
        text: shown ? root.modeGlyph(root.activeMode) : (slot === root.slots ? "0" : String(slot))
        opacity: occupied || shown ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onTooltipHoveredChanged: root.hoverNumber(button, tooltipHovered)
        onPressed: function() {
          root.listFor = null
          root.focusWorkspace(modelData)
        }
        onWheelMoved: function(delta) { root.scrollWorkspaces(delta) }

        Text {  // how many windows: small, raised beside the number
          visible: root.showCounts && button.windows.length > 0
          x: parent.width / 2 + Style.space(4)
          y: parent.height / 2 - Style.space(11)
          text: String(button.windows.length)
          color: button.foreground
          font.family: button.fontFamily
          font.pixelSize: Math.round(button.fontSize * 0.62)
          font.bold: true
        }
      }
    }
  }
}
