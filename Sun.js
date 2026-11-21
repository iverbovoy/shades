.pragma library

// Solar position after the NOAA solar calculator (good to a fraction of a degree).

function rad(d) { return d * Math.PI / 180 }
function deg(r) { return r * 180 / Math.PI }

function julianCentury(date) {
  return (date.getTime() / 86400000 + 2440587.5 - 2451545) / 36525
}

function solar(date) {
  var t = julianCentury(date)
  var l0 = (280.46646 + t * (36000.76983 + t * 0.0003032)) % 360
  var m = 357.52911 + t * (35999.05029 - 0.0001537 * t)
  var e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
  var c = Math.sin(rad(m)) * (1.914602 - t * (0.004817 + 0.000014 * t))
        + Math.sin(rad(2 * m)) * (0.019993 - 0.000101 * t)
        + Math.sin(rad(3 * m)) * 0.000289
  var omega = 125.04 - 1934.136 * t
  var lambda = l0 + c - 0.00569 - 0.00478 * Math.sin(rad(omega))
  var eps0 = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
  var eps = eps0 + 0.00256 * Math.cos(rad(omega))
  var decl = deg(Math.asin(Math.sin(rad(eps)) * Math.sin(rad(lambda))))
  var y = Math.tan(rad(eps / 2)) * Math.tan(rad(eps / 2))
  var eqTime = 4 * deg(y * Math.sin(2 * rad(l0))
             - 2 * e * Math.sin(rad(m))
             + 4 * e * y * Math.sin(rad(m)) * Math.cos(2 * rad(l0))
             - 0.5 * y * y * Math.sin(4 * rad(l0))
             - 1.25 * e * e * Math.sin(2 * rad(m)))
  return { decl: decl, eqTime: eqTime } // degrees, minutes
}

// Sun elevation in degrees at `date` for the given place.
function elevation(date, lat, lon) {
  var s = solar(date)
  var utcMin = date.getUTCHours() * 60 + date.getUTCMinutes() + date.getUTCSeconds() / 60
  var trueSolar = (utcMin + s.eqTime + 4 * lon + 1440) % 1440
  var ha = trueSolar / 4 - 180
  var cosZen = Math.sin(rad(lat)) * Math.sin(rad(s.decl))
             + Math.cos(rad(lat)) * Math.cos(rad(s.decl)) * Math.cos(rad(ha))
  return 90 - deg(Math.acos(Math.max(-1, Math.min(1, cosZen))))
}

// Sunrise and sunset as Date objects for the local day containing `date`.
// `polar` is "day" or "night" when the sun does not cross the horizon.
function riseSet(date, lat, lon) {
  var noonLocal = new Date(date.getFullYear(), date.getMonth(), date.getDate(), 12, 0, 0)
  var s = solar(noonLocal)
  var cosH = (Math.cos(rad(90.833)) - Math.sin(rad(lat)) * Math.sin(rad(s.decl)))
           / (Math.cos(rad(lat)) * Math.cos(rad(s.decl)))
  var midnightUtc = Date.UTC(noonLocal.getUTCFullYear(), noonLocal.getUTCMonth(), noonLocal.getUTCDate())
  var noonMin = 720 - 4 * lon - s.eqTime // minutes after 00:00 UTC
  // far from Greenwich the UTC day is not the local one: take the solar noon
  // that falls in the local day
  var noon = midnightUtc + noonMin * 60000
  while (noon - noonLocal.getTime() > 43200000) noon -= 86400000
  while (noonLocal.getTime() - noon > 43200000) noon += 86400000
  if (cosH > 1) return { polar: "night", noon: new Date(noon) }
  if (cosH < -1) return { polar: "day", noon: new Date(noon) }
  var h = deg(Math.acos(cosH)) * 4
  return {
    polar: "",
    noon: new Date(noon),
    sunrise: new Date(noon - h * 60000),
    sunset: new Date(noon + h * 60000)
  }
}

// Everything the wallpaper needs: elevation plus how far through the daylight we are.
function state(date, lat, lon) {
  var rs = riseSet(date, lat, lon)
  var elev = elevation(date, lat, lon)
  var progress
  if (rs.polar) {
    // no sunrise today: sweep once per 24h, centred on solar noon
    progress = 0.5 + (date.getTime() - rs.noon.getTime()) / 86400000
  } else {
    progress = (date.getTime() - rs.sunrise.getTime()) / (rs.sunset.getTime() - rs.sunrise.getTime())
  }
  return {
    elevation: elev,
    progress: Math.max(0, Math.min(1, progress)),
    sunrise: rs.sunrise || null,
    sunset: rs.sunset || null
  }
}
