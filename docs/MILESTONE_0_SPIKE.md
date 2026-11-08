# Milestone 0: Server Authority Spike

_Completed 2026-11-08. Go/no-go test for building Breakaway on Roblox Server Authority (see `PUCK_GAMEPLAY_RESEARCH.md` §5.3 and §8.5)._

## Verdict

**Go on Server Authority, with one condition:** blade-puck contact can't be left to Roblox's collision solver. It needs a deterministic contact model inside our simulation (details below). That's the next step before Milestone 1 builds on top of it.

| Question | Result |
|---|---|
| Do client inputs (including mouse-driven stick aim) reach the server through the Input Action System? | **Yes.** Mouse aim goes through a `Scriptable` InputBinding as an absolute value; the server reads the same value and clamps it. |
| Does your own skater feel instant at 110 ms ping? | **Yes.** First visible movement 16–47 ms after input (one or two frames) at 0 and 110 ms ping. |
| Does skating mispredict? | **No.** 0 mispredictions during skate + sweep + carve tests at 0 ms and at 110 ms ping (±10 ms jitter). |
| Does the stick mispredict? | **Constraint-driven: yes. Velocity-driven: no.** See finding 3. |
| Is a stick-on-puck shot predicted correctly? | **No.** Client and server disagree on shot results, sometimes completely. See finding 4. |

## What was built (throwaway-quality, but structured to be kept)

- **Studio settings:** `Workspace.AuthorityMode = Server`, `Gravity = 32.7`, streaming radius 256/512, `Players.CharacterAutoLoads = false`. Template baseplate/spawn removed.
- **Collision groups:** `Skaters`, `Sticks` (blade), `Shafts`, `Puck`. Sticks and shafts don't hit skaters; shafts don't hit ice or boards.
- **Spike rink:** 160 × 70 stud flat ice with straight boards and glass (`Workspace.Rink`). No corners or goals yet.
- **Puck:** 2× real size cylinder (0.5 × 0.17 studs).
- **Inputs:** `ReplicatedStorage.Inputs.Controls` with Move (WASD), Sprint, Carve, Jump, HardStop (C), ResetPuck (R, dev), StickAim and BladeAngle (both Scriptable). Default keys live on the bindings, ready for a rebinding menu later.
- **Scripts:** see `scripts/`. `Simulation` (+ `SkaterSim`, `StickSim`, `PuckSim`) runs at 60 Hz on both server and client. `PlayerSetup` builds each skater + stick. Client: `CameraController`, `StickInputController`, `DebugOverlay`. `DevTestHarness` (Studio only) lets MCP tests skate and reset positions.

Not in scope and not built: sprint, carve, jump, hard stop, free-look, puck tracking, viewmodel, goals.

## Findings

1. **`AlignPosition.ApplyAtCenterOfMass = true` moves the center of mass to the target, not the attachment.** For a stick (mass up the shaft) that put the blade ~2 studs off target and pressed it into the ice, causing jitter. Fixed (`false`).
2. **A long shaft colliding with the ice can wedge the whole stick.** Moved the shaft to its own collision group that only hits pucks and sticks.
3. **Constraint-driven stick mispredicts; velocity-driven doesn't.**
   - With `AlignPosition`/`AlignOrientation`, the stick mispredicted about once per second during sweeps and turns, even at 0 ms ping. Corrections were small in position (≤0.09 studs, ~2°) but large in velocity (4–7.5 studs/s), which matters because blade velocity is shot power. This matches the "drift in BodyMovers and Constraints" that Roblox staff flagged.
   - Setting the stick's velocities directly in the simulation (a P-controller toward the target, speed-capped) gave **0 mispredictions** at both 0 and 110 ms, with 0.16 studs mean tracking error.
   - `Config.Stick.DriveMode = "Velocity"` is now the default. Constraint mode is kept behind the switch for comparison.
4. **Raw physics contact between blade and puck isn't predictable.** The blade moves ~0.4 studs per 60 Hz step, close to the puck's radius, so the exact contact varies with tiny timing differences. The same scripted swing produced:
   - 0 ms: a 45–52 studs/s shot, but the client's predicted puck velocity differed from the server's by up to 35 studs/s.
   - 110 ms: one run a weak 4 studs/s push (client and server agreed); another run the client predicted a 52 studs/s shot sideways while the server's puck went forward and slowed to 3 studs/s, so the client snapped.

   Puck (the game) hit the same wall and added "a custom physics solver for the puck's exit trajectory". We need the equivalent.
5. **Writing velocity through a non-root part of a welded assembly breaks replication under Server Authority.** Only the root part's state replicates; the welded part's "authoritative" CFrame stayed frozen at spawn, so every frame looked mispredicted. Fix: the blade is now the assembly root (`RootPriority = 10`). Rule going forward: **always write physics state through the assembly root.**
6. **Carving created speed** (skaters hit 54 studs/s leaning on the boards). Fixed: carving can redirect horizontal speed but never increase it.
7. `RunService.Misprediction` is plugin-only, so the in-game overlay can't show it. Measurement happens through MCP (or Studio's visualizer, Ctrl+Shift+F6).

## Measured skating numbers (current Config, for your feel review)

- 0 → 17.5 studs/s in 1 s, 24.8 in 2 s, top speed 30 (~9 m/s).
- Turn rate 150°/s; while carving at speed, velocity trails the heading by ~21°.
- Full stop from top speed: 0.65 s with S.

## Not tested

- Two real clients contesting the puck (milestone 5). Other players' inputs aren't forwarded yet, so their skaters are not predicted locally.
- Packet loss. The simulator caps at 0.5%; worth one run later.
- Feel. Everything above is measured, not judged. You need to play it.

## Recommended next step: deterministic blade-puck contact (Milestone 0b)

Handle blade-puck contact inside `Simulation` instead of leaving it to the collision solver:

1. Each step, sweep the blade from its previous pose to its current pose and test it against the puck (analytic segment-vs-cylinder, or `Shapecast`).
2. On contact, compute the puck's new velocity ourselves: blade velocity at the contact point, blade face normal (which gives us lift from an open blade, decision 5), a restitution factor, and an optional subtle "grip" assist (decision 6).
3. Make the blade and puck not physically collide (collision group), so only our model applies.

Both client and server run the same math on the same state, so predictions match. We also get direct control over shot feel, which we'd want anyway. Roblox physics still handles puck vs ice, boards, nets and bodies.

Done when the scripted shot test gives the same result on client and server at 0 and 110 ms, with 0 or near-0 puck mispredictions.
