.pragma library

// Built-in actions are a closed whitelist. Application launches use
// `app:<desktop-id>` where the desktop id is validated before it is
// persisted or executed. Argv vectors for built-ins are constant.
// App argv is a constant prefix plus that validated id.

var ORDER = [
  "none",
  "lock",
  "screensaver",
  "desktop",
  "hide-windows",
  "menu",
  "notifications",
  "clipboard",
  "emojis",
  "screenshot",
  "color",
  "dnd",
  "nightlight",
  "bar",
  "terminal",
  "browser",
  "agent",
  "workspace-next",
  "workspace-prev",
  "shutdown",
  "reboot",
  "settings"
]

var META = {
  "none": { label: "None", kind: "none" },
  "lock": { label: "Lock screen", kind: "argv", argv: ["omarchy-system-lock"] },
  "screensaver": { label: "Screensaver", kind: "argv", argv: ["omarchy-launch-screensaver", "force"] },
  "desktop": { label: "Show desktop", kind: "hypr", dispatch: "togglespecialworkspace omacorners" },
  "hide-windows": { label: "Hide windows", kind: "hide-windows" },
  "menu": { label: "Omarchy menu", kind: "argv", argv: ["omarchy-menu", "toggle"] },
  "notifications": { label: "Notification history", kind: "argv", argv: ["omarchy-shell", "notifications", "showHistory"] },
  "clipboard": { label: "Clipboard history", kind: "argv", argv: ["omarchy-shell", "shell", "toggle", "omarchy.clipboard"] },
  "emojis": { label: "Emoji picker", kind: "argv", argv: ["omarchy-shell", "shell", "toggle", "omarchy.emojis"] },
  "screenshot": { label: "Screenshot", kind: "argv", argv: ["omarchy-capture-screenshot"] },
  "color": { label: "Color picker", kind: "argv", argv: ["hyprpicker", "-a"] },
  "dnd": { label: "Do not disturb", kind: "argv", argv: ["omarchy-toggle-notification-silencing"] },
  "nightlight": { label: "Night light", kind: "argv", argv: ["omarchy-toggle-nightlight"] },
  "bar": { label: "Toggle bar", kind: "argv", argv: ["omarchy-toggle-bar"] },
  "terminal": { label: "Terminal", kind: "argv", argv: ["omarchy-launch-terminal"] },
  "browser": { label: "Browser", kind: "argv", argv: ["omarchy-launch-browser"] },
  "agent": { label: "Default agent", kind: "argv", argv: ["omarchy-agent"], focusClass: "org.omarchy.agent" },
  "workspace-next": { label: "Next workspace", kind: "hypr", dispatch: "workspace e+1" },
  "workspace-prev": { label: "Previous workspace", kind: "hypr", dispatch: "workspace e-1" },
  "shutdown": { label: "Shut down", kind: "argv", argv: ["omarchy-system-shutdown"] },
  "reboot": { label: "Restart", kind: "argv", argv: ["omarchy-system-reboot"] },
  "settings": { label: "Omacorners settings", kind: "argv", argv: ["omarchy-shell", "shell", "toggle", "io.github.omargond.omacorners"] }
}

var DESKTOP_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._+\- ]{0,127}$/

var AGENT_IDS = {
  "agy": { label: "Antigravity", argv: ["agy", "--dangerously-skip-permissions"] },
  "claude": { label: "Claude", argv: ["claude", "--permission-mode", "auto"] },
  "codex": { label: "Codex", argv: ["codex", "--approve-for-me"] },
  "copilot": { label: "Copilot", argv: ["copilot", "--allow-all"] },
  "crush": { label: "Crush", argv: ["crush", "--yolo"] },
  "grok": { label: "Grok", argv: ["grok", "--permission-mode", "bypassPermissions"] },
  "omp": { label: "omp", argv: ["omp", "--auto-approve"] },
  "opencode": { label: "OpenCode", argv: ["opencode", "--auto"] },
  "ori": { label: "Ori", argv: ["ori", "code"] },
  "pi": { label: "Pi", argv: ["pi"] }
}

var AGENT_NAME_PATTERN = /^[a-z][a-z0-9]{0,31}$/

function isDesktopId(id) {
  if (typeof id !== "string" || id.length === 0 || id.length > 128) return false
  if (id.indexOf("..") !== -1) return false
  if (id.indexOf("/") !== -1 || id.indexOf("\\") !== -1) return false
  if (/[\n\r\0;|$`&<>'"()]/.test(id)) return false
  return DESKTOP_ID_PATTERN.test(id)
}

function isAgentName(id) {
  return typeof id === "string" && AGENT_NAME_PATTERN.test(id) && AGENT_IDS[id] !== undefined
}

function isAgentAction(id) {
  return typeof id === "string" && id.indexOf("agent:") === 0 && isAgentName(id.substring(6))
}

function agentNameOf(id) {
  return isAgentAction(id) ? id.substring(6) : ""
}

function agentArgv(name) {
  if (!isAgentName(name)) return null
  var spec = AGENT_IDS[name]
  return ["omarchy-launch-tui", "--app-id=org.omarchy.agent." + name].concat(spec.argv.slice())
}

function normalizeDesktopId(id) {
  var value = String(id || "").trim()
  if (value.slice(-8) === ".desktop") value = value.slice(0, -8)
  return isDesktopId(value) ? value : ""
}

function isAppAction(id) {
  return typeof id === "string" && id.indexOf("app:") === 0 && isDesktopId(id.substring(4))
}

function desktopIdOf(id) {
  return isAppAction(id) ? id.substring(4) : ""
}

function appAction(desktopId) {
  var id = normalizeDesktopId(desktopId)
  return id ? ("app:" + id) : "none"
}

function isBuiltin(id) {
  return typeof id === "string" && META[id] !== undefined
}

function isAction(id) {
  return isBuiltin(id) || isAppAction(id) || isAgentAction(id)
}

function normalize(id) {
  if (isBuiltin(id)) return id
  if (isAppAction(id)) return id
  if (isAgentAction(id)) return id
  return "none"
}

function labelOf(id) {
  if (isAppAction(id)) return desktopIdOf(id)
  if (isAgentAction(id)) return AGENT_IDS[agentNameOf(id)].label
  return META[normalize(id)].label
}

function needsConfirm(id) {
  id = normalize(id)
  return id === "shutdown" || id === "reboot"
}

function confirmMessage(id) {
  if (id === "reboot") return "Restart this computer?"
  if (id === "shutdown") return "Shut down this computer?"
  return ""
}

function confirmLabel(id) {
  if (id === "reboot") return "Restart"
  if (id === "shutdown") return "Shut down"
  return "Confirm"
}

function options() {
  var out = []
  for (var i = 0; i < ORDER.length; i++) {
    var id = ORDER[i]
    out.push({ value: id, label: META[id].label })
  }
  var names = []
  for (var name in AGENT_IDS) {
    if (AGENT_IDS.hasOwnProperty(name)) names.push(name)
  }
  names.sort()
  for (var n = 0; n < names.length; n++) {
    var agent = names[n]
    out.push({ value: "agent:" + agent, label: AGENT_IDS[agent].label })
  }
  return out
}

var CORNERS = ["topLeft", "topRight", "bottomLeft", "bottomRight"]
var WORKSPACE_KEY = /^[1-9][0-9]{0,2}$/
var WORKSPACE_MAP_MAX = 32

function clampPowerDelayMs(value) {
  var n = Number(value)
  if (!isFinite(n)) return 800
  if (n < 0) return 0
  if (n > 2000) return 2000
  return Math.round(n)
}

function workspaceKeyFrom(ws) {
  if (!ws) return ""
  var id = Number(ws.id)
  if (!isFinite(id) || id < 1 || id > 999) return ""
  return String(Math.round(id))
}

function isWorkspaceKey(key) {
  return typeof key === "string" && WORKSPACE_KEY.test(key)
}

function isRelativeWorkspace(key) {
  return key === "e+1" || key === "e-1"
}

function normalizeWorkspaceMap(raw) {
  var out = {}
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return out
  var keys = []
  for (var key in raw) {
    if (!raw.hasOwnProperty(key)) continue
    keys.push(key)
  }
  if (keys.length > WORKSPACE_MAP_MAX) keys = keys.slice(0, WORKSPACE_MAP_MAX)
  for (var i = 0; i < keys.length; i++) {
    var k = keys[i]
    if (!isWorkspaceKey(k)) continue
    var rec = raw[k]
    if (!rec || typeof rec !== "object") continue
    var cleaned = {}
    var any = false
    for (var c = 0; c < CORNERS.length; c++) {
      var which = CORNERS[c]
      if (rec[which] === undefined || rec[which] === null || rec[which] === "") continue
      cleaned[which] = normalize(rec[which])
      any = true
    }
    if (any) out[k] = cleaned
  }
  return out
}

function resolved(defaults, map, wsKey, which) {
  var over = map && isWorkspaceKey(wsKey) ? map[wsKey] : null
  if (over && over[which] !== undefined) return normalize(over[which])
  return normalize(defaults ? defaults[which] : "none")
}

function hasOverride(map, wsKey) {
  return !!(map && isWorkspaceKey(wsKey) && map[wsKey])
}

function isOverridden(map, wsKey, which) {
  var over = map && isWorkspaceKey(wsKey) ? map[wsKey] : null
  return !!(over && over[which] !== undefined)
}

function withOverride(map, wsKey, which, action) {
  var next = normalizeWorkspaceMap(map)
  if (!isWorkspaceKey(wsKey)) return next
  var rec = next[wsKey] ? next[wsKey] : {}
  var copy = {}
  for (var i = 0; i < CORNERS.length; i++) {
    var c = CORNERS[i]
    if (rec[c] !== undefined) copy[c] = rec[c]
  }
  copy[which] = normalize(action)
  next[wsKey] = copy
  return next
}

function withoutWorkspace(map, wsKey) {
  var next = normalizeWorkspaceMap(map)
  if (next[wsKey]) delete next[wsKey]
  return next
}

function entryIsThin(entry) {
  if (!entry || typeof entry !== "object") return true
  for (var k in entry) {
    if (!entry.hasOwnProperty(k)) continue
    if (k === "id") continue
    return false
  }
  return true
}

function focusClassOf(id) {
  if (isAgentAction(id)) return "org.omarchy.agent." + agentNameOf(id)
  if (!isBuiltin(id) || !META[id]) return ""
  var klass = META[id].focusClass
  return typeof klass === "string" ? klass : ""
}

function classMatchesDesktop(klass, initialClass, desktopId) {
  var id = String(desktopId || "").toLowerCase()
  if (!id) return false
  var klassL = String(klass || "").toLowerCase()
  var initial = String(initialClass || "").toLowerCase()
  var lastDot = id.lastIndexOf(".")
  var last = lastDot >= 0 ? id.substring(lastDot + 1) : id
  if (klassL === id || initial === id) return true
  if (klassL === last || initial === last) return true
  if (klassL.replace(/_/g, "-") === id || initial.replace(/_/g, "-") === id) return true
  return false
}

function canonicalAddress(addr) {
  var s = String(addr || "").toLowerCase()
  if (s.indexOf("0x") === 0) s = s.substring(2)
  if (!/^[0-9a-f]{4,18}$/.test(s)) return ""
  return "0x" + s
}

function isWindowAddress(addr) {
  return canonicalAddress(addr) !== ""
}

function sameAddress(a, b) {
  var left = canonicalAddress(a)
  var right = canonicalAddress(b)
  return left !== "" && left === right
}

function luaQuote(value) {
  return String(value || "").replace(/\\/g, "").replace(/"/g, "")
}

function focusWorkspaceDispatch(ws, usingLua) {
  if (!isWorkspaceKey(ws) && ws !== "e+1" && ws !== "e-1") return ""
  if (usingLua) return 'hl.dsp.focus({ workspace = "' + luaQuote(ws) + '" })'
  return "workspace " + ws
}

function focusWindowDispatch(addr, usingLua) {
  var canon = canonicalAddress(addr)
  if (!canon) return ""
  if (usingLua) return 'hl.dsp.focus({ window = "address:' + canon + '" })'
  return "focuswindow address:" + canon
}

var HIDE_SPECIAL = "omacorners-hide"

function moveWindowSilentDispatch(ws, addr, usingLua) {
  var canon = canonicalAddress(addr)
  if (!canon) return ""
  var dest = String(ws || "")
  if (!/^(special:[A-Za-z0-9_-]+|[1-9][0-9]{0,2})$/.test(dest)) return ""
  if (usingLua) {
    if (/^[1-9][0-9]{0,2}$/.test(dest))
      return 'hl.dsp.window.move({ workspace = ' + dest + ', follow = false, window = "address:' + canon + '" })'
    return 'hl.dsp.window.move({ workspace = "' + luaQuote(dest) + '", follow = false, window = "address:' + canon + '" })'
  }
  return "movetoworkspacesilent " + dest + ",address:" + canon
}

function moveWindowPixelExactDispatch(x, y, addr, usingLua) {
  var canon = canonicalAddress(addr)
  if (!canon) return ""
  x = Math.round(Number(x))
  y = Math.round(Number(y))
  if (!isFinite(x) || !isFinite(y)) return ""
  if (usingLua)
    return 'hl.dsp.window.move({ x = ' + x + ', y = ' + y + ', relative = false, window = "address:' + canon + '" })'
  return "movewindowpixel exact " + x + " " + y + ",address:" + canon
}

function resizeWindowPixelExactDispatch(w, h, addr, usingLua) {
  var canon = canonicalAddress(addr)
  if (!canon) return ""
  w = Math.round(Number(w))
  h = Math.round(Number(h))
  if (!isFinite(w) || !isFinite(h) || w < 1 || h < 1) return ""
  if (usingLua)
    return 'hl.dsp.window.resize({ x = ' + w + ', y = ' + h + ', relative = false, window = "address:' + canon + '" })'
  return "resizewindowpixel exact " + w + " " + h + ",address:" + canon
}

function xyPair(value) {
  if (!value) return null
  var a
  var b
  if (Array.isArray(value) && value.length >= 2) {
    a = Number(value[0])
    b = Number(value[1])
  } else if (typeof value === "object") {
    a = Number(value.x != null ? value.x : value[0])
    b = Number(value.y != null ? value.y : value[1])
  } else {
    return null
  }
  if (!isFinite(a) || !isFinite(b)) return null
  return [Math.round(a), Math.round(b)]
}

function classicToLua(classic) {
  var s = String(classic || "")
  if (s === "togglespecialworkspace omacorners")
    return 'hl.dsp.workspace.toggle_special("omacorners")'
  if (s === "workspace e+1") return focusWorkspaceDispatch("e+1", true)
  if (s === "workspace e-1") return focusWorkspaceDispatch("e-1", true)
  return s
}

function historyRank(client) {
  var n = Number(client && client.focusHistoryID)
  if (!isFinite(n) || n < 0) return 9999
  return n
}

function pickClient(local, other, activeAddress) {
  var active = canonicalAddress(activeAddress)
  var i
  if (active) {
    for (i = 0; i < local.length; i++) {
      if (!sameAddress(local[i].address, active)) return local[i]
    }
    if (other.length) return other[0]
    return local.length ? local[0] : null
  }
  if (local.length && other.length && local[0].history === 0) return other[0]
  if (local.length) return local[0]
  return other.length ? other[0] : null
}

function findClient(rawJson, desktopId, workspaceKey, activeAddress) {
  var desk = normalizeDesktopId(desktopId)
  if (!desk) return null
  var list
  try { list = JSON.parse(String(rawJson || "")) } catch (e) { return null }
  if (!Array.isArray(list)) return null
  var n = list.length
  if (typeof n !== "number" || n < 0) return null
  if (n > 256) n = 256
  var local = []
  var other = []
  var wantWs = workspaceKey ? String(workspaceKey) : ""
  for (var i = 0; i < n; i++) {
    var client = list[i]
    if (!client || typeof client !== "object") continue
    if (client.mapped === false) continue
    if (!classMatchesDesktop(client["class"], client.initialClass, desk)) continue
    var addr = canonicalAddress(client.address)
    if (!addr) continue
    var ws = client.workspace && client.workspace.id != null ? String(client.workspace.id) : ""
    var hit = { address: addr, workspace: isWorkspaceKey(ws) ? ws : "", history: historyRank(client) }
    if (wantWs && ws === wantWs) local.push(hit)
    else other.push(hit)
  }
  local.sort(function(a, b) { return a.history - b.history })
  other.sort(function(a, b) { return a.history - b.history })
  return pickClient(local, other, activeAddress)
}

function findClientAddress(rawJson, desktopId, workspaceKey, activeAddress) {
  var hit = findClient(rawJson, desktopId, workspaceKey, activeAddress)
  return hit ? hit.address : ""
}

function run(id, hyprDispatch, execArgv) {
  id = normalize(id)
  if (id === "none") return false
  if (isAppAction(id)) {
    if (typeof execArgv !== "function") return false
    var desktop = desktopIdOf(id)
    if (!desktop) return false
    execArgv(["uwsm-app", "--", "gtk-launch", desktop + ".desktop"])
    return true
  }
  if (isAgentAction(id)) {
    if (typeof execArgv !== "function") return false
    var argv = agentArgv(agentNameOf(id))
    if (!argv) return false
    execArgv(argv)
    return true
  }
  var meta = META[id]
  if (!meta) return false
  if (meta.kind === "hypr") {
    if (typeof hyprDispatch !== "function") return false
    hyprDispatch(String(meta.dispatch))
    return true
  }
  if (meta.kind === "argv") {
    if (typeof execArgv !== "function" || !meta.argv) return false
    execArgv(meta.argv.slice())
    return true
  }
  return false
}
