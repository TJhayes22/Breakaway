--!strict
-- DevTestHarness (Studio only): hooks for automated playtests driven over MCP.
--   * Adds a Scriptable binding ("TestScript") to each player's Move action so tests can
--     skate without a keyboard.
--   * ServerStorage.TestReset(rootPos, heading, puckPos) puts the first skater and the
--     puck in a known state.
-- Does nothing outside Studio.

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local PuckSim = require(ReplicatedStorage.Simulation.PuckSim)

local function onPlayerAdded(player: Player)
	local move = player:WaitForChild("Inputs"):WaitForChild("Controls"):WaitForChild("Move")
	if not move:FindFirstChild("TestScript") then
		local b = Instance.new("InputBinding")
		b.Name = "TestScript"
		b.Type = Enum.InputBindingType.Scriptable
		b.ClampMagnitudeToOne = false
		b.Parent = move
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayerAdded, p)
end

local reset = Instance.new("BindableFunction")
reset.Name = "TestReset"
reset.OnInvoke = function(rootPos: Vector3, heading: number, puckPos: Vector3)
	local model = workspace.Skaters:GetChildren()[1] :: Model?
	if not model then
		return false
	end
	local root = model:FindFirstChild("Root") :: BasePart
	local blade = (model:FindFirstChild("Stick") :: Model):FindFirstChild("Blade") :: BasePart
	local yaw = CFrame.Angles(0, heading, 0)
	local upright = root:FindFirstChild("Upright") :: AlignOrientation
	root:SetAttribute("Heading", heading)
	upright.CFrame = yaw
	root.CFrame = CFrame.new(rootPos) * yaw
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	blade.CFrame = CFrame.new(rootPos + yaw.LookVector * 3 - Vector3.new(0, 2.6, 0)) * yaw
	blade.AssemblyLinearVelocity = Vector3.zero
	blade.AssemblyAngularVelocity = Vector3.zero
	PuckSim.place(workspace:FindFirstChild("Puck") :: BasePart, puckPos)
	return true
end
reset.Parent = ServerStorage
