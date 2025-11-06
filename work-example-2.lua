local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
 
local Component = require(ReplicatedStorage.Packages.Component)
local ComponentExtensions = require(ReplicatedStorage.Packages.ComponentExtensions)
local Comm = require(ReplicatedStorage.Packages.Comm).ServerComm.new(ReplicatedStorage, "BoatComm")
 
local Trove = require(ReplicatedStorage.Packages.Trove)
local Waiter = require(ReplicatedStorage.Packages.Waiter)
 
local Roles = require(ServerScriptService.Modules.Roles)
local Schedules = require(ServerScriptService.Modules.Schedules)
 
local BoatsFolder = Instance.new("Folder")
BoatsFolder.Name = "StoredBoats"
BoatsFolder.Parent = script
 
local Assets = ReplicatedStorage:WaitForChild("Assets")
local BoatConfigs = Assets.BoatConfigs
local BoatEngine = BoatConfigs.BoatEngine
 
local SEAT_COOLDOWN = 3
local DISTANCE_CHECK_DELAY = 0.25
local DISTANCE_THRESHOLD = 150
local RESTRICTIVE_ANGLE = 90
 
 
local Server = {
    Signals = {
        GrabAlignmentCFrame = Comm:CreateSignal("GrabAlignmentCFrame"),
        BoatExploitCheck = Comm:CreateSignal("BoatExploitCheck")
    },
}
 
local Boat = Component.new {
    Tag = "Boat",
    Ancestors = { workspace },
    Extensions = {
    },
}
 
function Boat.StoreAll()
    for _, Boat in Boat:GetAll() do
        Boat.Instance.Parent = BoatsFolder
    end
end
 
function Boat.RespawnAll()
    for _, Boat in Boat:GetAll() do
        Boat.Instance:Destroy()
    end
    for _, Boat in BoatsFolder:GetChildren() do
        Boat = Boat:Clone()
        Boat.Parent = workspace
    end
end
 
function Boat:Construct()
    self.Trove = Trove.new()
    self.lastPosition = self.Instance:GetPivot().Position
    self.lastCheckedTime = os.clock()
 
    self.massMultiplier = self.Instance.PrimaryPart.AssemblyMass > 1200 and 150 or 125
 
    if self.Instance:GetAttribute("Initialized") then return end
    self.Instance:SetAttribute("Initialized", true)
 
 
    self.ClonedEngine = BoatEngine:Clone()
    self.ClonedEngine.Parent = self.Instance.DriverSeat
 
    if not self.Instance.DriverSeat:FindFirstChild("SeatJoint") then
        self.SeatJoint = Instance.new("WeldConstraint")
        self.SeatJoint.Name = "SeatJoint"
        self.SeatJoint.Parent = self.Instance.DriverSeat
        self.SeatJoint.Part0 = self.Instance.DriverSeat
        self.SeatJoint.Part1 = self.Instance.Parent.PrimaryPart
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
    self.ClonedEngine.FloatForce.Force = Vector3.new(0, (self.Instance.PrimaryPart.AssemblyMass * self.massMultiplier), 0) --// used to use MASS_MULTIPLIER
end
 
 
 
function Boat:Start()
    self.Instance.DriverSeat.Disabled = true
    self.Trove:Add(self.Instance.DriverSeat.Touched:Connect(function(touchedPart)
        local player = Players:GetPlayerFromCharacter(touchedPart.Parent)
        if player == nil then return end
        self:TrySeatPlayer(player)
    end))
    self.Trove:Add(self.Instance.DriverSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
        if self.Instance.DriverSeat.Occupant ~= nil then return end
        self.Instance:SetAttribute("Owner", "")
        self.SeatDisabled = true
        task.wait(SEAT_COOLDOWN)
        self.SeatDisabled = false
    end))
 
    self.Trove:Add(Server.Signals.BoatExploitCheck:Connect(function(player, boat, reason)
        if boat == nil then return end
        if reason == nil then return end
        if reason ~= "Boat-Exploitation-Check" then return end
 
        local currentOwner = boat:GetAttribute("Owner")
        if currentOwner == nil then return end 
        if currentOwner ~= player.Name then return end 
 
        boat:Destroy()
    end))
 
 
    Server.Signals.GrabAlignmentCFrame:Connect(function(player, boat, cframe)
        if boat == nil then return warn("doing end boat") end 
        if cframe == nil then return warn("doing end cframe") end 
 
        local seat = boat:FindFirstChild("DriverSeat")
        if seat == nil then warn("doing end seat") return end
 
        boat.DriverSeat.RotationForce.CFrame = cframe
 
    end)
end
 
 
function Boat:Stop()
    self:UnseatDriver()
    self.Trove:Clean()
end
 
function Boat:SteppedUpdate()
    local currentPosition = self.Instance:GetPivot().Position
    if os.clock() - self.lastCheckedTime <= DISTANCE_CHECK_DELAY then return end
 
 
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
    if occupant == nil then return end
    return Players:GetPlayerFromCharacter(occupant.Parent)
end
 
 
function Boat:TrySeatPlayer(player: Player)
    if self.Instance:FindFirstChild("DriverSeat") == nil then return end
    if self.SeatDisabled then return end
    if self:GetOccupant() ~= nil then return end
    if not self:CanDrive(player) then return end
    self.Instance.DriverSeat:SetNetworkOwner(player)
    self.Instance.DriverSeat:Sit(player.Character.Humanoid)
    self.Instance:SetAttribute("Owner", player.Name)
end
 
function Boat:UnseatDriver()
    if self.Instance:FindFirstChild("DriverSeat") == nil then return end
    local seatWeld = self.Instance.DriverSeat:FindFirstChild("SeatWeld")
    if seatWeld == nil then return end
    seatWeld:Destroy()
end
 
function Boat:CanDrive(driver: Player)
    if driver == nil then return false end
    local role = Roles.GetPlayerRole(driver)
    if role == nil then return false end
    return true
end
 
task.wait(3)
Boat.StoreAll()
task.wait()
Boat.RespawnAll()
 
Schedules.Values.Day.Changed:Connect(function()
    task.wait(3)
    Boat.RespawnAll()
end)
 
return Boat
