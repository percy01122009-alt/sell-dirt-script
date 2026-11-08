--[[
    Sell Dirt — automation suite
    language: Luau | target: Roblox client, Delta Executor (Android)
    file: 00_core.lua

    Services, executor capability probe, config/state, shared helpers.
    Everything else hangs off the global SD table.
]]

local SD = {}
getgenv().SD = SD

SD.version   = "1.0.0"
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

    -- utility
    anti_afk         = true,
    auto_rejoin      = true,
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
    return true
end

SD.log("core loaded v" .. SD.version)

--[[
    file: 10_recon.lua
    Runtime discovery. Nothing in this suite hardcodes a remote name — the game
    can rename anything and the script keeps working. Everything the features
    touch comes out of this cache.
]]

local SD = getgenv().SD

local REMOTE_CLASSES = {
    RemoteEvent = true,
    RemoteFunction = true,
    UnreliableRemoteEvent = true,
}

SD.cache = {
    parts    = {},   -- BasePart list
    by_name  = {},   -- lowercase name -> { BasePart, ... }
    models   = {},   -- Model list
    prompts  = {},   -- ProximityPrompt
    clicks   = {},   -- ClickDetector
    remotes  = {},   -- { obj, name, path, class }
    at       = 0,
}

local CACHE_TTL = 3.0

-- name matching -------------------------------------------------------------

function SD.match(name, patterns)
    if type(patterns) == "string" then patterns = { patterns } end
    local ln = string.lower(tostring(name))
    for _, p in ipairs(patterns) do
        if string.find(ln, string.lower(p), 1, true) then return true end
    end
    return false
end

-- scanning ------------------------------------------------------------------

function SD.scan_remotes()
    local out = {}
    local roots = {}
    if SD.ReplicatedStorage then roots[#roots + 1] = SD.ReplicatedStorage end
    roots[#roots + 1] = workspace

    for _, root in ipairs(roots) do
        local ok, desc = pcall(function() return root:GetDescendants() end)
        if ok and desc then
            for _, d in ipairs(desc) do
                if REMOTE_CLASSES[d.ClassName] then
                    out[#out + 1] = {
                        obj   = d,
                        name  = d.Name,
                        path  = d:GetFullName(),
                        class = d.ClassName,
                    }
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.path < b.path end)
    SD.cache.remotes = out
    return out
end

function SD.scan_prompts()
    local out = {}
    local ok, desc = pcall(function() return workspace:GetDescendants() end)
    if ok and desc then
        for _, d in ipairs(desc) do
            if d:IsA("ProximityPrompt") then out[#out + 1] = d end
        end
    end
    SD.cache.prompts = out
    return out
end

function SD.scan_clicks()
    local out = {}
    local ok, desc = pcall(function() return workspace:GetDescendants() end)
    if ok and desc then
        for _, d in ipairs(desc) do
            if d:IsA("ClickDetector") then out[#out + 1] = d end
        end
    end
    SD.cache.clicks = out
    return out
end

function SD.scan_parts()
    local parts, by_name, models = {}, {}, {}
    local ok, desc = pcall(function() return workspace:GetDescendants() end)
    if ok and desc then
        for _, d in ipairs(desc) do
            if d:IsA("BasePart") then
                parts[#parts + 1] = d
                local key = string.lower(d.Name)
                local bucket = by_name[key]
                if not bucket then
                    bucket = {}
                    by_name[key] = bucket
                end
                bucket[#bucket + 1] = d
            elseif d:IsA("Model") then
                models[#models + 1] = d
            end
        end
    end
    SD.cache.parts = parts
    SD.cache.by_name = by_name
    SD.cache.models = models
    return parts
end

function SD.refresh(force)
    local now = os.clock()
    if not force and (now - SD.cache.at) < CACHE_TTL then return false end
    SD.cache.at = now
    SD.scan_parts()
    SD.scan_prompts()
    SD.scan_clicks()
    SD.scan_remotes()
    return true
end

-- lookups -------------------------------------------------------------------

function SD.find_parts(patterns)
    SD.refresh()
    local out = {}
    for _, p in ipairs(SD.cache.parts) do
        if SD.match(p.Name, patterns) then out[#out + 1] = p end
    end
    return out
end

function SD.find_models(patterns)
    SD.refresh()
    local out = {}
    for _, m in ipairs(SD.cache.models) do
        if SD.match(m.Name, patterns) then out[#out + 1] = m end
    end
    return out
end

function SD.prompts_matching(patterns)
    SD.refresh()
    local out = {}
    for _, p in ipairs(SD.cache.prompts) do
        local parent_name = p.Parent and p.Parent.Name or ""
        if SD.match(p.Name, patterns) or SD.match(parent_name, patterns) or SD.match(p.ObjectText or "", patterns) then
            out[#out + 1] = p
        end
    end
    return out
end

function SD.remotes_matching(patterns)
    SD.refresh()
    local out = {}
    for _, r in ipairs(SD.cache.remotes) do
        if SD.match(r.name, patterns) or SD.match(r.path, patterns) then out[#out + 1] = r end
    end
    return out
end

function SD.clicks_matching(patterns)
    SD.refresh()
    local out = {}
    for _, c in ipairs(SD.cache.clicks) do
        local parent_name = c.Parent and c.Parent.Name or ""
        if SD.match(parent_name, patterns) or SD.match(c.Name, patterns) then out[#out + 1] = c end
    end
    return out
end

-- nearest -------------------------------------------------------------------

local function dist_to(part, from)
    if not part or not part.Parent then return math.huge end
    local ok, d = pcall(function() return (part.Position - from).Magnitude end)
    if ok then return d end
    return math.huge
end

function SD.nearest_part(parts, from)
    local best, bestd = nil, math.huge
    for _, p in ipairs(parts) do
        local d = dist_to(p, from)
        if d < bestd then best, bestd = p, d end
    end
    return best, bestd
end

-- resolve a "target" from a list of instances into a BasePart we can walk to
function SD.resolve_part(inst)
    if not inst then return nil end
    if inst:IsA("BasePart") then return inst end
    if inst:IsA("ProximityPrompt") or inst:IsA("ClickDetector") then
        local p = inst.Parent
        if p and p:IsA("BasePart") then return p end
        if p then return p:FindFirstChildWhichIsA("BasePart", true) end
        return nil
    end
    if inst:IsA("Model") then
        return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
    end
    return inst:FindFirstChildWhichIsA("BasePart", true)
end

-- interaction ---------------------------------------------------------------

-- Fire every prompt and click detector living inside an instance.
function SD.interact(inst, radius)
    if not inst then return 0 end
    local fired = 0
    local targets = { inst }
    local ok, desc = pcall(function() return inst:GetDescendants() end)
    if ok and desc then
        for _, d in ipairs(desc) do targets[#targets + 1] = d end
    end

    for _, d in ipairs(targets) do
        if d:IsA("ProximityPrompt") then
            if SD.caps.fireprompt then
                pcall(fireproximityprompt, d)
                fired = fired + 1
            else
                pcall(function()
                    d:InputHoldBegin()
                    task.wait(d.HoldDuration + 0.05)
                    d:InputHoldEnd()
                end)
                fired = fired + 1
            end
        elseif d:IsA("ClickDetector") then
            if SD.caps.fireclick then
                pcall(fireclickdetector, d)
                fired = fired + 1
            end
        end
    end
    return fired
end

-- Fire prompts near a world position (used after a teleport).
function SD.interact_near(pos, radius)
    SD.refresh()
    local fired = 0
    for _, p in ipairs(SD.cache.prompts) do
        local part = SD.resolve_part(p)
        if part and dist_to(part, pos) <= (radius or 12) then
            if SD.caps.fireprompt then
                pcall(fireproximityprompt, p)
                fired = fired + 1
            end
        end
    end
    for _, c in ipairs(SD.cache.clicks) do
        local part = SD.resolve_part(c)
        if part and dist_to(part, pos) <= (radius or 12) then
            if SD.caps.fireclick then
                pcall(fireclickdetector, c)
                fired = fired + 1
            end
        end
    end
    return fired
end

-- remote probing ------------------------------------------------------------

function SD.describe_remote(r)
    return string.format("%s  [%s]", r.path, r.class)
end

-- Fire or invoke a remote with a table of args. Returns ok, result/error.
function SD.probe_remote(remote, args)
    if not remote then return false, "no remote" end
    args = args or {}
    local obj = remote.obj or remote
    if obj:IsA("RemoteFunction") then
        local ok, res = pcall(function() return obj:InvokeServer(unpack(args)) end)
        return ok, res
    elseif obj:IsA("RemoteEvent") or obj:IsA("UnreliableRemoteEvent") then
        local ok, res = pcall(function() obj:FireServer(unpack(args)) end)
        return ok, res
    end
    return false, "unsupported class " .. tostring(obj.ClassName)
end

-- console report ------------------------------------------------------------

function SD.dump()
    SD.refresh(true)
    SD.log(("=== %s recon ==="):format(SD.game_name))
    SD.log(("place: %s  job: %s"):format(
        tostring(game.PlaceId),
        tostring(game.JobId)
    ))
    SD.log(("parts: %d   prompts: %d   clickdetectors: %d   remotes: %d"):format(
        #SD.cache.parts, #SD.cache.prompts, #SD.cache.clicks, #SD.cache.remotes
    ))

    local interesting = {
        "sell", "buy", "upgrade", "dig", "dirt", "crown", "rebirth",
        "prestige", "claim", "collect", "reward", "cash", "money",
    }
    SD.log("--- remotes matching grind keywords ---")
    for _, r in ipairs(SD.remotes_matching(interesting)) do
        SD.log("  " .. SD.describe_remote(r))
    end

    SD.log("--- prompts ---")
    for _, p in ipairs(SD.cache.prompts) do
        local parent = p.Parent and p.Parent:GetFullName() or "?"
        SD.log(("  %s  hold=%.2f  parent=%s"):format(p.Name, p.HoldDuration or 0, parent))
    end

    SD.log("--- leaderstats ---")
    for k, v in pairs(SD.leaderstats()) do
        SD.log(("  %s = %s"):format(k, tostring(v)))
    end
    SD.log("=== end recon ===")
end

SD.log("recon loaded")

--[[
    file: 20_gui.lua
    Minimal immediate-mode-ish GUI kit. Touch first: 34px+ rows, no hover-only
    affordances, no right click, no keyboard dependency. Draggable by the title
    bar, clamped to the viewport on release.
]]

local SD = getgenv().SD
local TweenService = SD.TweenService
local UIS = SD.UserInputService

local gui = {}
SD.gui = gui
gui.ready = false
gui.tabs = {}
gui.current = nil

gui.theme = {
    bg     = Color3.fromRGB(13, 15, 20),
    panel  = Color3.fromRGB(20, 23, 30),
    panel2 = Color3.fromRGB(26, 30, 39),
    stroke = Color3.fromRGB(40, 46, 58),
    text   = Color3.fromRGB(232, 235, 242),
    muted  = Color3.fromRGB(138, 147, 166),
    accent = Color3.fromRGB(124, 92, 255),
    on     = Color3.fromRGB(56, 224, 160),
    off    = Color3.fromRGB(62, 68, 82),
    danger = Color3.fromRGB(255, 92, 110),
    warn   = Color3.fromRGB(255, 186, 84),
}
local T = gui.theme

local FONT       = Enum.Font.GothamMedium
local FONT_BOLD  = Enum.Font.GothamBold
local FONT_MONO  = Enum.Font.Code

-- primitives ----------------------------------------------------------------

local function new(class, props, children)
    local inst = Instance.new(class)
    local parent = props and props.Parent
    for k, v in pairs(props or {}) do
        if k ~= "Parent" then inst[k] = v end
    end
    for _, c in ipairs(children or {}) do c.Parent = inst end
    if parent then inst.Parent = parent end
    return inst
end

local function corner(inst, r)
    return new("UICorner", { CornerRadius = UDim.new(0, r or 8), Parent = inst })
end

local function stroke(inst, color, thickness)
    return new("UIStroke", {
        Color = color or T.stroke,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = inst,
    })
end

local function pad(inst, t, r, b, l)
    return new("UIPadding", {
        PaddingTop = UDim.new(0, t or 0),
        PaddingRight = UDim.new(0, r or 0),
        PaddingBottom = UDim.new(0, b or 0),
        PaddingLeft = UDim.new(0, l or 0),
        Parent = inst,
    })
end

local function vlist(inst, padding)
    return new("UIListLayout", {
        Padding = UDim.new(0, padding or 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
        FillDirection = Enum.FillDirection.Vertical,
        Parent = inst,
    })
end

local function label(parent, text, size, color, bold)
    return new("TextLabel", {
        Size = UDim2.new(1, 0, 0, size or 18),
        BackgroundTransparency = 1,
        Font = bold and FONT_BOLD or FONT,
        TextSize = 13,
        TextColor3 = color or T.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = text,
        Parent = parent,
    })
end

gui.new = new
gui.corner = corner
gui.stroke = stroke
gui.label = label

-- notifications -------------------------------------------------------------

local toast_host

function gui.notify(text, kind)
    if not toast_host or not toast_host.Parent then return end
    local color = T.accent
    if kind == "ok" then color = T.on
    elseif kind == "warn" then color = T.warn
    elseif kind == "err" then color = T.danger end

    local toast = new("Frame", {
        Size = UDim2.new(1, 0, 0, 38),
        BackgroundColor3 = T.panel2,
        BackgroundTransparency = 0.05,
        Parent = toast_host,
    })
    corner(toast, 9)
    stroke(toast, T.stroke)

    new("Frame", {
        Size = UDim2.new(0, 3, 1, -14),
        Position = UDim2.new(0, 0, 0, 7),
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        Parent = toast,
    })

    new("TextLabel", {
        Size = UDim2.new(1, -24, 1, 0),
        Position = UDim2.new(0, 14, 0, 0),
        BackgroundTransparency = 1,
        Font = FONT,
        TextSize = 12,
        TextColor3 = T.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = tostring(text),
        Parent = toast,
    })

    task.spawn(function()
        task.wait(2.6)
        if not toast.Parent then return end
        local info = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        TweenService:Create(toast, info, { BackgroundTransparency = 1 }):Play()
        task.wait(0.24)
        if toast then toast:Destroy() end
    end)
end

-- slider drag dispatch (one global listener instead of one per slider) -------

gui._drag = nil

UIS.InputChanged:Connect(function(input)
    local d = gui._drag
    if not d then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement
        and input.UserInputType ~= Enum.UserInputType.Touch then return end
    d.set(input.Position.X)
end)

UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        gui._drag = nil
    end
end)

-- window --------------------------------------------------------------------

function gui.build()
    local playerGui = SD.plr:WaitForChild("PlayerGui")

    local sg = new("ScreenGui", {
        Name = "SellDirtUI",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 9999,
    })
    local parented = pcall(function() sg.Parent = game:GetService("CoreGui") end)
    if not parented or not sg.Parent then sg.Parent = playerGui end
    gui.root = sg

    local camera = workspace.CurrentCamera
    local function viewport()
        if camera then return camera.ViewportSize end
        return Vector2.new(1280, 720)
    end

    -- toast host
    toast_host = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 54),
        Size = UDim2.new(0, 280, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = sg,
    })
    vlist(toast_host, 6)

    -- floating opener
    local opener = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -14, 0, 44),
        Size = UDim2.new(0, 46, 0, 46),
        BackgroundColor3 = T.accent,
        AutoButtonColor = false,
        Font = FONT_BOLD,
        TextSize = 13,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Text = "SD",
        Parent = sg,
    })
    corner(opener, 14)
    stroke(opener, Color3.fromRGB(160, 138, 255), 1)

    -- main window
    local vp = viewport()
    local winW = math.clamp(math.floor(vp.X * 0.62), 320, 500)
    local winH = math.clamp(math.floor(vp.Y * 0.72), 250, 380)

    local win = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, winW, 0, winH),
        BackgroundColor3 = T.bg,
        BorderSizePixel = 0,
        Visible = false,
        Parent = sg,
    })
    corner(win, 14)
    stroke(win, T.stroke)
    gui.window = win

    -- title bar
    local bar = new("Frame", {
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundColor3 = T.panel,
        BorderSizePixel = 0,
        Active = true,
        Parent = win,
    })
    corner(bar, 14)
    new("Frame", {
        Size = UDim2.new(1, 0, 0, 14),
        Position = UDim2.new(0, 0, 1, -14),
        BackgroundColor3 = T.panel,
        BorderSizePixel = 0,
        Parent = bar,
    })

    local dot = new("Frame", {
        Size = UDim2.new(0, 8, 0, 8),
        Position = UDim2.new(0, 14, 0, 18),
        BackgroundColor3 = T.accent,
        BorderSizePixel = 0,
        Parent = bar,
    })
    corner(dot, 4)

    local title = label(bar, "SELL DIRT", 16, T.text, true)
    title.Size = UDim2.new(0, 140, 0, 16)
    title.Position = UDim2.new(0, 30, 0, 7)
    title.TextSize = 13

    local ver = label(bar, "v" .. SD.version, 14, T.muted)
    ver.Size = UDim2.new(0, 140, 0, 14)
    ver.Position = UDim2.new(0, 30, 0, 23)
    ver.TextSize = 10

    local status = label(bar, "idle", 16, T.muted)
    status.Size = UDim2.new(0, 150, 0, 16)
    status.Position = UDim2.new(1, -168, 0, 14)
    status.TextXAlignment = Enum.TextXAlignment.Right
    gui.status = status

    local close = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -10, 0, 10),
        Size = UDim2.new(0, 24, 0, 24),
        BackgroundColor3 = T.panel2,
        AutoButtonColor = false,
        Font = FONT_BOLD,
        TextSize = 14,
        TextColor3 = T.muted,
        Text = "x",
        Parent = bar,
    })
    corner(close, 7)

    -- tab rail
    local rail = new("ScrollingFrame", {
        Position = UDim2.new(0, 0, 0, 44),
        Size = UDim2.new(1, 0, 0, 38),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 0,
        ScrollingDirection = Enum.ScrollingDirection.X,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.X,
        Parent = win,
    })
    pad(rail, 0, 10, 0, 10)
    new("UIListLayout", {
        Padding = UDim.new(0, 6),
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = rail,
    })

    -- body
    local body = new("Frame", {
        Position = UDim2.new(0, 0, 0, 86),
        Size = UDim2.new(1, 0, 1, -96),
        BackgroundTransparency = 1,
        Parent = win,
    })
    pad(body, 0, 10, 8, 10)
    gui.body = body

    -- open / close
    local function set_open(open)
        win.Visible = open
        opener.Visible = not open
    end
    opener.MouseButton1Click:Connect(function() set_open(true) end)
    close.MouseButton1Click:Connect(function() set_open(false) end)
    gui.set_open = set_open

    -- drag
    local dragging, drag_start, start_pos = false, nil, nil
    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            drag_start = input.Position
            start_pos = win.Position
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local d = input.Position - drag_start
        win.Position = UDim2.new(
            start_pos.X.Scale, start_pos.X.Offset + d.X,
            start_pos.Y.Scale, start_pos.Y.Offset + d.Y
        )
    end)
    UIS.InputEnded:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            local v = viewport()
            local half = win.AbsoluteSize / 2
            local cx = math.clamp(win.AbsolutePosition.X + half.X, half.X, v.X - half.X)
            local cy = math.clamp(win.AbsolutePosition.Y + half.Y, half.Y, v.Y - half.Y)
            win.Position = UDim2.fromOffset(cx, cy)
        end
    end)

    -- tabs
    function gui.tab(name)
        if gui.tabs[name] then return gui.tabs[name].content end

        local pill = new("TextButton", {
            Size = UDim2.new(0, 0, 0, 28),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = T.panel,
            AutoButtonColor = false,
            Font = FONT,
            TextSize = 12,
            TextColor3 = T.muted,
            Text = "  " .. name .. "  ",
            Parent = rail,
        })
        corner(pill, 9)

        local content = new("ScrollingFrame", {
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 3,
            ScrollBarImageColor3 = T.stroke,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Visible = false,
            Parent = body,
        })
        pad(content, 0, 6, 0, 0)
        vlist(content, 10)

        local entry = { pill = pill, content = content }
        gui.tabs[name] = entry

        pill.MouseButton1Click:Connect(function() gui.select(name) end)

        if not gui.current then gui.select(name) end
        return content
    end

    function gui.select(name)
        local entry = gui.tabs[name]
        if not entry then return end
        gui.current = name
        for n, e in pairs(gui.tabs) do
            local active = (n == name)
            e.content.Visible = active
            e.pill.BackgroundColor3 = active and T.accent or T.panel
            e.pill.TextColor3 = active and Color3.fromRGB(255, 255, 255) or T.muted
        end
    end

    function gui.set_status(text)
        if gui.status then gui.status.Text = tostring(text) end
    end

    gui.ready = true
    for _, n in ipairs(SD._notify_queue) do gui.notify(n.text, n.kind) end
    SD._notify_queue = {}

    set_open(true)
    return win
end

-- controls ------------------------------------------------------------------

function gui.section(parent, title)
    local sec = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = T.panel,
        BorderSizePixel = 0,
        Parent = parent,
    })
    corner(sec, 10)
    stroke(sec, T.stroke)
    pad(sec, 10, 10, 10, 10)
    vlist(sec, 8)

    if title then
        local h = label(sec, string.upper(title), 14, T.muted, true)
        h.TextSize = 11
    end
    return sec
end

function gui.toggle(parent, opts)
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundTransparency = 1,
        Parent = parent,
    })

    local text = new("TextLabel", {
        Size = UDim2.new(1, -56, 1, 0),
        BackgroundTransparency = 1,
        Font = FONT,
        TextSize = 12,
        TextColor3 = T.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = opts.text or "",
        Parent = row,
    })

    local track = new("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0, 38, 0, 20),
        BackgroundColor3 = T.off,
        BorderSizePixel = 0,
        Parent = row,
    })
    corner(track, 10)

    local knob = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.new(0, 14, 0, 14),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        Parent = track,
    })
    corner(knob, 7)

    local hit = new("TextButton", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        Parent = row,
    })

    local state = opts.default and true or false
    local info = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    local function paint(animate)
        local to = state
            and { Position = UDim2.new(1, -17, 0.5, 0) }
            or  { Position = UDim2.new(0, 3, 0.5, 0) }
        if animate then
            TweenService:Create(knob, info, to):Play()
            TweenService:Create(track, info, { BackgroundColor3 = state and T.on or T.off }):Play()
        else
            knob.Position = to.Position
            track.BackgroundColor3 = state and T.on or T.off
        end
    end

    local api = {}
    function api.set(v, silent)
        state = v and true or false
        paint(true)
        if not silent and opts.callback then opts.callback(state) end
    end
    function api.get() return state end

    hit.MouseButton1Click:Connect(function()
        api.set(not state)
    end)

    paint(false)
    if opts.default and opts.callback then
        task.defer(function() opts.callback(true) end)
    end
    return api
end

function gui.slider(parent, opts)
    local min = opts.min or 0
    local max = opts.max or 100
    local decimals = opts.decimals or 0
    local value = math.clamp(opts.default or min, min, max)

    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundTransparency = 1,
        Parent = parent,
    })

    new("TextLabel", {
        Size = UDim2.new(1, -70, 0, 16),
        BackgroundTransparency = 1,
        Font = FONT,
        TextSize = 12,
        TextColor3 = T.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = opts.text or "",
        Parent = row,
    })

    local readout = new("TextLabel", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.new(0, 70, 0, 16),
        BackgroundTransparency = 1,
        Font = FONT_MONO,
        TextSize = 12,
        TextColor3 = T.accent,
        TextXAlignment = Enum.TextXAlignment.Right,
        Text = "",
        Parent = row,
    })

    local track = new("Frame", {
        Position = UDim2.new(0, 0, 0, 30),
        Size = UDim2.new(1, 0, 0, 6),
        BackgroundColor3 = T.panel2,
        BorderSizePixel = 0,
        Parent = row,
    })
    corner(track, 3)

    local fill = new("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = T.accent,
        BorderSizePixel = 0,
        Parent = track,
    })
    corner(fill, 3)

    local knob = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(0, 14, 0, 14),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        Parent = track,
    })
    corner(knob, 7)
    stroke(knob, T.accent, 2)

    local function paint()
        local a = (max > min) and ((value - min) / (max - min)) or 0
        fill.Size = UDim2.new(a, 0, 1, 0)
        knob.Position = UDim2.new(a, 0, 0.5, 0)
        local suffix = opts.suffix or ""
        local shown = decimals > 0
            and string.format("%." .. decimals .. "f", value)
            or tostring(math.floor(value + 0.5))
        readout.Text = shown .. suffix
    end

    local function set_from_x(x)
        local abs = track.AbsolutePosition.X
        local w = track.AbsoluteSize.X
        if w <= 0 then return end
        local a = math.clamp((x - abs) / w, 0, 1)
        local raw = min + (max - min) * a
        local m = 10 ^ decimals
        value = math.floor(raw * m + 0.5) / m
        value = math.clamp(value, min, max)
        paint()
        if opts.callback then opts.callback(value) end
    end

    local hit = new("TextButton", {
        Position = UDim2.new(0, 0, 0, 22),
        Size = UDim2.new(1, 0, 0, 22),
        BackgroundTransparency = 1,
        Text = "",
        Parent = row,
    })

    hit.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            gui._drag = { set = set_from_x }
            set_from_x(input.Position.X)
        end
    end)

    local api = {}
    function api.get() return value end
    function api.set(v)
        value = math.clamp(v, min, max)
        paint()
        if opts.callback then opts.callback(value) end
    end

    paint()
    return api
end

function gui.button(parent, opts)
    local btn = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = opts.color or T.panel2,
        AutoButtonColor = false,
        Font = FONT,
        TextSize = 12,
        TextColor3 = opts.text_color or T.text,
        Text = opts.text or "",
        Parent = parent,
    })
    corner(btn, 8)
    stroke(btn, opts.stroke or T.stroke)

    btn.MouseButton1Click:Connect(function()
        if opts.callback then
            task.spawn(function()
                local ok, err = pcall(opts.callback)
                if not ok then
                    SD.notify("error: " .. tostring(err), "err")
                    SD.warn(err)
                end
            end)
        end
    end)
    return btn
end

function gui.divider(parent)
    return new("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = T.stroke,
        BorderSizePixel = 0,
        Parent = parent,
    })
end

function gui.textbox(parent, opts)
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundTransparency = 1,
        Parent = parent,
    })

    new("TextLabel", {
        Size = UDim2.new(0, 108, 1, 0),
        BackgroundTransparency = 1,
        Font = FONT,
        TextSize = 12,
        TextColor3 = T.muted,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = opts.text or "",
        Parent = row,
    })

    local box = new("TextBox", {
        Position = UDim2.new(0, 112, 0, 0),
        Size = UDim2.new(1, -112, 1, 0),
        BackgroundColor3 = T.panel2,
        Font = FONT_MONO,
        TextSize = 12,
        TextColor3 = T.text,
        PlaceholderText = opts.placeholder or "",
        PlaceholderColor3 = T.muted,
        Text = opts.default or "",
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })
    corner(box, 7)
    stroke(box, T.stroke)
    pad(box, 0, 8, 0, 8)

    box.FocusLost:Connect(function()
        if opts.callback then opts.callback(box.Text) end
    end)

    local api = {}
    function api.get() return box.Text end
    function api.set(v) box.Text = tostring(v) end
    return api
end

-- cycling dropdown: no overlay, no clipping inside a scrolling frame ---------

function gui.dropdown(parent, opts)
    local options = opts.options or {}
    local index = 1
    if opts.default then
        for i, o in ipairs(options) do
            if o == opts.default then index = i break end
        end
    end

    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundTransparency = 1,
        Parent = parent,
    })

    new("TextLabel", {
        Size = UDim2.new(0, 108, 1, 0),
        BackgroundTransparency = 1,
        Font = FONT,
        TextSize = 12,
        TextColor3 = T.muted,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = opts.text or "",
        Parent = row,
    })

    local btn = new("TextButton", {
        Position = UDim2.new(0, 112, 0, 0),
        Size = UDim2.new(1, -112, 1, 0),
        BackgroundColor3 = T.panel2,
        AutoButtonColor = false,
        Font = FONT,
        TextSize = 12,
        TextColor3 = T.text,
        Text = tostring(options[index] or "-"),
        Parent = row,
    })
    corner(btn, 7)
    stroke(btn, T.stroke)

    local api = {}
    local function apply(silent)
        btn.Text = tostring(options[index] or "-")
        if not silent and opts.callback then opts.callback(options[index]) end
    end

    btn.MouseButton1Click:Connect(function()
        if #options == 0 then return end
        index = index % #options + 1
        apply(false)
    end)

    function api.get() return options[index] end
    function api.set(v)
        for i, o in ipairs(options) do
            if o == v then index = i break end
        end
        apply(true)
    end
    function api.set_options(list)
        options = list
        index = 1
        apply(true)
    end

    return api
end

SD.log("gui loaded")

--[[
    file: 30_features.lua
    The grind loop. Every target is resolved by name heuristic against the live
    cache, with a manual override in config for when recon gives us the real
    names. Nothing here assumes a specific remote exists.
]]

local SD = getgenv().SD
local F = {}
SD.features = F

-- defaults that live here rather than in core (feature-local knobs)
if SD.config.sell_return == nil then SD.config.sell_return = true end
if SD.config.dig_mode == nil then SD.config.dig_mode = "both" end
if SD.config.esp_players == nil then SD.config.esp_players = false end

-- rate gate ---------------------------------------------------------------

local gates = {}
function SD.gate(key, delay)
    local now = os.clock()
    if (gates[key] or 0) > now then return false end
    gates[key] = now + delay
    return true
end

-- target resolution -------------------------------------------------------

local SELL_PATTERNS   = { "sell", "cashout", "cash out", "exchange", "turn in" }
local SELL_FALLBACK   = { "market", "shop", "store", "vendor", "trade", "deposit" }
local CROWN_PATTERNS  = { "crown" }
local DIRT_PATTERNS   = { "dirt", "soil", "mud", "ore", "rock pile" }
local UPGRADE_PATTERNS = { "upgrade", "improve", "buy", "purchase", "level" }
local REBIRTH_PATTERNS = { "rebirth", "prestige", "ascend", "reset" }
local TOOL_PATTERNS   = { "shovel", "spade", "dig", "pickaxe", "drill", "excavator" }

function F.sell_target()
    local custom = SD.config.sell_name
    if custom and custom ~= "" then
        local p = SD.find_parts({ custom })
        if #p > 0 then return p[1] end
        local pr = SD.prompts_matching({ custom })
        if #pr > 0 then return pr[1] end
    end
    local pr = SD.prompts_matching(SELL_PATTERNS)
    if #pr > 0 then return pr[1] end
    local cd = SD.clicks_matching(SELL_PATTERNS)
    if #cd > 0 then return cd[1] end
    local parts = SD.find_parts(SELL_PATTERNS)
    if #parts > 0 then return parts[1] end
    local pr2 = SD.prompts_matching(SELL_FALLBACK)
    if #pr2 > 0 then return pr2[1] end
    return nil
end

local crown_memo, crown_memo_at = nil, 0

function F.crown_target()
    if crown_memo and crown_memo.Parent and (os.clock() - crown_memo_at) < 3 then
        return crown_memo
    end

    local found = nil

    local custom = SD.config.crown_name
    if custom and custom ~= "" then
        local p = SD.find_parts({ custom })
        if #p > 0 then found = p[1] end
    end

    if not found then
        local parts = SD.find_parts(CROWN_PATTERNS)
        if #parts > 0 then found = parts[1] end
    end

    if not found then
        local models = SD.find_models(CROWN_PATTERNS)
        if #models > 0 then found = models[1] end
    end

    -- last resort: the part carrying a BillboardGui that says "crown".
    -- Gated — this walks every part and is only worth it a couple of times a minute.
    if not found and SD.gate("crown_billboard_scan", 8) then
        SD.refresh()
        for _, p in ipairs(SD.cache.parts) do
            local bb = p:FindFirstChildWhichIsA("BillboardGui", true)
            if bb then
                for _, d in ipairs(bb:GetDescendants()) do
                    if d:IsA("TextLabel") and SD.match(d.Text, CROWN_PATTERNS) then
                        found = p
                        break
                    end
                end
            end
            if found then break end
        end
    end

    if found then
        crown_memo, crown_memo_at = found, os.clock()
    end
    return found
end

function F.dirt_target()
    local hrp = SD.get_hrp()
    local parts = SD.find_parts(DIRT_PATTERNS)
    if #parts == 0 then return nil end
    if not hrp then return parts[1] end
    return (SD.nearest_part(parts, hrp.Position))
end

function F.upgrade_target()
    local pr = SD.prompts_matching(UPGRADE_PATTERNS)
    if #pr > 0 then return pr[1] end
    local cd = SD.clicks_matching(UPGRADE_PATTERNS)
    if #cd > 0 then return cd[1] end
    return nil
end

function F.rebirth_target()
    local pr = SD.prompts_matching(REBIRTH_PATTERNS)
    if #pr > 0 then return pr[1] end
    local cd = SD.clicks_matching(REBIRTH_PATTERNS)
    if #cd > 0 then return cd[1] end
    return nil
end

function F.dig_tool()
    local ch = SD.get_char()
    if not ch then return nil end
    local patterns = TOOL_PATTERNS
    if SD.config.dig_tool_name and SD.config.dig_tool_name ~= "" then
        patterns = { SD.config.dig_tool_name }
    end

    local equipped = ch:FindFirstChildOfClass("Tool")
    if equipped and SD.match(equipped.Name, patterns) then return equipped end

    local bp = SD.plr:FindFirstChild("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and SD.match(t.Name, patterns) then
                local hum = SD.get_hum()
                if hum then pcall(function() hum:EquipTool(t) end) end
                return t
            end
        end
    end
    return equipped
end

-- movement helpers --------------------------------------------------------

function F.visit(inst, opts)
    opts = opts or {}
    local part = SD.resolve_part(inst)
    if not part then return false, 0 end
    local hrp = SD.get_hrp()
    if not hrp then return false, 0 end

    if opts.anchor ~= false and not SD.state.anchor then
        SD.state.anchor = hrp.CFrame
    end

    local offset = CFrame.new(0, opts.y_offset or 3, 0)
    SD.tp(part.CFrame * offset)
    task.wait(opts.settle or 0.22)

    local fired = SD.interact_near(part.Position, opts.radius or 16)
    if fired == 0 then fired = SD.interact(inst) end
    return true, fired
end

function F.return_home()
    if SD.state.anchor then SD.tp(SD.state.anchor) end
end

-- core actions ------------------------------------------------------------

function F.sell_once()
    local rname = SD.config.sell_remote
    if rname and rname ~= "" then
        local list = SD.remotes_matching({ rname })
        if #list > 0 then
            local ok, err = SD.probe_remote(list[1], {})
            if not ok then SD.warn("sell remote failed: " .. tostring(err)) end
            return ok
        end
    end

    local target = F.sell_target()
    if not target then return false end

    local ok, fired = F.visit(target, { radius = 18, settle = 0.25 })
    if not ok then return false end

    if fired == 0 then
        -- prompt may need a hold; try the raw prompt API on the object itself
        SD.interact(target)
    end

    if SD.config.sell_return then
        task.delay(0.4, F.return_home)
    end
    return true
end

function F.dig_click()
    local hrp = SD.get_hrp()
    if not hrp then return 0 end
    SD.refresh()
    local fired = 0
    for _, c in ipairs(SD.cache.clicks) do
        local part = SD.resolve_part(c)
        if part then
            local d = (part.Position - hrp.Position).Magnitude
            if d <= 26 then
                local pname = c.Parent and c.Parent.Name or ""
                if SD.match(part.Name, DIRT_PATTERNS) or SD.match(pname, DIRT_PATTERNS) then
                    pcall(fireclickdetector, c)
                    fired = fired + 1
                end
            end
        end
    end
    return fired
end

function F.dig_once()
    local mode = SD.config.dig_mode or "both"
    local acted = false

    if mode == "tool" or mode == "both" then
        local tool = F.dig_tool()
        if tool then
            pcall(function() tool:Activate() end)
            acted = true
        end
    end

    if mode == "click" or mode == "both" then
        if F.dig_click() > 0 then acted = true end
    end

    if not acted and SD.caps.fireprompt then
        local hrp = SD.get_hrp()
        if hrp then
            SD.refresh()
            for _, p in ipairs(SD.cache.prompts) do
                local part = SD.resolve_part(p)
                if part and (part.Position - hrp.Position).Magnitude <= 22 then
                    local pname = p.Parent and p.Parent.Name or ""
                    if SD.match(pname, DIRT_PATTERNS) or SD.match(p.Name, DIRT_PATTERNS) then
                        pcall(fireproximityprompt, p)
                        acted = true
                    end
                end
            end
        end
    end

    return acted
end

function F.collect_once()
    local hrp = SD.get_hrp()
    if not hrp then return 0 end
    return SD.interact_near(hrp.Position, 40)
end

function F.upgrade_once()
    local t = F.upgrade_target()
    if not t then return false end
    local ok = F.visit(t, { radius = 16, settle = 0.2 })
    if SD.config.sell_return then task.delay(0.4, F.return_home) end
    return ok
end

function F.rebirth_once()
    local t = F.rebirth_target()
    if not t then return false end
    local ok = F.visit(t, { radius = 16, settle = 0.2 })
    if SD.config.sell_return then task.delay(0.4, F.return_home) end
    return ok
end

function F.goto_crown()
    local t = F.crown_target()
    if not t then
        -- crown may live on the leaderboard leader
        local lead = F.leader()
        if lead then
            local ch = lead.Character
            if ch then
                local hrp = ch:FindFirstChild("HumanoidRootPart")
                if hrp then
                    SD.tp(hrp.CFrame * CFrame.new(0, 0, 3))
                    return true
                end
            end
        end
        return false
    end
    local ok, fired = F.visit(t, { radius = 18, settle = 0.25, anchor = false })
    return ok
end

function F.leader()
    local best, bestv = nil, -math.huge
    for _, plr in ipairs(SD.Players:GetPlayers()) do
        if plr ~= SD.plr then
            local ls = plr:FindFirstChild("leaderstats")
            if ls then
                for _, v in ipairs(ls:GetChildren()) do
                    if v:IsA("ValueBase") and type(v.Value) == "number" then
                        if v.Value > bestv then best, bestv = plr, v.Value end
                    end
                end
            end
        end
    end
    return best
end

function F.goto_sell()
    local t = F.sell_target()
    if not t then return false end
    local ok = F.visit(t, { radius = 18, anchor = false })
    return ok
end

function F.goto_dirt()
    local t = F.dirt_target()
    if not t then return false end
    return SD.tp(t.CFrame * CFrame.new(0, 4, 0))
end

-- ESP ---------------------------------------------------------------------

F.esp_store = { crown = {}, sell = {}, dirt = {}, players = {} }

local ESP_COLORS = {
    crown   = Color3.fromRGB(255, 196, 64),
    sell    = Color3.fromRGB(56, 224, 160),
    dirt    = Color3.fromRGB(120, 170, 255),
    players = Color3.fromRGB(255, 92, 110),
}

local function esp_add(bucket_name, inst, color)
    local bucket = F.esp_store[bucket_name]
    if not bucket then return end
    local part = SD.resolve_part(inst)
    if not part then return end
    local key = part:GetFullName()
    if bucket[key] and bucket[key].Parent then return end

    local h = Instance.new("Highlight")
    h.Name = "SD_ESP"
    h.FillColor = color
    h.FillTransparency = 0.6
    h.OutlineColor = color
    h.OutlineTransparency = 0
    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    h.Adornee = part
    h.Parent = SD.gui.root or SD.plr:FindFirstChild("PlayerGui")
    bucket[key] = h
end

local function esp_clear(bucket_name)
    local bucket = F.esp_store[bucket_name]
    if not bucket then return end
    for k, h in pairs(bucket) do
        if h then pcall(function() h:Destroy() end) end
        bucket[k] = nil
    end
end

function F.esp_tick()
    if SD.config.esp_crown then
        local t = F.crown_target()
        if t then esp_add("crown", t, ESP_COLORS.crown) end
    else
        esp_clear("crown")
    end

    if SD.config.esp_sell then
        local t = F.sell_target()
        if t then esp_add("sell", t, ESP_COLORS.sell) end
    else
        esp_clear("sell")
    end

    if SD.config.esp_dirt then
        for _, p in ipairs(SD.find_parts(DIRT_PATTERNS)) do
            esp_add("dirt", p, ESP_COLORS.dirt)
        end
    else
        esp_clear("dirt")
    end

    if SD.config.esp_players then
        for _, plr in ipairs(SD.Players:GetPlayers()) do
            if plr ~= SD.plr and plr.Character then
                local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
                if hrp then esp_add("players", hrp, ESP_COLORS.players) end
            end
        end
    else
        esp_clear("players")
    end
end

-- utility features --------------------------------------------------------

function F.anti_afk_enable()
    if F._afk_conn then return end
    F._afk_conn = SD.plr.Idled:Connect(function()
        if not SD.config.anti_afk then return end
        local vu = SD.VirtualUser
        if vu then
            pcall(function()
                vu:CaptureController()
                vu:ClickButton2(Vector2.new())
            end)
        end
        local hum = SD.get_hum()
        if hum then pcall(function() hum.Jump = true end) end
    end)
end

local LIGHTING_KEYS = { "Brightness", "ClockTime", "GlobalShadows", "FogEnd", "Ambient", "OutdoorAmbient" }
F._lighting_backup = nil

function F.fullbright_apply()
    local L = SD.Lighting
    if not L then return end
    if not F._lighting_backup then
        F._lighting_backup = {}
        for _, k in ipairs(LIGHTING_KEYS) do
            F._lighting_backup[k] = L[k]
        end
    end
    L.Brightness = 2
    L.ClockTime = 14
    L.GlobalShadows = false
    L.FogEnd = 100000
    L.Ambient = Color3.fromRGB(178, 178, 178)
    L.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
end

function F.fullbright_restore()
    local L = SD.Lighting
    if not L or not F._lighting_backup then return end
    for k, v in pairs(F._lighting_backup) do
        pcall(function() L[k] = v end)
    end
    F._lighting_backup = nil
end

local FX_CLASSES = { "BlurEffect", "BloomEffect", "SunRaysEffect", "ColorCorrectionEffect", "DepthOfFieldEffect" }
F._fx_backup = nil

function F.fps_boost_apply()
    local L = SD.Lighting
    if not L then return end
    F._fx_backup = F._fx_backup or {}
    for _, fx in ipairs(L:GetChildren()) do
        if table.find(FX_CLASSES, fx.ClassName) and fx.Enabled then
            F._fx_backup[fx] = true
            fx.Enabled = false
        end
    end
    pcall(function()
        local ugs = UserSettings():GetService("UserGameSettings")
        ugs.SavedQualitySetting = Enum.SavedQualitySetting.QualityLevel1
    end)
end

function F.fps_boost_restore()
    if not F._fx_backup then return end
    for fx in pairs(F._fx_backup) do
        if fx and fx.Parent then pcall(function() fx.Enabled = true end) end
    end
    F._fx_backup = nil
end

-- rejoin / hop ------------------------------------------------------------

function F.rejoin()
    if SD.state.rejoin_guard then return end
    SD.state.rejoin_guard = true
    SD.notify("rejoining...", "warn")
    task.wait(0.5)
    pcall(function()
        SD.TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, SD.plr)
    end)
end

function F.auto_rejoin_enable()
    if F._rejoin_conn then return end
    local CoreGui = SD.safe(function() return game:GetService("CoreGui") end)
    local prompt = CoreGui and CoreGui:FindFirstChild("RobloxPromptGui")
    local overlay = prompt and prompt:FindFirstChild("promptOverlay")

    if overlay then
        F._rejoin_conn = overlay.ChildAdded:Connect(function(child)
            if not SD.config.auto_rejoin then return end
            if child.Name == "ErrorPrompt" or child.Name == "GenericMessagePrompt" then
                task.delay(1.5, F.rejoin)
            end
        end)
    end

    SD.plr.AncestryChanged:Connect(function()
        if not SD.config.auto_rejoin then return end
        if not SD.plr:IsDescendantOf(game) then F.rejoin() end
    end)
end

function F.server_hop()
    local ok, body = pcall(function()
        return game:HttpGet(("https://games.roblox.com/v1/games/%d/servers/Public?limit=100&excludeFullGames=true"):format(game.PlaceId))
    end)
    if not ok or not body then
        SD.notify("hop failed: http blocked", "err")
        return
    end
    local dec_ok, data = pcall(function() return SD.HttpService:JSONDecode(body) end)
    if not dec_ok or not data or not data.data or #data.data == 0 then
        SD.notify("no servers found", "warn")
        return
    end
    local pick = data.data[math.random(1, #data.data)]
    SD.notify("hopping to " .. tostring(pick.id):sub(1, 8), "info")
    pcall(function()
        SD.TeleportService:TeleportToPlaceInstance(game.PlaceId, pick.id, SD.plr)
    end)
end

-- background tasks --------------------------------------------------------

function F.register_tasks()
    SD.add_task("auto_sell", 0.1, function()
        if not SD.config.auto_sell or SD.state.paused then return end
        if not SD.alive() then return end
        if not SD.gate("auto_sell", SD.config.auto_sell_delay) then return end
        F.sell_once()
    end)

    SD.add_task("auto_dig", 0.1, function()
        if not SD.config.auto_dig or SD.state.paused then return end
        if not SD.alive() then return end
        if not SD.gate("auto_dig", SD.config.auto_dig_delay) then return end
        F.dig_once()
    end)

    SD.add_task("auto_collect", 0.1, function()
        if not SD.config.auto_collect or SD.state.paused then return end
        if not SD.alive() then return end
        if not SD.gate("auto_collect", 0.8) then return end
        F.collect_once()
    end)

    SD.add_task("auto_upgrade", 0.1, function()
        if not SD.config.auto_upgrade or SD.state.paused then return end
        if not SD.alive() then return end
        if not SD.gate("auto_upgrade", 3.0) then return end
        F.upgrade_once()
    end)

    SD.add_task("auto_rebirth", 0.1, function()
        if not SD.config.auto_rebirth or SD.state.paused then return end
        if not SD.alive() then return end
        if not SD.gate("auto_rebirth", 5.0) then return end
        F.rebirth_once()
    end)

    SD.add_task("tp_crown", 0.1, function()
        if not SD.config.tp_crown or SD.state.paused then return end
        if not SD.alive() then return end
        if not SD.gate("tp_crown", SD.config.tp_crown_delay) then return end
        F.goto_crown()
    end)

    SD.add_task("speed_lock", 0.25, function()
        local hum = SD.get_hum()
        if not hum then return end
        if SD.config.walkspeed_lock and hum.WalkSpeed ~= SD.config.walkspeed then
            hum.WalkSpeed = SD.config.walkspeed
        end
        if SD.config.jumppower_lock then
            if not hum.UseJumpPower then hum.UseJumpPower = true end
            if hum.JumpPower ~= SD.config.jumppower then
                hum.JumpPower = SD.config.jumppower
            end
        end
    end)

    SD.add_task("esp", 0.8, function()
        F.esp_tick()
    end)

    SD.add_task("fullbright", 2.0, function()
        if SD.config.fullbright then F.fullbright_apply() end
    end)

    SD.add_task("stats", 0.5, function()
        local cash, name = SD.cash()
        if cash then
            if SD.state.last_cash and cash > SD.state.last_cash then
                SD.state.session_earned = SD.state.session_earned + (cash - SD.state.last_cash)
            end
            SD.state.last_cash = cash
            if SD.gui and SD.gui.set_status then
                SD.gui.set_status(("%s %s"):format(name or "cash", SD.fmt(cash)))
            end
        end
    end)
end

-- character lifecycle -----------------------------------------------------

function F.bind_character()
    SD.state.anchor = nil
    local ch = SD.get_char()
    if not ch then return end
    local hum = ch:FindFirstChildOfClass("Humanoid")
    if hum then
        if SD.config.walkspeed_lock then hum.WalkSpeed = SD.config.walkspeed end
        if SD.config.jumppower_lock then
            hum.UseJumpPower = true
            hum.JumpPower = SD.config.jumppower
        end
    end
end

SD.plr.CharacterAdded:Connect(function()
    task.wait(0.4)
    F.bind_character()
end)

F.anti_afk_enable()
F.auto_rejoin_enable()

SD.log("features loaded")

--[[
    file: 40_exploits.lua
    Discovery + probe kit.

    The game is not readable from outside, so nothing here guesses a remote
    name. It enumerates, filters, fires, and measures the cash delta. A remote
    that pays out on a bare FireServer() with no server-side validation is the
    classic Sell-Dirt-class bug: the client owns the amount.

    Everything in here is manual-trigger. Blind-firing every remote on load is
    a ban in three seconds, not a cheat.
]]

local SD = getgenv().SD
local E = {}
SD.exploits = E

E.selected = nil
E.hits = {}

-- arg parsing --------------------------------------------------------------

function E.parse_args(str)
    local out = {}
    if not str or str == "" then return out end
    for token in string.gmatch(str, "[^,]+") do
        token = string.gsub(string.gsub(token, "^%s+", ""), "%s+$", "")
        if token ~= "" then
            local num = tonumber(token)
            if num then
                out[#out + 1] = num
            elseif token == "true" then
                out[#out + 1] = true
            elseif token == "false" then
                out[#out + 1] = false
            else
                out[#out + 1] = (string.gsub(token, '^"(.*)"$', "%1"))
            end
        end
    end
    return out
end

-- cash delta probe --------------------------------------------------------

-- Fire a remote, watch the money stat. Returns gained, amount.
function E.cash_probe(remote, args, settle)
    local before = SD.cash()
    local ok, err = SD.probe_remote(remote, args)
    if not ok then return false, 0, tostring(err) end
    task.wait(settle or 0.6)
    local after = SD.cash()
    if before and after and after > before then
        return true, after - before, nil
    end
    return false, 0, nil
end

-- Fuzz one remote with a spread of payload shapes. Logs which ones land.
function E.fuzz(remote)
    local payloads = {
        { "empty",        {} },
        { "zero",         { 0 } },
        { "negative",     { -1 } },
        { "one",          { 1 } },
        { "huge",         { 1e9 } },
        { "huger",        { 1e12 } },
        { "string one",   { "1" } },
        { "string huge",  { "999999999999" } },
        { "true",         { true } },
        { "empty string", { "" } },
        { "table",        { {} } },
        { "vector",       { Vector3.new(0, 0, 0) } },
        { "cframe",       { CFrame.new() } },
    }

    local results = {}
    for _, entry in ipairs(payloads) do
        local label, args = entry[1], entry[2]
        local before = SD.cash()
        local ok, err = SD.probe_remote(remote, args)
        task.wait(0.4)
        local after = SD.cash()
        local gain = (before and after and after > before) and (after - before) or 0
        results[#results + 1] = { label = label, ok = ok, err = err, gain = gain }
        SD.log(("[fuzz] %-14s ok=%s gain=%s %s"):format(
            label, tostring(ok), SD.fmt(gain), err and tostring(err) or ""
        ))
        if gain > 0 then
            E.hits[#E.hits + 1] = { path = remote.path or tostring(remote), args = label, gain = gain }
        end
    end
    return results
end

-- Auto hunt: fire every grind-keyword remote with a couple of shapes and
-- report the ones that move money.
function E.auto_hunt()
    local keywords = {
        "sell", "cash", "money", "coin", "reward", "claim",
        "collect", "buy", "upgrade", "dig", "dirt", "deposit",
    }
    local list = SD.remotes_matching(keywords)
    if #list > 40 then
        local trimmed = {}
        for i = 1, 40 do trimmed[i] = list[i] end
        list = trimmed
    end

    SD.notify(("hunting %d remotes"):format(#list), "info")
    local found = 0

    for _, r in ipairs(list) do
        if SD.state.paused then break end

        local before = SD.cash()
        SD.probe_remote(r, {})
        task.wait(0.3)
        local after = SD.cash()
        if before and after and after > before then
            found = found + 1
            E.hits[#E.hits + 1] = { path = r.path, args = "empty", gain = after - before }
            SD.log(("[hunt] HIT %s  +%s"):format(r.path, SD.fmt(after - before)))
        else
            -- second pass: a number argument is the common shape for
            -- "sell(amount)" style remotes
            local b2 = SD.cash()
            SD.probe_remote(r, { 1 })
            task.wait(0.3)
            local a2 = SD.cash()
            if b2 and a2 and a2 > b2 then
                found = found + 1
                E.hits[#E.hits + 1] = { path = r.path, args = "1", gain = a2 - b2 }
                SD.log(("[hunt] HIT %s  +%s (arg=1)"):format(r.path, SD.fmt(a2 - b2)))
            end
        end
    end

    SD.notify(("hunt done: %d hits"):format(found), found > 0 and "ok" or "warn")
    return E.hits
end

-- client-side primitives --------------------------------------------------

-- ProximityPrompt config is replicated from the server, but the *hold* is
-- evaluated client-side in most games. Zeroing HoldDuration and lifting
-- MaxActivationDistance is the cheapest reach exploit there is.
function E.prompt_spoof()
    SD.refresh(true)
    local n = 0
    for _, p in ipairs(SD.cache.prompts) do
        local ok = pcall(function()
            p.HoldDuration = 0
            p.MaxActivationDistance = math.huge
            p.RequiresLineOfSight = false
            p.Enabled = true
        end)
        if ok then n = n + 1 end
    end
    return n
end

function E.click_spoof()
    SD.refresh(true)
    local n = 0
    for _, c in ipairs(SD.cache.clicks) do
        local ok = pcall(function() c.MaxActivationDistance = math.huge end)
        if ok then n = n + 1 end
    end
    return n
end

E._noclip = false

function E.noclip(on)
    E._noclip = on and true or false
    local ch = SD.get_char()
    if not ch then return end
    for _, p in ipairs(ch:GetDescendants()) do
        if p:IsA("BasePart") then
            pcall(function() p.CanCollide = not E._noclip end)
        end
    end
end

function E.god()
    local hum = SD.get_hum()
    if not hum then return false end
    pcall(function()
        hum.MaxHealth = math.huge
        hum.Health = math.huge
    end)
    return true
end

function E.infinite_jump()
    local hum = SD.get_hum()
    if not hum then return false end
    pcall(function()
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end)
    return true
end

-- Write a client-side ValueBase. If the server ever reads these back without
-- validating, this is the dupe primitive.
function E.client_values()
    local out = {}
    local plr = SD.plr
    for _, v in ipairs(plr:GetDescendants()) do
        if v:IsA("ValueBase") then
            out[#out + 1] = { obj = v, path = v:GetFullName(), value = v.Value }
        end
    end
    return out
end

function E.write_value(needle, value)
    if not needle or needle == "" then return 0 end
    local n = 0
    for _, entry in ipairs(E.client_values()) do
        if SD.match(entry.path, { needle }) then
            local ok = pcall(function() entry.obj.Value = value end)
            if ok then n = n + 1 end
        end
    end
    return n
end

-- GUI ---------------------------------------------------------------------

function E.build_gui(parent, gui)
    local T = gui.theme

    local disc = gui.section(parent, "Discovery")
    gui.label(disc, "Nothing is hardcoded. Scan, then pin names in Grind.", 16, T.muted).TextSize = 11

    gui.button(disc, {
        text = "Dump recon to console (F9)",
        callback = function()
            SD.dump()
            SD.notify("recon dumped to console", "ok")
        end,
    })

    gui.button(disc, {
        text = "Refresh cache",
        callback = function()
            SD.refresh(true)
            SD.notify(("%d remotes / %d prompts"):format(#SD.cache.remotes, #SD.cache.prompts), "ok")
        end,
    })

    gui.button(disc, {
        text = "Auto-hunt: fire candidates, watch cash",
        color = T.accent,
        callback = function()
            E.auto_hunt()
        end,
    })

    -- remote browser
    local rem = gui.section(parent, "Remote probe")
    local filter_box = gui.textbox(rem, {
        text = "filter",
        default = "sell",
        placeholder = "sell",
    })

    local list_host = gui.new("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, 150),
        BackgroundColor3 = T.panel2,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = T.stroke,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = rem,
    })
    gui.corner(list_host, 8)
    gui.new("UIPadding", {
        PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
        PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
        Parent = list_host,
    })
    gui.new("UIListLayout", {
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = list_host,
    })

    local selected_label = gui.label(rem, "selected: none", 16, T.muted)
    selected_label.TextSize = 11

    local function select(r)
        E.selected = r
        selected_label.Text = "selected: " .. (r and r.name or "none")
        selected_label.TextColor3 = r and T.on or T.muted
    end

    local function populate()
        for _, c in ipairs(list_host:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end
        local needle = filter_box.get()
        local list = SD.cache.remotes
        if needle and needle ~= "" then
            list = SD.remotes_matching({ needle })
        end
        local shown = 0
        for _, r in ipairs(list) do
            if shown >= 60 then break end
            shown = shown + 1
            local b = gui.new("TextButton", {
                Size = UDim2.new(1, 0, 0, 24),
                BackgroundColor3 = T.panel,
                AutoButtonColor = false,
                Font = Enum.Font.Code,
                TextSize = 11,
                TextColor3 = T.text,
                TextXAlignment = Enum.TextXAlignment.Left,
                Text = "  " .. r.name,
                Parent = list_host,
            })
            gui.corner(b, 5)
            b.MouseButton1Click:Connect(function()
                select(r)
                for _, other in ipairs(list_host:GetChildren()) do
                    if other:IsA("TextButton") then
                        other.BackgroundColor3 = T.panel
                    end
                end
                b.BackgroundColor3 = T.accent
            end)
        end
        if shown == 0 then
            local b = gui.new("TextButton", {
                Size = UDim2.new(1, 0, 0, 24),
                BackgroundColor3 = T.panel,
                Text = "  no match",
                Font = Enum.Font.Code,
                TextSize = 11,
                TextColor3 = T.muted,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = list_host,
            })
            gui.corner(b, 5)
        end
    end

    gui.button(rem, {
        text = "Scan / apply filter",
        callback = function()
            SD.refresh(true)
            populate()
            SD.notify(("%d remotes indexed"):format(#SD.cache.remotes), "ok")
        end,
    })

    local args_box = gui.textbox(rem, {
        text = "args",
        default = "",
        placeholder = "e.g. 1000  or  1,true",
    })

    gui.button(rem, {
        text = "Fire selected",
        callback = function()
            if not E.selected then SD.notify("select a remote first", "warn") return end
            local args = E.parse_args(args_box.get())
            local ok, res = SD.probe_remote(E.selected, args)
            SD.notify(("fired %s -> %s"):format(E.selected.name, tostring(ok)), ok and "ok" or "err")
            if ok and res ~= nil then SD.log("result: " .. tostring(res)) end
        end,
    })

    gui.button(rem, {
        text = "Fuzz selected (13 payloads)",
        color = T.panel2,
        callback = function()
            if not E.selected then SD.notify("select a remote first", "warn") return end
            local results = E.fuzz(E.selected)
            local gains = 0
            for _, r in ipairs(results) do
                if r.gain > 0 then gains = gains + 1 end
            end
            SD.notify(("fuzz done, %d paying payloads"):format(gains), gains > 0 and "ok" or "warn")
        end,
    })

    gui.button(rem, {
        text = "Cash-probe selected",
        color = T.accent,
        callback = function()
            if not E.selected then SD.notify("select a remote first", "warn") return end
            local gained, amount, err = E.cash_probe(E.selected, E.parse_args(args_box.get()))
            if gained then
                SD.notify(("PAYS OUT: +%s"):format(SD.fmt(amount)), "ok")
            elseif err then
                SD.notify("error: " .. err, "err")
            else
                SD.notify("no cash change", "warn")
            end
        end,
    })

    -- primitives
    local prim = gui.section(parent, "Client-side primitives")
    gui.label(prim, "Prompt and click config is server-replicated; hold time is not.", 16, T.muted).TextSize = 11

    gui.button(prim, {
        text = "Prompt spoof (hold=0, infinite reach)",
        callback = function()
            local n = E.prompt_spoof()
            SD.notify(("%d prompts patched"):format(n), n > 0 and "ok" or "warn")
        end,
    })

    gui.button(prim, {
        text = "Click detector reach",
        callback = function()
            local n = E.click_spoof()
            SD.notify(("%d detectors patched"):format(n), n > 0 and "ok" or "warn")
        end,
    })

    gui.toggle(prim, {
        text = "Noclip",
        default = false,
        callback = function(v)
            E.noclip(v)
            if v then
                SD.add_task("noclip", 0.2, function()
                    if not E._noclip then return end
                    local ch = SD.get_char()
                    if not ch then return end
                    for _, p in ipairs(ch:GetDescendants()) do
                        if p:IsA("BasePart") then pcall(function() p.CanCollide = false end) end
                    end
                end)
            end
        end,
    })

    gui.button(prim, {
        text = "God (client Health only)",
        callback = function()
            E.god()
            SD.notify("health patched client-side", "warn")
        end,
    })

    -- values
    local vals = gui.section(parent, "Client values")
    gui.label(vals, "If the server reads any of these back, writing them is the dupe.", 16, T.muted).TextSize = 11

    gui.button(vals, {
        text = "List writable values to console",
        callback = function()
            local list = E.client_values()
            SD.log(("--- %d client values ---"):format(#list))
            for _, v in ipairs(list) do
                SD.log(("  %s = %s"):format(v.path, tostring(v.value)))
            end
            SD.notify(("%d values logged"):format(#list), "ok")
        end,
    })

    local val_name = gui.textbox(vals, { text = "match", default = "", placeholder = "Cash" })
    local val_val = gui.textbox(vals, { text = "value", default = "", placeholder = "1000000" })

    gui.button(vals, {
        text = "Write matching values",
        callback = function()
            local v = tonumber(val_val.get())
            if not v then SD.notify("value must be a number", "warn") return end
            local n = E.write_value(val_name.get(), v)
            SD.notify(("%d values written"):format(n), n > 0 and "ok" or "warn")
        end,
    })

    -- session
    local sess = gui.section(parent, "Session")
    gui.button(sess, {
        text = "Server hop",
        callback = function() SD.features.server_hop() end,
    })
    gui.button(sess, {
        text = "Rejoin same server",
        callback = function() SD.features.rejoin() end,
    })
    gui.button(sess, {
        text = "Show discovered hits",
        callback = function()
            if #E.hits == 0 then SD.notify("no hits yet", "warn") return end
            for _, h in ipairs(E.hits) do
                SD.log(("[hit] %s  args=%s  +%s"):format(h.path, h.args, SD.fmt(h.gain)))
            end
            SD.notify(("%d hits in console"):format(#E.hits), "ok")
        end,
    })

    task.defer(function()
        SD.refresh(true)
        populate()
    end)

    return populate
end

SD.log("exploits loaded")

--[[
    file: 50_boot.lua
    Assembles the tabs, wires config <-> GUI, starts the scheduler.
]]

local SD = getgenv().SD
local gui = SD.gui
local T = gui.theme

SD.load_config()

gui.build()
local win = gui.window

-- silent persist, debounced ------------------------------------------------

local save_pending = false
local function persist()
    if not (SD.caps.writefile and SD.caps.makefolder) then return end
    pcall(function() makefolder("SellDirt") end)
    local ok, json = pcall(function() return SD.HttpService:JSONEncode(SD.config) end)
    if ok then pcall(function() writefile(SD.CONFIG_FILE, json) end) end
end

local function mark_dirty()
    if save_pending then return end
    save_pending = true
    task.delay(2, function()
        save_pending = false
        persist()
    end)
end

local function bind(key)
    return function(v)
        SD.config[key] = v
        mark_dirty()
    end
end

-- GRIND --------------------------------------------------------------------

local grind = gui.tab("Grind")

local auto = gui.section(grind, "Automation")

gui.toggle(auto, {
    text = "Auto sell",
    default = SD.config.auto_sell,
    callback = bind("auto_sell"),
})

gui.slider(auto, {
    text = "Sell interval",
    min = 0.5, max = 12, decimals = 1, suffix = "s",
    default = SD.config.auto_sell_delay,
    callback = bind("auto_sell_delay"),
})

gui.toggle(auto, {
    text = "Return to dig spot after selling",
    default = SD.config.sell_return,
    callback = bind("sell_return"),
})

gui.toggle(auto, {
    text = "Auto dig",
    default = SD.config.auto_dig,
    callback = bind("auto_dig"),
})

gui.slider(auto, {
    text = "Dig interval",
    min = 0.05, max = 2, decimals = 2, suffix = "s",
    default = SD.config.auto_dig_delay,
    callback = bind("auto_dig_delay"),
})

gui.dropdown(auto, {
    text = "Dig method",
    options = { "both", "tool", "click" },
    default = SD.config.dig_mode,
    callback = bind("dig_mode"),
})

gui.toggle(auto, {
    text = "Auto collect (fire nearby prompts)",
    default = SD.config.auto_collect,
    callback = bind("auto_collect"),
})

gui.toggle(auto, {
    text = "Auto upgrade",
    default = SD.config.auto_upgrade,
    callback = bind("auto_upgrade"),
})

gui.toggle(auto, {
    text = "Auto rebirth / prestige",
    default = SD.config.auto_rebirth,
    callback = bind("auto_rebirth"),
})

local targets = gui.section(grind, "Target overrides")
gui.label(targets, "Leave blank to use name heuristics.", 16, T.muted).TextSize = 11

gui.textbox(targets, {
    text = "sell object",
    default = SD.config.sell_name,
    placeholder = "SellZone",
    callback = bind("sell_name"),
})

gui.textbox(targets, {
    text = "crown object",
    default = SD.config.crown_name,
    placeholder = "Crown",
    callback = bind("crown_name"),
})

gui.textbox(targets, {
    text = "dig tool",
    default = SD.config.dig_tool_name,
    placeholder = "Shovel",
    callback = bind("dig_tool_name"),
})

gui.textbox(targets, {
    text = "sell remote",
    default = SD.config.sell_remote,
    placeholder = "SellDirt",
    callback = bind("sell_remote"),
})

gui.button(targets, {
    text = "Dump recon to console",
    callback = function() SD.dump() end,
})

-- MOVEMENT -----------------------------------------------------------------

local move = gui.tab("Move")

local tps = gui.section(move, "Teleports")

gui.toggle(tps, {
    text = "Auto TP to crown",
    default = SD.config.tp_crown,
    callback = bind("tp_crown"),
})

gui.slider(tps, {
    text = "Crown interval",
    min = 0.5, max = 15, decimals = 1, suffix = "s",
    default = SD.config.tp_crown_delay,
    callback = bind("tp_crown_delay"),
})

gui.button(tps, {
    text = "TP to crown now",
    callback = function()
        if SD.features.goto_crown() then
            SD.notify("moved to crown", "ok")
        else
            SD.notify("crown not found - set the name in Grind", "warn")
        end
    end,
})

gui.button(tps, {
    text = "TP to sell zone",
    callback = function()
        if SD.features.goto_sell() then
            SD.notify("moved to sell zone", "ok")
        else
            SD.notify("sell zone not found - set the name in Grind", "warn")
        end
    end,
})

gui.button(tps, {
    text = "TP to nearest dirt",
    callback = function()
        if SD.features.goto_dirt() then
            SD.notify("moved to dirt", "ok")
        else
            SD.notify("no dirt found", "warn")
        end
    end,
})

gui.button(tps, {
    text = "Set anchor here",
    callback = function()
        local hrp = SD.get_hrp()
        if hrp then
            SD.state.anchor = hrp.CFrame
            SD.notify("anchor set", "ok")
        end
    end,
})

gui.button(tps, {
    text = "Return to anchor",
    callback = function()
        if SD.state.anchor then
            SD.features.return_home()
            SD.notify("returned", "ok")
        else
            SD.notify("no anchor set", "warn")
        end
    end,
})

local speed = gui.section(move, "Speed")

gui.slider(speed, {
    text = "WalkSpeed",
    min = 16, max = 500, decimals = 0,
    default = SD.config.walkspeed,
    callback = function(v)
        SD.config.walkspeed = v
        if SD.config.walkspeed_lock then SD.set_walkspeed(v) end
        mark_dirty()
    end,
})

gui.toggle(speed, {
    text = "Lock WalkSpeed",
    default = SD.config.walkspeed_lock,
    callback = function(v)
        SD.config.walkspeed_lock = v
        if v then SD.set_walkspeed(SD.config.walkspeed) end
        mark_dirty()
    end,
})

gui.slider(speed, {
    text = "JumpPower",
    min = 50, max = 500, decimals = 0,
    default = SD.config.jumppower,
    callback = function(v)
        SD.config.jumppower = v
        if SD.config.jumppower_lock then SD.set_jumppower(v) end
        mark_dirty()
    end,
})

gui.toggle(speed, {
    text = "Lock JumpPower",
    default = SD.config.jumppower_lock,
    callback = function(v)
        SD.config.jumppower_lock = v
        if v then SD.set_jumppower(SD.config.jumppower) end
        mark_dirty()
    end,
})

-- VISUALS ------------------------------------------------------------------

local vis = gui.tab("Visual")
local esp = gui.section(vis, "ESP")

gui.toggle(esp, {
    text = "Highlight crown",
    default = SD.config.esp_crown,
    callback = bind("esp_crown"),
})

gui.toggle(esp, {
    text = "Highlight sell zone",
    default = SD.config.esp_sell,
    callback = bind("esp_sell"),
})

gui.toggle(esp, {
    text = "Highlight dirt",
    default = SD.config.esp_dirt,
    callback = bind("esp_dirt"),
})

gui.toggle(esp, {
    text = "Highlight players",
    default = SD.config.esp_players,
    callback = bind("esp_players"),
})

local render = gui.section(vis, "Render")

gui.toggle(render, {
    text = "Fullbright",
    default = SD.config.fullbright,
    callback = function(v)
        SD.config.fullbright = v
        if v then SD.features.fullbright_apply() else SD.features.fullbright_restore() end
        mark_dirty()
    end,
})

gui.toggle(render, {
    text = "FPS boost (kill post FX)",
    default = SD.config.fps_boost,
    callback = function(v)
        SD.config.fps_boost = v
        if v then SD.features.fps_boost_apply() else SD.features.fps_boost_restore() end
        mark_dirty()
    end,
})

-- EXPLOITS -----------------------------------------------------------------

local exp = gui.tab("Exploit")
local populate_remotes = SD.exploits.build_gui(exp, gui)

-- CONFIG -------------------------------------------------------------------

local cfg = gui.tab("Config")

local misc = gui.section(cfg, "Session")

gui.toggle(misc, {
    text = "Anti-AFK",
    default = SD.config.anti_afk,
    callback = bind("anti_afk"),
})

gui.toggle(misc, {
    text = "Auto rejoin on disconnect",
    default = SD.config.auto_rejoin,
    callback = bind("auto_rejoin"),
})

gui.toggle(misc, {
    text = "Pause all automation",
    default = false,
    callback = function(v)
        SD.state.paused = v
        SD.notify(v and "automation paused" or "automation resumed", v and "warn" or "ok")
    end,
})

local info = gui.label(misc, "uptime 0s", 16, T.muted)
info.TextSize = 11

local store = gui.section(cfg, "Config file")

gui.button(store, {
    text = "Save config",
    callback = function()
        SD.save_config()
    end,
})

gui.button(store, {
    text = "Reload config",
    callback = function()
        if SD.load_config() then
            SD.notify("config loaded - reopen the UI to see values", "ok")
        else
            SD.notify("no config file", "warn")
        end
    end,
})

gui.button(store, {
    text = "Unload script",
    color = Color3.fromRGB(60, 26, 34),
    text_color = T.danger,
    callback = function()
        SD.unload()
    end,
})

-- runtime ------------------------------------------------------------------

SD.features.register_tasks()

SD.add_task("uptime", 1.0, function()
    local up = os.time() - SD.state.session_start
    info.Text = ("uptime %s   session +%s"):format(
        SD.clock_str(up), SD.fmt(SD.state.session_earned)
    )
end)

local heartbeat = SD.RunService.Heartbeat:Connect(SD.run_tasks)

function SD.unload()
    if heartbeat then heartbeat:Disconnect() end
    SD.features.fullbright_restore()
    SD.features.fps_boost_restore()
    SD.exploits.noclip(false)
    for _, bucket in pairs(SD.features.esp_store) do
        for _, h in pairs(bucket) do
            if h then pcall(function() h:Destroy() end) end
        end
    end
    if SD.gui.root then SD.gui.root:Destroy() end
    getgenv().SD = nil
    print("[SD] unloaded")
end

SD.features.bind_character()
task.spawn(function() SD.refresh(true) end)

SD.notify("loaded - " .. SD.game_name, "ok")
SD.log("booted. F9 for console, click 'Dump recon' to see the map of the game.")

