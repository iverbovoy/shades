.pragma library

// WMO weather codes, as returned by Open-Meteo, in a couple of words.
function describe(code) {
  if (code === 0) return "Clear"
  if (code === 1) return "Mostly clear"
  if (code === 2) return "Partly cloudy"
  if (code === 3) return "Overcast"
  if (code === 45 || code === 48) return "Fog"
  if (code >= 51 && code <= 57) return "Drizzle"
  if (code >= 61 && code <= 67) return "Rain"
  if (code >= 71 && code <= 77) return "Snow"
  if (code >= 80 && code <= 82) return "Showers"
  if (code === 85 || code === 86) return "Snow showers"
  if (code >= 95) return "Thunderstorm"
  return ""
}

function url(lat, lon) {
  return "https://api.open-meteo.com/v1/forecast?latitude=" + lat.toFixed(2)
    + "&longitude=" + lon.toFixed(2)
    + "&current=temperature_2m,weather_code,cloud_cover"
}

// Open-Meteo response → { temperature, sky, clouds } or null.
function parse(raw) {
  try {
    var cur = JSON.parse(raw).current
    if (!cur || cur.temperature_2m === undefined) return null
    return {
      temperature: Math.round(cur.temperature_2m),
      sky: describe(cur.weather_code),
      clouds: cur.cloud_cover === undefined ? 0 : cur.cloud_cover
    }
  } catch (e) {
    return null
  }
}
