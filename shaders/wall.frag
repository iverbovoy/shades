#version 440

// Light through the blinds of a side window falling on a wall: the Omarchy background. A tree outside
// and lettering on the glass can each be switched on, and every light casts
// all of them, so the shadows slide and stretch together. The lights (sun,
// moon, the colours a theme splits them into, a light passing by) are added
// up in linear colour, which is what makes the shadow of one light take the
// colour of the other. All are so far off that their light is parallel.
//
// Scene (units: height of the reference monitor = 1, y up). The wall is the
// plane z = 0 and may span several monitors; `rect` says which part of it this
// window shows. A pixel is a point of that plane.
//   window = on the right side wall, spanning WIN_Z along the room depth and
//            room.zw vertically; there may be several in a row, a pier
//            between each two
// For each wall pixel we walk back toward a light, S ~ (k, m*k, 1), and look at
// where the ray crosses the window plane. k = sx/sz slides and widens the patch
// over the day, m = sy/sx is the slant of the slat shadows (height of the light).

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  float time;      // seconds, drives everything that moves
  float grain;     // strength of the colour mottling of the wall
  float ripple;    // unevenness of the window glass
  float treeAmt;   // 0..1 a tree outside the window
  float drift;     // 0..1 clouds pass over the sun now and then
  float dust;      // 0..1 motes floating in the beam
  float monoAmt;   // 0..1 the picture is black and white
  float latticeAmt; // 0..1 a carved screen hangs in the window in place of the blinds
  float castAmt;   // 0..1 the windows of the desktop cast shadows on the wall
  float castH;     // how far in front of the wall those windows float
  float trailAmt;  // 0..1 the wall keeps a trace of where the sun has been today
  float eclipseAmt; // 0..1 how much of the sun the moon is covering
  float slatOpen;  // share of each slat period the blinds let light through
  float shut;      // 0..1 the blinds drawn shut over a change that is not to be seen
  float archAmt;   // 0..1 the window has an arched head
  float stainAmt;  // 0..1 the window is stained glass
  float rainAmt;   // 0..1 rain on the glass
  float wallMix;   // 0..1 the wall is the wallpaper image
  float wallFade;  // 0..1 how far the new wallpaper has opened over the one before
  float wallAspectOld; // width / height of the one before
  float wallAspect; // width / height of that image
  float textAmt;   // 0..1 lettering on the glass
  float textLight; // 0 = letters cast shadows, 1 = only the letters let light in
  float shade;     // how much of itself the picture keeps out of the light
  float lift;      // how far the lift is past the last floor, 0..1; 0 at rest
  float motion;    // what the room is: 0 a room (or a lift), 2 a train, 3 a ship, 4 a racing car
  vec4 rect;       // this monitor on the wall: left, top, width, height
  vec4 room;       // wall left and right ends, window bottom and top
  vec4 race;       // the racing car: where it is along the lap, how far it has turned from the way it
                   // set out (radians), its speed as a share of the fastest, the glare of coming out of the dark
  vec4 track;      // its track: the length of a lap, where the tunnel begins and ends, and how hard
                   // the car is pressed sideways just now (-1..1)
  vec4 win;        // the windows along the side wall: where the first begins, how wide one is,
                   // from one to the next, how many
  vec4 ambient;    // linear colour of the wall out of any direct light
  vec4 sky;        // colour of the daylight the window spreads, w = its share of the ambient
  // per light: geo = (k, m, penumbra multiplier), col = linear colour it
  // adds. They are the sun and the moon, or the colours a theme splits them
  // into, all too far off for their light to be anything but parallel
  vec4 geo0; vec4 col0;
  vec4 geo1; vec4 col1;
  vec4 geo2; vec4 col2;
  vec4 geo3; vec4 col3;
  // a light that passes by: the headlights of a car.
  // It is far off and has its own way across the wall
  vec4 geo4; vec4 col4;
  vec4 white;      // linear colour of the wall in full sun
  // the shell's bar lies over the wall: x = edge (0 none, 1 top, 2 bottom, 3 left,
  // 4 right), y = its thickness as a share of that side, z = 1 when it is tinted
  vec4 bar;
  vec4 barTint;    // colour of the tint
  // desktop windows on the wall: left, bottom, right, top (empty when right <= left)
  vec4 w0; vec4 w1; vec4 w2; vec4 w3; vec4 w4; vec4 w5; vec4 w6; vec4 w7;
};

layout(binding = 1) uniform sampler2D textTex;
layout(binding = 2) uniform sampler2D wallTex;
layout(binding = 3) uniform sampler2D wallOld; // the wallpaper before this one

// colour the glass gave the light on the last call of shed()
vec3 glassTint = vec3(1.0);
// and how much of the haze round the patch that call found here
float haze = 0.0;
// how open the blinds stand this moment: as they are set, less what the curtain takes
float slatsNow = 0.64;
// how far the room leans just now: the patch leans with it
float heel = 0.0;
// 1 while the light being worked out is one that passes close by, inside
// whatever shuts the day out: a tunnel has no hold on its own lamps
float nearby = 0.0;

const float WIN_GAP = 0.02;
const float TREE_DIST = 2.5; // how far outside the window the tree stands
// the first window along the room's depth, and the whole row from the first to the last
vec2 WIN_Z = vec2(1.0, 2.4);
vec2 ALL_Z = vec2(1.0, 2.4);
const float SLAT_PERIOD = 0.036;
const float REVEAL = 0.05;   // thickness of the wall the window is set in
const float FLOOR = 1.7;     // from one floor to the next
const float SHAFT = 0.35;    // how far outside the glass the wall of the shaft goes by
const float SPEED = 1.6;     // of the train, a second
const float TUNNEL_EVERY = 80.0; // track from one tunnel mouth to the next
const float TUNNEL_LONG = 9.0;   // and the tunnel's share of it

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
             mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
  float a = 0.5, s = 0.0;
  for (int i = 0; i < 4; i++) {
    s += a * vnoise(p);
    p = p * 2.03 + 17.1;
    a *= 0.5;
  }
  return s;
}

// 1 inside [lo, hi], fading over e on both sides
float box(float v, vec2 r, float e) {
  return smoothstep(r.x - e, r.x + e, v) * (1.0 - smoothstep(r.y - e, r.y + e, v));
}

// Light getting past a bar of half width hw whose axis is d away, when the
// disc of the light smears edges over b either way.
float pastBar(float d, float hw, float b) {
  b = max(b, 1e-4);
  float c = clamp((min(d + b, hw) - max(d - b, -hw)) / (2.0 * b), 0.0, 1.0);
  return 1.0 - c;
}

// Light through blinds at y (in slat periods) when `open` of each period is
// clear and edges are smeared over b either way: the clear part averaged.
float pastSlats(float y, float open, float b) {
  b = max(b, 1e-3);
  float lo = y - b, hi = y + b;
  float a = floor(lo) * open + min(fract(lo), open);
  float c = floor(hi) * open + min(fract(hi), open);
  return (c - a) / (2.0 * b);
}

// A carved screen in place of the blinds, at upright window position w:
// eight-pointed stars cut through it, and a small diamond between every four.
// `open` says how wide they are cut, 1 as the screen was made and 0 shut.
float lattice(vec2 w, float open, float blur) {
  const float CELL = 0.085;
  vec2 q = abs(fract(w / CELL) - 0.5);
  float star = min(max(q.x, q.y), (q.x + q.y) * 0.7071) - 0.31 * open;
  vec2 c = 0.5 - q;
  float diamond = (c.x + c.y) * 0.7071 - 0.15 * open;
  // light that has come far draws every opening as a soft round of sun
  float b = clamp(blur / CELL, 0.01, 0.12);
  return 1.0 - smoothstep(-b, b, min(star, diamond));
}

// Coverage of the lettering at window position uv, blurred by r (in uv).
float lettering(vec2 uv, vec2 r) {
  float lod = log2(max(1.0, max(r.x, r.y) * 1024.0 * 0.35));
  float a = 2.0 * textureLod(textTex, uv, lod).a;
  for (int i = 0; i < 8; i++) {
    float ang = 0.785398 * float(i);
    a += textureLod(textTex, uv + r * 0.7 * vec2(cos(ang), sin(ang)), lod).a;
  }
  return a / 10.0;
}

// One depth of the canopy: how much of the light at c its leaves stop. A
// leaf sits in each cell of a grid `scale` to the unit, wherever the tree has
// a bough there; `blur` is how far the disc of the light smears its edge.
float leaves(vec2 c, float scale, float blur, float seed) {
  vec2 g = c * scale;
  vec2 cell = floor(g);
  float b = max(blur * scale, 0.02);
  // a leaf much smaller than the smear never gets fully dark
  float depth = min(1.0, 0.36 / b);
  float clear = 1.0;
  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      vec2 o = cell + vec2(float(i), float(j));
      float bough = smoothstep(0.34, 0.58, vnoise(o / scale * 2.6 + seed));
      if (hash(o + seed) > bough) continue;
      vec2 q = g - o - 0.5 - 0.8 * (vec2(hash(o + seed + 1.3), hash(o + seed + 2.9)) - 0.5);
      float turn = 6.283 * hash(o + seed + 4.1) + 0.25 * sin(time * 0.9 + 6.283 * hash(o + seed + 6.7));
      q = vec2(cos(turn) * q.x - sin(turn) * q.y, sin(turn) * q.x + cos(turn) * q.y);
      float d = (length(q / vec2(0.66, 0.30)) - 1.0) * 0.30;
      clear *= 1.0 - depth * (1.0 - smoothstep(-b, b, d));
    }
  }
  return 1.0 - clear;
}

// Sky showing through a tree at canopy position c (1 = open sky). The far
// leaves are smeared into the soft coins of light a tree lays on a wall; a
// branch that hangs nearer the window keeps the shape of its leaves.
float canopy(vec2 c, float blur) {
  c += 0.012 * vec2(sin(time * 0.60 + c.y * 2.0), cos(time * 0.47 + c.x * 1.7));
  float far = leaves(c, 24.0, blur, 3.0);
  float mid = leaves(c + 0.004 * sin(time * 0.8), 13.0, blur * 0.75, 11.0);
  float near = leaves(c - 0.006 * cos(time * 0.5), 10.0, blur * 0.45, 23.0);
  return (1.0 - 0.92 * far) * (1.0 - 0.92 * mid) * (1.0 - 0.85 * near);
}

// Stained glass at pane position uv: the colour of the glass and, in `came`,
// 0 where the lead blocks the light. Tall lights stand side by side, each of
// one colour, deep at the foot and paling toward the head, so that the light
// between two slats of the blinds runs through all of them in turn.
vec3 stained(vec2 uv, float blur, out float came) {
  float g = uv.x * 6.0;
  float id = floor(g);
  // the lead between two lights, and the two bars that tie them across
  float toLead = (0.5 - abs(fract(g) - 0.5)) / 6.0;
  float toBar = min(abs(uv.y - 0.36), abs(uv.y - 0.70));
  came = smoothstep(0.003, 0.003 + 0.5 * blur, toLead) * smoothstep(0.003, 0.003 + 0.5 * blur, toBar);
  vec3 c = vec3(0.14, 0.28, 0.74);                 // cobalt
  if (id > 0.5) c = vec3(0.12, 0.50, 0.56);        // teal
  if (id > 1.5) c = vec3(0.18, 0.52, 0.30);        // green
  if (id > 2.5) c = vec3(0.95, 0.62, 0.16);        // amber
  if (id > 3.5) c = vec3(0.78, 0.14, 0.12);        // ruby
  if (id > 4.5) c = vec3(0.46, 0.22, 0.60);        // violet
  c = mix(c, vec3(0.96, 0.90, 0.74), 0.20 + 0.50 * smoothstep(0.15, 1.0, uv.y));
  // hand-made glass: streaked the way it was drawn out, with a seed of air
  // here and there
  float streak = fbm(vec2(uv.x * 14.0 + 9.0 * id, uv.y * 3.0));
  c *= 1.10 + 0.30 * streak;
  c *= 1.0 - 0.22 * smoothstep(0.72, 0.86, vnoise(uv * vec2(160.0, 200.0)));
  return c;
}

// Rain on the glass at upright window position w, as the wall sees it. The
// drops are far too small to survive the trip across the room; what is left
// is a mottling and the wavering streaks of the water running down. Above 0
// it takes light away, below 0 it gathers some.
float rain(vec2 w) {
  float beads = fbm(w * 55.0 + vec2(0.0, time * 0.02));
  vec2 r = vec2(w.x * 38.0, w.y * 3.0 + time * 0.22);
  r.x += 0.6 * vnoise(vec2(w.x * 9.0, w.y * 5.0 + time * 0.15));
  return 0.5 * (beads - 0.47) + 1.1 * (fbm(r) - 0.47);
}

float inWindow(vec2 q, vec4 w, float blur) {
  if (w.z <= w.x) return 0.0;
  return box(q.x, w.xz, blur) * box(q.y, w.yw, blur);
}

// Shadow the desktop windows throw at room point p for a light that lies
// `toward` along the wall. They float a little in front of the wall, so the
// shadow slips out from under them away from the light: a short way at
// midday, a long way toward evening.
float desktopShadow(vec3 p, vec2 toward, float soft) {
  vec2 q = p.xy + max(castH - p.z, 0.0) * toward;
  float blur = 0.002 + 0.0015 * soft;
  float s = max(max(inWindow(q, w0, blur), inWindow(q, w1, blur)), max(inWindow(q, w2, blur), inWindow(q, w3, blur)));
  s = max(s, max(max(inWindow(q, w4, blur), inWindow(q, w5, blur)), max(inWindow(q, w6, blur), inWindow(q, w7, blur))));
  return castAmt * s;
}

// The room can ride up and down like a lift. At every floor a slab goes by
// outside the window: how much of the light bound for height y it lets
// past. At rest the slab stands clear of the window.
float shaft(float y, float blur) {
  float g = abs(fract((y - room.z + 0.475) / FLOOR + lift) - 0.5);
  float b = blur / FLOOR;
  return 1.0 - smoothstep(0.45 - b, 0.45 + b, g);
}

// How far inside a tunnel the train is at X along the track.
float tunnel(float X, float blur) {
  float f = fract(X / TUNNEL_EVERY) * TUNNEL_EVERY;
  float from = TUNNEL_EVERY - TUNNEL_LONG;
  return smoothstep(from - blur, from + blur, f) * (1.0 - smoothstep(TUNNEL_EVERY - 2.0 * blur, TUNNEL_EVERY, f));
}

// The roll of a ship in a swell.
float roll() {
  return 0.055 * sin(time * 0.47) + 0.02 * sin(time * 0.83 + 1.0);
}

// A room that travels turns under its light: the light as it stands to the
// room this moment.
vec4 swayed(vec4 geo) {
  if (motion < 1.5) return geo;
  if (motion < 2.5) {
    geo.y += 0.006 * sin(time * 3.7) * sin(time * 0.61);
  } else if (motion < 3.5) {
    geo.y += roll();
    geo.x *= 1.0 + 0.07 * sin(time * 0.29 + 2.0);
  } else {
    // The car turns under the sun: the light comes in at another angle by
    // as much as the car has turned, and stays there until it turns again.
    // It rolls a little the way it is pressed, and hums the more the faster
    // it goes.
    geo.x = tan(clamp(atan(geo.x) + race.y, 0.03, 1.25));
    geo.y += 0.03 * track.w + 0.0010 * race.z * sin(time * 37.0) * sin(time * 5.1);
  }
  return geo;
}

// The share of one light that arrives at point P of the room (z = distance
// out from the wall) through the window and past everything in it.
float shed(vec3 p, vec4 geo) {
  float sunK = max(geo.x, 1e-3);
  float soft = geo.z;
  float winX = room.y + WIN_GAP;
  vec2 WIN_Y = room.zw;

  // back toward the light until we cross the window plane
  float t = (winX - p.x) / sunK;
  float qz = p.z + t;
  float qy = p.y + (winX - p.x) * geo.y;

  // The sun is a disc half a degree across, so an edge is smeared over a
  // width that grows with the way the light still has to go: e up the window,
  // eW along it, where the slanting light stretches everything.
  float len = sqrt(1.0 + sunK * sunK * (1.0 + geo.y * geo.y));
  float e = soft * (0.0008 + 0.0047 * t * len);
  float eW = e * len / max(sunK, 0.1);

  // a train runs into a tunnel: its mouth crosses the window and shuts the day out
  bool train = motion > 1.5 && motion < 2.5;
  // Several windows stand in a row with a pier between each two: which of
  // them this light comes through, and from here on where in that one. What
  // is outside goes by the place along the whole wall.
  float nth = clamp(floor((qz - WIN_Z.x + 0.5 * (win.z - win.y)) / win.z), 0.0, win.w - 1.0);
  float qzAll = qz;
  qz -= nth * win.z;

  float along = time * SPEED + qzAll;
  // and a racing car into the tunnel of its track; where along the lap this
  // light comes past
  bool racer = motion > 3.5;
  float lapAt = mod(race.x + qzAll + 1.2 / sunK, track.x);
  float shut = nearby > 0.5 ? 0.0 : train ? tunnel(along + 0.3 / sunK, eW + 0.03)
             : racer ? box(lapAt, track.yz, eW + 0.06) : 0.0;

  // the air and the wall scatter a little of the light out round the patch
  haze = box(qz, WIN_Z, eW + 0.20) * box(qy, WIN_Y, e + 0.09) * shaft(qy + SHAFT * geo.y, e + 0.09) * (1.0 - shut);

  // the room leans, and the patch with it
  qy += heel * (qz - 0.5 * (WIN_Z.x + WIN_Z.y));

  // most of the room is nowhere near the patch: nothing below matters there
  if (box(qz, WIN_Z, eW + 0.03) * box(qy, WIN_Y, e + 0.02) < 1e-4) {
    glassTint = vec3(1.0);
    return 0.0;
  }

  // old glass is never flat: it bends the light a little and gathers it into
  // faint streaks that run the height of the pane
  vec2 gp = vec2(qz * 2.3 + 13.0 * nth, qy * 0.9); // no two panes alike
  qy += ripple * 0.006 * (fbm(gp * vec2(1.0, 6.0)) - 0.47);
  qz += ripple * 0.016 * (fbm(gp + 7.3) - 0.47);
  float streaks = 1.0 + ripple * 0.30 * (fbm(gp * vec2(3.1, 1.0) + 3.1) - 0.47);

  // the window is set in a wall with some thickness, and the light has to
  // clear the outer edge of the opening as well as the inner one
  float win = box(qz, WIN_Z, eW) * box(qy, WIN_Y, e)
            * box(qz + REVEAL / sunK, WIN_Z, eW) * box(qy + REVEAL * geo.y, WIN_Y, e)
            * shaft(qy + SHAFT * geo.y, e + 0.004) * (1.0 - shut);

  // what stands along the line goes by: masts, each a quick bar of shadow,
  // and now and then trees and houses that take the sun for a while
  if (train && nearby < 0.5) {
    float out_ = 2.0 / sunK;
    float at = along + out_;
    float d = (fract(at / 2.6) - 0.5) * 2.6;
    win *= 1.0 - 0.75 * step(0.4, hash(vec2(floor(at / 2.6), 5.0))) * (1.0 - pastBar(d, 0.035, 0.012 + soft * 0.003 * (t + out_)));
    win *= 1.0 - 0.7 * smoothstep(0.52, 0.70, vnoise(vec2(at * 0.16, 3.0))) * (0.55 + 0.45 * vnoise(vec2(at * 2.4, qy * 5.0)));
  }

  // What stands along a race track, lap after lap. The posts of the catch
  // fence go by too fast to be seen one by one: each is a streak, longer the
  // faster the car goes. Along one stretch the stands shut the sun out but
  // for the gaps between them, which come as flashes; and two bridges cross
  // the track.
  if (racer && nearby < 0.5) {
    float post = (fract(lapAt / 1.5) - 0.5) * 1.5;
    win *= 1.0 - 0.32 * (1.0 - pastBar(post, 0.03, 0.03 + 0.06 * race.z));
    float gap = (fract(lapAt / 3.0) - 0.5) * 3.0;
    win *= 1.0 - 0.93 * box(lapAt, vec2(88.0, 118.0), 0.8) * pastBar(gap, 0.5, 0.08 + 0.10 * race.z);
    win *= 1.0 - 0.9 * (box(lapAt, vec2(178.0, 179.8), 0.25) + box(lapAt, vec2(243.0, 244.8), 0.25));
  }

  // blinds: slats, plus the two lift cords
  float slats = pastSlats((qy - WIN_Y.x) / SLAT_PERIOD, slatsNow, e / SLAT_PERIOD);
  float u = (qz - WIN_Z.x) / (WIN_Z.y - WIN_Z.x);
  float span = WIN_Z.y - WIN_Z.x;
  float cords = pastBar((u - 0.30) * span, 0.003, eW) * pastBar((u - 0.70) * span, 0.003, eW);

  // what stands in the window, in wall-like coordinates so that it reads upright
  vec2 sill = vec2(-(qz - 0.5 * (WIN_Z.x + WIN_Z.y)) * 0.44, qy - WIN_Y.x - 0.17);

  float tall = WIN_Y.y - WIN_Y.x;
  float v = (qy - WIN_Y.x) / tall;
  // what the things at the window let past
  float past = 1.0;

  // the tree is far behind the glass, so its shadow is much softer than
  // anything standing in the window
  float gaps = 1.0;
  if (treeAmt > 0.0) {
    vec2 tc = vec2((qzAll + TREE_DIST / sunK) * 0.5, qy + TREE_DIST * geo.y);
    float tb = soft * 0.003 * (t + TREE_DIST / sunK);
    gaps = canopy(tc, tb);
    // every gap in the leaves is a pinhole that draws the sun on the wall,
    // so when the moon bites into the sun the coins of light become crescents
    if (eclipseAmt > 0.0) gaps *= 1.0 - 0.95 * canopy(tc + vec2(0.030, 0.012) * (1.6 - eclipseAmt), tb);
  }

  // an arched head in place of the square one
  vec2 ac = vec2((u - 0.5) / 0.5, max(v - 0.55, 0.0) / 0.45);
  win *= mix(1.0, 1.0 - smoothstep(1.0 - 5.0 * e, 1.0 + 5.0 * e, dot(ac, ac)), archAmt);

  if (castAmt > 0.0) past *= 1.0 - 0.75 * desktopShadow(p, sunK * vec2(1.0, geo.y), soft);

  glassTint = vec3(1.0);
  if (stainAmt > 0.0) {
    float came;
    vec3 piece = stained(vec2(1.0 - u, v), 0.01 + 2.5 * e, came);
    glassTint = mix(vec3(1.0), piece, stainAmt);
    past *= mix(1.0, came, stainAmt);
  }

  if (rainAmt > 0.0)
    past *= 1.0 - rainAmt * 0.9 * rain(vec2(sill.x + 3.0 * nth, qy)) / (1.0 + 0.3 * (soft - 1.0));

  // the blinds, or the carved screen some themes hang there instead
  float screen = slats * cords;
  if (latticeAmt > 0.5)
    screen = lattice(vec2(sill.x, qy - WIN_Y.x), min(slatsNow / 0.64, 1.25), 0.5 * (e + 0.44 * eW));

  float lit = win * past * screen
            * mix(1.0, 0.06 + 0.94 * gaps, treeAmt);

  // lettering on the glass; the texture is laid out as it reads on the wall
  // kept legible under cloud: the letters blur far less than the window does
  // and it is on the first window that the lettering is
  if (textAmt > 0.0 && nth < 0.5) {
    float et = 0.8 * min(soft, 2.5) * (0.0016 + 0.0011 * t);
    vec2 smear = vec2(et / max(sunK, 0.1) / (WIN_Z.y - WIN_Z.x), et / (WIN_Y.y - WIN_Y.x));
    float letters = lettering(vec2(1.0 - u, 1.0 - v), smear);
    // The letters are cut in film that is not quite opaque, and what the
    // film scatters lies round each of them as a paler edge.
    float round = max(lettering(vec2(1.0 - u, 1.0 - v), smear * 3.0 + 0.004) - letters, 0.0);
    float asShadow = lit * (1.0 - 0.80 * letters) * (1.0 + 0.45 * round);
    float asLight = win * letters;
    lit = mix(lit, mix(asShadow, asLight, textLight), textAmt);
  }

  return lit * streaks;
}

// Specks of dust drifting through the beam, two layers deep.
float motes(vec2 p) {
  float m = 0.0;
  for (int i = 0; i < 2; i++) {
    float fi = float(i);
    vec2 g = p * (26.0 + 17.0 * fi) + time * vec2(0.05 + 0.03 * fi, -0.035) + 31.0 * fi;
    vec2 cell = floor(g);
    vec2 at = fract(g) - 0.5 - 0.7 * (vec2(hash(cell), hash(cell + 5.3)) - 0.5);
    float twinkle = 0.5 + 0.5 * sin(time * 1.3 + 6.283 * hash(cell + 9.1));
    m += step(0.72, hash(cell + 2.7)) * twinkle * (1.0 - smoothstep(0.0, 0.07 - 0.02 * fi, length(at)));
  }
  return m;
}

// --- light --------------------------------------------------------------------

// Daylight that is not the sun: the window as a broad lamp. What a point with
// normal N gets of it, about 1 in the middle of the wall. It is what makes
// the corner beside the window dark and the far wall bright.
float skyFill(vec3 P, vec3 N) {
  float sum = 0.0;
  for (int j = 0; j < 2; j++) {
    for (int i = 0; i < 2; i++) {
      vec3 W = vec3(room.y + WIN_GAP, mix(room.z, room.w, 0.25 + 0.5 * float(j)), mix(ALL_Z.x, ALL_Z.y, 0.25 + 0.5 * float(i)));
      vec3 v = W - P;
      float r2 = dot(v, v);
      sum += max(dot(N, v), 0.0) * max(v.x, 0.0) / (r2 * (r2 + 0.15));
    }
  }
  return 2.4 * sum;
}

// The colour one light lays directly on point P.
vec3 light(vec3 P, vec4 geo, vec4 col) {
  if (col.r + col.g + col.b < 1e-4) return vec3(0.0);
  // shed() leaves the colour of the glass in glassTint, so it goes first
  float share = shed(P, geo);
  // Half in shadow the light is what comes round the edge of things, and
  // that is the redder part of it: every soft edge runs a little warm.
  vec3 edge = share * (1.0 - share) * vec3(0.22, 0.03, -0.16);
  float through = slatsNow * mix(1.0, 0.5, treeAmt) * mix(1.0, 0.6, stainAmt);
  return col.rgb * (glassTint * (share + edge) + 0.03 * through * haze);
}

// What a lit patch at Q (facing NQ) throws back at P (facing N); the last
// term is the little that finds its way round to faces turned away.
float thrown(vec3 P, vec3 N, vec3 Q, vec3 NQ) {
  vec3 v = Q - P;
  float r2 = dot(v, v) + 0.05;
  return (max(dot(N, v), 0.0) * max(-dot(NQ, v), 0.0) / r2 + 0.035) / r2;
}

// Light that reaches P second hand, off the patch a light lays on the wall.
vec3 bounce(vec3 P, vec3 N, vec4 geo, vec4 col) {
  if (col.r + col.g + col.b < 1e-4) return vec3(0.0);
  float k = max(geo.x, 1e-3), mk = geo.y * k;
  float cz = 0.5 * (ALL_Z.x + ALL_Z.y);
  vec3 Q = vec3(max(room.y + WIN_GAP - k * cz, room.x), 0.5 * (room.z + room.w) - mk * cz, 0.0);
  // what the blinds, the leaves and the glass hold back never gets to bounce
  float through = slatsNow * mix(1.0, 0.5, treeAmt) * mix(1.0, 0.6, stainAmt)
                * mix(1.0, mix(0.85, 0.25, textLight), textAmt);
  return col.rgb * thrown(P, N, Q, vec3(0.0, 0.0, 1.0)) * (0.065 * through);
}

// From light to what the screen shows: where lights overlap the picture
// rolls off gently and keeps its colour instead of clipping to white.
vec3 developed(vec3 c) {
  float peak = max(c.r, max(c.g, c.b));
  float over = max(peak - 0.55, 0.0);
  c *= (min(peak, 0.55) + 0.45 * (1.0 - exp(-over / 0.45))) / max(peak, 1e-4);
  return pow(c, vec3(1.0 / 2.2));
}

void main() {
  slatsNow = slatOpen * (1.0 - shut);
  WIN_Z = vec2(win.x, win.x + win.y);
  ALL_Z = vec2(win.x, win.x + (win.w - 1.0) * win.z + win.y);

  // the point of the wall plane this pixel looks through
  vec2 tc = qt_TexCoord0;
  // The bar of the shell lies over the wall: clear, or as a strip of tinted glass.
  float pane = 0.0;  // 1 under a tinted bar
  if (bar.x > 0.5 && bar.z > 0.5) {
    float into = bar.x < 1.5 ? bar.y - tc.y : bar.x < 2.5 ? tc.y - 1.0 + bar.y : bar.x < 3.5 ? bar.y - tc.x : tc.x - 1.0 + bar.y;
    pane = step(0.0, into);
  }

  vec2 s = vec2(rect.x + tc.x * rect.z, rect.y - tc.y * rect.w);

  vec3 P = vec3(s, 0.0);
  vec3 N = vec3(0.0, 0.0, 1.0);

  // a cloud crossing the sun takes most of it away for a while
  float cover = 1.0;
  if (drift > 0.0) cover -= 0.8 * drift * smoothstep(0.45, 0.62, vnoise(vec2(time * 0.045, 3.7)));

  // each light as it comes to this point of the wall
  bool train = motion > 1.5 && motion < 2.5;
  heel = train ? 0.004 * sin(time * 2.3) * sin(time * 0.37) : motion > 3.5 ? 0.06 * track.w + 0.0012 * race.z * sin(time * 29.0)
       : motion > 2.5 ? 0.6 * roll() : 0.0;
  // how far in a tunnel the room is as a whole
  float buried = train ? tunnel(time * SPEED + 0.5 * (ALL_Z.x + ALL_Z.y), 0.8)
               : motion > 3.5 ? box(mod(race.x + 0.5 * (ALL_Z.x + ALL_Z.y), track.x), track.yz, 0.8) : 0.0;
  vec4 g0 = swayed(geo0), g1 = swayed(geo1), g2 = swayed(geo2), g3 = swayed(geo3);

  // out of a tunnel the day is too bright for a moment
  cover *= 1.0 + 0.9 * race.w;

  // a racing car can turn until the sun is behind the wall its windows are in
  float d0In = motion > 3.5 ? smoothstep(0.03, 0.14, atan(geo0.x) + race.y) : 1.0;
  float d1In = motion > 3.5 ? smoothstep(0.03, 0.14, atan(geo1.x) + race.y) : 1.0;
  float d2In = motion > 3.5 ? smoothstep(0.03, 0.14, atan(geo2.x) + race.y) : 1.0;
  float d3In = motion > 3.5 ? smoothstep(0.03, 0.14, atan(geo3.x) + race.y) : 1.0;

  vec3 d0 = light(P, g0, col0) * cover * d0In;
  vec3 d1 = light(P, g1, col1) * d1In;
  vec3 d2 = light(P, g2, col2) * d2In;
  vec3 d3 = light(P, g3, col3) * d3In;
  nearby = 1.0;
  vec3 d4 = light(P, geo4, col4);
  nearby = 0.0;

  // Where the patch has already been today the wall is left a shade warmer.
  // The patch covers a point while k lies in a certain span; how much of that
  // span the sun has swept since sunrise is how long the point was lit.
  vec3 trace = vec3(0.0);
  if (trailAmt > 0.0) {
    float reach = (room.y + WIN_GAP - P.x);
    float span = room.y - room.x;
    float kRise = (0.02 + 0.26 * span) / 1.7, kSet = (0.02 + 0.64 * span) / 1.7;
    float lo = max(reach / ALL_Z.y, kRise), hi = min(reach / ALL_Z.x, max(geo0.x, kRise));
    float dwell = clamp((hi - lo) / (0.2 * (kSet - kRise)), 0.0, 1.0);
    float qy = P.y + reach * geo0.y;
    trace = trailAmt * 0.05 * white.rgb * dwell * box(qy, room.zw, 0.03);
  }

  vec3 col = d0 + d1 + d2 + d3 + d4 + trace;

  // the light without a direction, and the daylight the window spreads
  // between floors the shaft shuts some of that daylight out
  float open = 0.25 * (shaft(mix(room.z, room.w, 0.125), 0.06) + shaft(mix(room.z, room.w, 0.375), 0.06)
                     + shaft(mix(room.z, room.w, 0.625), 0.06) + shaft(mix(room.z, room.w, 0.875), 0.06))
             * (1.0 - buried);
  vec3 around = ambient.rgb * (1.0 - sky.w) + sky.rgb * (sky.w * skyFill(P, N) * open);
  col += around + bounce(P, N, g0, col0) * cover * open + bounce(P, N, g1, col1) * open
       + bounce(P, N, g2, col2) + bounce(P, N, g3, col3) + bounce(P, N, geo4, col4);

  if (dust > 0.0 && d0.r + d0.g + d0.b > 1e-4) col += dust * d0 * 0.5 * motes(s);

  // the light alone, before the picture takes its share of it
  vec3 lit = col;

  // the light falls on the picture
  if (wallMix > 0.0) {
    float shape = rect.z / max(rect.w, 1e-3);
    float fill = wallAspect / shape;
    vec2 wuv = (tc - 0.5) * (fill < 1.0 ? vec2(1.0, fill) : vec2(1.0 / fill, 1.0));
    vec3 picture = pow(textureLod(wallTex, wuv + 0.5, 0.0).rgb, vec3(2.2));
    if (wallFade < 1.0) {
      // a new one opens over the old from the middle outward, on a slant
      fill = wallAspectOld / shape;
      wuv = (tc - 0.5) * (fill < 1.0 ? vec2(1.0, fill) : vec2(1.0 / fill, 1.0));
      vec3 old = pow(textureLod(wallOld, wuv + 0.5, 0.0).rgb, vec3(2.2));
      float lean = 0.18 / shape;
      float away = abs(tc.x - 0.5 + lean * (tc.y - 0.5)) / (0.5 + 0.5 * lean);
      picture = mix(old, picture, smoothstep(away - 0.05, away + 0.05, wallFade * 1.10 - 0.05));
    }
    // The picture keeps its own colours. Out of the light it stands a little
    // lower, by day hardly at all, and the light lifts it from there; the
    // theme gives the light its colour and the shade a breath of its own.
    // How far there is to go depends on the picture as a whole, read from its
    // smallest copy: a dark one would swallow the light, so some of it lies
    // on top as a veil, and a pale one has no room left above it, so its
    // shade is set lower.
    float key = dot(pow(textureLod(wallTex, vec2(0.5), 16.0).rgb, vec3(2.2)), vec3(0.2126, 0.7152, 0.0722));
    float dark = 1.0 - smoothstep(0.02, 0.22, key), pale = smoothstep(0.30, 0.70, key);
    vec3 gain = max((col - ambient.rgb) / max(white.rgb - ambient.rgb, 1e-3), -0.25);
    float dim = dot(ambient.rgb, vec3(0.2126, 0.7152, 0.0722));
    vec3 breath = mix(vec3(1.0), ambient.rgb / max(dim, 1e-4), 0.30);
    // shut in a tunnel, the picture has little left
    float low = shade * mix(1.0, 0.66, pale) * (0.5 + 0.5 * open);
    col = mix(col, picture * (low * breath + (1.42 - low) * gain) + (0.05 + 0.13 * dark) * max(gain, 0.0), wallMix);
  }

  col = developed(col);
  // black and white film: no colour and a harder step from shadow to light
  if (monoAmt > 0.0) {
    float grey = dot(col, vec3(0.2126, 0.7152, 0.0722));
    col = mix(col, vec3(mix(grey, smoothstep(0.02, 0.98, grey), 0.6)), monoAmt);
  }

  // no wall is one even colour: the mottling of the plaster under the picture
  if (grain > 0.0) col *= 1.0 + grain * (fbm(s * 5.0) * 0.6 + fbm(s * 42.0) * 0.4 - 0.5);

  // a lens gives a little less at the edges of the frame
  vec2 off = qt_TexCoord0 - 0.5;
  col *= 1.0 - 0.22 * dot(off, off);

  // the tint of the bar
  if (pane > 0.5) col = mix(col, barTint.rgb, 0.62);

  // triangular dither so the long gradients do not band on 8-bit panels
  float n = hash(gl_FragCoord.xy) + hash(gl_FragCoord.xy + 31.7) - 1.0;
  col += n / 255.0;

  fragColor = vec4(col, 1.0) * qt_Opacity;
}
