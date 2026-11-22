import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Sun.js" as Sun
import "Moon.js" as Moon
import "Weather.js" as Weather
import "Themes.js" as Themes

// Draws the wall on the background layer and owns everything the bar panel
// shows and changes: the settings file, the lights, the weather.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null
  property var manifest: null

  readonly property string configPath: Quickshell.env("HOME") + "/.config/shades/config.json"

  // -1 follows the clock; otherwise local hours (0..24) to preview a moment of today
  property real simHour: -1
  property date now: new Date()
  // the real time, whatever is being previewed
  property date clock: new Date()
  property real swayTime: 0

  readonly property alias config: config

  // Where we are: the settings file, else the Omarchy weather location, else
  // a guess from the time zone (15 degrees of longitude an hour, mid latitude).
  readonly property var place: {
    var lat = parseFloat(config.latitude), lon = parseFloat(config.longitude)
    if (!isNaN(lat) && !isNaN(lon)) return { latitude: lat, longitude: lon, source: "config" }
    try {
      var shared = JSON.parse(systemPlace.text() || "{}")
      lat = parseFloat(shared.latitude)
      lon = parseFloat(shared.longitude)
      if (!isNaN(lat) && !isNaN(lon)) return { latitude: lat, longitude: lon, source: "omarchy" }
    } catch (e) {}
    return { latitude: 45, longitude: -new Date().getTimezoneOffset() / 4, source: "time zone" }
  }

  FileView {
    id: systemPlace
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    blockLoading: true
    printErrors: false
    onFileChanged: reload()
  }

  readonly property var sun: Sun.state(now, place.latitude, place.longitude)
  readonly property real elevation: sun.elevation
  readonly property real progress: sun.progress

  // How deep a solar eclipse is right now, 0..1. The moon's place is known to
  // a third of a degree from the centre of the Earth, which is enough to tell
  // that an eclipse is under way somewhere, not how it looks from here: when
  // one is, and our sun is up, we take part. `simEclipse` previews it.
  property real simEclipse: -1
  readonly property real eclipse: simEclipse >= 0 ? simEclipse
    : config.eclipses ? smooth(1.5, 0.3, moon.sunDistance) : 0

  readonly property var moon: Moon.state(now, place.latitude, place.longitude)

  // { temperature, sky, clouds } once Open-Meteo has answered
  property var weather: null
  readonly property string weatherText: weather ? (weather.temperature + "° " + weather.sky).trim() : ""
  // weather for a guessed place would be someone else's weather
  readonly property bool wantsWeather: config.enabled && place.source !== "time zone"
    && (config.overcast === "auto" || config.rain || (config.text && /\{(weather|temp|sky)\}/.test(config.lines.join(" "))))

  // 0 at night, 1 once the sun has cleared the horizon
  readonly property real day: smooth(-5, 3, elevation)
  // 0 while the sun is low and warm, 1 when it is high and white
  readonly property real high: smooth(4, 38, elevation)

  readonly property bool overcastNow: clouds > 0.5
  property real clouds: {
    if (config.overcast === "on") return 1
    if (config.overcast === "auto" && weather) return smooth(55, 95, weather.clouds)
    return 0
  }
  Behavior on clouds { NumberAnimation { duration: 4000; easing.type: Easing.InOutQuad } }

  function smooth(a, b, x) {
    var t = Math.max(0, Math.min(1, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
  }

  function mix3(a, b, t) {
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
  }

  function refresh() {
    clock = new Date()
    if (simHour < 0) {
      now = new Date()
      return
    }
    var d = new Date()
    d.setHours(0, 0, 0, 0)
    now = new Date(d.getTime() + simHour * 3600000)
  }

  onSimHourChanged: refresh()
  Component.onCompleted: {
    mend()
    shownTheme = config.theme
    shownCount = wantedCount
    warm()
    // a style kept from last time, with the bar gone solid since
    if (barWanted) { barProc.asked = true; syncBar() }
  }

  // The values a setting takes when it takes only a few; nothing for one
  // that can be anything of its kind.
  function choices(key) {
    switch (key) {
    case "theme": return themeIds
    case "motion": return motions
    case "bar": return barStyles
    case "window": return [""].concat(Themes.windows)
    case "overcast": return ["auto", "on", "off"]
    case "moon": return ["real", "always", "off"]
    case "layout": return ["span", "each"]
    case "blindsFollow": return ["none", "volume", "battery"]
    }
    return null
  }

  // A settings file from an older version, or one written by hand, may name
  // what is not there: such a setting goes back to its first value.
  function mend() {
    var few = ["bar", "motion", "window", "overcast", "moon", "layout", "blindsFollow"]
    for (var i = 0; i < few.length; i++)
      if (choices(few[i]).indexOf(config[few[i]]) < 0) set(few[i], choices(few[i])[0])
  }

  // Change one setting and persist it. Several in a row are written once.
  function set(key, value) {
    config[key] = value
    saveSoon.restart()
  }

  // when the settings were last written by us
  property real saved: 0

  Timer {
    id: saveSoon
    interval: 40
    onTriggered: {
      root.saved = Date.now()
      configFile.writeAdapter()
    }
  }

  // "{time}" and friends → what the wall should say right now
  function expand(line) {
    return String(line || "")
      .replace(/\{time\}/g, Qt.formatDateTime(now, "HH:mm"))
      .replace(/\{date\}/g, Qt.formatDateTime(now, "ddd d MMM"))
      .replace(/\{weather\}/g, weatherText)
      .replace(/\{temp\}/g, weather ? weather.temperature + "°" : "")
      .replace(/\{sky\}/g, weather ? weather.sky : "")
      .trim()
  }

  // what the glass says right now, blank lines dropped
  readonly property var shownLines: {
    var out = []
    for (var i = 0; i < config.lines.length; i++) {
      var line = expand(config.lines[i])
      if (line !== "") out.push(line)
    }
    return out
  }

  function status() {
    return "theme " + config.theme + ", omarchy " + systemTheme + ", place " + place.latitude.toFixed(2) + " " + place.longitude.toFixed(2)
      + " (" + place.source + ")" + ", time " + Qt.formatDateTime(now, "HH:mm")
      + ", elevation " + elevation.toFixed(1)
      + ", daylight " + (progress * 100).toFixed(0) + "%"
      + ", sunrise " + (sun.sunrise ? Qt.formatDateTime(sun.sunrise, "HH:mm") : "-")
      + ", sunset " + (sun.sunset ? Qt.formatDateTime(sun.sunset, "HH:mm") : "-")
      + ", moon " + moon.elevation.toFixed(1) + " lit " + (moon.phase * 100).toFixed(0) + "%"
      + (eclipse > 0 ? ", eclipse " + (eclipse * 100).toFixed(0) + "%" : "")
      + ", background " + (backgroundName || "-")
      + ", weather " + (weatherText || "-")
      + ", clouds " + clouds.toFixed(2)
      + ", " + (animated ? "moving" : covered ? "still (covered)" : "still")
      + (motion === "lift" ? ", lift " + (liftParked ? "at a floor" : (liftGoing ? "riding " : "stopping ") + liftSpeed.toFixed(2)) : motion === "racer" ? ", racer " + raceAt.toFixed(0) + " of " + lap + " at " + raceSpeed.toFixed(1) + (inTunnel ? " in the tunnel" : "")
        : moving ? ", " + motion : "")
      + (config.nightlight ? ", screen " + warmth + "K" : "")
      + (onBattery ? ", on battery" : "") + (hushed ? ", hushed" : "")
  }

  // --- theme ----------------------------------------------------------------

  // themes read from ~/.config/shades/themes/*.json, by id
  property var customThemes: ({})
  readonly property var themeIds: Themes.ids(customThemes)
  readonly property var theme: Themes.resolve(shownTheme !== "" ? shownTheme : config.theme, customThemes)

  // One theme gives way to another behind shut blinds: they close, the wall
  // changes in the dark, they open on the new light. Whatever differs between
  // two themes, the change looks the same. The blinds are a curtain as well:
  // when a theme of Omarchy's is asked for here they come down at once and
  // stay down while the system changes, and go up on the finished wall.
  //
  // The closing and the opening are run by each wall on its render thread
  // (see the animators there), so they do not falter while this thread is
  // busy; what is here only says when.
  property string shownTheme: ""
  property int shownCount: 1
  property bool turning: false     // from the blinds starting down until they are up again
  property bool curtained: false   // they are down, or on their way
  property string heldFor: ""      // the Omarchy theme they are kept down for
  property int picturesLoading: 0  // backgrounds still being read, over all the walls
  signal curtainDown()
  signal curtainUp()

  // something has changed that is not to change in sight
  function turn() {
    if (!config.enabled || shownTheme === "") { swap(); return }
    turning = true
    if (!curtained) {
      curtained = true
      curtainDown()
      swapSoon.restart()
    } else if (!swapSoon.running) {
      swap()
    }
  }

  // behind the blinds: the wall takes what the settings now say
  function swap() {
    shownTheme = config.theme
    shownCount = wantedCount
    if (curtained) raiseSoon.restart()
  }

  // The blinds come down, and stay down, for an Omarchy theme on its way in.
  function hold(name) {
    if (!config.enabled || name === systemTheme) return
    heldFor = name
    heldTooLong.interval = 6000
    heldTooLong.restart()
    turn()
  }

  // once they have shut
  Timer { id: swapSoon; interval: 300; onTriggered: root.swap() }

  // up again when nothing keeps them down: a theme still arriving, a
  // background still being read
  Timer {
    id: raiseSoon
    interval: 110
    onTriggered: {
      if (root.heldFor !== "" || root.picturesLoading > 0) { restart(); return }
      root.curtained = false
      root.curtainUp()
      risen.restart()
    }
  }

  Timer { id: risen; interval: 460; onTriggered: if (!root.curtained) root.turning = false }
  // the new theme is in and the dust has settled
  Timer { id: released; interval: 350; onTriggered: root.heldFor = "" }
  // a theme that never arrives does not keep the wall dark
  Timer { id: heldTooLong; interval: 6000; onTriggered: root.heldFor = "" }

  Connections {
    target: config
    // more windows or fewer come the same way
    function onWindowCountChanged() { if (root.wantedCount !== root.shownCount || root.turning) root.turn() }
    function onThemeChanged() { if (config.theme !== root.shownTheme || root.turning) root.turn() }
  }

  // The windows: how many stand in a row along the side wall, and how large
  // they are. One window is the room as it was built; more of them are each
  // narrower, so that the row is not much longer than the one was. The row
  // is centred where the one window stood and cannot begin behind the wall.
  readonly property int wantedCount: Math.max(1, Math.min(4, Math.round(config.windowCount)))
  readonly property real windowScale: Math.max(0.3, Math.min(3, config.windowSize))
  // where the first begins, how wide one is, from one to the next, how many
  readonly property vector4d panes: {
    var n = shownCount
    var wide = 1.4 * windowScale / (0.55 * n + 0.45)
    var pier = 0.28 * wide
    var row = n * wide + (n - 1) * pier
    return Qt.vector4d(Math.max(0.3, 1.7 - row / 2), wide, wide + pier, n)
  }

  function stepWindows(direction) {
    set("windowCount", (wantedCount - 1 + direction + 4) % 4 + 1)
  }

  // what a theme of the light is called
  function themeLabel(id) {
    return Themes.resolve(id, customThemes).label
  }

  // Pick a theme and set up the scene it comes with.
  function applyTheme(id) {
    if (themeIds.indexOf(id) < 0) return
    var scene = Themes.resolve(id, customThemes).scene || {}
    // a scene is the switches of the window, not any setting there is
    for (var key in scene)
      if (key !== "theme" && sceneKeys.indexOf(key) >= 0 && typeof scene[key] === typeof config[key]) config[key] = scene[key]
    set("theme", id)
  }

  // the window: the one picked, else the arch or the plain square of the theme
  readonly property string windowName: Themes.windows.indexOf(config.window) >= 0 ? config.window
    : theme.arch === true ? "arch" : "square"

  // How much of itself the background keeps out of the light: nearly all of
  // it by day, less under cloud and at night.
  readonly property real shade: (0.40 + 0.44 * Math.max(day, dusk)) * (1 - 0.10 * clouds)

  // A theme can keep some of the day through the night, as the white nights
  // of the north do: this much of it.
  readonly property real dusk: Math.max(0, Math.min(1, theme.dusk || 0))

  // Where the sun's light lies along the wall when it does not go out at
  // night: by day as anywhere; after sunset it goes back the way it came,
  // under the horizon, to be at the other end by sunrise.
  readonly property real sunPath: {
    if (!sun.sunrise || !sun.sunset) return progress
    var t = now.getTime(), rise = sun.sunrise.getTime(), set = sun.sunset.getTime()
    if (t >= rise && t <= set) return progress
    var night = 86400000 - (set - rise)
    var gone = t > set ? (t - set) / night : 1 - (rise - t) / night
    return 1 - Math.max(0, Math.min(1, gone))
  }

  // --- the bar as a pane over the wall ------------------------------------------

  // The wall is the only thing under the shell's bar, so with the bar's own
  // background off the wall can draw it: clear, or tinted.
  // The bar is the shell's; we read where it is and ask for its transparency.
  readonly property var barStyles: ["", "clear", "tint"]
  readonly property var shellBar: {
    try { return JSON.parse(shellFile.text() || "{}").bar || {} } catch (e) { return {} }
  }
  readonly property string barEdge: shellBar.position || "top"
  readonly property bool barShown: config.enabled && config.bar !== "" && shellBar.transparent === true

  function stepBar(direction) {
    var n = barStyles.length
    set("bar", barStyles[(Math.max(0, barStyles.indexOf(config.bar)) + direction + n) % n])
  }

  // x = edge, y = thickness as a share of that side of `screen`, z = style
  function barFor(width, height) {
    if (!barShown) return Qt.vector4d(0, 0, 0, 0)
    var edge = ["top", "bottom", "left", "right"].indexOf(barEdge) + 1
    var share = edge > 2 ? Style.bar.sizeVertical / Math.max(1, width) : Style.bar.sizeHorizontal / Math.max(1, height)
    return Qt.vector4d(edge, share, Math.max(0, barStyles.indexOf(config.bar) - 1), 0)
  }

  FileView {
    id: shellFile
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    blockLoading: true
    printErrors: false
    onFileChanged: reload()
  }

  // a style needs the bar see-through, and only while there is a wall under it
  readonly property bool barWanted: config.enabled && config.bar !== ""

  Process {
    id: barProc
    property bool asked: false
    // the style changed while the last one was being set
    onExited: if (asked !== root.barWanted) root.syncBar()
  }

  // back to the shell's own bar when the style is dropped
  function syncBar() {
    if (barProc.running) return
    // the shell's file may not have been read again since our last word
    if ((shellBar.transparent === true) === barWanted && barProc.asked === barWanted) return
    barProc.asked = barWanted
    barProc.command = ["omarchy", "bar", "transparent", barWanted ? "true" : "false"]
    barProc.running = true
  }

  Connections {
    target: config
    function onBarChanged() { root.syncBar() }
    // a bar that was see-through before we came is none of ours to shut
    function onEnabledChanged() { if (config.bar !== "") root.syncBar() }
  }

  function stepTheme(direction) {
    var n = themeIds.length
    applyTheme(themeIds[(themeIds.indexOf(config.theme) + direction + n) % n])
  }

  readonly property var palette: theme.palette

  readonly property color shadowNight: palette.shadowNight
  readonly property color shadowDawn: palette.shadowDawn
  readonly property color shadowDay: palette.shadowDay
  readonly property color shadowOvercast: palette.shadowOvercast

  readonly property color litHorizon: palette.litHorizon
  readonly property color litLow: palette.litLow
  readonly property color litHigh: palette.litHigh
  readonly property color litOvercast: palette.litOvercast
  readonly property color litMoon: palette.litMoon

  readonly property color shadowColor: {
    var sunny = mix3(shadowDawn, shadowDay, high)
    var c = mix3(sunny, shadowOvercast, clouds * 0.85)
    return mix3(shadowNight, c, day)
  }

  // the wall in full sun
  readonly property color litColor: {
    var warm = mix3(litHorizon, litLow, smooth(0, 11, elevation))
    var sunny = mix3(warm, litHigh, high)
    return mix3(sunny, litOvercast, clouds * 0.9)
  }

  // --- lights -----------------------------------------------------------------

  // Colours are added up in linear light; `scale` folds in a strength.
  function linear(c, scale) {
    return Qt.vector4d(Math.pow(c.r, 2.2) * scale, Math.pow(c.g, 2.2) * scale, Math.pow(c.b, 2.2) * scale, 0)
  }

  readonly property vector4d ambient: linear(shadowColor, 1)

  // Part of that ambient is daylight the window spreads through the room,
  // bluer than the wall under a clear sky; w is its share.
  readonly property vector4d sky: {
    var blue = day * (1 - clouds)
    return Qt.vector4d(ambient.x * (1 - 0.14 * blue), ambient.y * (1 - 0.03 * blue), ambient.z * (1 + 0.16 * blue), 0.45)
  }

  // The strength and the colour picked for the light, laid over what the
  // theme gives: what each of red, green and blue is multiplied by. A colour
  // keeps a little of the others, or it would leave the picture nothing.
  readonly property vector3d lightGain: {
    var k = Math.max(0, Math.min(6, config.brightness))
    if (!tinted) return Qt.vector3d(k, k, k)
    var c = config.tint === "accent" ? Commons.Color.accent : Qt.color(config.tint)
    var r = Math.pow(c.r, 2.2), g = Math.pow(c.g, 2.2), b = Math.pow(c.b, 2.2)
    var top = Math.max(r, g, b, 0.001)
    return Qt.vector3d(k * (0.12 + 0.88 * r / top), k * (0.12 + 0.88 * g / top), k * (0.12 + 0.88 * b / top))
  }

  // a colour that is none, or is not one, leaves the light as the theme has it
  readonly property bool tinted: config.tint === "accent" || /^#[0-9a-f]{6}$/i.test(config.tint)

  function gained(colour) {
    return Qt.vector4d(colour.x * lightGain.x, colour.y * lightGain.y, colour.z * lightGain.z, colour.w)
  }

  // A setting dragged in the panel is followed at once, not at the pace the
  // sky changes at.
  function tune(key, value) {
    tuning.restart()
    set(key, value)
  }

  Timer { id: tuning; interval: 700 }
  readonly property bool tuned: tuning.running

  // Each light: where it is along its arc, the slant of its shadows, and the
  // linear colour it adds to the wall where nothing is in its way.
  readonly property var lights: {
    // how far past the half degree of the sun's disc the edges are smeared;
    // black and white film wants its light hard
    var soft = (1 + 3 * clouds) * (theme.mono === true ? 0.6 : 1) * Math.max(0.1, Math.min(4, config.softness))
    // what is left of the sun in a white night comes from the whole sky
    var softSun = soft * (1 + 2.5 * dusk * (1 - day))

    // the sun takes the wall from its shadow colour up to its lit colour
    var direct = Math.max(smooth(-1.5, 5, elevation), dusk) * (1 - 0.45 * clouds) * (1 - 0.7 * eclipse)
    var lit = linear(litColor, 1)
    var sunCol = Qt.vector4d(Math.max(0, lit.x - ambient.x) * direct,
                             Math.max(0, lit.y - ambient.y) * direct,
                             Math.max(0, lit.z - ambient.z) * direct, 0)

    // "always" hangs a full moon in one place every night
    var real = config.moon !== "always"
    var moonElev = real ? moon.elevation : 35
    var moonAmt = config.moon === "off" ? 0
      : 0.30 * config.moonlight * (real ? (0.25 + 0.75 * moon.phase) * smooth(-1, 6, moonElev) : 1)
        * (1 - day) * (1 - 0.3 * clouds)

    var none = Qt.vector4d(0, 0, 0, 0)
    var sunLight = { progress: dusk > 0 ? sunPath : progress, slant: slant(elevation), soft: softSun, color: gained(sunCol) }
    var moonLight = { progress: real ? moon.progress : 0.5, slant: slant(moonElev), soft: soft,
                      color: gained(linear(litMoon, moonAmt / 0.55)) }

    var dark = { progress: 0.5, slant: 0, soft: 1, color: none }
    var parts = theme.split || []
    if (parts.length === 0) return [sunLight, moonLight, dark, dark]

    // A theme can split the light into colours. It is the light on the wall
    // that is split, the sun by day and the moon by night, so the patch goes
    // where any other theme's does; the other of the two is below the
    // horizon or lost in the day and stays whole.
    var byDay = elevation > -1.5
    var whole = byDay ? sunLight : moonLight
    return [piece(whole, parts[0]), byDay ? moonLight : sunLight,
            parts[1] ? piece(whole, parts[1]) : dark, parts[2] ? piece(whole, parts[2]) : dark]
  }

  // One of the colours `light` is split into, set a little apart from it.
  function piece(light, part) {
    var c = Qt.color(part.color), gain = part.gain === undefined ? 1 : part.gain
    return { progress: light.progress + (part.shift || 0), slant: light.slant + (part.lift || 0), soft: light.soft,
             color: Qt.vector4d(light.color.x * c.r * gain, light.color.y * c.g * gain, light.color.z * c.b * gain, light.color.w) }
  }

  // --- the room on the move -----------------------------------------------------

  // The room need not stand still. What moves is never the sun but the room
  // under it: a lift between its floors, a train with its masts and tunnels,
  // a ship rolling, a racing car through its corners.
  readonly property var motions: ["", "lift", "train", "ship", "racer"]
  readonly property string motion: motions.indexOf(config.motion) > 0 ? config.motion : ""
  readonly property bool moving: motion !== ""

  function stepMotion(direction) {
    var n = motions.length
    set("motion", motions[(Math.max(0, motions.indexOf(config.motion)) + direction + n) % n])
  }

  // --- the room as a lift -------------------------------------------------------

  // The lift rides without end. The sun stays where it is, so what moves is
  // what is near: the floors of the shaft crossing the window one after
  // another. A click on the wall stops it at the next floor; another sends
  // it on, the other way.
  property real liftAt: 0          // floors ridden
  property real liftSpeed: 0       // floors a second, up or down
  property bool liftGoing: true
  property int liftWay: 1
  property real liftStop: 0        // the floor it is braking for
  readonly property real liftCruise: 0.18
  readonly property real liftPull: 0.12 // how fast it gathers and loses speed
  readonly property bool liftParked: motion === "lift" && !liftGoing && liftSpeed === 0
  // how far past the last floor: all the shader needs, the floors being alike
  readonly property real lift: motion === "lift" ? liftAt - Math.floor(liftAt) : 0

  onMotionChanged: { liftAt = 0; liftSpeed = 0; liftWay = 1; liftGoing = true; raceAt = 0; raceSpeed = 0; raceGlare = 0 }

  function holdLift() {
    if (motion !== "lift") return
    if (liftGoing) {
      liftGoing = false
      // the first floor it can still brake for
      var brake = liftSpeed * liftSpeed / (2 * liftPull)
      liftStop = liftWay > 0 ? Math.ceil(liftAt + brake) : Math.floor(liftAt - brake)
    } else {
      if (liftSpeed === 0) liftWay = -liftWay
      liftGoing = true
    }
  }

  // the lift `dt` seconds on
  function rideOn(dt) {
    if (motion !== "lift" || dt <= 0) return
    var v = Math.abs(liftSpeed)
    if (liftGoing) {
      v = Math.min(liftCruise, v + liftPull * dt)
    } else {
      var left = (liftStop - liftAt) * liftWay
      if (left <= 0.001) { liftAt = liftStop; liftSpeed = 0; return }
      // no faster than it can still brake from, and never standing short of the floor
      v = Math.min(Math.max(0.02, Math.min(v + liftPull * dt, liftCruise, Math.sqrt(2 * liftPull * left))), left / dt)
    }
    liftSpeed = v * liftWay
    liftAt += liftSpeed * dt
  }

  // --- the room as a racing car ---------------------------------------------------

  // The car goes round a track, lap after lap. The sun stays where it is, so
  // every corner turns the car under it: the light comes in at another angle
  // and goes on doing so down the straight that follows, until the next
  // corner turns it again. The corners are long, taken at speed, and over a
  // lap they undo one another, so that the lap ends facing the way it began.
  // On the first straight there is a tunnel with lamps along its roof; the
  // shader knows the rest of what stands by the track, the fence, the stands
  // and the bridges.
  readonly property real lap: 300
  // where the middle of each corner is, how long it is, and how far it turns
  // the car in all (radians; to the left is less than none)
  readonly property var corners: [
    { at: 70, length: 50, turn: 0.35 }, { at: 140, length: 60, turn: -0.55 },
    { at: 215, length: 46, turn: 0.40 }, { at: 270, length: 40, turn: -0.20 }
  ]
  // the bend of the tightest of them, to measure the others by
  readonly property real tightest: {
    var most = 0
    for (var i = 0; i < corners.length; i++) most = Math.max(most, 2 * Math.abs(corners[i].turn) / corners[i].length)
    return most
  }
  readonly property real tunnelFrom: 4
  readonly property real tunnelTo: 34
  readonly property real lampEvery: 3      // from one lamp of the tunnel to the next
  readonly property real topSpeed: 12      // along the straight, a second
  property real raceAt: 0                  // how far round the lap
  property real raceSpeed: 0
  property real raceGlare: 0               // 1 as the car comes out of the tunnel, then fading
  // how far the car has turned from the way it set out, and how hard it is
  // pressed sideways just now (-1..1): the bend times the square of the speed
  readonly property real raceHeading: headingAt(raceAt)
  readonly property real raceLean: Math.max(-1, Math.min(1, bendAt(raceAt) / tightest * Math.pow(raceSpeed / topSpeed, 2) * 2.2))
  readonly property bool inTunnel: motion === "racer" && raceAt > tunnelFrom && raceAt < tunnelTo

  // A corner eases in and out: how far through its turn it is, 0..1, at the
  // share u of its length.
  function eased(u) {
    u = Math.max(0, Math.min(1, u))
    return u - Math.sin(2 * Math.PI * u) / (2 * Math.PI)
  }

  // which way the track points at x, in radians from the start
  function headingAt(x) {
    var sum = 0
    for (var i = 0; i < corners.length; i++)
      sum += corners[i].turn * eased((x - corners[i].at) / corners[i].length + 0.5)
    return sum
  }

  // how sharply it is turning there, radians a unit of track
  function bendAt(x) {
    var sum = 0
    for (var i = 0; i < corners.length; i++) {
      var u = (x - corners[i].at) / corners[i].length + 0.5
      if (u > 0 && u < 1) sum += corners[i].turn / corners[i].length * (1 - Math.cos(2 * Math.PI * u))
    }
    return sum
  }

  // the car `dt` seconds on
  function raceOn(dt) {
    if (motion !== "racer" || dt <= 0) return
    // it lifts for the tightest of the stretch ahead, and no more than a long
    // corner asks
    var ahead = 0
    for (var d = 0; d <= 16; d += 2) ahead = Math.max(ahead, Math.abs(bendAt((raceAt + d) % lap)))
    var want = topSpeed * (1 - 0.45 * ahead / tightest)
    // and sheds speed faster than it gathers it
    var rate = (want > raceSpeed ? 3.5 : 7) * dt
    raceSpeed += Math.max(-rate, Math.min(rate, want - raceSpeed))
    var inside = inTunnel
    raceAt = (raceAt + raceSpeed * dt) % lap
    if (inside && !inTunnel) raceGlare = 1
    raceGlare = raceGlare < 0.01 ? 0 : raceGlare * Math.exp(-dt / 0.45)
  }

  // --- lights that pass by ------------------------------------------------------

  // At night a car goes down the street now and then, and the light of its
  // headlamps crosses the wall. It is one more light, far off, with its own
  // way across the wall: `passAt` runs 0..1 over the passing of a car.
  property bool passing: false
  property real passAt: 0
  property real passFor: 4      // seconds a car takes
  property int passWay: 1

  readonly property bool carsFit: config.enabled && !moving

  function passBy() {
    if (passing || !carsFit) return
    passWay = Math.random() < 0.5 ? 1 : -1
    passFor = 3.2 + 2 * Math.random()
    passAt = 0
    passing = true
  }

  // the car `dt` seconds on
  function passOn(dt) {
    if (!passing) return
    passAt += dt / passFor
    if (passAt >= 1) { passing = false; passAt = 0 }
  }

  Timer {
    running: root.carsFit && config.headlights && root.day < 0.3 && !(config.pauseWhenCovered && root.covered)
    repeat: true
    interval: 60000
    onTriggered: {
      interval = 40000 + 140000 * Math.random()
      root.passBy()
    }
  }

  // The light passing just now, in the shape of the other lights; it comes in
  // at one end of the wall, crosses it and is gone at the other.
  readonly property var passer: {
    var none = { progress: 0.5, slant: 0, soft: 1, color: Qt.vector4d(0, 0, 0, 0) }
    // the lamps of the racing car's tunnel, each a flash that crosses the wall
    if (motion === "racer") {
      if (!inTunnel) return none
      var by = (raceAt - tunnelFrom) / lampEvery % 1
      // they hang from the roof: their light comes down as steeply as a high sun's
      return { progress: 1.15 - 1.4 * by, slant: 0.24, soft: 2.2,
               color: linear(Qt.color("#ffb24a"), 1.15 * smooth(0, 0.2, by) * (1 - smooth(0.8, 1, by))) }
    }
    var dark = (1 - day) * (1 - 0.3 * clouds)
    if (dark <= 0) return none
    if (!passing) return none
    // a car is lower than the window: its light climbs the wall as it comes nearer
    return { progress: passWay > 0 ? -0.2 + 1.3 * passAt : 1.1 - 1.3 * passAt, slant: -0.13 + 0.07 * passAt, soft: 1.6,
             color: linear(Qt.color("#ffe7c2"), 0.5 * dark * smooth(0, 0.25, passAt) * (1 - smooth(0.6, 1, passAt))) }
  }

  // slat shadows tilt with the height of the light
  function slant(elevation) {
    return 0.19 + 0.004 * Math.max(0, elevation)
  }

  // --- the wall across monitors -------------------------------------------------

  // "span" treats all monitors as openings onto one wall, laid out as the
  // compositor has them; "each" gives every monitor a wall of its own.
  readonly property var referenceScreen: {
    var screens = Quickshell.screens
    var best = null
    for (var i = 0; i < screens.length; i++) {
      if (screens[i].name === config.reference) return screens[i]
      if (!best || screens[i].width * screens[i].height > best.width * best.height) best = screens[i]
    }
    return best
  }

  // Where `screen` sits on its wall, in units of the reference monitor height
  // with the origin at that monitor's centre.
  function frameFor(screen) {
    var screens = config.layout === "each" ? [screen] : Quickshell.screens
    var ref = config.layout === "each" || !referenceScreen ? screen : referenceScreen
    var unit = Math.max(1, ref.height)
    var cx = ref.x + ref.width / 2
    var cy = ref.y + ref.height / 2
    var left = screen.x, right = screen.x + screen.width
    for (var i = 0; i < screens.length; i++) {
      left = Math.min(left, screens[i].x)
      right = Math.max(right, screens[i].x + screens[i].width)
    }
    return {
      rect: Qt.vector4d((screen.x - cx) / unit, (cy - screen.y) / unit, screen.width / unit, screen.height / unit),
      // the window is 0.64 high about a point a little above the middle of the wall
      room: Qt.vector4d((left - cx) / unit, (right - cx) / unit, 0.20 - 0.32 * windowScale, 0.20 + 0.32 * windowScale),
      casters: casters(cx, cy, unit)
    }
  }

  // --- shadows that tell you something ----------------------------------------

  // The blinds hang in every window; they can stand as open as the volume is
  // up or the battery is full.
  PwObjectTracker { objects: config.blindsFollow === "volume" && Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : [] }

  readonly property real blindsLevel: {
    if (config.blindsFollow === "volume") {
      var sink = Pipewire.defaultAudioSink
      if (!sink || !sink.audio) return 1
      return sink.audio.muted ? 0 : Math.max(0, Math.min(1, sink.audio.volume))
    }
    if (config.blindsFollow === "battery") {
      var battery = UPower.displayDevice
      return battery && battery.isPresent ? Math.max(0, Math.min(1, battery.percentage)) : 1
    }
    return -1
  }
  // 0.64 is how the blinds hang when they follow nothing; with notifications
  // silenced they are down and shut
  readonly property real slatOpen: hushed ? 0.10 : blindsLevel < 0 ? 0.64 : 0.10 + 0.78 * blindsLevel

  // --- what the rest of the system is doing ------------------------------------

  // Do not disturb, as the shell's notifications keep it.
  readonly property bool hushed: {
    if (!config.quiet) return false
    try { return JSON.parse(notifyFile.text() || "{}").dnd === true } catch (e) { return false }
  }

  FileView {
    id: notifyFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/notifications.json"
    watchChanges: true
    blockLoading: true
    printErrors: false
    onFileChanged: reload()
  }

  // Omarchy does not say when its theme or background changes, but each
  // leaves a file behind: the folder is watched. Without inotify-tools the
  // theme is still looked at once a minute.
  Process {
    id: watchProc
    running: config.enabled
    command: ["sh", "-c", 'd="$HOME/.local/state/omarchy/current"; [ -d "$d" ] || exit 0; '
      // a shell that is killed leaves its children behind: someone looks in
      // now and then and ends the watch with it. The watch itself takes this
      // process over, so that stopping it here stops the watch and no other.
      + '( while kill -0 $PPID 2>/dev/null && kill -0 $$ 2>/dev/null; do sleep 10; done; kill $$ 2>/dev/null ) >/dev/null 2>&1 & '
      + 'exec inotifywait -m -q -e create,moved_to,close_write --format %w%f "$d"']
    stdout: SplitParser {
      onRead: function(line) { systemSettle.restart() }
    }
  }

  Timer { id: systemSettle; interval: 120; onTriggered: root.refreshSystem() }

  // The screen warms as the real sun goes down and cools as it comes up, in
  // the two temperatures Omarchy's own night light switches between.
  readonly property real sunNow: Sun.state(clock, place.latitude, place.longitude).elevation
  readonly property int warmth: 4000 + 100 * Math.round(25 * smooth(-6, 6, sunNow))
  readonly property bool warming: config.enabled && config.nightlight && place.source !== "time zone"
  // switched off, the screen is handed back cool
  readonly property int screenWanted: warming ? warmth : 6500
  property bool screenOurs: false
  onScreenWantedChanged: warm()
  onWarmingChanged: warm()

  function warm() {
    if (warming) screenOurs = true
    if (!screenOurs || warmProc.running) return
    warmProc.sent = screenWanted
    // a hyprsunset just started sets its own temperature last, so ours is sent until it holds
    warmProc.command = ["sh", "-c", 'pgrep -x hyprsunset >/dev/null || { setsid uwsm-app -- hyprsunset >/dev/null 2>&1 & sleep 1; }; '
      + 'for i in 1 2 3 4 5 6 7 8 9 10; do hyprctl hyprsunset temperature ' + screenWanted + ' >/dev/null 2>&1; sleep 0.2; '
      + 'hyprctl hyprsunset temperature 2>/dev/null | grep -q "^' + screenWanted + '" && break; done; omarchy-shell -q nightlight refresh']
    warmProc.running = true
  }

  Process {
    id: warmProc
    property int sent: 0
    // the sun moved on while the last one was being set
    onExited: if (sent !== root.screenWanted) root.warm()
  }

  // On battery the wall moves at half the pace at most, and holds still once
  // the battery runs low.
  readonly property bool onBattery: config.saveBattery && UPower.onBattery
  readonly property bool batteryLow: onBattery && UPower.displayDevice && UPower.displayDevice.isPresent
    && UPower.displayDevice.percentage < 0.2
  // a room on the move needs more frames to move smoothly, and so does a light crossing the wall
  readonly property int fps: Math.max(1, onBattery ? Math.min(config.fps, 10) : motion === "racer" ? Math.max(config.fps, 60) : moving || passing ? Math.max(config.fps, 30) : config.fps)

  // --- the desktop's own windows ----------------------------------------------

  // Windows on the workspaces now showing, as the compositor reports them.
  readonly property var desktopWindows: {
    var showing = {}
    var monitors = Hyprland.monitors.values
    for (var i = 0; i < monitors.length; i++)
      if (monitors[i].activeWorkspace) showing[monitors[i].activeWorkspace.id] = true
    var out = []
    var toplevels = Hyprland.toplevels.values
    for (var j = 0; j < toplevels.length; j++) {
      var w = toplevels[j].lastIpcObject
      if (!w || !w.at || !w.size || !w.workspace || !showing[w.workspace.id] || w.hidden || w.mapped === false) continue
      out.push({ x: w.at[0], y: w.at[1], width: w.size[0], height: w.size[1] })
    }
    // the shader takes eight; the biggest throw the shadows that matter
    out.sort(function(a, b) { return b.width * b.height - a.width * a.height })
    return out.slice(0, 8)
  }

  // Those windows as rectangles on the wall (left, bottom, right, top), padded to eight.
  function casters(cx, cy, unit) {
    var out = []
    var on = config.windowShadows
    for (var i = 0; i < 8; i++) {
      var w = on ? desktopWindows[i] : null
      out.push(w ? Qt.vector4d((w.x - cx) / unit, (cy - w.y - w.height) / unit, (w.x + w.width - cx) / unit, (cy - w.y) / unit)
                 : Qt.vector4d(0, 0, 0, 0))
    }
    return out
  }

  // The compositor tells us when windows come, go and move between
  // workspaces, not when one is dragged or resized, so it is asked again
  // every couple of seconds as well, while there is light for them to
  // stand in.
  readonly property bool casting: config.enabled && config.windowShadows && lit

  Connections {
    target: Hyprland
    enabled: root.casting
    function onRawEvent(event) {
      if (/window|workspace|fullscreen|floating|monitor/.test(event.name)) windowsSettle.restart()
    }
  }

  Timer { id: windowsSettle; interval: 80; onTriggered: Hyprland.refreshToplevels() }

  Timer {
    interval: 2000
    running: root.casting
    repeat: true
    triggeredOnStart: true
    onTriggered: Hyprland.refreshToplevels()
  }

  // The patch slides from the right end of the wall to the left and widens
  // over the arc of the light, whatever the width of the wall.
  function geometry(light, room) {
    var reach = 0.26 + 0.38 * light.progress
    var k = (0.02 + reach * (room.y - room.x)) / 1.7
    // on a wall wider than one 16:9 monitor the light travels further, so the
    // slant is eased to keep the patch from sinking below the screens
    var single = (0.02 + reach * 16 / 9) / 1.7
    return Qt.vector4d(k, light.slant * Math.min(1, single / k), light.soft, 0)
  }

  // --- settings, weather, control -------------------------------------------

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    blockLoading: true
    printErrors: false
    // our own writing shows as a change too, and read back half written it
    // would undo the settings made since
    onFileChanged: if (!saveSoon.running && Date.now() - root.saved > 400) reload()
    onLoaded: root.mend()

    JsonAdapter {
      id: config
      property bool enabled: true      // show the wall, or leave the stock background
      // where the sun is worked out for; left empty, the place set for the
      // Omarchy weather widget is used
      property var latitude: null
      property var longitude: null
      property real brightness: 1      // strength of the sun's and the moon's light; 1 = as the theme has it
      property real softness: 1        // how soft the edges of the shadows are; 1 = as the sky makes them
      property string tint: ""         // its colour: "#rrggbb", or "accent" for the Omarchy accent; empty = the theme's
      property string overcast: "auto" // "auto" | "on" | "off"
      property string window: ""       // square | arch; empty = the theme's
      property real windowSize: 1      // how large the windows are; 1 = as the room was built, 3 = glass from floor to ceiling
      property int windowCount: 1      // how many stand in a row along the side wall, 1..4
      property bool tree: false        // a tree outside the window
      property string theme: "plaster" // see Themes.js
      property string bar: ""          // the shell's bar over the wall: clear | tint; empty = the shell's own solid bar
      property bool dust: true         // motes floating in the beam
      property bool passingClouds: true // the sun dims as clouds cross it
      property bool windowShadows: false // the desktop's windows cast shadows on the wall
      property real windowHeight: 0.05  // how far they float in front of it, in wall heights
      property string blindsFollow: "none" // "none" | "volume" | "battery": how open the blinds stand
      property bool headlights: true    // at night the lights of a passing car cross the wall
      property bool trail: false        // the wall keeps a trace of where the sun has been today
      property bool eclipses: true      // real solar eclipses dim the sun and turn tree light into crescents
      property bool rain: true         // drops on the glass when the weather says rain
      property bool pauseWhenCovered: true // hold still while windows cover the wall
      property bool saveBattery: true  // move slower on battery, hold still when it runs low
      property bool nightlight: false  // warm the screen as the real sun sets
      property bool quiet: true        // the blinds close while notifications are silenced
      property string motion: ""       // the room travels: lift | train | ship | racer
      property bool perTheme: true     // every Omarchy theme keeps a scene of its own
      property string sceneOf: ""      // the Omarchy theme the scene now set up belongs to
      property var scenes: ({})        // the scenes kept, by Omarchy theme
      property bool text: false        // lettering on the glass: the lines below
      property bool textLight: false   // letters of light instead of letter shadows
      // what the lettering says; {time} {date} {weather} {temp} {sky} are filled in
      property var lines: ["OMARCHY", "{time}", "{weather}"]
      property string font: ""         // empty = the shell font
      property int fps: 20             // frames a second of whatever moves; a room on the move takes more
      property real grain: 0.035       // mottling of the wall under the picture, 0 = none
      property real glass: 1           // unevenness of the window glass, 0 = perfect
      property string moon: "real"       // "real" | "always" | "off"
      property real moonlight: 0.22      // brightness of a full moon
      property string layout: "span"     // "span" | "each"
      property string reference: ""      // monitor that sets the scale; empty = the largest
    }
  }

  readonly property string weatherUrl: Weather.url(place.latitude, place.longitude)
  // somewhere else has other weather
  onWeatherUrlChanged: if (wantsWeather) weatherRetry.restart()

  Process {
    id: weatherProc
    command: ["curl", "-fsS", "--max-time", "8", root.weatherUrl]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Weather.parse(String(text || ""))
        if (parsed) root.weather = parsed
        // no answer, as when the network is not up yet: ask again soon
        else if (root.wantsWeather) { weatherRetry.interval = 60000; weatherRetry.restart() }
      }
    }
  }

  Timer {
    id: weatherRetry
    interval: 1000
    onTriggered: {
      interval = 1000
      if (root.wantsWeather && !weatherProc.running) weatherProc.running = true
    }
  }

  Timer {
    interval: 15 * 60000
    running: root.wantsWeather
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!weatherProc.running) weatherProc.running = true
  }

  IpcHandler {
    target: "shades"

    // preview a time of day, e.g. `omarchy-shell shades time 6.5`
    function time(hour: real): void { root.simHour = hour }
    // the hour being previewed, negative when the real time is followed
    function preview(): real { return root.simHour }
    // change a setting as the panel would, e.g. `set dust false`
    function set(key: string, value: string): string {
      if (config[key] === undefined) return "no such setting"
      var wanted = value
      try { wanted = JSON.parse(value) } catch (e) {}
      var among = root.choices(key)
      if (among && among.indexOf(wanted) < 0) return key + " is one of: " + among.map(function(c) { return c === "" ? '""' : c }).join(" ")
      if (key === "tint" && wanted !== "" && wanted !== "accent" && !/^#[0-9a-f]{6}$/i.test(wanted)) return 'tint is "#rrggbb", accent or ""'
      root.set(key, wanted)
      return key + " = " + JSON.stringify(config[key])
    }
    function follow(): void { root.simHour = -1 }
    function toggle(): void { root.set("enabled", !config.enabled) }
    function status(): string { return root.status() }
    // pick a theme by id; without one, list what there is
    function theme(id: string): string {
      if (id !== "") root.applyTheme(id)
      return root.themeIds.join(" ")
    }
    // step through the backgrounds of the Omarchy theme, or through its themes: 1 next, -1 previous
    function background(direction: int): string {
      root.stepBackground(direction < 0 ? -1 : 1)
      return root.backgroundName
    }
    // turn a switch over
    function flip(key: string): string {
      if (typeof config[key] !== "boolean") return "not a switch"
      root.set(key, !config[key])
      return key + " = " + config[key]
    }
    // what a setting is now
    function get(key: string): string {
      return config[key] === undefined ? "" : JSON.stringify(config[key])
    }
    function light(direction: int): string {
      root.stepTheme(direction < 0 ? -1 : 1)
      return config.theme
    }
    function system(direction: int): string {
      root.stepSystemTheme(direction < 0 ? -1 : 1)
      return root.pendingTheme
    }
    // a car goes by now, its headlights across the wall (at night)
    function car(): void { root.passBy() }
    // stop the lift at the next floor, or send it on again
    function hold(): string {
      if (root.motion !== "lift") return "no lift"
      root.holdLift()
      return root.liftGoing ? "riding" : "stopping"
    }
    // preview a solar eclipse of the given depth (0..1); a negative depth returns to the real sky
    function eclipse(depth: real): void { root.simEclipse = depth }
    function snapshot(path: string): void { root.snapshotRequested(path) }
  }

  signal snapshotRequested(string path)

  // with no light on the wall there is nothing to see moving
  readonly property bool lit: {
    for (var i = 0; i < lights.length; i++) {
      var c = lights[i].color
      if (c.x + c.y + c.z > 0.003) return true
    }
    return passer.color.x + passer.color.y + passer.color.z > 0.003
  }

  // Every frame of the wall makes the compositor redraw whatever lies over
  // it, blur and all, so the wall holds still while windows cover it on
  // every monitor.
  readonly property bool covered: {
    var monitors = Hyprland.monitors.values
    if (monitors.length === 0) return false
    for (var i = 0; i < monitors.length; i++) {
      var ws = monitors[i].activeWorkspace
      if (!ws || ws.toplevels.values.length === 0) return false
    }
    return true
  }

  // whether anything on the wall is moving; a still wall is not redrawn
  readonly property bool animated: {
    if (config.pauseWhenCovered && covered) return false
    if (batteryLow) return false
    // a room on the move goes on through the dark, as through a tunnel. A
    // lift standing at a floor is a room like any other.
    if (moving && !liftParked) return true
    // a light on its way across the wall
    if (passing) return true
    if (!lit) return false
    if (config.tree) return true
    if (drift > 0 || raining) return true
    if (config.dust && elevation > 0 && clouds < 0.5) return true
    return false
  }

  // broken cloud: now and then one of them crosses the sun
  readonly property real drift: {
    if (!config.passingClouds || config.overcast !== "auto" || !weather || elevation < 0) return 0
    return smooth(15, 40, weather.clouds) * (1 - smooth(70, 90, weather.clouds))
  }

  readonly property bool raining: config.rain && weather !== null && /rain|drizzle|shower|thunder/i.test(weather.sky)

  // --- the Omarchy theme and its backgrounds ----------------------------------

  // The wallpaper is Omarchy's: the background of the theme in use. Both can
  // be stepped through from the panel, with Omarchy's own commands, so the
  // rest of the system follows as if they had been picked in its menu.
  property string wallpaperPath: ""    // the picture Omarchy has as its background
  property string systemTheme: ""      // the theme in use, as a slug: "tokyo-night"
  property var systemThemes: []        // every theme installed
  property var backgrounds: []         // the pictures the theme in use comes with
  property string pendingTheme: ""     // stepped to but not applied yet

  // a path as a URL: "#" and "?" in a file name are part of the name
  function fileUrl(path) {
    return path === "" ? "" : "file://" + path.split("/").map(encodeURIComponent).join("/")
  }

  function titled(slug) {
    return String(slug || "").split("-").map(function(w) { return w.charAt(0).toUpperCase() + w.slice(1) }).join(" ")
  }

  // "2-layers-deep.jpg" reads "Layers Deep", as `omarchy theme bg current` has it
  function backgroundLabel(path) {
    return titled(String(path || "").replace(/^.*\//, "").replace(/\.[^.]+$/, "").replace(/^\d+-/, ""))
  }

  readonly property string backgroundName: backgroundLabel(wallpaperPath)
  readonly property int backgroundIndex: backgrounds.indexOf(wallpaperPath)

  // What makes up a scene: kept for every Omarchy theme and brought back with
  // it. A theme can come with one of its own, a shades.json with these keys.
  readonly property var sceneKeys: ["theme", "bar", "window", "brightness", "softness", "tint", "windowSize", "windowCount",
    "blindsFollow", "tree", "trail", "text", "textLight", "motion"]
  property var themeScene: null        // what the theme in use brought along, if anything

  function scene() {
    var out = {}
    for (var i = 0; i < sceneKeys.length; i++) out[sceneKeys[i]] = config[sceneKeys[i]]
    return out
  }

  function stage(next) {
    for (var i = 0; i < sceneKeys.length; i++) {
      var key = sceneKeys[i]
      // a scene kept from an older version may name what is no longer there
      var among = choices(key)
      if (typeof next[key] === typeof config[key] && (!among || among.indexOf(next[key]) >= 0))
        config[key] = next[key]
    }
  }

  // The Omarchy theme is not the one the scene was set up under: put that
  // scene by for it and bring out the one that goes with the new theme.
  function followTheme() {
    if (systemTheme === "" || config.sceneOf === systemTheme) return
    if (config.perTheme && config.sceneOf !== "") {
      var kept = {}
      for (var id in config.scenes) kept[id] = config.scenes[id]
      kept[config.sceneOf] = scene()
      config.scenes = kept
      var next = kept[systemTheme] || themeScene
      if (next) stage(next)
    }
    set("sceneOf", systemTheme)
  }

  function refreshSystem() {
    if (!systemProc.running) systemProc.running = true
  }

  // Stepping while the last background is still being set is not lost: the
  // one wanted is shown at once and set as soon as Omarchy is free.
  function stepBackground(direction) {
    var n = backgrounds.length
    if (n === 0) return
    wallpaperPath = backgrounds[(Math.max(0, backgroundIndex) + direction + n) % n]
    setBackground()
  }

  // one picked from the list
  function pickBackground(path) {
    if (backgrounds.indexOf(path) < 0) return
    wallpaperPath = path
    setBackground()
  }

  function setBackground() {
    if (backgroundProc.running || backgroundProc.sent === wallpaperPath) return
    backgroundProc.sent = wallpaperPath
    backgroundProc.command = ["omarchy", "theme", "bg", "set", wallpaperPath]
    backgroundProc.running = true
  }

  // A theme takes a few seconds to go through every program, so stepping
  // only names the next one; it is applied once the clicking stops.
  function stepSystemTheme(direction) {
    var n = systemThemes.length
    if (n === 0) return
    var from = systemThemes.indexOf(pendingTheme !== "" ? pendingTheme : systemTheme)
    pendingTheme = systemThemes[(Math.max(0, from) + direction + n) % n]
    hold(pendingTheme)
    themeSettle.interval = 900
    themeSettle.restart()
  }

  // One picked from the list is the one that is wanted: there is nothing to
  // wait for.
  function pickSystemTheme(name) {
    if (systemThemes.indexOf(name) < 0) return
    pendingTheme = name
    hold(name)
    themeSettle.interval = 60
    themeSettle.restart()
  }

  Timer {
    id: themeSettle
    interval: 900
    onTriggered: {
      if (themeProc.running) { restart(); return }
      // stepped all the way back to the theme in use
      if (root.pendingTheme === root.systemTheme) { root.pendingTheme = ""; root.heldFor = ""; return }
      themeProc.command = ["omarchy", "theme", "set", root.pendingTheme]
      themeProc.running = true
    }
  }

  Process {
    id: backgroundProc
    property string sent: ""
    onExited: {
      // stepped on meanwhile
      if (sent !== root.wallpaperPath && root.backgrounds.indexOf(root.wallpaperPath) >= 0) root.setBackground()
      else { sent = ""; root.refreshSystem() }
    }
  }
  Process {
    id: themeProc
    onExited: {
      // if the theme did not come in, the blinds do not wait for it long
      if (root.heldFor !== "") { heldTooLong.interval = 1500; heldTooLong.restart() }
      if (!themeSettle.running) root.pendingTheme = ""
      root.refreshSystem()
    }
  }

  // theme, background, the theme's backgrounds, the themes, the theme's own scene: a section each
  Process {
    id: systemProc
    command: ["sh", "-c", 'cur="$HOME/.local/state/omarchy/current"; name=$(cat "$cur/theme.name" 2>/dev/null); '
      + 'echo "$name"; readlink -f "$cur/background"; echo --; '
      + 'find -L "$HOME/.config/omarchy/backgrounds/$name/" "$cur/theme/backgrounds/" -maxdepth 1 -type f 2>/dev/null '
      + '| grep -iE "\\.(jpe?g|png|gif|bmp|webp)$" | sort | while read -r f; do readlink -f "$f"; done; echo --; '
      + '{ ls -1 "$HOME/.config/omarchy/themes" 2>/dev/null; ls -1 "${OMARCHY_PATH:-/usr/share/omarchy}/themes" 2>/dev/null; } | sort -u; '
      + 'echo --; tr -d "\\n" < "$cur/theme/shades.json" 2>/dev/null; true']
    stdout: StdioCollector {
      onStreamFinished: {
        var parts = String(text || "").split("\n--\n")
        if (parts.length < 4) return
        var head = parts[0].split("\n")
        var list = function(block) { return block.split("\n").filter(function(l) { return l !== "" }) }
        root.systemTheme = head[0] || ""
        // while a background of ours is on its way the link may still name the old one
        if (!backgroundProc.running) root.wallpaperPath = (head[1] || "").trim()
        var found = list(parts[1]), themes = list(parts[2])
        if (found.join("\n") !== root.backgrounds.join("\n")) root.backgrounds = found
        if (themes.join("\n") !== root.systemThemes.join("\n")) root.systemThemes = themes
        var brought = null
        try { brought = JSON.parse(parts[3]) } catch (e) {}
        root.themeScene = brought !== null && typeof brought === "object" ? brought : null
        root.followTheme()
        if (root.heldFor !== "" && root.systemTheme === root.heldFor) released.restart()
      }
    }
  }

  // in case the folder watch missed something, and more often when it is not
  // there at all; a new theme also shows as new colours
  Timer {
    interval: watchProc.running ? 300000 : 60000
    running: config.enabled
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshSystem()
  }

  Connections {
    target: Commons.Color
    function onBackgroundChanged() { root.refreshSystem() }
    function onAccentChanged() { root.refreshSystem() }
  }

  Process {
    id: themesProc
    running: true
    command: ["sh", "-c", 'for f in "$HOME"/.config/shades/themes/*.json; do [ -f "$f" ] && printf "%s\\t%s\\n" "$(basename "$f" .json)" "$(tr -d "\\n" < "$f")"; done; true']
    stdout: StdioCollector {
      onStreamFinished: {
        var found = {}
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var tab = lines[i].indexOf("\t")
          if (tab < 1) continue
          try { found[lines[i].slice(0, tab)] = JSON.parse(lines[i].slice(tab + 1)) } catch (e) {}
        }
        root.customThemes = found
      }
    }
  }

  // The sky is looked at every twenty seconds, and on the minute, so that a
  // clock on the glass turns over when the real one does.
  Timer {
    interval: 20000
    running: config.enabled
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.refresh()
      interval = Math.min(20000, 60050 - Date.now() % 60000)
    }
  }

  // when the wall last moved, to go by the time that has really passed: a
  // timer that is kept waiting would run everything slow
  property real ticked: 0

  Timer {
    interval: 1000 / root.fps
    running: config.enabled && root.animated
    repeat: true
    onRunningChanged: root.ticked = 0
    onTriggered: {
      var t = Date.now()
      var dt = root.ticked > 0 ? Math.min(0.25, (t - root.ticked) / 1000) : interval / 1000
      root.ticked = t
      root.swayTime += dt
      root.rideOn(dt)
      root.passOn(dt)
      root.raceOn(dt)
    }
  }

  // --- one window per screen onto the wall -----------------------------------

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      visible: config.enabled
      anchors { top: true; bottom: true; left: true; right: true }
      color: "black"
      exclusionMode: ExclusionMode.Ignore
      // a click on the bare wall stops the lift or sends it on; in any other
      // room clicks fall through to whatever handles the desktop
      mask: root.motion === "lift" ? null : nothing
      Region { id: nothing }

      MouseArea {
        anchors.fill: parent
        enabled: root.motion === "lift"
        onClicked: root.holdLift()
      }

      WlrLayershell.namespace: "shades"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      // The window glass: whatever is drawn here is cast onto the wall.
      Item {
        id: glass
        width: 1024
        height: 1024
        visible: false

        Column {
          id: lettering
          anchors.centerIn: parent
          spacing: 28
          scale: Math.min(1, 880 / Math.max(1, implicitHeight))

          Repeater {
            model: root.shownLines

            Text {
              required property var modelData
              width: 860
              text: modelData
              textFormat: Text.PlainText
              color: "white"
              horizontalAlignment: Text.AlignHCenter
              font.family: config.font !== "" ? config.font : Style.font.family
              font.bold: true
              font.pixelSize: 250
              minimumPixelSize: 24
              fontSizeMode: Text.HorizontalFit
            }
          }
        }
      }

      ShaderEffectSource {
        id: glassSource
        sourceItem: glass
        // nothing to redraw while the text is not shown
        live: config.text
        mipmap: true
        smooth: true
        visible: false
      }

      // The background in use and the one before it: a new one opens over
      // the old from the middle outward, the way Omarchy's own does.
      property string shown: ""
      property string before: ""
      property bool primed: false
      readonly property bool hasPicture: picture.status === Image.Ready || (picture.status === Image.Loading && primed)
      // the blinds wait for a background that is still being read
      readonly property bool reading: picture.status === Image.Loading
      onReadingChanged: root.picturesLoading += reading ? 1 : -1
      Component.onDestruction: if (reading) root.picturesLoading -= 1

      function show(path) {
        if (path === shown) return
        reveal.stop()
        wall.wallFade = 1
        before = primed ? shown : ""
        shown = path
        open()
      }

      // the new one is read: it opens over the old, if the old is still at hand
      function open() {
        if (picture.status !== Image.Ready) return
        primed = true
        if (before === "" || reveal.running) return
        if (pictureBefore.status !== Image.Ready) { before = ""; return }
        wall.wallFade = 0
        reveal.start()
      }

      // An animator works on the render thread: the opening goes on evenly
      // however busy the shell is with the theme that brought the background.
      UniformAnimator {
        id: reveal
        target: wall
        uniform: "wallFade"
        from: 0
        to: 1
        duration: 520
        easing.type: Easing.InOutCubic
        onFinished: panel.before = ""
      }

      // the blinds as a curtain, the same way
      UniformAnimator { id: shutting; target: wall; uniform: "shut"; from: 0; to: 1; duration: 280; easing.type: Easing.InQuad }
      UniformAnimator { id: unshutting; target: wall; uniform: "shut"; from: 1; to: 0; duration: 420; easing.type: Easing.OutQuad }

      Connections {
        target: root
        function onCurtainDown() { unshutting.stop(); shutting.start() }
        function onCurtainUp() { shutting.stop(); wall.shut = 1; unshutting.start() }
        function onWallpaperPathChanged() { panel.show(root.wallpaperPath) }
      }

      Component.onCompleted: show(root.wallpaperPath)

      // A background is often several times the size of the screen: thirty
      // megapixels for two. It is read no larger than covers this screen with
      // a little to spare, which is quicker to load and to hand to the
      // graphics card, and a new background comes in without a hitch.
      readonly property size pictureSize: Qt.size(Math.ceil(1.25 * modelData.width * modelData.devicePixelRatio),
                                                  Math.ceil(1.25 * modelData.height * modelData.devicePixelRatio))

      Image {
        id: picture
        visible: false
        asynchronous: true
        sourceSize: panel.pictureSize
        fillMode: Image.PreserveAspectCrop
        mipmap: true
        // the old background stays up until the next one has loaded
        retainWhileLoading: true
        source: root.fileUrl(panel.shown)
        onStatusChanged: panel.open()
      }

      Image {
        id: pictureBefore
        visible: false
        asynchronous: true
        sourceSize: panel.pictureSize
        fillMode: Image.PreserveAspectCrop
        mipmap: true
        source: root.fileUrl(panel.before)
      }

      ShaderEffect {
        id: wall
        anchors.fill: parent
        fragmentShader: Qt.resolvedUrl("shaders/wall.frag.qsb")

        readonly property var frame: root.frameFor(panel.modelData)
        property vector4d rect: frame.rect
        property vector4d room: frame.room
        property vector4d win: root.panes
        property vector4d race: Qt.vector4d(root.raceAt, root.raceHeading, root.raceSpeed / root.topSpeed, root.raceGlare)
        property vector4d track: Qt.vector4d(root.lap, root.tunnelFrom, root.tunnelTo, root.raceLean)
        property real time: root.swayTime
        property real grain: config.grain
        // no tree keeps up with a room that travels
        property real treeAmt: config.tree && !root.moving ? 1 : 0
        property real monoAmt: root.theme.mono === true ? 1 : 0
        // changes behind shut blinds, like everything a theme brings
        property real latticeAmt: root.theme.screen === "lattice" ? 1 : 0
        property real castAmt: config.windowShadows ? 1 : 0
        property real castH: config.windowHeight
        property vector4d bar: root.barFor(panel.width, panel.height)
        property color barTint: Commons.Color.bar.background
        property real slatOpen: root.slatOpen
        property real shut: 0
        property real trailAmt: config.trail && !root.moving ? root.day : 0
        property real eclipseAmt: root.eclipse
        property vector4d w0: frame.casters[0]
        property vector4d w1: frame.casters[1]
        property vector4d w2: frame.casters[2]
        property vector4d w3: frame.casters[3]
        property vector4d w4: frame.casters[4]
        property vector4d w5: frame.casters[5]
        property vector4d w6: frame.casters[6]
        property vector4d w7: frame.casters[7]
        property real archAmt: root.windowName === "arch" ? 1 : 0
        property real shade: root.shade
        property real lift: root.lift
        property real motion: root.motions.indexOf(root.motion)
        property real stainAmt: root.theme.stained === true ? 1 : 0
        property real rainAmt: root.raining ? 1 : 0
        // until there is a background to light, a plain plastered wall stands in for it
        property real wallMix: panel.hasPicture ? 1 : 0
        property real wallAspect: panel.hasPicture ? picture.implicitWidth / Math.max(1, picture.implicitHeight) : 1
        property real wallAspectOld: pictureBefore.status === Image.Ready ? pictureBefore.implicitWidth / Math.max(1, pictureBefore.implicitHeight) : 1
        property real wallFade: 1
        property var wallOld: pictureBefore
        property vector4d white: root.linear(root.litHigh, 1)
        property var wallTex: picture
        property vector4d sky: root.sky
        property real drift: root.drift
        property real dust: config.dust ? 1 : 0
        property real ripple: config.glass
        property real textAmt: config.text ? 1 : 0
        property real textLight: config.textLight ? 1 : 0
        property vector4d ambient: root.ambient
        property vector4d geo0: root.geometry(root.lights[0], room)
        property vector4d col0: root.lights[0].color
        property vector4d geo1: root.geometry(root.lights[1], room)
        property vector4d col1: root.lights[1].color
        property vector4d geo2: root.geometry(root.lights[2], room)
        property vector4d col2: root.lights[2].color
        property vector4d geo3: root.geometry(root.lights[3], room)
        property vector4d col3: root.lights[3].color
        // the passing light moves by itself and is not eased
        property vector4d geo4: root.geometry(root.passer, room)
        property vector4d col4: root.passer.color
        property var textTex: glassSource

        // a window dragged larger grows, it does not jump; how many there are
        // changes behind shut blinds, at once
        Behavior on room { enabled: !root.turning; PropertyAnimation { duration: 160 } }
        Behavior on win { enabled: !root.turning; PropertyAnimation { duration: 160 } }

        // colour and geometry glide instead of stepping every refresh
        readonly property int glide: root.simHour < 0 && !root.tuned ? 1500 : 200
        Behavior on ambient { PropertyAnimation { duration: wall.glide } }
        Behavior on sky { PropertyAnimation { duration: wall.glide } }
        Behavior on geo0 { PropertyAnimation { duration: wall.glide } }
        Behavior on col0 { PropertyAnimation { duration: wall.glide } }
        Behavior on geo1 { PropertyAnimation { duration: wall.glide } }
        Behavior on col1 { PropertyAnimation { duration: wall.glide } }
        Behavior on geo2 { PropertyAnimation { duration: wall.glide } }
        Behavior on col2 { PropertyAnimation { duration: wall.glide } }
        Behavior on geo3 { PropertyAnimation { duration: wall.glide } }
        Behavior on col3 { PropertyAnimation { duration: wall.glide } }
        Behavior on treeAmt { NumberAnimation { duration: 600 } }
        Behavior on monoAmt { NumberAnimation { duration: 600 } }
        // what a theme brings changes at once while the blinds are shut
        Behavior on slatOpen { enabled: !root.turning; NumberAnimation { duration: 300 } }
        Behavior on trailAmt { NumberAnimation { duration: 600 } }
        Behavior on eclipseAmt { NumberAnimation { duration: 1500 } }
        Behavior on archAmt { enabled: !root.turning; NumberAnimation { duration: 600 } }
        Behavior on shade { NumberAnimation { duration: wall.glide } }
        Behavior on stainAmt { enabled: !root.turning; NumberAnimation { duration: 600 } }
        Behavior on rainAmt { NumberAnimation { duration: 3000 } }
        Behavior on wallMix { NumberAnimation { duration: 600 } }
        Behavior on drift { NumberAnimation { duration: 4000 } }
        Behavior on textAmt { NumberAnimation { duration: 600 } }
        Behavior on textLight { NumberAnimation { duration: 600 } }
      }

      Connections {
        target: root
        function onSnapshotRequested(path) {
          // the reference monitor gets the path as given, the rest add their name
          var own = panel.modelData === root.referenceScreen
            ? path : path.replace(/(\.[^.\/]*)?$/, "-" + panel.modelData.name + "$1")
          wall.grabToImage(function(result) { result.saveToFile(own) })
        }
      }
    }
  }
}
