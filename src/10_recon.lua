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
