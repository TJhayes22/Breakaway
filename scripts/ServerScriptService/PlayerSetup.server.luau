--!strict
-- PlayerSetup: gives each joining player their inputs and a physics skater + stick.
-- Runs outside the simulation (creates/destroys instances on join/leave only).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local StickSim = require(ReplicatedStorage.Simulation.StickSim)

local SPAWN = Vector3.new(0, Config.Skater.BodySize.Y / 2 + 0.05, 12) -- facing -Z, toward center ice

local skaterFolder = workspace:FindFirstChild("Skaters") or Instance.new("Folder")
skaterFolder.Name = "Skaters"
skaterFolder.Parent = workspace

local function frictionless(density: number): PhysicalProperties
	return PhysicalProperties.new(density, 0, 0.1, 100, 1)
end

local function buildStick(model: Model, rootCFrame: CFrame)
	local S = Config.Stick
	local stick = Instance.new("Model")
	stick.Name = "Stick"

	local blade = Instance.new("Part")
	blade.Name = "Blade"
	blade.Size = S.BladeSize
	blade.Color = Color3.fromRGB(30, 30, 35)
	blade.Material = Enum.Material.SmoothPlastic
	blade.CustomPhysicalProperties = frictionless(S.Density)
	blade.CollisionGroup = "Sticks"
	-- The blade must be the assembly root: the simulation writes the stick's velocities
	-- through it, and under Server Authority only the root part's state replicates. With
	-- the shaft as root, every step reported a false misprediction (Milestone 0 finding).
	blade.RootPriority = 10
	blade.CFrame = rootCFrame * CFrame.new(0, -Config.Skater.BodySize.Y / 2 + 0.2, -3)
	blade.Parent = stick

	-- Shaft: two physics parts (lower shaft + handle), NOT welded (docs/STICK_DESIGN.md
	-- option B2, §10.4). StickSim places them every step on the line from the blade's heel
	-- toward the hands; they telescope (overlap more as the blade comes in). They hit pucks
	-- and other sticks only: never skaters, and never ice/boards (a shaft that hit the ice
	-- wedged the whole stick in the Milestone 0 spike).
	local hands = StickSim.handAnchor(rootCFrame.Position, 0, Vector2.new(0, 0.5))
	local shaftCF, gripCF = StickSim.shaftTargets(blade.CFrame, hands)
	local function shaftPart(name: string, thickness: number, length: number, color: Color3, cf: CFrame): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = Vector3.new(thickness, thickness, length) -- long axis = Z
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.CustomPhysicalProperties = frictionless(S.ShaftDensity)
		p.CollisionGroup = "Shafts"
		p.CFrame = cf
		p.Parent = stick
		return p
	end
	local shaft = shaftPart("Shaft", S.ShaftThickness, S.ShaftLength, Color3.fromRGB(200, 60, 40), shaftCF)
	local handle = shaftPart("Handle", S.GripThickness, S.GripLength, Color3.fromRGB(35, 35, 40), gripCF)

	-- The player's own stick pieces overlap; they must never push each other.
	for _, pair in { { blade, shaft }, { blade, handle }, { shaft, handle } } do
		local noCollide = Instance.new("NoCollisionConstraint")
		noCollide.Part0 = pair[1]
		noCollide.Part1 = pair[2]
		noCollide.Parent = pair[1]
	end

	local grip = Instance.new("Attachment")
	grip.Name = "Grip"
	grip.Parent = blade

	local drive = Instance.new("AlignPosition")
	drive.Name = "Drive"
	drive.Mode = Enum.PositionAlignmentMode.OneAttachment
	drive.Attachment0 = grip
	-- Must be false: when true, AlignPosition moves the assembly's center of mass (up the
	-- shaft) to the target, which drives the blade ~2 studs off target and into the ice.
	drive.ApplyAtCenterOfMass = false
	drive.MaxForce = 1e6
	drive.MaxVelocity = S.MaxSweepSpeed
	drive.Responsiveness = S.PositionResponsiveness
	drive.Position = blade.Position
	drive.Parent = blade

	local aim = Instance.new("AlignOrientation")
	aim.Name = "Aim"
	aim.Mode = Enum.OrientationAlignmentMode.OneAttachment
	aim.Attachment0 = grip
	aim.MaxTorque = 1e6
	aim.MaxAngularVelocity = S.MaxAngularSpeed
	aim.Responsiveness = S.OrientationResponsiveness
	aim.CFrame = blade.CFrame.Rotation
	aim.Parent = blade

	-- Only one drive method may be active (see Config.Stick.DriveMode).
	local useConstraints = S.DriveMode == "Constraint"
	drive.Enabled = useConstraints
	aim.Enabled = useConstraints

	stick.Parent = model
end

local function buildSkater(player: Player): Model
	local K = Config.Skater
	local model = Instance.new("Model")
	model.Name = "Skater_" .. player.Name
	model:SetAttribute("UserId", player.UserId)

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = K.BodySize
	root.CFrame = CFrame.new(SPAWN)
	root.Color = Color3.fromRGB(40, 90, 200)
	root.Material = Enum.Material.SmoothPlastic
	root.CustomPhysicalProperties = frictionless(K.BodyDensity)
	root.CollisionGroup = "Skaters"
	root:SetAttribute("Heading", 0)
	root.Parent = model
	model.PrimaryPart = root

	local att = Instance.new("Attachment")
	att.Name = "Center"
	att.Parent = root

	-- Keeps the body upright and facing the heading. Yaw comes from SkaterSim.
	local upright = Instance.new("AlignOrientation")
	upright.Name = "Upright"
	upright.Mode = Enum.OrientationAlignmentMode.OneAttachment
	upright.Attachment0 = att
	upright.MaxTorque = 1e7
	upright.Responsiveness = K.UprightResponsiveness
	upright.CFrame = CFrame.identity
	upright.Parent = root

	buildStick(model, root.CFrame)
	return model
end

local skaters: { [Player]: Model } = {}

local function onPlayerAdded(player: Player)
	local inputs = ReplicatedStorage.Inputs:Clone()
	inputs.Parent = player

	local model = buildSkater(player)
	model.Parent = skaterFolder
	skaters[player] = model
	player.ReplicationFocus = model.PrimaryPart
end

local function onPlayerRemoving(player: Player)
	local model = skaters[player]
	if model then
		model:Destroy()
		skaters[player] = nil
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
