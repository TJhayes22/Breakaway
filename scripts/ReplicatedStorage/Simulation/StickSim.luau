--!strict
-- StickSim: turns the (sanitized) stick input into a blade target, one 60 Hz step.
--
-- The stick is its own physics assembly. It is never teleported; it is pulled toward the
-- target (by constraints or by setting its velocity, see Config.Stick.DriveMode), capped
-- by MaxSweepSpeed. So the stick collides with the puck, boards and other sticks for real,
-- and shot power comes from how fast the blade is actually moving at contact.
--
-- Aim mapping:
--   aim.X in [-1, 1] -> angle around the skater (left arc .. right arc)
--   aim.Y in [0, LiftStart] -> reach (ReachMin .. ReachMax)
--   aim.Y above LiftStart -> the whole stick pitches up around the hands, toe first, like
--                            raising a baseball bat (up to LiftPitchMax)
-- Blade yaw (see computeBladeYaw and BLADE_YAW below), modeled on Puck reference video:
--   the toe always points AWAY from the middle, so the shaft runs back toward the body.
--   Stick on the right: toe right, the face on that side faces forward (forehand for a
--   right shot). Stick on the left: toe left, the other face forward (backhand). Crossing
--   the middle, the blade rotates through toe-forward (the forehand/backhand flip).
--   At the sides the forward face angles inward; pulled back it is square.
-- Blade frame: X = long axis toward the toe, Y = up, Z = X cross Y. Forehand is -Z for a
-- right shot, +Z for a left shot. The shaft is welded in this frame, running back from
-- the heel along -X.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config)

local C = Config.Stick
local BODY_HALF_HEIGHT = Config.Skater.BodySize.Y / 2

-- ===== Blade yaw tuning =====================================================
-- The stick is a point in reach space: lateral (aim.X, -1 left .. +1 right) and depth
-- (0 = pulled all the way back .. 1 = full reach, before lift). Yaw 0 = face square to
-- the look direction. Mirrored exactly left/right.
local BLADE_YAW = {
	-- Face angle at far left/right with the stick extended. Also a hard clamp: the face
	-- never turns further than this from forward. Positive = face turns INWARD (toward
	-- center) at the sides; negative = outward.
	SideMax = math.rad(30),
	-- |lateral| below this keeps the blade square (puck right in front of you). The side
	-- angle then eases in (smoothstep) from here to |lateral| = 1.
	SideDeadZone = 0.15,
	-- Forehand/backhand flip: across |lateral| < FlipWidth the blade rotates 180 deg
	-- through toe-forward. Smaller = snappier flip (0.05 ~ a snap), larger = slower.
	FlipWidth = 0.15,
	-- Pull-back straightening, by depth only: fully square at or below PullBackFull,
	-- no effect at or above PullBackStart, smooth in between.
	PullBackFull = 0.15,
	PullBackStart = 0.5,
}

-- Top of the shaft (where the hands hold it), in the blade's frame.
local HANDS_LOCAL = Vector3.new(
	-C.BladeSize.X / 2 - math.cos(C.LieAngle) * C.ShaftLength,
	math.sin(C.LieAngle) * C.ShaftLength,
	0
)

local StickSim = {}

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

StickSim.BLADE_YAW = BLADE_YAW

export type BladeYaw = {
	toeYaw: number, -- radians from forward, + = toe to the player's right
	faceYaw: number, -- forward face's angle from forward, + = turned right
	flip: number, -- -1 = toe left (left-side face forward) .. +1 = toe right
	lateral: number,
	depth: number,
	sideWeight: number, -- 0..1, how far into the side angle
	pullBack: number, -- 0..1, how much pull-back straightening applies
}

-- Blade yaw for an aim point. Pure function of (lateral, depth); mirrored left/right.
function StickSim.computeBladeYaw(aim: Vector2): BladeYaw
	local lateral = aim.X
	local depth = math.min(aim.Y / C.LiftStart, 1)
	local Y = BLADE_YAW
	local sideWeight = smoothstep((math.abs(lateral) - Y.SideDeadZone) / (1 - Y.SideDeadZone))
	local pullBack = 1 - smoothstep((depth - Y.PullBackFull) / (Y.PullBackStart - Y.PullBackFull))
	-- Inward: stick on the right -> forward face turns left (negative), mirrored on the left.
	local limit = math.abs(Y.SideMax)
	local faceYaw = math.clamp(-math.sign(lateral) * Y.SideMax * sideWeight * (1 - pullBack), -limit, limit)
	-- Smooth sign of lateral: the forehand/backhand flip.
	local flip = 2 * smoothstep((lateral + Y.FlipWidth) / (2 * Y.FlipWidth)) - 1
	-- Toe is perpendicular to the forward face, pointing to the stick's side.
	local toeYaw = flip * (math.pi / 2 - math.abs(faceYaw))
	return {
		toeYaw = toeYaw,
		faceYaw = faceYaw,
		flip = flip,
		lateral = lateral,
		depth = depth,
		sideWeight = sideWeight,
		pullBack = pullBack,
	}
end

-- Exposed so tests/debug tools can compute the same target the simulation uses.
function StickSim.computeTarget(rootPosition: Vector3, heading: number, aim: Vector2, bladeSteps: number): CFrame
	local theta = if aim.X < 0 then aim.X * C.ArcLeft else aim.X * C.ArcRight
	local reachT = math.min(aim.Y / C.LiftStart, 1)
	local reach = C.ReachMin + (C.ReachMax - C.ReachMin) * reachT
	local liftT = if aim.Y > C.LiftStart then (aim.Y - C.LiftStart) / (1 - C.LiftStart) else 0

	local blade = StickSim.computeBladeYaw(aim)

	-- Face tilt (scroll) tilts whichever face is forward. With this frame, +X rotation tips
	-- the +Z face down. Toe right (flip > 0): -Z faces forward. Scaling by flip keeps it
	-- continuous through the flip (no tilt mid-flip, when the blade is edge-on).
	-- Sign set by playtest (2026-11-09: "should be inverted back to how it was"); flip the
	-- leading minus to reverse the scroll direction.
	local tilt = bladeSteps * C.BladeAngleStep
	local alpha = -tilt * blade.flip

	-- Keep the lowest edge of the (possibly tilted) blade just above the ice.
	local halfExtent = 0.5 * (C.BladeSize.Y * math.cos(alpha) + C.BladeSize.Z * math.abs(math.sin(alpha)))
	local iceY = rootPosition.Y - BODY_HALF_HEIGHT
	local y = iceY + halfExtent + C.IceClearance

	local yaw = CFrame.Angles(0, heading, 0)
	-- Local blade position (X right, -Z forward), pushed out to MinBladeForward if it would
	-- otherwise slip under the camera.
	local localX = math.sin(theta) * reach
	local localZ = math.min(-math.cos(theta) * reach, -C.MinBladeForward)
	local flat = rootPosition + yaw:VectorToWorldSpace(Vector3.new(localX, 0, localZ))
	local position = Vector3.new(flat.X, y, flat.Z)

	local toe = yaw:VectorToWorldSpace(Vector3.new(math.sin(blade.toeYaw), 0, -math.cos(blade.toeYaw)))
	local flatPose = CFrame.fromMatrix(position, toe, Vector3.yAxis)
	local target = flatPose * CFrame.Angles(alpha, 0, 0)

	-- Lift: pitch the whole stick (blade + shaft) up around the hands, toe first.
	-- Rotating about the blade's horizontal face normal turns +X (toe) toward +Y (up).
	if liftT > 0 then
		local hands = target:PointToWorldSpace(HANDS_LOCAL)
		local pitch = CFrame.fromAxisAngle(flatPose.ZVector, liftT * C.LiftPitchMax)
		target = CFrame.new(hands) * pitch * CFrame.new(-hands) * target
	end

	return target
end

local function clampMagnitude(v: Vector3, max: number): Vector3
	local m = v.Magnitude
	return if m > max then v * (max / m) else v
end

-- Velocity drive: a P-controller on position and orientation, written straight into the
-- assembly's velocities. No constraint solver state, so client and server stay in step.
local function driveByVelocity(blade: BasePart, target: CFrame, dt: number)
	-- Orientation error as a world-space rotation vector.
	local axis, angle = (target.Rotation * blade.CFrame.Rotation:Inverse()):ToAxisAngle()
	if angle > math.pi then
		angle -= 2 * math.pi
	end
	local omega = clampMagnitude(axis * (angle * C.RotationGain), C.MaxAngularSpeed)

	-- We want the BLADE CENTER to move at bladeVel; the assembly velocity is defined at the
	-- center of mass (up the shaft), so subtract the rotational contribution.
	local bladeVel = clampMagnitude((target.Position - blade.Position) * C.PositionGain, C.MaxSweepSpeed)
	local com = blade.AssemblyCenterOfMass
	local comVel = bladeVel - omega:Cross(blade.Position - com)
	-- Cancel the gravity the step is about to add, so the stick doesn't sag.
	comVel += Vector3.new(0, Config.World.Gravity * dt, 0)

	blade.AssemblyLinearVelocity = comVel
	blade.AssemblyAngularVelocity = omega
end

function StickSim.step(rec: any, input: any, dt: number)
	local root: BasePart = rec.root
	local heading = (root:GetAttribute("Heading") :: number?) or 0
	local target = StickSim.computeTarget(root.Position, heading, input.aim, input.bladeSteps)
	if C.DriveMode == "Velocity" then
		driveByVelocity(rec.blade, target, dt)
	else
		rec.drive.Position = target.Position
		rec.aimAlign.CFrame = target.Rotation
	end
	-- Published for rendering (viewmodel, HUD). Only written on change.
	if root:GetAttribute("BladeSteps") ~= input.bladeSteps then
		root:SetAttribute("BladeSteps", input.bladeSteps)
	end
end

return StickSim
