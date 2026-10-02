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
 8 │ P1 P2 P3 P4   LN    CL    SV LD GL RS T- T+ ▶ │
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
| 12 | GL | Hold to open the global settings page. |
| 13 | RS | Reset all playheads to the start. |
| 14 / 15 | T- / T+ | Tempo down / up by 5 BPM. Dimmed and inactive when following external clock. |
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

### Global page

Hold key 12 in row 8 and the top of the grid shows settings that apply to every playhead. Release the key to go back to the pattern.

| Row | Setting | Keys | Values |
|---|---|---|---|
| 1 | Scale | 1–8 | major, natural minor, dorian, phrygian, lydian, mixolydian, locrian, harmonic minor |
| 2 | Root note | 1–12 | C to B (sharps and flats are lit dimmer, like a piano keyboard) |
| 3 | Root octave | 1–6 | octave 1–6 (key 3 = C3, the default) |
| 4 | Velocity | 1–16 | 8 to 127, in steps of 8 |
| 5 | Clock | 1–3 | internal, internal and send MIDI clock, or follow external MIDI clock |

Changing the scale, root note or octave sends note-offs for anything sounding first, so no notes get stuck. These settings are saved and loaded with SV and LD.

### Clock

Row 5 of the global page picks where timing comes from.

**Internal (key 1).** The grid runs its own clock at the tempo set with T- and T+. This is the default.

**Internal and send clock (key 2).** Same as internal, and the grid also sends MIDI clock. See below.

**External (key 3).** The grid follows MIDI clock from whatever is connected, such as a DAW or a drum machine passed through a computer or USB-MIDI host. Choosing it stops playback and waits:

- **Start** resets the playheads and plays from step 1.
- **Continue** plays from where the playheads are.
- **Stop** stops and sends note-offs for anything sounding.
- **▶** also starts and stops following, for sources that send clock without start messages.
- **T- and T+** do nothing, since the tempo comes from the source.
- If clock stops arriving for half a second, for example because a cable was pulled, all notes are released. Playback picks up again when pulses return.
- Switching back to internal keeps the last tempo that came in.

Each incoming pulse is two of the script's clock ticks. The first runs as soon as the pulse arrives and the second halfway to the next one, timed from the measured gap between pulses, so every playhead speed stays in time, including 4×.

The grid can only receive clock over USB-MIDI. It can't take an analog clock or trigger input.

### MIDI clock out

With key 2 in row 5 of the global page lit, the grid sends MIDI clock (24 pulses per quarter note), so a DAW or drum machine set to follow external clock stays in time with it.

| Action | Message sent |
|---|---|
| ▶ after a reset, or at startup | start |
| ▶ resuming where it stopped | continue |
| ▶ to stop | stop |
| RS, or LD, while playing | start, since the playheads are back at step 1 |

Turning clock out on while playing sends continue, so followers pick up the tempo straight away. They won't know where in the pattern the fugue is until the next start, so press RS to line them up. Turning it off while playing sends stop.

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
| `SCALE` | `{0,2,4,5,7,9,11}` | Starting scale as semitone offsets (major). Can be any scale, not just the eight on the global page; picking a scale on the page replaces it. |
| `ROOT` | `48` | Starting MIDI note for row 7 (C3). |
| `BPM` | `110` | Starting tempo. |
| `VEL` | `100` | Starting note velocity. |
| `PPS` | `12` | Clock ticks per 1× step. Keep it a multiple of 6 so MIDI clock out lines up. |
| `CLOCK` | `1` | Starting clock mode: `1` internal, `2` internal and send MIDI clock, `3` follow external MIDI clock. |

## MIDI routing

The grid shows up as a USB-MIDI device. On a computer, select it as a MIDI input in your DAW or synth apps and route channels 1–4 to whatever instruments you like. To drive DIN hardware without a computer, use a USB-MIDI host box between the grid and the synths.

## Tools

Two helpers for checking MIDI clock, in `tools/`:

- `miditest.lua` runs on the grid and prints the MIDI it receives, counting clock pulses once a second. Upload it with diii and run `require('miditest.lua')`.
- `clocksend.html` sends MIDI clock, start, continue and stop from Chrome, for testing external sync without a DAW. Chrome may block MIDI on a page opened as a local file. If so, serve the folder with `python3 -m http.server 8000` and open `http://localhost:8000/tools/clocksend.html`.

## Credits

Inspired by [Fugue Machine](https://alexandernaut.com/) by Alexandernaut. Built on [iii](https://monome.org/docs/iii/) by monome.

## License

MIT. See [LICENSE](LICENSE).
