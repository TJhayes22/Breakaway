--!strict
-- DebugOverlay (dev only): on-screen readout of skater/stick/puck state plus Server
-- Authority health. Misprediction stats aren't available to game scripts
-- (RunService.Misprediction is plugin-only); use Studio's Server Authority visualizer
-- (Ctrl+Shift+F6) or the MCP measurement snippet for those.
--
-- F2 toggles the blade-yaw readout (also settable via the player attribute "StickDebug").

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local StickSim = require(ReplicatedStorage.Simulation.StickSim)

local player = Players.LocalPlayer
local stickAim = player:WaitForChild("Inputs"):WaitForChild("Controls"):WaitForChild("StickAim") :: InputAction
local lastPrint = 0
local skaterFolder = workspace:WaitForChild("Skaters")
local puck = workspace:WaitForChild("Puck") :: BasePart

local gui = Instance.new("ScreenGui")
gui.Name = "DebugOverlay"
gui.ResetOnSpawn = false
local label = Instance.new("TextLabel")
label.Size = UDim2.fromOffset(380, 110)
label.Position = UDim2.fromOffset(10, 10)
label.BackgroundTransparency = 0.4
label.BackgroundColor3 = Color3.new(0, 0, 0)
label.TextColor3 = Color3.new(1, 1, 1)
label.Font = Enum.Font.Code
label.TextSize = 14
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Top
label.Parent = gui
gui.Parent = player:WaitForChild("PlayerGui")

local function myRoot(): BasePart?
	for _, model in skaterFolder:GetChildren() do
		if model:GetAttribute("UserId") == player.UserId then
			return model:FindFirstChild("Root") :: BasePart?
		end
	end
	return nil
end

local function status(inst: Instance?): string
	if not inst then
		return "-"
	end
	local ok, s = pcall(function()
		return RunService:GetPredictionStatus(inst)
	end)
	return if ok then tostring(s):gsub("^Enum%.%w+%.", "") else "err"
end

RunService.RenderStepped:Connect(function()
	local root = myRoot()
	local blade = root and root.Parent and root.Parent:FindFirstChild("Stick") and (root.Parent :: Instance).Stick:FindFirstChild("Blade") :: BasePart?
	local speed = if root then Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude else 0
	local bladeSpeed = if blade then blade.AssemblyLinearVelocity.Magnitude else 0
	label.Text = table.concat({
		string.format(" skater  %5.1f studs/s  heading %4.0f deg", speed, math.deg((root and root:GetAttribute("Heading") :: number?) or 0)),
		string.format(" blade   %5.1f studs/s", bladeSpeed),
		string.format(" puck    %5.1f studs/s  y=%.2f", puck.AssemblyLinearVelocity.Magnitude, puck.Position.Y),
		string.format(" predict root=%s blade=%s puck=%s", status(root), status(blade), status(puck)),
		string.format(" blade steps %s", tostring((root and root:GetAttribute("BladeSteps")) or "-")),
		" WASD skate | mouse stick | scroll blade | R puck | F2 stick debug",
	}, "\n")

	if player:GetAttribute("StickDebug") == true then
		local state = stickAim:GetState()
		local aim = if typeof(state) == "Vector2" then state else Vector2.zero
		local b = StickSim.computeBladeYaw(aim)
		local side = if math.abs(b.lateral) <= StickSim.BLADE_YAW.FlipWidth then "middle" elseif b.lateral > 0 then "right" else "left"
		-- Forehand forward when the toe points to the forehand side (right for a right shot).
		local forehandToe = if Config.Stick.Handedness == "Left" then -1 else 1
		local face = if math.abs(b.flip) < 0.5 then "flipping" elseif b.flip * forehandToe > 0 then "FOREHAND" else "BACKHAND"
		-- Measured: the actual blade's toe yaw relative to the heading, to compare with target.
		local measured = "-"
		if root and blade then
			local x = CFrame.Angles(0, (root:GetAttribute("Heading") :: number?) or 0, 0):VectorToObjectSpace(blade.CFrame.XVector)
			measured = string.format("%+.1f", math.deg(math.atan2(x.X, -x.Z)))
		end
		local lines = {
			string.format(" STICK lateral %+.2f  depth %.2f  side %s  face %s", b.lateral, b.depth, side, face),
			string.format(" face %+.1f deg  toe target %+.1f / blade %s deg", math.deg(b.faceYaw), math.deg(b.toeYaw), measured),
			string.format(" flip %+.2f  side %.2f  pullback %.2f", b.flip, b.sideWeight, b.pullBack),
		}
		label.Size = UDim2.fromOffset(430, 165)
		label.Text ..= "\n" .. table.concat(lines, "\n")
		local now = os.clock()
		if now - lastPrint > 0.5 then
			lastPrint = now
			print("[StickDebug]" .. table.concat(lines, " |"))
		end
	else
		label.Size = UDim2.fromOffset(380, 110)
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.F2 then
		player:SetAttribute("StickDebug", player:GetAttribute("StickDebug") ~= true)
	end
end)
