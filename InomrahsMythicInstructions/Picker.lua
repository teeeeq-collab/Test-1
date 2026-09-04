--------------------------------------------------------------------------------
-- Picker: choosing a colour.
--
-- A hue strip down one side and a saturation/brightness field beside it, which
-- is the shape asked for. Both are built from solid swatches rather than
-- gradient textures: SetGradient's signature changed in 10.0 and this addon
-- cannot verify from outside the game which form a client wants. A grid of flat
-- colours needs no such API, is exact to click, and costs a few hundred
-- textures once.
--
-- The three sliders are not a fallback for the field but the other half of it:
-- the field is for finding a colour, the sliders for saying exactly which.
--------------------------------------------------------------------------------

local ADDON, IMI = ...

IMI.Picker = {}
local Picker = IMI.Picker
local Color, Util = IMI.Color, IMI.Util

-- Coarse enough to stay cheap, fine enough to land on a colour by eye. The
-- sliders are there for the last step.
local FIELD_COLS, FIELD_ROWS = 24, 16
local HUE_STEPS = 32
local CELL = 9
local STRIP_W = 18

local frame

--- A marker that stays visible on whatever colour it lands on: a light outline
--- with a dark one just inside it. Drawn from plain textures like everything
--- else here, so there is no art path to be wrong about, and it takes no mouse
--- input so the swatch underneath still receives the click.
local function marker(parent, w, h)
    local m = CreateFrame("Frame", nil, parent)
    m:SetSize(w, h)
    m:SetFrameLevel((parent:GetFrameLevel() or 1) + 5)
    IMI.Style.Border(m, { 0, 0, 0, 0.85 }, 3)
    IMI.Style.Border(m, { 1, 1, 1, 1 }, 1)
    return m
end

local function swatchGrid(parent, cols, rows, cellW, cellH, onPick)
    local grid = CreateFrame("Button", nil, parent)
    grid:SetSize(cols * cellW, rows * cellH)
    grid.cells = {}

    for row = 1, rows do
        for col = 1, cols do
            local tex = grid:CreateTexture(nil, "ARTWORK")
            tex:SetSize(cellW, cellH)
            tex:SetPoint("TOPLEFT", (col - 1) * cellW, -(row - 1) * cellH)
            grid.cells[(row - 1) * cols + col] = tex
        end
    end

    -- Which cell was clicked, from where the cursor is inside the grid. The
    -- same arithmetic as the sidebar drop, and split out for the same reason:
    -- it is the part that can be got wrong and the part that can be tested.
    grid:SetScript("OnClick", function(self)
        local x, y = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        local left, top = self:GetLeft(), self:GetTop()
        if type(x) ~= "number" or type(scale) ~= "number" or scale == 0
            or type(left) ~= "number" or type(top) ~= "number" then
            return
        end

        local col, row = Picker.CellAt(x / scale - left, top - y / scale,
            cellW, cellH, cols, rows)
        onPick(col, row)
    end)

    return grid
end

--- Where the marker sits on the hue strip, measured down from its top.
---
--- The strip runs 0 at the top to 360 at the bottom, so this is the same
--- mapping the strip's own colours use — written once, so the marker cannot
--- point at a different hue from the one under it.
function Picker.HueOffset(hue, height)
    return ((tonumber(hue) or 0) % 360) / 360 * height
end

--- Where the marker sits on the field: saturation across, brightness down.
function Picker.FieldOffset(s, v, width, height)
    return (s or 0) * width, (1 - (v or 0)) * height
end

--- Which cell of a grid a point falls in, counting from 1 and clamped to the
--- grid. Pure arithmetic, so the one part of clicking a colour that can be off
--- by one is testable without a client.
function Picker.CellAt(x, y, cellW, cellH, cols, rows)
    local col = math.floor((x or 0) / cellW) + 1
    local row = math.floor((y or 0) / cellH) + 1
    if col < 1 then col = 1 elseif col > cols then col = cols end
    if row < 1 then row = 1 elseif row > rows then row = rows end
    return col, row
end

--- Saturation left to right, brightness top to bottom, at the chosen hue.
function Picker.FieldColor(col, row, hue)
    local s = (col - 0.5) / FIELD_COLS
    local v = 1 - (row - 0.5) / FIELD_ROWS
    return s, v, Color.HSVtoRGB(hue, s, v)
end

local function build()
    if frame then return frame end

    local blocker = CreateFrame("Frame", "InomrahsMIPicker", IMI.UI.root)
    blocker:SetAllPoints(IMI.UI.root)
    blocker:SetFrameStrata("FULLSCREEN_DIALOG")
    blocker:EnableMouse(true)
    blocker:Hide()

    local d = CreateFrame("Frame", nil, blocker)
    d:SetSize(FIELD_COLS * CELL + STRIP_W + 210, FIELD_ROWS * CELL + 96)
    d:SetPoint("CENTER", IMI.UI.root, "CENTER", 0, 0)
    d:SetFrameStrata("FULLSCREEN_DIALOG")
    d:SetFrameLevel(blocker:GetFrameLevel() + 10)
    IMI.Style.Panel(d, IMI.Style.colors.dialog)

    d.title = IMI.Style.Header(d, "")
    d.title:SetPoint("TOP", 0, -10)

    d.state = { h = 0, s = 1, v = 1 }

    -- The field ------------------------------------------------------------
    d.field = swatchGrid(d, FIELD_COLS, FIELD_ROWS, CELL, CELL, function(col, row)
        local s, v = Picker.FieldColor(col, row, d.state.h)
        d.state.s, d.state.v = s, v
        d:Apply()
    end)
    d.field:SetPoint("TOPLEFT", 14, -34)

    -- The hue strip --------------------------------------------------------
    d.hue = swatchGrid(d, 1, HUE_STEPS, STRIP_W, FIELD_ROWS * CELL / HUE_STEPS,
        function(_, row)
            d.state.h = (row - 0.5) / HUE_STEPS * 360
            d:Repaint()
            d:Apply()
        end)
    d.hue:SetPoint("TOPLEFT", d.field, "TOPRIGHT", 8, 0)
    for i = 1, HUE_STEPS do
        d.hue.cells[i]:SetColorTexture(Color.HSVtoRGB((i - 0.5) / HUE_STEPS * 360, 1, 1))
    end

    -- Which hue is current, and where on the field the colour sits. The picker
    -- worked without these; it just could not tell you where you were.
    d.hueMarker = marker(d.hue, STRIP_W + 6, 5)
    d.fieldMarker = marker(d.field, 11, 11)

    -- The result -----------------------------------------------------------
    d.swatchFrame = CreateFrame("Frame", nil, d)
    d.swatchFrame:SetSize(56, 32)
    d.swatchFrame:SetPoint("TOPLEFT", d.hue, "TOPRIGHT", 12, 0)
    d.swatch = d.swatchFrame:CreateTexture(nil, "ARTWORK")
    d.swatch:SetAllPoints()
    IMI.Style.Border(d.swatchFrame, IMI.Style.colors.rowEdge)

    -- The sliders ----------------------------------------------------------
    local function sliderRow(labelText, y, maxValue, get, set)
        local row = {}
        row.label = IMI.Style.Label(d, labelText)
        row.label:SetPoint("TOPLEFT", d.hue, "TOPRIGHT", 12, y)

        row.slider = CreateFrame("Slider", nil, d, "OptionsSliderTemplate")
        row.slider:SetPoint("TOPLEFT", d.hue, "TOPRIGHT", 12, y - 14)
        row.slider:SetWidth(120)
        -- Given a height rather than left to the template's. Three rows spaced
        -- by hand against a height nobody stated is a layout that moves when
        -- Blizzard changes the template.
        row.slider:SetHeight(17)
        row.slider:SetMinMaxValues(0, maxValue)
        row.slider:SetValueStep(1)
        row.slider:SetObeyStepOnDrag(true)
        -- The slider template's own labels. Cleared because the row has its
        -- own label and a number box; typed rather than tested for truthiness,
        -- since an absent field is not always nil.
        for _, field in ipairs({ "Low", "High", "Text" }) do
            if type(row.slider[field]) == "table" then row.slider[field]:SetText("") end
        end

        row.box = CreateFrame("EditBox", nil, d)
        row.box:SetFontObject("ChatFontNormal")
        IMI.Style.EditBox(row.box)
        row.box:SetSize(44, 18)
        row.box:SetPoint("LEFT", row.slider, "RIGHT", 10, 0)
        row.box:SetAutoFocus(false)
        row.box:SetNumeric(true)
        row.box:SetMaxLetters(3)

        row.slider:SetScript("OnValueChanged", function(self, value)
            if self.updating then return end
            set(value)
            d:Repaint()
            d:Apply()
        end)

        local function commit(self)
            set(tonumber(self:GetText()) or 0)
            self:ClearFocus()
            d:Repaint()
            d:Apply()
        end
        row.box:SetScript("OnEnterPressed", commit)
        row.box:SetScript("OnEditFocusLost", commit)

        row.get = get
        return row
    end

    d.rows = {
        hue = sliderRow("Hue", -44, 360,
            function() return d.state.h end,
            function(value) d.state.h = value % 360 end),
        sat = sliderRow("Saturation", -84, 100,
            function() return d.state.s * 100 end,
            function(value) d.state.s = value / 100 end),
        val = sliderRow("Brightness", -124, 100,
            function() return d.state.v * 100 end,
            function(value) d.state.v = value / 100 end),
    }

    -- Buttons --------------------------------------------------------------
    d.reset = IMI.UI.PanelButton(d, "Reset", 76, 22, function()
        if d.onReset then d.onReset() end
        d:Hide2()
    end, { tip = "Back to the addon's own colour" })
    d.reset:SetPoint("BOTTOMLEFT", 14, 12)

    d.close = IMI.UI.PanelButton(d, "Done", 76, 22, function() d:Hide2() end)
    d.close:SetPoint("BOTTOMRIGHT", -14, 12)

    --- Redraws the field for the current hue, and the controls for the current
    --- colour. Guarded against feeding a slider's own change back into it,
    --- which otherwise ends in a loop of tiny rounding steps.
    function d:Repaint()
        for row = 1, FIELD_ROWS do
            for col = 1, FIELD_COLS do
                local _, _, r, g, b = Picker.FieldColor(col, row, self.state.h)
                self.field.cells[(row - 1) * FIELD_COLS + col]:SetColorTexture(r, g, b)
            end
        end

        local r, g, b = Color.HSVtoRGB(self.state.h, self.state.s, self.state.v)
        self.swatch:SetColorTexture(r, g, b)

        local fieldW, fieldH = FIELD_COLS * CELL, FIELD_ROWS * CELL
        local mx, my = Picker.FieldOffset(self.state.s, self.state.v, fieldW, fieldH)
        self.fieldMarker:ClearAllPoints()
        self.fieldMarker:SetPoint("CENTER", self.field, "TOPLEFT", mx, -my)

        self.hueMarker:ClearAllPoints()
        self.hueMarker:SetPoint("CENTER", self.hue, "TOP", 0,
            -Picker.HueOffset(self.state.h, fieldH))

        for _, row in pairs(self.rows) do
            local value = row.get()
            row.slider.updating = true
            row.slider:SetValue(value)
            row.slider.updating = false
            row.box:SetText(tostring(math.floor(value + 0.5)))
        end
    end

    function d:Apply()
        if self.onChange then
            self.onChange(Color.Pack(Color.HSVtoRGB(self.state.h, self.state.s, self.state.v)))
        end
    end

    function d:Hide2() blocker:Hide() end

    blocker.dialog = d
    frame = blocker

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "InomrahsMIPicker")
    end
    return frame
end

--- Opens the picker on a colour, calling back on every change and on reset.
---
--- Live rather than an OK button: the whole point is seeing the colour on the
--- interface it will be used on, and a preview swatch cannot show that.
function Picker.Open(opts)
    opts = opts or {}
    local blocker = build()
    local d = blocker.dialog

    d.title:SetText(opts.title or "Colour")
    d.onChange = opts.onChange
    d.onReset = opts.onReset

    local start = opts.color
    if IMI.Color.Valid(start) then
        d.state.h, d.state.s, d.state.v = Color.RGBtoHSV(start[1], start[2], start[3])
    else
        d.state.h, d.state.s, d.state.v = 40, 0.62, 0.78
    end

    d.reset:SetShown(opts.onReset ~= nil)
    d:Repaint()
    blocker:Show()
    return blocker
end

function Picker.Frame() return frame end
