-- trifm
-- 3-operator FM voice
-- grid sequencer + arc
--
-- E1: page
-- E2: select parameter
-- E3: change value
-- K2: trigger once
-- K3: clock run / stop
--
-- GRID 128
-- rows 1-7: 16-step note
--   sequencer (row 7 = root,
--   row 1 = 7th degree up)
-- row 8: 1-8 algorithm,
--   10-14 clock division,
--   15 clear (hold 16),
--   16 run/stop
-- hold 16 + press a column:
--   set loop length
--
-- ARC 4
-- 1 op2 depth  2 op3 depth
-- 3 cutoff     4 env time
--
-- Grid and arc are optional.
-- MIDI notes also play it.

engine.name = "TriFM"

local musicutil = require "musicutil"

---------------------------------------------------------------------------
-- algorithms: must match the Select.kr tables in Engine_TriFM.sc
-- mXY = op X modulates op Y, c = which ops are heard (carriers)
---------------------------------------------------------------------------
local ALGS = {
  {name = "3>2>1",   m32 = 1, m31 = 0, m21 = 1, m13 = 0, c = {1, 0, 0}},
  {name = "2+3>1",   m32 = 0, m31 = 1, m21 = 1, m13 = 0, c = {1, 0, 0}},
  {name = "3>1+2",   m32 = 1, m31 = 1, m21 = 0, m13 = 0, c = {1, 1, 0}},
  {name = "2>1 | 3", m32 = 0, m31 = 0, m21 = 1, m13 = 0, c = {1, 0, 1}},
  {name = "3>2>1+2", m32 = 1, m31 = 0, m21 = 1, m13 = 0, c = {1, 1, 0}},
  {name = "triangle",m32 = 1, m31 = 1, m21 = 1, m13 = 0, c = {1, 0, 0}},
  {name = "1|2|3",   m32 = 0, m31 = 0, m21 = 0, m13 = 0, c = {1, 1, 1}},
  {name = "loop",    m32 = 1, m31 = 0, m21 = 1, m13 = 1, c = {1, 0, 0}},
}
local ALG_NAMES = {}
for i, a in ipairs(ALGS) do ALG_NAMES[i] = a.name end

local RATIOS = {0.25, 0.5, 0.75, 1, 1.5, 2, 2.5, 3, 3.5, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 16}
local RATIO_NAMES = {}
for i, r in ipairs(RATIOS) do RATIO_NAMES[i] = tostring(r) end

-- clock divisions, in beats (1 beat = quarter note)
local DIV_NAMES = {"1/32", "1/24", "1/16", "1/12", "1/8", "1/6", "1/4", "1/2", "1/1", "2/1"}
local DIV_BEATS = {1/8, 1/6, 1/4, 1/3, 1/2, 2/3, 1, 2, 4, 8}
-- the five divisions on grid row 8, columns 10-14
local GRID_DIVS = {1, 3, 5, 7, 8}

local SCALE_NAMES = {}
for i, s in ipairs(musicutil.SCALES) do SCALE_NAMES[i] = s.name end

-- arc ring n turns this param
local ARC_PARAMS = {"op2_depth", "op3_depth", "cutoff", "env_time"}

---------------------------------------------------------------------------
-- state
---------------------------------------------------------------------------
local running = true
local scale_notes = {48}   -- random mode: root + spread
local seq_notes = {48}     -- sequencer: 7 scale degrees
local last_trig = -10
local last_note = 48
local midi_in = nil

-- sequence: seq[step] = scale degree 1..7, or nil for a rest
local seq = {1, nil, 3, nil, 5, nil, 3, 6, 1, nil, 4, nil, 5, 7, nil, 2}
local step = 0

local g = grid.connect()
local a = arc.connect()
local grid_dirty = true
local run_held = false
local run_held_used = false

local page = 1
local sel = {1, 1, 1, 1, 1}

local PAGES = {
  {name = "MAIN",   items = {"alg", "div", "clock_tempo", "length", "prob", "root", "scale", "spread"}},
  {name = "OP 1",   items = {"op1_ratio", "op1_fine", "op1_depth", "op1_atk", "op1_dec", "op1_curve", "op1_envamt"}, op = 1},
  {name = "OP 2",   items = {"op2_ratio", "op2_fine", "op2_depth", "op2_atk", "op2_dec", "op2_curve", "op2_envamt"}, op = 2},
  {name = "OP 3",   items = {"op3_ratio", "op3_fine", "op3_depth", "op3_atk", "op3_dec", "op3_curve", "op3_envamt", "fb"}, op = 3},
  {name = "OUT",    items = {"cutoff", "res", "drive", "fenv", "fatk", "fdec", "ktrack", "env_time", "glide", "amp", "pan"}},
}

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
local function rebuild_scale()
  local root = params:get("root")
  local name = SCALE_NAMES[params:get("scale")]
  scale_notes = musicutil.generate_scale_of_length(root, name, params:get("spread") + 1)
  seq_notes = musicutil.generate_scale_of_length(root, name, 7)
end

local function send_ratio(i)
  local r = RATIOS[params:get("op" .. i .. "_ratio")]
  local cents = params:get("op" .. i .. "_fine")
  engine["r" .. i](r * 2 ^ (cents / 1200))
end

-- envelope times are scaled by the global "env time" macro
local function send_env(i)
  local t = params:get("env_time")
  engine["atk" .. i](params:get("op" .. i .. "_atk") * t)
  engine["dec" .. i](params:get("op" .. i .. "_dec") * t)
end

local function send_fenv()
  local t = params:get("env_time")
  engine.fatk(params:get("fatk") * t)
  engine.fdec(params:get("fdec") * t)
end

local function trigger(note)
  if note == nil then
    note = scale_notes[math.random(#scale_notes)]
  end
  last_note = note
  last_trig = util.time()
  engine.trig(musicutil.note_num_to_freq(note))
end

local function seq_empty()
  for x = 1, 16 do
    if seq[x] then return false end
  end
  return true
end

-- one clock tick: advance the sequencer, or play a random note if it is empty
local function tick()
  step = step % params:get("length") + 1
  grid_dirty = true
  if math.random(100) > params:get("prob") then return end
  if seq_empty() then
    trigger()
  elseif seq[step] then
    trigger(seq_notes[seq[step]])
  end
end

-- same shape as SuperCollider's Env.perc(atk, dec, 1, curve)
local function seg(x, c)
  if math.abs(c) < 0.001 then return x end
  return (1 - math.exp(c * x)) / (1 - math.exp(c))
end

local function env_at(i, t)
  local ts = params:get("env_time")
  local at = params:get("op" .. i .. "_atk") * ts
  local d = params:get("op" .. i .. "_dec") * ts
  local c = params:get("op" .. i .. "_curve")
  local amt = params:get("op" .. i .. "_envamt")
  local e
  if t < 0 then e = 0
  elseif t < at then e = seg(t / at, c)
  elseif t < at + d then e = 1 - seg((t - at) / d, c)
  else e = 0 end
  return (1 - amt) + amt * e
end

---------------------------------------------------------------------------
-- params
---------------------------------------------------------------------------
local function add_params()
  params:add_separator("trifm_sep", "TRIFM")

  params:add_group("trifm_main", "MAIN", 9)
  params:add_option("alg", "algorithm", ALG_NAMES, 1)
  params:set_action("alg", function(v) engine.alg(v - 1); grid_dirty = true end)
  params:add_option("div", "clock division", DIV_NAMES, 3)
  params:set_action("div", function() grid_dirty = true end)
  params:add_number("length", "loop length", 1, 16, 16)
  params:set_action("length", function() grid_dirty = true end)
  params:add_number("prob", "probability", 0, 100, 100, function(p) return p:get() .. "%" end)
  params:add_number("root", "root note", 0, 127, 48,
    function(p) return musicutil.note_num_to_name(p:get(), true) end)
  params:set_action("root", rebuild_scale)
  params:add_option("scale", "scale", SCALE_NAMES, 1)
  params:set_action("scale", rebuild_scale)
  params:add_number("spread", "pitch spread", 0, 24, 7,
    function(p) return p:get() .. " steps" end)
  params:set_action("spread", rebuild_scale)
  params:add_number("midi_dev", "midi in device", 1, 16, 1)
  params:set_action("midi_dev", function(v)
    midi_in = midi.connect(v)
    midi_in.event = function(data)
      local msg = midi.to_msg(data)
      if msg.type == "note_on" and msg.vel > 0 then trigger(msg.note) end
    end
  end)
  params:add_control("glide", "glide",
    controlspec.new(0, 2, "lin", 0.01, 0, "s"))
  params:set_action("glide", function(v) engine.glide(v) end)

  local defaults = {
    {ratio = 4,  depth = 0, atk = 0.005, dec = 0.6,  envamt = 1},
    {ratio = 6,  depth = 2, atk = 0.005, dec = 0.3,  envamt = 1},
    {ratio = 8,  depth = 3, atk = 0.005, dec = 0.15, envamt = 1},
  }
  for i = 1, 3 do
    local p = "op" .. i .. "_"
    local d = defaults[i]
    params:add_group("trifm_op" .. i, "OPERATOR " .. i, i == 3 and 8 or 7)
    params:add_option(p .. "ratio", "ratio", RATIO_NAMES, d.ratio)
    params:set_action(p .. "ratio", function() send_ratio(i) end)
    params:add_control(p .. "fine", "fine",
      controlspec.new(-100, 100, "lin", 1, 0, "ct"))
    params:set_action(p .. "fine", function() send_ratio(i) end)
    params:add_control(p .. "depth", "fm depth",
      controlspec.new(0, 12, "lin", 0.05, d.depth, ""))
    params:set_action(p .. "depth", function(v) engine["depth" .. i](v) end)
    params:add_control(p .. "atk", "attack",
      controlspec.new(0.001, 4, "exp", 0, d.atk, "s"))
    params:set_action(p .. "atk", function() send_env(i) end)
    params:add_control(p .. "dec", "decay",
      controlspec.new(0.01, 8, "exp", 0, d.dec, "s"))
    params:set_action(p .. "dec", function() send_env(i) end)
    params:add_control(p .. "curve", "curve",
      controlspec.new(-8, 8, "lin", 0.5, -4, ""))
    params:set_action(p .. "curve", function(v) engine["curve" .. i](v) end)
    params:add_control(p .. "envamt", "env amount",
      controlspec.new(0, 1, "lin", 0.01, d.envamt, ""))
    params:set_action(p .. "envamt", function(v) engine["envamt" .. i](v) end)
    if i == 3 then
      params:add_control("fb", "feedback",
        controlspec.new(0, 3, "lin", 0.01, 0, ""))
      params:set_action("fb", function(v) engine.fb(v) end)
    end
  end

  params:add_group("trifm_out", "FILTER / OUT", 10)
  params:add_control("cutoff", "cutoff",
    controlspec.new(20, 18000, "exp", 0, 2000, "Hz"))
  params:set_action("cutoff", function(v) engine.cutoff(v) end)
  params:add_control("res", "resonance",
    controlspec.new(0, 1, "lin", 0.01, 0.2, ""))
  params:set_action("res", function(v) engine.res(v) end)
  params:add_control("drive", "drive",
    controlspec.new(0.5, 10, "exp", 0, 1, ""))
  params:set_action("drive", function(v) engine.drive(v) end)
  params:add_control("fenv", "filter env",
    controlspec.new(-4, 6, "lin", 0.1, 2, "oct"))
  params:set_action("fenv", function(v) engine.fenv(v) end)
  params:add_control("fatk", "filter attack",
    controlspec.new(0.001, 4, "exp", 0, 0.005, "s"))
  params:set_action("fatk", send_fenv)
  params:add_control("fdec", "filter decay",
    controlspec.new(0.01, 8, "exp", 0, 0.3, "s"))
  params:set_action("fdec", send_fenv)
  params:add_control("ktrack", "keytrack",
    controlspec.new(0, 1, "lin", 0.01, 0.5, ""))
  params:set_action("ktrack", function(v) engine.ktrack(v) end)
  params:add_control("env_time", "env time",
    controlspec.new(0.25, 4, "exp", 0, 1, "x"))
  params:set_action("env_time", function()
    for i = 1, 3 do send_env(i) end
    send_fenv()
  end)
  params:add_control("amp", "level",
    controlspec.new(0, 1, "lin", 0.01, 0.6, ""))
  params:set_action("amp", function(v) engine.amp(v) end)
  params:add_control("pan", "pan",
    controlspec.new(-1, 1, "lin", 0.01, 0, ""))
  params:set_action("pan", function(v) engine.pan(v) end)
end

---------------------------------------------------------------------------
-- grid
---------------------------------------------------------------------------
local function grid_redraw()
  g:all(0)
  local len = params:get("length")
  for x = 1, 16 do
    local in_loop = x <= len
    for y = 1, 7 do
      local deg = 8 - y
      local lvl = 0
      if seq[x] == deg then
        lvl = in_loop and 10 or 3
        if x == step and running then lvl = 15 end
      elseif x == step and running then
        lvl = 3                                   -- playhead column
      elseif in_loop and y == 7 then
        lvl = 1                                   -- faint root row shows loop length
      end
      g:led(x, y, lvl)
    end
  end
  -- row 8: algorithm, division, clear, run
  for x = 1, 8 do
    g:led(x, 8, params:get("alg") == x and 12 or 3)
  end
  for i, d in ipairs(GRID_DIVS) do
    g:led(9 + i, 8, params:get("div") == d and 12 or 3)
  end
  g:led(15, 8, run_held and 6 or 0)
  g:led(16, 8, running and (step % 4 == 1 and 15 or 8) or 3)
  g:refresh()
end

g.key = function(x, y, z)
  if y == 8 and x == 16 then
    -- run/stop toggles on release, unless the key was used as a modifier
    if z == 1 then
      run_held = true
      run_held_used = false
    else
      if not run_held_used then running = not running end
      run_held = false
    end
    grid_dirty = true
    return
  end
  if z == 0 then return end

  if y <= 7 then
    if run_held then
      params:set("length", x)                     -- hold 16 + column: loop length
      run_held_used = true
    else
      local deg = 8 - y
      if seq[x] == deg then seq[x] = nil else seq[x] = deg end
      if seq[x] and not running then trigger(seq_notes[deg]) end   -- audition
    end
  elseif x <= 8 then
    params:set("alg", x)
  elseif x >= 10 and x <= 14 then
    params:set("div", GRID_DIVS[x - 9])
  elseif x == 15 and run_held then
    for i = 1, 16 do seq[i] = nil end             -- hold 16 + press 15: clear
    run_held_used = true
  end
  grid_dirty = true
end

---------------------------------------------------------------------------
-- arc
---------------------------------------------------------------------------
-- each ring shows its value like a knob: 7 o'clock (min) to 5 o'clock (max)
local ARC_START = 41      -- led 1 is 12 o'clock; 41 is 24 leds (135 deg) before it
local ARC_SPAN = 48       -- 48 of 64 leds = 270 degrees

a.delta = function(n, d)
  params:delta(ARC_PARAMS[n], d / 8)
end

local function arc_redraw()
  local pulse = env_at(1, util.time() - last_trig)  -- op1 envelope, for a glow on ring 4
  for n = 1, 4 do
    local v = params:get_raw(ARC_PARAMS[n])
    local tip = math.floor(v * (ARC_SPAN - 1) + 0.5)
    for i = 0, ARC_SPAN - 1 do
      local led = (ARC_START - 1 + i) % 64 + 1
      local lvl = 1
      if i < tip then lvl = 4 elseif i == tip then lvl = 15 end
      if n == 4 and i < tip then lvl = 3 + math.floor(pulse * 6) end
      a:led(n, led, lvl)
    end
    for i = ARC_SPAN, 63 do
      a:led(n, (ARC_START - 1 + i) % 64 + 1, 0)
    end
  end
  a:refresh()
end

---------------------------------------------------------------------------
-- init
---------------------------------------------------------------------------
function init()
  add_params()
  params:bang()

  -- sequencer clock
  clock.run(function()
    while true do
      clock.sync(DIV_BEATS[params:get("div")])
      if running then tick() end
    end
  end)

  -- follow external transport (Link / MIDI clock / crow)
  clock.transport.start = function() running = true; grid_dirty = true end
  clock.transport.stop = function() running = false; grid_dirty = true end

  -- screen, grid and arc refresh
  clock.run(function()
    while true do
      clock.sleep(1 / 15)
      redraw()
      if grid_dirty then grid_redraw(); grid_dirty = false end
      arc_redraw()
    end
  end)
end

-- redraw the grid when one is plugged in while the script runs
grid.add = function() grid_dirty = true end

---------------------------------------------------------------------------
-- norns keys and encoders
---------------------------------------------------------------------------
function enc(n, d)
  if n == 1 then
    page = util.clamp(page + d, 1, #PAGES)
  elseif n == 2 then
    sel[page] = util.clamp(sel[page] + d, 1, #PAGES[page].items)
  elseif n == 3 then
    params:delta(PAGES[page].items[sel[page]], d)
  end
end

function key(n, z)
  if z == 0 then return end
  if n == 2 then
    trigger()
  elseif n == 3 then
    running = not running
    grid_dirty = true
  end
end

---------------------------------------------------------------------------
-- screen
---------------------------------------------------------------------------
local NODE = {{96, 46}, {114, 22}, {78, 22}}   -- screen positions of op1, op2, op3

local function arrow(from, to)
  local x1, y1 = NODE[from][1], NODE[from][2]
  local x2, y2 = NODE[to][1], NODE[to][2]
  screen.level(6)
  screen.move(x1, y1)
  screen.line(x2, y2)
  screen.stroke()
  -- direction dot 70% along the way, towards the target
  screen.level(15)
  screen.circle(x1 + (x2 - x1) * 0.7, y1 + (y2 - y1) * 0.7, 1.5)
  screen.fill()
end

local function draw_algorithm()
  local al = ALGS[params:get("alg")]
  local t = util.time() - last_trig
  if al.m32 == 1 then arrow(3, 2) end
  if al.m31 == 1 then arrow(3, 1) end
  if al.m21 == 1 then arrow(2, 1) end
  if al.m13 == 1 then arrow(1, 3) end
  for i = 1, 3 do
    local x, y = NODE[i][1], NODE[i][2]
    if al.c[i] == 1 then -- carrier: line to the output
      screen.level(3)
      screen.move(x, y + 6)
      screen.line(x, 63)
      screen.stroke()
    end
    -- node brightness follows its envelope
    local lvl = math.floor(2 + 13 * env_at(i, t))
    screen.level(0)
    screen.circle(x, y, 6)
    screen.fill()
    screen.level(lvl)
    screen.circle(x, y, 6)
    if al.c[i] == 1 then screen.fill() else screen.stroke() end
    screen.level(al.c[i] == 1 and 0 or lvl)
    screen.move(x, y + 3)
    screen.text_center(i)
  end
  if params:get("fb") > 0 then -- op3 self feedback loop
    screen.level(6)
    screen.circle(NODE[3][1] - 8, NODE[3][2] - 6, 3)
    screen.stroke()
  end
end

local function draw_env(i)
  local x0, y0, w, h = 84, 22, 42, 30
  local ts = params:get("env_time")
  local total = (params:get("op" .. i .. "_atk") + params:get("op" .. i .. "_dec")) * ts
  screen.level(3)
  screen.move(x0, y0 + h)
  screen.line(x0 + w, y0 + h)
  screen.stroke()
  screen.level(12)
  for s = 0, w do
    local y = y0 + h - env_at(i, s / w * total) * h
    if s == 0 then screen.move(x0, y) else screen.line(x0 + s, y) end
  end
  screen.stroke()
  -- playhead
  local t = util.time() - last_trig
  if t < total then
    screen.level(4)
    screen.move(x0 + t / total * w, y0)
    screen.line(x0 + t / total * w, y0 + h)
    screen.stroke()
  end
  screen.level(5)
  screen.move(x0 + w, 62)
  screen.text_right(string.format("%.2fs", total))
end

-- short on-screen labels (full names are in the PARAMETERS menu)
local LABELS = {
  alg = "alg", div = "div", clock_tempo = "bpm", length = "length", prob = "prob",
  root = "root", scale = "scale", spread = "sprd", fb = "fdbk",
  cutoff = "cutoff", res = "reso", drive = "drive", fenv = "f.env",
  fatk = "f.atk", fdec = "f.dec", ktrack = "keytrk", env_time = "env time",
  glide = "glide", amp = "level", pan = "pan",
  ratio = "ratio", fine = "fine", depth = "depth", atk = "atk",
  dec = "dec", curve = "curve", envamt = "env amt",
}

local function label(id)
  return LABELS[id] or LABELS[string.match(id, "^op%d_(.+)$") or ""] or id
end

local function draw_list(items, x_val, rows, max_chars)
  local s = sel[page]
  local first = util.clamp(s - math.floor(rows / 2), 1, math.max(1, #items - rows + 1))
  for r = 0, rows - 1 do
    local idx = first + r
    local id = items[idx]
    if id == nil then break end
    local y = 20 + r * 8
    screen.level(idx == s and 15 or 4)
    screen.move(0, y)
    screen.text(label(id))
    screen.move(x_val, y)
    screen.text_right(string.sub(params:string(id), 1, max_chars))
  end
end

function redraw()
  screen.clear()
  screen.font_face(1)
  screen.font_size(8)

  -- header
  local pg = PAGES[page]
  screen.level(15)
  screen.move(0, 7)
  screen.text(pg.name)
  screen.level(running and 15 or 3)
  screen.move(127, 7)
  screen.text_right(running and ">" or "||")
  screen.level(4)
  screen.move(118, 7)
  screen.text_right(musicutil.note_num_to_name(last_note, true))
  screen.level(2)
  screen.move(0, 10)
  screen.line(127, 10)
  screen.stroke()

  if page == 1 then
    draw_list(pg.items, 68, 6, 7)
    draw_algorithm()
  elseif pg.op then
    draw_list(pg.items, 80, 6, 8)
    draw_env(pg.op)
  else
    draw_list(pg.items, 127, 6, 14)
  end
  screen.update()
end
