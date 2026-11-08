--[[
    test/smoke.lua
    Headless harness: a small fake DataModel good enough to load the whole
    script and exercise the GUI construction, the scheduler, and the feature
    entry points. Catches nil indexing and logic errors that would otherwise
    only show up on the phone.

    run: lua5.4 test/smoke.lua
]]

-- fake types ---------------------------------------------------------------

local function vec2(x, y)
    local v = { X = x or 0, Y = y or 0 }
    return setmetatable(v, {
        __sdtype = "Vector2",
        __sub = function(a, b) return vec2(a.X - b.X, a.Y - b.Y) end,
        __add = function(a, b) return vec2(a.X + b.X, a.Y + b.Y) end,
        __div = function(a, n) return vec2(a.X / n, a.Y / n) end,
    })
end

local function vec3(x, y, z)
    local v = { X = x or 0, Y = y or 0, Z = z or 0, Magnitude = 0 }
    v.Magnitude = math.sqrt(v.X ^ 2 + v.Y ^ 2 + v.Z ^ 2)
    return setmetatable(v, {
        __sdtype = "Vector3",
        __sub = function(a, b) return vec3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end,
        __add = function(a, b) return vec3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end,
    })
end

local function cframe(x, y, z)
    local c = { X = x or 0, Y = y or 0, Z = z or 0 }
    return setmetatable(c, {
        __sdtype = "CFrame",
        __mul = function(a, b)
            if getmetatable(b) and getmetatable(b).__sdtype == "CFrame" then
                return cframe(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
            end
            return cframe(a.X, a.Y, a.Z)
        end,
    })
end

local CF = {
    new = function(a, b, c)
        if type(a) == "table" then return cframe(a.X or 0, a.Y or 0, a.Z or 0) end
        return cframe(a, b, c)
    end,
}

local UDim = { new = function(s, o) return { Scale = s or 0, Offset = o or 0 } end }

local UDim2 = {
    new = function(xs, xo, ys, yo)
        return { X = { Scale = xs or 0, Offset = xo or 0 }, Y = { Scale = ys or 0, Offset = yo or 0 } }
    end,
    fromOffset = function(x, y)
        return { X = { Scale = 0, Offset = x or 0 }, Y = { Scale = 0, Offset = y or 0 } }
    end,
}

local Vector2 = { new = vec2 }
local Vector3 = { new = vec3, zero = vec3(0, 0, 0) }
local Color3 = { fromRGB = function(r, g, b) return { R = r, G = g, B = b } end }

local function enum_tree()
    return setmetatable({}, {
        __index = function(t, k)
            local v = enum_tree()
            rawset(t, k, v)
            return v
        end,
    })
end
local Enum = enum_tree()

-- fake instances -----------------------------------------------------------

local Instance_mt = {}

local METHODS = {}

local SIGNALS = {
    MouseButton1Click = true, InputBegan = true, InputChanged = true,
    InputEnded = true, FocusLost = true, FocusGained = true, ChildAdded = true,
    ChildRemoved = true, AncestryChanged = true, Idled = true,
    CharacterAdded = true, CharacterRemoving = true, Heartbeat = true,
    Touched = true, Activated = true,
}

local function signal()
    local s = { _fns = {} }
    function s:Connect(fn)
        table.insert(self._fns, fn)
        return { Disconnect = function() end }
    end
    function s:Wait() return nil end
    function s:Fire(...)
        for _, fn in ipairs(self._fns) do pcall(fn, ...) end
    end
    return s
end

local HIERARCHY = {
    BasePart = { "PVInstance", "Instance" },
    Part = { "BasePart", "PVInstance", "Instance" },
    Model = { "PVInstance", "Instance" },
    Tool = { "BackpackItem", "Instance" },
}

Instance_mt.__index = function(t, k)
    local props = rawget(t, "_p")
    local methods = METHODS[k]
    if methods then return methods end
    if SIGNALS[k] then
        local s = signal()
        props[k] = s
        return s
    end
    return props[k]
end

Instance_mt.__newindex = function(t, k, v)
    local props = rawget(t, "_p")
    if k == "Parent" then
        local old = props.Parent
        if old and old._c then
            for i, c in ipairs(old._c) do
                if c == t then table.remove(old._c, i) break end
            end
        end
        props.Parent = v
        if v and v._c then table.insert(v._c, t) end
        return
    end
    props[k] = v
end

local function make(class, name)
    local inst = setmetatable({
        _p = { ClassName = class, Name = name or class },
        _c = {},
    }, Instance_mt)
    inst._p.ClassName = class
    return inst
end

METHODS.GetChildren = function(self)
    local out = {}
    for i, c in ipairs(self._c) do out[i] = c end
    return out
end

METHODS.GetDescendants = function(self)
    local out = {}
    local function walk(node)
        for _, c in ipairs(node._c) do
            out[#out + 1] = c
            walk(c)
        end
    end
    walk(self)
    return out
end

METHODS.FindFirstChild = function(self, name, recursive)
    for _, c in ipairs(self._c) do
        if c._p.Name == name then return c end
    end
    if recursive then
        for _, c in ipairs(self._c) do
            local hit = METHODS.FindFirstChild(c, name, true)
            if hit then return hit end
        end
    end
    return nil
end

METHODS.FindFirstChildOfClass = function(self, class)
    for _, c in ipairs(self._c) do
        if c._p.ClassName == class then return c end
    end
    return nil
end

METHODS.FindFirstChildWhichIsA = function(self, class, recursive)
    for _, c in ipairs(self._c) do
        if c:IsA(class) then return c end
    end
    if recursive then
        for _, c in ipairs(self._c) do
            local hit = METHODS.FindFirstChildWhichIsA(c, class, true)
            if hit then return hit end
        end
    end
    return nil
end

METHODS.IsA = function(self, class)
    local own = self._p.ClassName
    if own == class then return true end
    for _, parent in ipairs(HIERARCHY[own] or {}) do
        if parent == class then return true end
    end
    return false
end

METHODS.Destroy = function(self)
    local p = self._p.Parent
    if p and p._c then
        for i, c in ipairs(p._c) do
            if c == self then table.remove(p._c, i) break end
        end
    end
    self._p.Parent = nil
end

METHODS.WaitForChild = function(self, name) return METHODS.FindFirstChild(self, name) end
METHODS.GetFullName = function(self)
    local parts = { self._p.Name }
    local p = self._p.Parent
    while p do
        table.insert(parts, 1, p._p.Name)
        p = p._p.Parent
    end
    return table.concat(parts, ".")
end
METHODS.IsDescendantOf = function(self, target)
    local p = self._p.Parent
    while p do
        if p == target then return true end
        p = p._p.Parent
    end
    return false
end
METHODS.FireServer = function(self) SD_TEST_FIRED = (SD_TEST_FIRED or 0) + 1 end
METHODS.InvokeServer = function(self) return true end
METHODS.Activate = function(self) return true end
METHODS.EquipTool = function(self) return true end
METHODS.ChangeState = function(self) return true end
METHODS.InputHoldBegin = function(self) return true end
METHODS.InputHoldEnd = function(self) return true end
METHODS.PivotTo = function(self) return true end
METHODS.GetPlayers = function(self) return { self._p.LocalPlayer } end

local Instance = {}
Instance.new = function(class, parent)
    local inst = make(class)
    if parent then inst.Parent = parent end
    return inst
end

-- globals ------------------------------------------------------------------

function typeof(v)
    local mt = getmetatable(v)
    if mt and mt.__sdtype then return mt.__sdtype end
    return type(v)
end

math.clamp = function(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

table.find = function(t, v)
    for i, x in ipairs(t) do
        if x == v then return i end
    end
    return nil
end

local env = {}
function getgenv() return env end

local wait_queue = {}
task = {
    wait = function() return 0 end,
    spawn = function(fn, ...) local ok, err = pcall(fn, ...) if not ok then error(err, 0) end end,
    defer = function(fn, ...) local ok, err = pcall(fn, ...) if not ok then error(err, 0) end end,
    delay = function(_, fn, ...) local ok, err = pcall(fn, ...) if not ok then error(err, 0) end end,
}

local fired_prompts, fired_clicks = 0, 0
function fireproximityprompt() fired_prompts = fired_prompts + 1 return true end
function fireclickdetector() fired_clicks = fired_clicks + 1 return true end

local files = {}
function writefile(path, data) files[path] = data return true end
function readfile(path) return files[path] end
function isfile(path) return files[path] ~= nil end
function makefolder() return true end

-- fake game tree -----------------------------------------------------------

local game_obj = make("DataModel", "Game")
game_obj._p.PlaceId = 123456789
game_obj._p.JobId = "job-abc"

local services = {}

local function service(class, name)
    local s = make(class, name or class)
    services[name or class] = s
    s._p.Parent = game_obj
    return s
end

local Players = service("Players", "Players")
local RunService = service("RunService", "RunService")
local TweenService = service("TweenService", "TweenService")
local UserInputService = service("UserInputService", "UserInputService")
local ReplicatedStorage = service("ReplicatedStorage", "ReplicatedStorage")
local TeleportService = service("TeleportService", "TeleportService")
local HttpService = service("HttpService", "HttpService")
local Lighting = service("Lighting", "Lighting")
local StarterGui = service("StarterGui", "StarterGui")
local CoreGui = service("CoreGui", "CoreGui")
local VirtualUser = service("VirtualUser", "VirtualUser")
local CollectionService = service("CollectionService", "CollectionService")

RunService._p.Heartbeat = signal()

HttpService.JSONEncode = function(self, t)
    local out = {}
    for k, v in pairs(t) do
        local val
        if type(v) == "string" then val = '"' .. v .. '"'
        elseif type(v) == "boolean" then val = tostring(v)
        elseif type(v) == "number" then val = tostring(v)
        else val = "null" end
        out[#out + 1] = '"' .. k .. '":' .. val
    end
    return "{" .. table.concat(out, ",") .. "}"
end

HttpService.JSONDecode = function(self, s)
    local t = {}
    for k, v in string.gmatch(s, '"([^"]+)"%s*:%s*"?([^",}]+)"?') do
        t[k] = tonumber(v) or (v == "true") or v
    end
    return t
end

TweenService.Create = function(self, inst, info, goal)
    return { Play = function() end }
end

local workspace = make("Workspace", "Workspace")
workspace._p.Parent = game_obj
local camera = make("Camera", "Camera")
camera._p.ViewportSize = vec2(1280, 720)
camera._p.Parent = workspace
workspace._p.CurrentCamera = camera

local player = make("Player", "Kai")
player._p.Parent = Players
Players._p.LocalPlayer = player

local playerGui = make("PlayerGui", "PlayerGui")
playerGui._p.Parent = player

local character = make("Model", "Character")
character._p.Parent = workspace
local hrp = make("Part", "HumanoidRootPart")
hrp._p.Parent = character
hrp._p.CFrame = cframe(0, 5, 0)
hrp._p.Position = vec3(0, 5, 0)
local humanoid = make("Humanoid", "Humanoid")
humanoid._p.Parent = character
humanoid._p.Health = 100
humanoid._p.MaxHealth = 100
humanoid._p.WalkSpeed = 16
humanoid._p.JumpPower = 50
humanoid._p.UseJumpPower = true
character._p.PrimaryPart = hrp
player._p.Character = character

local leaderstats = make("Folder", "leaderstats")
leaderstats._p.Parent = player
local cash = make("IntValue", "Cash")
cash._p.Parent = leaderstats
cash._p.Value = 500
local dirt = make("IntValue", "Dirt")
dirt._p.Parent = leaderstats
dirt._p.Value = 12

local backpack = make("Backpack", "Backpack")
backpack._p.Parent = player
local shovel = make("Tool", "Shovel")
shovel._p.Parent = backpack

-- world objects
local sellZone = make("Part", "SellZone")
sellZone._p.Parent = workspace
sellZone._p.Position = vec3(40, 5, 0)
sellZone._p.CFrame = cframe(40, 5, 0)
local sellPrompt = make("ProximityPrompt", "SellPrompt")
sellPrompt._p.Parent = sellZone
sellPrompt._p.HoldDuration = 0.5
sellPrompt._p.ObjectText = "Sell"

local crown = make("Part", "Crown")
crown._p.Parent = workspace
crown._p.Position = vec3(-30, 20, 0)
crown._p.CFrame = cframe(-30, 20, 0)

for i = 1, 3 do
    local d = make("Part", "Dirt" .. i)
    d._p.Parent = workspace
    d._p.Position = vec3(i * 5, 1, 0)
    d._p.CFrame = cframe(i * 5, 1, 0)
    local cd = make("ClickDetector", "DigClick")
    cd._p.Parent = d
end

local upgradePad = make("Part", "UpgradePad")
upgradePad._p.Parent = workspace
upgradePad._p.Position = vec3(10, 1, 10)
upgradePad._p.CFrame = cframe(10, 1, 10)
local upPrompt = make("ProximityPrompt", "UpgradePrompt")
upPrompt._p.Parent = upgradePad
upPrompt._p.HoldDuration = 0.2

local sellRemote = make("RemoteEvent", "SellDirt")
sellRemote._p.Parent = ReplicatedStorage
local buyRemote = make("RemoteEvent", "BuyUpgrade")
buyRemote._p.Parent = ReplicatedStorage
local junkRemote = make("RemoteEvent", "RandomThing")
junkRemote._p.Parent = ReplicatedStorage

local game_api = {
    GetService = function(self, name)
        if name == "Workspace" then return workspace end
        local s = services[name]
        if s then return s end
        return service(name, name)
    end,
    HttpGet = function(self, url) return '{"data":[]}' end,
}
game_obj.GetService = game_api.GetService
game_obj.HttpGet = game_api.HttpGet

_G.game = game_obj
_G.workspace = workspace
INSTANCE_NEW = Instance.new
_G.Instance = Instance
_G.UDim2 = UDim2
_G.UDim = UDim
_G.Vector2 = Vector2
_G.Vector3 = Vector3
_G.CFrame = CF
_G.Color3 = Color3
_G.Enum = Enum
_G.UserSettings = function()
    return {
        GetService = function() return { SavedQualitySetting = "high" } end,
    }
end
_G.TweenInfo = { new = function(...) return { args = { ... } } end }
_G.warn = print

-- run ----------------------------------------------------------------------

print("--- loading dist/SellDirt.lua ---")
local ok, err = pcall(dofile, "dist/SellDirt.lua")
if not ok then
    print("LOAD FAILED: " .. tostring(err))
    os.exit(1)
end
print("load ok")

local SD = getgenv().SD
assert(SD, "SD table missing")

print("--- recon ---")
SD.refresh(true)
print(("parts=%d models=%d prompts=%d clicks=%d remotes=%d"):format(
    #SD.cache.parts, #SD.cache.models, #SD.cache.prompts,
    #SD.cache.clicks, #SD.cache.remotes))
assert(#SD.cache.remotes == 3, "remote scan count")
assert(#SD.cache.prompts == 2, "prompt scan count")

print("--- targets ---")
assert(SD.features.sell_target(), "sell target not resolved")
assert(SD.features.crown_target(), "crown target not resolved")
assert(SD.features.dirt_target(), "dirt target not resolved")
assert(SD.features.upgrade_target(), "upgrade target not resolved")
assert(SD.features.dig_tool(), "dig tool not resolved")
print("targets ok")

print("--- scheduler ---")
for i = 1, 30 do SD.run_tasks() end

print("--- features ---")
SD.config.auto_sell = true
SD.config.auto_dig = true
SD.config.auto_collect = true
SD.config.auto_upgrade = true
SD.config.tp_crown = true
SD.config.esp_crown = true
SD.config.esp_sell = true
SD.config.esp_dirt = true
SD.config.walkspeed_lock = true
SD.config.fullbright = true
for i = 1, 60 do SD.run_tasks() end
print("feature loop ok")

print("--- actions ---")
SD.features.sell_once()
SD.features.dig_once()
SD.features.collect_once()
SD.features.goto_crown()
SD.features.goto_sell()
SD.features.goto_dirt()
SD.features.upgrade_once()
SD.features.return_home()
print("actions ok")

print("--- exploits ---")
local args = SD.exploits.parse_args("1000, true, hello")
assert(#args == 3 and args[1] == 1000 and args[2] == true and args[3] == "hello", "arg parse")
assert(SD.exploits.prompt_spoof() > 0, "prompt spoof")
assert(SD.exploits.click_spoof() > 0, "click spoof")
SD.exploits.noclip(true)
SD.exploits.noclip(false)
SD.exploits.god()
assert(#SD.exploits.client_values() > 0, "client values")
local hits = SD.exploits.auto_hunt()
print(("auto_hunt returned %d hits"):format(#hits))
print("exploits ok")

print("--- gui ---")
SD.gui.notify("smoke test", "ok")
SD.gui.select("Move")
SD.gui.select("Exploit")
SD.gui.select("Config")
SD.gui.set_status("test")
print("gui ok")

print("--- config roundtrip ---")
SD.config.auto_sell_delay = 4.5
assert(SD.save_config(), "save")
SD.config.auto_sell_delay = 1
assert(SD.load_config(), "load")
assert(SD.config.auto_sell_delay == 4.5, "roundtrip value")
print("config ok")

print("--- unload ---")
SD.unload()
print("ALL SMOKE TESTS PASSED")
