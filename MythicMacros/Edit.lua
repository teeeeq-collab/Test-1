--------------------------------------------------------------------------------
-- Edit: the right-hand panel.
--
-- Two tabs for whichever dungeon the sidebar has selected.
--
--   Enemies -- a card per enemy: a name box, its lines stacked underneath.
--              Click any box and type into it. There is no separate editor
--              panel, because a callout is one short line and routing it
--              through a detached text area made the boxes on screen look
--              inert.
--   Pages   -- which enemies appear on which page of the route.
--
-- Adding is a named box at the bottom, plus a button. Enter works, but a button
-- says so; nothing here should depend on guessing that Enter commits.
--------------------------------------------------------------------------------

local ADDON, MM = ...

MM.Edit = {}
local Edit = MM.Edit
local Core, Util = MM.Core, MM.Util

local state = { categoryId = nil, pageId = nil, tab = "enemies" }
local ui = {}

local ROW_H, CARD_GAP, INDENT = 22, 8, 14

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

local function button(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h or 20)
    b:SetText(text)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

local function label(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
    fs:SetText(text or "")
    return fs
end

local function editBox(parent, maxLetters)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetHeight(20)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(maxLetters or 64)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    return eb
end

--- Pools reuse frames, because frames cannot be destroyed. Every field a pooled
--- frame carries must therefore be reset on reuse, not only on creation: the
--- previous build shipped "+ line" buttons reading "+ enemy" precisely because
--- their text was set once, at creation, and inherited by whatever the frame
--- was used for next.
local function acquire(pool, index, make)
    local f = pool[index]
    if not f then
        f = make()
        pool[index] = f
    end
    f:Show()
    return f
end

local function releaseFrom(pool, index)
    for i = index, #pool do pool[i]:Hide() end
end

--------------------------------------------------------------------------------
-- The character counter
--
-- With the boxes edited in place there is no single editor to hang a counter
-- off, so it follows the focus. That is also the only box where the limit can
-- be reached, so it is the only place the warning is useful.
--------------------------------------------------------------------------------

local function updateCounter(eb)
    if not ui.counter then return end

    local text = eb:GetText()
    local channel = Core.Settings().channel or Util.DEFAULT_CHANNEL

    -- The cap applies to the composed macro, not the raw text, so the room a
    -- channel prefix will take is subtracted up front. The typed cap moves with
    -- it, so a line cannot be typed into a length that only fails on write.
    local max = Util.MaxTypedChars(text, channel)
    eb:SetMaxLetters(max)

    local remaining = max - Util.CharLen(text)
    ui.counter:SetText(tostring(remaining))
    if remaining <= 0 then
        ui.counter:SetTextColor(1, 0.3, 0.3)
    elseif remaining <= 30 then
        ui.counter:SetTextColor(1, 0.8, 0.2)
    else
        ui.counter:SetTextColor(0.55, 0.55, 0.6)
    end
    ui.counter:Show()
end

local function attachCounter(eb)
    eb:SetScript("OnEditFocusGained", function(self) updateCounter(self) end)
    eb:SetScript("OnEditFocusLost", function() if ui.counter then ui.counter:Hide() end end)
    eb:SetScript("OnTextChanged", function(self) if self:HasFocus() then updateCounter(self) end end)
end

--------------------------------------------------------------------------------
-- Enemies tab
--------------------------------------------------------------------------------

local namePool, linePool, btnPool = {}, {}, {}

local function refreshSortControls()
    if not ui.sortBtn then return end
    local s = Core.Settings()
    local manual = (s.enemySort or "manual") == "manual"

    ui.sortBtn:SetText(manual and "Order: manual" or "Order: A-Z")
    ui.sortDirBtn:SetText(s.enemySortDesc and "reversed" or "normal")
    -- Only offered when there is something to bake in.
    ui.sortApply:SetShown(not manual or s.enemySortDesc)
end

function Edit.RefreshEnemies()
    refreshSortControls()
    local ni, li, bi = 1, 1, 1
    local cat = state.categoryId and Core.GetCategory(state.categoryId)

    if not cat then
        releaseFrom(namePool, 1); releaseFrom(linePool, 1); releaseFrom(btnPool, 1)
        ui.enemyList:SetHeight(1)
        return
    end

    local width = ui.enemyList:GetWidth() or 460
    local y = -4

    for _, enemy in ipairs(Core.EnemiesInOrder(state.categoryId,
            Core.Settings().enemySort, Core.Settings().enemySortDesc)) do
        -- Name -----------------------------------------------------------------
        local name = acquire(namePool, ni, function()
            local eb = editBox(ui.enemyList, 64)
            -- Children of the box, not of the list: hiding a pooled box then
            -- has to take its buttons with it. Parented to the list, a removed
            -- line left its "-" behind, which is exactly what shipped once.
            eb.up = button(eb, "^", 20, 18)
            eb.up:SetPoint("LEFT", eb, "RIGHT", 6, 0)
            eb.down = button(eb, "v", 20, 18)
            eb.down:SetPoint("LEFT", eb.up, "RIGHT", 2, 0)
            eb.del = button(eb, "x", 20, 18)
            eb.del:SetPoint("LEFT", eb.down, "RIGHT", 2, 0)
            return eb
        end)
        ni = ni + 1

        name:ClearAllPoints()
        name:SetPoint("TOPLEFT", ui.enemyList, "TOPLEFT", 10, y)
        name:SetWidth(width - 140)
        name:SetText(enemy.name)
        name:SetScript("OnEnterPressed", function(self)
            Core.RenameEnemy(state.categoryId, enemy.id, self:GetText())
            self:ClearFocus()
            MM.UI.RefreshSidebar()
        end)
        name:SetScript("OnEditFocusLost", function(self)
            Core.RenameEnemy(state.categoryId, enemy.id, self:GetText())
        end)

        name.del:SetScript("OnClick", function()
            Core.DeleteEnemy(state.categoryId, enemy.id)
            Edit.RefreshEnemies()
        end)

        -- Moving only means something against the stored order. Under an
        -- alphabetical view "up" has no stable meaning, so the arrows go quiet
        -- rather than doing something arbitrary.
        local manual = (Core.Settings().enemySort or "manual") == "manual"
        local step = Core.Settings().enemySortDesc and -1 or 1

        name.up:SetEnabled(manual)
        name.down:SetEnabled(manual)
        name.up:SetScript("OnClick", function()
            Core.MoveEnemy(state.categoryId, enemy.id, -step)
            Edit.RefreshEnemies()
        end)
        name.down:SetScript("OnClick", function()
            Core.MoveEnemy(state.categoryId, enemy.id, step)
            Edit.RefreshEnemies()
        end)

        y = y - ROW_H

        -- Lines ----------------------------------------------------------------
        for _, line in ipairs(enemy.lines) do
            local box = acquire(linePool, li, function()
                local eb = editBox(ui.enemyList, Util.MAX_MACRO_CHARS)
                eb.del = button(eb, "-", 20, 18)
                eb.del:SetPoint("LEFT", eb, "RIGHT", 6, 0)
                attachCounter(eb)
                return eb
            end)
            li = li + 1

            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", ui.enemyList, "TOPLEFT", 10 + INDENT, y)
            box:SetWidth(width - 140 - INDENT)
            box:SetText(line.body or "")

            -- Committed on Enter and on losing focus, so clicking away keeps
            -- what was typed rather than discarding it.
            local function commit(self)
                Core.SetLine(state.categoryId, enemy.id, line.id, nil, self:GetText())
            end
            box:SetScript("OnEnterPressed", function(self) commit(self) self:ClearFocus() end)
            box:SetScript("OnEditFocusLost", function(self)
                commit(self)
                if ui.counter then ui.counter:Hide() end
            end)

            box.del:SetScript("OnClick", function()
                Core.DeleteLine(state.categoryId, enemy.id, line.id)
                Edit.RefreshEnemies()
            end)

            y = y - ROW_H
        end

        -- Per-enemy controls ---------------------------------------------------
        local addLine = acquire(btnPool, bi, function() return button(ui.enemyList, "", 70, 18) end)
        bi = bi + 1
        addLine:SetText("+ line")          -- reset on reuse, never only at creation
        addLine:SetWidth(70)
        addLine:ClearAllPoints()
        addLine:SetPoint("TOPLEFT", ui.enemyList, "TOPLEFT", 10 + INDENT, y)
        addLine:SetScript("OnClick", function()
            Core.AddLine(state.categoryId, enemy.id, "", "")
            Edit.RefreshEnemies()
        end)

        local perRow = acquire(btnPool, bi, function() return button(ui.enemyList, "", 70, 18) end)
        bi = bi + 1
        perRow:SetText(("per row: %d"):format(enemy.perRow or 1))
        perRow:SetWidth(80)
        perRow:ClearAllPoints()
        perRow:SetPoint("LEFT", addLine, "RIGHT", 6, 0)
        perRow:SetScript("OnClick", function()
            -- Above 1, lines fill across instead of stacking. That is the boss
            -- layout, without needing a separate boss type.
            Core.SetEnemyPerRow(state.categoryId, enemy.id, (enemy.perRow or 1) % 4 + 1)
            Edit.RefreshEnemies()
        end)

        y = y - ROW_H - CARD_GAP
    end

    releaseFrom(namePool, ni); releaseFrom(linePool, li); releaseFrom(btnPool, bi)

    ui.enemyEmpty:SetShown(#cat.enemies == 0)
    ui.enemyList:SetHeight(math.max(20, math.abs(y) + 10))
end

--------------------------------------------------------------------------------
-- Pages tab
--------------------------------------------------------------------------------

local pagePool = {}

function Edit.RefreshPages()
    local pi = 1
    local cat = state.categoryId and Core.GetCategory(state.categoryId)

    if not cat then
        releaseFrom(pagePool, 1)
        ui.pageName:SetText("")
        ui.pageList:SetHeight(1)
        return
    end

    if not state.pageId or not Core.GetPage(state.categoryId, state.pageId) then
        state.pageId = cat.pages[1] and cat.pages[1].id or nil
    end

    local page = state.pageId and Core.GetPage(state.categoryId, state.pageId)
    ui.pageName:SetText(page and page.name or "")
    ui.pageIndex:SetText(page
        and ("page %d of %d"):format(Util.IndexById(cat.pages, page.id) or 1, #cat.pages)
        or "no pages yet")

    local width = ui.pageList:GetWidth() or 460
    local y = -4

    local function row(index)
        return acquire(pagePool, index, function()
            local f = CreateFrame("Frame", nil, ui.pageList)
            f:SetHeight(20)
            f.text = label(f, "")
            f.text:SetPoint("LEFT", 4, 0)
            f.a = button(f, "", 24, 18)
            f.b = button(f, "", 24, 18)
            f.c = button(f, "", 44, 18)
            f.c:SetPoint("RIGHT", -2, 0)
            f.b:SetPoint("RIGHT", f.c, "LEFT", -2, 0)
            f.a:SetPoint("RIGHT", f.b, "LEFT", -2, 0)
            return f
        end)
    end

    if page then
        local onPage = Core.PageEnemies(state.categoryId, page.id)
        local isOn = {}

        for _, enemy in ipairs(onPage) do
            isOn[enemy.id] = true
            local f = row(pi); pi = pi + 1
            f:SetWidth(width - 12)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", ui.pageList, "TOPLEFT", 6, y)
            f.text:SetText(("%s  |cffaaaaaa(%d line%s)|r")
                :format(enemy.name, #enemy.lines, #enemy.lines == 1 and "" or "s"))

            f.a:Show(); f.a:SetText("^")
            f.a:SetScript("OnClick", function()
                Core.MoveEnemyOnPage(state.categoryId, page.id, enemy.id, -1)
                Edit.RefreshPages()
            end)
            f.b:Show(); f.b:SetText("v")
            f.b:SetScript("OnClick", function()
                Core.MoveEnemyOnPage(state.categoryId, page.id, enemy.id, 1)
                Edit.RefreshPages()
            end)
            -- Off this page only. Deleting the enemy itself is on the Enemies
            -- tab, so tidying a page can never destroy the text.
            f.c:Show(); f.c:SetText("remove")
            f.c:SetScript("OnClick", function()
                Core.RemoveEnemyFromPage(state.categoryId, page.id, enemy.id)
                Edit.RefreshPages()
            end)

            y = y - 22
        end

        local header = false
        for _, enemy in ipairs(cat.enemies) do
            if not isOn[enemy.id] then
                if not header then
                    header = true
                    local h = row(pi); pi = pi + 1
                    h:SetWidth(width - 12)
                    h:ClearAllPoints()
                    h:SetPoint("TOPLEFT", ui.pageList, "TOPLEFT", 6, y - 6)
                    h.text:SetText("|cffaaaaaaNot on this page|r")
                    h.a:Hide(); h.b:Hide(); h.c:Hide()
                    y = y - 28
                end

                local f = row(pi); pi = pi + 1
                f:SetWidth(width - 12)
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", ui.pageList, "TOPLEFT", 6, y)
                f.text:SetText("|cff888888" .. enemy.name .. "|r")
                f.a:Hide(); f.b:Hide()
                f.c:Show(); f.c:SetText("add")
                f.c:SetScript("OnClick", function()
                    Core.AddEnemyToPage(state.categoryId, page.id, enemy.id)
                    Edit.RefreshPages()
                end)
                y = y - 22
            end
        end
    end

    releaseFrom(pagePool, pi)
    ui.pageList:SetHeight(math.max(20, math.abs(y) + 10))
end

--------------------------------------------------------------------------------
-- Tabs and scope
--------------------------------------------------------------------------------

local function showTab(name)
    state.tab = name
    ui.enemiesPanel:SetShown(name == "enemies")
    ui.pagesPanel:SetShown(name == "pages")
    ui.tabEnemies:SetEnabled(name ~= "enemies")
    ui.tabPages:SetEnabled(name ~= "pages")

    if name == "enemies" then Edit.RefreshEnemies() else Edit.RefreshPages() end
end

function Edit.ShowTab(name) showTab(name) end

--- Called by the sidebar. Both tabs act on one dungeon, and say which, rather
--- than showing an empty panel that looks broken.
function Edit.SetCategory(catId)
    state.categoryId = catId
    state.pageId = nil

    local cat = catId and Core.GetCategory(catId)
    ui.title:SetText(cat and cat.name or "")
    ui.prompt:SetShown(cat == nil)
    ui.enemiesPanel:SetShown(cat ~= nil and state.tab == "enemies")
    ui.pagesPanel:SetShown(cat ~= nil and state.tab == "pages")
    ui.tabEnemies:SetShown(cat ~= nil)
    ui.tabPages:SetShown(cat ~= nil)

    if cat then showTab(state.tab) end
    Edit.RefreshSendHint()
    Edit.RefreshStaleMarker()
end

function Edit.Category() return state.categoryId end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function Edit.Build(parent)
    ui.title = label(parent, "", "GameFontNormalLarge")
    ui.title:SetPoint("TOP", 0, -6)

    ui.prompt = label(parent, "Pick a dungeon on the left, or make one with New dungeon.")
    ui.prompt:SetPoint("TOPLEFT", 12, -34)

    ui.tabEnemies = button(parent, "Enemies", 70, 20, function() showTab("enemies") end)
    ui.tabEnemies:SetPoint("TOPLEFT", 8, -28)
    ui.tabPages = button(parent, "Pages", 62, 20, function() showTab("pages") end)
    ui.tabPages:SetPoint("LEFT", ui.tabEnemies, "RIGHT", 4, 0)

    ui.counter = label(parent, "")
    ui.counter:SetPoint("TOPRIGHT", -10, -32)
    ui.counter:Hide()

    ui.stale = label(parent, "")
    ui.stale:SetPoint("TOPRIGHT", ui.counter, "TOPLEFT", -12, 0)

    -- Enemies ------------------------------------------------------------------
    ui.enemiesPanel = CreateFrame("Frame", nil, parent)
    ui.enemiesPanel:SetPoint("TOPLEFT", 6, -52)
    ui.enemiesPanel:SetPoint("BOTTOMRIGHT", -6, 58)

    ui.sendHint = label(ui.enemiesPanel, "")
    ui.sendHint:SetPoint("TOPLEFT", 10, -4)

    -- Sorting is a view, not a rewrite. Changing how the list is displayed
    -- should never quietly discard an arrangement someone built by hand, so
    -- baking it in is a separate, deliberate button.
    ui.sortBtn = button(ui.enemiesPanel, "", 110, 18, function()
        local s = Core.Settings()
        s.enemySort = (s.enemySort == "name") and "manual" or "name"
        Edit.RefreshEnemies()
    end)
    ui.sortBtn:SetPoint("TOPLEFT", 10, -20)

    ui.sortDirBtn = button(ui.enemiesPanel, "", 90, 18, function()
        local s = Core.Settings()
        s.enemySortDesc = not s.enemySortDesc
        Edit.RefreshEnemies()
    end)
    ui.sortDirBtn:SetPoint("LEFT", ui.sortBtn, "RIGHT", 4, 0)

    ui.sortApply = button(ui.enemiesPanel, "Keep this order", 110, 18, function()
        local s = Core.Settings()
        Core.SortEnemies(state.categoryId, s.enemySort, s.enemySortDesc)
        s.enemySort, s.enemySortDesc = "manual", false
        Edit.RefreshEnemies()
        Util.Print("order saved. The arrows work again.")
    end)
    ui.sortApply:SetPoint("LEFT", ui.sortDirBtn, "RIGHT", 4, 0)

    ui.enemyEmpty = label(ui.enemiesPanel,
        "|cffaaaaaaNo enemies yet. Name one below, or target a mob and use Add target.|r")
    ui.enemyEmpty:SetPoint("TOPLEFT", 10, -42)

    local enemyScroll = CreateFrame("ScrollFrame", nil, ui.enemiesPanel, "UIPanelScrollFrameTemplate")
    enemyScroll:SetPoint("TOPLEFT", 0, -40)
    enemyScroll:SetPoint("BOTTOMRIGHT", -24, 0)
    ui.enemyList = CreateFrame("Frame", nil, enemyScroll)
    ui.enemyList:SetSize(470, 40)
    enemyScroll:SetScrollChild(ui.enemyList)

    -- Pages --------------------------------------------------------------------
    ui.pagesPanel = CreateFrame("Frame", nil, parent)
    ui.pagesPanel:SetPoint("TOPLEFT", 6, -52)
    ui.pagesPanel:SetPoint("BOTTOMRIGHT", -6, 58)
    ui.pagesPanel:Hide()

    local pagePrev = button(ui.pagesPanel, "<", 22, 20, function()
        local cat = Core.GetCategory(state.categoryId)
        if not cat or #cat.pages == 0 then return end
        local i = (Util.IndexById(cat.pages, state.pageId) or 1) - 1
        if i < 1 then i = #cat.pages end
        state.pageId = cat.pages[i].id
        Edit.RefreshPages()
    end)
    pagePrev:SetPoint("TOPLEFT", 4, -2)

    ui.pageName = editBox(ui.pagesPanel, 40)
    ui.pageName:SetPoint("LEFT", pagePrev, "RIGHT", 8, 0)
    ui.pageName:SetWidth(180)
    ui.pageName:SetScript("OnEnterPressed", function(self)
        if state.pageId then Core.RenamePage(state.categoryId, state.pageId, self:GetText()) end
        self:ClearFocus()
        Edit.RefreshPages()
    end)

    local pageNext = button(ui.pagesPanel, ">", 22, 20, function()
        local cat = Core.GetCategory(state.categoryId)
        if not cat or #cat.pages == 0 then return end
        local i = (Util.IndexById(cat.pages, state.pageId) or 1) + 1
        if i > #cat.pages then i = 1 end
        state.pageId = cat.pages[i].id
        Edit.RefreshPages()
    end)
    pageNext:SetPoint("LEFT", ui.pageName, "RIGHT", 6, 0)

    ui.pageIndex = label(ui.pagesPanel, "")
    ui.pageIndex:SetPoint("LEFT", pageNext, "RIGHT", 10, 0)

    local delPage = button(ui.pagesPanel, "Delete page", 86, 20, function()
        if not state.pageId then return end
        Core.DeletePage(state.categoryId, state.pageId)
        state.pageId = nil
        Edit.RefreshPages()
    end)
    delPage:SetPoint("TOPRIGHT", -4, -2)

    local pagesScroll = CreateFrame("ScrollFrame", nil, ui.pagesPanel, "UIPanelScrollFrameTemplate")
    pagesScroll:SetPoint("TOPLEFT", 0, -28)
    pagesScroll:SetPoint("BOTTOMRIGHT", -24, 0)
    ui.pageList = CreateFrame("Frame", nil, pagesScroll)
    ui.pageList:SetSize(470, 40)
    pagesScroll:SetScrollChild(ui.pageList)

    -- The add bar, shared by both tabs -----------------------------------------
    ui.addLabel = label(parent, "")
    ui.addLabel:SetPoint("BOTTOMLEFT", 10, 38)

    ui.addBox = editBox(parent, 64)
    ui.addBox:SetPoint("BOTTOMLEFT", 14, 12)
    ui.addBox:SetPoint("BOTTOMRIGHT", -230, 12)

    local function commitAdd()
        local text = ui.addBox:GetText()
        if not text or not text:match("%S") then return end
        if not state.categoryId then
            Util.Print("|cffff4444pick a dungeon on the left first.|r")
            return
        end

        if state.tab == "enemies" then
            local enemy = Core.AddEnemy(state.categoryId, text)
            Core.AddLine(state.categoryId, enemy.id, "", "")
            Edit.RefreshEnemies()
        else
            local page = Core.AddPage(state.categoryId, text)
            state.pageId = page.id
            Edit.RefreshPages()
        end

        ui.addBox:SetText("")
        ui.addBox:ClearFocus()
        Edit.RefreshStaleMarker()
    end

    ui.addBox:SetScript("OnEnterPressed", commitAdd)

    -- Enter works, but a visible button is what tells you so.
    ui.addBtn = button(parent, "Add", 50, 20, commitAdd)
    ui.addBtn:SetPoint("BOTTOMLEFT", ui.addBox, "BOTTOMRIGHT", 6, 0)

    ui.addTarget = button(parent, "Add target", 78, 20, function()
        local name, why = MM.Capture.AddTarget("target")
        if name then
            Util.Print(("added |cffffff00%s|r to %s."):format(name, why))
            Edit.RefreshEnemies()
        else
            Util.Print("|cffff4444" .. (why or "could not add") .. "|r")
        end
    end)
    ui.addTarget:SetPoint("LEFT", ui.addBtn, "RIGHT", 4, 0)

    local exportBtn = button(parent, "Export", 54, 20, function()
        if not state.categoryId then
            Util.Print("|cffff4444pick a dungeon first.|r") return
        end
        local str, err = MM.Export.EncodeCategory(state.categoryId)
        if not str then Util.Print("|cffff4444" .. (err or "failed") .. "|r") return end
        Core.MarkExported()
        Edit.RefreshStaleMarker()
        MM.UI.ShowExport(("Export: %s"):format(Core.GetCategory(state.categoryId).name), str)
    end)
    exportBtn:SetPoint("LEFT", ui.addTarget, "RIGHT", 4, 0)

    local importBtn = button(parent, "Import", 54, 20, function()
        MM.UI.ShowImport("Import", function(text)
            local what, err = MM.Export.Import(text)
            if what then
                MM.UI.RefreshCategories()
                Edit.RefreshEnemies()
            end
            return what, err
        end)
    end)
    importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 4, 0)

    Edit.RefreshSendHint()
    Edit.SetCategory(nil)
end

--- Only appears once enough has changed to be worth losing. SavedVariables is
--- not written until logout or a reload, and a crash takes everything since.
--- Says where plain text goes, and that a slash command overrides it. Typing an
--- instruction with no command was the failure that made a button look right
--- and fire nothing, so the rule is stated where the typing happens.
function Edit.RefreshSendHint()
    if not ui.sendHint then return end
    local channel = Core.Settings().channel or Util.DEFAULT_CHANNEL
    ui.sendHint:SetText((
        "|cffaaaaaaPlain text is sent to |r|cffffff00%s|r|cffaaaaaa. " ..
        "Start a line with /cast, /i or any command to run it as written.|r")
        :format(channel))
end

function Edit.RefreshStaleMarker()
    if not ui.stale then return end
    local n = Core.EditsSinceExport()
    ui.stale:SetText(n >= 20 and ("|cffd9a441%d edits unbacked|r"):format(n) or "")

    if ui.addLabel then
        ui.addLabel:SetText(state.tab == "enemies"
            and "Name an enemy and press Enter, or use Add"
            or  "Name a page and press Enter, or use Add")
    end
end

function Edit.Refresh()
    Edit.SetCategory(state.categoryId)
end

function Edit.RefreshDungeons()
    MM.UI.RefreshSidebar()
end
