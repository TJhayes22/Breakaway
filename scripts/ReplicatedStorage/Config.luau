--!strict
-- Config: every gameplay tunable lives here so feel can be iterated quickly.
-- Units: studs (1 stud ~= 0.3 m), seconds, radians unless noted.
-- These are starting points for tuning, not final values.

local Config = {}

Config.Skater = {
	BodySize = Vector3.new(2.2, 5.6, 1.4), -- collider (W, H, D); visual rig comes later
	BodyDensity = 0.7,
	EyeHeight = 2.3, -- above body center

	MaxSpeed = 25, -- cruise top speed (~7.5 m/s). Was 30: "too fast" (M0 playtest)
	ForwardAccel = 26, -- accel at rest; tapers linearly to 0 at MaxSpeed
	BrakeDecel = 30, -- S while moving forward, at full strength. Was 45: too abrupt
	BrakeRampTime = 0.25, -- brake force eases in over this long, so stops feel smoother
	BackwardMaxSpeed = 10,
	BackwardAccel = 16,
	GlideDecel = 1.2, -- coasting loss per second

	TurnRate = math.rad(150), -- A/D max yaw rate (rad/s)
	TurnAccel = math.rad(700), -- how fast the yaw rate builds/decays (rad/s^2); ~0.2 s to full turn. Was instant
	EdgeGrip = 6, -- how fast sideways velocity bleeds off (1/s); this is what makes it feel like skates
	CarveEfficiency = 0.6, -- share of bled-off sideways speed that is redirected forward

	UprightResponsiveness = 60,
}

Config.Stick = {
	Handedness = "Right", -- "Right" shot: forehand on the player's right; forehand sweeps right -> left. Was "Left" (2026-11-09 playtest)

	-- Aim arc (radians from straight ahead; positive = to the player's right).
	-- Kept inside the default camera view so the blade never leaves the screen
	-- (was 80/55 deg, which went out of frame; M0 playtest).
	-- The forehand side (right, for a right shot) gets the wider arc.
	ArcLeft = math.rad(48),
	ArcRight = math.rad(58),
	ReachMin = 2.3, -- blade distance from body center. Was 2.6; pulled back ~1 stud closer with MinBladeForward (2026-11-09 playtest)
	ReachMax = 6.5,
	-- The blade is never closer than this in FRONT of the body. A fixed gameplay rule,
	-- deliberately NOT derived from the camera: FOV will be a player setting and must never
	-- change how the stick plays. Was 3.3, which kept the whole blade on screen for vertical
	-- FOV >= ~88; at 2.3 (2026-11-09 playtest: "come back ~1 stud") the fully pulled-back
	-- blade sits at the bottom edge of the view, partly off screen, like Puck.
	MinBladeForward = 2.3,
	LiftStart = 0.8, -- aim.Y beyond this lifts the stick instead of extending reach
	-- Lift swings the blade up around the hands like a baseball bat, toe first (M0 playtest;
	-- was a straight 3-stud raise). The shaft follows (STICK_DESIGN.md §4.4).
	LiftPitchMax = math.rad(55),
	-- Blade yaw (face direction) tunables live at the top of Simulation.StickSim (BLADE_YAW).

	BladeSize = Vector3.new(1.1, 0.3, 0.12), -- (length, height, thickness)
	-- Blade and shaft are separate physics parts (STICK_DESIGN.md option B2).
	Density = 17, -- blade alone ~7x puck mass, so the puck can't knock it around (was 6 with the shaft welded on)
	ShaftDensity = 6,
	-- Telescoping shaft (STICK_DESIGN.md §10.4): the lower shaft starts at the heel, the
	-- handle ends ButtOverhang past the hands; they overlap more as the blade comes in.
	-- GripLength <= shortest heel-to-hands + ButtOverhang (handle never passes the heel);
	-- ShaftLength + GripLength >= longest heel-to-hands + ButtOverhang (no gap).
	ShaftLength = 4.4,
	ShaftThickness = 0.12,
	GripLength = 3.5,
	GripThickness = 0.15, -- a bit thicker than the shaft, like taped grip; hides the overlap
	ButtOverhang = 0.4, -- handle's butt end past the hands
	-- 0..1: how far the toe turns toward the hands line when extended (STICK_DESIGN.md
	-- §10.3). 1 = the shaft always reaches the hands; 0 = the original yaw model.
	HandsLineBlend = 1,
	LieAngle = math.rad(40), -- fallback shaft angle only, if the hands were ever ahead of the heel
	-- Hands (STICK_DESIGN.md §4.1): base point relative to the body center (X right, Y up,
	-- -Z forward) for a right shot, mirrored for a left shot. They drift sideways opposite
	-- the blade by HandSwing x the blade's sideways offset (studs), capped at HandSwingMax.
	HandAnchor = Vector3.new(-0.6, 0.5, -1.1),
	HandSwing = 0.15,
	HandSwingMax = 1.0,
	-- Shaft drive caps. The shaft re-attaches to the blade every step; these only stop
	-- runaway values (e.g. right after a reset).
	ShaftMaxSpeed = 150,
	ShaftMaxAngularSpeed = 60,

	-- Blade face tilt, in discrete scroll steps. Scroll up = open, scroll down = close.
	BladeAngleStep = math.rad(12.5),
	BladeAngleSteps = 4,

	-- How the stick is driven toward its target (Milestone 0 compares both):
	--   "Constraint": AlignPosition/AlignOrientation (closest to Puck's PID + output clamp)
	--   "Velocity":   the simulation sets the stick's velocity directly each step
	DriveMode = "Velocity",
	MaxSweepSpeed = 70, -- studs/s cap on blade speed (feel knob AND anti-exploit cap)
	MaxAngularSpeed = 25, -- rad/s
	-- Constraint mode
	PositionResponsiveness = 200,
	OrientationResponsiveness = 200,
	-- Velocity mode: 1/s. Higher = snappier tracking (time constant = 1 / gain)
	PositionGain = 30,
	RotationGain = 30,
	IceClearance = 0.02,
}

Config.World = {
	Gravity = 32.7, -- must match Workspace.Gravity (real gravity at 1 stud = 0.3 m)
}

Config.Puck = {
	StartPosition = Vector3.new(0, 0.2, 0),
	MaxSpeed = 100, -- ~30 m/s, same cap as Puck
	LinearDrag = 0.15, -- fraction of horizontal speed lost per second on the ice
	AngularDrag = 0.8,
	KillY = -20, -- below this the puck is reset
}

Config.Camera = {
	FieldOfView = 95, -- Roblox FOV is vertical. Was 90; will become a player setting
	PitchDown = math.rad(18), -- default downward tilt so the blade and puck are visible
}

Config.Input = {
	-- Default keybinds live on the InputActions in ReplicatedStorage.Inputs.
	-- A rebinding menu will edit those bindings later.
	StickSensitivityX = 0.0018, -- aim units per pixel. Was 0.0028 ("really high", 2026-11-09), 0.0035 before that
	StickSensitivityY = 0.0018,
}

return Config
