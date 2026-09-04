--------------------------------------------------------------------------------
-- UI: the frame, the sidebar, and the views.
--
-- Layout is a sidebar and a content panel. The sidebar always lists the
-- dungeons, with creating one and going back pinned to the bottom, so the list
-- of what exists is never more than a glance away and creating a dungeon is
-- never buried inside editing one.
--
-- Run and Edit both fill the content panel; what differs is whether the cards
-- in it are pressable or editable.
--------------------------------------------------------------------------------

local ADDON, IMI = ...

IMI.UI = {}
local UI = IMI.UI
local Core, Runtime, Util = IMI.Core, IMI.Runtime, IMI.Util

local root, bar, body, sidebar, content, confirmFrame
local sidebarCollapsed = false

-- Declared here because ApplySettings and showView both call it and both are
-- written above it. A local used before its declaration resolves to a global
-- and is nil at run time, which luac passes without complaint.
local layoutBody
local layoutSidebar
local combatWatcher
local toggleButton
local views, currentView
local selected = { categoryId = nil }

-- Run remembers which page you were on, so stepping out to the dungeon list
-- mid-key and back resumes the route instead of restarting it.
--
-- The intent is "remember it for this key". Detecting a key would mean watching
-- keystone state, which this addon deliberately does not do, so the memory is
-- approximated two ways instead: it lives in memory only, so a reload or logout
-- clears it, and opening a different dungeon clears the previous one. Inside a
-- key you will not open another dungeon, so the effect is the same without
-- watching anything.
local lastPage = {}

local BAR_H, SIDE_W = 24, 168

-- The sidebar list is a fixed grid: row height, the gap-inclusive pitch between
-- them, and the inset above the first. Dropping a dragged row works out which
-- slot the cursor is over by dividing by the pitch, so these three have to be
-- the numbers actually used to lay the rows out, not a second copy of them.
local ROW_H, ROW_PITCH, LIST_TOP = 22, 24, 4

-- The list is a scroll child 24 narrower than the sidebar, because the scroll
-- template puts its bar in that gutter. A row wider than this reaches under the
-- bar, and whatever sits at the row's right edge — the delete button — is drawn
-- behind it and cannot be clicked. That shipped once.
local ROW_W = SIDE_W - 36

-- The strip down the left of the content panel that holds the collapse handle,
-- and the width of the invisible edges you grab to resize the window.
local GRIP = 12

-- Small enough to still be a panel, large enough that the sidebar plus one
-- column of callouts still fits.
local MIN_W, MIN_H = 560, 300
local DEFAULT_W, DEFAULT_H = 760, 380

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

local function fontString(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
    fs:SetText(text or "")
    fs:SetTextColor(unpack(IMI.Style.colors.text))
    return fs
end

local function panelButton(parent, text, w, h, onClick, opts)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h or 20)
    IMI.Style.Button(b, text, opts)
    if onClick then b:SetScript("OnClick", onClick) end
    -- Anything labelled with a symbol has to say what it is on hover; a "*" is
    -- not a word. Buttons whose own label is already the answer say nothing.
    if opts and opts.tip then IMI.Style.Tooltip(b, opts.tip, opts.tipDetail) end
    return b
end

--- Remembers what a frame was registered for, because the client offers no way
--- to ask. A frame whose work is a snippet must accept one direction or it runs
--- twice per press, and the self-test checks that inside the game where it
--- actually matters.
function UI.RegisterClicks(frame, ...)
    frame:RegisterForClicks(...)
    frame.__clickTypes = { ... }
    return frame
end

--------------------------------------------------------------------------------
-- Capturing one key press
--
-- Taking the keyboard is the most dangerous thing this addon does. While a
-- frame holds it, nothing reaches the game — including the Escape that opens
-- the menu and the slash command that would fix it. A capture that can be left
-- on is a keyboard that stops working with no way to type your way out, and
-- that is exactly what shipped: the keybind dialog returned early when it was
-- not waiting for anything, with the keyboard still held, swallowing every key
-- including Escape.
--
-- So there is one implementation, used everywhere, and every path out of it
-- releases: the key itself, Escape, the frame hiding, a key arriving while
-- nothing is armed, and a timeout if none of those happen. The timeout is the
-- one that matters — it is the guarantee that no fault here can cost more than
-- a few seconds.
--------------------------------------------------------------------------------

local CAPTURE_SECONDS = 10

local captureFrames = {}

--- Prepares a frame to capture a key. Does not arm it.
function UI.KeyCapture(frame)
    captureFrames[#captureFrames + 1] = frame

    frame.captureArmed = false
    frame:EnableKeyboard(false)

    local function release(announce)
        frame.captureArmed = false
        frame:EnableKeyboard(false)
        frame:SetScript("OnUpdate", nil)
        -- Back to passing keys through, so even a frame left enabled by some
        -- path not thought of here cannot swallow them.
        if frame.SetPropagateKeyboardInput then frame:SetPropagateKeyboardInput(true) end
        if announce then Util.Print("|cffff4444no key pressed. the keyboard is yours again.|r") end
        if frame.onCaptureEnd then frame.onCaptureEnd() end
    end
    frame.ReleaseKeys = release

    frame:SetScript("OnKeyDown", function(self, key)
        -- A key arriving while nothing is armed means the keyboard is held and
        -- should not be. Give it back rather than eating it.
        if not self.captureArmed then
            release()
            return
        end

        if key == "ESCAPE" then
            release()
            return
        end

        local chord = IMI.Binds.Chord(key, IsShiftKeyDown(), IsControlKeyDown(), IsAltKeyDown())
        if not chord then return end        -- a bare modifier: keep waiting

        local handler = self.onCaptureKey
        release()
        if handler then handler(chord) end
    end)

    frame:HookScript("OnHide", function() release() end)
    return frame
end

--- Arms it: the next key press goes to onKey, and the keyboard comes back
--- whatever happens.
function UI.ArmKeyCapture(frame, onKey, onEnd)
    frame.onCaptureKey, frame.onCaptureEnd = onKey, onEnd
    frame.captureArmed = true
    frame.captureUntil = (GetTime and GetTime() or 0) + CAPTURE_SECONDS

    frame:EnableKeyboard(true)
    if frame.SetPropagateKeyboardInput then frame:SetPropagateKeyboardInput(false) end

    frame:SetScript("OnUpdate", function(self)
        if not GetTime then return end
        if GetTime() > (self.captureUntil or 0) then frame.ReleaseKeys(true) end
    end)
    return frame
end

--- Every frame in the game that currently has the keyboard enabled and is on
--- screen, whether it belongs to this addon or not.
---
--- EnumerateFrames walks all of them, which is the only way to answer "what is
--- eating my keys". Focus is one way to lose the keyboard; a frame with
--- EnableKeyboard set and propagation off is the other, and nothing about it is
--- visible from the outside.
local function keyboardHolders()
    local out = {}
    if type(EnumerateFrames) ~= "function" then return out end

    local frame = EnumerateFrames()
    while frame do
        if frame.IsKeyboardEnabled and frame:IsKeyboardEnabled()
            and frame.IsVisible and frame:IsVisible() then
            out[#out + 1] = frame
        end
        frame = EnumerateFrames(frame)
    end
    return out
end

local function describe(frame)
    local name = frame.GetName and frame:GetName()
    if name then return name end

    local parent = frame.GetParent and frame:GetParent()
    local parentName = parent and parent.GetName and parent:GetName()
    return ("unnamed %s in %s"):format(
        tostring(frame.GetObjectType and frame:GetObjectType() or "?"),
        tostring(parentName or "unnamed parent"))
end

--- Gives the keyboard back from every capture there is, and from any edit box
--- of this addon's that is holding focus.
---
--- The safety valve. A focused edit box is the other way to lose the keyboard:
--- keys go into the box instead of to your bindings, and it does not look like
--- a capture at all — it looks like the keyboard has stopped working.
function UI.ReleaseAllKeys()
    local released = 0
    for _, frame in ipairs(captureFrames) do
        if frame.ReleaseKeys then
            frame.ReleaseKeys()
            released = released + 1
        end
    end

    local focused = _G.GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if focused and focused.ClearFocus then
        focused:ClearFocus()
        released = released + 1
    end

    -- And any frame of ours still holding the keyboard by enabling it, which
    -- clearing focus does nothing about. Only ours: taking the keyboard off
    -- another addon's frame would be a worse bug than the one being fixed.
    for _, frame in ipairs(keyboardHolders()) do
        local name = frame.GetName and frame:GetName()
        if (name and name:find("InomrahsMI", 1, true)) or frame.ReleaseKeys then
            frame:EnableKeyboard(false)
            if frame.SetPropagateKeyboardInput then frame:SetPropagateKeyboardInput(true) end
            released = released + 1
        end
    end

    return released, focused
end

--- Says what is holding the keyboard, without changing anything.
---
--- A lockout is hard to diagnose from a description: the game stops answering
--- its bindings while chat still works, and that reads the same whichever frame
--- is responsible. This names it, so the next one arrives as a fact.
---
--- Deliberately reaches for nothing declared later in this file — a local used
--- above its declaration resolves to a global and is nil, and this has to work
--- when everything else has gone wrong.
function UI.KeyboardReport()
    local focused = _G.GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()

    local who
    if not focused then
        who = "nothing has focus"
    else
        local name = focused.GetName and focused:GetName()
        local kind = focused.GetObjectType and focused:GetObjectType()
        local parent = focused.GetParent and focused:GetParent()
        local parentName = parent and parent.GetName and parent:GetName()
        who = ("focus: %s (%s) in %s"):format(
            tostring(name or "unnamed"), tostring(kind or "?"),
            tostring(parentName or "unnamed parent"))
    end

    local armed = 0
    for _, frame in ipairs(captureFrames) do
        if frame.captureArmed then armed = armed + 1 end
    end

    local holders = {}
    for _, frame in ipairs(keyboardHolders()) do
        holders[#holders + 1] = describe(frame)
    end

    return ("%s | captures: %d built, %d armed | keyboard enabled on: %s"):format(
        who, #captureFrames, armed,
        #holders > 0 and table.concat(holders, ", ") or "nothing")
end

--- Shared with Picker, which draws its own dialog but must not draw its own
--- kind of button.
function UI.PanelButton(...) return panelButton(...) end

--- Hand-skinned, because secure frames must inherit their secure template and
--- nothing else: adding a button template alongside one replaces the secure
--- OnLoad and the frame silently loses SetFrameRef and its handler methods.
local function skin(b, text)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.16, 0.16, 0.21, 0.95)
    -- A ground like any other, so it fades with the rest of them.
    IMI.Style.Ground(bg)

    local edge = b:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(0.36, 0.36, 0.46, 1)
    edge:SetDrawLayer("BORDER", -1)

    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.label:SetAllPoints()
    b.label:SetText(text or "")

    b:EnableMouse(true)
    b:SetScript("OnEnter", function() bg:SetColorTexture(0.26, 0.26, 0.34, 0.95) end)
    b:SetScript("OnLeave", function() bg:SetColorTexture(0.16, 0.16, 0.21, 0.95) end)
    return b
end

--------------------------------------------------------------------------------
-- Combat
--
-- The window has protected children — the callout buttons — and insecure code
-- may not hide, move or resize a frame with those in it while in combat. That
-- is not a bug to work around but the rule the whole design rests on.
--
-- Two things are worth having anyway, and the restricted environment allows
-- both: closing the window and dragging it. So the X and the title bar do their
-- work inside a secure snippet rather than from a script, and behave the same
-- in a pull as out of one.
--------------------------------------------------------------------------------

local CLOSE_SNIPPET = [==[
    local window = self:GetFrameRef("window")
    if window then window:Hide() end
]==]

-- The window has protected children, so insecure code cannot show or hide it in
-- combat — which is why /imi cannot reopen it mid-pull. A key bound to click
-- this does the same work from inside the restricted environment, where it is
-- allowed, so a keybind can do what the slash command cannot.
--
-- Show, Hide and IsShown are measured as available there. Moving and resizing
-- are measured as not; see the note above the drag scripts.
local TOGGLE_SNIPPET = [==[
    local window = self:GetFrameRef("window")
    if not window then return end
    if window:IsShown() then window:Hide() else window:Show() end
]==]

-- There are no snippets for moving or resizing, and there cannot be.
--
-- Measured in the client, 12.1.0: a frame handle in the restricted environment
-- has Show, Hide, IsShown, SetWidth, SetHeight, SetPoint, ClearAllPoints,
-- SetAttribute, GetAttribute and GetFrameRef. It does not have StartMoving,
-- StopMovingOrSizing or StartSizing.
--
-- So closing the window from a key works in combat, and moving or resizing it
-- does not. An earlier version assumed otherwise and drove both through
-- snippets that called methods which are not there — which broke dragging and
-- resizing outright, in combat and out of it, because the snippet is the only
-- path once it is installed. Both are plain scripts again, refused in combat
-- and working the rest of the time.

--- Points a secure handler at the window and gives it a snippet.
---
--- Returns false when the frame did not inherit its template — the failure that
--- has broken this addon twice — so the caller can fall back to a plain script
--- rather than shipping a control that does nothing.
local function bindSecure(frame, window, attribute, snippet)
    if type(frame.SetFrameRef) ~= "function" then return false end
    frame:SetFrameRef("window", window)
    frame:SetAttribute(attribute, snippet)
    return true
end

--- A dropdown built from plain frames.
---
--- WoW's own menu API was reworked in 12.x and this addon cannot verify which
--- form is current from outside the game. A button and a list of buttons has no
--- such risk, and behaves identically.
function UI.Dropdown(parent, width)
    local dd = panelButton(parent, "", width or 150, 20)

    dd.list = CreateFrame("Frame", nil, dd)
    dd.list:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)
    dd.list:SetWidth(width or 150)
    dd.list:SetFrameStrata("DIALOG")
    dd.list:Hide()

    IMI.Style.Background(dd.list, IMI.Style.colors.window)
    IMI.Style.Border(dd.list, IMI.Style.colors.gold)

    dd.rows = {}

    function dd:SetItems(items, onSelect)
        for _, row in ipairs(self.rows) do row:Hide() end

        local y = -2
        for i, item in ipairs(items) do
            local row = self.rows[i]
            if not row then
                row = panelButton(self.list, "", (width or 150) - 6, 18, nil,
                    { justify = "LEFT" })
                self.rows[i] = row
            end
            row:SetPoint("TOPLEFT", 3, y)
            row:SetText(item.text)
            row:SetScript("OnClick", function()
                self.list:Hide()
                onSelect(item.value, item)
            end)
            row:Show()
            y = y - 20
        end

        self.list:SetHeight(math.max(10, math.abs(y) + 2))
    end

    dd:SetScript("OnClick", function(self)
        if self.list:IsShown() then self.list:Hide() else self.list:Show() end
    end)

    return dd
end

UI.Skin = skin
UI.FontString = fontString
UI.PanelButton = panelButton

function UI.ApplySettings()
    local s = Core.Settings()
    if InCombatLockdown() then return false end   -- SetScale is blocked in combat
    root:SetScale(s.scale or 1)
    -- Not root:SetAlpha. That fades the frame and everything in it, so a
    -- see-through window came with see-through text and a see-through rule
    -- around every button. Only the grounds fade.
    root:SetAlpha(1)
    IMI.Style.SetOpacity(s.opacity or 1)

    -- Clamped on the way in as well as while dragging: a size from an older
    -- version, or a hand-edited saved variable, should not be able to produce a
    -- window too small to use.
    local w = math.max(MIN_W, tonumber(s.width) or DEFAULT_W)
    local h = math.max(MIN_H, tonumber(s.height) or DEFAULT_H)
    root:SetSize(w, h)

    -- Text scale is the whole interface, not just the callout buttons. It used
    -- to reach only the text Runtime set a font on, which was Run and nothing
    -- else.
    IMI.Style.SetTextScale(s.textScale or 1)
    IMI.Style.LoadUserColors(s.colors)
    UI.ApplyToggleKey()

    sidebarCollapsed = s.sidebarCollapsed == true
    layoutBody()
    return true
end

--------------------------------------------------------------------------------
-- Sidebar
--------------------------------------------------------------------------------

local sidebarRows = {}

-- A drag has a state between the press and the release that is neither "nothing
-- is happening" nor a committed move. It lives here rather than on the row,
-- because a refresh can recycle the row it started on before the mouse comes
-- back up.
local dragState = { id = nil, target = nil }


local function selectCategory(id)
    -- Opening a different dungeon ends the previous one's route memory.
    if selected.categoryId and selected.categoryId ~= id then
        lastPage[selected.categoryId] = nil
    end

    selected.categoryId = id
    IMI.Capture.SetCategory(id)

    -- The interface takes the open dungeon's colour. Nil puts it back to the
    -- addon's own, so closing a dungeon is not a state you have to undo.
    IMI.Style.SetDungeonColor(id and Core.CategoryColor(id) or nil)

    UI.RefreshSidebar()

    if currentView == "run" then
        UI.OpenRun(id)
    elseif currentView == "edit" then
        IMI.Edit.SetCategory(id)
    end
end

function UI.SelectedCategory()
    return selected.categoryId
end

--- Selecting from outside the sidebar — undo returning to where a change was
--- made, for one.
function UI.SelectCategory(id) selectCategory(id) end

--- The dungeon rows, in list order. Exposed for the same reason UI.Arrows is:
--- the rows carry the rename, reorder and delete behaviour, and there is no
--- other way to reach it from a test.
function UI.SidebarRows()
    return sidebarRows
end

--- Puts Run back to its nothing-selected state. Both Back and deleting the
--- dungeon you were looking at end up here.
local function clearRun()
    Runtime.HideAll()
    views.run.title:SetText("")
    views.run.prompt:SetText("Pick a dungeon on the left.")
    views.run.prompt:Show()
    if views.run.variant then views.run.variant:Hide() end
end

--- Asks a yes/no over the panel, and calls back only on yes.
---
--- Built once and refilled rather than created per question: frames cannot be
--- destroyed, so a dialog made on demand would leak one every time it was
--- asked for.
---
--- Escape closes it through UISpecialFrames rather than a key handler of its
--- own. That distinction matters: a handler would have to swallow keys the
--- client would otherwise deliver, and this panel is on screen during a pull —
--- the last thing it should be able to do is eat an interrupt. UISpecialFrames
--- is the client closing its own dialog, and only while one is open.
function UI.Confirm(opts)
    opts = opts or {}

    if not confirmFrame then
        -- Swallows clicks aimed at the panel underneath, so what is being asked
        -- about cannot be changed or deleted twice while the question is up.
        local blocker = CreateFrame("Frame", "InomrahsMIConfirm", root)
        blocker:SetAllPoints(root)
        blocker:SetFrameStrata("FULLSCREEN_DIALOG")
        blocker:EnableMouse(true)
        blocker:Hide()

        local d = CreateFrame("Frame", nil, blocker)
        d:SetSize(320, 140)
        d:SetPoint("CENTER", root, "CENTER", 0, 0)
        d:SetFrameStrata("FULLSCREEN_DIALOG")
        d:SetFrameLevel(blocker:GetFrameLevel() + 10)
        IMI.Style.Panel(d, IMI.Style.colors.dialog)

        d.title = IMI.Style.Header(d, "")
        d.title:SetPoint("TOP", 0, -12)

        d.body = fontString(d, "")
        d.body:SetPoint("TOPLEFT", 16, -38)
        d.body:SetPoint("TOPRIGHT", -16, -38)
        d.body:SetJustifyH("LEFT")
        d.body:SetJustifyV("TOP")

        -- The destructive answer sits on the right, away from where the cursor
        -- lands coming off the button that opened this.
        d.accept = panelButton(d, "", 96, 22)
        d.accept:SetPoint("BOTTOMRIGHT", -14, 14)

        d.cancel = panelButton(d, "Cancel", 96, 22, function() blocker:Hide() end)
        d.cancel:SetPoint("RIGHT", d.accept, "LEFT", -8, 0)

        blocker.dialog = d
        confirmFrame = blocker

        if type(UISpecialFrames) == "table" then
            table.insert(UISpecialFrames, "InomrahsMIConfirm")
        end
    end

    local d = confirmFrame.dialog
    d.title:SetText(opts.title or "Are you sure?")
    d.body:SetText(opts.body or "")
    d.accept:SetText(opts.accept or "OK")
    d.accept:SetDanger(opts.danger)
    d.accept:SetScript("OnClick", function()
        confirmFrame:Hide()
        if opts.onAccept then opts.onAccept() end
    end)

    confirmFrame:Show()
    return confirmFrame
end

--- The confirmation, for tests: its two buttons are the only way past it.
function UI.ConfirmFrame() return confirmFrame end

local function deleteCategory(id)
    -- Run has this dungeon's secure buttons on screen and hiding those is
    -- refused in combat. Only this one case is blocked: deleting some other
    -- dungeon mid-key touches nothing protected.
    if InCombatLockdown() and Runtime.BuiltCategory() == id then
        Util.Print("|cffff4444can't delete the dungeon you are running, in combat.|r")
        return
    end

    local cats = Core.Categories()
    local index = Util.IndexById(cats, id)
    local cat = Core.GetCategory(id)
    local name = cat and cat.name or "dungeon"
    if not Core.DeleteCategory(id) then return end

    lastPage[id] = nil
    if Runtime.BuiltCategory() == id then clearRun() end

    -- The list closes up around the gap, so the dungeon that slid into the
    -- deleted one's place is the one to show. Deleting the last leaves nothing
    -- selected rather than jumping to the top.
    if selected.categoryId == id then
        selected.categoryId = nil
        local neighbour = cats[index] or cats[#cats]
        if neighbour then
            selectCategory(neighbour.id)
        else
            IMI.Capture.SetCategory(nil)
            clearRun()
            IMI.Edit.SetCategory(nil)
        end
    end

    UI.RefreshSidebar()
    Util.Print(("deleted |cffffff00%s|r."):format(name))
end

--- Undo or redo one step, then put the editor back where that change was made
--- so the change coming or going is on screen rather than somewhere you have to
--- go and find.
---
--- Refused in combat. A step can delete the dungeon Run has built, and hiding
--- its buttons mid-fight is not allowed; and there is no reason to be editing
--- during a pull. One rule is easier to rely on than a partial one.
local function historyStep(direction)
    if InCombatLockdown() then
        Util.Print("|cffff4444not while in combat.|r")
        return
    end

    local History = IMI.History
    local ctx = (direction == "undo") and History.Undo() or History.Redo()
    if ctx == nil then
        Util.Print(("nothing to %s."):format(direction))
        return
    end

    -- Everything was replaced wholesale, so anything held by id may be gone.
    if selected.categoryId and not Core.GetCategory(selected.categoryId) then
        selected.categoryId = nil
        IMI.Capture.SetCategory(nil)
        IMI.Edit.SetCategory(nil)
    end
    if Runtime.BuiltCategory() and not Core.GetCategory(Runtime.BuiltCategory()) then
        clearRun()
    end

    -- Navigating touches stored data (the active variant), and that must not
    -- land on the stacks as an edit of its own.
    IMI.History.Silently(function() IMI.Edit.RestoreContext(ctx or nil) end)

    UI.RefreshSidebar()
    IMI.Edit.RefreshStaleMarker()
    UI.RefreshHistoryButtons()
end

function UI.Undo() historyStep("undo") end
function UI.Redo() historyStep("redo") end

--- Greys the buttons out when there is nothing that way. Called by History
--- whenever the stacks move, so the buttons never claim a step that is not
--- there.
function UI.RefreshHistoryButtons()
    local buttons = views and views.edit and views.edit.history
    if not buttons then return end

    local History = IMI.History
    local undoDepth, redoDepth = History.Depth()

    buttons.undo:SetEnabled(History.CanUndo())
    buttons.redo:SetEnabled(History.CanRedo())

    IMI.Style.Tooltip(buttons.undo, "Undo",
        undoDepth > 0
            and ("Takes back the last change, and goes to where it was made. %d step%s back.")
                :format(undoDepth, undoDepth == 1 and "" or "s")
            or "Nothing to undo yet.")
    IMI.Style.Tooltip(buttons.redo, "Redo",
        redoDepth > 0
            and ("Puts back the last undone change. %d step%s forward.")
                :format(redoDepth, redoDepth == 1 and "" or "s")
            or "Nothing to redo.")
end

--- The undo pair, for tests: nothing else reaches into the Edit view's frames.
function UI.EditHistoryButtons()
    return views and views.edit and views.edit.history
end

--- Which slot in the list a point sits in, counting from 1.
---
--- Split out as plain arithmetic because it is the one part of dragging that
--- can be tested without a client: everything else needs a real cursor. Out of
--- range clamps to an end, so dragging past the last row means "put it last".
function UI.DropIndex(listTop, cursorY, count)
    if count <= 0 then return 1 end
    local slot = math.floor((listTop - LIST_TOP - cursorY) / ROW_PITCH) + 1
    if slot < 1 then slot = 1 end
    if slot > count then slot = count end
    return slot
end

--- Where the cursor is in the list, or nil if the client will not say. Guarded
--- rather than trusted: GetCursorPosition is one of the calls that returns
--- nothing at all in some frames, and arithmetic on that is a Lua error in
--- the middle of a drag.
local function cursorSlot()
    if type(GetCursorPosition) ~= "function" then return nil end
    local _, y = GetCursorPosition()
    local scale = sidebar.list:GetEffectiveScale()
    local top = sidebar.list:GetTop()
    if type(y) ~= "number" or type(scale) ~= "number" or type(top) ~= "number"
        or scale == 0 then
        return nil
    end
    return UI.DropIndex(top, y / scale, #Core.Categories())
end

local function dragUpdate()
    local slot = cursorSlot()
    if not slot then return end
    dragState.target = slot

    local line = sidebar.dropLine
    if not line then return end
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", sidebar.list, "TOPLEFT", 6,
        -(LIST_TOP + (slot - 1) * ROW_PITCH) + 1)
    line:SetWidth(ROW_W)
    line:Show()
end

local function endDrag()
    sidebar:SetScript("OnUpdate", nil)
    if sidebar.dropLine then sidebar.dropLine:Hide() end

    local id, target = dragState.id, dragState.target
    dragState.id, dragState.target = nil, nil
    if id and target then Core.MoveCategoryTo(id, target) end
    UI.RefreshSidebar()
end

local function newSidebarRow()
    local row = panelButton(sidebar.list, "", ROW_W, ROW_H, nil,
        { justify = "LEFT" })

    -- Leaves room for the delete button, so a long dungeon name stops short of
    -- it rather than running underneath it.
    row.label:SetPoint("RIGHT", -24, 0)

    row.del = panelButton(row, "x", 18, 18, nil, { danger = true,
        tip = "Delete dungeon", tipDetail = "Asks first. Takes everything in it." })
    row.del:SetPoint("RIGHT", -2, 0)

    -- Both of these sit on top of the row rather than beside it, and a frame
    -- only draws above another by having a higher level. Left to the default
    -- they would be somewhere under the row's own background, which reads as
    -- the button simply not being there.
    row.del:SetFrameLevel(row:GetFrameLevel() + 2)

    -- Renaming happens on the row itself, so a name is edited where it is read
    -- rather than in a field somewhere else that has to say which row it means.
    row.rename = CreateFrame("EditBox", nil, row)
    row.rename:SetFontObject("ChatFontNormal")
    IMI.Style.EditBox(row.rename)
    row.rename:SetAllPoints()
    row.rename:SetAutoFocus(false)
    row.rename:SetMaxLetters(64)
    row.rename:SetFrameLevel(row:GetFrameLevel() + 1)
    row.rename:HookScript("OnHide", function(self) self:ClearFocus() end)
    row.rename:Hide()

    row:RegisterForDrag("LeftButton")
    return row
end

function UI.RefreshSidebar()
    for _, row in ipairs(sidebarRows) do row:Hide() end

    -- Rearranging and deleting belong to Edit. In Run the list is a way in and
    -- nothing else: a stray double-click or a slipped drag mid-key should not
    -- be able to rename a dungeon, reorder the list, or cost you one.
    local editable = (currentView == "edit")

    local y = -LIST_TOP
    for i, cat in ipairs(Core.Categories()) do
        local row = sidebarRows[i]
        if not row then
            row = newSidebarRow()
            sidebarRows[i] = row
        end

        row:SetPoint("TOPLEFT", sidebar.list, "TOPLEFT", 6, y)
        row:SetText(cat.name)
        -- The row truncates rather than wrapping, so hovering is how a long
        -- name stays readable.
        IMI.Style.Tooltip(row, cat.name)
        row:SetAlpha(1)
        row.rename:Hide()
        row:SetScript("OnClick", function() selectCategory(cat.id) end)

        row.del:SetShown(editable)
        row.del:SetScript("OnClick", function()
            UI.Confirm({
                title = "Delete dungeon",
                body = ("Delete |cffffff00%s|r?\n\nThis removes every variant, enemy, line and page in it. It cannot be undone.")
                    :format(cat.name),
                accept = "Delete",
                danger = true,
                onAccept = function() deleteCategory(cat.id) end,
            })
        end)

        row:SetScript("OnDoubleClick", editable and function()
            row.rename:SetText(cat.name)
            row.rename:Show()
            row.rename:SetFocus()
            row.rename:HighlightText()
        end or nil)

        -- Enter and click-away both commit, Escape abandons. Committing on lost
        -- focus is what the enemy name boxes already do, so a name typed and
        -- then clicked away from is kept rather than quietly dropped.
        row.rename:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        row.rename:SetScript("OnEscapePressed", function(self)
            self.cancelled = true
            self:ClearFocus()
        end)
        row.rename:SetScript("OnEditFocusLost", function(self)
            self:Hide()
            if self.cancelled then self.cancelled = nil; return end
            if not Core.RenameCategory(cat.id, self:GetText()) then return end

            UI.RefreshSidebar()
            if Runtime.BuiltCategory() == cat.id then
                views.run.title:SetText(self:GetText())
            end
            if currentView == "edit" then IMI.Edit.RefreshTitle() end
        end)

        row:SetScript("OnDragStart", editable and function()
            dragState.id, dragState.target = cat.id, i
            row:SetAlpha(0.5)
            sidebar:SetScript("OnUpdate", dragUpdate)
            dragUpdate()
        end or nil)
        row:SetScript("OnDragStop", editable and endDrag or nil)

        -- The selected dungeon is highlighted, so which one the right panel is
        -- showing never has to be inferred from its heading.
        if cat.id == selected.categoryId then row:LockHighlight() else row:UnlockHighlight() end

        row:Show()
        y = y - ROW_PITCH
    end

    sidebar.empty:SetShown(#Core.Categories() == 0)
    layoutSidebar(editable, #Core.Categories() > 0)
    sidebar.list:SetHeight(math.max(20, math.abs(y)))

    IMI.Style.RefreshScrollBar(sidebar.scroll, math.abs(y))
end

local function commitNewCategory()
    local name = sidebar.newName:GetText()
    if not name or not name:match("%S") then
        sidebar.newName:Hide()
        return
    end
    local cat = Core.AddCategory(name)
    sidebar.newName:SetText("")
    sidebar.newName:Hide()
    selectCategory(cat.id)
    if currentView == "edit" then IMI.Edit.SetCategory(cat.id) end
end

--------------------------------------------------------------------------------
-- Views
--------------------------------------------------------------------------------

-- Work asked for during a pull, to be carried out when it ends.
local pendingView, pendingRelayout

local function showView(name)
    if name ~= currentView and InCombatLockdown() then
        -- Run's pages are protected, and insecure code may neither hide nor
        -- show a frame holding those in combat. The calls fail silently, so
        -- what happened instead was half a switch: Edit drawn underneath Run's
        -- callouts, both sets of text on screen at once.
        --
        -- Refusing outright would strand you in Edit for the rest of a pull, so
        -- the switch is remembered and made the moment combat ends.
        pendingView = name
        UI.WatchCombat()
        Util.Print(("|cffff4444can't switch to %s in combat.|r doing it when combat ends.")
            :format(name))
        return false
    end

    for viewName, frame in pairs(views) do
        if viewName == name then frame:Show() else frame:Hide() end
    end

    -- Secure buttons left showing under another view would sit on top of it,
    -- and could not be hidden later if a pull started.
    if name ~= "run" then Runtime.HideAll() end

    currentView = name
    layoutBody()
    sidebar.newBtn:SetShown(name == "edit")

    if bar and bar.tabs then
        for tabName, btn in pairs(bar.tabs) do
            if tabName == name then btn:LockHighlight() else btn:UnlockHighlight() end
        end
    end

    if name == "edit" then
        IMI.Edit.SetCategory(selected.categoryId)
    elseif name == "run" and selected.categoryId then
        UI.OpenRun(selected.categoryId)
    end

    UI.RefreshSidebar()
    return true
end

--- Waits for the end of combat, once, to carry out a switch that was refused.
---
--- The only game event this addon listens to. It reads nothing about the world
--- — not the zone, not the keystone, not the fight — only that the restriction
--- which blocked a button press has lifted.
function UI.WatchCombat()
    if not combatWatcher then
        combatWatcher = CreateFrame("Frame")
        combatWatcher:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()

            local wanted, relayout = pendingView, pendingRelayout
            pendingView, pendingRelayout = nil, false

            if wanted then
                showView(wanted)
                Util.Print(("switched to |cffffff00%s|r."):format(wanted))
            elseif relayout then
                UI.Relayout()
            end
        end)
    end
    combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    return combatWatcher
end

function UI.PendingView() return pendingView end

--- Applies the key that opens and closes the window.
---
--- Owned by its own frame, not the pager: the pager clears its bindings on
--- every page flip, and a key that stopped working when you turned the page
--- would be a strange thing to have.
function UI.ApplyToggleKey()
    if InCombatLockdown() then return false end
    if type(ClearOverrideBindings) ~= "function"
        or type(SetOverrideBindingClick) ~= "function" then
        return false
    end
    if not toggleButton then return false end

    ClearOverrideBindings(toggleButton)

    local key = Core.Settings().toggleKey
    if key and key ~= "" then
        SetOverrideBindingClick(toggleButton, true, key, toggleButton:GetName())
    end
    return true
end

function UI.ToggleButton() return toggleButton end

--- The controls that must work during a pull, for tests: whether they are
--- secure is the whole of their behaviour and is invisible otherwise.
function UI.CloseButton() return root and root.closeButton end
function UI.TitleBar() return bar end
function UI.ResizeGrips()
    if not root then return {} end
    return { root.gripRight, root.gripBottom, root.gripCorner }
end
function UI.PendingRelayout() return pendingRelayout == true end

--- Divides the dungeon column between the list and the fixed stack under it.
---
--- The stack is Back, New dungeon, the name box and the hint, and it does not
--- shrink. In a short window it ate into the list and the hint ended up drawn
--- across the last dungeon. The hint is what gives way: it explains two
--- gestures, and a list you cannot read is the worse trade. The gestures stay
--- reachable on the column's heading.
function layoutSidebar(editable, hasRows)
    local height = sidebar:GetHeight()
    local roomy = type(height) ~= "number" or height > 300

    local showHint = editable and hasRows and roomy
    sidebar.hint:SetShown(showHint)

    sidebar.scroll:ClearAllPoints()
    sidebar.scroll:SetPoint("TOPLEFT", 0, -24)
    sidebar.scroll:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -24,
        showHint and 106 or 82)
end

--- Where the content panel starts, and whether the dungeon list is beside it.
---
--- One function rather than a SetPoint at each call site: Settings hides the
--- list, collapsing hides the list, and the two got different answers. The
--- panel's own left border was left standing in the middle of the Settings
--- page, drawn straight through the sliders.
function layoutBody()
    local wanted = (currentView ~= "settings") and not sidebarCollapsed
    sidebar:SetShown(wanted)

    content:ClearAllPoints()
    if wanted then
        content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 6, 0)
    else
        content:SetPoint("TOPLEFT", body, "TOPLEFT", GRIP + 6, -6)
    end
    content:SetPoint("BOTTOMRIGHT", -6, 6)

    -- The handle stays put whether the list is there or not: it is the way back
    -- as much as the way in, so it cannot travel with what it hides.
    if body.sidebarToggle then
        body.sidebarToggle:SetShown(currentView ~= "settings")
        body.sidebarToggle:SetText(sidebarCollapsed and ">" or "<")
        IMI.Style.Tooltip(body.sidebarToggle,
            sidebarCollapsed and "Show the dungeon list" or "Hide the dungeon list",
            "Gives the panel the whole window.")
    end
end

--- Folds the dungeon list away for more room. Out of combat only: the content
--- panel resizing moves Run's secure buttons, and that is refused mid-fight.
function UI.ToggleSidebar()
    if InCombatLockdown() then
        Util.Print("|cffff4444not while in combat.|r")
        return false
    end

    sidebarCollapsed = not sidebarCollapsed
    Core.Settings().sidebarCollapsed = sidebarCollapsed
    layoutBody()
    UI.Relayout()
    return true
end

function UI.SidebarCollapsed() return sidebarCollapsed end

--- The two panels, for tests: how they are anchored is the thing that went
--- wrong, and it is not visible from outside any other way.
function UI.ContentPanel() return content end

--- The two groups whose widgets sit closest together, for the overlap test.
function UI.BarWidgets()
    return {
        collapse = bar.collapse, run = bar.tabs and bar.tabs.run,
        edit = bar.tabs and bar.tabs.edit, title = bar.title,
        info = bar.info, gear = bar.gear, close = root and root.closeButton,
    }
end

--- The Run view's own furniture, which shares a strip with the page arrows.
function UI.RunWidgets()
    return {
        title = views.run.title, prompt = views.run.prompt,
        variant = views.run.variant, pages = views.run.pages,
        prev = views.run.arrows and views.run.arrows.prev,
        next = views.run.arrows and views.run.arrows.next,
    }
end

function UI.SidebarWidgets()
    return {
        header = sidebar.header, list = sidebar.scroll, hint = sidebar.hint,
        newName = sidebar.newName, newBtn = sidebar.newBtn, back = sidebar.back,
    }
end
function UI.Sidebar() return sidebar end

--- Re-lays whatever the content panel is showing, after its width changed.
function UI.Relayout()
    if InCombatLockdown() then return false end

    if currentView == "run" and selected.categoryId then
        UI.OpenRun(selected.categoryId)
    elseif currentView == "edit" then
        IMI.Edit.Refresh()
    end
    return true
end

function UI.CurrentView() return currentView end
--- Returns whether the switch actually happened: in combat it may only be
--- remembered, and a caller that assumes it took would draw the wrong thing.
function UI.ShowView(name) return showView(name) end

--------------------------------------------------------------------------------
-- Run
--------------------------------------------------------------------------------

--- Builds a dungeon's buttons and shows its pages. Refuses in combat, because
--- this writes every button's macro text and combat forbids that. Nothing is
--- half-written: the build either succeeds or changes nothing.
--- Fills the variant chooser and rebuilds when one is picked. Switching variant
--- rewrites every button, so it is the same out-of-combat operation as opening
--- a dungeon, and refuses in combat for the same reason.
function UI.RefreshVariantChooser(catId)
    local dd = views.run.variant
    if not dd then return end

    local variants = Core.Variants(catId)
    if #variants <= 1 then
        -- One variant is the normal case; a chooser with a single entry is
        -- clutter that explains nothing.
        dd:Hide()
        return
    end

    local items = {}
    for _, variant in ipairs(variants) do
        items[#items + 1] = { text = variant.name, value = variant.id }
    end

    dd:SetItems(items, function(variantId)
        Core.SetActiveVariant(catId, variantId)
        UI.OpenRun(catId)
    end)

    local current = Core.Variant(catId)
    dd:SetText(current and current.name or "")
    dd:Show()
end

function UI.OpenRun(catId)
    local ok, err = Runtime.Build(views.run.pages, catId, Core.Settings())
    if not ok then
        views.run.prompt:SetText("|cffff4444" .. (err or "could not load") .. "|r")
        views.run.prompt:Show()
        return false
    end

    local cat = Core.GetCategory(catId)
    views.run.prompt:Hide()
    views.run.title:SetText(cat and cat.name or "")
    UI.RefreshVariantChooser(catId)
    Runtime.ShowPage(lastPage[catId] or 1)
    return true
end

--- Remembers where you were before leaving the dungeon, so coming back mid-key
--- resumes the route rather than restarting it.
function UI.RememberPage()
    if selected.categoryId then
        lastPage[selected.categoryId] = Runtime.CurrentPage()
    end
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function UI.Init()
    root = CreateFrame("Frame", "InomrahsMIFrame", UIParent)
    root:SetSize(DEFAULT_W, DEFAULT_H)
    root:SetPoint("CENTER")
    root:SetMovable(true)
    root:EnableMouse(true)
    root:SetClampedToScreen(true)

    IMI.Style.Background(root, IMI.Style.colors.window)
    IMI.Style.Border(root, IMI.Style.colors.gold)

    -- Bar --------------------------------------------------------------------
    bar = CreateFrame("Frame", nil, root, "SecureHandlerDragTemplate")
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(BAR_H)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")

    bar:SetScript("OnDragStart", function()
        -- Moving a frame with protected children is refused in combat, and the
        -- restricted environment cannot do it either. Saying so beats a window
        -- that quietly will not move.
        if InCombatLockdown() then
            Util.Print("|cffff4444can't move the window in combat.|r")
            return
        end
        root:StartMoving()
    end)

    bar:SetScript("OnDragStop", function()
        root:StopMovingOrSizing()
        local point, _, rel, x, y = root:GetPoint()
        Core.Settings().point = { point = point, relativePoint = rel, x = x, y = y }
    end)

    IMI.Style.Background(bar, IMI.Style.colors.bar)

    local collapse = panelButton(bar, "-", 22, BAR_H - 4, nil,
        { tip = "Collapse", tipDetail = "Rolls the window up to just this bar." })
    collapse:SetPoint("LEFT", 3, 0)

    -- Run and Edit are where the work happens, so they get the left. Settings,
    -- help and close are occasional, so they sit as icons on the right, out of
    -- the way of the two buttons actually used every session.
    local runBtn  = panelButton(bar, "Run", 60, BAR_H - 4, function() showView("run") end,
        { tip = "Run", tipDetail = "The pages of callout buttons, for use in a key." })
    local editBtn = panelButton(bar, "Edit", 60, BAR_H - 4, function() showView("edit") end,
        { tip = "Edit", tipDetail = "Write the callouts and arrange the pages." })
    runBtn:SetPoint("LEFT", collapse, "RIGHT", 4, 0)
    editBtn:SetPoint("LEFT", runBtn, "RIGHT", 2, 0)

    bar.tabs = { run = runBtn, edit = editBtn }
    bar.collapse = collapse

    local close = CreateFrame("Button", nil, bar, "SecureHandlerClickTemplate")
    close:SetSize(22, BAR_H - 4)
    close:SetPoint("RIGHT", -3, 0)
    skin(close, "X")
    -- One direction only. A frame whose work is an _onclick snippet runs it on
    -- every click it accepts, so registering both fired it on the way down and
    -- again on the way up. The page arrows have said so since they were
    -- written; this did not, and closing therefore lasted only as long as the
    -- key was held.
    UI.RegisterClicks(close, "AnyUp")
    IMI.Style.Tooltip(close, "Close window",
        "/imi opens it again out of combat. Nothing is lost.")

    root.closeButton = close

    if not bindSecure(close, root, "_onclick", CLOSE_SNIPPET) then
        close:SetScript("OnClick", function()
            if InCombatLockdown() then
                Util.Print("|cffff4444can't close the window in combat.|r")
                return
            end
            root:Hide()
        end)
    end

    local gear = panelButton(bar, "*", 22, BAR_H - 4, function()
        showView(currentView == "settings" and "run" or "settings")
    end, { tip = "Settings", tipDetail = "Size, opacity, text scale and which chat channel." })
    gear:SetPoint("RIGHT", close, "LEFT", -2, 0)

    local info = panelButton(bar, "?", 22, BAR_H - 4, function() UI.ShowHelp() end,
        { tip = "Help", tipDetail = "What everything does, and the slash commands." })
    info:SetPoint("RIGHT", gear, "LEFT", -2, 0)

    bar.info, bar.gear = info, gear
    bar.title = IMI.Style.Header(bar, "Inomrah's Mythic Instructions")
    bar.title:SetPoint("CENTER", bar, "CENTER", 0, 0)

    body = CreateFrame("Frame", nil, root)
    body:SetPoint("TOPLEFT", bar, "BOTTOMLEFT")
    body:SetPoint("BOTTOMRIGHT")

    -- Resizing ---------------------------------------------------------------
    root:SetResizable(true)
    -- The bounds call was renamed; ask for whichever this client has rather
    -- than picking one and having no minimum at all on the other.
    if root.SetResizeBounds then
        root:SetResizeBounds(MIN_W, MIN_H)
    elseif root.SetMinResize then
        root:SetMinResize(MIN_W, MIN_H)
    end

    --- One draggable edge. Invisible: an edge you can grab is a convention, and
    --- drawing it would mean three more lines competing with the gold rule.
    local function resizeGrip(direction, setPoints, tip)
        local g = CreateFrame("Frame", nil, root, "SecureHandlerMouseUpDownTemplate")
        setPoints(g)
        g:EnableMouse(true)
        IMI.Style.Tooltip(g, tip)
        g:SetAttribute("edge", direction)

        g:SetScript("OnMouseDown", function()
            if InCombatLockdown() then
                Util.Print("|cffff4444can't resize the window in combat.|r")
                return
            end
            root:StartSizing(direction)
        end)

        g:SetScript("OnMouseUp", function()
            root:StopMovingOrSizing()

            local settings = Core.Settings()
            settings.width, settings.height = root:GetWidth(), root:GetHeight()

            -- The panel is a different width now, so what is in it has to be
            -- laid out again.
            if not UI.Relayout() then
                pendingRelayout = true
                UI.WatchCombat()
            end
        end)
        return g
    end

    -- Never clicked with the mouse; it exists to be the target of a keybind.
    toggleButton = CreateFrame("Button", "InomrahsMIToggle", root,
        "SecureHandlerClickTemplate")
    toggleButton:SetSize(1, 1)
    toggleButton:SetPoint("TOPLEFT")
    UI.RegisterClicks(toggleButton, "AnyUp")
    if not bindSecure(toggleButton, root, "_onclick", TOGGLE_SNIPPET) then
        toggleButton:SetScript("OnClick", function()
            if InCombatLockdown() then
                Util.Print("|cffff4444can't open or close the window in combat.|r")
                return
            end
            if root:IsShown() then root:Hide() else root:Show() end
        end)
    end

    root.gripRight = resizeGrip("RIGHT", function(g)
        g:SetPoint("TOPRIGHT", 0, -BAR_H)
        g:SetPoint("BOTTOMRIGHT", 0, GRIP)
        g:SetWidth(GRIP)
    end, "Drag to change the width")

    root.gripBottom = resizeGrip("BOTTOM", function(g)
        g:SetPoint("BOTTOMLEFT")
        g:SetPoint("BOTTOMRIGHT", -GRIP, 0)
        g:SetHeight(GRIP)
    end, "Drag to change the height")

    root.gripCorner = resizeGrip("BOTTOMRIGHT", function(g)
        g:SetPoint("BOTTOMRIGHT")
        g:SetSize(GRIP, GRIP)
    end, "Drag to change both")

    collapse:SetScript("OnClick", function(self)
        if InCombatLockdown() then
            Util.Print("|cffff4444can't collapse the window in combat.|r")
            return
        end
        if body:IsShown() then
            body:Hide(); self:SetText("+"); root:SetHeight(BAR_H)
        else
            body:Show(); self:SetText("-"); root:SetHeight(380)
        end
    end)

    -- Sidebar ------------------------------------------------------------------
    sidebar = CreateFrame("Frame", nil, body)
    sidebar:SetPoint("TOPLEFT", 6, -6)
    sidebar:SetPoint("BOTTOMLEFT", 6, 6)
    sidebar:SetWidth(SIDE_W)

    IMI.Style.Panel(sidebar)

    sidebar.header = IMI.Style.Header(sidebar, "Dungeons")
    sidebar.header:SetPoint("TOP", 0, -6)
    -- Says the same as the hint below the list, which is dropped when the
    -- window is too short to hold both it and the list.
    sidebar.headerHit = CreateFrame("Frame", nil, sidebar)
    sidebar.headerHit:SetPoint("TOPLEFT", 0, -2)
    sidebar.headerHit:SetPoint("TOPRIGHT", 0, -2)
    sidebar.headerHit:SetHeight(20)
    sidebar.headerHit:EnableMouse(true)
    IMI.Style.Tooltip(sidebar.headerHit, "Dungeons",
        "In Edit: double-click a name to rename it, drag a row to reorder, "
        .. "and the red x deletes.")

    -- Pinned to the bottom, so they stay put however long the list grows.
    sidebar.back = panelButton(sidebar, "Back", SIDE_W - 16, 22, function()
        UI.RememberPage()
        selected.categoryId = nil
        IMI.Style.SetDungeonColor(nil)
        clearRun()
        IMI.Edit.SetCategory(nil)
        UI.RefreshSidebar()
    end)
    sidebar.back:SetPoint("BOTTOMLEFT", 8, 8)
    IMI.Style.Tooltip(sidebar.back, "Back to the list",
        "Closes the dungeon without changing it. In Run, the page you were on is remembered.")

    sidebar.newBtn = panelButton(sidebar, "New dungeon", SIDE_W - 16, 22, function()
        sidebar.newName:Show()
        sidebar.newName:SetText("")
        sidebar.newName:SetFocus()
    end)
    sidebar.newBtn:SetPoint("BOTTOMLEFT", sidebar.back, "TOPLEFT", 0, 4)
    IMI.Style.Tooltip(sidebar.newBtn, "New dungeon", "Type a name and press Enter.")

    sidebar.newName = CreateFrame("EditBox", nil, sidebar)
    sidebar.newName:SetFontObject("ChatFontNormal")
    IMI.Style.EditBox(sidebar.newName)
    sidebar.newName:SetSize(SIDE_W - 22, 20)
    sidebar.newName:SetPoint("BOTTOMLEFT", sidebar.newBtn, "TOPLEFT", 5, 4)
    sidebar.newName:SetAutoFocus(false)
    sidebar.newName:SetMaxLetters(64)
    sidebar.newName:SetScript("OnEnterPressed", commitNewCategory)
    sidebar.newName:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        self:Hide()
    end)
    sidebar.newName:HookScript("OnHide", function(self) self:ClearFocus() end)
    sidebar.newName:Hide()

    local listScroll = CreateFrame("ScrollFrame", nil, sidebar, "UIPanelScrollFrameTemplate")
    sidebar.scroll = listScroll
    IMI.Style.WheelScroll(listScroll)
    listScroll:SetPoint("TOPLEFT", 0, -24)
    listScroll:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -24, 106)
    sidebar.list = CreateFrame("Frame", nil, listScroll)
    sidebar.list:SetSize(SIDE_W - 24, 40)
    listScroll:SetScrollChild(sidebar.list)

    -- Where a dragged row would land. Drawn on the list rather than moving the
    -- row itself: the row stays in place and slightly faded, so the list never
    -- reflows under the cursor while you are aiming at a gap in it.
    sidebar.dropLine = sidebar.list:CreateTexture(nil, "OVERLAY")
    sidebar.dropLine:SetColorTexture(unpack(IMI.Style.colors.accent))
    sidebar.dropLine:SetHeight(2)
    sidebar.dropLine:Hide()

    sidebar.empty = fontString(sidebar, "|cffaaaaaaNothing yet.|r")
    sidebar.empty:SetPoint("TOPLEFT", 10, -30)

    -- Neither renaming nor reordering leaves a mark on the panel, so they are
    -- said once here instead of being found by accident.
    sidebar.hint = fontString(sidebar,
        "|cff8a8a8fDouble-click a name to rename it.\nDrag a row to reorder.|r")
    sidebar.hint:SetPoint("BOTTOMLEFT", sidebar.newName, "TOPLEFT", 0, 6)
    sidebar.hint:SetWidth(SIDE_W - 20)
    sidebar.hint:SetJustifyH("LEFT")
    sidebar.hint:Hide()

    -- Content ------------------------------------------------------------------
    content = CreateFrame("Frame", nil, body)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 6, 0)
    content:SetPoint("BOTTOMRIGHT", -6, 6)

    -- On the divider between the two, which is where what it does is.
    body.sidebarToggle = panelButton(body, "<", GRIP, 44, function()
        UI.ToggleSidebar()
    end)
    body.sidebarToggle:SetPoint("RIGHT", content, "LEFT", -1, 0)

    IMI.Style.Panel(content)

    views = {}

    -- Run ----------------------------------------------------------------------
    views.run = CreateFrame("Frame", nil, content)
    views.run:SetAllPoints()

    views.run.title = IMI.Style.Header(views.run, "")
    views.run.title:SetFontObject("GameFontNormalLarge")
    views.run.title:SetTextColor(unpack(IMI.Style.colors.goldText))
    views.run.title:SetPoint("TOP", 0, -6)

    local nextBtn = CreateFrame("Button", "InomrahsMINext", views.run, "SecureHandlerClickTemplate")
    nextBtn:SetSize(26, 20)
    nextBtn:SetPoint("TOPRIGHT", -8, -6)
    skin(nextBtn, ">")
    IMI.Style.Tooltip(nextBtn, "Next page")

    local prevBtn = CreateFrame("Button", "InomrahsMIPrev", views.run, "SecureHandlerClickTemplate")
    prevBtn:SetSize(26, 20)
    prevBtn:SetPoint("RIGHT", nextBtn, "LEFT", -4, 0)
    skin(prevBtn, "<")
    IMI.Style.Tooltip(prevBtn, "Previous page")

    views.run.arrows = { prev = prevBtn, next = nextBtn }

    views.run.variant = UI.Dropdown(views.run, 150)
    views.run.variant:SetPoint("TOPLEFT", 10, -4)
    views.run.variant:Hide()

    views.run.prompt = fontString(views.run, "Pick a dungeon on the left.")
    views.run.prompt:SetPoint("TOPLEFT", 12, -34)

    views.run.pages = CreateFrame("Frame", nil, views.run)
    views.run.pages:SetPoint("TOPLEFT", 10, -46)
    views.run.pages:SetPoint("BOTTOMRIGHT", -10, 8)

    -- Edit ---------------------------------------------------------------------
    views.edit = CreateFrame("Frame", nil, content)
    views.edit:SetAllPoints()
    IMI.Edit.Build(views.edit)

    -- Settings -----------------------------------------------------------------
    views.settings = CreateFrame("Frame", nil, body)
    views.settings:SetPoint("TOPLEFT", 12, -12)
    views.settings:SetPoint("BOTTOMRIGHT", -12, 12)

    -- Scrolled, because the window can be as short as 300 and the settings are
    -- taller than that now the palette is in them. A page you cannot reach the
    -- bottom of is worse than one you have to scroll.
    local settingsScroll = CreateFrame("ScrollFrame", nil, views.settings,
        "UIPanelScrollFrameTemplate")
    settingsScroll:SetPoint("TOPLEFT")
    settingsScroll:SetPoint("BOTTOMRIGHT", -24, 0)
    IMI.Style.WheelScroll(settingsScroll)

    views.settings.page = CreateFrame("Frame", nil, settingsScroll)
    views.settings.page:SetSize(600, 620)
    settingsScroll:SetScrollChild(views.settings.page)
    views.settings.scroll = settingsScroll

    UI.BuildSettings(views.settings.page)

    showView("run")
    UI.RefreshSidebar()

    local s = Core.Settings()
    if s.point then
        root:ClearAllPoints()
        root:SetPoint(s.point.point, UIParent, s.point.relativePoint, s.point.x, s.point.y)
    end
    UI.ApplySettings()

    root:Hide()
    UI.root = root
    return root
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local SETTING_DEFAULTS = {
    opacity = 1.0, scale = 1.0, buttonScale = 1.0, textScale = 1.0,
}

function UI.BuildSettings(parent)
    local y = -8
    local rows = {}

    --- One setting: a slider, a value you can type into, and a reset.
    ---
    --- `live` decides whether dragging applies as it goes. Overall scale must
    --- not: scaling the window moves the slider out from under the cursor,
    --- which makes it almost impossible to aim. It commits when released, while
    --- the number updates as you drag so there is still feedback.
    local function row(labelText, key, minv, maxv, live, note)
        local text = fontString(parent, labelText)
        text:SetPoint("TOPLEFT", 12, y)

        local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT", 150, y + 4)
        slider:SetWidth(190)
        slider:SetMinMaxValues(minv, maxv)
        slider:SetValueStep(0.01)
        slider:SetObeyStepOnDrag(true)

        local box = CreateFrame("EditBox", nil, parent)
        box:SetFontObject("ChatFontNormal")
        IMI.Style.EditBox(box)
        box:SetSize(46, 20)
        box:SetPoint("LEFT", slider, "RIGHT", 16, 0)
        box:SetAutoFocus(false)
        box:SetMaxLetters(5)
        box:SetJustifyH("CENTER")

        local reset = panelButton(parent, "Reset", 52, 20)
        reset:SetPoint("LEFT", box, "RIGHT", 8, 0)

        local function apply(value)
            Core.Settings()[key] = value
            if not UI.ApplySettings() then
                Util.Print("|cffff4444settings apply out of combat.|r")
            end
        end

        local function show(value)
            box:SetText(("%.2f"):format(value))
        end

        slider:SetScript("OnMouseDown", function(self) self.dragging = true end)
        slider:SetScript("OnMouseUp", function(self)
            self.dragging = false
            apply(self:GetValue())
        end)

        slider:SetScript("OnValueChanged", function(self, value)
            show(value)
            -- Applying mid-drag is what made the window squirm; for the one
            -- setting that resizes the window, the number alone is feedback
            -- enough until the mouse comes up.
            if live then apply(value) end
        end)

        box:SetScript("OnEnterPressed", function(self)
            local value = tonumber((self:GetText() or ""):gsub(",", "."))
            if value then
                value = math.max(minv, math.min(maxv, value))
                slider:SetValue(value)
                apply(value)
            end
            show(Core.Settings()[key] or SETTING_DEFAULTS[key])
            self:ClearFocus()
        end)
        box:SetScript("OnEscapePressed", function(self)
            show(Core.Settings()[key] or SETTING_DEFAULTS[key])
            self:ClearFocus()
        end)

        reset:SetScript("OnClick", function()
            local value = SETTING_DEFAULTS[key]
            slider:SetValue(value)
            show(value)
            apply(value)
        end)

        if note then
            local n = fontString(parent, "|cff888888" .. note .. "|r")
            n:SetPoint("TOPLEFT", 14, y - 17)
            y = y - 14
        end

        rows[#rows + 1] = function()
            local value = Core.Settings()[key] or SETTING_DEFAULTS[key]
            slider:SetValue(value)
            show(value)
        end

        y = y - 36
        return slider
    end

    -- Where plain text goes. This decides whether a line reaches the group at
    -- all, so it sits above the cosmetic settings.
    local chanLabel = fontString(parent, "Send plain text to")
    chanLabel:SetPoint("TOPLEFT", 12, y)

    local chanBtn = panelButton(parent, Core.Settings().channel or Util.DEFAULT_CHANNEL, 80, 22)
    chanBtn:SetPoint("TOPLEFT", 150, y + 4)
    chanBtn:SetScript("OnClick", function(self)
        local current = Core.Settings().channel or Util.DEFAULT_CHANNEL
        local index = 1
        for i, c in ipairs(Util.CHANNELS) do
            if c == current then index = i break end
        end
        local nextChannel = Util.CHANNELS[index % #Util.CHANNELS + 1]
        Core.Settings().channel = nextChannel
        self:SetText(nextChannel)
        if IMI.Edit and IMI.Edit.RefreshSendHint then IMI.Edit.RefreshSendHint() end
        Util.Print(("plain text now goes to |cffffff00%s|r. Reopen the dungeon in Run to apply it.")
            :format(nextChannel))
    end)

    local chanNote = fontString(parent,
        "|cff888888A line starting with a slash command ignores this and runs as written.|r")
    chanNote:SetPoint("TOPLEFT", 14, y - 20)
    y = y - 50

    row("Opacity",      "opacity",     0.2, 1.0, true)
    row("Window scale", "scale",       0.6, 1.6, false,
        "Applies when you let go of the slider.")
    row("Button scale", "buttonScale", 0.6, 1.8, true,
        "Reopen the dungeon in Run to see it.")
    row("Text scale",   "textScale",   0.6, 1.6, true,
        "Reopen the dungeon in Run to see it.")

    -- Keybinds ---------------------------------------------------------------
    y = y - 16
    local bindsHeader = IMI.Style.Header(parent, "Keybinds")
    bindsHeader:SetPoint("TOPLEFT", 12, y)
    y = y - 24

    local bindRows = {}

    local toggleLabel = fontString(parent, "Open/close addon")
    toggleLabel:SetPoint("TOPLEFT", 14, y - 4)

    -- The same gesture as the page keybinds: click, then press. Capturing the
    -- keyboard only while this button is waiting, and letting Escape through.
    local toggleBtn = panelButton(parent, "", 130, 20, nil,
        { tip = "Open/close addon",
          tipDetail = "Works in combat, which the slash command cannot: the key "
                   .. "clicks a secure button rather than asking the addon to hide itself." })
    toggleBtn:SetPoint("TOPLEFT", 150, y)

    local capture = UI.KeyCapture(CreateFrame("Frame", nil, parent))

    toggleBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    toggleBtn:SetScript("OnClick", function(self, mouseButton)
        if InCombatLockdown() then
            Util.Print("|cffff4444can't change keys in combat.|r")
            return
        end
        if mouseButton == "RightButton" then
            Core.Settings().toggleKey = nil
            UI.ApplyToggleKey()
            UI.RefreshSettings()
            return
        end
        self:SetText("press a key")
        UI.ArmKeyCapture(capture, function(chord)
            Core.Settings().toggleKey = chord
            UI.ApplyToggleKey()
            UI.RefreshSettings()
        end, UI.RefreshSettings)
    end)

    bindRows[#bindRows + 1] = function()
        toggleBtn:SetText(IMI.Binds.Short(Core.Settings().toggleKey) or "Set")
    end
    y = y - 26

    --- A setting that is on or off, shown as the word rather than a box: the
    --- rest of this panel is buttons and the eye should not have to learn a
    --- second kind of control for two rows.
    local function toggleRow(labelText, key, note)
        local label = fontString(parent, labelText)
        label:SetPoint("TOPLEFT", 14, y - 4)

        local btn = panelButton(parent, "", 90, 20, function()
            local settings = Core.Settings()
            settings[key] = not (settings[key] ~= false)
            UI.RefreshSettings()
            -- Run redraws its buttons; Edit redraws its boxes.
            UI.Relayout()
        end, { tip = labelText, tipDetail = note })
        btn:SetPoint("TOPLEFT", 220, y)

        bindRows[#bindRows + 1] = function()
            btn:SetText((Core.Settings()[key] ~= false) and "Shown" or "Hidden")
        end
        y = y - 26
    end

    toggleRow("Show keybinds in Run mode", "showBindsRun",
        "The little box in a callout's corner. It only ever appears where a key "
        .. "is actually set.")
    toggleRow("Show keybinds in Edit mode", "showBindsEdit",
        "The same box on the callout lines in Edit.")

    -- The palette ----------------------------------------------------------
    -- One row per colour the interface actually uses, rather than a single
    -- theme colour: someone who wants to change the headings should not have to
    -- accept a new selection colour to get it.
    local THEME_ROWS = {
        { key = "gold",     name = "Panel edges" },
        { key = "goldText", name = "Headings" },
        { key = "accent",   name = "Selection" },
        { key = "text",     name = "Text" },
        { key = "textDim",  name = "Faint text" },
    }

    y = y - 16
    local paletteHeader = IMI.Style.Header(parent, "Colours")
    paletteHeader:SetPoint("TOPLEFT", 12, y)
    y = y - 22

    local swatchRows = {}
    for _, entry in ipairs(THEME_ROWS) do
        local swatchFrame = CreateFrame("Frame", nil, parent)
        swatchFrame:SetSize(20, 20)
        swatchFrame:SetPoint("TOPLEFT", 14, y)
        IMI.Style.Border(swatchFrame, IMI.Style.colors.rowEdge)
        local swatch = swatchFrame:CreateTexture(nil, "ARTWORK")
        swatch:SetAllPoints()

        local button = panelButton(parent, entry.name, 120, 20, function()
            IMI.Picker.Open({
                title = entry.name,
                color = IMI.Style.UserColor(entry.key) or IMI.Style.colors[entry.key],
                onChange = function(color)
                    Core.Settings().colors = Core.Settings().colors or {}
                    Core.Settings().colors[entry.key] = color
                    IMI.Style.SetUserColor(entry.key, color)
                    UI.RefreshSettings()
                end,
                onReset = function()
                    if Core.Settings().colors then
                        Core.Settings().colors[entry.key] = nil
                    end
                    IMI.Style.SetUserColor(entry.key, nil)
                    UI.RefreshSettings()
                end,
            })
        end, { tip = entry.name, tipDetail = "Applies everywhere, under any dungeon colour." })
        button:SetPoint("TOPLEFT", 40, y)

        swatchRows[#swatchRows + 1] = function()
            swatch:SetColorTexture(IMI.Color.Unpack(
                IMI.Style.UserColor(entry.key) or IMI.Style.colors[entry.key]))
        end
        y = y - 24
    end

    local resetColors = panelButton(parent, "Reset colours", 110, 20, function()
        Core.Settings().colors = {}
        IMI.Style.ResetUserColors()
        UI.RefreshSettings()
        Util.Print("colours reset.")
    end, { tip = "Reset colours",
           tipDetail = "Back to the addon's own palette. Dungeon colours are kept." })
    resetColors:SetPoint("TOPLEFT", 40, y)
    y = y - 30

    local resetAll = panelButton(parent, "Reset all", 90, 22, function()
        for key, value in pairs(SETTING_DEFAULTS) do
            Core.Settings()[key] = value
        end
        Core.Settings().colors = {}
        IMI.Style.ResetUserColors()
        -- Keys are not a cosmetic default. Resetting the sliders should not
        -- silently take away a binding someone set up.
        UI.ApplySettings()
        UI.RefreshSettings()
        Util.Print("settings reset.")
    end)
    resetAll:SetPoint("TOPLEFT", 12, y - 4)

    local note = fontString(parent,
        "|cff888888Scale and opacity apply out of combat only.|r")
    note:SetPoint("TOPLEFT", 110, y - 10)

    --- Pull every control back in line with what is stored. Used by Reset all,
    --- which changes the values behind the widgets.
    function UI.RefreshSettings()
        for _, refresh in ipairs(rows) do refresh() end
        for _, refresh in ipairs(bindRows) do refresh() end
        for _, refresh in ipairs(swatchRows) do refresh() end
        if chanBtn then chanBtn:SetText(Core.Settings().channel or Util.DEFAULT_CHANNEL) end
    end

    -- The page is a scroll child, so it has to be as tall as what is on it
    -- rather than as tall as the window.
    parent:SetHeight(math.max(200, math.abs(y) + 40))

    UI.RefreshSettings()
end

--------------------------------------------------------------------------------
-- The string window, used for both export and import
--------------------------------------------------------------------------------

local stringWindow

local function ensureStringWindow()
    if stringWindow then return stringWindow end

    local f = CreateFrame("Frame", "InomrahsMIStringWindow", UIParent,
        "BasicFrameTemplateWithInset")
    f:SetSize(560, 300)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("TOP", f.TitleBg, "TOP", 0, -5)

    local scroll = CreateFrame("ScrollFrame", "InomrahsMIStringScroll", f,
        "UIPanelScrollFrameTemplate")
    IMI.Style.WheelScroll(scroll)
    scroll:SetPoint("TOPLEFT", 14, -32)
    scroll:SetPoint("BOTTOMRIGHT", -34, 44)

    f.editBox = CreateFrame("EditBox", nil, scroll)
    f.editBox:SetMultiLine(true)
    f.editBox:SetMaxLetters(0)
    f.editBox:SetAutoFocus(false)
    f.editBox:SetFontObject(ChatFontNormal)
    f.editBox:SetWidth(500)
    f.editBox:SetHeight(220)
    -- Clearing focus before hiding, not instead of it. A focused multi-line
    -- box takes every key you press, so leaving it focused turns the rest of
    -- the keyboard off — and hiding the frame is not reliably enough to let go.
    f.editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        f:Hide()
    end)
    f:HookScript("OnHide", function() f.editBox:ClearFocus() end)
    scroll:SetScrollChild(f.editBox)

    f.action = panelButton(f, "", 110, 22)
    f.action:SetPoint("BOTTOMRIGHT", -16, 14)

    -- A way out that needs no keyboard, because the keyboard is exactly what
    -- you may not have while a box holds it.
    f.select = panelButton(f, "Select all", 90, 22, function()
        f.editBox:SetFocus()
        f.editBox:HighlightText()
    end, { tip = "Select all", tipDetail = "Then Ctrl-C, or Cmd-C on a Mac." })
    f.select:SetPoint("BOTTOMRIGHT", f.action, "BOTTOMLEFT", -6, 0)

    f.release = panelButton(f, "Done typing", 96, 22, function()
        f.editBox:ClearFocus()
    end, { tip = "Done typing", tipDetail = "Gives the keyboard back to the game." })
    f.release:SetPoint("BOTTOMRIGHT", f.select, "BOTTOMLEFT", -6, 0)

    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("BOTTOMLEFT", 18, 20)

    stringWindow = f
    return f
end

--- The copy window and its box, for tests: whether it holds the keyboard is
--- the behaviour, and it is invisible from anywhere else.
function UI.StringWindow() return stringWindow end
function UI.StringBox() return stringWindow and stringWindow.editBox end

function UI.ShowExport(title, text)
    local f = ensureStringWindow()
    f.title:SetText(title)
    f.hint:SetText("Select all, then Ctrl-C (Cmd-C on a Mac)")
    f.editBox:SetText(text or "")
    f.action:SetText("Close")
    f.action:SetScript("OnClick", function() f:Hide() end)
    f:Show()
    -- Not focused on open. Taking the keyboard because something is ready to
    -- copy is a trade nobody agreed to; Select all is one click away.
    f.editBox:ClearFocus()
end

function UI.ShowImport(title, onImport)
    local f = ensureStringWindow()
    f.title:SetText(title)
    f.hint:SetText("Paste here, then Import. Nothing is overwritten.")
    f.editBox:SetText("")
    f.action:SetText("Import")
    f.action:SetScript("OnClick", function()
        local what, err = onImport(f.editBox:GetText())
        if what then
            Util.Print(("imported %s."):format(what))
            f:Hide()
        else
            Util.Print("|cffff4444" .. (err or "import failed") .. "|r")
        end
    end)
    f:Show()
    f.editBox:SetFocus()
end

--------------------------------------------------------------------------------
-- Entry points
--------------------------------------------------------------------------------

--- What the addon does and the two rules that are not obvious from using it:
--- that editing is out-of-combat work, and that nothing reaches disk until a
--- reload. Both are the kind of thing people discover by losing something.
function UI.ShowHelp()
    UI.ShowExport("Inomrah's Mythic Instructions - how it works", table.concat({
        "RUN",
        "  Pick a dungeon on the left, then press a button to send its callout.",
        "  < and > step through the pages of the route.",
        "  Buttons and page arrows work in combat.",
        "",
        "EDIT",
        "  Pick a dungeon on the left, or make one with New dungeon.",
        "  Enemies: give an enemy a name, then add lines under it. Click any box",
        "  and type straight into it. A line is one macro: /p, /i, /cast, and so on.",
        "  Pages: choose which enemies appear on which page of the route.",
        "",
        "WHAT COMBAT BLOCKS",
        "  Loading a dungeon, editing, and changing scale all need to be out of",
        "  combat - the game refuses them mid-fight. Pressing buttons and flipping",
        "  pages are fine in combat, which is what matters.",
        "",
        "SAVING",
        "  WoW writes addon data on logout or /reload, not continuously. After a",
        "  real editing session, /reload. Export gives you a string to keep",
        "  outside the game; a crash cannot take that with it.",
        "",
        "LIMITS",
        "  A macro line caps at 255 characters. The counter appears in whichever",
        "  box you are typing in.",
        "",
        "COMMANDS",
        "  /imi           open or close",
        "  /imi starter   add this season's dungeons",
        "  /imi add       add your current target as an enemy",
        "  /imi demo      a sample dungeon with content in it",
    }, "\n"))
end

function UI.Toggle()
    if not root then return end
    if root:IsShown() then root:Hide() else root:Show() end
end

function UI.Show(view)
    if not root then return end
    root:Show()
    if view then showView(view) end
end

function UI.RefreshCategories()
    if sidebar then UI.RefreshSidebar() end
end

function UI.Arrows()
    return views and views.run and views.run.arrows
end
