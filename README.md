# trifm

3-operator FM voice for norns with a grid 128 step sequencer and arc 4 control. 8 routing algorithms, clock-triggered envelopes, drive + Moog-style low-pass.

## Files

- `trifm.lua` — the norns script (controls, clock, screen)
- `lib/Engine_TriFM.sc` — the SuperCollider engine (sound)
- `trifm_mac_test.scd` (separate download) — same sound engine with a slider window, runs in SuperCollider on a Mac without a norns

## Try it on a Mac today

1. Install SuperCollider from supercollider.github.io
2. Open `trifm_mac_test.scd`, click inside the outer brackets, press Cmd+Return
3. A window with all controls opens; a MIDI keyboard plays it too. Cmd+. stops sound.

## Install on norns

1. Connect norns to WiFi (SYSTEM > WIFI).
2. On the Mac, Finder > Go > Connect to Server (Cmd+K), enter `smb://norns.local`, log in as `we` with password `sleep`.
3. Copy the whole `trifm` folder into `dust/code/`, so you have `dust/code/trifm/trifm.lua` and `dust/code/trifm/lib/Engine_TriFM.sc`.
4. On norns: SYSTEM > RESTART once, so SuperCollider compiles the new engine. Only needed when an engine file is new or changed; Lua edits just need the script reloaded.
5. SELECT > trifm.

For editing on the device, open `http://norns.local` in a browser: that is maiden, the built-in editor with a file browser, code editor and REPL.

## Controls on norns

E1 page · E2 select · E3 change · K2 trigger once · K3 clock run/stop.
Everything is also in the PARAMETERS menu, so it can be MIDI-mapped and saved as PSETs.

## Grid 128 (optional)

- Rows 1–7: 16-step note sequencer. Row 7 is the root, row 1 the 7th scale step up. Press to place or remove a note; while stopped, a press also plays it.
- Row 8: columns 1–8 algorithm, 10–14 clock division (1/32, 1/16, 1/8, 1/4, 1/2), 16 run/stop.
- Hold 16 and press any column: loop length. Hold 16 and press 15: clear the sequence.
- An empty sequence falls back to random notes from the scale (root, scale, pitch spread).

## Arc 4 (optional)

Ring 1 op2 depth · ring 2 op3 depth · ring 3 cutoff · ring 4 env time (scales all envelope times; its ring glows with the envelope).

Pages: MAIN (algorithm with live routing diagram, clock division, tempo, probability, root, scale, pitch spread) · OP 1–3 (ratio, fine, fm depth, attack, decay, curve, env amount, plus op3 feedback; envelope preview with playhead) · OUT (cutoff, resonance, drive, filter env/attack/decay, keytrack, glide, level, pan).

## Algorithms (`a>b` = a modulates b, `|` = separate voices heard together)

| # | name | heard |
|---|------|-------|
| 1 | 3>2>1 | 1 |
| 2 | 2+3>1 | 1 |
| 3 | 3>1+2 | 1, 2 |
| 4 | 2>1 \| 3 | 1, 3 |
| 5 | 3>2>1+2 | 1, 2 |
| 6 | triangle (3>2, 3>1, 2>1) | 1 |
| 7 | 1\|2\|3 additive | 1, 2, 3 |
| 8 | loop (3>2>1, 1 back into 3) | 1 |

## Design notes

- "fm depth" is per operator: how hard that operator modulates whatever it feeds. Op1 only modulates in the loop algorithm.
- "env amount" 0 gives a static level (drones), 1 a fully plucked operator. Each operator has its own envelope, all fired by the same clock tick.
- Op3 feedback is true one-sample feedback (SinOscFB). The loop algorithm feeds op1 into op3's frequency with one control block of delay, so it gets gritty quickly.
- Mono voice: a new trigger retriggers the envelopes and glides to the new pitch.

## Files and license

- `extras/`: browser simulator, studio page, demo of the 8 algorithms and the SuperCollider test file for a Mac. Not needed on norns.
- `LICENSE`: GPL-3.0.
