// Checks Themes.js and Weather.js: run with `node tests/modules.test.js`.
const fs = require("fs")
const path = require("path")
const assert = require("assert")

// The modules are QML JavaScript libraries: drop the pragma and collect what they define.
function load(name, exported) {
  const source = fs.readFileSync(path.join(__dirname, "..", name), "utf8").replace(/^\.pragma library$/m, "")
  return new Function(source + "\nreturn { " + exported.join(", ") + " }")()
}

const Themes = load("Themes.js", ["builtin", "order", "windows", "resolve", "ids"])
const Weather = load("Weather.js", ["describe", "url", "parse"])

// --- themes ---------------------------------------------------------------

// Every theme in the order is there, and nothing is there that is not in it.
assert.deepStrictEqual(Themes.order.slice().sort(), Object.keys(Themes.builtin).sort(), "order names the built-in themes")
assert.strictEqual(Themes.order[0], "plaster", "plaster comes first: it is the default")

// A resolved theme has every key plaster has, and a whole palette.
const keys = Object.keys(Themes.builtin.plaster).sort()
const colours = Object.keys(Themes.builtin.plaster.palette).sort()
for (const id of Themes.order) {
  const theme = Themes.resolve(id, {})
  assert.deepStrictEqual(Object.keys(theme).sort(), keys, id + ": every key is filled in")
  assert.deepStrictEqual(Object.keys(theme.palette).sort(), colours, id + ": the palette is whole")
  for (const c of colours) assert.match(theme.palette[c], /^#[0-9a-f]{6}$/i, id + "." + c + " is a colour")
  assert.ok(theme.split.length <= 3, id + ": the light is split three ways at most")
  for (const part of theme.split) assert.match(part.color, /^#[0-9a-f]{6}$/i, id + ": a split colour is a colour")
  assert.ok(theme.dusk >= 0 && theme.dusk <= 1, id + ": dusk is a share")
  assert.ok(["blinds", "lattice"].includes(theme.screen), id + ": a screen there is")
  assert.ok(typeof theme.label === "string" && theme.label !== "", id + ": it has a name")
}

// What a theme leaves out comes from plaster; what it sets is its own.
assert.strictEqual(Themes.resolve("noir", {}).mono, true)
assert.strictEqual(Themes.resolve("noir", {}).arch, Themes.builtin.plaster.arch)
assert.strictEqual(Themes.resolve("lattice", {}).screen, "lattice")

// A theme that is not there is plaster, under plaster's name.
const gone = Themes.resolve("no-such-theme", {})
assert.deepStrictEqual(gone.palette, Themes.builtin.plaster.palette)
assert.strictEqual(gone.label, Themes.builtin.plaster.label)

// A theme of the user's adds to the list, overrides a built-in one of the
// same name, and need not give a whole palette.
const custom = { dawn: { palette: { litHigh: "#ffeedd" }, arch: true }, noir: { label: "My Noir", mono: false } }
assert.deepStrictEqual(Themes.ids(custom), Themes.order.concat(["dawn"]))
const dawn = Themes.resolve("dawn", custom)
assert.strictEqual(dawn.palette.litHigh, "#ffeedd")
assert.strictEqual(dawn.palette.litLow, Themes.builtin.plaster.palette.litLow)
assert.strictEqual(dawn.arch, true)
assert.strictEqual(dawn.label, "dawn", "a theme without a name goes by its file's")
assert.strictEqual(Themes.resolve("noir", custom).label, "My Noir")
assert.strictEqual(Themes.resolve("noir", custom).mono, false)
assert.deepStrictEqual(Themes.ids(null), Themes.order)

// --- weather --------------------------------------------------------------

assert.strictEqual(Weather.describe(0), "Clear")
assert.strictEqual(Weather.describe(3), "Overcast")
assert.strictEqual(Weather.describe(63), "Rain")
assert.strictEqual(Weather.describe(82), "Showers")
assert.strictEqual(Weather.describe(96), "Thunderstorm")
assert.strictEqual(Weather.describe(1234), "Thunderstorm")
assert.strictEqual(Weather.describe(-1), "", "a code nobody knows says nothing")

// the place is sent to the hundredth of a degree, no finer
const url = Weather.url(48.8566, 2.3522)
assert.ok(url.includes("latitude=48.86&longitude=2.35"), url)
assert.ok(url.startsWith("https://api.open-meteo.com/"), url)

const answer = JSON.stringify({ current: { temperature_2m: 3.6, weather_code: 61, cloud_cover: 88 } })
assert.deepStrictEqual(Weather.parse(answer), { temperature: 4, sky: "Rain", clouds: 88 })
assert.strictEqual(Weather.parse(JSON.stringify({ current: { temperature_2m: -0.4, weather_code: 0 } })).clouds, 0, "no cloud cover given is none")
assert.strictEqual(Weather.parse(""), null, "no answer")
assert.strictEqual(Weather.parse("<html>busy</html>"), null, "not an answer")
assert.strictEqual(Weather.parse("{}"), null, "an answer with nothing in it")
assert.strictEqual(Weather.parse(JSON.stringify({ current: {} })), null)

console.log("modules: all checks passed")
