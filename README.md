# fugue

A multi-playhead MIDI sequencer for the [monome grid](https://monome.org/docs/grid/) running [iii](https://monome.org/docs/iii/), inspired by Alexandernaut's [Fugue Machine](https://alexandernaut.com/).

You draw one pattern on the grid. Four playheads read that same pattern at the same time, each at its own speed and direction, with its own transposition and MIDI channel. A short phrase played forwards, backwards, at half speed and an octave down, at double speed and a fifth up, turns into a canon, the same way a fugue builds counterpoint from a single subject.

The script runs entirely on the grid. Plug the grid into anything that accepts USB-MIDI and it plays.

## Requirements

- A monome grid with iii support (the 2022 and later RP2040-based grids), 16×8
- Something to receive USB-MIDI: a computer, an iPad, or a USB-MIDI host box for DIN synths

Older grids with an FTDI chip can't run iii or send USB-MIDI themselves. They can run the script through [viii](https://monome.org/docs/iii/), the browser-based iii environment, with MIDI going out through the computer.

## Installing

1. Open [diii](https://monome.org/diii) in a browser and connect the grid.
2. Upload `fugue.lua`.
3. Run it with `require('fugue.lua')`.
4. To have the grid boot straight into it, run `first('fugue.lua')`.

## Grid layout

```
     1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16
   ┌───────────────────────────────────────────────┐
 1 │                                               │  highest scale degree
 2 │                                               │
 3 │              p a t t e r n                    │
 4 │        16 steps × 7 scale degrees             │
 5 │                                               │
 6 │                                               │
 7 │                                               │  root
   ├───────────────────────────────────────────────┤
 8 │ P1 P2 P3 P4 .  LN .  CL .  SV LD .  RS T- T+ ▶ │
   └───────────────────────────────────────────────┘
```

### Pattern (rows 1–7)

Press a key to toggle a note. Each column is a step and each row is a degree of the current scale, with the root on row 7. Several notes in one column play as a chord. Columns beyond the loop length are drawn dimmer and are skipped.

Each active playhead is shown as a lit column. Notes it is currently on light up brightly.

### Control row (row 8)

| Key | Name | Action |
|---|---|---|
| 1–4 | P1–P4 | Tap to mute or unmute that playhead. Hold to open its edit page. |
| 6 | LN | Hold, then press any column in rows 1–7 to set the loop length. |
| 8 | CL | While holding LN, press to clear the pattern. |
| 10 | SV | Save the pattern, settings and tempo. |
| 11 | LD | Load what was saved. |
| 13 | RS | Reset all playheads to the start. |
| 14 / 15 | T- / T+ | Tempo down / up by 5 BPM. |
| 16 | ▶ | Play / stop. Stopping sends note-offs for anything sounding. |

### Edit page

Hold one of keys 1–4 in row 8 and the top of the grid shows that playhead's settings. Release the key to go back to the pattern.

| Row | Setting | Keys | Values |
|---|---|---|---|
| 1 | Speed | 1–8 | ¼, ½, ¾, 1, 1½, 2, 3, 4 × |
| 2 | Direction | 1–4 | forward, reverse, ping-pong, random |
| 3 | Octave | 1–5 | −2 to +2 (key 3 = no shift) |
| 4 | Transpose | 1–16 | −7 to +8 scale degrees (key 8 = no shift) |
| 5 | MIDI channel | 1–16 | channel 1–16 |
| 6 | Gate | 1–8 | note length, from ⅛ to the full step |

Transposition is in scale degrees, not semitones, so a transposed playhead stays in key. A transpose of +4 in a major scale is a diatonic fifth above.

### Default playheads

| | Speed | Direction | Octave | Transpose | Channel | State |
|---|---|---|---|---|---|---|
| P1 | 1× | forward | 0 | 0 | 1 | on |
| P2 | ½× | reverse | −1 | 0 | 2 | on |
| P3 | 2× | forward | +1 | 0 | 3 | muted |
| P4 | ¾× | ping-pong | 0 | +2 | 4 | muted |

## How it works

### Clock

The script runs a fast internal clock of 12 ticks per sixteenth note. Each playhead counts ticks and moves one step when its count runs out, so every speed is a whole number of ticks per step:

| Speed | ¼× | ½× | ¾× | 1× | 1½× | 2× | 3× | 4× |
|---|---|---|---|---|---|---|---|---|
| Ticks per step | 48 | 24 | 16 | 12 | 8 | 6 | 4 | 3 |

Because every playhead counts the same ticks, they stay locked together. A ¾× playhead and a 1× playhead realign every 48 ticks, which is four sixteenths.

The clock is driven by a metro, but timing comes from `get_time()`. On each metro callback the script works out how many ticks are due since the last one and runs all of them. If the grid is busy for a moment, the clock catches up rather than drifting late.

### Display

The LEDs are redrawn by a separate timer at about 30 frames per second, and only when something has changed. Key presses and clock steps just mark the display as out of date. This keeps LED updates from delaying the clock.

At high tempos the fastest playheads can move about once per frame, so they may look as if they skip steps. They don't; the display just can't show every step.

### Notes

Each pattern row is a scale degree. A playhead's note is:

```
degree = (7 − row) + transpose
note   = ROOT + SCALE[degree mod 7] + 12 × (floor(degree / 7) + octave)
```

Notes are clamped to MIDI 0–127. When a playhead lands on a step it sends note-ons for every note in that column, then sends note-offs after its gate time, or at its next step if the gate is full length.

### Directions

- **Forward** and **reverse** wrap around the loop.
- **Ping-pong** bounces off both ends without repeating the end steps.
- **Random** jumps to any step within the loop.

If the loop length is shortened while a playhead is beyond the new end, it is pulled back inside the loop.

## Configuration

These are at the top of `fugue.lua`:

| Variable | Default | Meaning |
|---|---|---|
| `SCALE` | `{0,2,4,5,7,9,11}` | Scale as semitone offsets (major). Minor is `{0,2,3,5,7,8,10}`. |
| `ROOT` | `48` | MIDI note for row 7 (C3). |
| `BPM` | `110` | Starting tempo. |
| `VEL` | `100` | Note velocity. |
| `PPS` | `12` | Clock ticks per 1× step. |

## MIDI routing

The grid shows up as a USB-MIDI device. On a computer, select it as a MIDI input in your DAW or synth apps and route channels 1–4 to whatever instruments you like. To drive DIN hardware without a computer, use a USB-MIDI host box between the grid and the synths.

## Credits

Inspired by [Fugue Machine](https://alexandernaut.com/) by Alexandernaut. Built on [iii](https://monome.org/docs/iii/) by monome.

## License

MIT. See [LICENSE](LICENSE).
