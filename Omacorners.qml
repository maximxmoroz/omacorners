import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Corners.js" as Corners
import "Actions.js" as Actions

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "io.github.omargond.omacorners"
  readonly property string pluginDir: {
    var url = Qt.resolvedUrl(".")
    return url.toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  }
  readonly property string helperPath: pluginDir + "/scripts/omacorners-cursor"

  readonly property var pluginEntry: {
    var cfg = shell ? shell.shellConfig : null
    var pluginRec = ({})
    var list = cfg && Array.isArray(cfg.plugins) ? cfg.plugins : []
    for (var i = 0; i < list.length; i++) {
      if (list[i] && String(list[i].id || "") === pluginId) { pluginRec = list[i]; break }
    }
    var barRec = ({})
    var layout = cfg && cfg.bar && cfg.bar.layout ? cfg.bar.layout : null
    var sections = ["left", "center", "right"]
    if (layout) {
      for (var s = 0; s < sections.length; s++) {
        var arr = layout[sections[s]] || []
        for (var j = 0; j < arr.length; j++) {
          if (arr[j] && String(arr[j].id || "") === pluginId) { barRec = arr[j]; s = 99; break }
        }
      }
    }
    if (!Actions.entryIsThin(barRec)) return barRec
    if (!Actions.entryIsThin(pluginRec)) return pluginRec
    if (barRec && barRec.id) return barRec
    return pluginRec
  }

  readonly property bool active: pluginEntry.active === false ? false : true
  readonly property int delayMs: Corners.clampDelayMs(pluginEntry.delayMs === undefined ? 400 : pluginEntry.delayMs)
  readonly property int thresholdPx: Corners.clampThresholdPx(pluginEntry.thresholdPx === undefined ? 8 : pluginEntry.thresholdPx)
  readonly property int powerDelayMs: Actions.clampPowerDelayMs(pluginEntry.powerDelayMs === undefined ? 800 : pluginEntry.powerDelayMs)
  readonly property bool requireSuper: pluginEntry.requireSuper === false ? false : true
  readonly property bool suppressFullscreen: pluginEntry.suppressFullscreen === false ? false : true
  readonly property bool suppressDrag: pluginEntry.suppressDrag === false ? false : true
  readonly property bool suppressOverlay: pluginEntry.suppressOverlay === false ? false : true
  readonly property string topLeft: Actions.normalize(pluginEntry.topLeft)
  readonly property string topRight: Actions.normalize(pluginEntry.topRight)
  readonly property string bottomLeft: Actions.normalize(pluginEntry.bottomLeft)
  readonly property string bottomRight: Actions.normalize(pluginEntry.bottomRight)
  readonly property var workspaceMap: Actions.normalizeWorkspaceMap(pluginEntry.workspaces)
  readonly property bool welcomed: pluginEntry.welcomed === true
  readonly property string workspaceKey: Actions.workspaceKeyFrom(Hyprland.focusedWorkspace)
  // Quickshell 0.3.1's Hyprland.usingLua reports false even though Hyprland 0.5x
  // only accepts the Lua dispatch syntax, so force it on. Revert to
  // `Hyprland.usingLua === true` if this ever runs on classic-dispatch Hyprland.
  readonly property bool hyprUsingLua: true

  property var actionOptions: []
  property string pendingPower: ""
  property bool superArmed: true
  property bool superSeen: false
  property bool dragging: false
  property string focusDesktopId: ""
  property string focusAction: ""
  property string focusActiveAddr: ""
  property string focusFromWorkspace: ""

  property int cursorX: -100000
  property int cursorY: -100000
  property string dwellCorner: ""
  property string dwellScreen: ""
  property real dwellProgress: 0
  property double dwellStartedAt: 0
  property bool latched: false
  property bool pulsing: false
  property int helperRestarts: 0
  property bool helperStarted: false
  property string lastHelperCorner: ""
  property string lastHelperScreen: ""
  property bool hideWindowsPending: false
  property string hideWindowsMonitor: ""
  property var hideWindowsParked: ({})

  readonly property string liveCorner: dwellCorner
  readonly property string liveScreen: dwellScreen
  readonly property real liveProgress: dwellProgress

  function whichFromCorner(corner) {
    if (corner === "tl") return "topLeft"
    if (corner === "tr") return "topRight"
    if (corner === "bl") return "bottomLeft"
    if (corner === "br") return "bottomRight"
    return ""
  }

  function defaults() {
    return { topLeft: topLeft, topRight: topRight, bottomLeft: bottomLeft, bottomRight: bottomRight }
  }

  function resolvedCorner(which) {
    return Actions.resolved(defaults(), workspaceMap, workspaceKey, which)
  }

  function actionForCorner(corner) {
    var which = whichFromCorner(corner)
    if (!which) return "none"
    return resolvedCorner(which)
  }

  readonly property bool fullscreenActive: {
    var top = Hyprland.activeToplevel
    var obj = top ? top.lastIpcObject : null
    if (!obj) return false
    var fs = obj.fullscreen
    return fs === 1 || fs === 2 || fs === true
  }

  function overlayBlocking() {
    if (pendingPower !== "") return true
    if (!shell || typeof shell.isPluginOpen !== "function") return false
    var ids = ["omarchy.menu", "omarchy.emojis", "omarchy.clipboard", "omarchy.image-picker"]
    for (var i = 0; i < ids.length; i++) {
      try { if (shell.isPluginOpen(ids[i])) return true } catch (e) {}
    }
    return false
  }

  function waitFor(action) {
    var base = delayMs
    if (Actions.needsConfirm(action)) return base + powerDelayMs
    return base
  }

  function labelForCorner(corner) {
    return prettyLabel(actionForCorner(corner))
  }

  function prettyLabel(id) {
    var value = Actions.normalize(id)
    var opts = actionOptions
    if (opts && opts.length) {
      for (var i = 0; i < opts.length; i++) {
        if (opts[i] && opts[i].value === value) return String(opts[i].label)
      }
    }
    return Actions.labelOf(value)
  }

  function refreshActionOptions() {
    var out = Actions.options()
    var seen = ({})
    for (var i = 0; i < out.length; i++) seen[out[i].value] = true

    var apps = []
    try {
      var values = DesktopEntries.applications.values || []
      var n = values.length
      if (typeof n !== "number") n = 0
      if (n > 400) n = 400
      for (var j = 0; j < n; j++) {
        var entry = values[j]
        if (!entry || entry.noDisplay === true) continue
        var desk = Actions.normalizeDesktopId(entry.id)
        if (!desk) continue
        var value = Actions.appAction(desk)
        if (seen[value]) continue
        seen[value] = true
        apps.push({ value: value, label: String(entry.name || desk) })
      }
    } catch (e) {}

    apps.sort(function(a, b) {
      var al = String(a.label).toLowerCase()
      var bl = String(b.label).toLowerCase()
      if (al < bl) return -1
      if (al > bl) return 1
      return 0
    })
    actionOptions = out.concat(apps)
  }

  function persist(changes) {
    var entry = {
      id: pluginId,
      active: active,
      delayMs: delayMs,
      thresholdPx: thresholdPx,
      powerDelayMs: powerDelayMs,
      requireSuper: requireSuper,
      suppressFullscreen: suppressFullscreen,
      suppressDrag: suppressDrag,
      suppressOverlay: suppressOverlay,
      topLeft: topLeft,
      topRight: topRight,
      bottomLeft: bottomLeft,
      bottomRight: bottomRight,
      workspaces: workspaceMap,
      welcomed: welcomed
    }
    if (changes) {
      for (var key in changes) entry[key] = changes[key]
    }
    if (entry.topLeft !== undefined) entry.topLeft = Actions.normalize(entry.topLeft)
    if (entry.topRight !== undefined) entry.topRight = Actions.normalize(entry.topRight)
    if (entry.bottomLeft !== undefined) entry.bottomLeft = Actions.normalize(entry.bottomLeft)
    if (entry.bottomRight !== undefined) entry.bottomRight = Actions.normalize(entry.bottomRight)
    if (entry.delayMs !== undefined) entry.delayMs = Corners.clampDelayMs(entry.delayMs)
    if (entry.thresholdPx !== undefined) entry.thresholdPx = Corners.clampThresholdPx(entry.thresholdPx)
    if (entry.powerDelayMs !== undefined) entry.powerDelayMs = Actions.clampPowerDelayMs(entry.powerDelayMs)
    if (entry.workspaces !== undefined) entry.workspaces = Actions.normalizeWorkspaceMap(entry.workspaces)
    if (shell && typeof shell.mutateShellConfig === "function") {
      var payload = JSON.parse(JSON.stringify(entry))
      shell.mutateShellConfig(function(config) {
        root.writeEntryInto(config, payload)
      })
      return
    }
    if (shell && typeof shell.updateEntryInline === "function")
      shell.updateEntryInline(pluginId, entry)
  }

  function writeEntryInto(config, entry) {
    var written = false
    if (!config.plugins) config.plugins = []
    for (var j = 0; j < config.plugins.length; j++) {
      if (config.plugins[j] && String(config.plugins[j].id || "") === pluginId) {
        config.plugins[j] = entry
        written = true
      }
    }
    var layout = config.bar && config.bar.layout ? config.bar.layout : null
    var sections = ["left", "center", "right"]
    if (layout) {
      for (var s = 0; s < sections.length; s++) {
        var arr = layout[sections[s]] || []
        for (var i = 0; i < arr.length; i++) {
          if (arr[i] && String(arr[i].id || "") === pluginId) {
            layout[sections[s]][i] = entry
            written = true
          }
        }
      }
    }
    if (!written) config.plugins.push(entry)
  }

  function setCorner(which, id, workspaceScope) {
    if (which !== "topLeft" && which !== "topRight" && which !== "bottomLeft" && which !== "bottomRight")
      return
    if (workspaceScope && Actions.isWorkspaceKey(workspaceScope)) {
      persist({ workspaces: Actions.withOverride(workspaceMap, workspaceScope, which, id) })
      return
    }
    var changes = {}
    changes[which] = Actions.normalize(id)
    persist(changes)
  }

  function clearWorkspace(workspaceScope) {
    persist({ workspaces: Actions.withoutWorkspace(workspaceMap, workspaceScope) })
  }

  function setRequireSuper(value) { persist({ requireSuper: value !== false }) }
  function setSuppressFullscreen(value) { persist({ suppressFullscreen: value !== false }) }
  function setSuppressDrag(value) { persist({ suppressDrag: value !== false }) }
  function setSuppressOverlay(value) { persist({ suppressOverlay: value !== false }) }
  function setPowerDelayMs(value) { persist({ powerDelayMs: Actions.clampPowerDelayMs(value) }) }

  function setDelayMs(value) {
    persist({ delayMs: Corners.clampDelayMs(value) })
  }

  function setThresholdPx(value) {
    persist({ thresholdPx: Corners.clampThresholdPx(value) })
  }

  function setActive(value) {
    persist({ active: value !== false })
  }

  onActiveChanged: {
    if (active) startHelper()
    else {
      stopHelper()
      clearDwell()
    }
  }

  function clearDwell() {
    dwellTimer.stop()
    dwellCorner = ""
    dwellScreen = ""
    dwellProgress = 0
  }

  function blocked() {
    if (!active) return true
    if (pendingPower !== "") return true
    if (requireSuper && superSeen && !superArmed) return true
    if (suppressDrag && dragging) return true
    if (suppressOverlay && overlayBlocking()) return true
    return false
  }

  function fullscreenOn(monitorName) {
    var top = Hyprland.activeToplevel
    var obj = top ? top.lastIpcObject : null
    if (!obj) return false
    var fs = obj.fullscreen
    if (!(fs === 1 || fs === 2 || fs === true)) return false
    var mon = obj.monitor
    if (monitorName && mon !== undefined && mon !== null && String(mon) !== "" && String(mon) !== String(monitorName))
      return false
    return true
  }

  function scaledScreens() {
    var fromHypr = Corners.screensFromHyprland(Hyprland.monitors)
    if (fromHypr.length) return fromHypr
    return Corners.screensFromModel(Quickshell.screens)
  }

  function onCursor(x, y, helperCorner, helperScreen) {
    cursorX = x
    cursorY = y
    if (pendingPower !== "") return
    if (blocked()) {
      clearDwell()
      return
    }
    var hit = null
    if (helperCorner && helperCorner !== "none")
      hit = { corner: helperCorner, name: helperScreen && helperScreen !== "-" ? helperScreen : "" }
    else
      hit = Corners.hit(root.scaledScreens(), x, y, thresholdPx)
    if (!hit || actionForCorner(hit.corner) === "none") {
      latched = false
      clearDwell()
      return
    }
    if (suppressFullscreen && root.fullscreenOn(hit.name)) {
      latched = false
      clearDwell()
      return
    }
    if (latched && hit.corner === dwellCorner && hit.name === dwellScreen) return
    if (hit.corner === dwellCorner && hit.name === dwellScreen) {
      updateProgress()
      return
    }
    latched = false
    dwellCorner = hit.corner
    dwellScreen = hit.name
    dwellStartedAt = Date.now()
    var wait = waitFor(actionForCorner(hit.corner))
    dwellTimer.interval = Math.max(1, wait)
    dwellProgress = wait <= 0 ? 1 : 0
    if (wait <= 0) fire()
    else dwellTimer.restart()
  }

  function updateProgress() {
    var wait = waitFor(actionForCorner(dwellCorner))
    if (wait <= 0) {
      dwellProgress = 1
      return
    }
    dwellProgress = Math.max(0, Math.min(1, (Date.now() - dwellStartedAt) / wait))
  }

  function executeAction(action) {
    var matchId = Actions.isAppAction(action)
      ? Actions.desktopIdOf(action)
      : Actions.focusClassOf(action)
    if (matchId) {
      focusOrLaunch(matchId, action)
      return
    }
    root.runAction(action)
  }

  function runAction(action) {
    if (Actions.normalize(action) === "hide-windows") {
      root.toggleHideWindows()
      return
    }
    Actions.run(action, function(dispatch) {
      var req = root.hyprUsingLua ? Actions.classicToLua(dispatch) : dispatch
      if (req) Hyprland.dispatch(req)
    }, function(argv) {
      Util.execArgv(argv)
    })
  }

  function workspaceIdOnScreen(screenName) {
    if (screenName) {
      try {
        var model = Hyprland.monitors
        var n = model ? model.length : 0
        if (typeof n !== "number" || n < 0) n = 0
        if (n > 16) n = 16
        for (var i = 0; i < n; i++) {
          var s = model[i]
          if (!s || String(s.name || "") !== String(screenName)) continue
          var aws = s.activeWorkspace
          var aid = aws && aws.id != null ? Number(aws.id) : NaN
          if (isFinite(aid) && aid > 0) return Math.round(aid)
        }
      } catch (e) {}
    }
    var key = Number(root.workspaceKey)
    if (isFinite(key) && key > 0) return Math.round(key)
    try {
      var fw = Hyprland.focusedWorkspace
      var fid = fw && fw.id != null ? Number(fw.id) : NaN
      if (isFinite(fid) && fid > 0) return Math.round(fid)
    } catch (e2) {}
    return 0
  }

  function toggleHideWindows() {
    hideWindowsMonitor = dwellScreen || lastHelperScreen || ""
    hideWindowsPending = true
    if (clientsProc.running) clientsProc.running = false
    clientsProc.running = true
  }

  function applyHideWindows(raw) {
    var list
    try { list = JSON.parse(String(raw || "")) } catch (e) { return }
    if (!Array.isArray(list)) return
    var wsId = workspaceIdOnScreen(hideWindowsMonitor)
    if (wsId <= 0) return
    var slot = String(wsId)
    var lua = root.hyprUsingLua
    var specialName = "special:" + Actions.HIDE_SPECIAL
    var hideable = []
    var n = list.length
    if (typeof n !== "number" || n < 0) return
    if (n > 256) n = 256
    for (var i = 0; i < n; i++) {
      var c = list[i]
      if (!c || typeof c !== "object") continue
      if (c.mapped === false || c.hidden === true || c.pinned === true) continue
      var addr = Actions.canonicalAddress(c.address)
      if (!addr) continue
      var name = c.workspace && c.workspace.name != null ? String(c.workspace.name) : ""
      var id = c.workspace && c.workspace.id != null ? Number(c.workspace.id) : 0
      if (name.indexOf("special") === 0) continue
      if (!isFinite(id) || Math.round(id) !== wsId) continue
      var at = Actions.xyPair(c.at)
      var size = Actions.xyPair(c.size)
      hideable.push({
        address: addr,
        workspace: wsId,
        x: at ? at[0] : 0,
        y: at ? at[1] : 0,
        w: size ? size[0] : 0,
        h: size ? size[1] : 0
      })
    }
    hideable.sort(function(a, b) {
      if (a.y !== b.y) return a.y - b.y
      return a.x - b.x
    })
    var parked = hideWindowsParked && typeof hideWindowsParked === "object" ? hideWindowsParked : ({})
    if (hideable.length) {
      var nextParked = ({})
      for (var key in parked) {
        if (Object.prototype.hasOwnProperty.call(parked, key)) nextParked[key] = parked[key]
      }
      nextParked[slot] = hideable
      hideWindowsParked = nextParked
      for (var h = 0; h < hideable.length; h++) {
        var hideReq = Actions.moveWindowSilentDispatch(specialName, hideable[h].address, lua)
        if (hideReq) hyprDispatch(hideReq)
      }
      return
    }
    var saved = parked[slot] || []
    if (!saved.length) return
    for (var p = 0; p < saved.length; p++) {
      var showReq = Actions.moveWindowSilentDispatch(String(saved[p].workspace), saved[p].address, lua)
      if (showReq) hyprDispatch(showReq)
    }
    for (var g = 0; g < saved.length; g++) {
      var win = saved[g]
      var moveReq = Actions.moveWindowPixelExactDispatch(win.x, win.y, win.address, lua)
      if (moveReq) hyprDispatch(moveReq)
      var resizeReq = Actions.resizeWindowPixelExactDispatch(win.w, win.h, win.address, lua)
      if (resizeReq) hyprDispatch(resizeReq)
    }
    var cleared = ({})
    for (var k in parked) {
      if (Object.prototype.hasOwnProperty.call(parked, k) && k !== slot) cleared[k] = parked[k]
    }
    hideWindowsParked = cleared
  }

  function hyprDispatch(request) {
    if (!request) return
    Hyprland.dispatch(request)
  }

  function activeWindowAddress() {
    var top = Hyprland.activeToplevel
    if (!top) return ""
    var addr = top.address ? String(top.address) : ""
    if (!addr && top.lastIpcObject && top.lastIpcObject.address)
      addr = String(top.lastIpcObject.address)
    return Actions.canonicalAddress(addr)
  }

  function revealWindow(addr, ws) {
    if (!Actions.isWindowAddress(addr)) return
    var lua = root.hyprUsingLua
    var windowReq = Actions.focusWindowDispatch(addr, lua)
    if (!windowReq) return
    var fromWs = focusFromWorkspace || root.workspaceKey
    if (ws && Actions.isWorkspaceKey(ws) && ws !== fromWs) {
      var wsReq = Actions.focusWorkspaceDispatch(ws, lua)
      if (wsReq) hyprDispatch(wsReq)
    }
    hyprDispatch(windowReq)
  }

  function focusOrLaunch(matchId, action) {
    var desk = Actions.normalizeDesktopId(matchId)
    if (!desk) {
      root.runAction(action)
      return
    }
    if (clientsProc.running) clientsProc.running = false
    focusDesktopId = desk
    focusAction = action
    focusActiveAddr = root.activeWindowAddress()
    focusFromWorkspace = root.workspaceKey
    clientsProc.running = true
  }

  function fire() {
    if (!active || latched || dwellCorner === "" || pendingPower !== "") return
    var action = actionForCorner(dwellCorner)
    if (action === "none") return
    latched = true
    dwellProgress = 1
    pulsing = true
    pulseTimer.restart()
    if (Actions.needsConfirm(action)) {
      if (shell && typeof shell.hide === "function") shell.hide(pluginId)
      pendingPower = action
      return
    }
    executeAction(action)
  }

  function confirmPower() {
    var action = pendingPower
    pendingPower = ""
    if (Actions.needsConfirm(action)) executeAction(action)
  }

  function cancelPower() {
    pendingPower = ""
  }

  onPendingPowerChanged: {
    if (pendingPower !== "")
      Qt.callLater(function() { confirmKeyCatcher.forceActiveFocus() })
  }

  function startHelper() {
    if (!active) return
    if (helperProc.running) return
    helperProc.running = true
    helperStarted = true
  }

  function stopHelper() {
    if (helperProc.running) helperProc.running = false
    helperStarted = false
  }

  Component.onCompleted: {
    refreshActionOptions()
    if (active) startHelper()
    if (!welcomed) welcomeTimer.start()
  }

  onWelcomedChanged: if (welcomed) welcomeTimer.stop()

  Component.onDestruction: stopHelper()

  Timer {
    id: welcomeTimer
    interval: 1500
    repeat: false
    onTriggered: {
      if (root.welcomed) return
      root.persist({ welcomed: true })
      Quickshell.execDetached([
        "omarchy-notification-send",
        "Omacorners is on",
        "Open settings to assign an action to each screen corner."
      ])
    }
  }

  Timer {
    id: dwellTimer
    interval: Math.max(1, root.delayMs)
    repeat: false
    onTriggered: root.fire()
  }

  Timer {
    id: progressTimer
    interval: 16
    repeat: true
    running: root.dwellCorner !== "" && !root.latched && root.waitFor(root.actionForCorner(root.dwellCorner)) > 0
    onTriggered: root.updateProgress()
  }

  Timer {
    id: pulseTimer
    interval: 280
    repeat: false
    onTriggered: root.pulsing = false
  }

  Timer {
    id: helperRestartTimer
    interval: Math.min(8000, 500 * Math.pow(2, Math.min(4, root.helperRestarts)))
    repeat: false
    onTriggered: {
      if (root.active) root.startHelper()
    }
  }

  Process {
    id: helperProc
    running: false
    command: ["python3", root.helperPath]

    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(data) {
        var line = String(data || "").trim()
        if (line === "ARM 1" || line === "ARM 0") {
          root.superSeen = true
          root.superArmed = line === "ARM 1"
          return
        }
        if (line === "DRAG 1" || line === "DRAG 0") {
          root.dragging = line === "DRAG 1"
          return
        }
        if (line.indexOf("HIT ") === 0) {
          var hitParts = line.split(" ")
          root.lastHelperCorner = hitParts.length >= 2 ? hitParts[1] : ""
          root.lastHelperScreen = hitParts.length >= 3 ? hitParts[2] : ""
          return
        }
        if (line.indexOf("POS ") !== 0) return
        var parts = line.split(" ")
        if (parts.length < 3) return
        var x = parseInt(parts[1], 10)
        var y = parseInt(parts[2], 10)
        if (isNaN(x) || isNaN(y)) return
        root.helperRestarts = 0
        root.onCursor(x, y, root.lastHelperCorner, root.lastHelperScreen)
      }
    }

    stderr: SplitParser {
      splitMarker: "\n"
      onRead: function(data) {
        var line = String(data || "").trim()
        if (line) console.warn("omacorners-cursor: " + line)
      }
    }

    onExited: function(code) {
      root.helperStarted = false
      if (!root.active) return
      root.helperRestarts += 1
      if (root.helperRestarts > 12) {
        console.warn("omacorners: helper gave up after repeated exits, code " + code)
        return
      }
      helperRestartTimer.restart()
    }
  }

  Process {
    id: clientsProc
    running: false
    command: ["hyprctl", "-j", "clients"]
    stdout: StdioCollector {
      id: clientsOut
      waitForEnd: true
    }
    onExited: function(code) {
      if (root.hideWindowsPending) {
        root.hideWindowsPending = false
        if (code === 0) root.applyHideWindows(clientsOut.text)
        return
      }
      var desk = root.focusDesktopId
      var action = root.focusAction
      var activeAddr = root.focusActiveAddr
      var fromWs = root.focusFromWorkspace
      root.focusDesktopId = ""
      root.focusAction = ""
      root.focusActiveAddr = ""
      root.focusFromWorkspace = ""
      if (!desk) return
      var hit = code === 0 ? Actions.findClient(clientsOut.text, desk, fromWs, activeAddr) : null
      if (hit && hit.address) {
        root.revealWindow(hit.address, hit.workspace)
        return
      }
      root.runAction(action || Actions.appAction(desk))
    }
  }

  IpcHandler {
    target: "omacorners"
    function ping(): string { return "ok" }
    function status(): string {
      return JSON.stringify({
        active: root.active,
        delayMs: root.delayMs,
        thresholdPx: root.thresholdPx,
        powerDelayMs: root.powerDelayMs,
        requireSuper: root.requireSuper,
        workspaceKey: root.workspaceKey,
        topLeft: root.resolvedCorner("topLeft"),
        topRight: root.resolvedCorner("topRight"),
        bottomLeft: root.resolvedCorner("bottomLeft"),
        bottomRight: root.resolvedCorner("bottomRight"),
        cursorX: root.cursorX,
        cursorY: root.cursorY,
        dwellCorner: root.dwellCorner,
        helper: helperProc.running,
        pendingPower: root.pendingPower,
        superArmed: root.superArmed,
        superSeen: root.superSeen,
        dragging: root.dragging,
        usingLua: root.hyprUsingLua
      })
    }
    function hideWindows(): string {
      root.toggleHideWindows()
      return "ok"
    }
    function toggle(): string {
      if (root.shell && typeof root.shell.toggle === "function") {
        root.shell.toggle(root.pluginId)
        return "ok"
      }
      return "no-shell"
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: glowWindow
      required property var modelData
      screen: modelData
      visible: true
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "omacorners-glow"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      anchors { top: true; bottom: true; left: true; right: true }
      mask: Region {}

      readonly property bool onThisScreen: root.dwellScreen === String(modelData.name || "")
      readonly property bool showGlow: root.active && onThisScreen && root.dwellCorner !== ""
      readonly property real glowSize: Style.space(root.pulsing ? 168 : (110 + Math.round(50 * root.dwellProgress)))
      readonly property real glowOpacity: {
        if (!showGlow) return 0
        if (root.pulsing) return 0.55
        return 0.12 + 0.38 * root.dwellProgress
      }

      function glowX(corner) {
        if (corner === "tr" || corner === "br") return glowWindow.width - glowSize / 2
        return -glowSize / 2
      }

      function glowY(corner) {
        if (corner === "bl" || corner === "br") return glowWindow.height - glowSize / 2
        return -glowSize / 2
      }

      Rectangle {
        id: glow
        width: glowWindow.glowSize
        height: glowWindow.glowSize
        radius: width / 2
        x: glowWindow.glowX(root.dwellCorner)
        y: glowWindow.glowY(root.dwellCorner)
        color: Color.accent
        opacity: glowWindow.glowOpacity
        visible: glowWindow.showGlow && opacity > 0.01

        Behavior on opacity { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
      }
    }
  }

  PanelWindow {
    id: confirmWindow
    visible: root.pendingPower !== ""
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omacorners-confirm"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.pendingPower !== "" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    ConfirmDialog {
      id: powerConfirm
      anchors.fill: parent
      opened: root.pendingPower !== ""
      message: Actions.confirmMessage(root.pendingPower)
      confirmText: Actions.confirmLabel(root.pendingPower)
      cancelText: "Cancel"
      background: Color.menu.background
      foreground: Color.menu.text
      scrim: Color.menu.scrim
      fontFamily: Style.font.menuFamily
      cornerRadius: Style.cornerRadius
      onConfirmed: root.confirmPower()
      onCanceled: root.cancelPower()
    }

    Item {
      id: confirmKeyCatcher
      anchors.fill: parent
      focus: root.pendingPower !== ""
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (powerConfirm.handleKey(event)) event.accepted = true
      }
    }
  }
}
