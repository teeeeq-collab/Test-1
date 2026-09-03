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

local function unpackColor(c) return c[1], c[2], c[3], c[4] end

--------------------------------------------------------------------------------
-- Primitives
--------------------------------------------------------------------------------

function Style.Background(frame, color, layer)
    local tex = frame:CreateTexture(nil, layer or "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(unpackColor(color))
    return tex
end

--- A one-pixel rule, drawn as four thin textures.
---
--- Deliberately not a backdrop: this needs no template, cannot conflict with a
--- secure one, and behaves the same on every frame it is given.
function Style.Border(frame, color, thickness)
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
    Style.Border(frame, Style.colors.gold)
    return frame
end

--- Centred gold heading, as sits above each column in the reference.
function Style.Header(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetText(text or "")
    fs:SetTextColor(unpackColor(Style.colors.goldText))
    return fs
end

function Style.Label(parent, text, dim)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetText(text or "")
    fs:SetTextColor(unpackColor(dim and Style.colors.textDim or Style.colors.text))
    return fs
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

    local label = b:CreateFontString(nil, "OVERLAY",
        opts.font or "GameFontNormalSmall")
    if opts.justify == "LEFT" then
        label:SetPoint("LEFT", 8, 0)
        label:SetPoint("RIGHT", -6, 0)
        label:SetJustifyH("LEFT")
    else
        label:SetAllPoints()
    end
    label:SetText(text or "")
    label:SetTextColor(unpackColor(Style.colors.text))

    b.bg, b.label = bg, label
    b.selected, b.enabled = false, true
    -- Read from the button rather than the options table it was built with, so
    -- a reused button can become the dangerous one and back again.
    b.danger = opts.danger

    local function repaint()
        if not b.enabled then
            bg:SetColorTexture(unpackColor(Style.colors.row))
            label:SetTextColor(unpackColor(Style.colors.textDim))
            Style.SetBorderColor(b, Style.colors.rowEdge)
        elseif b.selected then
            bg:SetColorTexture(unpackColor(
                b.hovered and Style.colors.accentHover or Style.colors.accent))
            label:SetTextColor(unpackColor(Style.colors.onAccent))
            Style.SetBorderColor(b, Style.colors.accent)
        else
            bg:SetColorTexture(unpackColor(
                b.hovered and Style.colors.rowHover or Style.colors.row))
            label:SetTextColor(unpackColor(
                b.danger and Style.colors.danger or Style.colors.text))
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
