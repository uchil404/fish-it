-- Rayfield UI - try multiple loader sources and several http methods for executor compatibility
local function fetchUrl(url)
    -- try game:HttpGet
    local ok, res = pcall(function() return game:HttpGet(url) end)
    if ok and res and res ~= "" then return res end

    -- try common exploit request wrappers
    local wrappers = {
        function(u) if syn and syn.request then return syn.request({Url = u, Method = "GET"}).Body end end,
        function(u) if http and http.request then return http.request({Url = u, Method = "GET"}).Body end end,
        function(u) if request then return request({Url = u, Method = "GET"}).Body end end,
        function(u) if http_request then return http_request({Url = u, Method = "GET"}).Body end end,
    }
    for _,fn in ipairs(wrappers) do
        local ok2, res2 = pcall(fn, url)
        if ok2 and res2 and res2 ~= "" then return res2 end
    end
    return nil
end

local Rayfield
local loaderSources = {
    "https://raw.githubusercontent.com/uchil404/fish-it/refs/heads/main/fish_it_premiumV1_script.lua",
    "https://raw.githubusercontent.com/shlexware/Rayfield/main/source"
}
for _, src in ipairs(loaderSources) do
    local body = fetchUrl(src)
    if body then
        local ok, ret = pcall(function() return loadstring(body)() end)
        if ok and ret then
            Rayfield = ret
            break
        end
    end
end
if not Rayfield then
    warn("Failed to load Rayfield UI from known sources. GUI features may not work.")
    Rayfield = {}
    Rayfield.CreateWindow = function() error("Rayfield not loaded") end
end

-- Prevent double-run when re-executing in the same session
if getgenv().FishItLoaded then
    warn("Fish It script already running in this environment. Aborting duplicate load.")
    return
end
getgenv().FishItLoaded = true

-- Wait for LocalPlayer (helps when executing immediately after attach)
local Players = game:GetService("Players")
if not Players.LocalPlayer then
    repeat task.wait() until Players.LocalPlayer
end

-- Services
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-- Constants
local FISHING_DELAY = 1.5  -- Delay between fishing attempts
local SELL_CHECK_DELAY = 2 -- Delay between sell checks
local AUTO_CATCH_DELAY = 0.3 -- Delay for auto catch

-- Create Window
local Window = Rayfield:CreateWindow({
   Name = "Fish It Ultimate",
   LoadingTitle = "Lynx Fish It",
   LoadingSubtitle = "Full Features",
   ConfigurationSaving = {
      Enabled = true,
      FileName = "Config"
   },
   KeySystem = false
})

-- =========================
-- =========================
local SettingsTab = Window:CreateTab("Settings",4483362458)
SettingsTab:CreateToggle({Name="Anti Lag / Low Texture",CurrentValue=false,Callback=function(val)
    local PERFECT_CAST_INTERVAL = 3.5  -- Waktu antara perfect cast (sesuaikan jika perlu)
    local PERFECT_CAST_WINDOW = 0.1    -- Window waktu untuk perfect cast
    getgenv().AntiLag=val
        for _,v in pairs(game:GetDescendants()) do
            if v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Explosion") then v:Destroy()
            elseif v:IsA("BasePart") then v.Material=Enum.Material.Plastic;v.Reflectance=0 end
        end
    end
end})
SettingsTab:CreateToggle({Name="Anti AFK",CurrentValue=false,Callback=function(val)
    getgenv().AntiAFK=val
    if val then
        -- getconnections may not be available in all executors; guard with pcall
        pcall(function()
            for i,v in pairs(getconnections(LocalPlayer.Idled)) do v:Disable() end
        end)
    end
    -- Perfect Cast System
    local lastCastTime = 0

    local function isPerfectCastTime()
        local currentTime = tick()
        local timeSinceLastCast = currentTime - lastCastTime
    
        if timeSinceLastCast >= PERFECT_CAST_INTERVAL then
            lastCastTime = currentTime
            return true
        end
        return false
    end

    local function doPerfectCast()
        if not findRod() then return end
    
        task.wait(randomDelay(0.1, 0.05))  -- Sedikit delay random untuk menghindari deteksi
    
        pcall(function()
            -- Simulasi perfect cast timing
            ReplicatedStorage.Remotes.CastRod:FireServer()
            task.wait(PERFECT_CAST_WINDOW)
            ReplicatedStorage.Remotes.CatchFish:FireServer()
        end)
    end
end})
SettingsTab:CreateButton({Name="Rejoin Server",Callback=function()
    local ts=game:GetService("TeleportService")
    ts:Teleport(game.PlaceId,LocalPlayer)
end})
SettingsTab:CreateButton({Name="Buy Rod",Callback=function() ReplicatedStorage.Remotes.BuyRod:FireServer() end})
SettingsTab:CreateButton({Name="Buy Bait",Callback=function() ReplicatedStorage.Remotes.BuyBait:FireServer() end})
SettingsTab:CreateButton({Name="Spawn Boat",Callback=function() ReplicatedStorage.Remotes.SpawnBoat:FireServer() end})

-- =========================
-- FISHING TAB
-- =========================
local FishingTab = Window:CreateTab("Fishing",4483362458)
-- Utility Functions
local function findRod()
    local rod = nil
    if LocalPlayer:FindFirstChild("Backpack") then 
        rod = LocalPlayer.Backpack:FindFirstChild("Fishing Rod") 
    end
    if (not rod) and LocalPlayer.Character then 
        rod = LocalPlayer.Character:FindFirstChild("Fishing Rod") 
    end
    return rod
end

local function randomDelay(base, variance)
    return base + (math.random() * variance)
end

local function autoCast()
    local rod = findRod()
    if rod then
        local success, err = pcall(function()
            ReplicatedStorage.Remotes.CastRod:FireServer()
        end)
        if not success then
            warn("Failed to cast rod:", err)
        end
    end
end

local function autoCatch()
    local rod = findRod()
    if rod then
        local success, err = pcall(function()
            ReplicatedStorage.Remotes.CatchFish:FireServer()
        end)
        if not success then
            warn("Failed to catch fish:", err)
        end
    end
end

-- Clean up old connections when script re-runs
if getgenv().CleanupConnections then
    for _, connection in pairs(getgenv().CleanupConnections) do
        connection:Disconnect()
    end
end
getgenv().CleanupConnections = {}

FishingTab:CreateToggle({
    Name = "Auto Fish & Catch",
    CurrentValue = false,
    Callback = function(val)
        getgenv().AutoFish = val
        if val then
            local connection = RunService.Heartbeat:Connect(function()
                if not getgenv().AutoFish then return end
                task.wait(randomDelay(FISHING_DELAY, 0.5))
                autoCast()
                task.wait(randomDelay(AUTO_CATCH_DELAY, 0.2))
                autoCatch()
            end)
            table.insert(getgenv().CleanupConnections, connection)
        end
    end
})

-- Auto Perfect Cast UI (moved to proper place)
FishingTab:CreateToggle({
    Name = "Auto Perfect Cast",
    CurrentValue = false,
    Callback = function(val)
        getgenv().AutoPerfectCast = val
        if val then
            local connection = RunService.Heartbeat:Connect(function()
                if not getgenv().AutoPerfectCast then return end
                if isPerfectCastTime() then
                    doPerfectCast()
                end
            end)
            table.insert(getgenv().CleanupConnections, connection)
        end
    end
})

-- Import Locations UI
local importBox
-- Rayfield sometimes has CreateInput/CreateTextBox; attempt to create an input, else fallback to button-based import using getgenv().ImportedLocations
local createdInput = pcall(function()
    importBox = TeleportTab:CreateInput({Name = "Import Locations (Name,x,y,z per line)", Placeholder = "Paste locations here...", Value = ""})
end)

if not createdInput then
    -- fallback: create a small button that reads from getgenv().ImportedLocations string
    TeleportTab:CreateLabel({Name = "Import Locations: paste to getgenv().ImportedLocations as multiline string"})
end

TeleportTab:CreateButton({Name = "Apply Import", Callback = function()
    local raw = nil
    if importBox and importBox.Value then raw = importBox.Value end
    if (not raw) and getgenv().ImportedLocations then raw = getgenv().ImportedLocations end
    if not raw or raw == "" then return end

    for line in raw:gmatch("[^
]+") do
        local name,x,y,z = line:match("^%s*(.-)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*$")
        if name and x and y and z then
            local vx = tonumber(x)
            local vy = tonumber(y)
            local vz = tonumber(z)
            if vx and vy and vz then
                Locations[name] = Vector3.new(vx,vy,vz)
                -- create button for new location
                TeleportTab:CreateButton({Name = "Teleport "..name, Callback = function() if LocalPlayer.Character then pcall(function() LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(Vector3.new(vx,vy,vz)) end) end end})
            end
        end
    end
end})
FishingTab:CreateToggle({
    Name = "Auto Perfect",
    CurrentValue = false,
    Callback = function(val)
        getgenv().AutoPerfect = val
        if val then
            local connection = RunService.Heartbeat:Connect(function()
                if not getgenv().AutoPerfect then return end
                task.wait(randomDelay(AUTO_CATCH_DELAY, 0.2))
                pcall(function()
                    ReplicatedStorage.Remotes.SellPerfect:FireServer()
                end)
            end)
            table.insert(getgenv().CleanupConnections, connection)
        end
    end
})

FishingTab:CreateToggle({
    Name = "Auto Amazing",
    CurrentValue = false,
    Callback = function(val)
        getgenv().AutoAmazing = val
        if val then
            local connection = RunService.Heartbeat:Connect(function()
                if not getgenv().AutoAmazing then return end
                task.wait(randomDelay(AUTO_CATCH_DELAY, 0.2))
                pcall(function()
                    ReplicatedStorage.Remotes.SellAmazing:FireServer()
                end)
            end)
            table.insert(getgenv().CleanupConnections, connection)
        end
    end
})

-- =========================
-- AUTO SELL TAB
-- =========================
local SellTab = Window:CreateTab("Auto Sell",4483362458)
SellTab:CreateToggle({Name="Auto Sell All",CurrentValue=false,Callback=function(val)
    getgenv().AutoSell=val
    task.spawn(function() while getgenv().AutoSell do task.wait(2); if #LocalPlayer.Backpack:GetChildren()>=5 then ReplicatedStorage.Remotes.SellAllFish:FireServer() end end end)
end})
SellTab:CreateSlider({Name="Sell Threshold",Range={0,100},Increment=1,Suffix="%",CurrentValue=50,Callback=function(val) getgenv().SellThreshold=val end})

-- =========================
-- PLAYER TAB
-- =========================
local PlayerTab = Window:CreateTab("Player",4483362458)
PlayerTab:CreateToggle({Name="Float On Water",CurrentValue=false,Callback=function(val) getgenv().FloatOnWater=val
    task.spawn(function() while getgenv().FloatOnWater do task.wait(0.5)
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            local hrp = LocalPlayer.Character.HumanoidRootPart
            -- set Y to 10 while preserving X,Z (rotation may be reset)
            hrp.CFrame = CFrame.new(hrp.Position.X, 10, hrp.Position.Z)
        end
    end end)
end})
PlayerTab:CreateToggle({Name="Infinite Jump",CurrentValue=false,Callback=function(val) getgenv().InfiniteJump=val end})
PlayerTab:CreateToggle({Name="Unlimited Jump",CurrentValue=false,Callback=function(val) getgenv().UnlimitedJump=val end})
UserInputService.JumpRequest:Connect(function()
    if getgenv().InfiniteJump or getgenv().UnlimitedJump then
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end)
PlayerTab:CreateSlider({Name="Walk Speed",Range={16,200},Increment=1,CurrentValue=16,Callback=function(val) if LocalPlayer.Character then LocalPlayer.Character.Humanoid.WalkSpeed=val end end})
PlayerTab:CreateToggle({Name="Trade No Delay",CurrentValue=false,Callback=function(val)
    getgenv().TradeNoDelay=val
    if val then
        -- Attempt to remove client-side TradeDelay object; server-side removal may not be possible from client.
        pcall(function()
            if ReplicatedStorage and ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("TradeDelay") then
                ReplicatedStorage.Remotes.TradeDelay:Destroy()
            end
        end)
    end
end})

-- Tele Select Player
local playersList={}
local teleSelected=nil
local function refreshPlayers()
    playersList={}
    for _,p in pairs(Players:GetPlayers()) do if p~=LocalPlayer then table.insert(playersList,p) end end
end
PlayerTab:CreateButton({Name="Refresh Player List",Callback=function() refreshPlayers() end})
PlayerTab:CreateDropdown({Name="Select Player To Teleport",Options={},CurrentOption="",Callback=function(val) for _,p in pairs(playersList) do if p.Name==val then teleSelected=p break end end end})
PlayerTab:CreateButton({Name="Teleport To Selected Player",Callback=function() if teleSelected and teleSelected.Character and LocalPlayer.Character then LocalPlayer.Character.HumanoidRootPart.CFrame=teleSelected.Character.HumanoidRootPart.CFrame end end})

-- =========================
-- BUY WEATHER TAB
-- =========================
local WeatherTab = Window:CreateTab("Weather",4483362458)
local weatherTypes={"Cloud","Storm","Wind","Radiant","Snow"}
for _,w in pairs(weatherTypes) do WeatherTab:CreateButton({Name="Spawn "..w,Callback=function() ReplicatedStorage.Remotes.SpawnWeather:FireServer(w) end}) end
WeatherTab:CreateToggle({Name="Auto Buy Weather",CurrentValue=false,Callback=function(val)
    getgenv().AutoWeather=val
    task.spawn(function() while getgenv().AutoWeather do task.wait(1.5); for _,w in pairs(weatherTypes) do ReplicatedStorage.Remotes.BuyWeather:FireServer(w) end end end)
end})

-- =========================
-- SHARK HUNT TAB
-- =========================
local SharkTab = Window:CreateTab("Shark Hunt",4483362458)
SharkTab:CreateButton({Name="Spawn Shark Hunt",Callback=function() ReplicatedStorage.Remotes.SpawnSharkHunt:FireServer() end})
SharkTab:CreateToggle({Name="Auto Shark Hunt",CurrentValue=false,Callback=function(val)
    getgenv().AutoShark=val
    task.spawn(function() while getgenv().AutoShark do task.wait(1); ReplicatedStorage.Remotes.StartSharkHunt:FireServer() end end)
end})

-- =========================
-- TELEPORT TAB
-- =========================
local TeleportTab = Window:CreateTab("Teleport",4483362458)
local Locations={
["Coral Reefs"]=Vector3.new(-2945,66,2248),["Kohana"]=Vector3.new(-645,16,606),
["Weather Machine"]=Vector3.new(-1535,2,1917),["Lost Isle [Sisypuhus]"]=Vector3.new(-3703,-136,-1019),
["Winter Fest"]=Vector3.new(1616,4,3280),["Esoteric Depths"]=Vector3.new(3214,-1303,1411),
["Tropical Grove"]=Vector3.new(-2047,6,3662),["Stingray Shores"]=Vector3.new(2,4,2839),
["Lost Isle [Treasure Room]"]=Vector3.new(-3594,-285,-1635),["Lost Isle [Lost Shore]"]=Vector3.new(-3672,70,-912),
["Kohana Volcano"]=Vector3.new(-512,24,191),["Crater Island"]=Vector3.new(1019,20,5071)
}
for name,pos in pairs(Locations) do TeleportTab:CreateButton({Name="Teleport "..name,Callback=function() if LocalPlayer.Character then LocalPlayer.Character.HumanoidRootPart.CFrame=CFrame.new(pos) end end}) end

-- =========================
-- EVENT TAB
-- =========================
local EventTab = Window:CreateTab("Event",4483362458)
EventTab:CreateButton({Name="Auto Farm Event",Callback=function() task.spawn(function() while true do task.wait(2); ReplicatedStorage.Remotes.FarmEvent:FireServer() end end) end})
EventTab:CreateButton({Name="Refresh Event List",Callback=function() ReplicatedStorage.Remotes.RefreshEvents:FireServer() end})
EventTab:CreateButton({Name="Teleport To Event",Callback=function() ReplicatedStorage.Remotes.TeleportToEvent:FireServer() end})
