--[[
    file: 30_features.lua
    The grind loop. Every target is resolved by name heuristic against the live
    cache, with a manual override in config for when recon gives us the real
    names. Nothing here assumes a specific remote exists.
]]

local SD = getgenv().SD
local F = {}
SD.features = F

-- defaults (safe "cheat" behavior: no robux purchases, minimal teleporting)
	if SD.config.sell_return == nil then SD.config.sell_return = false end
	if SD.config.dig_mode == nil then SD.config.dig_mode = "both" end
	if SD.config.esp_players == nil then SD.config.esp_players = false end
	if SD.config.auto_sell_remote_fallback == nil then SD.config.auto_sell_remote_fallback = true end
	if SD.config.auto_sell_teleport == nil then SD.config.auto_sell_teleport = false end
	if SD.config.queue_on_teleport == nil then SD.config.queue_on_teleport = false end
	if SD.config.only_my_plot == nil then SD.config.only_my_plot = true end
	if SD.config.tp_crown_only_active == nil then SD.config.tp_crown_only_active = true end
	if SD.config.auto_upgrade == nil then SD.config.auto_upgrade = false end -- off: can spend in-game currency unexpectedly
	if SD.config.auto_rebirth == nil then SD.config.auto_rebirth = false end -- off: destructive
	if SD.config.safe_mode == nil then SD.config.safe_mode = true end

-- plot ownership (fix: never interact with another player's plot) ---------

	F._my_plot = nil
	F._my_plot_at = 0

	local function owner_matches_player(obj)
		if not obj or not obj.Parent then return false end
		local plr = SD.plr
		if not plr then return false end
		local name = plr.Name
		local uid = plr.UserId

		-- common attribute patterns
		local okAttr, attrs = pcall(function() return obj:GetAttributes() end)
		if okAttr and type(attrs) == "table" then
			for k, v in pairs(attrs) do
				local lk = string.lower(tostring(k))
				if string.find(lk, "owner", 1, true) or string.find(lk, "user", 1, true) then
					if v == name or v == uid or tostring(v) == name or tostring(v) == tostring(uid) then
						return true
					end
					if typeof and typeof(v) == "Instance" and v == plr then return true end
				end
			end
		end

		-- ObjectValue/StringValue/IntValue owner markers
		for _, key in ipairs({ "Owner", "owner", "Player", "player", "OwnerId", "UserId", "PlotOwner" }) do
			local child = obj:FindFirstChild(key)
			if child then
				local ok, val = pcall(function() return child.Value end)
				if ok then
					if val == plr or val == name or val == uid or tostring(val) == name or tostring(val) == tostring(uid) then
						return true
					end
				end
			end
		end

		return false
	end

	local function path_has_my_name(inst)
		if not inst or not SD.plr then return false end
		local ok, path = pcall(function() return inst:GetFullName() end)
		if not ok or not path then return false end
		return string.find(path, SD.plr.Name, 1, true) ~= nil
	end

	function F.my_plot()
		if F._my_plot and F._my_plot.Parent and (os.clock() - F._my_plot_at) < 8 then
			return F._my_plot
		end
		F._my_plot = nil

		local roots = {}
		for _, name in ipairs({ "Plots", "plots", "Tycoons", "tycoons", "Bases", "bases", "Islands", "islands", "Farms", "farms", "PlayerPlots" }) do
			local r = workspace:FindFirstChild(name)
			if r then roots[#roots + 1] = r end
		end
		if #roots == 0 then
			-- scan top-level for plot-like containers
			for _, c in ipairs(workspace:GetChildren()) do
				local ln = string.lower(c.Name)
				if string.find(ln, "plot", 1, true) or string.find(ln, "tycoon", 1, true) or string.find(ln, "base", 1, true) then
					roots[#roots + 1] = c
				end
			end
		end

		for _, root in ipairs(roots) do
			-- direct child named after player
			local byName = root:FindFirstChild(SD.plr.Name)
			if byName then F._my_plot = byName break end

			for _, plot in ipairs(root:GetChildren()) do
				if owner_matches_player(plot) or path_has_my_name(plot) then
					F._my_plot = plot
					break
				end
			end
			if F._my_plot then break end
		end

		-- fallback: nearest plot-like model to spawn/character that has sell-like stuff? risky.
		if F._my_plot then F._my_plot_at = os.clock() end
		return F._my_plot
	end

	function F.is_mine(inst)
		if not SD.config.only_my_plot then return true end
		local plot = F.my_plot()
		if not plot then return true end -- can't determine ownership: don't block everything
		local obj = inst
		if typeof(inst) == "Instance" then
			if inst:IsA("ProximityPrompt") or inst:IsA("ClickDetector") then
				obj = inst.Parent
			end
		end
		if not obj then return true end
		local ok, isDesc = pcall(function() return obj:IsDescendantOf(plot) end)
		if ok and isDesc then return true end
		-- allow if it's literally the plot or has our name
		if path_has_my_name(obj) then return true end
		-- check owner markers on ancestors up a bit
		local cur = obj
		for _ = 1, 6 do
			if not cur or cur == workspace then break end
			if owner_matches_player(cur) then return true end
			cur = cur.Parent
		end
		return false
	end

	local function filter_mine(list)
		if not SD.config.only_my_plot then return list end
		local plot = F.my_plot()
		if not plot then return list end
		local out = {}
		for _, v in ipairs(list) do
			if F.is_mine(v) then out[#out + 1] = v end
		end
		-- if filtering removed everything, fall back to unfiltered to avoid breaking games without plot metadata
		if #out == 0 then return list end
		return out
	end

	-- rate gate ---------------------------------------------------------------

local gates = {}
function SD.gate(key, delay)
    local now = os.clock()
    if (gates[key] or 0) > now then return false end
    gates[key] = now + delay
    return true
end

-- safety: never trigger robux/gamepass/devproduct/purchase/autosell-pass flows
	local function is_risky_action(inst)
		local texts = {}
		local function add(v)
			if type(v) == "string" and v ~= "" then texts[#texts + 1] = string.lower(v) end
		end
		if typeof(inst) == "Instance" then
			add(inst.Name)
			local ok, path = pcall(function() return inst:GetFullName() end)
			if ok then add(path) end
			if inst:IsA("ProximityPrompt") then
				pcall(function() add(inst.ActionText) end)
				pcall(function() add(inst.ObjectText) end)
			end
			local parent = inst.Parent
			if parent then
				add(parent.Name)
				for _, d in ipairs(parent:GetDescendants()) do
					if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
						pcall(function() add(d.Text) end)
					end
					if #texts > 24 then break end
				end
			end
		end
		local hard_bad = { "robux", "gamepass", "game pass", "devproduct", "developer product", "donate", "donation", "premium", "vip pass", "purchase pass", "buy pass" }
		for _, t in ipairs(texts) do
			for _, b in ipairs(hard_bad) do
				if string.find(t, b, 1, true) then return true end
			end
			-- "Auto Sell" gamepass buttons/prompts are a common trap (user reported this)
			if string.find(t, "autosell", 1, true) or string.find(t, "auto sell", 1, true) or string.find(t, "auto-sell", 1, true) then
				return true
			end
			-- avoid obvious purchase prompts unless clearly "sell"
			if string.find(t, "buy", 1, true) and not string.find(t, "sell", 1, true) then
				if SD.config.safe_mode ~= false then return true end
			end
		end
		return false
	end
	SD.is_risky = is_risky_action

	-- target resolution -------------------------------------------------------

	local SELL_PATTERNS   = { "sell", "cashout", "cash out", "exchange", "turn in", "deposit" }
	local SELL_FALLBACK   = {} -- removed: shop/store/vendor caused bad teleports
	local CROWN_PATTERNS  = { "crown" }
	local DIRT_PATTERNS   = { "dirt", "soil", "mud", "ore", "rock pile", "dig" }
	local UPGRADE_PATTERNS = { "upgrade", "level up", "levelup", "improve" } -- no "buy/purchase" by default
	local REBIRTH_PATTERNS = { "rebirth", "prestige", "ascend" } -- no generic "reset"
	local TOOL_PATTERNS   = { "shovel", "spade", "dig", "pickaxe", "drill", "excavator" }

	local function safe_filter(list)
		local out = {}
		for _, v in ipairs(list) do
			if not is_risky_action(v) then out[#out + 1] = v end
		end
		return out
	end

function F.sell_target()
		local custom = SD.config.sell_name
		if custom and custom ~= "" then
			local pr = safe_filter(filter_mine(SD.prompts_matching({ custom })))
			if #pr > 0 then return pr[1] end
			local cd = safe_filter(filter_mine(SD.clicks_matching({ custom })))
			if #cd > 0 then return cd[1] end
			local p = safe_filter(filter_mine(SD.find_parts({ custom })))
			if #p > 0 then return p[1] end
		end
		-- prompts/clicks are safer than teleporting to arbitrary parts
		local pr = safe_filter(filter_mine(SD.prompts_matching(SELL_PATTERNS)))
		if #pr > 0 then return pr[1] end
		local cd = safe_filter(filter_mine(SD.clicks_matching(SELL_PATTERNS)))
		if #cd > 0 then return cd[1] end
		local parts = safe_filter(filter_mine(SD.find_parts(SELL_PATTERNS)))
		if #parts > 0 then return parts[1] end
		return nil
	end

local crown_memo, crown_memo_at = nil, 0

	local function crown_path_excluded(inst)
		local ok, path = pcall(function() return inst:GetFullName() end)
		if not ok or not path then return false end
		local p = string.lower(path)
		local bad = { "feedback", "report", "suggest", "complaint", "donate", "shop", "settings", "menu", "gui", "screen", "interface", "leaderboarddisplay", "statue", "decoration", "spawnlocation" }
		for _, b in ipairs(bad) do
			if string.find(p, b, 1, true) then return true end
		end
		-- never target crowns held by players
		local players = SD.Players
		if players then
			for _, plr in ipairs(players:GetPlayers()) do
				local ch = plr.Character
				if ch then
					local okD, isD = pcall(function() return inst:IsDescendantOf(ch) end)
					if okD and isD then return true end
				end
			end
		end
		return false
	end

	local function crown_is_active(inst)
		if not inst or not inst.Parent then return false end
		local okW, inWorld = pcall(function() return inst:IsDescendantOf(workspace) end)
		if not okW or not inWorld then return false end
		if crown_path_excluded(inst) then return false end

		local function part_visible(p)
			if not p or not p:IsA("BasePart") then return false end
			if p.Transparency >= 0.995 then return false end
			local okSize, sz = pcall(function() return p.Size end)
			if okSize and sz and sz.Magnitude < 0.05 then return false end
			return true
		end

		if inst:IsA("BasePart") then
			return part_visible(inst)
		elseif inst:IsA("Model") then
			if inst.PrimaryPart and part_visible(inst.PrimaryPart) then return true end
			for _, d in ipairs(inst:GetDescendants()) do
				if d:IsA("BasePart") and part_visible(d) then return true end
			end
			return false
		elseif inst:IsA("Tool") or inst:IsA("Accessory") then
			for _, d in ipairs(inst:GetDescendants()) do
				if d:IsA("BasePart") and part_visible(d) then return true end
			end
			-- a tool/accessory in workspace can be a pickup crown
			return inst.Parent == workspace or (inst.Parent and inst.Parent.Parent == workspace)
		end

		local p = SD.resolve_part(inst)
		return part_visible(p)
	end

	local function strong_crown_name(inst)
		if not inst then return false end
		local n = string.lower(tostring(inst.Name or ""))
		if n == "crown" or n == "thecrown" or n == "eventcrown" or n == "crownpickup" or n == "kingcrown" then return true end
		-- allow "Crown" as a clear token in short names, avoid random matches
		if string.find(n, "crown", 1, true) and #n <= 24 and not string.find(n, "feedback", 1, true) and not string.find(n, "report", 1, true) then
			return true
		end
		return false
	end

	function F.crown_target(opts)
		opts = opts or {}
		-- Always require an active, real crown for auto behavior (safety: never TP to random objects)
		local require_active = true

		if crown_memo and crown_memo.Parent and (os.clock() - crown_memo_at) < 1.5 then
			if crown_is_active(crown_memo) then return crown_memo end
			crown_memo = nil
		end

		local custom = SD.config.crown_name
		if custom and custom ~= "" then
			local candidates = {}
			for _, p in ipairs(SD.find_parts({ custom })) do candidates[#candidates + 1] = p end
			for _, m in ipairs(SD.find_models({ custom })) do candidates[#candidates + 1] = m end
			for _, c in ipairs(candidates) do
				if crown_is_active(c) then
					crown_memo, crown_memo_at = c, os.clock()
					return c
				end
			end
			return nil
		end

		-- Auto-detect: ONLY strong crown-named objects in workspace (no billboard text scan, no loose matches)
		local candidates = {}
		SD.refresh()
		for _, m in ipairs(SD.cache.models) do
			if strong_crown_name(m) and crown_is_active(m) then candidates[#candidates + 1] = m end
		end
		for _, p in ipairs(SD.cache.parts) do
			if strong_crown_name(p) and crown_is_active(p) then candidates[#candidates + 1] = p end
		end

		-- if nothing found, try a very narrow scan of direct workspace children
		if #candidates == 0 then
			for _, d in ipairs(workspace:GetDescendants()) do
				if strong_crown_name(d) and crown_is_active(d) then
					candidates[#candidates + 1] = d
					break
				end
			end
		end

		local found = candidates[1]
		if found then crown_memo, crown_memo_at = found, os.clock() end
		return found
	end

function F.dirt_target()
	    local hrp = SD.get_hrp()
	    local parts = filter_mine(SD.find_parts(DIRT_PATTERNS))
	    if #parts == 0 then parts = SD.find_parts(DIRT_PATTERNS) end
	    if #parts == 0 then return nil end
	    if not hrp then return parts[1] end
	    return (SD.nearest_part(parts, hrp.Position))
	end

function F.upgrade_target()
		local pr = safe_filter(filter_mine(SD.prompts_matching(UPGRADE_PATTERNS)))
		if #pr > 0 then return pr[1] end
		local cd = safe_filter(filter_mine(SD.clicks_matching(UPGRADE_PATTERNS)))
		if #cd > 0 then return cd[1] end
		return nil
	end

	function F.rebirth_target()
		local pr = safe_filter(filter_mine(SD.prompts_matching(REBIRTH_PATTERNS)))
		if #pr > 0 then return pr[1] end
		local cd = safe_filter(filter_mine(SD.clicks_matching(REBIRTH_PATTERNS)))
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
		if is_risky_action(inst) then return false, 0 end
		local part = SD.resolve_part(inst)
		if not part then return false, 0 end
		local hrp = SD.get_hrp()
		if not hrp then return false, 0 end

		if opts.allow_teleport == false then
			local fired = SD.interact(inst)
			if fired == 0 then fired = SD.interact_near(part.Position, opts.radius or 16) end
			return fired > 0, fired
		end

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
		-- Fire sell/cashout remotes (no teleporting). Prefer this over physical zones.
		-- Strict matching: "dirt" alone is too broad in this game and can hit wrong remotes.
		local names = { "sell", "cashout", "cash out", "exchange", "deposit", "turnin", "turn in", "selldirt", "sell_dirt" }
		local list = SD.remotes_matching(names)
		local fired = 0
		for _, r in ipairs(list) do
			local n = string.lower((r.name or "") .. " " .. (r.path or ""))
			local blocked = string.find(n, "rebirth", 1, true)
				or string.find(n, "prestige", 1, true)
				or string.find(n, "reset", 1, true)
				or string.find(n, "buy", 1, true)
				or string.find(n, "purchase", 1, true)
				or string.find(n, "robux", 1, true)
				or string.find(n, "gamepass", 1, true)
				or string.find(n, "devproduct", 1, true)
				or string.find(n, "autosell", 1, true)
				or string.find(n, "auto sell", 1, true)
				or string.find(n, "auto_sell", 1, true)
				or string.find(n, "toggle", 1, true)
				or string.find(n, "prompt", 1, true) and string.find(n, "pass", 1, true)
			if not blocked then
				local ok = SD.probe_remote(r, {})
				if ok then
					fired = fired + 1
					if fired >= 2 then break end
				end
				task.wait(0.05)
			end
		end
		return fired
	end

	local function is_real_sell_prompt(p)
		if not p or not p.Parent then return false end
		if is_risky_action(p) then return false end
		local name = string.lower(p.Name or "")
		local action = string.lower(p.ActionText or "")
		local objt = string.lower(p.ObjectText or "")
		local parent = string.lower(p.Parent.Name or "")
		local text = name .. " " .. action .. " " .. objt .. " " .. parent
		-- must look like selling, not auto-sell gamepass/toggle
		local sells = string.find(text, "sell", 1, true) or string.find(text, "cashout", 1, true) or string.find(text, "cash out", 1, true) or string.find(text, "exchange", 1, true) or string.find(text, "deposit", 1, true) or string.find(text, "turn in", 1, true) or string.find(text, "turnin", 1, true)
		if not sells then return false end
		if string.find(text, "autosell", 1, true) or string.find(text, "auto sell", 1, true) or string.find(text, "auto-sell", 1, true) then return false end
		if string.find(text, "gamepass", 1, true) or string.find(text, "robux", 1, true) or string.find(text, "pass", 1, true) then return false end
		return true
	end

	local function safe_sell_remote(r)
		if not r then return false end
		local n = string.lower((r.name or "") .. " " .. (r.path or ""))
		if string.find(n, "autosell", 1, true) or string.find(n, "auto sell", 1, true) or string.find(n, "auto_sell", 1, true) then return false end
		if string.find(n, "toggle", 1, true) then return false end
		if string.find(n, "gamepass", 1, true) or string.find(n, "robux", 1, true) or string.find(n, "devproduct", 1, true) then return false end
		if string.find(n, "buy", 1, true) or string.find(n, "purchase", 1, true) then return false end
		if string.find(n, "promptpurchase", 1, true) or string.find(n, "marketplace", 1, true) then return false end
		return true
	end

	function F.sell_once()
		-- 1) explicit sell remote override (no teleport)
		local rname = SD.config.sell_remote
		if rname and rname ~= "" then
			local list = SD.remotes_matching({ rname })
			for _, r in ipairs(list) do
				if safe_sell_remote(r) then
					local ok = SD.probe_remote(r, {})
					if ok then return true end
				end
			end
		end

		-- 2) fire actual sell prompts on MY plot from ANY distance (executor fireproximityprompt)
		if SD.caps.fireprompt then
			SD.refresh()
			local candidates = {}
			for _, p in ipairs(SD.cache.prompts) do
				if F.is_mine(p) and is_real_sell_prompt(p) then candidates[#candidates + 1] = p end
			end
			if #candidates == 0 then
				for _, p in ipairs(SD.prompts_matching(SELL_PATTERNS)) do
					if F.is_mine(p) and is_real_sell_prompt(p) then candidates[#candidates + 1] = p end
				end
			end
			if #candidates > 0 then
				local fired = 0
				for i = 1, math.min(3, #candidates) do
					local ok = pcall(fireproximityprompt, candidates[i])
					if ok then fired = fired + 1 end
				end
				if fired > 0 then return true end
			end
		end

		-- 3) click detectors on my plot (any distance)
		if SD.caps.fireclick then
			SD.refresh()
			for _, c in ipairs(SD.clicks_matching(SELL_PATTERNS)) do
				if F.is_mine(c) and not is_risky_action(c) and safe_sell_remote({ name = c.Name or "", path = c.Parent and c.Parent:GetFullName() or c.Name or "" }) then
					local ok = pcall(fireclickdetector, c)
					if ok then return true end
				end
			end
		end

		-- 4) strict sell remotes (try several common names/patterns)
		if SD.config.auto_sell_remote_fallback ~= false then
			local tries = {
				{ "selldirt", "sell_dirt", "sellall", "sell_all" },
				{ "sell", "cashout", "cash_out", "deposit" },
			}
			for _, names in ipairs(tries) do
				local list = SD.remotes_matching(names)
				for _, r in ipairs(list) do
					if safe_sell_remote(r) then
						-- prefer remotes explicitly about selling
						local n = string.lower(r.name or "")
						local looks = string.find(n, "sell", 1, true) or string.find(n, "cash", 1, true) or string.find(n, "deposit", 1, true)
						if looks then
							local ok = SD.probe_remote(r, {})
							if ok then return true end
						end
					end
				end
			end
		end

		-- 5) optional teleport (OFF by default) - last resort
		if not SD.config.auto_sell_teleport then return false end
		if not SD.gate("sell_tp", math.max(5, (SD.config.auto_sell_delay or 2) * 2)) then return false end
		local target = F.sell_target()
		if target and F.is_mine(target) and (is_real_sell_prompt(target) or not is_risky_action(target)) then
			local ok = F.visit(target, { radius = 16, settle = 0.2, allow_teleport = true, anchor = false })
			return ok
		end
		return false
	end

function F.dig_click()
	    local hrp = SD.get_hrp()
	    if not hrp then return 0 end
	    SD.refresh()
	    local fired = 0
	    for _, c in ipairs(SD.cache.clicks) do
	        if F.is_mine(c) then
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
	                if F.is_mine(p) then
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
	    end

    return acted
end

function F.collect_once()
		local n = 0
		if not SD.caps.fireprompt then return 0 end
		SD.refresh()
		for _, p in ipairs(SD.cache.prompts) do
			if F.is_mine(p) and not is_risky_action(p) then
				local pname = string.lower((p.Name or "") .. " " .. (p.ActionText or "") .. " " .. (p.ObjectText or ""))
				local parentName = p.Parent and string.lower(p.Parent.Name or "") or ""
				local path = ""
				pcall(function() path = string.lower(p:GetFullName()) end)
				local text = pname .. " " .. parentName .. " " .. path
				-- collect is for pickups/drops/rewards/boards/balls only - NEVER sell/upgrade/extractor
				local looks_sell = string.find(text, "sell", 1, true) or string.find(text, "cashout", 1, true) or string.find(text, "exchange", 1, true)
				local looks_upgrade = string.find(text, "upgrade", 1, true) or string.find(text, "buy", 1, true) or string.find(text, "shop", 1, true)
				local looks_extractor = string.find(text, "extractor", 1, true) or string.find(text, "extract", 1, true) or string.find(text, "machine", 1, true) or string.find(text, "processor", 1, true)
				local looks_collect = string.find(text, "collect", 1, true) or string.find(text, "claim", 1, true) or string.find(text, "pickup", 1, true) or string.find(text, "pick up", 1, true) or string.find(text, "grab", 1, true) or string.find(text, "take", 1, true) or string.find(text, "reward", 1, true) or string.find(text, "ball", 1, true) or string.find(text, "drop", 1, true) or string.find(text, "loot", 1, true) or string.find(text, "board", 1, true)
				if not looks_sell and not looks_upgrade and not looks_extractor and looks_collect then
					local ok = pcall(fireproximityprompt, p)
					if ok then n = n + 1 end
				end
			end
		end
		return n
	end

function F.upgrade_once()
		if SD.config.safe_mode then return false end -- upgrades can spend in-game currency; enable explicitly by disabling safe mode? safer to keep opt-in via config
		local t = F.upgrade_target()
		if not t then return false end
		local ok = F.visit(t, { radius = 16, settle = 0.2, allow_teleport = SD.config.auto_sell_teleport == true }) -- reuse teleport permission concept? better separate
		return ok
	end

	function F.rebirth_once()
		-- destructive: only when explicitly enabled (auto_rebirth toggle controls scheduling)
		local t = F.rebirth_target()
		if not t then return false end
		local ok = F.visit(t, { radius = 16, settle = 0.2, allow_teleport = false })
		return ok
	end

function F.goto_crown(opts)
		opts = opts or {}
		local require_active = opts.require_active
		if require_active == nil then require_active = SD.config.tp_crown_only_active end

		local t = F.crown_target({ require_active = require_active })
		if not t then
			-- Only fall back to leaderboard leader when the user explicitly allows
			-- non-event behavior (manual override). Auto TP must not chase players
			-- when no crown event/object is active.
			if not require_active and opts.allow_leader_fallback then
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
			end
			return false
		end
		local ok = F.visit(t, { radius = 18, settle = 0.25, anchor = false })
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
