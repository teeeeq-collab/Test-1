--------------------------------------------------------------------------------
-- Style: the look.
--
-- Everything is drawn from plain textures rather than Blizzard's button and
-- backdrop templates. Two reasons: UIPanelButtonTemplate is where the maroon
-- stone buttons come from, which is most of why this did not resemble the
-- reference; and template mixing has already broken this addon twice, so
-- frames that must stay secure inherit their secure template and gain their
-- appearance from here instead.
--------------------------------------------------------------------------------

local ADDON, IMI = ...

IMI.Style = {}
local Style = IMI.Style

-- Dark blue-grey grounds, a gold rule around anything that is a panel, and one
-- warm accent reserved for "this is the thing you have selected". The accent
-- earns its loudness by being the only saturated colour on screen.
Style.colors = {
    window      = { 0.055, 0.055, 0.075, 0.96 },
    panel       = { 0.085, 0.085, 0.115, 0.98 },
    bar         = { 0.10,  0.09,  0.13,  1.00 },
    -- Fully opaque, unlike the window: a question you must answer should not
    -- show the thing it is asking about faintly through itself.
    dialog      = { 0.07,  0.07,  0.095, 1.00 },

    gold        = { 0.78,  0.63,  0.30,  1.00 },
    goldText    = { 1.00,  0.82,  0.20,  1.00 },

    row         = { 0.135, 0.135, 0.175, 1.00 },
    rowHover    = { 0.185, 0.185, 0.235, 1.00 },
    rowEdge     = { 0.26,  0.26,  0.33,  1.00 },

    accent      = { 0.88,  0.54,  0.12,  1.00 },
    accentHover = { 0.95,  0.62,  0.18,  1.00 },
    onAccent    = { 0.10,  0.08,  0.05,  1.00 },

    text        = { 0.88,  0.88,  0.91,  1.00 },
    textDim     = { 0.55,  0.55,  0.60,  1.00 },
    danger      = { 0.85,  0.32,  0.28,  1.00 },
}

--------------------------------------------------------------------------------
-- The live palette
--
-- Style.colors is the palette as shipped and never changes. Style.active is
-- what is actually drawn, and is Style.colors with two kinds of override laid
-- over it: the user's own choices from Settings, and the colour of whichever
-- dungeon is open. Everything that draws reads Style.active, so a change is one
-- table swap and a retint rather than a hunt through call sites.
--------------------------------------------------------------------------------

-- The keys a user may override. Anything not here is structural.
Style.THEMED = { "gold", "goldText", "accent", "text", "textDim" }

Style.active = {}

local userColors, dungeonColor = {}, nil

local function unpackColor(c) return c[1], c[2], c[3], c[4] or 1 end

--- Starts the live palette off as the palette as shipped. Retint replaces it
--- properly once Color is loaded; this is what keeps the first frames drawn
--- during load from reading an empty table.
for key, value in pairs(Style.colors) do Style.active[key] = value end

--------------------------------------------------------------------------------
-- Text scale
--
-- Every font string and edit box this file makes is remembered, so one setting
-- can resize all of them. Without the register the setting could only reach the
-- text Runtime happened to set a font on, which was the callout buttons and
-- nothing else.
--------------------------------------------------------------------------------

local scaled = {}
local currentTextScale = 1

--- Sets a font string's size from the text scale.
---
--- The unscaled size is remembered the first time. Reading the current size and
--- multiplying by the scale looks equivalent and is not: these outlive a
--- rebuild, so each pass would multiply an already-scaled size again and the
--- text would grow without limit.
function Style.ApplyTextScale(fs, scale)
    if not fs then return end

    if not fs.baseFont then
        local file, size, flags = fs:GetFont()
        if not (file and size) then return end
        fs.baseFont = { file = file, size = size, flags = flags }
    end

    local base = fs.baseFont
    fs:SetFont(base.file, base.size * (scale or 1), base.flags)
end

--- Remembers a font string so the scale can reach it later, and brings it to
--- the scale already in force — a frame built after the setting was changed
--- must not come up at the wrong size.
function Style.Scaled(fs)
    if not fs then return fs end
    scaled[#scaled + 1] = fs
    if currentTextScale ~= 1 then Style.ApplyTextScale(fs, currentTextScale) end
    return fs
end

function Style.SetTextScale(scale)
    currentTextScale = tonumber(scale) or 1
    for _, fs in ipairs(scaled) do Style.ApplyTextScale(fs, currentTextScale) end
    return currentTextScale
end

function Style.TextScale() return currentTextScale end

--------------------------------------------------------------------------------
-- What has been drawn, so it can be drawn again in a new colour
--------------------------------------------------------------------------------

local borders, headers, buttons = {}, {}, {}

--- Recomputes the live palette and repaints everything already on screen.
---
--- A dungeon's colour is one colour, not a palette, so the rest is derived from
--- it: the rule around the panels takes it directly, headings take a readable
--- version of it, and selection takes it with a brighter hover shade. Picking
--- five colours to describe one dungeon is not a thing anyone wants to do.
function Style.Retint()
    local Color = IMI.Color

    for key, value in pairs(Style.colors) do Style.active[key] = value end
    for key, value in pairs(userColors) do
        if Color.Valid(value) then Style.active[key] = value end
    end

    if Color.Valid(dungeonColor) then
        Style.active.gold        = dungeonColor
        Style.active.goldText    = Color.ForText(dungeonColor)
        Style.active.accent      = dungeonColor
        Style.active.accentHover = Color.Shade(dungeonColor, 1.15)
    else
        Style.active.accentHover = Style.active.accentHover or Style.colors.accentHover
    end

    for _, edges in ipairs(borders) do
        for _, tex in ipairs(edges.list) do
            tex:SetColorTexture(unpackColor(Style.active[edges.key] or Style.colors.gold))
        end
    end

    for _, fs in ipairs(headers) do
        fs:SetTextColor(unpackColor(Style.active.goldText))
    end

    for _, b in ipairs(buttons) do
        if b.Repaint then b:Repaint() end
    end
end

--- The user's own palette, from Settings. Nil for a key means "as shipped".
function Style.SetUserColor(key, color)
    userColors[key] = color
    Style.Retint()
end

function Style.UserColor(key) return userColors[key] end

function Style.ResetUserColors()
    userColors = {}
    Style.Retint()
end

function Style.LoadUserColors(stored)
    userColors = {}
    if type(stored) == "table" then
        for key, value in pairs(stored) do
            if IMI.Color.Valid(value) then userColors[key] = value end
        end
    end
    Style.Retint()
end

--- The colour of whichever dungeon is open, or nil for none.
function Style.SetDungeonColor(color)
    dungeonColor = IMI.Color.Valid(color) and color or nil
    Style.Retint()
end

function Style.DungeonColor() return dungeonColor end

--------------------------------------------------------------------------------
-- Primitives
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Opacity
--
-- Applied to the grounds only, never to the frame. SetAlpha on the window fades
-- everything inside it, so a see-through window came with see-through text and
-- a see-through rule around every button — which is the opposite of what fading
-- the window is for. You want to see the fight through it and still read it.
--------------------------------------------------------------------------------

local grounds = {}
local currentOpacity = 1

--- Remembers a texture as a background, so opacity can reach it, and brings it
--- to the opacity already in force.
function Style.Ground(tex)
    if not tex then return tex end
    grounds[#grounds + 1] = tex
    if currentOpacity ~= 1 then tex:SetAlpha(currentOpacity) end
    return tex
end

function Style.SetOpacity(value)
    currentOpacity = tonumber(value) or 1
    for _, tex in ipairs(grounds) do tex:SetAlpha(currentOpacity) end
    return currentOpacity
end

function Style.Opacity() return currentOpacity end

function Style.Background(frame, color, layer)
    local tex = frame:CreateTexture(nil, layer or "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(unpackColor(color))
    -- Alpha here is separate from the colour's own alpha, so a button
    -- repainting itself on hover cannot undo it.
    return Style.Ground(tex)
end

--- A one-pixel rule, drawn as four thin textures.
---
--- Deliberately not a backdrop: this needs no template, cannot conflict with a
--- secure one, and behaves the same on every frame it is given.
--- @param key  which palette entry this rule follows, so a retint knows what
---              colour to give it. Defaults to the gold rule around panels.
function Style.Border(frame, color, thickness, key)
    thickness = thickness or 1
    local edges = {}

    local function edge(p1, p2, w, h)
        local tex = frame:CreateTexture(nil, "BORDER")
        tex:SetColorTexture(unpackColor(color))
        tex:SetPoint(p1)
        tex:SetPoint(p2)
        if w then tex:SetWidth(w) end
        if h then tex:SetHeight(h) end
        edges[#edges + 1] = tex
        return tex
    end

    edge("TOPLEFT", "TOPRIGHT", nil, thickness)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, thickness)
    edge("TOPLEFT", "BOTTOMLEFT", thickness, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", thickness, nil)

    frame.borderEdges = edges
    if key then borders[#borders + 1] = { list = edges, key = key } end
    return edges
end

function Style.SetBorderColor(frame, color)
    for _, tex in ipairs(frame.borderEdges or {}) do
        tex:SetColorTexture(unpackColor(color))
    end
end

--- A panel: dark ground, gold rule. Used for the window and each column.
function Style.Panel(frame, color)
    Style.Background(frame, color or Style.colors.panel)
    -- Follows the palette: this is the rule a dungeon's colour is most visible
    -- on, and the one Settings calls "panel edge".
    Style.Border(frame, Style.active.gold or Style.colors.gold, 1, "gold")
    return frame
end

--- Centred gold heading, as sits above each column in the reference.
function Style.Header(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetText(text or "")
    fs:SetTextColor(unpackColor(Style.active.goldText or Style.colors.goldText))
    headers[#headers + 1] = fs
    return Style.Scaled(fs)
end

function Style.Label(parent, text, dim)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetText(text or "")
    fs:SetTextColor(unpackColor(dim and (Style.active.textDim or Style.colors.textDim)
                                    or (Style.active.text or Style.colors.text)))
    return Style.Scaled(fs)
end

--------------------------------------------------------------------------------
-- Buttons
--------------------------------------------------------------------------------

--- Gives a plain Button the addon's appearance, and the handful of methods the
--- rest of the code expects from Blizzard's template: SetText, SetEnabled and
--- the highlight pair used to show selection.
---
--- The selected state is a solid accent fill with dark text, which is the one
--- piece of loud colour in the whole interface and the only thing it means.
function Style.Button(b, text, opts)
    opts = opts or {}

    local bg = Style.Background(b, Style.colors.row)
    Style.Border(b, Style.colors.rowEdge)
    buttons[#buttons + 1] = b

    local label = b:CreateFontString(nil, "OVERLAY",
        opts.font or "GameFontNormalSmall")
    if opts.justify == "LEFT" then
        label:SetPoint("LEFT", 8, 0)
        label:SetPoint("RIGHT", -6, 0)
        label:SetJustifyH("LEFT")
    else
        label:SetAllPoints()
    end

    -- A label anchored on both sides wraps when the text is too long, and a
    -- button is a fixed height, so the extra lines spill out over whatever is
    -- underneath. A long dungeon name did exactly that to the two rows below
    -- it in the sidebar.
    --
    -- So a label is held to a line count and ends in an ellipsis past it. One
    -- line is the default; a caller that has made room for more says how many,
    -- and is then responsible for the height that needs.
    local maxLines = opts.maxLines or 1
    label:SetWordWrap(maxLines > 1)
    label:SetMaxLines(maxLines)

    label:SetText(text or "")
    label:SetTextColor(unpackColor(Style.colors.text))

    Style.Scaled(label)

    b.bg, b.label = bg, label
    b.selected, b.enabled = false, true
    -- Read from the button rather than the options table it was built with, so
    -- a reused button can become the dangerous one and back again.
    b.danger = opts.danger

    local function repaint()
        -- Read live rather than captured, so a palette change repaints instead
        -- of needing every button rebuilt.
        local palette = Style.active
        if not b.enabled then
            bg:SetColorTexture(unpackColor(Style.colors.row))
            label:SetTextColor(unpackColor(palette.textDim or Style.colors.textDim))
            Style.SetBorderColor(b, Style.colors.rowEdge)
        elseif b.selected then
            bg:SetColorTexture(unpackColor(
                b.hovered and (palette.accentHover or Style.colors.accentHover)
                          or (palette.accent or Style.colors.accent)))
            label:SetTextColor(unpackColor(Style.colors.onAccent))
            Style.SetBorderColor(b, palette.accent or Style.colors.accent)
        else
            bg:SetColorTexture(unpackColor(
                b.hovered and Style.colors.rowHover or Style.colors.row))
            label:SetTextColor(unpackColor(
                b.danger and Style.colors.danger or (palette.text or Style.colors.text)))
            Style.SetBorderColor(b, Style.colors.rowEdge)
        end
    end

    b.Repaint = repaint

    b:SetScript("OnEnter", function(self) self.hovered = true; repaint() end)
    b:SetScript("OnLeave", function(self) self.hovered = false; repaint() end)

    b.SetText = function(self, value) label:SetText(value or "") end
    b.GetText = function() return label:GetText() end

    local nativeSetEnabled = b.SetEnabled
    b.SetEnabled = function(self, enabled)
        self.enabled = not not enabled
        if nativeSetEnabled then nativeSetEnabled(self, enabled) end
        repaint()
    end

    b.SetDanger = function(self, on)
        self.danger = not not on
        repaint()
    end

    -- The rest of the addon shows selection through these, so they keep their
    -- names and change what selection looks like rather than how it is said.
    b.LockHighlight   = function(self) self.selected = true;  repaint() end
    b.UnlockHighlight = function(self) self.selected = false; repaint() end

    repaint()
    return b
end

--- A one-line label on hover, saying what a button does.
---
--- Hooked rather than set, because every styled button already owns OnEnter and
--- OnLeave for its hover colour and replacing those would leave buttons that
--- never light up. Guarded on GameTooltip existing so this stays testable
--- outside the client, where there is no tooltip to borrow.
function Style.Tooltip(frame, text, detail)
    if not frame or not text then return frame end
    frame.tooltipText = text
    frame.tooltipDetail = detail

    if frame.hasTooltip then return frame end
    frame.hasTooltip = true

    frame:HookScript("OnEnter", function(self)
        if type(GameTooltip) ~= "table" or not self.tooltipText then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltipText, 1, 1, 1)
        if self.tooltipDetail then
            -- Wrapped, because the second line is the "why", and a long one
            -- running off the screen edge helps nobody.
            GameTooltip:AddLine(self.tooltipDetail, 0.7, 0.7, 0.75, true)
        end
        GameTooltip:Show()
    end)

    frame:HookScript("OnLeave", function()
        if type(GameTooltip) == "table" then GameTooltip:Hide() end
    end)

    return frame
end

--- Makes a scroll frame answer the mouse wheel.
---
--- The scroll templates ship with a bar and no wheel, which means a list you
--- can see is too long has to be dragged by a thin bar at its edge. Clamped at
--- both ends rather than left to the client, because a scroll frame will
--- happily scroll past its content and leave the list apparently empty.
function Style.WheelScroll(scroll, step)
    step = step or 24
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local current, range = self:GetVerticalScroll(), self:GetVerticalScrollRange()
        if type(current) ~= "number" or type(range) ~= "number" then return end

        local target = current - (delta or 0) * step
        if target < 0 then target = 0 end
        if target > range then target = range end
        self:SetVerticalScroll(target)
    end)
    return scroll
end

--- Shows a scroll frame's bar only when there is something to scroll.
---
--- A bar for a list that fits is clutter, and these templates put their arrows
--- in the gutter beside the rows where they read as buttons belonging to them.
--- Typed rather than trusted: the field is Blizzard's, and this asks for one by
--- name.
function Style.RefreshScrollBar(scroll, contentHeight)
    local bar = scroll and scroll.ScrollBar
    if type(bar) ~= "table" then return end

    local visible = scroll:GetHeight()
    bar:SetShown(type(visible) == "number" and type(contentHeight) == "number"
        and contentHeight > visible)
end

--- The little box in a button's corner saying which key fires it.
---
--- Sized to its text rather than fixed: "E" and "CTRL+E" are very different
--- widths and a box wide enough for the second wastes a third of a button for
--- the first. A floor keeps a single letter from becoming a sliver.
function Style.KeyBadge(parent)
    local badge = CreateFrame("Frame", nil, parent)
    badge:SetHeight(12)
    badge:SetFrameLevel((parent:GetFrameLevel() or 1) + 3)

    Style.Background(badge, Style.colors.window)
    Style.Border(badge, Style.colors.rowEdge)

    badge.label = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badge.label:SetPoint("CENTER")
    badge.label:SetTextColor(unpackColor(Style.colors.goldText))
    badge.label:SetWordWrap(false)
    badge.label:SetMaxLines(1)
    Style.Scaled(badge.label)

    --- Nil hides it. A badge with nothing in it is a smudge on the corner of a
    --- button, so there is no empty state to draw.
    function badge:SetKey(text)
        if not text or text == "" then
            self:Hide()
            return
        end
        self.label:SetText(text)
        local width = self.label:GetStringWidth()
        if type(width) ~= "number" then width = 24 end
        self:SetWidth(math.max(18, width + 8))
        self:Show()
    end

    badge:Hide()
    return badge
end

--- A read-only row of text, as the note rows in the reference are.
function Style.Row(frame)
    Style.Background(frame, Style.colors.row)
    Style.Border(frame, Style.colors.rowEdge)
    return frame
end

--- Edit boxes lose Blizzard's chunky metal frame and gain the same flat rule as
--- everything else, so a field reads as part of the panel rather than sitting
--- on top of it.
function Style.EditBox(eb)
    -- Registered like a font string: an edit box has the same GetFont/SetFont
    -- pair, and text you are typing into should be the size of the text beside
    -- it.
    Style.Scaled(eb)
    Style.Background(eb, Style.colors.window)
    Style.Border(eb, Style.colors.rowEdge)
    eb:SetTextColor(unpackColor(Style.colors.text))
    eb:SetTextInsets(6, 6, 0, 0)

    eb:HookScript("OnEditFocusGained", function(self)
        Style.SetBorderColor(self, Style.colors.accent)
    end)
    eb:HookScript("OnEditFocusLost", function(self)
        Style.SetBorderColor(self, Style.colors.rowEdge)
    end)
    return eb
end
