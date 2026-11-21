.pragma library

// Moon position and phase from the low-precision series of the Astronomical
// Almanac (about a third of a degree, parallax ignored: plenty for a shadow).

function rad(d) { return d * Math.PI / 180 }
function deg(r) { return r * 180 / Math.PI }
function sind(d) { return Math.sin(rad(d)) }
function cosd(d) { return Math.cos(rad(d)) }

// Elevation in degrees, how far through its arc across the sky the moon is
// (0 rising, 1 setting), the lit fraction of its disc and its distance from the sun.
function state(date, lat, lon) {
  var d = date.getTime() / 86400000 + 2440587.5 - 2451545 // days since J2000
  var t = d / 36525

  // ecliptic longitude and latitude
  var lambda = 218.32 + 481267.881 * t
             + 6.29 * sind(135.0 + 477198.87 * t)
             - 1.27 * sind(259.3 - 413335.36 * t)
             + 0.66 * sind(235.7 + 890534.22 * t)
             + 0.21 * sind(269.9 + 954397.74 * t)
             - 0.19 * sind(357.5 + 35999.05 * t)
             - 0.11 * sind(186.5 + 966404.03 * t)
  var beta = 5.13 * sind(93.3 + 483202.02 * t)
           + 0.28 * sind(228.2 + 960400.89 * t)
           - 0.28 * sind(318.3 + 6003.15 * t)
           - 0.17 * sind(217.6 - 407332.21 * t)

  // to right ascension and declination
  var eps = 23.439 - 0.013 * t
  var l = cosd(beta) * cosd(lambda)
  var m = cosd(eps) * cosd(beta) * sind(lambda) - sind(eps) * sind(beta)
  var n = sind(eps) * cosd(beta) * sind(lambda) + cosd(eps) * sind(beta)
  var ra = deg(Math.atan2(m, l))
  var decl = deg(Math.asin(n))

  // hour angle: negative before the moon crosses the meridian
  var gmst = 280.46061837 + 360.98564736629 * d
  var ha = (((gmst + lon - ra + 180) % 360) + 360) % 360 - 180

  var sinElev = sind(lat) * sind(decl) + cosd(lat) * cosd(decl) * cosd(ha)
  var elev = deg(Math.asin(Math.max(-1, Math.min(1, sinElev))))

  // half the arc above the horizon; the moon may also stay up or down all day
  var cosH = -Math.tan(rad(lat)) * Math.tan(rad(decl))
  var progress = Math.abs(cosH) < 1 ? 0.5 + ha / (2 * deg(Math.acos(cosH))) : 0.5 + ha / 360

  // lit fraction from the angle between the moon and the sun
  var g = 357.528 + 35999.050 * t
  var sunLambda = 280.460 + 36000.771 * t + 1.915 * sind(g) + 0.020 * sind(2 * g)
  var cosElong = cosd(beta) * cosd(lambda - sunLambda)

  return {
    elevation: elev,
    progress: Math.max(0, Math.min(1, progress)),
    phase: (1 - cosElong) / 2,
    // degrees between the centres of the moon and the sun, seen from the
    // centre of the Earth; under about 1.5 an eclipse is under way somewhere
    sunDistance: deg(Math.acos(Math.max(-1, Math.min(1, cosElong))))
  }
}
