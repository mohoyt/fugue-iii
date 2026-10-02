-- fugue.lua
-- multi-playhead piano roll for monome iii (16x8 grid)
-- inspired by Alexandernaut's Fugue Machine
--
-- rows 1-7 : pattern (row 7 = lowest scale degree, row 1 = highest)
-- row 8    : controls
--   1-4  tap = mute/unmute playhead, hold = edit that playhead
--   6    hold + press a column in rows 1-7 = set pattern length
--   6+8  hold 6 and press 8 = clear pattern
--   10   save (pset 1)      11  load (pset 1)
--   12   hold = global settings page
--   13   reset playheads    14  tempo -5    15  tempo +5
--   16   play / stop
--
-- edit page (while holding a playhead key):
--   row 1  speed      cols 1-8 : 1/4 1/2 3/4 1 3/2 2 3 4
--   row 2  direction  cols 1-4 : fwd rev pingpong random
--   row 3  octave     cols 1-5 : -2 .. +2 (col 3 = 0)
--   row 4  transpose  cols 1-16: scale degrees -7 .. +8 (col 8 = 0)
--   row 5  midi ch    cols 1-16
--   row 6  gate       cols 1-8 : 1/8 .. 8/8 of the step
--
-- global page (while holding 12):
--   row 1  scale      cols 1-8 : maj min dor phr lyd mix loc harm-min
--   row 2  root note  cols 1-12: C .. B
--   row 3  root oct   cols 1-6 : octave 1 .. 6 (col 3 = C3)
--   row 4  velocity   cols 1-16: 8 .. 127
--   row 5  clock      col 1 = internal, col 2 = internal + send midi clock,
--                     col 3 = follow external midi clock

-- ===== config =====
SCALE = {0,2,4,5,7,9,11}   -- major; e.g. minor = {0,2,3,5,7,8,10}
ROOT  = 48                 -- midi note for row 7 (C3)
BPM   = 110
VEL   = 100
PPS   = 12                 -- ticks per 1x step (1x step = 16th note)
CLOCK = 1                  -- 1 internal, 2 internal + send midi clock,
                           -- 3 follow external midi clock

SPEEDS = {48,24,16,12,8,6,4,3}  -- ticks per step, 1/4x .. 4x

SCALES = {
  {0,2,4,5,7,9,11},  -- major
  {0,2,3,5,7,8,10},  -- natural minor
  {0,2,3,5,7,9,10},  -- dorian
  {0,1,3,5,7,8,10},  -- phrygian
  {0,2,4,6,7,9,11},  -- lydian
  {0,2,4,5,7,9,10},  -- mixolydian
  {0,1,3,5,6,8,10},  -- locrian
  {0,2,3,5,7,8,11},  -- harmonic minor
}

-- ===== state =====
local W, ROWS = 16, 7

pat = {}
for x=1,W do
  pat[x] = {}
  for y=1,ROWS do pat[x][y] = false end
end
len = 16

heads = {
  {speed=4, dir=1, oct=0,  deg=0, ch=1, gate=4, on=true},
  {speed=2, dir=2, oct=-1, deg=0, ch=2, gate=6, on=true},
  {speed=6, dir=1, oct=1,  deg=0, ch=3, gate=3, on=false},
  {speed=3, dir=3, oct=0,  deg=2, ch=4, gate=4, on=false},
}

-- index into SCALES, or nil if SCALE above is a custom scale
scale_i = nil
for i, sc in ipairs(SCALES) do
  if table.concat(sc, ",") == table.concat(SCALE, ",") then scale_i = i end
end

playing   = true
held_glob = false
held_head = nil
held_time = 0
edited    = false
len_held  = false
dirty     = true

math.randomseed(math.floor(get_time() * 1000000))
pset_init("fugue")

-- ===== helpers =====
local function clampn(n, lo, hi)
  if n < lo then return lo elseif n > hi then return hi else return n end
end

local function reset_head(h)
  h.count = 0
  h.off = 0
  h.pp = 1
  if h.dir == 2 then h.pos = len + 1 else h.pos = 0 end
end

local function release(h)
  local t = h.notes
  for i=#t,1,-1 do
    midi_note_off(t[i], 0, h.ch)
    t[i] = nil
  end
end

local function release_all()
  for _, h in ipairs(heads) do release(h) end
end

-- ===== midi clock out =====
-- 24 pulses per quarter = 6 per 16th = one pulse every PPS/6 ticks
local CLK, START, CONT, STOP = 0xF8, 0xFA, 0xFB, 0xFC
ctick = 0
fresh = true  -- playheads are at the start; play sends start, not continue

local function clock_send(b)
  if CLOCK == 2 then midi_out({b}) end
end

local function reset_all()
  release_all()
  for _, h in ipairs(heads) do reset_head(h) end
  -- everything is back at step 1, so tell followers to start over too
  ctick = 0
  fresh = true
  if playing then clock_send(START); fresh = false end
  dirty = true
end

for _, h in ipairs(heads) do h.notes = {}; reset_head(h) end

local function note_for(row, h)
  local d = (ROWS - row) + h.deg
  local n = #SCALE
  local o = math.floor(d / n)
  local s = SCALE[(d % n) + 1]
  return clampn(ROOT + s + 12 * (o + h.oct), 0, 127)
end

local function advance(h)
  if h.dir == 1 then
    h.pos = h.pos + 1
    if h.pos > len then h.pos = 1 end
  elseif h.dir == 2 then
    h.pos = h.pos - 1
    if h.pos < 1 then h.pos = len end
  elseif h.dir == 3 then
    h.pos = h.pos + h.pp
    if h.pos > len then
      h.pp = -1; h.pos = math.max(1, len - 1)
    elseif h.pos < 1 then
      h.pp = 1; h.pos = math.min(len, 2)
    end
  else
    h.pos = math.random(1, len)
  end
  if h.pos > len then h.pos = ((h.pos - 1) % len) + 1 end
end

local function play_step(h)
  for row=1,ROWS do
    if pat[h.pos][row] then
      local n = note_for(row, h)
      midi_note_on(n, VEL, h.ch)
      table.insert(h.notes, n)
    end
  end
end

-- ===== clock =====
local function tick_time()
  return 60 / BPM / 4 / PPS
end

next_t = 0

local function clock_step()
  if ctick % math.floor(PPS / 6) == 0 then clock_send(CLK) end
  ctick = ctick + 1
  for _, h in ipairs(heads) do
    -- gate off first, so a full-length gate releases before the next note
    if h.off > 0 then
      h.off = h.off - 1
      if h.off == 0 then release(h) end
    end
    h.count = h.count - 1
    if h.count <= 0 then
      local steplen = SPEEDS[h.speed]
      h.count = steplen
      advance(h)
      if h.on then
        release(h)
        play_step(h)
        h.off = math.max(1, math.floor(steplen * h.gate / 8))
      end
      dirty = true
    end
  end
end

-- ===== external clock =====
-- each incoming pulse is PPS/6 ticks: the first runs straight away, the
-- rest are spread over the time until the next pulse, using the measured
-- time between pulses. the metro just polls for those spread-out ticks.
local POLL = 0.002
ext_last   = nil    -- time of the last pulse
ext_period = nil    -- smoothed time between pulses
ext_left   = 0      -- ticks still due before the next pulse
ext_next   = 0      -- when the next of those is due
ext_lost   = false  -- pulses stopped arriving while playing

local function ext_pulse(now)
  if ext_last then
    local dt = now - ext_last
    -- longer gaps are the source stopping, not a tempo
    if dt < 0.25 then
      ext_period = ext_period and (ext_period * 0.75 + dt * 0.25) or dt
    end
  end
  ext_last = now
  ext_lost = false
  if not playing then return end
  -- a pulse came before its spread-out ticks ran: catch up first
  while ext_left > 0 do clock_step(); ext_left = ext_left - 1 end
  clock_step()
  local k = math.floor(PPS / 6)
  local step = (ext_period or tick_time() * k) / k
  ext_left = k - 1
  ext_next = now + step
end

local function ext_poll()
  local now = get_time()
  local k = math.floor(PPS / 6)
  local step = (ext_period or tick_time() * k) / k
  while ext_left > 0 and now >= ext_next do
    clock_step()
    ext_left = ext_left - 1
    ext_next = ext_next + step
  end
  -- source unplugged or stopped without sending stop: don't leave notes hanging
  if playing and not ext_lost and ext_last and now - ext_last > 0.5 then
    release_all(); ext_left = 0; ext_lost = true
  end
end

function event_midi(a)
  if CLOCK ~= 3 then return end
  if a == CLK then ext_pulse(get_time())
  elseif a == START then playing = true; ext_left = 0; reset_all()
  elseif a == CONT then playing = true; dirty = true
  elseif a == STOP then playing = false; ext_left = 0; release_all(); dirty = true
  end
end

-- the metro can fire late when the grid is busy; instead of losing those
-- ticks, run as many clock steps as real time says are due
function tick()
  if CLOCK == 3 then ext_poll(); return end
  local now = get_time()
  local tt = tick_time()
  local n = 0
  while now >= next_t and n < 16 do
    clock_step()
    next_t = next_t + tt
    n = n + 1
  end
  if now >= next_t then next_t = now + tt end  -- far behind: resync
end

local function set_tempo()
  if CLOCK ~= 3 then m.time = tick_time() end
  print("bpm " .. BPM)
end

local function set_clock(c)
  if c == CLOCK then return end
  local was = CLOCK
  if was == 2 and playing then clock_send(STOP) end
  CLOCK = c
  ext_left = 0
  if c == 3 then
    -- stop and wait for the external start (or ▶)
    playing = false; release_all()
    m.time = POLL; m:start()
  elseif was == 3 then
    playing = false; release_all(); m:stop()
    -- carry the external tempo over
    if ext_period then
      BPM = clampn(math.floor(60 / (ext_period * 24) + 0.5), 20, 300)
    end
    set_tempo()
  elseif c == 2 and playing then
    -- followers joining mid-pattern can only lock to tempo, not position
    clock_send(CONT)
  end
  dirty = true
end

-- ===== save / load =====
local function save()
  local t = {len=len, bpm=BPM, root=ROOT, vel=VEL, scale=scale_i,
             clk=CLOCK, p={}, h={}}
  for x=1,W do
    for y=1,ROWS do t.p[#t.p+1] = pat[x][y] and 1 or 0 end
  end
  for _, h in ipairs(heads) do
    local v = {h.speed, h.dir, h.oct, h.deg, h.ch, h.gate, h.on and 1 or 0}
    for _, n in ipairs(v) do t.h[#t.h+1] = n end
  end
  pset_write(1, t)
  print("saved")
end

local function load()
  local t = pset_read(1)
  if not t or not t.p then print("nothing saved"); return end
  release_all()
  len = t.len or 16
  BPM = t.bpm or BPM
  ROOT = t.root or ROOT
  VEL = t.vel or VEL
  if t.clk then set_clock(t.clk) end
  if t.scale and SCALES[t.scale] then scale_i = t.scale; SCALE = SCALES[t.scale] end
  local i = 1
  for x=1,W do
    for y=1,ROWS do pat[x][y] = (t.p[i] == 1); i = i + 1 end
  end
  i = 1
  for _, h in ipairs(heads) do
    h.speed, h.dir, h.oct, h.deg = t.h[i], t.h[i+1], t.h[i+2], t.h[i+3]
    h.ch, h.gate, h.on = t.h[i+4], t.h[i+5], (t.h[i+6] == 1)
    i = i + 7
  end
  set_tempo()
  reset_all()
  print("loaded")
end

-- ===== drawing =====
local function draw_controls()
  for i, h in ipairs(heads) do
    local b = h.on and 8 or 2
    if held_head == i then b = 15 end
    grid_led(i, 8, b)
  end
  grid_led(6, 8, len_held and 15 or 4)
  if len_held then grid_led(8, 8, 6) end
  grid_led(10, 8, 3)
  grid_led(11, 8, 3)
  grid_led(12, 8, held_glob and 15 or 3)
  grid_led(13, 8, 3)
  local tb = CLOCK == 3 and 1 or 3  -- tempo keys do nothing on external clock
  grid_led(14, 8, tb)
  grid_led(15, 8, tb)
  grid_led(16, 8, playing and 12 or 4)
end

local function draw_pattern()
  for x=1,W do
    for y=1,ROWS do
      if pat[x][y] then grid_led(x, y, x <= len and 5 or 2) end
    end
    if len_held and x == len then
      for y=1,ROWS do grid_led(x, y, 3, true) end
    end
  end
  for _, h in ipairs(heads) do
    if h.on and h.pos >= 1 and h.pos <= len then
      for y=1,ROWS do
        grid_led(h.pos, y, pat[h.pos][y] and 10 or 4, true)
      end
    end
  end
end

local function draw_edit(h)
  for x=1,8 do grid_led(x, 1, x == h.speed and 15 or 3) end
  for x=1,4 do grid_led(x, 2, x == h.dir and 15 or 3) end
  for x=1,5 do grid_led(x, 3, (x - 3) == h.oct and 15 or (x == 3 and 6 or 3)) end
  for x=1,16 do grid_led(x, 4, (x - 8) == h.deg and 15 or (x == 8 and 6 or 2)) end
  for x=1,16 do grid_led(x, 5, x == h.ch and 15 or 2) end
  for x=1,8 do grid_led(x, 6, x <= h.gate and 10 or 2) end
end

local BLACK = {[2]=true, [4]=true, [7]=true, [9]=true, [11]=true}

local function draw_global()
  for x=1,8 do grid_led(x, 1, x == scale_i and 15 or 3) end
  local pc, oct = ROOT % 12, math.floor(ROOT / 12) - 1
  for x=1,12 do grid_led(x, 2, (x - 1) == pc and 15 or (BLACK[x] and 2 or 5)) end
  for x=1,6 do grid_led(x, 3, x == oct and 15 or (x == 3 and 6 or 3)) end
  local v = math.ceil(VEL / 8)
  for x=1,16 do grid_led(x, 4, x <= v and 10 or 2) end
  for x=1,3 do grid_led(x, 5, x == CLOCK and 15 or 3) end
end

function redraw()
  grid_led_all(0)
  if held_glob then draw_global()
  elseif held_head then draw_edit(heads[held_head])
  else draw_pattern() end
  draw_controls()
  grid_refresh()
  dirty = false
end

-- ===== input =====
local function edit(h, x, y)
  if y == 1 and x <= 8 then h.speed = x
  elseif y == 2 and x <= 4 then
    h.dir = x
    if h.pos > len then h.pos = len end
  elseif y == 3 and x <= 5 then h.oct = x - 3
  elseif y == 4 then h.deg = x - 8
  elseif y == 5 then release(h); h.ch = x
  elseif y == 6 and x <= 8 then h.gate = x
  end
end

-- scale and root changes alter pitches, so release first: a note-off
-- has to match the pitch of its note-on
local function edit_global(x, y)
  if y == 1 and x <= 8 then
    release_all(); scale_i = x; SCALE = SCALES[x]
  elseif y == 2 and x <= 12 then
    release_all(); ROOT = (math.floor(ROOT / 12)) * 12 + (x - 1)
  elseif y == 3 and x <= 6 then
    release_all(); ROOT = (x + 1) * 12 + ROOT % 12
  elseif y == 4 then VEL = math.min(127, x * 8)
  elseif y == 5 and x <= 3 then set_clock(x)
  end
end

function event_grid(x, y, z)
  if y == 8 then
    if x == 12 then
      held_glob = (z == 1)
      -- a playhead key still held underneath shouldn't count as a tap
      if held_glob then edited = true end
    elseif x <= 4 then
      if z == 1 and held_glob then
        -- ignore new playhead presses while the global page is up
      elseif z == 1 then
        held_head = x; held_time = get_time(); edited = false
      elseif held_head == x then
        if not edited and get_time() - held_time < 0.3 then
          local h = heads[x]
          h.on = not h.on
          if not h.on then release(h) end
        end
        held_head = nil
      end
    elseif x == 6 then
      len_held = (z == 1)
    elseif z == 1 then
      if x == 8 and len_held then
        for cx=1,W do for cy=1,ROWS do pat[cx][cy] = false end end
        release_all()
      elseif x == 10 then save()
      elseif x == 11 then load()
      elseif x == 13 then reset_all()
      elseif x == 14 and CLOCK ~= 3 then BPM = math.max(20, BPM - 5); set_tempo()
      elseif x == 15 and CLOCK ~= 3 then BPM = math.min(300, BPM + 5); set_tempo()
      elseif x == 16 then
        playing = not playing
        if CLOCK == 3 then
          -- on external clock, ▶ just decides whether pulses move the playheads
          if not playing then ext_left = 0; release_all() end
        elseif playing then
          clock_send(fresh and START or CONT); fresh = false
          next_t = get_time(); m:start()
        else
          m:stop(); release_all(); clock_send(STOP)
        end
      end
    end
  elseif z == 1 then
    if held_glob then
      edit_global(x, y)
    elseif held_head then
      edit(heads[held_head], x, y); edited = true
    elseif len_held then
      len = x
      for _, h in ipairs(heads) do
        if h.pos > len then h.pos = len end
      end
    else
      pat[x][y] = not pat[x][y]
    end
  end
  dirty = true
end

-- ===== go =====
-- display refresh runs on its own timer at ~30 fps, separate from the clock
disp = metro.init(function() if dirty then redraw() end end, 1/30)
disp:start()

if CLOCK == 3 then playing = false end  -- wait for the external start
if playing then clock_send(START); fresh = false end
next_t = get_time()
m = metro.init(tick, CLOCK == 3 and POLL or tick_time())
m:start()
redraw()
