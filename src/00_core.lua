--[[
    Sell Dirt — v3 core
    Luau client script (Delta Executor Android). Shared services, config, scheduler, helpers.
]]

local SD = {}
getgenv().SD = SD

SD.version = "3.2.1"
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
