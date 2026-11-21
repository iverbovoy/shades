// Checks Sun.js and Moon.js against facts that do not come from this code:
// run with `node tests/astronomy.test.js`.
const fs = require("fs")
const path = require("path")
const assert = require("assert")

// The modules are QML JavaScript libraries: drop the pragma and collect the functions.
function load(name, exported) {
  const source = fs.readFileSync(path.join(__dirname, "..", name), "utf8").replace(/^\.pragma library$/m, "")
  return new Function(source + "\nreturn { " + exported.join(", ") + " }")()
}

const Sun = load("Sun.js", ["elevation", "riseSet", "state"])
const Moon = load("Moon.js", ["state"])

function near(actual, expected, tolerance, what) {
  assert.ok(Math.abs(actual - expected) <= tolerance, `${what}: ${actual} is not within ${tolerance} of ${expected}`)
}

// At solar noon the sun stands at 90 - latitude + declination.
const paris = { lat: 48.86, lon: 2.35 }
const solstice = Sun.riseSet(new Date(2026, 5, 21, 12), paris.lat, paris.lon)
near(Sun.elevation(solstice.noon, paris.lat, paris.lon), 90 - paris.lat + 23.44, 0.2, "Paris, June solstice noon")

const winter = Sun.riseSet(new Date(2026, 11, 21, 12), paris.lat, paris.lon)
near(Sun.elevation(winter.noon, paris.lat, paris.lon), 90 - paris.lat - 23.44, 0.2, "Paris, December solstice noon")

// On the equinox day and night are equal everywhere (refraction adds a few minutes).
const equinox = Sun.riseSet(new Date(2026, 2, 20, 12), 0, 0)
near((equinox.sunset - equinox.sunrise) / 3600000, 12, 0.2, "equator, equinox day length")

// Beyond the polar circle the sun does not set in June nor rise in December.
assert.strictEqual(Sun.riseSet(new Date(2026, 5, 21, 12), 78, 15).polar, "day")
assert.strictEqual(Sun.riseSet(new Date(2026, 11, 21, 12), 78, 15).polar, "night")

// Daylight progress runs from 0 at sunrise to 1 at sunset.
near(Sun.state(solstice.sunrise, paris.lat, paris.lon).progress, 0, 0.01, "progress at sunrise")
near(Sun.state(solstice.noon, paris.lat, paris.lon).progress, 0.5, 0.01, "progress at noon")

// Far from Greenwich the local day and the UTC day differ: sunrise and sunset
// still belong to the local day, and noon lies between them.
const here = process.env.TZ
for (const [zone, lat, lon] of [["Pacific/Auckland", -36.85, 174.76], ["Pacific/Kiritimati", 1.87, -157.4],
                                ["Pacific/Honolulu", 21.3, -157.85], ["Europe/Paris", 48.86, 2.35]]) {
  process.env.TZ = zone
  const noon = new Date(2026, 11, 21, 12)
  const day = Sun.riseSet(noon, lat, lon)
  assert.strictEqual(day.sunrise.getDate(), 21, zone + ": sunrise on the local day")
  assert.strictEqual(day.sunset.getDate(), 21, zone + ": sunset on the local day")
  assert.ok(day.sunrise < noon && noon < day.sunset, zone + ": noon is in daylight")
  near(Sun.state(day.noon, lat, lon).progress, 0.5, 0.01, zone + ": progress at solar noon")
}
if (here === undefined) delete process.env.TZ
else process.env.TZ = here

// Published moon phases, November 2026 (UTC).
near(Moon.state(new Date("2026-11-09T07:02Z"), 0, 0).phase, 0, 0.01, "new moon")
near(Moon.state(new Date("2026-11-17T11:48Z"), 0, 0).phase, 0.5, 0.01, "first quarter")
near(Moon.state(new Date("2026-11-24T14:53Z"), 0, 0).phase, 1, 0.01, "full moon")

// A full moon is opposite the sun: up at midnight, down at noon.
const fullMoonNight = new Date("2026-11-24T23:00Z") // midnight in Paris
assert.ok(Moon.state(fullMoonNight, paris.lat, paris.lon).elevation > 30, "full moon is high at midnight")
assert.ok(Moon.state(new Date("2026-11-24T11:00Z"), paris.lat, paris.lon).elevation < 0, "full moon is down at noon")

// Solar eclipses: the moon meets the sun at the greatest eclipse of 12 August
// 2026 (17:46 UTC) and of 2 August 2027 (10:07 UTC), and is far from it a week later.
assert.ok(Moon.state(new Date("2026-08-12T17:46Z"), 0, 0).sunDistance < 1.2, "eclipse of August 2026")
assert.ok(Moon.state(new Date("2027-08-02T10:07Z"), 0, 0).sunDistance < 1.2, "eclipse of August 2027")
assert.ok(Moon.state(new Date("2026-08-19T17:46Z"), 0, 0).sunDistance > 60, "a week after an eclipse")
// An ordinary new moon passes well clear of the sun.
assert.ok(Moon.state(new Date("2026-11-09T07:02Z"), 0, 0).sunDistance > 1.5, "new moon without an eclipse")

console.log("astronomy: all checks passed")
