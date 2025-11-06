local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
 
local Component = require(ReplicatedStorage.Packages.Component)
local Knit = require(ReplicatedStorage.Packages.Knit)
 
local MoneyService
local PermissionService
 
local Schedules = require(ServerScriptService.Modules.Schedules)
local JewlleryAssets = ReplicatedStorage.Assets:WaitForChild("JewelleryStore")
 
local JewelTag = "Jewel"
local JewelGlassTag = "JewelGlass"
local JewelSpawnTag = "JewelSpawn"
local AlarmTag = "Alarm"
 
local JewelleryService  = Knit.CreateService {
    Name = "JewelleryService",
    Client = {
    },
}
 
 
JewelleryService.ROBBERY_DURATION = script.Configs:GetAttribute("RobberyDuration") --// in seconds
JewelleryService.MONEY_PER_JEWEL = script.Configs:GetAttribute("MONEY_PER_JEWEL")
JewelleryService.GLASS_BREAK_DISTANCE = script.Configs:GetAttribute("GlassBreakDistance") --// exploit prevention
JewelleryService.JEWEL_STEAL_DURATION = script.Configs:GetAttribute("JewelStealDuration")
JewelleryService.GLASS_BREAK_DURATION = script.Configs:GetAttribute("GlassBreakDuration")
 
JewelleryService.JewlleryStoreStatus = "Closed"
JewelleryService.AlarmsStatus = "Dormant"
JewelleryService.OpenTimes = {}
 
 
local ALARM_EFFECT_DELAY = 1
 
function JewelleryService:KnitStart()
    MoneyService = Knit.GetService("Money")
    PermissionService = Knit.GetService("Permissions")
 
    local success, err = pcall(function()
        for index, openTime in script.OpenTimesConfig:GetAttributes() do 
            JewelleryService.OpenTimes[index] = (openTime * 60) --// since timings are saved as minutes
        end
    end)
    if not success then warn(`error in creating Jewellery store open times! {err}`) end
    print(JewelleryService.OpenTimes)
 
    task.wait(2)
 
    JewelleryService:SetupJewelGlass()
    JewelleryService:ConfigureStoreLights(true)
    JewelleryService.JewlleryStoreStatus = "Open" 
end
 
function JewelleryService:ConfigureJewlleryStatus(status)
    JewelleryService.JewlleryStoreStatus = status
end
 
function JewelleryService.Client:GetJewlleryStoreStatusClient()
    return JewelleryService.JewlleryStoreStatus
end
 
 
function JewelleryService:AlarmEffects(alarm)
    alarm.Light.AlarmLight.Brightness = 20
    task.wait(ALARM_EFFECT_DELAY)
    alarm.Light.AlarmLight.Brightness = 0
    task.wait(ALARM_EFFECT_DELAY-0.25)
end
 
function JewelleryService:AlarmOn(alarm)
    if alarm == nil then return end
    alarm.HingePart.HingeConstraint.Enabled = true
    alarm.SoundPart.Sound:Play()
 
    task.spawn(function()
        while JewelleryService.JewlleryStoreStatus == "Robbing" do 
            self:AlarmEffects(alarm)
        end
    end)
end
 
function JewelleryService:AlarmOff(alarm)
    if alarm == nil then return end
 
    alarm.HingePart.HingeConstraint.Enabled = false
    alarm.SoundPart.Sound:Stop()
    alarm.Light.AlarmLight.Brightness = 0
end
 
function JewelleryService:ConfigureAlarm(alarmStatus, alarmParent)
    if JewelleryService.AlarmsStatus == "Active" then  return end
    if alarmStatus then JewelleryService.AlarmsStatus = "Active" end
 
    for index, alarm in CollectionService:GetTagged(AlarmTag) do
        if alarm:GetAttribute("AlarmParent") ~= alarmParent then continue end
 
        if alarmStatus then self:AlarmOn(alarm) else self:AlarmOff(alarm) end
    end
end
 
function JewelleryService:CollectJewel(player, jewel)
    if player.Team.Name == "Customs" then return end
    player:SetAttribute("RobbingJewlleryStore", true) 
    jewel:Destroy()
    MoneyService:AddMoney(player, self.MONEY_PER_JEWEL)
end
 
function JewelleryService:AnchorModel(model)
    for index, child : Part in model:GetChildren() do 
        if not child:IsA("BasePart") then continue end 
        child.Anchored = true
    end
end
 
function JewelleryService:EndRobbery()
    JewelleryService.JewlleryStoreStatus = "Closed"
    JewelleryService.AlarmsStatus = "Dormant"
 
    self:ClearActiveJewelGlass()
    self:ConfigureAlarm(false, "JewelleryStore")
    self:ConfigureStoreLights(false) 
end
 
function JewelleryService:BreakGlass(player,glassInstance )
    if player.Character == nil then return end
    if glassInstance == nil then return end
    if glassInstance:FindFirstChild("GlassPart") == nil then return end 
    if JewelleryService.JewlleryStoreStatus == "Closed" then return end
    if player.Team.Name == "Customs" then return end
    if (player.Character.HumanoidRootPart.Position - glassInstance.PrimaryPart.Position).Magnitude > self.GLASS_BREAK_DISTANCE then warn("exploiting glass break") return end
 
 
    player:SetAttribute("RobbingJewlleryStore", true) 
    self:ConfigureJewlleryStatus("Robbing")
 
    glassInstance.PrimaryPart:Destroy()
    self:ConfigureAlarm(true, "JewelleryStore")
 
    task.delay(self.ROBBERY_DURATION, function()
        self:EndRobbery()
    end)
 
    for index, child in glassInstance.Jewels:GetChildren() do 
        local newPrompt = self:CreatePrompt(child, "Steal", "", false)
 
        newPrompt.Triggered:Connect(function()
            self:CollectJewel(player, child)
        end)
    end
end
 
function JewelleryService:ClearActiveJewelGlass()
    for index, jewelGlass in CollectionService:GetTagged(JewelGlassTag) do
        if jewelGlass:GetAttribute("ActiveJewel") == nil then  continue end
        jewelGlass:Destroy()
    end 
end
 
function JewelleryService:CreatePrompt(instance, actionText, objectText, isGlass, holdDuration, activationDistance)
    if holdDuration == nil then holdDuration = 3 end 
 
    local Prompt = Instance.new("ProximityPrompt")
    Prompt.MaxActivationDistance = activationDistance or 10
    Prompt.ActionText = actionText
    Prompt.ObjectText = objectText
    Prompt.HoldDuration = (isGlass and self.GLASS_BREAK_DURATION or self.JEWEL_STEAL_DURATION) or holdDuration
    Prompt.RequiresLineOfSight = false
    Prompt.Parent = instance
 
    return Prompt
end
 
 
function JewelleryService:CreateJewelGlass(jewelSpawn)
    if jewelSpawn == nil then return end
    local glassCf = CFrame.new(jewelSpawn.Position) * CFrame.Angles(0,0,0)
 
    local NewGlass = JewlleryAssets.MainGlass:Clone()
    NewGlass:PivotTo(glassCf)
    NewGlass:SetAttribute("ActiveJewel", true)
    NewGlass.Parent = workspace
 
    local Prompt = self:CreatePrompt(NewGlass.PrimaryPart, "Break Glass", "", true)
    Prompt.Triggered:Connect(function(player)
        NewGlass.Break:Play()
        self:BreakGlass(player, NewGlass)
    end)
end
 
 
function JewelleryService:SetupJewelGlass()
    self:ClearActiveJewelGlass()
 
    for index, jewelSpawn in CollectionService:GetTagged(JewelSpawnTag) do
        self:CreateJewelGlass(jewelSpawn)
    end
end
 
function JewelleryService:GetTiming(passedTiming)
    for index, timing in JewelleryService.OpenTimes do  
        if tonumber(timing) ~= tonumber(passedTiming) then continue end
        return true
    end
end
 
function JewelleryService:ConfigureStoreLights(enabled)
    for index, light in workspace["Jewellery ShopMain"].Shop.Light:GetDescendants() do 
        if light:IsA("PointLight") then light.Enabled = enabled end
    end
end
 
Schedules.Values.DayProgress.Changed:Connect(function()
    local secondsIntoDay = Schedules.Properties.DayProgress:Get() * Schedules.Variables.DayLength
    local secondsRemaining = Schedules.Variables.DayLength - secondsIntoDay
 
    if JewelleryService:GetTiming(math.floor(secondsIntoDay)) then
        if JewelleryService.JewlleryStoreStatus == "Open" then return end
        if JewelleryService.JewlleryStoreStatus == "Robbing" then return end
 
        JewelleryService:SetupJewelGlass()
        JewelleryService:ConfigureStoreLights(true)
        JewelleryService.JewlleryStoreStatus = "Open" 
    end
end)
 
JewelleryService:ConfigureStoreLights(false) --// initially
 
return JewelleryService
