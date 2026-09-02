.pragma library

// Hit-testing for screen-corner dwell. Coordinates are compositor layout
// pixels, the same space as `hyprctl cursorpos` and Quickshell.screens.

function clamp(value, min, max) {
  var n = Number(value)
  if (!isFinite(n)) return min
  return Math.max(min, Math.min(max, n))
}

function clampDelayMs(value) {
  return Math.round(clamp(value, 0, 2000))
}

function clampThresholdPx(value) {
  return Math.round(clamp(value, 2, 48))
}

function hitOnScreen(sx, sy, sw, sh, x, y, threshold) {
  var t = clampThresholdPx(threshold)
  if (sw <= 0 || sh <= 0) return ""
  if (x < sx || y < sy || x >= sx + sw || y >= sy + sh) return ""
  var left = x - sx <= t
  var right = (sx + sw) - x <= t
  var top = y - sy <= t
  var bottom = (sy + sh) - y <= t
  if (top && left) return "tl"
  if (top && right) return "tr"
  if (bottom && left) return "bl"
  if (bottom && right) return "br"
  return ""
}

function hit(screens, x, y, threshold) {
  if (!screens) return null
  var n = screens.length
  if (typeof n !== "number") n = 0
  for (var i = 0; i < n; i++) {
    var s = screens[i]
    if (!s) continue
    var sx = Number(s.x) || 0
    var sy = Number(s.y) || 0
    var sw = Number(s.width) || 0
    var sh = Number(s.height) || 0
    var corner = hitOnScreen(sx, sy, sw, sh, x, y, threshold)
    if (corner)
      return { corner: corner, name: String(s.name || ""), x: sx, y: sy, width: sw, height: sh }
  }
  return null
}

function screensFromModel(model) {
  var out = []
  if (!model) return out
  var n = 0
  try { n = model.length } catch (e) { n = 0 }
  if (typeof n !== "number" || n < 0) n = 0
  // Hard cap: a pathological screen list must not grow the dwell loop.
  if (n > 16) n = 16
  for (var i = 0; i < n; i++) {
    var s = model[i]
    if (!s) continue
    out.push({
      name: String(s.name || ""),
      x: Number(s.x) || 0,
      y: Number(s.y) || 0,
      width: Number(s.width) || 0,
      height: Number(s.height) || 0
    })
  }
  return out
}

function screensFromHyprland(model) {
  // hyprctl monitors report mode pixels; cursorpos is layout pixels (mode / scale).
  var out = []
  if (!model) return out
  var n = 0
  try { n = model.length } catch (e) { n = 0 }
  if (typeof n !== "number" || n < 0) n = 0
  if (n > 16) n = 16
  for (var i = 0; i < n; i++) {
    var s = model[i]
    if (!s) continue
    var scale = Number(s.scale)
    if (!isFinite(scale) || scale <= 0) scale = 1
    var sw = Number(s.width) || 0
    var sh = Number(s.height) || 0
    out.push({
      name: String(s.name || ""),
      x: Number(s.x) || 0,
      y: Number(s.y) || 0,
      width: Math.round(sw / scale),
      height: Math.round(sh / scale)
    })
  }
  return out
}
