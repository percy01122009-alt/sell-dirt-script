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

local auto = gui.section(grind, "Main (turn on what you want)")
gui.label(auto, "Nothing is enabled by default. Auto Sell uses remotes (no teleport) and only your plot.", 16, T.muted).TextSize = 11
gui.button(auto, {
	text = "Scan Game / Detect Plot",
	callback = function() pcall(function() SD.exploits.auto_configure() end) end,
})

gui.toggle(auto, {
    text = "Auto Sell (safe, no robux)",
    default = SD.config.auto_sell,
    callback = bind("auto_sell"),
})

gui.toggle(auto, {
    text = "Auto Dig",
    default = SD.config.auto_dig,
    callback = bind("auto_dig"),
})

gui.toggle(auto, {
    text = "Auto Collect nearby (my plot)",
    default = SD.config.auto_collect,
    callback = bind("auto_collect"),
})

gui.toggle(auto, {
    text = "Auto Upgrade (in-game only, can spend game cash)",
    default = SD.config.auto_upgrade,
    callback = bind("auto_upgrade"),
})

gui.toggle(auto, {
    text = "Auto Rebirth/Prestige (DANGEROUS: resets progress)",
    default = SD.config.auto_rebirth,
    callback = bind("auto_rebirth"),
})

gui.slider(auto, {
    text = "Sell speed",
    min = 0.8, max = 12, decimals = 1, suffix = "s",
    default = SD.config.auto_sell_delay,
    callback = bind("auto_sell_delay"),
})

gui.slider(auto, {
    text = "Dig speed",
    min = 0.05, max = 2, decimals = 2, suffix = "s",
    default = SD.config.auto_dig_delay,
    callback = bind("auto_dig_delay"),
})

gui.button(auto, {
    text = "Sell Now",
    callback = function()
        local ok = SD.features.sell_once()
        SD.notify(ok and "Sell triggered" or "Couldn't sell yet (try Auto-Setup / Sell remote in Setup)", ok and "ok" or "warn")
    end,
})

local adv = gui.section(grind, "Advanced (usually not needed)")
gui.toggle(adv, {
    text = "Teleport to sell zone (OFF recommended - can bug/TP wrong)",
    default = SD.config.auto_sell_teleport,
    callback = bind("auto_sell_teleport"),
})

gui.toggle(adv, {
    text = "Return after sell teleport",
    default = SD.config.sell_return,
    callback = bind("sell_return"),
})

gui.dropdown(adv, {
    text = "Dig method",
    options = { "both", "tool", "click" },
    default = SD.config.dig_mode,
    callback = bind("dig_mode"),
})

local targets = gui.section(grind, "Setup (only if auto-detect misses)")
gui.toggle(targets, {
    text = "Only use MY plot (recommended)",
    default = SD.config.only_my_plot,
    callback = bind("only_my_plot"),
})

gui.textbox(targets, {
    text = "Sell remote name",
    default = SD.config.sell_remote,
    placeholder = "auto-detected",
    callback = bind("sell_remote"),
})

gui.textbox(targets, {
    text = "Sell object name",
    default = SD.config.sell_name,
    placeholder = "leave blank",
    callback = bind("sell_name"),
})

gui.textbox(targets, {
    text = "Dig tool name",
    default = SD.config.dig_tool_name,
    placeholder = "Shovel",
    callback = bind("dig_tool_name"),
})

-- MOVEMENT -----------------------------------------------------------------

local move = gui.tab("Move")

local tps = gui.section(move, "Crown (automatic)")
gui.label(tps, "Auto TP only moves when a real crown/event object is active.", 16, T.muted).TextSize = 11

gui.toggle(tps, {
    text = "Auto TP to Crown (only during active crown event)",
    default = SD.config.tp_crown,
    callback = bind("tp_crown"),
})

gui.slider(tps, {
    text = "Crown check speed",
    min = 0.5, max = 15, decimals = 1, suffix = "s",
    default = SD.config.tp_crown_delay,
    callback = bind("tp_crown_delay"),
})

gui.button(tps, {
    text = "TP to Crown Now (if active)",
    callback = function()
        local ok = SD.features.goto_crown({ require_active = true })
        if ok then
            SD.notify("Moved to active crown", "ok")
        else
            SD.notify("No active crown/event right now", "warn")
        end
    end,
})

local misc_tp = gui.section(move, "Other teleports")

gui.button(misc_tp, {
    text = "TP to sell zone (my plot)",
    callback = function()
        if SD.features.goto_sell() then
            SD.notify("moved to sell zone", "ok")
        else
            SD.notify("sell zone not found (Auto Sell remote mode doesn't need this)", "warn")
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

local cheats = gui.section(move, "Client movement helpers")

gui.toggle(cheats, {
    text = "Noclip (client; may not bypass all anti-cheat)",
    default = false,
    callback = function(v)
        SD.exploits.noclip(v)
        if v then
            SD.add_task("noclip", 0.2, function()
                if not SD.exploits._noclip then return end
                local ch = SD.get_char()
                if not ch then return end
                for _, p in ipairs(ch:GetDescendants()) do
                    if p:IsA("BasePart") then p.CanCollide = false end
                end
            end)
        end
    end,
})

gui.button(cheats, {
    text = "Enable infinite jump (client)",
    callback = function()
        SD.exploits.infinite_jump()
        SD.notify("infinite jump enabled", "ok")
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
    text = "Queue script on teleport/hop (needs hosted loadstring URL)",
    default = SD.config.queue_on_teleport,
    callback = bind("queue_on_teleport"),
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
	    local plot = SD.features and SD.features.my_plot and SD.features.my_plot()
	    local plotTxt = plot and (" | plot: " .. tostring(plot.Name)) or ""
	    info.Text = ("uptime %s   session +%s%s"):format(
	        SD.clock_str(up), SD.fmt(SD.state.session_earned), plotTxt
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
	task.spawn(function()
		SD.refresh(true)
	end)

	SD.notify("Loaded (v" .. SD.version .. "). Nothing is enabled - turn on what you want.", "ok")
	SD.log("booted. Nothing enabled by default. Use Grind/Move tabs to enable features.")
