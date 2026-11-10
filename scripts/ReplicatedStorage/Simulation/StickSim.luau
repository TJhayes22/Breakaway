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
--   aim.Y above LiftStart -> the blade swings up around the hands (handAnchor), toe first,
--                            like raising a baseball bat (up to LiftPitchMax)
-- Blade yaw (see computeBladeYaw and BLADE_YAW below), modeled on Puck reference video:
--   the toe always points AWAY from the middle, so the shaft runs back toward the body.
--   Stick on the right: toe right, the face on that side faces forward (forehand for a
--   right shot). Stick on the left: toe left, the other face forward (backhand). Crossing
--   the middle, the blade rotates through toe-forward (the forehand/backhand flip).
--   At the sides the forward face angles inward; pulled back it is square.
-- Blade frame: X = long axis toward the toe, Y = up, Z = X cross Y. Forehand is -Z for a
-- right shot, +Z for a left shot. The heel (-X end) is the end nearest the middle.
--
-- The shaft is two physics parts (lower shaft + handle), not welded (docs/STICK_DESIGN.md
-- option B2 and §10). Each step they are placed on one line from the blade's heel toward
-- the hands, in the blade's own plane, so blade and shaft always read as one stick. When
-- extended, the toe follows the hands line (HandsLineBlend) so that line reaches the
-- hands. All pieces collide with the puck, never with skaters.

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
	-- Scroll tilt (STICK_DESIGN.md §10.7): the forward face keeps the same tilt on forehand
	-- and backhand. The switch between faces eases in while the toe is within this angle of
	-- straight ahead (blade nearest edge-on), so it rolls over smoothly as the blade turns.
	TiltFlipWidth = math.rad(40),
}

local HEEL_LOCAL = Vector3.new(-C.BladeSize.X / 2, 0, 0)

local StickSim = {}

-- Blade target position in the skater's frame (X right, -Z forward), before lift: arc
-- angle from aim.X, reach from aim.Y, never closer than MinBladeForward in front.
local function bladeLocalXZ(aim: Vector2): (number, number)
	local theta = if aim.X < 0 then aim.X * C.ArcLeft else aim.X * C.ArcRight
	local reachT = math.min(aim.Y / C.LiftStart, 1)
	local reach = C.ReachMin + (C.ReachMax - C.ReachMin) * reachT
	return math.sin(theta) * reach, math.min(-math.cos(theta) * reach, -C.MinBladeForward)
end

-- Where the hands hold the stick, in the skater's frame (X right, -Z forward): HandAnchor
-- (mirrored for a left shot), drifting sideways opposite the blade like the Puck reference
-- video. A pure function of the aim, so client and server always agree.
local function handsLocalXZ(aim: Vector2): (number, number)
	local bladeX = bladeLocalXZ(aim)
	local h = C.HandAnchor
	local baseX = if C.Handedness == "Left" then -h.X else h.X
	local swing = math.clamp(-C.HandSwing * bladeX, -C.HandSwingMax, C.HandSwingMax)
	return baseX + swing, h.Z
end

-- The hands point in world space.
function StickSim.handAnchor(rootPosition: Vector3, heading: number, aim: Vector2): Vector3
	local hx, hz = handsLocalXZ(aim)
	return rootPosition + CFrame.Angles(0, heading, 0):VectorToWorldSpace(Vector3.new(hx, C.HandAnchor.Y, hz))
end

-- Shaft poses for a blade pose (STICK_DESIGN.md §10.4: telescoping shaft). Both pieces lie
-- on one line that starts at the heel and stays in the vertical plane through the blade's
-- long axis (so it follows the blade's direction and lift, but not the scroll tilt, which
-- turns the blade around its own long axis); within that plane it points as close to the
-- hands as it can. The lower shaft starts at the heel; the handle (grip) ends ButtOverhang
-- past the hands. They overlap more the closer the blade is to the hands.
-- Returns the two center CFrames, LookVector running from the heel toward the butt.
function StickSim.shaftTargets(bladeCF: CFrame, hands: Vector3): (CFrame, CFrame)
	local heel = bladeCF:PointToWorldSpace(HEEL_LOCAL)
	local flat = bladeCF.XVector:Cross(Vector3.yAxis)
	local normal = if flat.Magnitude > 1e-3 then flat.Unit else bladeCF.ZVector
	local v = hands - heel
	v -= normal * v:Dot(normal)
	local dir: Vector3
	if v:Dot(-bladeCF.XVector) > 0.1 * v.Magnitude then
		dir = v.Unit
	else
		-- Hands ahead of the heel (shouldn't happen in play): fall back to the default lie.
		dir = (-bladeCF.XVector * math.cos(C.LieAngle) + bladeCF.YVector * math.sin(C.LieAngle)).Unit
	end
	local L = C.ShaftLength
	local shaftCF = CFrame.lookAt(heel + dir * (L / 2), heel + dir * L, normal)
	-- Handle: butt end ButtOverhang past the point on the line nearest the hands, never
	-- reaching below the heel.
	local G = C.GripLength
	local butt = math.max((hands - heel):Dot(dir), 0) + C.ButtOverhang
	local gripCenter = heel + dir * (math.max(butt - G, 0) + G / 2)
	local gripCF = CFrame.lookAt(gripCenter, gripCenter + dir, normal)
	return shaftCF, gripCF
end

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
	tiltSign: number, -- -1..1: which face the scroll tilt applies to (follows the toe, §10.7)
	modelToeYaw: number, -- the approved yaw model alone (§2), before the hands-line blend
	lineYaw: number, -- direction from the hands to the blade target (§10.3)
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
	local modelToeYaw = flip * (math.pi / 2 - math.abs(faceYaw))
	-- Hands-line blend (STICK_DESIGN.md §10.3): extended, the toe turns toward the line from
	-- the hands to the blade, so the shaft (in line with the blade) runs back to the hands.
	-- Pulled back it fades out, keeping the square blade.
	local bx, bz = bladeLocalXZ(aim)
	local hx, hz = handsLocalXZ(aim)
	local lineYaw = math.atan2(bx - hx, -(bz - hz))
	local diff = (lineYaw - modelToeYaw + math.pi) % (2 * math.pi) - math.pi
	local lineWeight = C.HandsLineBlend * (1 - pullBack)
	local toeYaw = modelToeYaw + lineWeight * diff
	-- Forward face from the actual toe: forehand (toe right) faces toe - 90, backhand toe + 90.
	faceYaw = toeYaw - (if toeYaw >= 0 then math.pi / 2 else -math.pi / 2)
	-- Scroll tilt goes to whichever face is forward (STICK_DESIGN.md §10.7). Its switch
	-- follows whatever drives the yaw: pulled back, the model's flip (the blade spins 180 deg
	-- across it); extended, the toe passing straight ahead (the blade turns gradually).
	local toeSign = 2 * smoothstep((toeYaw + Y.TiltFlipWidth) / (2 * Y.TiltFlipWidth)) - 1
	local tiltSign = flip + lineWeight * (toeSign - flip)
	return {
		toeYaw = toeYaw,
		faceYaw = faceYaw,
		flip = flip,
		lateral = lateral,
		depth = depth,
		sideWeight = sideWeight,
		pullBack = pullBack,
		modelToeYaw = modelToeYaw,
		lineYaw = lineYaw,
		tiltSign = tiltSign,
	}
end

-- Exposed so tests/debug tools can compute the same target the simulation uses.
function StickSim.computeTarget(rootPosition: Vector3, heading: number, aim: Vector2, bladeSteps: number): CFrame
	local liftT = if aim.Y > C.LiftStart then (aim.Y - C.LiftStart) / (1 - C.LiftStart) else 0

	local blade = StickSim.computeBladeYaw(aim)

	-- Face tilt (scroll) tilts whichever face is forward. With this frame, +X rotation tips
	-- the +Z face down. Toe right (tiltSign > 0): -Z faces forward. tiltSign follows the
	-- blade's actual toe, so the switch happens as the blade turns edge-on, not as a snap.
	-- Sign set by playtest (2026-11-09: "should be inverted back to how it was"); flip the
	-- leading minus to reverse the scroll direction.
	local tilt = bladeSteps * C.BladeAngleStep
	local alpha = -tilt * blade.tiltSign

	-- Keep the lowest edge of the (possibly tilted) blade just above the ice.
	local halfExtent = 0.5 * (C.BladeSize.Y * math.cos(alpha) + C.BladeSize.Z * math.abs(math.sin(alpha)))
	local iceY = rootPosition.Y - BODY_HALF_HEIGHT
	local y = iceY + halfExtent + C.IceClearance

	local yaw = CFrame.Angles(0, heading, 0)
	local localX, localZ = bladeLocalXZ(aim)
	local flat = rootPosition + yaw:VectorToWorldSpace(Vector3.new(localX, 0, localZ))
	local position = Vector3.new(flat.X, y, flat.Z)

	local toe = yaw:VectorToWorldSpace(Vector3.new(math.sin(blade.toeYaw), 0, -math.cos(blade.toeYaw)))
	local flatPose = CFrame.fromMatrix(position, toe, Vector3.yAxis)
	local target = flatPose * CFrame.Angles(alpha, 0, 0)

	-- Lift: swing the blade up around the hands, like raising a baseball bat. The axis is
	-- horizontal and perpendicular to the hands-to-blade line, so the blade rises along
	-- that line and its toe tips up with it. The shaft follows on its own.
	if liftT > 0 then
		local hands = StickSim.handAnchor(rootPosition, heading, aim)
		local out = Vector3.new(position.X - hands.X, 0, position.Z - hands.Z)
		if out.Magnitude > 1e-3 then
			local pitch = CFrame.fromAxisAngle(out.Unit:Cross(Vector3.yAxis), liftT * C.LiftPitchMax)
			target = CFrame.new(hands) * pitch * CFrame.new(-hands) * target
		end
	end

	return target
end

local function clampMagnitude(v: Vector3, max: number): Vector3
	local m = v.Magnitude
	return if m > max then v * (max / m) else v
end

-- Velocity drive: a P-controller on position and orientation, written straight into the
-- assembly's velocities. No constraint solver state, so client and server stay in step.
local function driveByVelocity(blade: BasePart, target: CFrame, dt: number): (Vector3, Vector3)
	-- Orientation error as a world-space rotation vector.
	local axis, angle = (target.Rotation * blade.CFrame.Rotation:Inverse()):ToAxisAngle()
	if angle > math.pi then
		angle -= 2 * math.pi
	end
	local omega = clampMagnitude(axis * (angle * C.RotationGain), C.MaxAngularSpeed)

	-- We want the BLADE CENTER to move at bladeVel; the assembly velocity is defined at the
	-- center of mass, so subtract the rotational contribution (zero for a lone blade).
	local bladeVel = clampMagnitude((target.Position - blade.Position) * C.PositionGain, C.MaxSweepSpeed)
	local com = blade.AssemblyCenterOfMass
	local comVel = bladeVel - omega:Cross(blade.Position - com)
	-- Cancel the gravity the step is about to add, so the stick doesn't sag.
	comVel += Vector3.new(0, Config.World.Gravity * dt, 0)

	blade.AssemblyLinearVelocity = comVel
	blade.AssemblyAngularVelocity = omega
	return bladeVel, omega
end

-- Where the blade will be at the end of this step, given the velocities just written
-- (gravity is cancelled, so it moves exactly at bladeVel / omega).
local function predictBlade(blade: BasePart, bladeVel: Vector3, omega: Vector3, dt: number): CFrame
	local rot = blade.CFrame.Rotation
	local w = omega.Magnitude
	if w > 1e-6 then
		rot = CFrame.fromAxisAngle(omega / w, w * dt) * rot
	end
	return CFrame.new(blade.Position + bladeVel * dt) * rot
end

-- Shaft drive: deadbeat (closes the whole error in one step), so the shaft stays attached
-- to the blade instead of trailing it. Same velocity-writing approach as the blade.
local function driveShaft(shaft: BasePart, target: CFrame, dt: number)
	local axis, angle = (target.Rotation * shaft.CFrame.Rotation:Inverse()):ToAxisAngle()
	if angle > math.pi then
		angle -= 2 * math.pi
	end
	local omega = clampMagnitude(axis * (angle / dt), C.ShaftMaxAngularSpeed)
	local vel = clampMagnitude((target.Position - shaft.Position) / dt, C.ShaftMaxSpeed)
	vel -= omega:Cross(shaft.Position - shaft.AssemblyCenterOfMass)
	vel += Vector3.new(0, Config.World.Gravity * dt, 0)
	shaft.AssemblyLinearVelocity = vel
	shaft.AssemblyAngularVelocity = omega
end

function StickSim.step(rec: any, input: any, dt: number)
	local root: BasePart = rec.root
	local heading = (root:GetAttribute("Heading") :: number?) or 0
	local target = StickSim.computeTarget(root.Position, heading, input.aim, input.bladeSteps)
	local bladeNext: CFrame
	if C.DriveMode == "Velocity" then
		local bladeVel, omega = driveByVelocity(rec.blade, target, dt)
		bladeNext = predictBlade(rec.blade, bladeVel, omega, dt)
	else
		rec.drive.Position = target.Position
		rec.aimAlign.CFrame = target.Rotation
		bladeNext = rec.blade.CFrame
	end

	-- Shaft: from where the blade will be at the end of this step toward where the hands
	-- will be (the body moves during the step too), so it doesn't trail during sweeps.
	local rootNext = root.Position + root.AssemblyLinearVelocity * dt
	local hands = StickSim.handAnchor(rootNext, heading, input.aim)
	local shaftCF, gripCF = StickSim.shaftTargets(bladeNext, hands)
	driveShaft(rec.shaft, shaftCF, dt)
	driveShaft(rec.handle, gripCF, dt)
	-- Published for rendering (viewmodel, HUD). Only written on change.
	if root:GetAttribute("BladeSteps") ~= input.bladeSteps then
		root:SetAttribute("BladeSteps", input.bladeSteps)
	end
end

return StickSim
