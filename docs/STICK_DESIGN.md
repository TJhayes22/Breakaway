# Stick Design

_Living design doc for the hockey stick. Last updated 2026-11-09 (Milestone 0b, part 1: complete after §10.7)._

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
| Handedness | **Right shot.** Forehand is the right side. Arc is **58° both ways** (left was 48°; widened 2026-11-09: "move the whole stick more to the left like the forehand side"). | `Config.Stick.Handedness`, `ArcRight/ArcLeft` |
| Blade yaw model | From the Puck video. The toe always points away from the middle. **Right of middle:** forehand faces forward. **Left of middle:** backhand faces forward. Crossing the middle, the blade **rotates smoothly** through toe-forward. | `StickSim.computeBladeYaw` |
| Face angle at the sides | Forward face turns **inward** (toward center), up to **30°** at full side reach. | `BLADE_YAW.SideMax` |
| Flip width | The flip happens across lateral −0.15 … +0.15. | `BLADE_YAW.FlipWidth` |
| Pulled back | The blade squares up (face straight ahead), based on depth only, on both sides. | `BLADE_YAW.PullBackFull/Start` |
| Closest blade distance | **2.3 studs** in front of the body (was 3.3). Fully pulled back, the blade sits at the bottom edge of the screen. | `MinBladeForward`, `ReachMin` |
| Stick sensitivity | **0.0018** aim units per pixel (was 0.0028). | `Config.Input` |
| Scroll tilt | A wrist roll: a fixed roll of the blade around its long axis, in 12.5° steps, ±4 steps, that stays with the blade as it swings across (§10.8, Q6). **Scroll down opens the forehand** (lifts the puck) and closes the backhand; **scroll up closes the forehand** and opens the backhand. | `StickSim` (`alpha` in `computeTarget`) |
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
- ~~Q5.~~ **Decided 2026-11-09: (a) toe follows the hands line when extended, with a blend knob, plus a telescoping two-piece shaft** (§10).
- ~~Q4.~~ **Decided 2026-11-09: scroll down lifts the puck** on the forehand (opens the forward face). Since Q6, the same roll lifts on the backhand with scroll up.
- ~~Q6.~~ **Decided 2026-11-09: scroll tilt is a wrist roll** that stays with the blade, so a closed forehand becomes an open backhand (§10.8).

## 9. B2 implementation results (2026-11-09)

### 9.1 What was built and measured

- **Built:**
  - The shaft is its own physical part.
  - Each step it starts at the blade's heel, using where the blade **will be** at the end of the step, so it doesn't trail.
  - It stays in the vertical plane through the blade's long axis, so it's always in line with the blade. Scroll tilt doesn't move it.
  - Within that plane it angles as close to the hands as it can.
  - It's placed exactly each step (it closes the whole error every step).
  - Shaft length is 7.8.
  - The hands swing opposite the blade.
- **Results:**

| Check | Result |
|---|---|
| 1. Blade unchanged | ✅ Same positions and yaw as the checkpoint formula (0 error). Lift is different **by design**: it now pivots on the swinging hands (§4.4). |
| 2. Shaft on the hands | ⚠ Within 0.2–0.6 at center, max reach center and far left. 1.1–1.4 at far right, max right, pulled back right and full lift. **~2.9 at mid reach to the sides (aim.X ±0.5) and mid-flip** (see 9.2). |
| 3. Heel joint | ✅ 0.006–0.031 studs at rest. Worst 0.166 during a 66 studs/s flick. |
| 4. Max-reach look | ✅ Max reach center: the shaft runs off the bottom of the screen at center. Max right: off the bottom at 76% across. ⚠ Pulled back in the middle: the shaft stands nearly vertical in front of the camera (leaves the top of the screen). |
| 5. Puck hits the shaft | ✅ A puck thrown at the shaft stops on it; the control throw passes. |
| 6. No skater collisions | ✅ Collision groups verified. Own blade and shaft ignore each other (NoCollisionConstraint). |
| 7. Misprediction | ✅ 0 events in 6 s of sweeps, flips and lift at 0 ms and with 110 ms incoming lag. (Caveat: the lag was set via Studio's network setting and wasn't independently confirmed.) |
| 8. Shots unchanged | ✅ Forehand 20.3 studs/s at −29.8° (was 19.4 at −27.6°). Backhand 15.7 at +29.3° (was 16.1 at +29.4°). |

### 9.2 The remaining conflict (Q5)

- **The rule:** a shaft that's in line with the blade can only reach the hands if the toe points roughly away from the hands.
- **Where it breaks:** our blade-yaw model turns the toe almost straight sideways (~79°) at mid reach, so the face looks forward. In those spots the in-line shaft lies across in front of the player instead of coming back to the hands. Puck looks like this only when **pulled back** (video 19.5 s). At mid reach, Puck's toe follows the hands-to-blade line (~45° at mid-right, video 8–9 s).
- **Options:**
  - **(a) Toe follows the hands-to-blade line when extended** (Puck geometry). The blade squares up only when pulled back.
    - The stick always looks connected.
    - The face is no longer near-square at mid reach, so it changes the approved blade feel.
    - Could be a blend knob (0 = today's yaw, 1 = Puck line) to compare in one playtest.
  - **(b) Allow a small bend at the heel:** the shaft turns partly toward the hands, by up to N°. It's more connected but shows a kink, which you disliked in the earlier experiment.
  - **(c) Keep it:** the stick lies across in front at mid reach.
- **Separate issue, pulled back in the middle:** the shaft stands nearly vertical in front of the camera. Possible fixes:
  - cap the shaft's angle above the ice
  - hide the part above the hands on your own screen only (the fallback in §4.3)
  - let the blade go under the camera, like Puck

## 10. Q5 fix: toe follows the hands, telescoping shaft (decided 2026-11-09)

### 10.1 Your playtest feedback on B2

- "The stick is a little too long."
- "When it's far away it still looks really disconnected from the player."

### 10.2 What we measured (B2, shaft 7.8)

| Position | Shaft misses hands by | Shaft past the hands |
|---|---|---|
| Center, max reach | 0.6 | 2.0 |
| Center, pulled back | 0.6 | **4.6** (above your head) |
| Far right, max reach | 1.4 | 0.5 |
| Mid-right, max reach | **3.7** | 2.3 |
| Mid-left, max reach | **4.3** | 3.6 |

- **Disconnect:** the yaw model points the toe ~79° sideways at diagonals, but the hands line is only ~40° off forward.
- **Too long:** one fixed-length shaft has to be long enough for max reach, so closer in it sticks out past the hands.

### 10.3 Fix 1: toe follows the hands line when extended (option a)

- **Line yaw:** the direction from the hands to the blade target, flat on the ice. It's computed from the aim only (hands and blade target are both pure functions of aim), so client and server agree.
- **The blend:** `toeYaw = modelYaw + HandsLineBlend × (1 − pullBack) × (lineYaw − modelYaw)`
  - `modelYaw` is today's approved yaw (§2).
  - At `HandsLineBlend = 1` and extended, the toe sits exactly on the hands line, so the in-line shaft reaches the hands.
  - Pulled back, the toe still squares up as today. There the shaft can miss by about 1 stud, like Puck's pulled-back look.
  - **`HandsLineBlend`** (Config, 0..1, starts at **1**): set it to 0 for the old yaw, to compare.
- **Consequences, to judge in the playtest:**
  - At extended diagonals the forward face turns ~50° inward (was ~11°), so shots from there go more across the body.
  - **The forehand/backhand flip gets more gradual when extended.** The hands line only crosses straight-ahead slowly as the blade moves across. Around center the toe points mostly forward and the face looks sideways over a wider range than the snappy ±0.15 flip. Pulled back, the flip is unchanged.
  - This is the geometric price of an in-line shaft that reaches the hands. A lower blend trades connection back for the snappier flip.
- **Scroll tilt:** at first this still used the lateral-based `flip` value for its sign. With the gradual toe, that made the blade snap-roll in the middle; fixed in §10.7.

### 10.4 Fix 2: telescoping shaft

- **Two physical pieces** on the same line, from the heel toward the hands:
  - **Lower shaft:** starts at the heel and runs up. Fixed length `ShaftLength`.
  - **Grip:** its butt end sits `ButtOverhang` past the hands and it runs down toward the heel. Fixed length `GripLength`. Slightly thicker and darker, like taped grip; it overlaps the lower shaft.
- **Lengths:** the heel-to-hands distance ranges from ~3.3 (pulled back) to ~7.5 (max reach right).
  - The grip must not reach past the heel, so `GripLength ≤ shortest distance + ButtOverhang`.
  - Together the pieces must span the longest distance: `ShaftLength + GripLength ≥ longest + ButtOverhang`.
  - So pulled back, the lower shaft pokes ~0.5 past the grip's butt. Two pieces can't hide that completely (the range is more than 2×). Total past the hands is ~1 stud at worst, vs. 4.6 today.
  - Exact values are measured during implementation.
- **Both pieces** are their own predicted parts, driven deadbeat like today's shaft.
  - Collision group `Shafts`: they hit the puck and other sticks, never skaters, ice or boards.
  - `NoCollisionConstraint` between all three own pieces (blade, shaft, grip).
- **If the shaft line misses the hands** (pulled back), the grip sits at the point on the line nearest the hands, so the stick stays one straight piece.

### 10.5 Acceptance checks

1. The blade position is unchanged. The yaw is unchanged at `HandsLineBlend = 0`.
2. Extended (depth ≥ 0.5) at every standard position: the shaft line passes within **0.15** of the hands.
3. Past the hands: **≤ ~1 stud** at every standard position, including lift.
4. The grip never extends past the heel. Grip and lower shaft overlap at every position (no gap in the stick).
5. Misprediction: 0 or near-0 in sweep, flip and lift tests (same method as §9).
6. Flick test: report forehand and backhand shot directions and speeds (expected to change at diagonals; not a pass/fail).
7. Then your feel playtest, including a comparison at `HandsLineBlend = 0.5` and 0.

### 10.6 Results (2026-11-09; ShaftLength 4.4, GripLength 3.5, ButtOverhang 0.4, blend 1)

The upper shaft piece is a part named `Handle`, because the blade already has an attachment named `Grip`.

| Check | Result |
|---|---|
| 1. Blade position | ✅ Unchanged (`bladeLocalXZ` untouched). The yaw at blend 0 is the old formula exactly (the blend term is 0). |
| 2. Shaft on the hands, extended | ✅ **0.000** miss on the whole aim grid (41×21 points) wherever depth ≥ 0.5, including lift. |
| 3. Past the hands | ✅ Extended: **0.4** everywhere. Pulled back at center: 1.2. ⚠ Pulled back on the **backhand side** (lateral −0.7 … −0.15, depth < ~0.2): ~2–3 (see below). |
| 4. Grip vs heel, overlap | ✅ The handle never passes the heel (minimum 0.00). The pieces always overlap (min 0.04 static; dynamic: always overlapping, ≥ 0.58). Handle stays on the shaft line (≤ 0.07). |
| 5. Misprediction | ✅ 0 events (`RunService.Misprediction`) in 7 s of sweeps, flips, lift and a full-width flick, at 0 ms. Not re-run at 110 ms. |
| Heel gap (dynamic) | ⚠ Worst **0.27** for a frame or two, only when the blade hits its 25 rad/s turn cap during a fast pulled-back flip near center (B2: 0.17). Otherwise < 0.12. |
| 6. Flicks | Forehand from mid-right (aim 0.5, 0.6): 29.7 studs/s at **−46°**. Backhand from mid-left (−0.5, 0.6): 26.7 studs/s at **+67°**. Shots follow the new face angles, so the backhand from mid-left goes nearly sideways. |

Collision setup verified: blade, shaft and handle all hit the puck and ignore skaters; 3 `NoCollisionConstraint`s keep the player's own pieces apart. Fast sweeps (~46 studs/s) still tunnel through the puck; that's a known part-2 issue.

**Remaining pulled-back backhand case:**
- Pulled back, the blade is square (toe straight left on the backhand), so the hands sit almost directly behind the heel.
- The in-plane shaft can't point at them, so it falls back to the 40° default lie and crosses in front of you to the right.
- B2 had the same pose with a 7.8 shaft. Now it's 4.4.
- Possible follow-ups, to decide after the playtest:
  - let the hands-line blend act partly even when pulled back
  - pick a better fallback direction

### 10.7 Final tweaks from the playtest (2026-11-09)

The user's verdict: "HUGE IMPROVEMENT, this is feeling really close to puck!" Two tweaks, then this stage is complete.

1. **Backhand reach:** `ArcLeft` goes from 48° to **58°**, matching the forehand.
2. **Tilt bug:** "when our blade is tilted a lot, moving to backhand auto tilts it, but the tilt should remain the same."
   - **Cause:** the tilt's sign switched faces across lateral ±0.15. That matched the old yaw, which spun the blade 180° in the same band. With the toe following the hands, the blade only turns ~15–20° in that band, so the blade visibly snap-rolled from leaning one way to the other.
   - **Decision (the user):** the forward face keeps the same tilt on both sides. The switch happens smoothly as the blade turns, not as a snap.
   - **Fix:** the tilt's face switch follows whatever drives the yaw, using the same blend weight as §10.3.
     - **Extended:** it follows the blade's actual toe. It eases from full forehand tilt to full backhand tilt while the toe is within `TiltFlipWidth` (**±40°**) of straight ahead.
     - **Pulled back:** it uses the old lateral switch, which matches the blade's fast 180° spin there.
     - Both faces get the full tilt everywhere outside the middle (forward face pitch −50° at 4 steps, at lateral ±0.5 and ±1, at every depth).
   - **Measured:** the most the blade turns per 0.02 of lateral, at full tilt:

| Depth (aim.Y) | Old tilt switch | New | Yaw alone, no tilt |
|---|---|---|---|
| 0.8 (max reach) | 10.1° | **3.4°** | 1.6° |
| 0.45 | ~10° | **3.7°** | 1.8° |
| 0.3 | 11.9° | 13.1° | 6.5° |
| 0.2 | ~20° | 19.8° | 14.7° |
| 0.05 (pulled back) | 20.4° | 20.4° | 17.9° |

   - A ±25° window was tried first. It made the pulled-back flip much worse (48° in one step), because the roll got squeezed into a small part of the spin.
3. **Checks after both tweaks:**
   - Far left at max reach, the blade sits 23% across the screen, mirroring 77% on the right; fully on screen at every depth.
   - Extended shaft-to-hands miss is still 0.000 across the aim grid with the blade tilted 4 steps. It sticks out ≤ 0.4 past the hands, and the pieces always overlap.
   - 0 mispredictions in 6 s of tilted sweeps and flips.

**Part 1 (stick orientation, shaft, hands) is complete.** Known leftovers carried forward:
- Pulled back on the backhand side, the shaft falls back to the default lie and crosses in front of you.
- The heel gap blips to ~0.27 during fast pulled-back flips.
- Misprediction hasn't been re-run at 110 ms.
- Q4 (which scroll direction lifts) was still open at this point (since settled, see §7).

### 10.8 Q6: scroll tilt is a wrist roll (decided 2026-11-09)

**The user:** "blade tilt is good on the forehand side but should stay tilted that way, for example: say i scroll up to close tilt (deloft) and when i slide it over to backhand it should be open so the blade would lift the puck."

- **What §10.7 did:** it re-applied the tilt to whichever face pointed forward. The forward face had the same tilt on both sides, so the blade rolled over (smoothly) as it crossed the middle.
- **Decision:** the scroll tilt is a fixed roll of the blade around its long axis, like rolling your wrists in real hockey. It stays with the blade as it swings across. The blade turns around between forehand and backhand, so the same roll closes one side and opens the other:

| Scroll | Forehand | Backhand |
|---|---|---|
| Up (bladeSteps +) | closed (deloft) | open (lifts) |
| Down (bladeSteps −) | open (lifts) | closed |

- **Code:** `alpha = -tilt` (no per-side sign). `TiltFlipWidth`, `tiltSign` and the face-switch blend from §10.7 were removed.
- **Measured (target math, fresh module):**
  - At ±4 steps, the forward face's normal is ±0.77 up (50°) at every lateral and depth, with the sign switching exactly where the blade turns around.
  - The roll stays 50° relative to the blade everywhere (0.00° deviation).
  - The largest blade turn per 0.02 of lateral is 17.9°. That's the pulled-back yaw spin alone; the tilt adds nothing.
- **Q4 still stands** (scroll down lifts), but now only on the forehand. On the backhand, scroll up lifts.
- **Playtest (the user):** "awesome feels great."
- **Follow-up, the shaft rolls too:** the user noticed the two shaft pieces didn't turn with the blade's tilt.
  - Both pieces now roll around their own long axis to line up with the blade's face. Their up vector is the blade's face normal, projected square to the shaft line.
  - Position and direction are unchanged: a 0.00000 difference across the aim grid at every tilt. Untilted, the pose is the same as before (≤ 0.03°).
  - The cross-section is square, so collisions are effectively unchanged.
  - At ±4 steps the shaft rolls 42–45°, a bit less than the blade's 50°, because the shaft leans at the lie angle instead of lining up with the blade's long axis.

## 8. Not in this step

- Blade-puck contact model (Milestone 0b part 2): carry, flick, soft touches, lift assist, tunneling. That gets its own plan section before any code.
- Stick-on-stick tie-ups (Milestone 5).
- Visible arms and gloves (viewmodel).
