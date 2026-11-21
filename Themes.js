.pragma library

// A theme is the colour of the light and the shade, what it does to the window and
// the scene it sets up there when it is picked. Anything a theme
// leaves out falls back to "plaster". A file ~/.config/shades/themes/<id>.json
// with the same keys adds a theme or overrides a built-in one.
//
//   palette   wall out of the light (shadow*) and in full light (lit*)
//   split     up to three colours the light is split into, sun and moon
//             alike: each a copy of the light on the wall in its own colour,
//             set a little apart from the others, so that the patch is one
//             and its edges and shadows are edged in colour:
//             color = what it keeps of the light, gain = how much (1),
//             shift = how far along the wall it is set off, lift = how far up
//   dusk      0..1 how much of the day's light stays all night, as in the
//             white nights of the north: the sun's patch does not go out
//             but pales, softens and goes back along the wall to where the
//             morning will find it
//   mono      black and white, like film
//   screen    "lattice" hangs a carved screen of stars in the window in place
//             of the blinds
//   arch      the window has an arched head, unless another window is chosen
//             (the blinds hang in every window, more or less open)
//   stained   the window is stained glass and colours the light
//   scene     switches set when the theme is picked (config keys)

var builtin = {
  plaster: {
    label: "Plaster",
    palette: {
      shadowNight: "#17181d", shadowDawn: "#6f5a49", shadowDay: "#6e6257", shadowOvercast: "#63605c",
      litHorizon: "#ffb877", litLow: "#f8e7bd", litHigh: "#f1e6d2", litOvercast: "#8f8b86", litMoon: "#aab6cf"
    },
    split: [],
    dusk: 0,
    mono: false,
    screen: "blinds",
    arch: false,
    stained: false,
    scene: { tree: false }
  },

  vitrage: {
    label: "Vitrage",
    palette: {
      shadowNight: "#121317", shadowDawn: "#5c5650", shadowDay: "#5f5f60", shadowOvercast: "#595a5b",
      litHorizon: "#ffc594", litLow: "#fbf1d8", litHigh: "#f6f3ea", litOvercast: "#8c8c8c", litMoon: "#b4c0d8"
    },
    arch: true,
    stained: true,
    scene: { tree: false, text: false, textLight: false }
  },

  // a northern summer: the night never quite falls
  whitenights: {
    label: "White Nights",
    palette: {
      shadowNight: "#3b4150", shadowDawn: "#5f5c66", shadowDay: "#6a6a6e", shadowOvercast: "#606268",
      litHorizon: "#e6dde6", litLow: "#f1ead9", litHigh: "#eef0ee", litOvercast: "#8e9096", litMoon: "#b9c2d6"
    },
    dusk: 0.32,
    scene: { tree: false, text: false, textLight: false }
  },

  noir: {
    label: "Noir",
    palette: {
      shadowNight: "#0b0b0b", shadowDawn: "#2c2c2c", shadowDay: "#2e2e2e", shadowOvercast: "#303030",
      litHorizon: "#d8d8d8", litLow: "#e6e6e6", litHigh: "#ececec", litOvercast: "#6a6a6a", litMoon: "#b0b0b0"
    },
    mono: true,
    scene: { tree: false, text: false, textLight: false }
  },

  // sandstone, an arched opening and a carved screen in it
  lattice: {
    label: "Lattice",
    palette: {
      shadowNight: "#16141a", shadowDawn: "#7a5540", shadowDay: "#8a6b4c", shadowOvercast: "#75654f",
      litHorizon: "#ff9c5a", litLow: "#fbd9a0", litHigh: "#f6e3bd", litOvercast: "#a08f76", litMoon: "#b3b0c8"
    },
    arch: true,
    screen: "lattice",
    scene: { tree: false, text: false, textLight: false }
  },

  neon: {
    label: "Neon",
    palette: {
      shadowNight: "#15121f", shadowDawn: "#3d3935", shadowDay: "#3a3c3f", shadowOvercast: "#37393b",
      litHorizon: "#ff9a52", litLow: "#e6d9bd", litHigh: "#d9d9d3", litOvercast: "#6b6d6f", litMoon: "#8f9db8"
    },
    // cyan and magenta: where both land the wall is pale, and each one's
    // shadows are the colour of the other
    split: [
      { color: "#12d8ff", shift: -0.02, lift: -0.012 },
      { color: "#ff1f8e", shift: 0.02, lift: 0.012 }
    ],
    scene: { tree: false, text: false, textLight: false }
  }
}

// the windows there are
var windows = ["square", "arch"]

var order = ["plaster", "whitenights", "noir", "neon", "vitrage", "lattice"]

// `custom` maps theme ids to objects read from the user's theme files.
function resolve(id, custom) {
  var base = builtin.plaster
  var own = (custom && custom[id]) || builtin[id] || {}
  var out = {}
  for (var key in base) out[key] = own[key] !== undefined ? own[key] : base[key]
  if (own.palette) {
    out.palette = {}
    for (var c in base.palette) out.palette[c] = own.palette[c] || base.palette[c]
  }
  // a theme that is no longer there shows as the one that stands in for it
  out.label = own.label || (custom && custom[id] ? id : base.label)
  return out
}

function ids(custom) {
  var out = order.slice()
  for (var id in (custom || {})) if (out.indexOf(id) < 0) out.push(id)
  return out
}
