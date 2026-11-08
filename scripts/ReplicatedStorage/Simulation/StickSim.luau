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
--   aim.Y above LiftStart -> blade lifts off the ice (up to LiftMax)
-- Blade frame: X = long axis, pointing away from the hands (so the shaft always runs back
-- toward the player's hands), Z = face normal.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config)

local C = Config.Stick
local BODY_HALF_HEIGHT = Config.Skater.BodySize.Y / 2

local StickSim = {}

-- Exposed so tests/debug tools can compute the same target the simulation uses.
function StickSim.computeTarget(rootPosition: Vector3, heading: number, aim: Vector2, bladeSteps: number): CFrame
	local theta = if aim.X < 0 then aim.X * C.ArcLeft else aim.X * C.ArcRight
	local reachT = math.min(aim.Y / C.LiftStart, 1)
	local reach = C.ReachMin + (C.ReachMax - C.ReachMin) * reachT
	local lift = if aim.Y > C.LiftStart then (aim.Y - C.LiftStart) / (1 - C.LiftStart) * C.LiftMax else 0

	-- Face tilt. With this frame, +X rotation tips the +Z face down (closed).
	-- Left shot: forehand is the +Z face, so "open" = negative rotation. Right shot: mirrored.
	local tilt = bladeSteps * C.BladeAngleStep
	local alpha = if C.Handedness == "Left" then -tilt else tilt

	-- Keep the lowest edge of the (possibly tilted) blade just above the ice.
	local halfExtent = 0.5 * (C.BladeSize.Y * math.cos(alpha) + C.BladeSize.Z * math.abs(math.sin(alpha)))
	local iceY = rootPosition.Y - BODY_HALF_HEIGHT
	local y = iceY + halfExtent + C.IceClearance + lift

	local yaw = CFrame.Angles(0, heading, 0)
	-- Local blade position (X right, -Z forward), pushed out to MinBladeForward if it would
	-- otherwise slip under the camera.
	local localX = math.sin(theta) * reach
	local localZ = math.min(-math.cos(theta) * reach, -C.MinBladeForward)
	local radial = yaw:VectorToWorldSpace(Vector3.new(localX, 0, localZ).Unit)
	local flat = rootPosition + yaw:VectorToWorldSpace(Vector3.new(localX, 0, localZ))
	local position = Vector3.new(flat.X, y, flat.Z)

	-- Point the blade (and therefore the shaft) along the line from the hands to the blade.
	local hand = C.HandOffset
	if C.Handedness ~= "Left" then
		hand = Vector3.new(-hand.X, hand.Y, hand.Z)
	end
	local handWorld = rootPosition + yaw:VectorToWorldSpace(hand)
	local along = Vector3.new(flat.X - handWorld.X, 0, flat.Z - handWorld.Z)
	local xAxis = if along.Magnitude > 0.1 then along.Unit else radial

	return CFrame.fromMatrix(position, xAxis, Vector3.yAxis) * CFrame.Angles(alpha, 0, 0)
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
