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
gui.toggle(main, { text = "Auto Upgrade (in-game currency only, safe)", default = SD.config.auto_upgrade, callback = bind("auto_upgrade") })
gui.toggle(main, { text = "Auto Rebirth (DANGEROUS - resets progress)", default = SD.config.auto_rebirth, callback = bind("auto_rebirth") })

local speedSec = gui.section(farm, "Speed")
gui.slider(speedSec, { text = "Sell delay", min = 0.5, max = 10, decimals = 1, suffix = "s", default = SD.config.sell_delay, callback = bindNum("sell_delay") })
gui.slider(speedSec, { text = "Collect delay", min = 0.3, max = 10, decimals = 1, suffix = "s", default = SD.config.collect_delay, callback = bindNum("collect_delay") })
gui.slider(speedSec, { text = "Dig delay", min = 0.05, max = 2, decimals = 2, suffix = "s", default = SD.config.dig_delay, callback = bindNum("dig_delay") })
gui.slider(speedSec, { text = "Crown check", min = 0.3, max = 5, decimals = 1, suffix = "s", default = SD.config.crown_delay, callback = bindNum("crown_delay") })

local actions = gui.section(farm, "Quick actions")
gui.button(actions, { text = "Sell Now", callback = function() local ok = F.sell_once(); SD.notify(ok and "Sell triggered" or ("Sell: " .. tostring(F.status.sell)), ok and "ok" or "warn") end })
gui.button(actions, { text = "Collect Now", callback = function() local n = F.collect_once(); SD.notify("Collected " .. tostring(n) .. " prompt(s)", n > 0 and "ok" or "warn") end })
gui.button(actions, { text = "TP to Crown Now (only if active)", callback = function() local ok = F.goto_crown(); SD.notify(ok and "Teleported to crown" or "No active crown event right now", ok and "ok" or "warn") end })
gui.button(actions, { text = "Buy Upgrades Now (safe, my plot)", callback = function() local n = F.buy_upgrades_once(); SD.notify("Upgrade prompts triggered: " .. tostring(n), n > 0 and "ok" or "warn") end })
gui.button(actions, { text = "Scan Game / Detect Plot", callback = function() pcall(function() SD.exploits.auto_configure() end) end })

-- CROWN / PLAYER TAB --------------------------------------------------------
local player = gui.tab("Crown/Player")

local crownSec = gui.section(player, "Crown")
gui.label(crownSec, "Auto Crown module is in Farm. It only TPs when a real active crown event object exists.", 16, T.muted).TextSize = 11
gui.button(crownSec, { text = "TP to Crown Now (if active)", callback = function() local ok = F.goto_crown(); SD.notify(ok and "Teleported to crown" or "No active crown event right now", ok and "ok" or "warn") end })

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
	statusLabel.Text = ("Up %s | earned +%s | plot %s\nSell:%s Collect:%s Dig:%s Crown:%s\nUpgrade:%s Rebirth:%s"):format(
		SD.clock_str(up), SD.fmt(SD.state.session_earned), tostring(s.plot or "?"),
		tostring(s.sell or "off"), tostring(s.collect or "off"), tostring(s.dig or "off"), tostring(s.crown or "off"),
		tostring(s.upgrade or "off"), tostring(s.rebirth or "off")
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
						-- AFK recovery: queue script for next server if supported
						local url = rawget(getgenv(), "SD_LOADSTRING_URL")
						if SD.caps.queue_teleport and type(url) == "string" and url ~= "" then
							pcall(function() queue_on_teleport(("loadstring(game:HttpGet(%q))()"):format(url)) end)
						end
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
