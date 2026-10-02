-- miditest.lua
-- prints the midi that reaches a script, to check whether iii passes
-- clock and transport messages to event_midi
--
-- run it, send midi clock to the grid (e.g. from a daw), press play/stop
-- clock pulses are counted rather than printed, once a second

local names = {[0xFA]="start", [0xFB]="continue", [0xFC]="stop", [0xF2]="song position"}
local pulses, first = 0, true

function event_midi(a, b, c)
  if a == 0xF8 then
    pulses = pulses + 1
    if first then
      print("clock pulse arrived as: " .. tostring(a) .. " " .. tostring(b) .. " " .. tostring(c))
      first = false
    end
  else
    print(string.format("%-14s %s %s %s", names[a] or "",
      tostring(a), tostring(b), tostring(c)))
  end
end

local count = metro.init(function()
  if pulses > 0 then
    print("clock: " .. pulses .. " pulses/sec = " .. (pulses * 60 / 24) .. " bpm")
    pulses = 0
  end
end, 1)
count:start()

print("listening for midi")
