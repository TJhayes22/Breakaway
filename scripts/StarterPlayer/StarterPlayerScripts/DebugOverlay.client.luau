--!strict
-- DebugOverlay (dev only): on-screen readout of skater/stick/puck state plus Server
-- Authority health. Misprediction stats aren't available to game scripts
-- (RunService.Misprediction is plugin-only); use Studio's Server Authority visualizer
-- (Ctrl+Shift+F6) or the MCP measurement snippet for those.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
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
		" WASD skate | mouse stick | scroll blade | R puck",
	}, "\n")
end)
