--!strict
-- SkaterSim: momentum skating for one skater, one 60 Hz step.
--
-- Velocity is split into a forward part (along the skates) and a sideways part.
--   * Forward: thrust with a tapering accel curve, braking, backwards skating, slow glide loss.
--   * Sideways: bled off quickly ("edge grip"); part of what's lost is redirected forward.
-- That split is what makes turning feel like carving on ice: velocity swings toward
-- your heading over time, and turn radius naturally grows with speed.
--
-- Spike scope: W/S/A/D only. Sprint, carve, jump and hard stop arrive in Milestone 2.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config)

local C = Config.Skater

local SkaterSim = {}

function SkaterSim.step(rec: any, input: any, dt: number)
	local root: BasePart = rec.root

	-- Heading (yaw). A/D turn; D = turn right = negative yaw in Roblox.
	-- The yaw rate ramps toward the target instead of jumping, so turns ease in and out.
	local heading = (root:GetAttribute("Heading") :: number?) or 0
	local turnVel = (root:GetAttribute("TurnVel") :: number?) or 0
	local targetTurn = -input.move.X * C.TurnRate
	local maxChange = C.TurnAccel * dt
	turnVel += math.clamp(targetTurn - turnVel, -maxChange, maxChange)
	heading += turnVel * dt
	root:SetAttribute("Heading", heading)
	if root:GetAttribute("TurnVel") ~= turnVel then
		root:SetAttribute("TurnVel", turnVel)
	end
	rec.upright.CFrame = CFrame.Angles(0, heading, 0)

	local fwd = Vector3.new(-math.sin(heading), 0, -math.cos(heading))
	local right = Vector3.new(math.cos(heading), 0, -math.sin(heading))

	local v = root.AssemblyLinearVelocity
	local vf = v:Dot(fwd)
	local vr = v:Dot(right)
	local throttle = input.move.Y

	-- Brake ramp: braking force eases in over BrakeRampTime instead of hitting at once.
	local braking = throttle < 0 and vf > 0
	local brakeTime = if braking then ((root:GetAttribute("BrakeTime") :: number?) or 0) + dt else 0
	if root:GetAttribute("BrakeTime") ~= brakeTime then
		root:SetAttribute("BrakeTime", brakeTime)
	end
	local brakeStrength = math.min(1, brakeTime / C.BrakeRampTime)

	if throttle > 0 then
		if vf >= 0 then
			vf += C.ForwardAccel * math.max(0, 1 - vf / C.MaxSpeed) * throttle * dt
		else
			vf = math.min(0, vf + C.BrakeDecel * throttle * dt) -- W while drifting backwards: brake
		end
	elseif throttle < 0 then
		if vf > 0 then
			vf = math.max(0, vf + C.BrakeDecel * brakeStrength * throttle * dt) -- S while moving forward: slow down
		else
			vf -= C.BackwardAccel * math.max(0, 1 + vf / C.BackwardMaxSpeed) * -throttle * dt
		end
	else
		local speed = math.max(0, math.abs(vf) - C.GlideDecel * dt)
		vf = if vf >= 0 then speed else -speed
	end

	-- Edge grip: sideways speed bleeds off, some of it carried into forward speed.
	-- Carving redirects speed but must never create it, so the result is capped at the
	-- horizontal speed going in. (Without the cap, turning or leaning on the boards
	-- accelerated skaters past 50 studs/s; found in the Milestone 0 spike.)
	local speedIn = math.sqrt(vf * vf + vr * vr)
	local newVr = vr * math.exp(-C.EdgeGrip * dt)
	local carried = (math.abs(vr) - math.abs(newVr)) * C.CarveEfficiency
	vf += if vf >= 0 then carried else -carried
	local speedOut = math.sqrt(vf * vf + newVr * newVr)
	if speedOut > speedIn and speedOut > 0 then
		local k = speedIn / speedOut
		vf *= k
		newVr *= k
	end

	root.AssemblyLinearVelocity = fwd * vf + right * newVr + Vector3.new(0, v.Y, 0)
end

return SkaterSim
