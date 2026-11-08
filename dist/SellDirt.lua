--[[
    Sell Dirt — v3 core
    Luau client script (Delta Executor Android). Shared services, config, scheduler, helpers.
]]

local SD = {}
getgenv().SD = SD

SD.version = "3.1.0"
SD.game_name = "Sell Dirt"

local function svc(name)
	local ok, s = pcall(game.GetService, game, name)
	return ok and s or nil
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
SD.VirtualUser       = svc("VirtualUser")
SD.Workspace         = workspace
SD.plr               = SD.Players and SD.Players.LocalPlayer or nil
SD.t0                = os.clock()

SD.caps = {
	writefile      = type(writefile) == "function",
	readfile       = type(readfile) == "function",
	isfile         = type(isfile) == "function",
	makefolder     = type(makefolder) == "function",
	fireprompt     = type(fireproximityprompt) == "function",
	fireclick      = type(fireclickdetector) == "function",
	queue_teleport = type(queue_on_teleport) == "function",
}

local PREFIX = "[SD] "
function SD.log(...) local p={}; for i=1,select("#",...) do p[#p+1]=tostring(select(i,...)) end; print(PREFIX..table.concat(p," ")) end
function SD.warn(...) local p={}; for i=1,select("#",...) do p[#p+1]=tostring(select(i,...)) end; warn(PREFIX..table.concat(p," ")) end

SD._notify_queue = {}
function SD.notify(text, kind)
	local gui = SD.gui
	if gui and gui.ready then gui.notify(text, kind) else table.insert(SD._notify_queue, { text=text, kind=kind }) end
end

function SD.safe(fn, ...) local ok, res = pcall(fn, ...); if ok then return res end; return nil, res end
function SD.fmt(n)
	n = tonumber(n) or 0; local a = math.abs(n)
	if a >= 1e12 then return string.format("%.2fT", n/1e12) end
	if a >= 1e9  then return string.format("%.2fB", n/1e9) end
	if a >= 1e6  then return string.format("%.2fM", n/1e6) end
	if a >= 1e4  then return string.format("%.1fK", n/1e3) end
	return tostring(math.floor(n + 0.5))
end
function SD.clock_str(sec)
	sec = math.max(0, math.floor(sec or 0))
	local h = math.floor(sec/3600); local m = math.floor((sec%3600)/60); local s = sec%60
	if h > 0 then return string.format("%dh %02dm", h, m) end
	if m > 0 then return string.format("%dm %02ds", m, s) end
	return string.format("%ds", s)
end

function SD.get_char() return LP and LP.Character or (SD.plr and SD.plr.Character) end
local LP = SD.plr
function SD.get_char() return SD.plr and SD.plr.Character end
function SD.get_hrp() local ch=SD.get_char(); return ch and ch:FindFirstChild("HumanoidRootPart") end
function SD.get_hum() local ch=SD.get_char(); return ch and ch:FindFirstChildOfClass("Humanoid") end
function SD.alive() local h=SD.get_hum(); return h and h.Health > 0 end

function SD.tp(target)
	local hrp = SD.get_hrp(); if not hrp then return false end
	local cf
	if typeof(target) == "CFrame" then cf = target
	elseif typeof(target) == "Vector3" then cf = CFrame.new(target)
	elseif typeof(target) == "Instance" then
		if target:IsA("BasePart") then cf = target.CFrame
		elseif target:IsA("Model") and target.PrimaryPart then cf = target.PrimaryPart.CFrame
		else local p = target:FindFirstChildWhichIsA("BasePart", true); if not p then return false end; cf = p.CFrame end
	else return false end
	local ok = pcall(function() hrp.CFrame = cf end)
	if not ok then local ch=SD.get_char(); if ch then pcall(function() ch:PivotTo(cf) end) end end
	pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end)
	return true
end

local STAT_CONTAINERS = { "leaderstats", "Stats", "Data", "Values", "PlayerStats", "save" }
function SD.leaderstats()
	local out = {}; local plr = SD.plr; if not plr then return out end
	for _, cname in ipairs(STAT_CONTAINERS) do
		local c = plr:FindFirstChild(cname)
		if c then for _, v in ipairs(c:GetChildren()) do if v:IsA("ValueBase") then out[v.Name] = v.Value end end end
	end
	return out
end
function SD.cash()
	local best, bestv = nil, -math.huge
	for name, v in pairs(SD.leaderstats()) do
		if type(v) == "number" and v > bestv then
			local ln = string.lower(name)
			if has and has(ln, "cash") then best,bestv=name,v
			elseif string.find(ln,"cash",1,true) or string.find(ln,"money",1,true) or string.find(ln,"coin",1,true) or string.find(ln,"dirt",1,true) or string.find(ln,"dollar",1,true) then
				best,bestv=name,v end
		end
	end
	if best then return bestv, best end
	return nil, nil
end

SD.tasks = {}
function SD.add_task(name, interval, fn) SD.tasks[name] = { interval=interval, fn=fn, last=0 } end
function SD.run_tasks()
	local t = os.clock()
	for name, task in pairs(SD.tasks) do
		if t - task.last >= task.interval then
			task.last = t
			local ok, err = pcall(task.fn)
			if not ok then SD.warn("task " .. name .. ": " .. tostring(err)) end
		end
	end
end

SD.CONFIG_FILE = "SellDirt/config.json"
SD.config = {
	-- modules (all OFF by default)
	auto_sell=false, auto_collect=false, auto_dig=false, auto_crown=false,
	auto_upgrade=false, auto_rebirth=false,
	anti_afk=false, auto_rejoin=false,
	speed_lock=false, jump_lock=false, noclip=false,
	esp_crown=false, esp_players=false, fullbright=false, fps_boost=false,
	-- tuning
	walkspeed=24, jumppower=50,
	sell_delay=1.2, dig_delay=0.25, collect_delay=1.0, crown_delay=0.75,
	only_my_plot=true,
	-- overrides
	sell_remote="", sell_object="", crown_object="", dig_tool="",
}
SD.state = { session_start=os.time(), session_earned=0, last_cash=nil, paused=false, rejoin_guard=false }

local FORCE_OFF = { "auto_sell","auto_collect","auto_dig","auto_crown","auto_upgrade","auto_rebirth","anti_afk","auto_rejoin","speed_lock","jump_lock","noclip","esp_crown","esp_players","fullbright","fps_boost","tp_crown","walkspeed_lock","jumppower_lock","auto_sell_teleport","queue_on_teleport" }

function SD.save_config()
	if not (SD.caps.writefile and SD.caps.makefolder) then SD.notify("config save unavailable in this executor", "warn"); return false end
	pcall(function() makefolder("SellDirt") end)
	local ok, json = pcall(function() return SD.HttpService:JSONEncode(SD.config) end)
	if not ok then return false end
	local w = pcall(function() writefile(SD.CONFIG_FILE, json) end)
	if w then SD.notify("Config saved", "ok") end
	return w
end

function SD.load_config()
	if not (SD.caps.readfile and SD.caps.isfile and isfile(SD.CONFIG_FILE)) then return false end
	local ok, raw = pcall(readfile, SD.CONFIG_FILE)
	if not ok or not raw then return false end
	local ok2, data = pcall(function() return SD.HttpService:JSONDecode(raw) end)
	if not ok2 or type(data) ~= "table" then return false end
	for k, v in pairs(data) do if SD.config[k] ~= nil then SD.config[k] = v end end
	-- map old keys to new where helpful
	if data.tp_crown ~= nil then SD.config.auto_crown = data.tp_crown end
	if data.auto_sell_delay ~= nil then SD.config.sell_delay = data.auto_sell_delay end
	if data.auto_dig_delay ~= nil then SD.config.dig_delay = data.auto_dig_delay end
	if data.tp_crown_delay ~= nil then SD.config.crown_delay = data.tp_crown_delay end
	if data.walkspeed_lock ~= nil then SD.config.speed_lock = data.walkspeed_lock end
	if data.jumppower_lock ~= nil then SD.config.jump_lock = data.jumppower_lock end
	if data.sell_name ~= nil and SD.config.sell_object == "" then SD.config.sell_object = data.sell_name end
	if data.crown_name ~= nil and SD.config.crown_object == "" then SD.config.crown_object = data.crown_name end
	if data.dig_tool_name ~= nil and SD.config.dig_tool == "" then SD.config.dig_tool = data.dig_tool_name end
	for _, k in ipairs(FORCE_OFF) do SD.config[k] = false end -- always start with modules OFF
	return true
end

SD.log("core v" .. SD.version .. " loaded")

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

	local function risky_interaction(inst)
		-- basic safety even before features hook: block obvious monetization/autosell gamepass prompts
		if SD.is_risky and SD.is_risky(inst) then return true end
		if not inst or not inst.Parent then return false end
		local bits = {}
		local function add(s) if type(s)=="string" and s~="" then bits[#bits+1]=string.lower(s) end end
		add(inst.Name)
		pcall(function() add(inst:GetFullName()) end)
		if inst:IsA("ProximityPrompt") then
			pcall(function() add(inst.ActionText) end)
			pcall(function() add(inst.ObjectText) end)
		end
		for _, b in ipairs(bits) do
			if string.find(b, "robux", 1, true) or string.find(b, "gamepass", 1, true) or string.find(b, "game pass", 1, true) or string.find(b, "devproduct", 1, true) then return true end
			if string.find(b, "autosell", 1, true) or string.find(b, "auto sell", 1, true) or string.find(b, "auto-sell", 1, true) then return true end
			if string.find(b, "donate", 1, true) or string.find(b, "premium", 1, true) then return true end
		end
		return false
	end

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
	            if not risky_interaction(d) and SD.caps.fireprompt then
	                pcall(fireproximityprompt, d)
	                fired = fired + 1
	            end
	        elseif d:IsA("ClickDetector") then
	            if not risky_interaction(d) and SD.caps.fireclick then
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
	            if not risky_interaction(p) and SD.caps.fireprompt then
	                pcall(fireproximityprompt, p)
	                fired = fired + 1
	            end
	        end
	    end
	    for _, c in ipairs(SD.cache.clicks) do
	        local part = SD.resolve_part(c)
	        if part and dist_to(part, pos) <= (radius or 12) then
	            if not risky_interaction(c) and SD.caps.fireclick then
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

    -- floating opener (always visible: toggles show/hide)
	    local opener = new("TextButton", {
	        AnchorPoint = Vector2.new(1, 0),
	        Position = UDim2.new(1, -14, 0, 44),
	        Size = UDim2.new(0, 52, 0, 46),
	        BackgroundColor3 = T.accent,
	        AutoButtonColor = false,
	        Font = FONT_BOLD,
	        TextSize = 12,
	        TextColor3 = Color3.fromRGB(255, 255, 255),
	        Text = "SD",
	        Parent = sg,
	    })
	    corner(opener, 14)
	    stroke(opener, Color3.fromRGB(160, 138, 255), 1)
	    gui.opener = opener

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

    -- open / close (opener stays visible and toggles)
	    local function set_open(open)
	        win.Visible = open and true or false
	        opener.Visible = true
	        opener.Text = win.Visible and "Hide" or "SD"
	        opener.BackgroundColor3 = win.Visible and T.panel2 or T.accent
	        opener.TextColor3 = win.Visible and T.text or Color3.fromRGB(255, 255, 255)
	    end
	    opener.MouseButton1Click:Connect(function() set_open(not win.Visible) end)
	    close.MouseButton1Click:Connect(function() set_open(false) end)
	    gui.set_open = set_open

    -- drag (track the active input to avoid touch/mouse conflicts)
	    local dragInput, dragStart, startPos = nil, nil, nil
	    local function beginDrag(input)
	        if input.UserInputType ~= Enum.UserInputType.MouseButton1
	            and input.UserInputType ~= Enum.UserInputType.Touch then return end
	        -- don't drag when pressing the close button area
	        local pos = input.Position
	        local ap = close.AbsolutePosition
	        local asz = close.AbsoluteSize
	        if pos.X >= ap.X - 4 and pos.X <= ap.X + asz.X + 4
	            and pos.Y >= ap.Y - 4 and pos.Y <= ap.Y + asz.Y + 4 then
	            return
	        end
	        dragInput = input
	        dragStart = input.Position
	        startPos = win.Position
	    end
	    bar.InputBegan:Connect(beginDrag)
	    close.InputBegan:Connect(function() dragInput = nil end)

	    UIS.InputChanged:Connect(function(input)
	        if input ~= dragInput then return end
	        if input.UserInputType ~= Enum.UserInputType.MouseMovement
	            and input.UserInputType ~= Enum.UserInputType.Touch then return end
	        if not (dragStart and startPos) then return end
	        local d = input.Position - dragStart
	        win.Position = UDim2.new(
	            startPos.X.Scale, startPos.X.Offset + d.X,
	            startPos.Y.Scale, startPos.Y.Offset + d.Y
	        )
	    end)
	    UIS.InputEnded:Connect(function(input)
	        if input ~= dragInput then return end
	        dragInput = nil
	        local v = viewport()
	        local half = win.AbsoluteSize
	        local x = win.AbsolutePosition.X
	        local y = win.AbsolutePosition.Y
	        local margin = 8
	        local nx = math.clamp(x, margin - half.X + 60, v.X - 60 - margin)
	        local ny = math.clamp(y, margin, math.max(margin, v.Y - 44 - margin))
	        win.Position = UDim2.fromOffset(nx, ny)
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
    Sell Dirt automation features (v3 rework)
    Goals: no robux/gamepass actions, no cross-plot actions, no false crown TPs,
    simple on/off modules, and distance-independent sell/collect where possible.
]]

local SD = getgenv().SD
local F = {}
SD.features = F

-- defaults (safe by default; modules off)
local function dflt(k, v) if SD.config[k] == nil then SD.config[k] = v end end
dflt("auto_sell", false)
dflt("auto_collect", false)
dflt("auto_dig", false)
dflt("auto_crown", false)
dflt("auto_upgrade", false)
dflt("auto_rebirth", false)
dflt("anti_afk", false)
dflt("auto_rejoin", false)
dflt("speed_lock", false)
dflt("jump_lock", false)
dflt("noclip", false)
dflt("esp_crown", false)
dflt("esp_players", false)
dflt("fullbright", false)
dflt("fps_boost", false)
dflt("walkspeed", 24)
dflt("jumppower", 50)
dflt("sell_delay", 1.2)
dflt("dig_delay", 0.25)
dflt("collect_delay", 1.0)
dflt("crown_delay", 0.75)
dflt("only_my_plot", true)
dflt("sell_remote", "")
dflt("sell_object", "")
dflt("crown_object", "")
dflt("dig_tool", "")

F.status = { sell = "off", collect = "off", dig = "off", crown = "off", plot = "?" }
F._plot, F._plotAt = nil, 0
F._crown, F._crownAt = nil, 0
F.esp = { crown = {}, players = {} }

local P = SD.Players
local LP = SD.plr

local function now() return os.clock() end
local function lower(s) return string.lower(tostring(s or "")) end
local function has(s, pat) return string.find(lower(s), lower(pat), 1, true) ~= nil end
local function hasAny(s, pats)
	s = lower(s)
	for _, p in ipairs(pats) do if string.find(s, lower(p), 1, true) then return true end end
	return false
end

-- safety --------------------------------------------------------------------
local RISKY = { "robux", "gamepass", "game pass", "devproduct", "developer product", "donate", "donation", "premium", "vip pass", "autosell", "auto sell", "auto-sell", "promptpurchase", "marketplace" }
function F.is_risky(inst)
	if not inst then return false end
	local bits = {}
	local function add(v) if type(v) == "string" and v ~= "" then bits[#bits+1] = lower(v) end end
	if typeof(inst) == "Instance" then
		add(inst.Name)
		pcall(function() add(inst:GetFullName()) end)
		if inst:IsA("ProximityPrompt") then
			pcall(function() add(inst.ActionText) end)
			pcall(function() add(inst.ObjectText) end)
		end
		local par = inst.Parent
		if par then
			add(par.Name)
			for _, d in ipairs(par:GetDescendants()) do
				if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
					pcall(function() add(d.Text) end)
				end
				if #bits > 20 then break end
			end
		end
	elseif type(inst) == "table" then
		add(inst.name); add(inst.path)
	end
	for _, t in ipairs(bits) do
		for _, b in ipairs(RISKY) do if has(t, b) then return true end end
		-- block "buy" unless clearly sell-related
		if has(t, "buy") and not has(t, "sell") then return true end
	end
	return false
end
SD.is_risky = F.is_risky

-- plot ownership ------------------------------------------------------------
local function owner_matches(obj)
	if not obj or not obj.Parent or not LP then return false end
	local name, uid = LP.Name, LP.UserId
	local okA, attrs = pcall(function() return obj:GetAttributes() end)
	if okA and type(attrs) == "table" then
		for k, v in pairs(attrs) do
			local lk = lower(k)
			if has(lk, "owner") or has(lk, "user") then
				if v == LP or v == name or v == uid or tostring(v) == name or tostring(v) == tostring(uid) then return true end
				if typeof and typeof(v) == "Instance" and v == LP then return true end
			end
		end
	end
	for _, key in ipairs({ "Owner", "owner", "Player", "player", "UserId", "OwnerId", "PlotOwner" }) do
		local ch = obj:FindFirstChild(key)
		if ch then
			local ok, val = pcall(function() return ch.Value end)
			if ok and (val == LP or val == name or val == uid or tostring(val) == name or tostring(val) == tostring(uid)) then return true end
		end
	end
	return false
end

function F.my_plot()
	if F._plot and F._plot.Parent and (now() - F._plotAt) < 10 then return F._plot end
	F._plot = nil
	if not LP then return nil end
	local roots = {}
	for _, name in ipairs({ "Plots", "Tycoons", "Bases", "Islands", "Farms", "PlayerPlots", "plots", "tycoons" }) do
		local r = workspace:FindFirstChild(name)
		if r then roots[#roots+1] = r end
	end
	if #roots == 0 then
		for _, c in ipairs(workspace:GetChildren()) do
			local n = lower(c.Name)
			if has(n, "plot") or has(n, "tycoon") or has(n, "base") then roots[#roots+1] = c end
		end
	end
	for _, root in ipairs(roots) do
		local by = root:FindFirstChild(LP.Name)
		if by then F._plot = by; break end
		for _, plot in ipairs(root:GetChildren()) do
			if owner_matches(plot) then F._plot = plot; break end
		end
		if F._plot then break end
	end
	if F._plot then F._plotAt = now(); F.status.plot = F._plot.Name else F.status.plot = "auto" end
	return F._plot
end

function F.is_mine(inst)
	if not SD.config.only_my_plot then return true end
	local plot = F.my_plot()
	if not plot then return true end
	local obj = inst
	if typeof(inst) == "Instance" then
		if inst:IsA("ProximityPrompt") or inst:IsA("ClickDetector") then obj = inst.Parent end
	end
	if not obj then return true end
	local ok, desc = pcall(function() return obj:IsDescendantOf(plot) end)
	if ok and desc then return true end
	pcall(function() if has(obj:GetFullName(), LP.Name) then desc = true end end)
	if desc == true then return true end
	local cur = obj
	for _ = 1, 6 do
		if not cur or cur == workspace then break end
		if owner_matches(cur) then return true end
		cur = cur.Parent
	end
	return false
end

-- crown ---------------------------------------------------------------------
local function crown_excluded(inst)
	local ok, path = pcall(function() return inst:GetFullName() end)
	local p = ok and lower(path) or ""
	for _, b in ipairs({ "feedback","report","suggest","complaint","donate","shop","setting","menu","gui","screen","interface","statue","decoration","spawnlocation","npc" }) do
		if has(p, b) then return true end
	end
	if P then
		for _, plr in ipairs(P:GetPlayers()) do
			local ch = plr.Character
			if ch then
				local okD, isD = pcall(function() return inst:IsDescendantOf(ch) end)
				if okD and isD then return true end
			end
		end
	end
	return false
end

local function crown_active(inst)
	if not inst or not inst.Parent then return false end
	local okW, inW = pcall(function() return inst:IsDescendantOf(workspace) end)
	if not okW or not inW then return false end
	if crown_excluded(inst) then return false end
	local function vis(part)
		if not part or not part:IsA("BasePart") then return false end
		if part.Transparency >= 0.995 then return false end
		local okS, sz = pcall(function() return part.Size end)
		if okS and sz and sz.Magnitude < 0.05 then return false end
		return true
	end
	if inst:IsA("BasePart") then return vis(inst) end
	if inst:IsA("Model") or inst:IsA("Tool") or inst:IsA("Accessory") then
		for _, d in ipairs(inst:GetDescendants()) do if d:IsA("BasePart") and vis(d) then return true end end
	end
	local rp = SD.resolve_part(inst)
	return vis(rp)
end

local function strong_crown(inst)
	local n = lower(inst and inst.Name or "")
	if n == "crown" or n == "thecrown" or n == "eventcrown" or n == "crownpickup" or n == "kingcrown" then return true end
	if has(n, "crown") and #n <= 24 and not has(n, "feedback") and not has(n, "report") then return true end
	return false
end

function F.find_crown()
	if F._crown and F._crown.Parent and (now() - F._crownAt) < 1.0 and crown_active(F._crown) then return F._crown end
	F._crown = nil
	local custom = SD.config.crown_object
	if custom and custom ~= "" then
		for _, inst in ipairs(SD.find_parts({ custom })) do if crown_active(inst) then F._crown = inst; F._crownAt = now(); return inst end end
		for _, inst in ipairs(SD.find_models({ custom })) do if crown_active(inst) then F._crown = inst; F._crownAt = now(); return inst end end
		return nil
	end
	SD.refresh()
	for _, m in ipairs(SD.cache.models or {}) do if strong_crown(m) and crown_active(m) then F._crown = m; F._crownAt = now(); return m end end
	for _, p in ipairs(SD.cache.parts or {}) do if strong_crown(p) and crown_active(p) then F._crown = p; F._crownAt = now(); return p end end
	for _, d in ipairs(workspace:GetDescendants()) do
		if strong_crown(d) and crown_active(d) then F._crown = d; F._crownAt = now(); return d end
	end
	return nil
end

function F.goto_crown()
	local c = F.find_crown()
	if not c then F.status.crown = "waiting for crown event"; return false end
	local ok = SD.tp(c)
	F.status.crown = ok and "holding crown" or "tp failed"
	return ok
end

-- selling -------------------------------------------------------------------
local SELL_NAMES = { "sell", "cashout", "cash out", "exchange", "deposit", "turn in", "turnin", "selldirt", "sell_dirt" }
local function is_sell_prompt(p)
	if not p or not p.Parent or F.is_risky(p) then return false end
	local txt = lower((p.Name or "") .. " " .. (p.ActionText or "") .. " " .. (p.ObjectText or "") .. " " .. (p.Parent.Name or ""))
	if not hasAny(txt, { "sell","cashout","cash out","exchange","deposit","turn in","turnin" }) then return false end
	if hasAny(txt, { "autosell","auto sell","auto-sell","gamepass","robux","pass","toggle" }) then return false end
	return true
end

local function safe_remote(r)
	if not r or F.is_risky(r) then return false end
	local n = lower((r.name or "") .. " " .. (r.path or ""))
	if hasAny(n, { "autosell","auto sell","auto_sell","toggle","buy","purchase","robux","gamepass","devproduct","marketplace","promptpurchase" }) then return false end
	return true
end

function F.sell_once()
	-- explicit override
	local ovr = SD.config.sell_remote
	if ovr and ovr ~= "" then
		for _, r in ipairs(SD.remotes_matching({ ovr })) do
			if safe_remote(r) and SD.probe_remote(r, {}) then F.status.sell = "remote OK"; return true end
		end
	end

	-- prompts on my plot from anywhere
	if SD.caps.fireprompt then
		SD.refresh()
		local fired = 0
		for _, p in ipairs(SD.cache.prompts or {}) do
			if F.is_mine(p) and is_sell_prompt(p) then
				if pcall(fireproximityprompt, p) then fired = fired + 1 end
			end
		end
		if fired == 0 then
			for _, p in ipairs(SD.prompts_matching(SELL_NAMES) or {}) do
				if F.is_mine(p) and is_sell_prompt(p) then
					if pcall(fireproximityprompt, p) then fired = fired + 1 end
				end
			end
		end
		if fired > 0 then F.status.sell = "sold (" .. fired .. " prompt)"; return true end
	end

	-- click detectors
	if SD.caps.fireclick then
		for _, c in ipairs(SD.clicks_matching(SELL_NAMES) or {}) do
			if F.is_mine(c) and not F.is_risky(c) then
				if pcall(fireclickdetector, c) then F.status.sell = "sold (click)"; return true end
			end
		end
	end

	-- strict sell remotes
	for _, names in ipairs({ { "selldirt","sell_dirt","sellall","sell_all" }, { "sell","cashout","cash_out","deposit" } }) do
		for _, r in ipairs(SD.remotes_matching(names) or {}) do
			if safe_remote(r) then
				local n = lower(r.name or "")
				if has(n, "sell") or has(n, "cash") or has(n, "deposit") then
					if SD.probe_remote(r, {}) then F.status.sell = "remote OK"; return true end
				end
			end
		end
	end

	F.status.sell = "waiting (scan/setup if stuck)"
	return false
end

-- collect -------------------------------------------------------------------
function F.collect_once()
	if not SD.caps.fireprompt then F.status.collect = "no prompt support"; return 0 end
	SD.refresh()
	local n = 0
	for _, p in ipairs(SD.cache.prompts or {}) do
		if F.is_mine(p) and not F.is_risky(p) then
			local txt = lower((p.Name or "") .. " " .. (p.ActionText or "") .. " " .. (p.ObjectText or "") .. " " .. (p.Parent and p.Parent.Name or ""))
			pcall(function() txt = txt .. " " .. lower(p:GetFullName()) end)
			local bad = hasAny(txt, { "sell","cashout","exchange","upgrade","buy","shop","extractor","extract","machine","processor","autosell","auto sell","gamepass","robux" })
			local good = hasAny(txt, { "collect","claim","pickup","pick up","grab","take","reward","ball","drop","loot","board","dirt" })
			-- "dirt" pickup only if not a sell/extractor context; keep conservative
			if has(txt, "sell") or has(txt, "extractor") then good = false end
			if not bad and good then
				if pcall(fireproximityprompt, p) then n = n + 1 end
			end
		end
	end
	F.status.collect = n > 0 and ("collected " .. n) or "idle"
	return n
end

-- dig -----------------------------------------------------------------------
local TOOL_PATTERNS = { "shovel", "spade", "dig", "pickaxe", "drill", "excavator", "scoop" }
function F.dig_tool()
	local ch = SD.get_char(); if not ch then return nil end
	local custom = SD.config.dig_tool
	local pats = (custom and custom ~= "") and { custom } or TOOL_PATTERNS
	local eq = ch:FindFirstChildOfClass("Tool")
	if eq and SD.match(eq.Name, pats) then return eq end
	local bp = LP and LP:FindFirstChild("Backpack")
	if bp then
		for _, t in ipairs(bp:GetChildren()) do
			if t:IsA("Tool") and SD.match(t.Name, pats) then
				local hum = SD.get_hum()
				if hum then pcall(function() hum:EquipTool(t) end) end
				return t
			end
		end
	end
	return eq
end

function F.dig_once()
	local acted = false
	local tool = F.dig_tool()
	if tool then pcall(function() tool:Activate() end); acted = true end
	-- also fire dirt click detectors/prompts on my plot (nearby)
	if SD.caps.fireclick then
		local hrp = SD.get_hrp()
		for _, c in ipairs(SD.cache.clicks or {}) do
			if F.is_mine(c) and not F.is_risky(c) then
				local part = SD.resolve_part(c)
				local d = (hrp and part) and (part.Position - hrp.Position).Magnitude or 999
				local pn = lower((part and part.Name or "") .. " " .. (c.Parent and c.Parent.Name or ""))
				if d <= 30 and (has(pn, "dirt") or has(pn, "dig") or has(pn, "mud") or has(pn, "pile")) then
					if pcall(fireclickdetector, c) then acted = true end
				end
			end
		end
	end
	F.status.dig = acted and "digging" or "waiting (equip tool)"
	return acted
end

-- upgrades (manual/safe) ----------------------------------------------------
function F.buy_upgrades_once()
	SD.refresh()
	local n = 0
	for _, p in ipairs(SD.prompts_matching({ "upgrade", "level up", "improve" }) or {}) do
		if F.is_mine(p) and not F.is_risky(p) then
			if pcall(fireproximityprompt, p) then n = n + 1 end
		end
	end
	F.status.upgrades = n > 0 and ("triggered " .. n) or "none found"
	return n
end

-- ESP -----------------------------------------------------------------------
local function espAdd(bucket, key, adornee, color)
	if not adornee then return end
	if F.esp[bucket][key] and F.esp[bucket][key].Parent then return end
	local h = Instance.new("Highlight")
	h.Name = "SD_" .. bucket
	h.FillColor = color
	h.FillTransparency = 0.65
	h.OutlineColor = color
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Adornee = adornee
	h.Parent = SD.gui and SD.gui.root or LP:FindFirstChild("PlayerGui")
	F.esp[bucket][key] = h
end
local function espClear(bucket)
	for k, h in pairs(F.esp[bucket] or {}) do pcall(function() h:Destroy() end); F.esp[bucket][k] = nil end
end

function F.esp_tick()
	if SD.config.esp_crown then
		local c = F.find_crown()
		if c then espAdd("crown", "active", c, Color3.fromRGB(255, 200, 64)) else espClear("crown") end
	else espClear("crown") end
	if SD.config.esp_players then
		local seen = {}
		if P then
			for _, plr in ipairs(P:GetPlayers()) do
				if plr ~= LP and plr.Character then
					seen[plr.Name] = true
					espAdd("players", plr.Name, plr.Character, Color3.fromRGB(255, 110, 120))
				end
			end
		end
		for k, h in pairs(F.esp.players) do if not seen[k] then pcall(function() h:Destroy() end); F.esp.players[k] = nil end end
	else espClear("players") end
end

-- utility -------------------------------------------------------------------
function F.apply_speed()
	local hum = SD.get_hum(); if not hum then return end
	if SD.config.speed_lock then hum.WalkSpeed = tonumber(SD.config.walkspeed) or 24 end
	if SD.config.jump_lock then hum.UseJumpPower = true; hum.JumpPower = tonumber(SD.config.jumppower) or 50 end
end

F._noclipConn = nil
function F.set_noclip(on)
	SD.config.noclip = on and true or false
	if F._noclipConn then F._noclipConn:Disconnect(); F._noclipConn = nil end
	if not on then return end
	local RS = SD.RunService
	if RS and RS.Stepped then
		F._noclipConn = RS.Stepped:Connect(function()
			if not SD.config.noclip then return end
			local ch = SD.get_char(); if not ch then return end
			for _, p in ipairs(ch:GetDescendants()) do
				if p:IsA("BasePart") then p.CanCollide = false end
			end
		end)
	end
end

function F.fullbright(on)
	local L = SD.Lighting; if not L then return end
	if on then
		F._lb = F._lb or { B=L.Brightness, C=L.ClockTime, G=L.GlobalShadows, F=L.FogEnd, A=L.Ambient }
		L.Brightness = 2; L.ClockTime = 14; L.GlobalShadows = false; L.FogEnd = 100000
		L.Ambient = Color3.fromRGB(178,178,178); L.OutdoorAmbient = L.Ambient
	else
		if F._lb then pcall(function() L.Brightness=F._lb.B; L.ClockTime=F._lb.C; L.GlobalShadows=F._lb.G; L.FogEnd=F._lb.F; L.Ambient=F._lb.A end); F._lb=nil end
	end
end

function F.fps_boost(on)
	local L = SD.Lighting; if not L then return end
	if on then
		F._fx = F._fx or {}
		for _, fx in ipairs(L:GetChildren()) do
			if (fx:IsA("BlurEffect") or fx:IsA("BloomEffect") or fx:IsA("SunRaysEffect") or fx:IsA("ColorCorrectionEffect") or fx:IsA("DepthOfFieldEffect")) and fx.Enabled then
				F._fx[fx]=true; fx.Enabled=false
			end
		end
	else
		for fx in pairs(F._fx or {}) do pcall(function() fx.Enabled=true end) end
		F._fx=nil
	end
end

-- tasks ---------------------------------------------------------------------
local gates = {}
local function gate(k, sec)
	local t = now(); if (gates[k] or 0) > t then return false end; gates[k] = t + sec; return true
end

function F.register_tasks()
	SD.add_task("sell", 0.2, function()
		if not SD.config.auto_sell or SD.state.paused or not SD.alive() then F.status.sell = SD.config.auto_sell and "paused" or "off"; return end
		if gate("sell", tonumber(SD.config.sell_delay) or 1.2) then F.sell_once() end
	end)
	SD.add_task("collect", 0.2, function()
		if not SD.config.auto_collect or SD.state.paused or not SD.alive() then F.status.collect = SD.config.auto_collect and "paused" or "off"; return end
		if gate("collect", tonumber(SD.config.collect_delay) or 1.0) then F.collect_once() end
	end)
	SD.add_task("dig", 0.1, function()
		if not SD.config.auto_dig or SD.state.paused or not SD.alive() then F.status.dig = SD.config.auto_dig and "paused" or "off"; return end
		if gate("dig", tonumber(SD.config.dig_delay) or 0.25) then F.dig_once() end
	end)
	SD.add_task("crown", 0.15, function()
		if not SD.config.auto_crown or SD.state.paused or not SD.alive() then F.status.crown = SD.config.auto_crown and "paused" or "off"; return end
		if gate("crown", tonumber(SD.config.crown_delay) or 0.75) then F.goto_crown() end
	end)
	SD.add_task("speed", 0.25, function() F.apply_speed() end)
	SD.add_task("esp", 0.9, function() F.esp_tick() end)
	SD.add_task("stats", 0.5, function()
		local cash, name = SD.cash()
		if cash then
			if SD.state.last_cash and cash > SD.state.last_cash then SD.state.session_earned = SD.state.session_earned + (cash - SD.state.last_cash) end
			SD.state.last_cash = cash
			if SD.gui and SD.gui.set_status then SD.gui.set_status((name or "cash") .. " " .. SD.fmt(cash)) end
		end
	end)
end

function F.bind_character()
	SD.state.anchor = nil
	task.defer(F.apply_speed)
	if SD.config.noclip then F.set_noclip(true) end
end

if LP then LP.CharacterAdded:Connect(function() task.wait(0.4); F.bind_character() end) end
F.my_plot()

SD.log("features v3 loaded")

--[[
    Sell Dirt v3 exploits/discovery (manual, opt-in, deep scan)
    - No blind firing on load.
    - Never fires buy/purchase/gamepass/robux/autosell/admin/marketplace remotes.
    - Probes for cash/stat-gain bugs and common dupe patterns. Results in console (F9).
    NOTE: Roblox server source is not accessible to clients; this scans live client-visible
    remotes/prompts and measures observable stat changes.
]]

local SD = getgenv().SD
local E = {}
SD.exploits = E
E.hits = {}
E.log = {}

local function elog(msg) E.log[#E.log+1]=msg; SD.log("[exploit] " .. tostring(msg)) end

local HARD_BLOCK = {
	"autosell","auto sell","auto_sell","autocollect","gamepass","robux","devproduct",
	"marketplace","promptpurchase","promptgamepass","promptproduct",
	"buy","purchase","donate","pay","billing",
	"admin","ban","kick","mod","moderate",
	"chat","report","log","analytics","telemetry","track",
	"save","datastore", -- avoid poking persistence internals blindly
}

local function risky_remote(r)
	if not r then return true end
	local n = string.lower((r.name or "") .. " " .. (r.path or ""))
	for _, b in ipairs(HARD_BLOCK) do if string.find(n, b, 1, true) then return true end end
	if SD.is_risky and SD.is_risky(r) then return true end
	return false
end

local function snapshot_stats()
	local s = {}
	local plr = SD.plr; if not plr then return s end
	for _, cname in ipairs({ "leaderstats","Stats","Data","Values","PlayerStats","Inventory","BackpackData","save" }) do
		local c = plr:FindFirstChild(cname)
		if c then
			for _, v in ipairs(c:GetDescendants()) do
				if v:IsA("NumberValue") or v:IsA("IntValue") or v:IsA("IntConstrainedValue") then
					local ok, path = pcall(function() return v:GetFullName() end)
					s[ok and path or v.Name] = tonumber(v.Value) or 0
				elseif v:IsA("StringValue") then
					-- ignore
				end
			end
		end
	end
	-- also scan player descendants for numeric values (bounded)
	local n = 0
	for _, v in ipairs(plr:GetDescendants()) do
		if n > 250 then break end
		if v:IsA("NumberValue") or v:IsA("IntValue") then
			local ok, path = pcall(function() return v:GetFullName() end)
			local k = ok and path or v.Name
			if s[k] == nil then s[k] = tonumber(v.Value) or 0; n = n + 1 end
		end
	end
	return s
end

local function diff_stats(before, after)
	local gains = {}
	for k, av in pairs(after) do
		local bv = before[k]
		if bv ~= nil and av > bv then gains[#gains+1] = { key=k, before=bv, after=av, gain=av-bv } end
	end
	table.sort(gains, function(a,b) return a.gain > b.gain end)
	return gains
end

local function fire_remote(remote, args)
	return SD.probe_remote(remote, args)
end

function E.probe(remote, args, settle)
	local before = snapshot_stats()
	local ok, err = fire_remote(remote, args)
	if not ok then return { ok=false, err=tostring(err), gains={} } end
	task.wait(settle or 0.45)
	local after = snapshot_stats()
	return { ok=true, gains=diff_stats(before, after) }
end

local function record_hit(remote, argsLabel, gains)
	local best = gains[1]
	local hit = {
		remote = remote.path or remote.name,
		name = remote.name,
		args = argsLabel,
		gain = best and best.gain or 0,
		stat = best and best.key or "?",
	}
	E.hits[#E.hits+1] = hit
	elog(("HIT %s | +%s | stat=%s | args=%s"):format(hit.name, SD.fmt(hit.gain), hit.stat, argsLabel))
	for i=2, math.min(#gains, 4) do
		elog(("  also +%s %s"):format(SD.fmt(gains[i].gain), gains[i].key))
	end
	return hit
end

local function arg_label(args)
	local ok, j = pcall(function() return SD.HttpService:JSONEncode(args) end)
	return ok and j or tostring(args)
end

local COMMON_PROBES = {
	{},
	{1}, {true}, {false},
	{999}, {999999}, {999999999},
	{math.huge}, {-1},
	{"all"}, {"All"}, {"SellAll"}, {"Sell"}, {"Collect"}, {"Claim"},
	{SD.plr and SD.plr.Name or "Player"},
	{SD.plr},
}
local DUPE_PROBES = {
	{{amount=999999}}, {{Amount=999999}}, {{count=999999}}, {{Count=999999}},
	{{value=999999}}, {{Value=999999}}, {{cash=999999}}, {{Cash=999999}},
	{{dirt=999999}}, {{Dirt=999999}},
	{{[1]=999999}}, {{[1]="all"}},
	{{item="all", amount=999999}}, {{action="sell", amount=999999}},
}

local function candidate_score(r)
	local n = string.lower((r.name or "") .. " " .. (r.path or ""))
	local s = 0
	for _, k in ipairs({ "sell","cashout","collect","claim","reward","deposit","redeem","dirt","money","cash","coin","give","add","gain" }) do
		if string.find(n, k, 1, true) then s = s + 2 end
	end
	for _, k in ipairs({ "inventory","tool","item","crate","open","pickup" }) do
		if string.find(n, k, 1, true) then s = s + 1 end
	end
	if r.class == "RemoteFunction" then s = s + 1 end
	return s
end

function E.get_candidates()
	SD.refresh(true)
	local all = {}
	for _, r in ipairs(SD.cache.remotes or {}) do
		if not risky_remote(r) then
			local s = candidate_score(r)
			if s > 0 then all[#all+1] = { r=r, s=s } end
		end
	end
	table.sort(all, function(a,b) return a.s > b.s end)
	local out = {}
	for i=1, math.min(#all, 60) do out[#out+1] = all[i].r end
	return out
end

function E.deep_scan(opts)
	opts = opts or {}
	SD.refresh(true)
	E.hits = {}; E.log = {}
	elog("=== DEEP SCAN START ===")
	elog("Note: server source is not client-accessible. Scanning client-visible remotes/prompts and stat deltas.")
	elog(("Remotes: %d | Prompts: %d | Executor caps: fireprompt=%s"):format(#(SD.cache.remotes or {}), #(SD.cache.prompts or {}), tostring(SD.caps.fireprompt)))

	local candidates = E.get_candidates()
	elog("Safe candidates to probe: " .. #candidates)
	local tried = 0
	local maxTries = tonumber(opts.max_tries) or 80

	-- Phase 1: common probes on top candidates
	for _, remote in ipairs(candidates) do
		if SD.state.paused or tried >= maxTries then break end
		for _, args in ipairs(COMMON_PROBES) do
			if SD.state.paused or tried >= maxTries then break end
			tried = tried + 1
			local res = E.probe(remote, args, 0.35)
			if res.ok and #res.gains > 0 then record_hit(remote, arg_label(args), res.gains); break end
			task.wait(0.03)
		end
	end

	-- Phase 2: dupe/amount-shaped probes on sell-like remotes
	local sellish = {}
	for _, r in ipairs(candidates) do
		local n = string.lower(r.name or "")
		if string.find(n,"sell",1,true) or string.find(n,"cash",1,true) or string.find(n,"collect",1,true) or string.find(n,"claim",1,true) or string.find(n,"reward",1,true) or string.find(n,"dirt",1,true) then
			sellish[#sellish+1] = r
		end
	end
	elog("Phase 2 (dupe-shaped args) on " .. #sellish .. " remotes")
	for _, remote in ipairs(sellish) do
		if SD.state.paused or tried >= maxTries + 40 then break end
		for _, args in ipairs(DUPE_PROBES) do
			if SD.state.paused or tried >= maxTries + 40 then break end
			tried = tried + 1
			local res = E.probe(remote, args, 0.4)
			if res.ok and #res.gains > 0 then record_hit(remote, arg_label(args), res.gains); break end
			task.wait(0.03)
		end
	end

	-- Phase 3: rapid double-fire check (can reveal weak validation / duplication)
	elog("Phase 3 (double-fire) on top sell-like remotes")
	local dbl = 0
	for _, remote in ipairs(sellish) do
		if dbl >= 12 or SD.state.paused then break end
		dbl = dbl + 1
		local before = snapshot_stats()
		pcall(function() fire_remote(remote, {}) end)
		pcall(function() fire_remote(remote, {}) end)
		task.wait(0.5)
		local gains = diff_stats(before, snapshot_stats())
		if #gains > 0 then record_hit(remote, "double-fire {}", gains) end
		task.wait(0.04)
	end

	-- Phase 4: prompt scan (find gamepass/autosell prompts to AVOID, and useful prompts)
	if SD.caps.fireprompt then
		elog("Phase 4 (prompt audit, no firing)")
		for _, p in ipairs(SD.cache.prompts or {}) do
			local txt = string.lower((p.Name or "") .. " " .. (p.ActionText or "") .. " " .. (p.ObjectText or ""))
			local par = p.Parent and p.Parent:GetFullName() or "?"
			if string.find(txt,"gamepass",1,true) or string.find(txt,"robux",1,true) or string.find(txt,"autosell",1,true) or string.find(txt,"auto sell",1,true) then
				elog("AVOID prompt (gamepass/autosell): " .. txt .. " @ " .. par)
			elseif string.find(txt,"sell",1,true) or string.find(txt,"collect",1,true) or string.find(txt,"claim",1,true) then
				elog("Useful prompt: " .. txt .. " @ " .. par)
			end
		end
	end

	elog(("=== DEEP SCAN DONE | tried=%d | hits=%d ==="):format(tried, #E.hits))
	if #E.hits == 0 then
		SD.notify(("Deep scan done: no stat-gain exploits found (%d probes)."):format(tried), "warn")
		elog("No observable stat gains. This does NOT prove no dupes exist (server logic/stateful dupes may not show as immediate stat changes).")
	else
		SD.notify(("Deep scan found %d possible exploit(s)! Check console (F9)."):format(#E.hits), "ok")
		elog("Review hits above. A 'possible exploit' means firing that remote/args increased a numeric stat; verify manually and use at your own risk.")
	end
	return E.hits
end

function E.sell_candidates()
	local out = {}
	for _, r in ipairs(E.get_candidates()) do
		local n = string.lower(r.name or "")
		if (string.find(n,"sell",1,true) or string.find(n,"cash",1,true) or string.find(n,"deposit",1,true)) and not risky_remote(r) then out[#out+1]=r end
	end
	return out
end

function E.auto_configure()
	SD.refresh(true)
	local plot = SD.features and SD.features.my_plot and SD.features.my_plot()
	local plotName = plot and plot.Name or "auto"
	local best = nil
	for _, r in ipairs(E.sell_candidates()) do
		local n = string.lower(r.name or "")
		if string.find(n, "sell", 1, true) then best = r; break end
	end
	if not best then
		for _, r in ipairs(E.get_candidates()) do
			local n = string.lower(r.name or "")
			if (string.find(n,"sell",1,true) or string.find(n,"cash",1,true)) and not risky_remote(r) then best=r; break end
		end
	end
	if best and (not SD.config.sell_remote or SD.config.sell_remote == "") then SD.config.sell_remote = best.name end
	SD.notify("Scan done. Modules are OFF — enable in Farm.", "ok")
	elog(("Scan: plot=%s remotes=%d prompts=%d sellRemote=%s"):format(plotName, #(SD.cache.remotes or {}), #(SD.cache.prompts or {}), best and best.name or "auto"))
	return { plot=plotName, sellRemote=best and best.name or nil }
end

function E.find_exploits() return E.deep_scan({ max_tries = 60 }) end
function E.deep_dupe_scan() return E.deep_scan({ max_tries = 140 }) end

SD.log("exploits v3 deep scan loaded")

--[[
    Sell Dirt v3 boot — clean, simple GUI. All modules are on/off switches.
    Nothing enabled by default.
]]

local SD = getgenv().SD
local gui = SD.gui
local F = SD.features
local T = gui.theme

SD.load_config()
gui.build()

local savePending = false
local function persist()
	if savePending then return end
	savePending = true
	task.delay(1.5, function()
		savePending = false
		if SD.caps.writefile and SD.caps.makefolder then
			pcall(function() makefolder("SellDirt") end)
			local ok, json = pcall(function() return SD.HttpService:JSONEncode(SD.config) end)
			if ok then pcall(function() writefile(SD.CONFIG_FILE, json) end) end
		end
	end)
end
local function bind(key)
	return function(v) SD.config[key] = v; persist() end
end
local function bindNum(key)
	return function(v) SD.config[key] = tonumber(v) or SD.config[key]; persist() end
end

-- FARM TAB ------------------------------------------------------------------
local farm = gui.tab("Farm")

local main = gui.section(farm, "Modules (on/off)")
gui.label(main, "Everything is OFF by default. Turn on what you want. Safe: no Robux/gamepass actions, your plot only.", 16, T.muted).TextSize = 11

gui.toggle(main, { text = "Auto Sell (works from anywhere)", default = SD.config.auto_sell, callback = bind("auto_sell") })
gui.toggle(main, { text = "Auto Collect (pickups/board, skips extractor)", default = SD.config.auto_collect, callback = bind("auto_collect") })
gui.toggle(main, { text = "Auto Dig", default = SD.config.auto_dig, callback = bind("auto_dig") })
gui.toggle(main, { text = "Auto Crown (TP only when a real crown event is active)", default = SD.config.auto_crown, callback = bind("auto_crown") })

local speedSec = gui.section(farm, "Speed")
gui.slider(speedSec, { text = "Sell delay", min = 0.5, max = 10, decimals = 1, suffix = "s", default = SD.config.sell_delay, callback = bindNum("sell_delay") })
gui.slider(speedSec, { text = "Collect delay", min = 0.3, max = 10, decimals = 1, suffix = "s", default = SD.config.collect_delay, callback = bindNum("collect_delay") })
gui.slider(speedSec, { text = "Dig delay", min = 0.05, max = 2, decimals = 2, suffix = "s", default = SD.config.dig_delay, callback = bindNum("dig_delay") })
gui.slider(speedSec, { text = "Crown check", min = 0.3, max = 5, decimals = 1, suffix = "s", default = SD.config.crown_delay, callback = bindNum("crown_delay") })

local actions = gui.section(farm, "Quick actions")
gui.button(actions, { text = "Sell Now", callback = function() local ok = F.sell_once(); SD.notify(ok and "Sell triggered" or ("Sell not found: " .. tostring(F.status.sell)), ok and "ok" or "warn") end })
gui.button(actions, { text = "Collect Now", callback = function() local n = F.collect_once(); SD.notify("Collected " .. tostring(n) .. " prompt(s)", n > 0 and "ok" or "warn") end })
gui.button(actions, { text = "TP to Crown Now (only if active)", callback = function() local ok = F.goto_crown(); SD.notify(ok and "Teleported to crown" or "No active crown event right now", ok and "ok" or "warn") end })
gui.button(actions, { text = "Scan Game / Detect Plot", callback = function() pcall(function() SD.exploits.auto_configure() end) end })

-- PLAYER TAB ----------------------------------------------------------------
local player = gui.tab("Player")

local move = gui.section(player, "Movement")
gui.toggle(move, { text = "Lock WalkSpeed", default = SD.config.speed_lock, callback = function(v) SD.config.speed_lock = v; persist(); F.apply_speed() end })
gui.slider(move, { text = "WalkSpeed", min = 16, max = 300, decimals = 0, default = SD.config.walkspeed, callback = function(v) SD.config.walkspeed = v; persist(); F.apply_speed() end })
gui.toggle(move, { text = "Lock JumpPower", default = SD.config.jump_lock, callback = function(v) SD.config.jump_lock = v; persist(); F.apply_speed() end })
gui.slider(move, { text = "JumpPower", min = 50, max = 300, decimals = 0, default = SD.config.jumppower, callback = function(v) SD.config.jumppower = v; persist(); F.apply_speed() end })
gui.toggle(move, { text = "Noclip", default = SD.config.noclip, callback = function(v) F.set_noclip(v); persist() end })

local vis = gui.section(player, "Visual")
gui.toggle(vis, { text = "ESP Crown (active event only)", default = SD.config.esp_crown, callback = bind("esp_crown") })
gui.toggle(vis, { text = "ESP Players", default = SD.config.esp_players, callback = bind("esp_players") })
gui.toggle(vis, { text = "Fullbright", default = SD.config.fullbright, callback = function(v) SD.config.fullbright = v; F.fullbright(v); persist() end })
gui.toggle(vis, { text = "FPS Boost", default = SD.config.fps_boost, callback = function(v) SD.config.fps_boost = v; F.fps_boost(v); persist() end })

-- SETTINGS TAB --------------------------------------------------------------
local settings = gui.tab("Settings")

local util = gui.section(settings, "Utility")
gui.toggle(util, { text = "Anti-AFK", default = SD.config.anti_afk, callback = bind("anti_afk") })
gui.toggle(util, { text = "Auto Rejoin on disconnect", default = SD.config.auto_rejoin, callback = bind("auto_rejoin") })
gui.toggle(util, { text = "Pause all modules", default = false, callback = function(v) SD.state.paused = v; SD.notify(v and "Paused" or "Resumed", v and "warn" or "ok") end })

local statusLabel = gui.label(util, "Status: ready", 16, T.muted)
statusLabel.TextSize = 11
statusLabel.TextWrapped = true
statusLabel.AutomaticSize = Enum.AutomaticSize.Y

local setup = gui.section(settings, "Setup (only if auto-detect misses)")
gui.toggle(setup, { text = "Only use MY plot (recommended)", default = SD.config.only_my_plot, callback = bind("only_my_plot") })
gui.textbox(setup, { text = "Sell remote", default = SD.config.sell_remote, placeholder = "auto", callback = function(v) SD.config.sell_remote = v; persist() end })
gui.textbox(setup, { text = "Sell object", default = SD.config.sell_object, placeholder = "auto", callback = function(v) SD.config.sell_object = v; persist() end })
gui.textbox(setup, { text = "Crown object", default = SD.config.crown_object, placeholder = "Crown", callback = function(v) SD.config.crown_object = v; persist() end })
gui.textbox(setup, { text = "Dig tool", default = SD.config.dig_tool, placeholder = "Shovel", callback = function(v) SD.config.dig_tool = v; persist() end })

local cfg = gui.section(settings, "Config")
gui.button(cfg, { text = "Save config", callback = function() SD.save_config() end })
gui.button(cfg, { text = "Unload", color = Color3.fromRGB(60, 26, 34), text_color = T.danger, callback = function() SD.unload() end })

local expl = gui.section(settings, "Exploit / dupe scan (manual)")
gui.label(expl, "Scans client-visible remotes/prompts for cash/stat-gain bugs and dupe-shaped arg patterns. Never fires gamepass/robux/buy/admin remotes. Results print to console (F9).", 16, T.muted).TextSize = 11
gui.button(expl, { text = "Scan (fast)", callback = function() task.spawn(function() if SD.exploits then SD.exploits.find_exploits() end end) end })
gui.button(expl, { text = "Deep Dupe/Exploit Scan (thorough)", color = T.accent, callback = function() task.spawn(function() if SD.exploits and SD.exploits.deep_dupe_scan then SD.exploits.deep_dupe_scan() else SD.notify("Unavailable", "warn") end end) end })
gui.button(expl, { text = "Dump Recon to Console", callback = function() SD.dump(); SD.notify("Recon dumped (F9)", "ok") end })
gui.button(expl, { text = "Show Last Hits", callback = function()
	local E = SD.exploits
	if not E or #(E.hits or {}) == 0 then SD.notify("No hits yet", "warn"); return end
	for _, h in ipairs(E.hits) do SD.log(("[HIT] %s +%s %s args=%s"):format(h.remote or h.name, SD.fmt(h.gain), h.stat or "", h.args or "")) end
	SD.notify(#E.hits .. " hit(s) printed to console", "ok")
end })

-- RUNTIME -------------------------------------------------------------------
F.register_tasks()

local heartbeat = SD.RunService.Heartbeat:Connect(SD.run_tasks)

SD.add_task("ui_status", 1.0, function()
	local up = os.time() - SD.state.session_start
	pcall(F.my_plot)
	local s = F.status or {}
	statusLabel.Text = ("Up %s | earned +%s | plot %s\nSell: %s | Collect: %s | Dig: %s | Crown: %s"):format(
		SD.clock_str(up), SD.fmt(SD.state.session_earned), tostring(s.plot or "?"),
		tostring(s.sell or "off"), tostring(s.collect or "off"), tostring(s.dig or "off"), tostring(s.crown or "off")
	)
end)

-- anti-afk / auto-rejoin
if SD.plr then
	SD.plr.Idled:Connect(function()
		if not SD.config.anti_afk then return end
		local vu = SD.VirtualUser
		if vu then pcall(function() vu:CaptureController(); vu:ClickButton2(Vector2.new()) end) end
	end)
	local cg = SD.safe(function() return game:GetService("CoreGui") end)
	local overlay = cg and cg:FindFirstChild("RobloxPromptGui") and cg.RobloxPromptGui:FindFirstChild("promptOverlay")
	if overlay then
		overlay.ChildAdded:Connect(function(child)
			if not SD.config.auto_rejoin or SD.state.rejoin_guard then return end
			if child.Name == "ErrorPrompt" then
				SD.state.rejoin_guard = true
				task.delay(1.5, function()
					pcall(function() SD.TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, SD.plr) end)
				end)
			end
		end)
	end
end

function SD.unload()
	if heartbeat then heartbeat:Disconnect() end
	F.set_noclip(false)
	F.fullbright(false); F.fps_boost(false)
	for _, bucket in pairs(F.esp or {}) do for _, h in pairs(bucket) do pcall(function() h:Destroy() end) end end
	if SD.gui and SD.gui.root then SD.gui.root:Destroy() end
	getgenv().SD = nil
	print("[SD] unloaded")
end

F.bind_character()
task.spawn(function() SD.refresh(true); pcall(F.my_plot) end)

SD.notify("Sell Dirt v" .. SD.version .. " loaded. All modules OFF — enable what you want in Farm.", "ok")
SD.log("v3 ready")

