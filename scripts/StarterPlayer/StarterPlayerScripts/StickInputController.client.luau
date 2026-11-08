--!strict
-- StickInputController: mouse -> stick aim, scroll -> blade angle.
--
-- The client sends an ABSOLUTE aim (not mouse deltas) through Scriptable input bindings.
-- Absolute values survive dropped/late inputs without drift, and the server clamps them.
-- Scroll up opens the blade face (lifts the puck), scroll down closes it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)

local player = Players.LocalPlayer
local controls = player:WaitForChild("Inputs"):WaitForChild("Controls")
local aimBinding = controls:WaitForChild("StickAim"):WaitForChild("Script") :: InputBinding
local bladeBinding = controls:WaitForChild("BladeAngle"):WaitForChild("Script") :: InputBinding

local STEPS = Config.Stick.BladeAngleSteps
local sensX = Config.Input.StickSensitivityX
local sensY = Config.Input.StickSensitivityY

-- Start with the blade out front on the forehand side.
local aim = Vector2.new(if Config.Stick.Handedness == "Left" then -0.3 else 0.3, 0.45)
local bladeSteps = 0

aimBinding:Fire(aim)
bladeBinding:Fire(0)

RunService.RenderStepped:Connect(function()
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false

	local delta = UserInputService:GetMouseDelta()
	if delta.X ~= 0 or delta.Y ~= 0 then
		aim = Vector2.new(
			math.clamp(aim.X + delta.X * sensX, -1, 1),
			math.clamp(aim.Y - delta.Y * sensY, 0, 1) -- mouse forward = reach out
		)
		aimBinding:Fire(aim)
	end
end)

UserInputService.InputChanged:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.MouseWheel then
		return
	end
	if input.Position.Z > 0 then
		bladeSteps = math.min(bladeSteps + 1, STEPS) -- scroll up: open
	elseif input.Position.Z < 0 then
		bladeSteps = math.max(bladeSteps - 1, -STEPS) -- scroll down: close
	end
	bladeBinding:Fire(bladeSteps / STEPS)
end)
