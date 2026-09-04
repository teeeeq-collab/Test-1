--------------------------------------------------------------------------------
-- Binds: giving a page's callouts keys.
--
-- A key belongs to a page. The same key calls a different callout on each page
-- of a route, which is what makes paging worth having: one hand position for a
-- whole dungeon instead of eighteen numpad positions to remember.
--
-- The two paging keys are the exception and are global, because a key that
-- turned the page on one page and did nothing on the next would be worse than
-- no key at all.
--
-- Capturing a key means taking the keyboard for as long as the dialog is open.
-- That is done only out of combat, only while a row is waiting, and it always
-- lets Escape through: an addon that can swallow an interrupt is not one to
-- have open in a key.
--------------------------------------------------------------------------------

local ADDON, IMI = ...

IMI.Binds = {}
local Binds = IMI.Binds
local Core, Util = IMI.Core, IMI.Util

local ROW_H, VISIBLE = 24, 9

-- Keys the client needs more than this addon does. Binding any of them would
-- take away something you cannot get back without a reload.
local REFUSED = {
    ESCAPE = true, ENTER = true, ["NUMPADENTER"] = true,
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, UNKNOWN = true,
}

local frame, waitingRow

--- The key as WoW names it, with the modifiers held at the time.
---
--- Modifier order is fixed rather than however they happen to be read, because
--- "SHIFT-CTRL-1" and "CTRL-SHIFT-1" are the same chord to a person and two
--- different strings to a table lookup.
function Binds.Chord(key, shift, ctrl, alt)
    if not key or REFUSED[key] then return nil end

    local prefix = ""
    if alt   then prefix = prefix .. "ALT-" end
    if ctrl  then prefix = prefix .. "CTRL-" end
    if shift then prefix = prefix .. "SHIFT-" end
    return prefix .. key
end

-- Long key names would make the badge on a button wider than the button. Only
-- the ones that actually appear on a keyboard are shortened; anything else is
-- left alone rather than mangled into something unrecognisable.
local SHORT = {
    MOUSEWHEELUP = "MWUp", MOUSEWHEELDOWN = "MWDn",
    BUTTON3 = "M3", BUTTON4 = "M4", BUTTON5 = "M5",
    PAGEUP = "PgUp", PAGEDOWN = "PgDn",
    INSERT = "Ins", DELETE = "Del", HOME = "Home", END = "End",
    SPACE = "Spc", BACKSPACE = "Bksp", CAPSLOCK = "Caps", TAB = "Tab",
}

--- A key as it should read on a badge: "CTRL-E" becomes "CTRL+E", which is how
--- people write a chord, and long names are shortened so the badge stays
--- narrower than the button it sits on.
function Binds.Short(key)
    if type(key) ~= "string" or key == "" then return nil end

    local parts = {}
    for part in key:gmatch("[^-]+") do
        local piece = SHORT[part] or part
        if piece:match("^NUMPAD") then piece = "N" .. piece:sub(7) end
        parts[#parts + 1] = piece
    end
    return table.concat(parts, "+")
end

--- Everything on a page that can take a key, in the order it is drawn, plus the
--- two paging entries. One list so the dialog has no special cases in it.
function Binds.Rows(catId, pageId)
    local rows = {}

    for _, enemy in ipairs(Core.PageEnemies(catId, pageId)) do
        for _, line in ipairs(enemy.lines) do
            rows[#rows + 1] = {
                kind = "line",
                id = line.id,
                enemy = enemy.name,
                label = Util.ButtonLabel(line, 40),
                key = Core.LineBind(catId, pageId, line.id),
            }
        end
    end

    local settings = Core.Settings()
    rows[#rows + 1] = { kind = "next", enemy = "All pages",
                        label = "Next page", key = settings.pageNextKey }
    rows[#rows + 1] = { kind = "prev", enemy = "All pages",
                        label = "Previous page", key = settings.pagePrevKey }
    return rows
end

--- Which row, if any, already answers to this key. Paging keys count against
--- every page, so they conflict with a callout on any of them.
function Binds.Conflict(rows, key, exceptIndex)
    -- No key conflicts with nothing. Without this an unset row matched every
    -- other unset row, so clearing a key reported a clash with all of them.
    if key == nil or key == "" then return nil end

    for i, row in ipairs(rows) do
        if i ~= exceptIndex and row.key == key then return i, row end
    end
    return nil
end

local function stopWaiting()
    if not frame then return end
    frame.dialog:EnableKeyboard(false)
    if waitingRow then waitingRow.button:SetText(waitingRow.data.key or "Set") end
    waitingRow = nil
    frame.dialog.help:SetText(
        "|cffaaaaaaClick Set, then press the key. Right-click a key to clear it.|r")
end

local function assign(catId, pageId, row, key)
    if row.kind == "line" then
        Core.SetLineBind(catId, pageId, row.id, key)
    else
        local settings = Core.Settings()
        if row.kind == "next" then settings.pageNextKey = key else settings.pagePrevKey = key end
        IMI.Runtime.SetPageKeys(settings.pageNextKey, settings.pagePrevKey)
    end
end

local function build()
    if frame then return frame end

    local blocker = CreateFrame("Frame", "InomrahsMIBinds", IMI.UI.root)
    blocker:SetAllPoints(IMI.UI.root)
    blocker:SetFrameStrata("FULLSCREEN_DIALOG")
    blocker:EnableMouse(true)
    blocker:Hide()

    local d = CreateFrame("Frame", nil, blocker)
    d:SetSize(430, VISIBLE * ROW_H + 96)
    d:SetPoint("CENTER", IMI.UI.root, "CENTER", 0, 0)
    d:SetFrameStrata("FULLSCREEN_DIALOG")
    d:SetFrameLevel(blocker:GetFrameLevel() + 10)
    IMI.Style.Panel(d, IMI.Style.colors.dialog)

    d.title = IMI.Style.Header(d, "Keybinds")
    d.title:SetPoint("TOP", 0, -10)

    d.help = IMI.Style.Label(d, "")
    d.help:SetPoint("TOPLEFT", 14, -30)
    d.help:SetPoint("TOPRIGHT", -14, -30)
    d.help:SetJustifyH("LEFT")

    local scroll = CreateFrame("ScrollFrame", nil, d, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -50)
    scroll:SetPoint("BOTTOMRIGHT", -30, 42)
    IMI.Style.WheelScroll(scroll, ROW_H)

    d.list = CreateFrame("Frame", nil, scroll)
    d.list:SetSize(380, ROW_H)
    scroll:SetScrollChild(d.list)
    d.scroll = scroll
    d.rows = {}

    d.close = IMI.UI.PanelButton(d, "Done", 76, 22, function()
        stopWaiting()
        blocker:Hide()
    end)
    d.close:SetPoint("BOTTOMRIGHT", -14, 12)

    d.clearAll = IMI.UI.PanelButton(d, "Clear this page", 110, 22, function()
        stopWaiting()
        for _, row in ipairs(Binds.Rows(d.catId, d.pageId)) do
            if row.kind == "line" then Core.SetLineBind(d.catId, d.pageId, row.id, nil) end
        end
        Binds.Refresh()
        Util.Print("keys cleared for this page.")
    end, { tip = "Clear this page",
           tipDetail = "The two paging keys are kept: they belong to every page." })
    d.clearAll:SetPoint("BOTTOMLEFT", 14, 12)

    -- The keyboard is taken only while a row is waiting, and given straight
    -- back. Escape always reaches the client.
    d:SetScript("OnKeyDown", function(self, key)
        if not waitingRow then return end
        if key == "ESCAPE" then
            stopWaiting()
            return
        end

        local chord = Binds.Chord(key, IsShiftKeyDown(), IsControlKeyDown(), IsAltKeyDown())
        if not chord then return end   -- a bare modifier, or a key worth keeping

        local rows = Binds.Rows(self.catId, self.pageId)
        local clashIndex, clash = Binds.Conflict(rows, chord, waitingRow.index)
        if clash then
            assign(self.catId, self.pageId, clash, nil)
            Util.Print(("|cffffff00%s|r taken from %s."):format(chord, clash.label))
        end

        assign(self.catId, self.pageId, waitingRow.data, chord)
        stopWaiting()
        Binds.Refresh()
    end)

    blocker.dialog = d
    frame = blocker

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "InomrahsMIBinds")
    end
    return frame
end

--- Redraws the list against what is stored.
function Binds.Refresh()
    if not frame or not frame:IsShown() then return end
    local d = frame.dialog
    local rows = Binds.Rows(d.catId, d.pageId)

    for _, row in ipairs(d.rows) do row.frame:Hide() end

    for i, data in ipairs(rows) do
        local row = d.rows[i]
        if not row then
            row = {}
            row.frame = CreateFrame("Frame", nil, d.list)
            row.frame:SetSize(370, ROW_H - 2)

            row.name = IMI.Style.Label(row.frame, "")
            row.name:SetPoint("LEFT", 4, 0)
            row.name:SetWidth(250)
            row.name:SetJustifyH("LEFT")
            row.name:SetWordWrap(false)
            row.name:SetMaxLines(1)

            row.button = IMI.UI.PanelButton(row.frame, "Set", 100, 20)
            row.button:SetPoint("RIGHT", -4, 0)
            row.button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

            d.rows[i] = row
        end

        row.frame:ClearAllPoints()
        row.frame:SetPoint("TOPLEFT", d.list, "TOPLEFT", 0, -(i - 1) * ROW_H)
        row.name:SetText(("|cff%s%s|r  %s")
            :format(data.kind == "line" and "ffd200" or "8f7fe8",
                    data.enemy, data.label))
        row.button:SetText(data.key or "Set")

        row.button:SetScript("OnClick", function(self, mouseButton)
            stopWaiting()
            if mouseButton == "RightButton" then
                assign(d.catId, d.pageId, data, nil)
                Binds.Refresh()
                return
            end

            waitingRow = { data = data, button = self, index = i }
            self:SetText("press a key")
            d.help:SetText("|cffffd200Press a key. Escape cancels.|r")
            d:EnableKeyboard(true)
        end)

        row.frame:Show()
    end

    for i = #rows + 1, #d.rows do d.rows[i].frame:Hide() end

    d.list:SetHeight(math.max(ROW_H, #rows * ROW_H))
    IMI.Style.RefreshScrollBar(d.scroll, #rows * ROW_H)
end

--- Opens the dialog for one page.
---
--- Refused in combat: assigning a key writes attributes and override bindings,
--- and neither is allowed mid-fight. Nothing is half-applied by trying.
function Binds.Open(catId, pageId)
    if InCombatLockdown() then
        Util.Print("|cffff4444can't change keys in combat.|r")
        return false
    end
    if not catId or not pageId then
        Util.Print("|cffff4444pick a page first.|r")
        return false
    end

    -- Keys pointing at deleted lines would otherwise sit in the list with
    -- nothing to fire.
    Core.PruneBinds(catId, pageId)

    local blocker = build()
    local d = blocker.dialog
    d.catId, d.pageId = catId, pageId

    local page = Core.GetPage(catId, pageId)
    d.title:SetText(("Keybinds — %s"):format(page and page.name or "page"))

    blocker:Show()
    stopWaiting()
    Binds.Refresh()
    return true
end

function Binds.Frame() return frame end
function Binds.Waiting() return waitingRow end
