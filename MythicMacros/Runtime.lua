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

local ADDON, MM = ...

MM.Runtime = {}
local Runtime = MM.Runtime
local Util = MM.Util
local Core = MM.Core

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
local CARD_GAP, LINE_GAP = 10, 3
local HEADER_H = 16

--------------------------------------------------------------------------------
-- The pager
--
-- The index lives on a manager frame that both arrows reference, so the two
-- arrows cannot disagree about which page is current. The snippet does the
-- show/hide itself: handing that work back to insecure code would put it right
-- back under the combat restriction this exists to avoid.
--------------------------------------------------------------------------------

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
]]

local manager

local function ensureManager(parent)
    if manager then return manager end
    manager = CreateFrame("Frame", "MythicMacrosPager", parent, "SecureHandlerBaseTemplate")
    manager:SetSize(1, 1)
    manager:SetPoint("TOPLEFT")
    return manager
end

--- Wire an arrow to the manager. `delta` is -1 for back, 1 for forward.
function Runtime.BindArrow(button, delta)
    button:RegisterForClicks("AnyUp")   -- one click type only: registering both
                                        -- up and down fires the action twice
    button:SetFrameRef("manager", manager)
    button:SetAttribute("delta", delta)
    button:SetAttribute("_onclick", FLIP_SNIPPET)
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

    page = CreateFrame("Frame", "MythicMacrosPage" .. index, parent,
        "SecureHandlerBaseTemplate")
    page:SetAllPoints(parent)
    page:Hide()

    -- The page name is drawn by the page itself. The restricted environment
    -- cannot set text, so a single shared title could never follow the flip;
    -- giving each page its own means it shows and hides with its contents.
    page.title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    page.title:SetPoint("BOTTOMLEFT", page, "TOPLEFT", 0, 6)

    frames.pages[index] = page
    frames.buttons[index] = {}
    return page
end

local function acquireButton(pageIndex, page, buttonIndex)
    local pool = frames.buttons[pageIndex]
    local button = pool[buttonIndex]
    if button then return button end

    button = CreateFrame("Button", ("MythicMacrosBtn%d_%d"):format(pageIndex, buttonIndex),
        page, "SecureActionButtonTemplate")
    button:SetSize(BUTTON_W, BUTTON_H)
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("type", "macro")

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.13, 0.13, 0.18, 0.92)
    button.bg = bg

    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.label:SetPoint("LEFT", 6, 0)
    button.label:SetPoint("RIGHT", -6, 0)
    button.label:SetJustifyH("LEFT")

    button:SetScript("OnEnter", function() bg:SetColorTexture(0.22, 0.22, 0.30, 0.95) end)
    button:SetScript("OnLeave", function() bg:SetColorTexture(0.13, 0.13, 0.18, 0.92) end)

    pool[buttonIndex] = button
    return button
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

--- Lay one page out: enemy cards left to right, wrapping at the container edge,
--- each card a name over its lines. An enemy's perRow decides whether its lines
--- stack or fill across, which is what makes a boss compact.
local function layoutPage(page, pageIndex, catId, pageData, width, settings)
    local enemies = Core.PageEnemies(catId, pageData.id)
    local buttonIndex = 0

    local x, y, rowHeight = 0, 0, 0
    local scale = settings and settings.buttonScale or 1
    local bw, bh = BUTTON_W * scale, BUTTON_H * scale

    for _, enemy in ipairs(enemies) do
        local perRow = math.max(1, enemy.perRow or 1)
        local lines  = enemy.lines
        local cols   = math.min(perRow, math.max(1, #lines))
        local rows   = math.ceil(#lines / cols)

        local cardW = cols * bw + (cols - 1) * LINE_GAP
        local cardH = HEADER_H + rows * bh + (rows - 1) * LINE_GAP

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
            page.headers[enemy.id] = header
        end
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
        header:SetWidth(cardW)
        header:SetJustifyH("LEFT")
        header:SetText(enemy.name)
        header:Show()

        for i, line in ipairs(lines) do
            buttonIndex = buttonIndex + 1
            local button = acquireButton(pageIndex, page, buttonIndex)

            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)

            button:ClearAllPoints()
            button:SetSize(bw, bh)
            button:SetPoint("TOPLEFT", page, "TOPLEFT",
                x + col * (bw + LINE_GAP),
                y - HEADER_H - row * (bh + LINE_GAP))

            -- The whole point: the line's text, on the button, set now, while
            -- we are out of combat and allowed to.
            button:SetAttribute("macrotext", line.body or "")
            button.label:SetText(Util.ButtonLabel(line))
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
    for index, pageData in ipairs(cat.pages) do
        local page = acquirePage(container, index)
        manager:SetFrameRef("page" .. index, page)
        local height = layoutPage(page, index, catId, pageData, width, settings)
        tallest = math.max(tallest, height)
        page:Hide()
    end

    -- Retire pages the previous category needed and this one does not.
    for index = #cat.pages + 1, #frames.pages do
        frames.pages[index]:Hide()
        manager:SetFrameRef("page" .. index, nil)
    end

    manager:SetAttribute("pageCount", #cat.pages)
    manager:SetAttribute("pageIndex", 1)

    if frames.pages[1] and #cat.pages > 0 then
        frames.pages[1]:Show()
    end

    built.categoryId = catId
    built.pageCount  = #cat.pages
    return true, nil, tallest
end

function Runtime.BuiltCategory()
    return built.categoryId
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

--- Hide everything. Used when leaving Run for Edit, where stale secure buttons
--- would otherwise sit under the editor.
function Runtime.HideAll()
    for _, page in ipairs(frames.pages) do
        page:Hide()
    end
end
