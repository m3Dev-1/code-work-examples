local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Component = require(ReplicatedStorage.Packages.Component)
local Comm = require(ReplicatedStorage.Packages.Comm).ServerComm.new(ReplicatedStorage, "BoatComm")
local Trove = require(ReplicatedStorage.Packages.Trove)

local Roles = require(ServerScriptService.Modules.Roles)
local Schedules = require(ServerScriptService.Modules.Schedules)

local BoatsFolder = Instance.new("Folder")
BoatsFolder.Name = "StoredBoats"
BoatsFolder.Parent = script

local Assets = ReplicatedStorage:WaitForChild("Assets")
local BoatConfigs = Assets:WaitForChild("BoatConfigs")
local BoatEngine = BoatConfigs:WaitForChild("BoatEngine")

local SEAT_COOLDOWN = 3
local DISTANCE_CHECK_DELAY = 0.25
local DISTANCE_THRESHOLD = 150

local Server = {
	Signals = {
		GrabAlignmentCFrame = Comm:CreateSignal("GrabAlignmentCFrame"),
		BoatExploitCheck = Comm:CreateSignal("BoatExploitCheck"),
	},
}

local Boat = Component.new({
	Tag = "Boat",
	Ancestors = { workspace },
})

function Boat.StoreAll()
	for _, boatComponent in Boat:GetAll() do
		boatComponent.Instance.Parent = BoatsFolder
	end
end

function Boat.RespawnAll()
	for _, boatComponent in Boat:GetAll() do
		boatComponent.Instance:Destroy()
	end

	for _, storedBoat in BoatsFolder:GetChildren() do
		storedBoat:Clone().Parent = workspace
	end
end

function Boat:Construct()
	self.Trove = Trove.new()
	self.lastPosition = self.Instance:GetPivot().Position
	self.lastCheckedTime = os.clock()
	self.massMultiplier = self.Instance.PrimaryPart.AssemblyMass > 1200 and 150 or 125

	if self.Instance:GetAttribute("Initialized") then
		return
	end

	self.Instance:SetAttribute("Initialized", true)

	self.ClonedEngine = BoatEngine:Clone()
	self.ClonedEngine.Parent = self.Instance.DriverSeat

	if not self.Instance.DriverSeat:FindFirstChild("SeatJoint") then
		self.SeatJoint = Instance.new("WeldConstraint")
		self.SeatJoint.Name = "SeatJoint"
		self.SeatJoint.Parent = self.Instance.DriverSeat
		self.SeatJoint.Part0 = self.Instance.DriverSeat
		self.SeatJoint.Part1 = self.Instance.PrimaryPart
	end

	if not self.Instance.DriverSeat:FindFirstChild("ForceAttachment") then
		self.ForceAttachment = Instance.new("Attachment")
		self.ForceAttachment.Name = "ForceAttachment"
		self.ForceAttachment.Parent = self.Instance.DriverSeat
	end

	if not self.Instance.DriverSeat:FindFirstChild("AlignAttachment") then
		self.AlignAttachment = Instance.new("Attachment")
		self.AlignAttachment.Name = "AlignAttachment"
		self.AlignAttachment.Parent = self.Instance.DriverSeat
	end

	self.ClonedEngine.MovementForce.Attachment0 = self.Instance.DriverSeat.ForceAttachment
	self.ClonedEngine.FloatForce.Attachment0 = self.Instance.DriverSeat.ForceAttachment
	self.ClonedEngine.RotationForce.Parent = self.Instance.DriverSeat

	self.Instance.DriverSeat.RotationForce.Attachment0 = self.Instance.DriverSeat.AlignAttachment
	self.ClonedEngine.FloatForce.Force = Vector3.new(0, self.Instance.PrimaryPart.AssemblyMass * self.massMultiplier, 0)
end

function Boat:Start()
	self.Instance.DriverSeat.Disabled = true

	self.Trove:Add(self.Instance.DriverSeat.Touched:Connect(function(touchedPart)
		local player = Players:GetPlayerFromCharacter(touchedPart.Parent)
		if not player then
			return
		end

		self:TrySeatPlayer(player)
	end))

	self.Trove:Add(self.Instance.DriverSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if self.Instance.DriverSeat.Occupant then
			return
		end

		self.Instance:SetAttribute("Owner", "")
		self.SeatDisabled = true

		task.delay(SEAT_COOLDOWN, function()
			self.SeatDisabled = false
		end)
	end))

	self.Trove:Add(Server.Signals.BoatExploitCheck:Connect(function(player, boat, reason)
		if not boat then
			return
		end

		if reason ~= "Boat-Exploitation-Check" then
			return
		end

		local currentOwner = boat:GetAttribute("Owner")
		if currentOwner ~= player.Name then
			return
		end

		boat:Destroy()
	end))

	self.Trove:Add(Server.Signals.GrabAlignmentCFrame:Connect(function(player, boat, cframe)
		if not boat or not cframe then
			return
		end

		local seat = boat:FindFirstChild("DriverSeat")
		if not seat then
			return
		end

		local currentOwner = boat:GetAttribute("Owner")
		if currentOwner ~= player.Name then
			return
		end

		local rotationForce = seat:FindFirstChild("RotationForce")
		if not rotationForce then
			return
		end

		rotationForce.CFrame = cframe
	end))
end

function Boat:Stop()
	self:UnseatDriver()
	self.Trove:Clean()
end

function Boat:SteppedUpdate()
	local currentPosition = self.Instance:GetPivot().Position

	if os.clock() - self.lastCheckedTime <= DISTANCE_CHECK_DELAY then
		return
	end

	local distance = (currentPosition - self.lastPosition).Magnitude
	if distance > DISTANCE_THRESHOLD then
		self.Instance:Destroy()
		return
	end

	self.lastPosition = currentPosition
	self.lastCheckedTime = os.clock()
end

function Boat:GetOccupant(): Player?
	local occupant = self.Instance.DriverSeat.Occupant
	if not occupant then
		return
	end

	return Players:GetPlayerFromCharacter(occupant.Parent)
end

function Boat:TrySeatPlayer(player: Player)
	local driverSeat = self.Instance:FindFirstChild("DriverSeat")
	if not driverSeat then
		return
	end

	if self.SeatDisabled then
		return
	end

	if self:GetOccupant() then
		return
	end

	if not self:CanDrive(player) then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	driverSeat:SetNetworkOwner(player)
	driverSeat:Sit(humanoid)
	self.Instance:SetAttribute("Owner", player.Name)
end

function Boat:UnseatDriver()
	local driverSeat = self.Instance:FindFirstChild("DriverSeat")
	if not driverSeat then
		return
	end

	local seatWeld = driverSeat:FindFirstChild("SeatWeld")
	if not seatWeld then
		return
	end

	seatWeld:Destroy()
end

function Boat:CanDrive(driver: Player)
	if not driver then
		return false
	end

	local role = Roles.GetPlayerRole(driver)
	if not role then
		return false
	end

	return true
end

task.delay(3, function()
	Boat.StoreAll()
	task.wait()
	Boat.RespawnAll()
end)

Schedules.Values.Day.Changed:Connect(function()
	task.wait(3)
	Boat.RespawnAll()
end)

return Boat
