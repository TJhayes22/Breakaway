# Puck Gameplay Research & Prototype Architecture

_Breakaway — Phase 1 deliverable. Written 2026-11-08._

This document covers the First Assignment in `CLAUDE.md`: what Puck does, what makes it satisfying, what Roblox can and can't do today, and a proposed architecture and plan for the first physics prototype. Nothing has been implemented yet.

## How to read this

Every claim about Puck is tagged:

| Tag | Meaning |
|---|---|
| **[Confirmed]** | Stated by the developer (Steam store page or official patch notes). |
| **[Community]** | Stated by one or more players in Steam discussions or a community guide. Probably true, not verified. |
| **[Mod]** | Read from the documentation of a community server mod that exposes Puck's internal tuning parameters. Reliable for _names_ of systems, values may be out of date. |
| **[Inferred]** | My interpretation of the above. Not observed. |
| **[Unknown]** | I couldn't find it. Needs a playtest or footage. |

**Important limitation:** I can't watch video. Everything here comes from text: the store page, patch notes, community threads and guides, and mod documentation. Several things CLAUDE.md asks about (camera feel, exactly how turning works, how lifting the puck works) are best answered by playing Puck. It's free on Steam; 30–60 minutes of play would still help confirm the [design decisions](#9-design-decisions) and close the remaining **[Unknown]** gaps below.

---

## 1. Current project state (MCP inspection)

**Studio connection:** one Studio instance connected (`Place1`), Edit mode.

**Place contents:** a default Baseplate template. `ServerScriptService`, `ReplicatedStorage`, `StarterGui` and `ServerStorage` are empty; `StarterPlayer` has only its two default script folders. Workspace has `Baseplate`, `SpawnLocation`, `Terrain`, `Camera`. The place is unpublished (`PlaceId = 0`).

**Relevant Workspace settings right now:** `AuthorityMode = Automatic` (classic client/server physics), `StreamingEnabled = true`, `Gravity = 196.2`.

**Repo:** hosted at https://github.com/TJhayes22/Breakaway. Studio is the source of truth; scripts are exported to `/scripts` mirroring the Studio hierarchy (see `scripts/README.md`). The place file isn't committed yet ([decision 8](#9-design-decisions)).

**MCP tools available and how I'll use them:**

| Tool | Use in this project |
|---|---|
| `search_game_tree`, `inspect_instance`, `script_read/search/grep` | Inspect hierarchy and scripts before changing anything. |
| `execute_luau` | Build the rink, create/edit instances, run checks in Edit, Server or Client datamodels. |
| `multi_edit` | Write and edit scripts. |
| `start_stop_play`, `get_console_output`, `get_studio_state` | Start/stop single-client playtests and read errors/logs. |
| `user_keyboard_input`, `user_mouse_input`, `character_navigation` | Drive a playtest with synthetic input (e.g. skate forward, sweep the stick). |
| `screen_capture` | See what the playtest looks like. |
| Skills: `rbx-network-simulator` | Add latency/jitter/packet loss in playtests. Essential for testing the puck netcode. |
| Skills: `rbx-unit-test`, `rbx-debug`, `rbx-perf-profiling` | Test pure physics/math modules, breakpoints, MicroProfiler. |
| `generate_mesh`, `generate_material`, `insert_asset` | Later: stick/rink/arena art. |

**What the tools can't do:**
- `start_stop_play` starts a **single-client** playtest. Multi-client tests (Studio's "Local Server" with 2+ players) have to be started by you from the Test tab; I can then inspect them.
- I can verify that things work and measure them (speeds, distances, latency behavior), but I **can't judge feel**. Feel tuning will need your playtesting and feedback every milestone.

---

## 2. Puck at a glance

- Developer/publisher NS7, free-to-play on Steam, released **January 4, 2025**. **[Confirmed]**
- Described as a "fast-paced, physics-driven hockey simulation" where "realistic physics" govern "every pass, shot, and body check". Stick controls are pitched as offering "precision and depth" and reacting to "dynamic puck physics". **[Confirmed]**
- Roles: forward, defenseman, **goaltender (player-controlled)**. Marketing emphasizes passing, one-timers, give-and-go. **[Confirmed]** _Note: our design uses AI goalies, which is a meaningful difference._
- Reviews: about 84–86% positive across ~4,500–5,400 reviews depending on when captured. **[Confirmed]**
- Built in Unity with Netcode for GameObjects (patch B202 "Updated Netcode for GameObjects to 2.3.0"). Dedicated servers, community-hostable, Workspace mods. **[Confirmed]**

---

## 3. Observed mechanics

### 3.1 First-person camera

- First-person. Players widely raise FOV: recommendations of "100+", "100–120", "100–115". **[Community]** Whether Puck's FOV number is horizontal or vertical is **[Unknown]**, which matters because Roblox's `Camera.FieldOfView` is vertical and caps at 120.
- A "downward camera angle slider" was added in B185. **[Confirmed]** **[Inferred]** Seeing the puck near your skates is a core problem in first person, and the developer solved it partly with a configurable pitch offset rather than only free-look.
- Goals trigger slow-motion replays and a celebration cam following the scorer (B1153). **[Confirmed]**
- Lower mouse sensitivity is the #1 community tip; "the default is way too high". Several players set vertical sensitivity lower than horizontal. **[Community]**
- How the player looks around while the mouse is driving the stick is **[Unknown]**. One player warns against "relying on the left click to find direction", which suggests a click-to-look or click-to-orient function. Needs a playtest.

### 3.2 Skating and movement

Controls per a community guide (marked WIP, ~670 days old): **[Community]**
- `W` / `S`: accelerate / brake
- `Space`: jump
- `Ctrl`: slide (uses stamina)
- `Alt`: quick/sharp stop (also confirmed in B155 patch notes **[Confirmed]**)

From patch notes **[Confirmed]**:
- Movement systems mentioned by name: **sprint with stamina**, **backwards skating** (sprint backwards added B185), **A/D "sway"**, **leaning**, **double-tap spinning**, **sliding** (with its own friction, turn speed, drag), **jumping**, **falling/get-up** after checks, **turn speed** (tuned up and down several times).
- B163 lowered turn speeds and raised sprint acceleration and stamina drain. It was "a bit controversial" because of changes to stick feel and movement. **[Confirmed]** **[Inferred]** Movement feel is sensitive and the community notices small changes. We should keep all tunables in one config module so we can iterate fast.

From the mod documentation **[Mod]**: skater movement has separate **forward, backward and sprint acceleration curves**, **turn acceleration**, **braking**, **max speed**, a **post-slide turn curve**, and stamina drain/regen curves. Physics uses a fixed timestep with configurable solver iterations.

**[Inferred]** A/D likely turns or leans rather than strafes ("sway"), which fits skating where you can't sidestep freely. Exactly how turning is controlled is **[Unknown]**.

Community advice **[Community]**: "most of the work is done with your feet"; "don't hold W all the time"; slow down to keep space between your body and the puck.

### 3.3 Acceleration, momentum, friction, turning

**[Inferred]** from the above:
- Momentum is strong. Players describe the controls as "floaty" and liken the physics feel to QWOP/Surgeon Simulator. **[Community]**
- Acceleration is curve-based (faster from low speed, tapering near max) rather than constant. **[Mod]** names "acceleration curves".
- Stopping is a deliberate action (`S` brake, `Alt` sharp stop). Coasting carries you a long way.
- Concrete numbers (max speed, time to top speed, turn rate) are **[Unknown]**.

### 3.4 Independent stick control

This is the core of Puck's identity.

How it's controlled **[Community]**:
- Moving the mouse **left/right sweeps the stick in an arc** around the player.
- Moving the mouse **forward/back changes reach**; pushing far enough **lifts the blade off the ice**.
- The **scroll wheel rotates the blade angle**. One player says it "adds power to low shots".
- "Stick radius" is called "the biggest concept you need to figure out": keep the puck as far out as possible without lifting the stick, with "way less range to the sides". **[Community]**

How it's built **[Mod]** (parameter names from the mod's documentation):
- The stick is a **physical rigidbody** driven toward a target by a **PID-style controller** (`ShaftHandleProportionalGain = 500`). A "stick positioner" output clamp (`StickPositionerOutputMax`) **caps how fast the stick can sweep**.
- **Blade angle** is stepped: 12.5° per step, ±4 steps (±50°).
- **Tie-ups:** when a blade touches another stick's shaft, the blade's PID gain is lowered, so sticks can lock each other up physically.
- **Grip:** while the puck touches a stick, the puck's inertia tensor changes (`PuckStickTensor`) and there's a stick-on-puck mass tweak (`StickOnPuckInverseMass`). **[Inferred]** The developer quietly increases rotational stability while the puck is on the blade so stickhandling feels controllable rather than chaotic. This is a subtle "assist" layered on real physics, not a magnet.

From patch notes **[Confirmed]**:
- The stick rotation pivot moved to **the bottom center of the blade** (B185) "making stick-to-board collisions and puck exit angles more predictable".
- The pivot moved closer to the body (B155). Reach was extended while sliding (B163). Stick control feel at full reach was adjusted (B171).
- Numerous fixes for jitter: blade-tip leading, stick-on-stick collisions, sticks rotating players on high-force collisions, stick spinning at high sensitivity.

### 3.5 Blade-puck interaction

- Players report that you "should barely be tapping the puck"; "very little stick movement" is needed. **[Community]**
- Puck pass-through on sticks at high speed was a real problem, fixed by switching all rigidbodies to **speculative continuous collision detection** (B163). **[Confirmed]**
- The developer added a **"custom physics solver for [the puck's] exit trajectory"** (B185). **[Confirmed]** **[Inferred]** Pure rigidbody contact between a thin blade and a puck produced unsatisfying or inconsistent exit directions, so they post-process the result. Expect us to need something similar.

### 3.6 Puck movement

**[Confirmed]** across patches:
- Puck **friction was reduced and weight increased** (B155), then weight increased again (B185). Drag and weight were moved to midpoints (B163).
- Collider changed to a **cylinder**, and earlier made "less rounded". Fixed "feather-light feel when leading the puck".
- Board bounciness: made uniform, then **cut by 50%**, then raised. Board colliders were fixed so they no longer send the puck in random directions.
- **Nets dampen incoming pucks.** Goals no longer register on high-speed net impacts.
- **[Mod]** `PuckMaxSpeed = 30` (almost certainly Unity units = meters/second, ≈108 km/h). Mod options exist for speed- and height-dependent drag.

**[Inferred]** The puck went through a lot of tuning toward _heavier, less bouncy, more predictable_. "Floaty" and "random" are the failure modes players hate.

### 3.7 Shooting and shot power

- "Swing your mouse left to right to swing, up and down to raise and lower." **[Community]**
- There is no shoot button. Shot power comes from stick speed at contact. **[Inferred]** from the above plus the absence of any shot keybind in the guide.
- It took one player "about an hour to get consistent long-distance shots". **[Community]**
- How players lift the puck (blade angle? stick lift? a separate input?) is **[Unknown]**.

### 3.8 Passing and stickhandling

- Passing uses the same mechanics as shooting with less stick speed. **[Inferred]**
- Marketing pushes passing, one-timers and give-and-go. **[Confirmed]**
- Stickhandling is about light touches and skating positioning, not big stick movements. **[Community]**

### 3.9 Collisions and checking

**[Confirmed]** via patches:
- Body checking is "easier and dependent on angle of attack".
- Checked players **fall, must fully fall before getting up**, and have a get-up sequence. "Body checks no longer launch targets across the rink."
- **Soft collisions** between players and with the boards.
- Player bodies made 20% slimmer. **Crouch** height lets the puck pass under players.
- **Goalie crease protection:** body collisions are filtered inside the crease, and intruders appear as ghosts.

### 3.10 Pacing and match flow

- Faceoffs, warmup, replays, celebration cam. **[Confirmed]**
- Contested pucks are decided fast; with high ping you get "almost no time to control the puck" before it's knocked away. **[Community]**
- Match length and rink dimensions are **[Unknown]**.

### 3.11 Networking (for comparison)

**[Confirmed]** from patch notes:
- Dedicated servers run at a **200 Hz tick rate** (raised from 100).
- **Server-authoritative** physics with **client-side smoothing**. A "Network Buffering" setting offers Predictive / Responsive / Balanced / Smooth, trading input latency against accuracy.
- Repeated work on jitter, bandwidth and input delay. Players say "anything above 50 ping makes gathering the puck take way longer". **[Community]**

**[Inferred]** Even with a custom netcode and 200 Hz servers, Puck's stickhandling degrades noticeably with latency. We'll be on a 60 Hz simulation step with Roblox's netcode. We must design for latency rather than hope to eliminate it.

---

## 4. What makes it satisfying (and what players dislike)

**What players praise** (from reviews, community threads, and the patch history's priorities):
1. **Emergent skill.** Shots, passes, dekes and checks all come from the same physical stick and body. Nothing is canned, so good plays feel earned. "The difficulty is the fun part."
2. **High skill ceiling.** People talk about sinking hours in and slowly getting consistent. Retention through mastery.
3. **The stick as a physical object.** Tie-ups, poke checks, blocking passes and deflections fall out of the physics for free.
4. **Momentum skating.** Positioning with your feet is half the game.
5. **Team plays.** One-timers and give-and-go are the highlight moments.

**What players complain about:**
1. **Steep onboarding.** "Unintuitive and janky", "controlling the puck is impossible for me", "hardest game ever". Default sensitivity is too high.
2. **Floaty controls.** Puck too light/fast early on (patched repeatedly toward heavier).
3. **Latency sensitivity.** Above ~50 ms, puck battles feel bad.
4. **Physics glitches.** Pass-through, jitter, random bounces off boards. Most early patches fixed these.

**Implications for us:**
- The physics fidelity is the product. Glitches are much more damaging here than in a normal game.
- Roblox's audience skews younger and more casual than Steam's. **We should keep Puck's skill ceiling but lower the floor**: sane default sensitivity, a practice rink, a tutorial, and maybe subtle physical assists (like Puck's grip tensor) that don't automate anything.
- Design for latency from day one.

---

## 5. Roblox capabilities (as of November 2026)

### 5.1 Physics

- Unanchored parts are simulated by Roblox's rigid-body solver, which substeps internally (adaptive timestepping, up to 240 Hz). Per-part `CustomPhysicalProperties` give density, friction, elasticity and their weights.
- Mover constraints suited to us: **`AlignPosition` / `AlignOrientation`** (spring-like pull toward a target with `MaxForce`, `MaxVelocity`, `Responsiveness`; very close to Puck's PID-with-output-clamp stick), **`LinearVelocity`**, **`VectorForce`**, **`AngularVelocity`**, plus `ApplyImpulse` for scripted impulses.
- **No documented continuous collision detection** for fast, thin objects. Tunneling (puck through a thin blade or board) is a real risk and has to be handled with collider sizing, speed caps and sweep tests (`Blockcast`/`Shapecast`).

### 5.2 Classic networking: network ownership

Roblox's default model is **distributed physics**: each unanchored assembly is simulated by one owner (server or a nearby client) and replicated to everyone else.

- Owner-simulated parts feel instant for the owner; everyone else sees them late.
- **Roblox cannot verify physics from a client-owned part.** The client can teleport it. (Roblox docs, "Security concerns".) A client-owned puck is exploitable.
- Server-owned parts are safe, but every touch has a full round-trip of input latency. For stickhandling that's unplayable.
- Past Roblox hockey developers hit exactly this wall: ownership switching causes stutter, puck teleports when two players fight for it, and "invisible server puck + local visual puck" setups didn't fix it. Several gave up on physics for scripted CFrame pucks. (DevForum threads in [Sources](#10-sources).)

### 5.3 New option: Server Authority (released July 9, 2026)

Roblox released **Server Authority** for all experiences on July 9, 2026. It changes the tradeoff entirely and is the single most important finding of this research.

- The **server owns and simulates everything**. Clients send only **inputs** (via the Input Action System).
- Clients **predict** a few frames ahead so their own actions feel instant. When the server disagrees, the client **rolls back and resimulates**.
- Your core logic goes in `RunService:BindToSimulation()` callbacks in ModuleScripts that run on **both** client and server. Fixed-step, **up to 60 Hz**. Only "simulation access" properties can be touched there. Custom state syncs through **attributes** (64 per instance, strings ≤ 50 chars).
- `Player:GetCameraState()` gives the server each player's camera CFrame, so the server can use the player's real look direction.
- Roblox ships a **Soccer template** that uses this for a ball, including a render-smoothing technique for the ball (smooth only when the simulated ball jumps due to a correction). That's the closest precedent to our puck.
- Enabled per place with `Workspace.AuthorityMode = Server` (which turns on `NextGenerationReplication`, `PlayerScriptsUseInputActionSystem`, deferred signals, `UseFixedSimulation`, `StreamingEnabled`).

**Known costs and limits:**
- Higher CPU on server and clients. Correcting a misprediction at 100 ms ping means resimulating 100 ms of physics in one frame.
- **Other players' inputs aren't forwarded by default**, so contested pucks will mispredict. Roblox's Racing template shows a workaround: copy inputs into attributes so all clients can simulate other players.
- Roblox staff note **"some drift in certain BodyMovers and Constraints"** that is still being investigated. Our stick would be driven by constraints, so this is a risk we must test early.
- Mobile/console clients lag desktop by a few days after engine updates.
- Fixed 60 Hz script step vs Puck's 200 Hz. The physics solver still substeps faster, but our control code runs at 60 Hz.
- **It shapes the codebase.** All gameplay code has to be written as a shared simulation from the start. Retrofitting later means rewriting it.

---

## 6. Implementation approaches

### 6.1 Puck physics and networking

| Option | How it works | Pros | Cons |
|---|---|---|---|
| **A. Server-owned physics puck, classic networking** | Puck `SetNetworkOwner(nil)`. | Simple, secure. | Full round-trip latency on every touch. Unplayable stickhandling. |
| **B. Dynamic ownership** | Hand ownership to whoever is closest/has possession. | Instant for the possessor. Proven in many Roblox ball games. | Exploitable (client controls puck). Handoff hitches exactly during puck battles, which is the moment that matters most. |
| **C. Server Authority** | Puck, sticks and skaters all server-owned and predicted. | Secure by design. Responsive for your own touches. Roblox's intended solution for sports games. | Newest tech, CPU cost, constraint drift risk, mispredictions in contested battles. Shapes all code. |
| **D. Fully custom puck simulation** | Our own puck integrator, collision and netcode, no Roblox physics. | Total control. | Huge effort; we'd be rebuilding a physics engine and netcode. Last resort. |

**Recommendation: C (Server Authority), validated by an early spike, with B as the fallback.** It's the only option that is both responsive and server-authoritative, which CLAUDE.md requires. But it's new enough that we should prove it works for _our_ case (thin blade, fast puck, constraint-driven stick, two players contesting the puck at 100 ms ping) before building much on it.

### 6.2 Skating

Don't use default `Humanoid` walking. It's built for instant start/stop on foot.

**Recommendation: a custom physics skater body**, driven in `BindToSimulation`:
- One unanchored capsule-ish collider (root), kept upright by `AlignOrientation`, with yaw from the player's turn input.
- Each simulation step, compute the force/velocity change from inputs:
  - **Thrust** (`W`) along the skate heading, following an acceleration curve (strong from rest, tapering near top speed). `S` slows you down while moving forward, then skates backwards (lower top speed) once you've stopped.
  - **Turning** (`A`/`D`) rotates the skater's heading at a capped turn rate. Turning is never done with the mouse ([decision 2](#9-design-decisions)).
  - **Low friction along the skate** (glide), **high friction across it** (edges bite). This one rule is what makes it feel like skating: velocity gradually rotates toward where you're facing, and **turn radius grows with speed** naturally.
  - **Carve** (hold `Ctrl`): higher turn rate and edge grip, skater crouches slightly (lower camera and collider).
  - **Sprint** (`Shift`): higher thrust and top speed, drains **stamina**.
  - **Jump** (`Space`): costs stamina.
  - **Hard stop** (`C`): skates turn sideways, very high friction, quick stop (snow-spray effect later).
  - One shared stamina bar with a regen delay.
  - All keys are defaults stored in `Config`; a rebinding menu comes later ([decision 7](#9-design-decisions)).
- **Dive (planned, not scheduled):** costs stamina; the skater drops and slides on the ice with momentum, can still move the stick, can't skate for ~3 s, then gets up. Built later as a fun "lock"/desperation move. The stick-while-down requirement means the stick's pivot has to work from a prone body pose, which we'll keep in mind when building the stick.
- The visible character (body, arms, gloves) is a separate, non-colliding visual rig that follows the root. In first person, the local player sees only arms, gloves and stick.

Alternative: Roblox's Character Controller Library (`ControllerManager` + `GroundController` with acceleration/friction/turn parameters). It's Server-Authority compatible and less custom code, but it's designed for walking, and the lateral-grip model above is hard to express with it. Worth a 1-hour comparison during the spike, not a commitment.

### 6.3 Stick

**Recommendation: a physical stick assembly driven toward a target by `AlignPosition` + `AlignOrientation`**, the Roblox equivalent of Puck's PID-driven stick:
- The stick is its **own unanchored assembly** (not welded to the skater), so it collides with the puck, boards and other sticks for real.
- **Input:** mouse deltas move a target in "stick space" around the player: **angle** (mouse X; wider arc on the forehand than backhand) and **reach** (mouse Y; past a threshold the blade lifts). Scroll sets the **blade angle** in discrete steps. **Scroll up closes the face** (tilts it over the puck, keeps it on the ice); **scroll down opens it** (tilts it back so contact pushes the puck upward). Lift comes from the real contact normal of the tilted blade, not a scripted pop, so the same input gives saucer passes, wristers and top-shelf shots depending on stick speed ([decision 5](#9-design-decisions)).
- **Speed cap:** `MaxVelocity` / `MaxAngularVelocity` on the align constraints caps sweep speed. This is both a feel knob and an **anti-exploit guarantee** (the server enforces it no matter what the client sends).
- **Pivot** at the bottom-center of the blade, following Puck's lesson.
- **Blade collider** slightly thicker than the visual blade, and **sweep tests** from last frame's blade pose to this frame's to catch tunneling.
- **Grip assist (optional, tunable):** while the puck is touching the blade, increase its angular damping. Physical and subtle, like Puck's inertia trick. No magnetism, no auto-aim.

Shooting and passing then **emerge** from stick speed and blade angle at contact. No shoot button, per CLAUDE.md.

### 6.4 Puck

- An unanchored **cylinder** part. Low friction against the ice, modest elasticity against boards, heavy enough not to feel "feather-light".
- **Custom drag** each simulation step (linear + quadratic, maybe height-dependent), and a **max speed cap**.
- **Optional exit-trajectory correction:** clamp or flatten unrealistic post-contact velocity (e.g. puck popping up unpredictably off the blade). Puck needed this; we probably will too.
- **Render smoothing** client-side: a visual-only puck that tracks the simulated one and smooths only when the simulated puck jumps (Soccer template technique).

### 6.5 Camera

- First person, locked to the skater's head with gentle **speed-based bob/sway** and FOV kick on sprint (subtle, toggleable).
- **Default downward pitch** so the puck near your blade is visible, plus a settings slider (Puck added this).
- FOV slider (default ~90 vertical in Roblox terms; max 120). Separate horizontal/vertical mouse sensitivity, **low defaults**.
- Look controls ([decision 2](#9-design-decisions)):
  - **Default:** camera faces the skater's heading (A/D turn the body and the view). Mouse cursor is locked; mouse movement drives the stick only.
  - **Hold right mouse:** free-look. Mouse rotates the camera instead of the stick; the stick holds its last target. On release, the camera eases back to the heading.
  - **Hold left click:** camera tracks the puck for as long as the button is held (quick ease-in, not an instant cut, to avoid disorientation); eases back to the heading on release.

---

## 7. Technical challenges & risks

| Risk | Why it matters | Mitigation |
|---|---|---|
| Constraint drift under Server Authority | Our stick is constraint-driven; drift = constant mispredictions = jittery stick. | First spike measures prediction success rate with the SA visualizer (`Ctrl+Shift+F6`). Fallback: drive the stick with velocities set directly in `BindToSimulation`. |
| Contested-puck mispredictions | Other players' inputs aren't known locally, so puck battles will correct. | Forward inputs via attributes (Racing template technique), render smoothing, and design for it (slightly heavier puck, capped stick speed). |
| Puck tunneling through blade/boards | No CCD in Roblox. | Thick colliders, speed caps, sweep tests, thick boards. |
| 60 Hz control step | Puck uses 200 Hz. Fast flicks may feel coarser. | Solver substeps between steps. Test early; if needed, interpolate stick targets within a step. |
| Tiny objects at Roblox scale | A real puck is ~0.25 studs; tiny parts are hard to see and collide poorly. | Puck is 2× real size ([decision 4](#9-design-decisions)); blade collider oversized too. |
| `Ctrl` as the carve key | Ctrl+A/Ctrl+D/Ctrl+W combos may be intercepted by Studio shortcuts during playtests (and Ctrl+click is right-click on some setups). | Verify in the first skating test. Make the key rebindable in `Config`; fallback `Left Alt` (`C` is now hard stop). |
| Default gravity | Roblox's 196.2 studs/s² is ~6× real gravity at 1 stud ≈ 0.3 m; lifted pucks would drop like rocks. | Set match-place gravity to ~32.7 studs/s² (real-world at our scale). |
| Onboarding | Puck's #1 complaint. | Low default sensitivity, practice rink, tutorial prompts. |
| Server CPU | SA + 6 skaters + 6 sticks + puck + 2 AI goalies at 60 Hz. | Profile in Phase 4. Small player count helps. |
| Version control | Studio is the source of truth; git only sees exported copies. | Re-export to `/scripts` after every milestone (see `scripts/README.md`). Save the place to a file soon; it's currently unsaved. |

---

## 8. Proposed architecture & prototype plan

### 8.1 Scale and starting numbers

All of these go in one `Config` module and are **starting points for tuning**, not final values.

| Item | Proposal | Notes |
|---|---|---|
| World scale | **1 stud ≈ 0.3 m** | A 1.8 m skater ≈ 6 studs, close to Roblox avatars. |
| Gravity (match place) | **32.7 studs/s²** | Real gravity at this scale. |
| Rink | **~160 × 70 studs** (~48 × 21 m), corner radius ~20 studs | Smaller than NHL (61 × 26 m) for 3v3 pace. |
| Boards | ~3.6 studs high + glass | |
| Goal | ~6 × 4 studs (6 × 4 ft) | |
| Puck | **0.5 studs diameter × 0.17 thick** | 2× real size (decided). Revisit after stickhandling tests. |
| Puck max speed | ~100 studs/s (30 m/s) | Matches Puck's cap. |
| Skater cruise / sprint top speed | ~30 / ~38 studs/s (9 / 11.4 m/s) | |
| Stick length / blade | ~5.3 studs / ~1 × 0.25 studs | Collider thicker than visual. |
| Stick reach | ~1.5–5 studs from body | Wider forehand arc than backhand. |
| Blade angle | ±4 steps of 12.5° | Mirrors Puck; easy to change. |
| FOV | default 90, slider 70–120 | Roblox FOV is vertical. |

### 8.2 Project structure (prototype only)

Only what the prototype needs. No empty folders.

```
ReplicatedStorage
  Config                 (ModuleScript)  all tunables
  Inputs                 (Folder)        InputContext + InputActions, cloned per player
    Skate (Vector2: W/S + A/D), StickAim (Vector2), BladeAngle, Carve, Sprint, Jump, HardStop
    (free-look and puck-focus are camera-only, so they stay client-side and aren't sim inputs)
  Simulation             (ModuleScript)  BindToSimulation entry point, runs on client + server
    SkaterSim            (ModuleScript)  momentum skating
    StickSim             (ModuleScript)  stick target -> align constraints, speed caps
    PuckSim              (ModuleScript)  drag, speed cap, grip assist, exit correction
    ServerLoader         (Script)
    ClientLoader         (LocalScript)

ServerScriptService
  PlayerSetup            (Script)  builds each player's skater body + stick, clones Inputs
  PuckSpawner            (Script)  puck reset/respawn (prototype convenience)

StarterPlayer.StarterPlayerScripts
  CameraController       (LocalScript)  first-person camera, bob, pitch offset
  StickInputController   (LocalScript)  mouse/scroll -> InputActions, sensitivity
  ViewmodelRenderer      (LocalScript)  arms/gloves/stick visuals
  PuckRenderer           (LocalScript)  smoothed visual puck
  DebugOverlay           (LocalScript)  speeds, stick state, prediction stats (dev only)

Workspace
  Rink                   (Model)  ice, boards, glass, goals
  Puck                   (Part)
```

### 8.3 Data flow per simulation step

1. Client reads mouse/keyboard → updates **InputActions** (aim target, skate vector, buttons).
2. Inputs go to the server automatically and are replayed on the client during resimulation.
3. `Simulation` (both sides, 60 Hz): `SkaterSim` applies skating forces → `StickSim` moves stick targets (clamped, rate-limited) → Roblox physics resolves collisions (substepped) → `PuckSim` applies drag/caps/assists.
4. Server state is authoritative. Clients correct on mismatch.
5. `RenderStepped` on the client: camera, viewmodel, smoothed puck, effects. Nothing here affects the simulation.

### 8.4 Security model

- Clients send only **inputs**. The server clamps them (aim inside the legal arc and reach, stick speed via constraint caps, sprint only with stamina).
- Puck position, velocity, goals and match state never come from a client.
- This is roughly what Server Authority gives us for free. With fallback B we'd need explicit validation of client puck state.

### 8.5 Milestones

Each milestone ends with: what was built, files changed, what I tested, what's unfinished, and my recommendation. Then you playtest and give feel feedback.

| # | Milestone | Done when |
|---|---|---|
| **0** | **Server Authority spike** (throwaway) | Puck + one constraint-driven stick + simple skater under SA. With `rbx-network-simulator` at 100 ms: prediction success rate measured, stick and puck look stable. **Go/no-go on SA.** |
| 1 | Rink + puck | Ice, boards, goals, puck. Puck glides, bounces off boards believably, never tunnels at max speed. |
| 2 | Skater + first-person camera | Momentum skating: W thrust with accel curve, S slow down/skate backwards, C hard stop, A/D turn, glide/edge grip, Ctrl carve with crouch, Shift sprint and Space jump on a shared stamina bar. Camera with pitch offset, FOV/sensitivity settings, RMB free-look, hold-LMB puck tracking. |
| 3 | Stick (aim + reach + blade angle) | Visible stick follows mouse in an arc, lifts at full reach, scroll opens/closes the blade, collides with boards and puck. |
| 4 | Stickhandling, passing, shooting | Shots, passes and dekes emerge from stick motion. Exit-trajectory and grip tuning. **This is the "does it feel good" checkpoint.** |
| 5 | Two-player test | Two local clients contest the puck at simulated 50–150 ms. Measure and tune. |

Milestones 0–4 = CLAUDE.md Phases 2–3. Milestone 5 starts Phase 4.

**Why put networking (milestone 0) first** when CLAUDE.md lists multiplayer as Phase 4: Server Authority dictates how every gameplay script is written. Building single-player physics first and converting later would mean rewriting milestones 1–4. The spike is small and throwaway; it just tells us which foundation to build on.

---

## 9. Design decisions

Answered by the designer on 2026-11-08. These replace the open questions from the first draft.

1. **Server Authority:** yes, from the start, gated by the milestone-0 spike. Dynamic ownership (option B) stays the fallback.
2. **Turning and looking:** like Puck. `A`/`D` turn the skater. Hold right mouse and move the mouse to look around freely. Hold left click to keep the camera tracking the puck. Otherwise the mouse drives the stick. (Details in [6.5](#65-camera).)
3. **Prototype skating moves:** forward, `S` to slow down and skate backwards, hard stop (`C`), turning, carve (hold `Ctrl`: faster turn, slight crouch), sprint (drains stamina), jump (costs stamina). **Dive is plan-only**: costs stamina, slide on the ice with stick control, can't skate for ~3 s, then get up. (Details in [6.2](#62-skating).)
4. **Puck size:** 2× real (0.5 studs). Adjust later if needed.
5. **Lifting the puck:** blade angle via scroll wheel. Scroll up closes the face, scroll down opens it so the puck lifts. (Details in [6.3](#63-stick).)
6. **Physical assists:** subtle assists are OK to make the game easier to learn. Still no magnetism or auto-aim.
7. **Input:** mouse and keyboard only for the prototype. Current keys are defaults kept in `Config`; a rebinding menu is planned for later.
8. **Version control:** git on GitHub (https://github.com/TJhayes22/Breakaway). Studio is the source of truth; scripts are exported to `/scripts` mirroring the Studio hierarchy and re-exported after big changes. Committing the place file is optional, pending a size check.

---

## 10. Sources

**Puck — official**
- Steam store page: https://store.steampowered.com/app/2994020/Puck/
- Steam news / patch notes (B155–B1235): https://steamcommunity.com/app/2994020/allnews/
- Build 163 announcement: https://steamcommunity.com/games/2994020/announcements/detail/538844469688009190

**Puck — community**
- "How do you shoot in this game" (Steam discussion): https://steamcommunity.com/app/2994020/discussions/0/594012261956210530/
- "trying SO hard to enjoy this" (Steam discussion): https://steamcommunity.com/app/2994020/discussions/0/603023534349909081/
- "Controls! (WIP)" community guide: https://steamcommunity.com/sharedfiles/filedetails/?id=3402666940 (contents via search summary; the page itself rate-limited my fetch)
- PoncePuck/CompetitiveAdjustments server mod (parameter names/values): https://github.com/PoncePuck/CompetitiveAdjustments
- PC Gamer, "People are taking this free-to-play hockey game very seriously": https://www.pcgamer.com/people-are-taking-this-free-to-play-hockey-game-very-seriously (only headline retrievable)
- SteamPulse review tracker: https://steampulse.org/game/2994020

**Roblox — official**
- Network ownership: https://create.roblox.com/docs/physics/network-ownership
- Server authority model: https://create.roblox.com/docs/projects/server-authority
- Server authority techniques: https://create.roblox.com/docs/projects/server-authority/techniques
- `RunService` (BindToSimulation, IsResimulating): https://create.roblox.com/docs/reference/engine/classes/RunService
- `StepFrequency` enum: https://create.roblox.com/docs/reference/engine/enums/StepFrequency
- `Workspace.UseFixedSimulation`: https://create.roblox.com/docs/reference/engine/classes/Workspace
- [Full Release] Server Authority (July 9, 2026): https://devforum.roblox.com/t/full-release-ship-fair-and-competitive-games-with-server-authority/4727993
- [Client Beta] Server Authority (April 30, 2026): https://devforum.roblox.com/t/client-beta-publish-test-your-server-authoritative-experiences/4606949
- Server Authority tech deep dive: https://devforum.roblox.com/t/server-authority-tech-deep-dive-engineering-insights/4624565
- Soccer Server Authority Template: https://www.roblox.com/games/110687099504272/Soccer-Server-Authority-Template
- Racing Server Authority Template: https://www.roblox.com/games/134686834388911/Racing-Server-Authority-Template

**Roblox — community hockey precedents**
- "Precise physics issue for hockey game": https://devforum.roblox.com/t/precise-physics-issue-for-hockey-game/3057478
- "Trouble with making a hockey puck system": https://devforum.roblox.com/t/trouble-with-making-a-hockey-puck-system/3740724
