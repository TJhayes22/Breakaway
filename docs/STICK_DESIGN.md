# Stick Design

_Living design doc for the hockey stick. Last updated 2026-11-09 (Milestone 0b, part 1)._

This doc records what we've **decided** about the stick and what's still **open**, so changes start from an agreed plan instead of trial and error. Rule going forward: anything that changes what's physical, what collides, or how a system works gets written here and agreed **before** code changes. Feel tuning (numbers) can happen directly.

---

## 1. Goals

1. The stick feels like Puck: the blade goes where the mouse says, the forehand and backhand flip naturally through the middle, and shots come from real stick motion.
2. The stick is a **physical object**: the blade **and shaft** collide with the puck (and later with other sticks), never with skaters.
3. The stick always looks **connected to the player**, at every reach, including max reach ([reference](../reference_images/max_reach_blade_on_ice.png)).
4. It works under Server Authority: client and server compute the same stick each 60 Hz step, so there's no misprediction.

---

## 2. Settled decisions

| Topic | Decision | Where |
|---|---|---|
| Handedness | **Right shot.** Forehand is the right side and gets the wider arc (58° right, 48° left). | `Config.Stick.Handedness`, `ArcRight/ArcLeft` |
| Blade yaw model | From the Puck video. The toe always points away from the middle. **Right of middle:** forehand faces forward. **Left of middle:** backhand faces forward. Crossing the middle, the blade **rotates smoothly** through toe-forward. | `StickSim.computeBladeYaw` |
| Face angle at the sides | Forward face turns **inward** (toward center), up to **30°** at full side reach. | `BLADE_YAW.SideMax` |
| Flip width | The flip happens across lateral −0.15 … +0.15. | `BLADE_YAW.FlipWidth` |
| Pulled back | The blade squares up (face straight ahead), based on depth only, on both sides. | `BLADE_YAW.PullBackFull/Start` |
| Closest blade distance | **2.3 studs** in front of the body (was 3.3). Fully pulled back, the blade sits at the bottom edge of the screen. | `MinBladeForward`, `ReachMin` |
| Stick sensitivity | **0.0018** aim units per pixel (was 0.0028). | `Config.Input` |
| Scroll tilt | Tilts whichever face is forward, in 12.5° steps, ±4 steps. Direction set by playtest: scroll up tilts the forward face **down**. ⚠ See open question Q4. | `StickSim` (`alpha` sign) |
| Lift | Past `LiftStart` the stick swings up around the hands like a baseball bat, toe first, up to 55°. | `LiftPitchMax` |
| Shaft is physical | The shaft collides with the puck and other sticks, never with skaters, ice or boards. (A visual-only shaft was tried and **rejected**, 2026-11-09.) | collision group `Shafts` |
| Drive method | The stick is moved by setting its velocities in the simulation, not by constraints. Constraints mispredicted in Milestone 0. | `Config.Stick.DriveMode = "Velocity"` |
| Debug | **F2** shows lateral/depth, active face (FOREHAND/BACKHAND/flipping), and the toe target vs. the measured toe. | `DebugOverlay` |

---

## 3. How the stick works today

- **One physical assembly:** the blade (the root part) plus a 5-stud shaft **welded** to it at a fixed 40° lie angle.
- **Each step, `StickSim.computeTarget` turns the aim into a target pose for the blade:**
  - **Position:** the arc angle from lateral, the reach from depth.
  - **Orientation:** the yaw model plus the scroll tilt.
  - **Lift:** applied on top.
- `driveByVelocity` then sets the assembly's velocities to pull the blade toward that pose.
- The shaft just comes along, fixed in the blade's frame.

**The problem:** the shaft's angle and length are fixed relative to the blade, so its top lands wherever the blade puts it. At max reach the top is about **2.7 studs in front of the player**, so the stick looks like it's floating. In Puck, the shaft always runs back to the player's hands.

---

## 4. Plan: option B, the stick is posed from two points

The blade target (from the mouse) and the **hands** (a point fixed to the body) together decide where the stick is. The shaft always runs from the blade's heel back to the hands, at any reach and while lifting. This is how Puck's stick works (it has a separate controller pulling the handle toward the hands; see the research doc §3.4).

### 4.1 Hands point (decided Q3: hands move opposite the blade)

- **Base position:** `HandAnchor`, relative to the body center. Starting value **(−0.6, 0.5, −1.1)**: left of center, at chest height, a little forward.
  - With the blade straight ahead at max reach, that puts the butt end at the bottom edge of the screen, matching the reference screenshot. The value was measured on screen during the reverted experiment.
  - Mirrored for a left shot.
- **Movement:** like the Puck video, the hands drift opposite the blade, sideways only:

  `hands.x = HandAnchor.x − HandSwing × bladeTarget.x`, with the shift clamped to ±`HandSwingMax`

  - `bladeTarget.x` is the blade target's sideways offset from the body center, in studs.
  - Starting values: `HandSwing = 0.15` and `HandSwingMax = 1.0`. With the blade far right (~5.5 studs), the hands move ~0.8 studs left. With the blade far left (~4.8), they move ~0.7 right.
- **Computed from the blade's target, not its actual position,** so client and server always agree. The same point is used for the shaft and as the lift pivot.
- **Tuning:** raise `HandSwing` for a stronger cross-body swing; set it to 0 for fixed hands.

### 4.2 The geometry catch (decided Q1: **B2**)

A real stick is rigid: the blade meets the shaft at a fixed angle (the lie). If the shaft has to point at the hands, its slope changes with reach: shallow at max reach (~30°) and steep pulled back (~65°). A rigid stick can't do all three of these at every reach:

- (a) keep the blade flat on the ice
- (b) keep the blade's direction exactly as the current yaw model says
- (c) have the shaft point at the hands

Two ways to resolve it:

**B1: one rigid stick (closest to real physics)**
- Blade and shaft are one welded piece. To keep the shaft on the hands and the blade on the ice, the stick rolls around its shaft.
- **Consequence:** the blade's face angle and direction become partly a result of reach. The face opens or closes and the toe swings as you reach in and out, on top of the yaw model.
- That changes the blade behavior you just approved, and fighting that coupling is likely to put us back in the tuning loop.

**B2: two physical pieces, each placed exactly (chosen 2026-11-09)**
- **Blade:** behaves exactly as it does now. Same yaw model, tilt and lift, same target.
- **Shaft:** its own physical part. Each step it's driven to lie along the line from the blade's **actual** heel to the hands. Same velocity drive and Server Authority setup as the blade.
- **Collisions:** both pieces hit the puck; neither hits skaters. A `NoCollisionConstraint` stops a player's own blade and shaft from colliding with each other.
- **Joint:** they're not welded, so a gap can open at the heel during very fast moves. It's limited by how closely the shaft tracks its target, and we measure it in the acceptance checks.
- **What it keeps:** the approved blade feel and a physical shaft, and it fixes the floating.

### 4.3 Shaft length (decided Q2: **long**)

A physical part's length should stay fixed: resizing a simulated part every step is risky for prediction. But the distance from heel to hands changes a lot with reach, from ~3.3 studs pulled back to ~6.6 at max reach. So:

- **Long shaft (~6.6 + a little):**
  - Always reaches the hands.
  - Pulled back, the extra length sticks out past the hands, upward past the camera.
  - Puck does something similar: pulled back in the middle, only the butt end shows at the bottom of the screen.
- **Medium shaft:** shorter overhang when pulled back, but the top falls short of the hands at max reach. That's a smaller version of the floating problem.
- **Chosen: long shaft.**
  - Length = the heel-to-hands distance at max reach, plus a butt overhang of ~0.5. That's about 7 studs; the exact value gets measured during implementation.
  - The shaft starts at the heel and runs toward the hands, so it always reaches them.
  - We check the pulled-back view. If the overhang crosses the camera badly, the fallback is to hide the part of the shaft above the hands on the local player's screen only (a visual trick, no physics change). That fallback gets agreed with you before it's built.

### 4.4 Lift

The blade swings up around the hands, toe first. The shaft follows automatically, because it always runs from the heel to the hands.

### 4.5 Collision groups

| Piece | Puck | Other players' sticks (later: tie-ups) | Skaters | Ice / boards |
|---|---|---|---|---|
| Blade (`Sticks`) | yes | yes | no | yes |
| Shaft (`Shafts`) | yes | yes | no | no (it wedged the stick in Milestone 0) |

Own blade and own shaft never collide with each other (`NoCollisionConstraint`).

### 4.6 Weight

- Today the stick weighs ~7× the puck (blade + shaft together).
- With B2, each piece is driven separately. The blade is ~2.4× the puck at the current density, so raise its density to keep it ~7×. The shaft gets a similar weight.
- Weight only matters during a single step, since the drive resets velocities every step. It mostly decides how much the puck can shove the stick during contact.

---

## 5. Acceptance checks (all must pass before the playtest)

Measured over MCP, with your hands off Studio:

1. **Blade unchanged:** at the 10 standard positions (far L/R, mid L/R, center, pulled back L/R/center, mid-flip, lift), the blade's target pose is identical to the committed part 1 (`1a8910a`).
2. **Shaft on the hands:** the shaft's line passes within **0.1 studs** of the hands point at every standard position, at rest. The hands shift opposite the blade (far right → hands ~0.8 left; far left → ~0.7 right; center → base position).
3. **Joint:** heel-to-shaft gap **< 0.1 studs** at rest; worst case reported during a fast flick.
4. **Max reach looks like the reference:** the butt end is at the bottom edge of the screen, left of center (screen-position check like the reverted experiment).
5. **Puck hits the shaft:** a puck slid into the shaft bounces off it.
6. **No collisions with skaters:** pushing the blade and shaft into your own body doesn't move it.
7. **No misprediction:** 0 or near-0 stick mispredictions during sweep and flip tests at 0 and 110 ms ping (Milestone 0 method).
8. **Shots unchanged:** forehand and backhand flick tests give the same direction (±30° inward) and similar speeds as part 1.

Then **one** feel playtest by you.

---

## 6. Implementation steps

1. `Config`: `HandAnchor`, `HandSwing`, `HandSwingMax`, the shaft length and thickness, the blade and shaft densities.
2. `PlayerSetup`: build the shaft as its own unwelded part, plus the `NoCollisionConstraint`.
3. `StickSim`:
   - `handAnchor(root, heading, bladeTarget)` (§4.1).
   - Lift pivots on the hands.
   - Shaft target computed from the blade's actual heel to the hands.
   - Drive the shaft by velocity, the same way as the blade.
4. `Simulation`: register the shaft as its own predicted assembly.
5. Run the acceptance checks, export to `/scripts`, commit, then your playtest.

---

## 7. Open questions

- ~~Q1.~~ **Decided 2026-11-09: B2** (two pieces, blade unchanged).
- ~~Q2.~~ **Decided 2026-11-09: long shaft**, always reaching the hands.
- ~~Q3.~~ **Decided 2026-11-09: hands move opposite the blade** (§4.1).
- **Q4.** _Still open._ Scroll direction: today scroll up tilts the forward face **down**, which is opposite to what the research doc records ("scroll up opens"). Confirm with a puck lift test which scroll direction lifts the puck, and we'll update the research doc to match.

## 8. Not in this step

- Blade-puck contact model (Milestone 0b part 2): carry, flick, soft touches, lift assist, tunneling. That gets its own plan section before any code.
- Stick-on-stick tie-ups (Milestone 5).
- Visible arms and gloves (viewmodel).
