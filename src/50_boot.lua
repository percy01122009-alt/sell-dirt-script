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
