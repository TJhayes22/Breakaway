--!strict
-- CameraController: first-person camera locked to the local skater's head.
-- Render-only: reads simulation state, never writes it.
-- Spike scope: follows heading with a downward pitch. RMB free-look and hold-LMB puck
-- tracking come in Milestone 2.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local skaterFolder = workspace:WaitForChild("Skaters")

local root: BasePart? = nil

local function findRoot()
	for _, model in skaterFolder:GetChildren() do
		if model:GetAttribute("UserId") == player.UserId then
			local r = model:FindFirstChild("Root")
			if r and r:IsA("BasePart") then
				r.LocalTransparencyModifier = 1 -- don't render our own body from inside it
				return r
			end
		end
	end
	return nil
end

RunService:BindToRenderStep("BreakawayCamera", Enum.RenderPriority.Camera.Value + 1, function()
	if not (root and root.Parent) then
		root = findRoot()
		if not root then
			return
		end
	end
	local r = root :: BasePart
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = Config.Camera.FieldOfView
	local heading = (r:GetAttribute("Heading") :: number?) or 0
	local eye = r.Position + Vector3.new(0, Config.Skater.EyeHeight, 0)
	camera.CFrame = CFrame.new(eye) * CFrame.Angles(0, heading, 0) * CFrame.Angles(-Config.Camera.PitchDown, 0, 0)
end)
