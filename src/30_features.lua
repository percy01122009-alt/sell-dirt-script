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
	if SD.config.auto_sell_remote_fallback == nil then SD.config.auto_sell_remote_fallback = true end
	if SD.config.queue_on_teleport == nil then SD.config.queue_on_teleport = false end

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

function F.fire_sell_remotes()
		-- Fire remotes that look like sell/cashout. Useful when the game uses a
		-- RemoteEvent instead of a physical sell zone. Silent and rate-gated by caller.
		local names = { "sell", "cashout", "cash out", "exchange", "deposit", "turnin", "turn in" }
		local list = SD.remotes_matching(names)
		local fired = 0
		for _, r in ipairs(list) do
			-- avoid obviously dangerous global actions
			local n = string.lower(r.name or "")
			if not (string.find(n, "rebirth", 1, true) or string.find(n, "prestige", 1, true) or string.find(n, "reset", 1, true)) then
				local ok = SD.probe_remote(r, {})
				if ok then fired = fired + 1 end
			end
		end
		return fired
	end

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
		if target then
			local ok, fired = F.visit(target, { radius = 18, settle = 0.25 })
			if ok then
				if fired == 0 then
					-- prompt may need a hold; try the raw prompt API on the object itself
					SD.interact(target)
				end
				if SD.config.sell_return then
					task.delay(0.4, F.return_home)
				end
				return true
			end
		end

		-- fallback: some Sell Dirt variants are remote-driven with no physical zone
		if SD.config.auto_sell_remote_fallback then
			return F.fire_sell_remotes() > 0
		end
		return false
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

-- rejoin / hop (F.rejoin and F.server_hop defined below with queue_on_teleport support)

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

local function queue_self()
		if SD.state.queued_tp then return end
		if not SD.config.queue_on_teleport then return end
		if not SD.caps.queue_teleport then return end
		-- Re-execute from the same hosted source if the user loaded via HttpGet,
		-- or just re-run the global entry if present. We store a small bootstrap.
		local url = rawget(getgenv(), "SD_LOADSTRING_URL")
		local payload
		if type(url) == "string" and url ~= "" then
			payload = ("loadstring(game:HttpGet(%q))()"):format(url)
		else
			-- no known URL; nothing safe to queue
			return
		end
		local ok = pcall(function() queue_on_teleport(payload) end)
		if ok then SD.state.queued_tp = true end
	end

	function F.server_hop()
		queue_self()
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

	function F.rejoin()
		if SD.state.rejoin_guard then return end
		SD.state.rejoin_guard = true
		queue_self()
		SD.notify("rejoining...", "warn")
		task.wait(0.5)
		pcall(function()
			SD.TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, SD.plr)
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
