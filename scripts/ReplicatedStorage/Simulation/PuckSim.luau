--!strict
-- PuckSim: puck adjustments on top of Roblox physics, one 60 Hz step.
-- Collisions (blade, boards, skaters) are resolved by the physics engine. This module
-- only adds what the engine doesn't model the way we want:
--   * ice drag (the puck and ice are frictionless; drag is ours, so it's tunable),
--   * spin decay,
--   * a hard speed cap,
--   * out-of-bounds reset.
-- Later: grip assist while on the blade, exit-trajectory cleanup.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config)

local C = Config.Puck
local FLAT = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis is X; stand it flat

local PuckSim = {}

function PuckSim.place(puck: BasePart, position: Vector3)
	puck.CFrame = CFrame.new(position) * FLAT
	puck.AssemblyLinearVelocity = Vector3.zero
	puck.AssemblyAngularVelocity = Vector3.zero
end

function PuckSim.step(puck: BasePart, dt: number)
	if puck.Position.Y < C.KillY then
		PuckSim.place(puck, C.StartPosition)
		return
	end

	local v = puck.AssemblyLinearVelocity
	local keep = math.max(0, 1 - C.LinearDrag * dt)
	local newV = Vector3.new(v.X * keep, v.Y, v.Z * keep)
	if newV.Magnitude > C.MaxSpeed then
		newV = newV.Unit * C.MaxSpeed
	end
	puck.AssemblyLinearVelocity = newV
	puck.AssemblyAngularVelocity *= math.max(0, 1 - C.AngularDrag * dt)
end

return PuckSim
