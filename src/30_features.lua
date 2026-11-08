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

F.status = { sell = "off", collect = "off", dig = "off", crown = "off", upgrade = "off", rebirth = "off", plot = "?" }
F._plot, F._plotAt = nil, 0
F._crown, F._crownAt = nil, 0
F.esp = { crown = {}, players = {} }

local function LP() return SD.plr end
local function P() return SD.Players end

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
	local plr = LP()
	if not obj or not obj.Parent or not plr then return false end
	local name, uid = plr.Name, plr.UserId
	local okA, attrs = pcall(function() return obj:GetAttributes() end)
	if okA and type(attrs) == "table" then
		for k, v in pairs(attrs) do
			local lk = lower(k)
			if has(lk, "owner") or has(lk, "user") then
				if v == plr or v == name or v == uid or tostring(v) == name or tostring(v) == tostring(uid) then return true end
			if typeof and typeof(v) == "Instance" and v == plr then return true end
			end
		end
	end
	for _, key in ipairs({ "Owner", "owner", "Player", "player", "UserId", "OwnerId", "PlotOwner" }) do
		local ch = obj:FindFirstChild(key)
		if ch then
			local ok, val = pcall(function() return ch.Value end)
		if ok and (val == plr or val == name or val == uid or tostring(val) == name or tostring(val) == tostring(uid)) then return true end
		end
	end
	return false
end

function F.my_plot()
	if F._plot and F._plot.Parent and (now() - F._plotAt) < 10 then return F._plot end
	F._plot = nil
	local plr = LP(); if not plr then return nil end
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
		local by = root:FindFirstChild(plr.Name)
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
	local plr = LP(); pcall(function() if plr and has(obj:GetFullName(), plr.Name) then desc = true end end)
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
	local Ps = P()
	if Ps then
		for _, plr in ipairs(Ps:GetPlayers()) do
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
	-- explicit remote override
	local ovr = SD.config.sell_remote
	if ovr and ovr ~= "" then
		for _, r in ipairs(SD.remotes_matching({ ovr })) do
			if safe_remote(r) and SD.probe_remote(r, {}) then F.status.sell = "remote OK"; return true end
		end
	end
	-- explicit sell object name override (my plot only)
	local objOvr = SD.config.sell_object
	if objOvr and objOvr ~= "" and SD.caps.fireprompt then
		SD.refresh()
		for _, p in ipairs(SD.cache.prompts or {}) do
			if F.is_mine(p) and not F.is_risky(p) then
				local pn = lower(p.Name or ""); local par = p.Parent and lower(p.Parent.Name or "") or ""
				if has(pn, objOvr) or has(par, objOvr) then
					if pcall(fireproximityprompt, p) then F.status.sell = "sold (override)"; return true end
				end
			end
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
	local plr = LP(); local bp = plr and plr:FindFirstChild("Backpack")
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

-- upgrades / rebirth (optional, off by default) ----------------------------
local UPGRADE_NAMES = { "upgrade", "level up", "levelup", "improve", "enhance" }
local REBIRTH_NAMES = { "rebirth", "prestige", "ascend", "ascension" }
local function safe_plot_prompt(p, names)
	if not p or not F.is_mine(p) or F.is_risky(p) then return false end
	local txt = lower((p.Name or "") .. " " .. (p.ActionText or "") .. " " .. (p.ObjectText or "") .. " " .. (p.Parent and p.Parent.Name or ""))
	if hasAny(txt, { "robux","gamepass","devproduct","buy","purchase","donate" }) then return false end
	return hasAny(txt, names)
end

function F.buy_upgrades_once()
	if not SD.caps.fireprompt then F.status.upgrade = "no prompt support"; return 0 end
	SD.refresh()
	local n = 0
	for _, p in ipairs(SD.cache.prompts or {}) do
		if safe_plot_prompt(p, UPGRADE_NAMES) then
			if pcall(fireproximityprompt, p) then n = n + 1 end
		end
	end
	if n == 0 then
		for _, p in ipairs(SD.prompts_matching(UPGRADE_NAMES) or {}) do
			if safe_plot_prompt(p, UPGRADE_NAMES) then
				if pcall(fireproximityprompt, p) then n = n + 1 end
			end
		end
	end
	F.status.upgrade = n > 0 and ("triggered " .. n) or "none found"
	return n
end

function F.rebirth_once()
	-- DANGEROUS by design when enabled: only safe rebirth/prestige prompts on my plot, no robux
	if not SD.caps.fireprompt then F.status.rebirth = "no prompt support"; return 0 end
	SD.refresh()
	local n = 0
	for _, p in ipairs(SD.cache.prompts or {}) do
		if safe_plot_prompt(p, REBIRTH_NAMES) then
			if pcall(fireproximityprompt, p) then n = n + 1 end
		end
	end
	F.status.rebirth = n > 0 and ("triggered " .. n) or "none found"
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
	local plr = LP(); h.Parent = SD.gui and SD.gui.root or (plr and plr:FindFirstChild("PlayerGui"))
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
		local Ps, me = P(), LP()
		if Ps then
			for _, plr in ipairs(Ps:GetPlayers()) do
				if plr ~= me and plr.Character then
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
	SD.add_task("upgrade", 0.5, function()
		if not SD.config.auto_upgrade or SD.state.paused or not SD.alive() then F.status.upgrade = SD.config.auto_upgrade and "paused" or "off"; return end
		if gate("upgrade", 8.0) then F.buy_upgrades_once() end
	end)
	SD.add_task("rebirth", 1.0, function()
		if not SD.config.auto_rebirth or SD.state.paused or not SD.alive() then F.status.rebirth = SD.config.auto_rebirth and "paused" or "off"; return end
		if gate("rebirth", 15.0) then F.rebirth_once() end
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

local plr = LP(); if plr then plr.CharacterAdded:Connect(function() task.wait(0.4); F.bind_character() end) end
F.my_plot()

SD.log("features v3 loaded")
