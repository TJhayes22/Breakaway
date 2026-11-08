--!strict
-- Config: every gameplay tunable lives here so feel can be iterated quickly.
-- Units: studs (1 stud ~= 0.3 m), seconds, radians unless noted.
-- These are starting points for tuning, not final values.

local Config = {}

Config.Skater = {
	BodySize = Vector3.new(2.2, 5.6, 1.4), -- collider (W, H, D); visual rig comes later
	BodyDensity = 0.7,
	EyeHeight = 2.3, -- above body center

	MaxSpeed = 30, -- cruise top speed (~9 m/s)
	ForwardAccel = 26, -- accel at rest; tapers linearly to 0 at MaxSpeed
	BrakeDecel = 45, -- S while moving forward
	BackwardMaxSpeed = 12,
	BackwardAccel = 16,
	GlideDecel = 1.2, -- coasting loss per second

	TurnRate = math.rad(150), -- A/D yaw rate (rad/s)
	EdgeGrip = 6, -- how fast sideways velocity bleeds off (1/s); this is what makes it feel like skates
	CarveEfficiency = 0.6, -- share of bled-off sideways speed that is redirected forward

	UprightResponsiveness = 60,
}

Config.Stick = {
	Handedness = "Left", -- "Left" shot: blade sits on the player's left; forehand sweeps left -> right

	-- Aim arc (radians from straight ahead; positive = to the player's right)
	ArcLeft = math.rad(80),
	ArcRight = math.rad(55),
	ReachMin = 1.6, -- blade distance from body center
	ReachMax = 5.0,
	LiftStart = 0.85, -- aim.Y beyond this lifts the blade instead of extending reach
	LiftMax = 2.0, -- blade height at full lift

	BladeSize = Vector3.new(1.1, 0.3, 0.12), -- (length, height, thickness)
	ShaftLength = 5.3,
	ShaftThickness = 0.12,
	LieAngle = math.rad(45), -- shaft rise from the ice
	Density = 6, -- stick ~7x puck mass, so the puck can't knock the stick around

	-- Blade face tilt, in discrete scroll steps. Scroll up = close, scroll down = open.
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
	FieldOfView = 90, -- Roblox FOV is vertical
	PitchDown = math.rad(18), -- default downward tilt so the blade and puck are visible
}

Config.Input = {
	-- Default keybinds live on the InputActions in ReplicatedStorage.Inputs.
	-- A rebinding menu will edit those bindings later.
	StickSensitivityX = 0.0035, -- aim units per pixel
	StickSensitivityY = 0.0035,
}

return Config
