--------------------------------------------------------------------------------
-- Runtime: turning a category into pressable buttons.
--
-- Everything here is shaped by what the probe measured on 12.1.0:
--
--   * macrotext executes, in combat, during a boss encounter and inside a
--     keystone. So a line's text lives on its button and no character macros
--     are created.
--   * SetAttribute is blocked in combat. So buttons are written once, when a
--     category is selected, and never touched again while playing.
--   * Plain Hide() on a frame with a protected child is blocked in combat. So
--     pages cannot be swapped by ordinary code.
--   * A secure-handler flip driven by a hardware click works in combat. So the
--     page arrows are secure handlers, and the flip happens entirely inside the
--     restricted environment.
--   * A scripted :Click() on a secure handler is refused. Nothing here drives
--     the arrows from Lua.
--
-- The consequence: one frame per page, all built up front, all their buttons
-- carrying their final text. Playing is show/hide and clicking, which is all
-- combat permits.
--------------------------------------------------------------------------------

local ADDON, IMI = ...

IMI.Runtime = {}
local Runtime = IMI.Runtime
local Util = IMI.Util
local Core = IMI.Core

local frames = {
    pages   = {},   -- page frame pool, index-keyed
    buttons = {},   -- button pool per page frame
}

local built = {
    categoryId = nil,
    pageCount  = 0,
}

--------------------------------------------------------------------------------
-- Layout constants
--------------------------------------------------------------------------------

local BUTTON_W, BUTTON_H = 150, 22

-- A callout that does not fit on one line gets a second, because half a
-- sentence is a worse prompt mid-pull than a slightly taller button. Past two
-- it ends in an ellipsis: the tooltip carries the whole line, and a button tall
-- enough for a paragraph stops being something you hit by sight.
local MAX_LABEL_LINES = 2
local CARD_GAP, LINE_GAP = 10, 3
local HEADER_H = 16

--- The strip at the top of a page that holds its name. Inside the page, not
--- above it: the pages sit in a scroll frame now, and anything anchored above
--- the scroll child's top edge is clipped away rather than drawn.
local PAGE_TITLE_H = 16

--------------------------------------------------------------------------------
-- The pager
--
-- The index lives on a manager frame that both arrows reference, so the two
-- arrows cannot disagree about which page is current. The snippet does the
-- show/hide itself: handing that work back to insecure code would put it right
-- back under the combat restriction this exists to avoid.
--------------------------------------------------------------------------------

--- Applies one page's keys, plus the two paging keys that carry across pages.
---
--- Written as a string once and pasted into both the flip snippet and the
--- manager's own, because the restricted environment has no way to call a
--- shared function: a snippet is a string, not a closure.
local BIND_BODY = [[
    m:ClearBindings()

    local page = m:GetFrameRef("page" .. index)
    if page then
        local binds = page:GetAttribute("bindCount") or 0
        for i = 1, binds do
            local key = page:GetAttribute("bindKey" .. i)
            local target = page:GetFrameRef("bindButton" .. i)
            if key and target then
                m:SetBindingClick(true, key, target)
            end
        end
    end

    local nextKey, nextButton = m:GetAttribute("nextKey"), m:GetFrameRef("nextButton")
    if nextKey and nextButton then m:SetBindingClick(true, nextKey, nextButton) end

    local prevKey, prevButton = m:GetAttribute("prevKey"), m:GetFrameRef("prevButton")
    if prevKey and prevButton then m:SetBindingClick(true, prevKey, prevButton) end
]]

local FLIP_SNIPPET = [[
    local m = self:GetFrameRef("manager")
    if not m then return end

    local count = m:GetAttribute("pageCount") or 0
    if count < 1 then return end

    local index = (m:GetAttribute("pageIndex") or 1) + (self:GetAttribute("delta") or 1)
    if index < 1 then index = count elseif index > count then index = 1 end
    m:SetAttribute("pageIndex", index)

    for i = 1, count do
        local page = m:GetFrameRef("page" .. i)
        if page then
            if i == index then page:Show() else page:Hide() end
        end
    end
]] .. BIND_BODY

-- Run on the manager itself, so a page shown from outside combat rebinds by the
-- same code path a flip does. Two implementations of "which keys are live" is
-- exactly the pair that drifts.
local REBIND_SNIPPET = [[
    local m = self
    local index = m:GetAttribute("pageIndex") or 1
]] .. BIND_BODY

local manager
local arrowNames = {}

local function ensureManager(parent)
    if manager then return manager end
    manager = CreateFrame("Frame", "InomrahsMIPager", parent, "SecureHandlerBaseTemplate")
    manager:SetSize(1, 1)
    manager:SetPoint("TOPLEFT")

    -- Named so the manager can run it on itself when a page is shown from
    -- outside the restricted environment.
    if type(manager.SetAttribute) == "function" then
        manager:SetAttribute("_rebind", REBIND_SNIPPET)
    end
    return manager
end

--- The manager must exist before the arrows are bound, and the arrows are built
--- with the UI, well before any category is loaded.
function Runtime.EnsureManager(parent)
    return ensureManager(parent)
end

--- Wire an arrow to the manager. `delta` is -1 for back, 1 for forward.
function Runtime.BindArrow(button, delta)
    -- A button that inherited a second template alongside its secure one has no
    -- SetFrameRef. Saying so beats throwing during login, where the error lands
    -- before anything is on screen to explain it.
    if type(button.SetFrameRef) ~= "function" then
        Util.Print("|cffff4444page arrows are not secure handlers - "
            .. "paging will not work. This is a bug.|r")
        return false
    end

    IMI.UI.RegisterClicks(button, "AnyUp")  -- one click type only: registering both
                                        -- up and down fires the action twice
    button:SetFrameRef("manager", manager)
    button:SetAttribute("delta", delta)
    button:SetAttribute("_onclick", FLIP_SNIPPET)

    -- Both directions are reachable from the manager, so a paging key can be
    -- bound to one without knowing which frame the UI built.
    manager:SetFrameRef(delta > 0 and "nextButton" or "prevButton", button)
    arrowNames[delta > 0 and "next" or "prev"] = button:GetName()
    return true
end

--------------------------------------------------------------------------------
-- Pools
--
-- Frames cannot be destroyed once created, and cannot be created in combat, so
-- everything is reused. A rebuild hides what it does not need rather than
-- leaking a new frame per category switch.
--------------------------------------------------------------------------------

local function acquirePage(parent, index)
    local page = frames.pages[index]
    if page then return page end

    page = CreateFrame("Frame", "InomrahsMIPage" .. index, parent,
        "SecureHandlerBaseTemplate")
    page:SetAllPoints(parent)
    page:Hide()

    -- The page name is drawn by the page itself. The restricted environment
    -- cannot set text, so a single shared title could never follow the flip;
    -- giving each page its own means it shows and hides with its contents.
    page.title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    page.title:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -2)

    frames.pages[index] = page
    frames.buttons[index] = {}
    return page
end

local function acquireButton(pageIndex, page, buttonIndex)
    local pool = frames.buttons[pageIndex]
    local button = pool[buttonIndex]
    if button then return button end

    button = CreateFrame("Button", ("InomrahsMIBtn%d_%d"):format(pageIndex, buttonIndex),
        page, "SecureActionButtonTemplate")
    button:SetSize(BUTTON_W, BUTTON_H)
    -- Both directions, matching the configuration the probe proved fires. An
    -- earlier version registered only AnyUp, on the theory that both would
    -- double-send. The probe data said otherwise: two click records, one
    -- message. The theory lost to the measurement.
    IMI.UI.RegisterClicks(button, "AnyUp", "AnyDown")
    -- Explicit, not assumed. The probe's working buttons enabled the mouse and
    -- these did not, and a button that never receives the click is
    -- indistinguishable from one whose action is refused.
    button:EnableMouse(true)
    button:SetAttribute("type", "macro")

    -- Same appearance as every other button, from the same place, so a callout
    -- does not look like a different kind of control from the ones around it.
    IMI.Style.Button(button, "", { justify = "LEFT", maxLines = MAX_LABEL_LINES })

    pool[buttonIndex] = button
    return button
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

--- Lay one page out: enemy cards left to right, wrapping at the container edge,
--- each card a name over its lines. An enemy's perRow decides whether its lines
--- stack or fill across, which is what makes a boss compact.
-- The callout buttons and enemy headers are scaled here rather than through
-- Style's register, because they are rebuilt per dungeon and the scale has to
-- be applied as they are laid out anyway.
local applyTextScale = IMI.Style.ApplyTextScale

--- How many lines a label will take on a button this wide, and how tall a line
--- is at the current text scale.
---
--- Measured rather than guessed from a character count: how much fits depends
--- on the font, the size, the text-scale setting and which characters they are
--- — "iiiiiiii" and "WWWWWWWW" are not the same width. GetStringWidth reports
--- the unwrapped width, which is exactly the question being asked.
---
--- One hidden font string per page does the measuring, so this costs no frames.
local function measureLabel(page, text, available, textScale)
    local m = page.measure
    if not m then
        m = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        m:Hide()
        page.measure = m
    end

    applyTextScale(m, textScale)
    m:SetText(text or "")

    local textWidth, lineHeight = m:GetStringWidth(), m:GetStringHeight()
    if type(lineHeight) ~= "number" or lineHeight <= 0 then
        -- No client to ask. One line, and a height that will not collapse.
        return 1, 12 * (textScale or 1)
    end

    local lines = 1
    if type(textWidth) == "number" and available > 0 and textWidth > available then
        lines = math.min(MAX_LABEL_LINES, math.ceil(textWidth / available))
    end
    return lines, lineHeight
end

local function layoutPage(page, pageIndex, catId, pageData, width, settings)
    local enemies = Core.PageEnemies(catId, pageData.id)
    local buttonIndex = 0

    -- Keys for this page, held two ways: as attributes, the only shape the
    -- restricted environment can read, and as a plain list for the path used
    -- out of combat. Both written here so the two cannot disagree.
    local binds = Core.PageBinds(catId, pageData.id)
    local bindCount = 0
    page.bindList = {}

    local x, y, rowHeight = 0, -PAGE_TITLE_H, 0
    local scale = settings and settings.buttonScale or 1
    local bw, bh = BUTTON_W * scale, BUTTON_H * scale

    for _, enemy in ipairs(enemies) do
        local perRow = math.max(1, enemy.perRow or 1)
        local lines  = enemy.lines
        local cols   = math.min(perRow, math.max(1, #lines))
        local rows   = math.ceil(#lines / cols)

        -- One height for the whole card, taken from its longest label, so the
        -- buttons under an enemy stay a grid rather than a ragged stack. The
        -- insets match Style.Button's left and right label anchors.
        local textScale = (settings and settings.textScale) or 1
        local available = bw - 14
        local cardLines = 1
        for _, line in ipairs(lines) do
            local needed = measureLabel(page, Util.ButtonLabel(line), available, textScale)
            if needed > cardLines then cardLines = needed end
        end

        local _, lineHeight = measureLabel(page, "Ag", available, textScale)
        local cardBH = bh
        if cardLines > 1 then cardBH = bh + (cardLines - 1) * lineHeight end

        local cardW = cols * bw + (cols - 1) * LINE_GAP
        local cardH = HEADER_H + rows * cardBH + (rows - 1) * LINE_GAP

        -- Wrap when the card would overhang. Auto-wrap keeps left-to-right
        -- order and only chooses where to break.
        if x > 0 and (x + cardW) > width then
            x = 0
            y = y - rowHeight - CARD_GAP
            rowHeight = 0
        end

        local header = page.headers and page.headers[enemy.id]
        if not header then
            page.headers = page.headers or {}
            header = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            header:SetTextColor(unpack(IMI.Style.colors.goldText))
            page.headers[enemy.id] = header
        end
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
        header:SetWidth(cardW)
        header:SetJustifyH("LEFT")
        header:SetText(enemy.name)
        applyTextScale(header, textScale)
        -- Held to one line for the same reason the buttons are held to two: a
        -- long name anchored across the card width would wrap down onto the
        -- callouts underneath it.
        header:SetWordWrap(false)
        header:SetMaxLines(1)
        header:Show()

        for i, line in ipairs(lines) do
            buttonIndex = buttonIndex + 1
            local button = acquireButton(pageIndex, page, buttonIndex)

            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)

            button:ClearAllPoints()
            button:SetSize(bw, cardBH)
            button:SetPoint("TOPLEFT", page, "TOPLEFT",
                x + col * (bw + LINE_GAP),
                y - HEADER_H - row * (cardBH + LINE_GAP))

            -- The whole point: the line's text, on the button, set now, while
            -- we are out of combat and allowed to. Plain text gains the chosen
            -- channel; a body that already starts with a slash command is left
            -- exactly as written.
            local channel = (settings and settings.channel) or Util.DEFAULT_CHANNEL
            local macro = Util.ComposeMacro(line.body, channel)

            button:SetAttribute("macrotext", macro)
            button.label:SetText(Util.ButtonLabel(line))
            button.macroText = macro

            local key = binds[line.id]
            button.boundKey = key

            if not button.badge then
                button.badge = IMI.Style.KeyBadge(button)
                button.badge:SetPoint("TOPLEFT", 2, -2)
            end
            -- Only ever shown where a key exists, whatever the setting says:
            -- an empty badge is a smudge on the corner of a button.
            button.badge:SetKey(settings and settings.showBindsRun ~= false
                and IMI.Binds.Short(key) or nil)
            if key then
                bindCount = bindCount + 1
                page:SetAttribute("bindKey" .. bindCount, key)
                page:SetFrameRef("bindButton" .. bindCount, button)
                page.bindList[bindCount] = { key = key, button = button }
            end

            -- Text scale is separate from button scale on purpose: a bigger hit
            -- target and a bigger caption are different needs, and one should
            -- not force the other.
            applyTextScale(button.label, textScale)

            button:SetScript("OnEnter", function(self)
                self.hovered = true
                self:Repaint()
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(enemy.name, 1, 0.82, 0)
                GameTooltip:AddLine(self.macroText or "", 1, 1, 1, true)
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", function(self)
                self.hovered = false
                self:Repaint()
                GameTooltip:Hide()
            end)

            button:Show()
        end

        x = x + cardW + CARD_GAP
        rowHeight = math.max(rowHeight, cardH)
    end

    -- Hide leftovers from whatever this page showed last.
    local pool = frames.buttons[pageIndex]
    for i = buttonIndex + 1, #pool do
        pool[i]:Hide()
    end

    -- Cleared past the count, so a page that lost a key does not keep firing
    -- the one left in the attribute from its previous build.
    page:SetAttribute("bindCount", bindCount)
    for i = bindCount + 1, (page.lastBindCount or 0) do
        page:SetAttribute("bindKey" .. i, nil)
    end
    page.lastBindCount = bindCount

    page.title:SetText(pageData.name or "")
    return math.abs(y) + rowHeight
end

--- Build every page of a category. Out of combat only: this writes attributes,
--- which combat forbids. Returns false and a reason rather than half-building.
function Runtime.Build(container, catId, settings)
    if InCombatLockdown() then
        return false, "can't load a dungeon in combat"
    end

    local cat = Core.GetCategory(catId)
    if not cat then
        return false, "category not found"
    end

    ensureManager(container)

    local width = container:GetWidth()
    if not width or width < 1 then width = 600 end

    local tallest = 0
    for index, pageData in ipairs(Core.Pages(catId)) do
        local page = acquirePage(container, index)
        manager:SetFrameRef("page" .. index, page)
        local height = layoutPage(page, index, catId, pageData, width, settings)
        tallest = math.max(tallest, height)
        page:Hide()
    end

    -- Retire pages the previous category needed and this one does not.
    for index = #Core.Pages(catId) + 1, #frames.pages do
        frames.pages[index]:Hide()
        manager:SetFrameRef("page" .. index, nil)
    end

    manager:SetAttribute("pageCount", #Core.Pages(catId))
    manager:SetAttribute("pageIndex", 1)

    if frames.pages[1] and #Core.Pages(catId) > 0 then
        frames.pages[1]:Show()
    end

    -- The paging keys are the same for every dungeon, so they are refreshed
    -- with each build rather than left over from the last one.
    local s = Core.Settings()
    manager:SetAttribute("nextKey", s.pageNextKey)
    manager:SetAttribute("prevKey", s.pagePrevKey)

    built.categoryId = catId
    built.pageCount  = #Core.Pages(catId)
    return true, nil, tallest
end

--- Show a specific page. Only ever called out of combat, from opening a
--- dungeon: in combat the pager is the only thing allowed to change pages, and
--- it does so from inside the restricted environment.
function Runtime.ShowPage(index)
    if not manager or built.pageCount == 0 then return false end
    if InCombatLockdown() then return false end

    index = tonumber(index) or 1
    if index < 1 or index > built.pageCount then index = 1 end

    for i = 1, #frames.pages do
        local page = frames.pages[i]
        if page then
            if i == index then page:Show() else page:Hide() end
        end
    end

    manager:SetAttribute("pageIndex", index)
    Runtime.ApplyBindings(index)
    return true
end

--- Makes this page's keys the live ones, out of combat.
---
--- Plain override bindings rather than the manager's snippet, because this path
--- only ever runs out of combat and the plain API is one that certainly exists.
--- Both paths own their bindings through the manager, so the snippet's
--- ClearBindings takes these away as readily as its own.
function Runtime.ApplyBindings(index)
    if not manager or InCombatLockdown() then return false end
    if type(ClearOverrideBindings) ~= "function"
        or type(SetOverrideBindingClick) ~= "function" then
        return false
    end

    ClearOverrideBindings(manager)

    local page = frames.pages[tonumber(index) or 1]
    for _, entry in ipairs(page and page.bindList or {}) do
        local name = entry.button and entry.button:GetName()
        if entry.key and name then
            SetOverrideBindingClick(manager, true, entry.key, name)
        end
    end

    -- The paging keys are the same on every page, so they are applied here
    -- rather than stored per page.
    local settings = Core.Settings()
    if settings.pageNextKey and arrowNames.next then
        SetOverrideBindingClick(manager, true, settings.pageNextKey, arrowNames.next)
    end
    if settings.pagePrevKey and arrowNames.prev then
        SetOverrideBindingClick(manager, true, settings.pagePrevKey, arrowNames.prev)
    end
    return true
end

--- The keys that turn the page. Kept on the manager as well, because a flip in
--- combat rebinds from there and cannot read a setting.
function Runtime.SetPageKeys(nextKey, prevKey)
    if not manager then return false end
    manager:SetAttribute("nextKey", nextKey)
    manager:SetAttribute("prevKey", prevKey)
    return Runtime.ApplyBindings(Runtime.CurrentPage() or 1)
end

--- Every key this dungeon currently answers to, for showing conflicts.
function Runtime.BoundKeys(index)
    local page = frames.pages[tonumber(index) or 1]
    local out = {}
    for _, entry in ipairs(page and page.bindList or {}) do
        out[entry.key] = true
    end
    return out
end

--- The pager, for tests: what is bound is owned by it.
function Runtime.Manager() return manager end

function Runtime.BuiltCategory()
    return built.categoryId
end

--- One page's buttons, for tests: the layout's sizing is not visible any other
--- way from outside.
--- A built page, for tests. Its name is drawn by the page itself, and where
--- that name is anchored decides whether it is visible at all once the pages
--- are inside something that clips them.
function Runtime.Page(index) return frames.pages[index] end

function Runtime.PageButtons(pageIndex)
    return frames.buttons[pageIndex]
end

function Runtime.PageCount()
    return built.pageCount
end

--- Which page is showing. Read from the manager rather than tracked separately,
--- because the flip happens inside the restricted environment and any copy kept
--- out here would drift the moment an arrow is pressed in combat.
function Runtime.CurrentPage()
    if not manager then return 1 end
    return manager:GetAttribute("pageIndex") or 1
end

--- What is actually on the buttons, and whether clicks reach them.
---
--- "Nothing happened" has at least three causes that look identical from
--- outside: the button never got its text, the click never landed, or the click
--- landed and the game refused the action. This separates them, which is the
--- same thing the probe had to do before any of this could be built.
function Runtime.Debug()
    Util.Print(("built category: %s, pages: %d"):format(
        tostring(built.categoryId), built.pageCount))
    Util.Print(("manager: %s, pageIndex: %s"):format(
        manager and "yes" or "MISSING",
        manager and tostring(manager:GetAttribute("pageIndex")) or "-"))

    for pageIndex = 1, built.pageCount do
        local page = frames.pages[pageIndex]
        if page then
            Util.Print(("page %d: shown=%s buttons=%d"):format(
                pageIndex, tostring(page:IsShown()), #(frames.buttons[pageIndex] or {})))

            for i, button in ipairs(frames.buttons[pageIndex] or {}) do
                if button:IsShown() then
                    Util.Print(("  [%d.%d] type=%s clicks=%s"):format(
                        pageIndex, i,
                        tostring(button:GetAttribute("type")),
                        tostring(button:GetAttribute("macrotext")) ))

                    -- One hook, once, reporting that the click arrived. If this
                    -- prints and nothing is sent, the fault is the action being
                    -- refused, not the button being dead.
                    if not button.debugHooked then
                        button.debugHooked = true
                        button:HookScript("OnClick", function(self, mouseButton, down)
                            Util.Print(("|cff33ff99click|r on [%d.%d] down=%s combat=%s"):format(
                                pageIndex, i, tostring(down), tostring(InCombatLockdown())))
                        end)
                    end
                end
            end
        end
    end

    Util.Print("now press a button. A 'click' line means it reached the button.")
end

--- Hide everything. Used when leaving Run for Edit, where stale secure buttons
--- would otherwise sit under the editor.
function Runtime.HideAll()
    for _, page in ipairs(frames.pages) do
        page:Hide()
    end
end
