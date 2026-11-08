--!strict
-- Simulation: the shared, fixed-step (60 Hz) gameplay simulation.
-- Runs on BOTH server (authoritative) and client (prediction + resimulation)
-- under Server Authority. Everything that affects competitive state happens here.
--
-- Rules for code called from the bound function:
--   * Only touch properties/methods with "Simulation Access".
--   * Read inputs only through InputActions.
--   * Use time(), never tick()/os.clock().
--   * Store custom state in attributes on predicted instances.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local SkaterSim = require(script.SkaterSim)
local StickSim = require(script.StickSim)
local PuckSim = require(script.PuckSim)

export type SkaterInput = {
	move: Vector2, -- X: A/D turn, Y: W/S
	sprint: boolean,
	carve: boolean,
	jump: boolean,
	hardStop: boolean,
	resetPuck: boolean,
	aim: Vector2, -- X: arc position [-1, 1], Y: reach/lift [0, 1]
	bladeSteps: number, -- integer, + = open face
}

export type SkaterRecord = {
	model: Model,
	root: BasePart,
	upright: AlignOrientation,
	blade: BasePart,
	drive: AlignPosition,
	aimAlign: AlignOrientation,
	actions: { [string]: InputAction },
}

local Simulation = {}

local isServer = RunService:IsServer()
local skaters: { [Model]: SkaterRecord } = {}
local puck: BasePart? = nil

local ACTION_NAMES = { "Move", "Sprint", "Carve", "Jump", "HardStop", "ResetPuck", "StickAim", "BladeAngle" }

local function asVector2(v: any): Vector2
	return if typeof(v) == "Vector2" then v else Vector2.zero
end

local function asNumber(v: any): number
	return if typeof(v) == "number" and v == v then v else 0
end

-- Read and sanitize one player's inputs. The server never trusts the raw values.
local function readInput(actions: { [string]: InputAction }): SkaterInput
	local move = asVector2(actions.Move:GetState())
	local aim = asVector2(actions.StickAim:GetState())
	local steps = Config.Stick.BladeAngleSteps
	return {
		move = Vector2.new(math.clamp(move.X, -1, 1), math.clamp(move.Y, -1, 1)),
		sprint = actions.Sprint:GetState() == true,
		carve = actions.Carve:GetState() == true,
		jump = actions.Jump:GetState() == true,
		hardStop = actions.HardStop:GetState() == true,
		resetPuck = actions.ResetPuck:GetState() == true,
		aim = Vector2.new(math.clamp(aim.X, -1, 1), math.clamp(aim.Y, 0, 1)),
		bladeSteps = math.clamp(math.round(asNumber(actions.BladeAngle:GetState()) * steps), -steps, steps),
	}
end

-- Dev/testing: R drops the puck in front of you. Edge-triggered via an attribute so it
-- resimulates correctly.
local function handlePuckReset(rec: SkaterRecord, input: SkaterInput)
	local wasHeld = rec.root:GetAttribute("ResetHeld") == true
	if input.resetPuck ~= wasHeld then
		rec.root:SetAttribute("ResetHeld", input.resetPuck)
	end
	if input.resetPuck and not wasHeld and puck then
		local heading = rec.root:GetAttribute("Heading") :: number? or 0
		local fwd = Vector3.new(-math.sin(heading), 0, -math.cos(heading))
		local pos = rec.root.Position + fwd * 3.5
		PuckSim.place(puck, Vector3.new(pos.X, Config.Puck.StartPosition.Y, pos.Z))
	end
end

local function step(dt: number)
	for _, rec in skaters do
		local input = readInput(rec.actions)
		SkaterSim.step(rec, input, dt)
		StickSim.step(rec, input, dt)
		handlePuckReset(rec, input)
	end
	if puck then
		PuckSim.step(puck, dt)
	end
end

-- Registration happens OUTSIDE the simulation (events + WaitForChild are not simulation-safe).
local function setPredicted(inst: Instance)
	if not isServer then
		RunService:SetPredictionMode(inst, Enum.PredictionMode.On)
	end
end

local function registerSkater(model: Model)
	local userId = model:GetAttribute("UserId")
	local player = if typeof(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	if not player then
		return
	end
	-- The client only simulates its own skater for now. Other skaters render from server
	-- state; forwarding their inputs (Racing-template technique) is Milestone 5.
	if not isServer and player ~= Players.LocalPlayer then
		return
	end

	local root = model:WaitForChild("Root", 10) :: BasePart?
	local stick = model:WaitForChild("Stick", 10)
	local blade = stick and stick:WaitForChild("Blade", 10) :: BasePart?
	local controls = player:WaitForChild("Inputs", 10)
	controls = controls and controls:WaitForChild("Controls", 10)
	if not (root and blade and controls) then
		warn("[Simulation] skater incomplete, not registered:", model:GetFullName())
		return
	end

	local actions: { [string]: InputAction } = {}
	for _, name in ACTION_NAMES do
		actions[name] = controls:WaitForChild(name, 10) :: InputAction
	end

	setPredicted(root)
	setPredicted(blade)
	setPredicted((stick :: Instance):WaitForChild("Shaft", 10) :: Instance)

	skaters[model] = {
		model = model,
		root = root,
		upright = root:WaitForChild("Upright") :: AlignOrientation,
		blade = blade,
		drive = blade:WaitForChild("Drive") :: AlignPosition,
		aimAlign = blade:WaitForChild("Aim") :: AlignOrientation,
		actions = actions,
	}

	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			skaters[model] = nil
		end
	end)
end

function Simulation.Initialize()
	local skaterFolder = workspace:WaitForChild("Skaters")
	skaterFolder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			task.spawn(registerSkater, child)
		end
	end)
	for _, child in skaterFolder:GetChildren() do
		if child:IsA("Model") then
			task.spawn(registerSkater, child)
		end
	end

	task.spawn(function()
		local p = workspace:WaitForChild("Puck") :: BasePart
		setPredicted(p)
		puck = p
	end)

	RunService:BindToSimulation(step, Enum.StepFrequency.Hz60)
end

return Simulation
