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
