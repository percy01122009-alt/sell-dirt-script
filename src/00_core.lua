--[[
    Sell Dirt — automation suite
    language: Luau | target: Roblox client, Delta Executor (Android)
    file: 00_core.lua

    Services, executor capability probe, config/state, shared helpers.
    Everything else hangs off the global SD table.
]]

local SD = {}
getgenv().SD = SD

SD.version   = "2.1.0"
SD.game_name = "Sell Dirt"

local function svc(name)
    local ok, s = pcall(game.GetService, game, name)
    if ok then return s end
    return nil
end

SD.Players           = svc("Players")
SD.RunService        = svc("RunService")
SD.TweenService      = svc("TweenService")
SD.UserInputService  = svc("UserInputService")
SD.ReplicatedStorage = svc("ReplicatedStorage")
SD.TeleportService   = svc("TeleportService")
SD.HttpService       = svc("HttpService")
SD.Lighting          = svc("Lighting")
SD.StarterGui        = svc("StarterGui")
SD.CollectionService = svc("CollectionService")
SD.VirtualUser       = svc("VirtualUser")
SD.Workspace         = workspace

SD.plr = SD.Players and SD.Players.LocalPlayer or nil
SD.t0  = os.clock()

-- executor surface ----------------------------------------------------------

SD.caps = {
    writefile      = type(writefile) == "function",
    readfile       = type(readfile) == "function",
    isfile         = type(isfile) == "function",
    makefolder     = type(makefolder) == "function",
    fireprompt     = type(fireproximityprompt) == "function",
    fireclick      = type(fireclickdetector) == "function",
    getconnections = type(getconnections) == "function",
    hookfunction   = type(hookfunction) == "function",
    getrawmeta     = type(getrawmetatable) == "function",
    sethidden      = type(sethiddenproperty) == "function",
    queue_teleport = type(queue_on_teleport) == "function",
    httpget        = type(game.HttpGet) == "function",
}

-- logging -------------------------------------------------------------------

local PREFIX = "[SD] "

function SD.log(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(i, ...)))
    end
    print(PREFIX .. table.concat(parts, " "))
end

function SD.warn(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(i, ...)))
    end
    warn(PREFIX .. table.concat(parts, " "))
end

-- notifications: queued until the GUI exists, then flushed -------------------

SD._notify_queue = {}

function SD.notify(text, kind)
    local gui = SD.gui
    if gui and gui.ready then
        gui.notify(text, kind)
    else
        table.insert(SD._notify_queue, {text = text, kind = kind})
    end
end

-- small utilities -----------------------------------------------------------

function SD.safe(fn, ...)
    local ok, res = pcall(fn, ...)
    if ok then return res end
    return nil, res
end

function SD.round(n, dp)
    local m = 10 ^ (dp or 0)
    return math.floor(n * m + 0.5) / m
end

function SD.fmt(n)
    n = tonumber(n) or 0
    local a = math.abs(n)
    if a >= 1e12 then return string.format("%.2ft", n / 1e12) end
    if a >= 1e9  then return string.format("%.2fb", n / 1e9)  end
    if a >= 1e6  then return string.format("%.2fm", n / 1e6)  end
    if a >= 1e4  then return string.format("%.1fk", n / 1e3)  end
    return tostring(math.floor(n))
end

function SD.clock_str(sec)
    sec = math.max(0, math.floor(sec or 0))
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    if h > 0 then return string.format("%dh %02dm", h, m) end
    if m > 0 then return string.format("%dm %02ds", m, s) end
    return string.format("%ds", s)
end

function SD.wait_for(pred, timeout)
    local deadline = os.clock() + (timeout or 5)
    while os.clock() < deadline do
        local v = pred()
        if v then return v end
        task.wait(0.1)
    end
    return nil
end

-- character access ----------------------------------------------------------

function SD.get_char()
    local plr = SD.plr
    if not plr then return nil end
    return plr.Character
end

function SD.get_hrp()
    local ch = SD.get_char()
    if not ch then return nil end
    return ch:FindFirstChild("HumanoidRootPart")
end

function SD.get_hum()
    local ch = SD.get_char()
    if not ch then return nil end
    return ch:FindFirstChildOfClass("Humanoid")
end

function SD.alive()
    local hum = SD.get_hum()
    return hum ~= nil and hum.Health > 0
end

-- movement ------------------------------------------------------------------

function SD.set_walkspeed(v)
    local hum = SD.get_hum()
    if hum then hum.WalkSpeed = v end
end

function SD.set_jumppower(v)
    local hum = SD.get_hum()
    if hum then
        hum.UseJumpPower = true
        hum.JumpPower = v
    end
end

function SD.tp(target)
    local hrp = SD.get_hrp()
    if not hrp then return false end

    local cf
    if typeof(target) == "CFrame" then
        cf = target
    elseif typeof(target) == "Vector3" then
        cf = CFrame.new(target)
    elseif typeof(target) == "Instance" then
        if target:IsA("BasePart") then
            cf = target.CFrame
        elseif target:IsA("Model") and target.PrimaryPart then
            cf = target.PrimaryPart.CFrame
        else
            local p = target:FindFirstChildWhichIsA("BasePart", true)
            if not p then return false end
            cf = p.CFrame
        end
    else
        return false
    end

    local ok = pcall(function() hrp.CFrame = cf end)
    if not ok then
        local ch = SD.get_char()
        if ch then pcall(function() ch:PivotTo(cf) end) end
    end
    pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end)
    return true
end

-- stats ---------------------------------------------------------------------

local STAT_CONTAINERS = { "leaderstats", "Stats", "Data", "Values", "PlayerStats", "save" }

function SD.leaderstats()
    local out = {}
    local plr = SD.plr
    if not plr then return out end
    for _, cname in ipairs(STAT_CONTAINERS) do
        local c = plr:FindFirstChild(cname)
        if c then
            for _, v in ipairs(c:GetChildren()) do
                if v:IsA("ValueBase") then
                    out[v.Name] = v.Value
                end
            end
        end
    end
    return out
end

function SD.all_values()
    local out = {}
    local plr = SD.plr
    if not plr then return out end
    for _, v in ipairs(plr:GetDescendants()) do
        if v:IsA("ValueBase") then
            out[v:GetFullName()] = v.Value
        end
    end
    return out
end

function SD.cash()
    local ls = SD.leaderstats()
    local best, bestv = nil, -math.huge
    for name, v in pairs(ls) do
        if type(v) == "number" and v > bestv then
            local ln = string.lower(name)
            if string.find(ln, "cash", 1, true)
                or string.find(ln, "money", 1, true)
                or string.find(ln, "coin", 1, true)
                or string.find(ln, "dollar", 1, true) then
                best, bestv = name, v
            end
        end
    end
    if best then return bestv, best end
    return nil, nil
end

-- task scheduler ------------------------------------------------------------

SD.tasks = {}

function SD.add_task(name, interval, fn)
    SD.tasks[name] = { interval = interval, fn = fn, last = 0 }
end

function SD.run_tasks()
    local now = os.clock()
    for name, t in pairs(SD.tasks) do
        if now - t.last >= t.interval then
            t.last = now
            local ok, err = pcall(t.fn)
            if not ok then
                SD.warn("task '" .. name .. "' failed: " .. tostring(err))
            end
        end
    end
end

-- config --------------------------------------------------------------------

SD.CONFIG_FILE = "SellDirt/config.json"

SD.config = {
    -- selling / grinding
    auto_sell        = false,
    auto_sell_delay  = 1.5,
    auto_dig         = false,
    auto_dig_delay   = 0.35,
    auto_collect     = false,
    auto_upgrade     = false,
    auto_rebirth     = false,

    -- movement
    tp_crown         = false,
    tp_crown_delay   = 2.0,
    walkspeed        = 16,
    walkspeed_lock   = false,
    jumppower        = 50,
    jumppower_lock   = false,

    -- utility (all off by default)
	    anti_afk         = false,
	    auto_rejoin      = false,
	    fullbright       = false,
	    fps_boost        = false,
	    esp_crown        = false,
	    esp_sell         = false,
	    esp_dirt         = false,

    -- user overrides (filled by the GUI, used by the heuristics)
    crown_name       = "",
    sell_name        = "",
    dig_tool_name    = "",
    sell_remote      = "",
}

SD.state = {
		session_start  = os.time(),
		session_earned = 0,
		last_cash      = nil,
		paused         = false,
		anchor         = nil,   -- CFrame to return to after a sell trip
		rejoin_guard   = false,
		queued_tp      = false,
	}

function SD.save_config()
    if not (SD.caps.writefile and SD.caps.makefolder) then
        SD.notify("executor cannot write files", "warn")
        return false
    end
    pcall(function() makefolder("SellDirt") end)
    local ok, json = pcall(function() return SD.HttpService:JSONEncode(SD.config) end)
    if not ok then return false end
    local wrote = pcall(function() writefile(SD.CONFIG_FILE, json) end)
    if wrote then SD.notify("config saved", "ok") end
    return wrote
end

function SD.load_config()
	    if not (SD.caps.readfile and SD.caps.isfile) then return false end
	    if not isfile(SD.CONFIG_FILE) then return false end
	    local ok, raw = pcall(readfile, SD.CONFIG_FILE)
	    if not ok or not raw then return false end
	    local decoded_ok, data = pcall(function() return SD.HttpService:JSONDecode(raw) end)
	    if not decoded_ok or type(data) ~= "table" then return false end
	    for k, v in pairs(data) do
	        if SD.config[k] ~= nil then SD.config[k] = v end
	    end
	    -- Always start with features OFF (user requested: nothing enabled by default)
	    local force_off = {
	        "auto_sell","auto_dig","auto_collect","auto_upgrade","auto_rebirth",
	        "tp_crown","walkspeed_lock","jumppower_lock","fullbright","fps_boost",
	        "esp_crown","esp_sell","esp_dirt","anti_afk","auto_rejoin",
	        "auto_sell_teleport","queue_on_teleport",
	    }
	    for _, k in ipairs(force_off) do SD.config[k] = false end
	    return true
	end

SD.log("core loaded v" .. SD.version)
