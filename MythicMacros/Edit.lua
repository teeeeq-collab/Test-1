--------------------------------------------------------------------------------
-- Edit: writing the callouts, and composing the pages.
--
-- Two sub-views under one category selector:
--
--   Enemies -- a text area over every enemy in the category. Click a line, it
--              loads above; edit and save. This is the macro window's shape,
--              which is already familiar and handles long bodies properly.
--   Pages   -- add enemies to a page as cards, reorder them, remove them.
--
-- Everything here is out-of-combat work by nature, which is convenient, since
-- writing button attributes is blocked in combat anyway.
--------------------------------------------------------------------------------

local ADDON, MM = ...

MM.Edit = {}
local Edit = MM.Edit
local Core, Util = MM.Core, MM.Util
-- MM.UI is resolved at call time: Edit and UI reference each other, and
-- capturing either at file scope would make the load order load-bearing.

local state = {
    categoryId = nil,
    enemyId    = nil,
    lineId     = nil,
    pageId     = nil,
    tab        = "enemies",
}

local ui = {}

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

local function editBox(parent, w, h, maxLetters)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(w, h or 20)
    eb:SetAutoFocus(false)
    if maxLetters then eb:SetMaxLetters(maxLetters) end
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    return eb
end

--- Frees a pooled list of frames without destroying them: frames cannot be
--- destroyed, so every rebuild reuses what it has and hides the rest.
local function releaseAll(pool)
    for _, frame in ipairs(pool) do frame:Hide() end
end

--------------------------------------------------------------------------------
-- The line editor
--------------------------------------------------------------------------------

local function currentLine()
    if not (state.categoryId and state.enemyId and state.lineId) then return nil end
    return Core.GetLine(state.categoryId, state.enemyId, state.lineId)
end

local function updateCounter()
    local remaining = Util.MAX_MACRO_CHARS - Util.CharLen(ui.body:GetText())
    ui.counter:SetText(("%d"):format(remaining))

    -- The cap is enforced by SetMaxLetters; this only says how close you are.
    if remaining <= 0 then
        ui.counter:SetTextColor(1, 0.3, 0.3)
    elseif remaining <= 30 then
        ui.counter:SetTextColor(1, 0.8, 0.2)
    else
        ui.counter:SetTextColor(0.6, 0.6, 0.65)
    end
end

local function loadLine(enemyId, lineId)
    state.enemyId, state.lineId = enemyId, lineId
    local line = currentLine()

    if not line then
        ui.caption:SetText("")
        ui.body:SetText("")
        ui.editingWho:SetText("|cffaaaaaaSelect a line below to edit it.|r")
    else
        local enemy = Core.GetEnemy(state.categoryId, enemyId)
        ui.caption:SetText(line.caption or "")
        ui.body:SetText(line.body or "")
        ui.editingWho:SetText(("Editing |cffffff00%s|r"):format(enemy and enemy.name or "?"))
    end

    updateCounter()
    Edit.RefreshEnemies()
end

local function saveLine()
    local line = currentLine()
    if not line then return end
    Core.SetLine(state.categoryId, state.enemyId, state.lineId,
        ui.caption:GetText(), ui.body:GetText())
    Edit.RefreshEnemies()
    Util.Print("saved. |cffaaaaaa/reload writes it to disk.|r")
end

--------------------------------------------------------------------------------
-- Enemies sub-view
--------------------------------------------------------------------------------

local enemyPool, linePool, miscPool = {}, {}, {}

function Edit.RefreshEnemies()
    releaseAll(enemyPool); releaseAll(linePool); releaseAll(miscPool)
    local ei, li, mi = 0, 0, 0

    local function nextFrom(pool, index, make)
        index = index + 1
        local f = pool[index]
        if not f then f = make(); pool[index] = f end
        f:Show()
        return f, index
    end

    local cat = state.categoryId and Core.GetCategory(state.categoryId)
    if not cat then
        ui.enemyList:SetHeight(1)
        return
    end

    local x, y = 6, -6
    local CARD_W = 168

    for _, enemy in ipairs(cat.enemies) do
        local card
        card, ei = nextFrom(enemyPool, ei, function()
            local f = CreateFrame("Frame", nil, ui.enemyList)
            f:SetSize(CARD_W, 40)
            f.name = editBox(f, CARD_W - 44, 20, 64)
            f.name:SetPoint("TOPLEFT", 4, 0)
            f.del = button(f, "x", 18, 18)
            f.del:SetPoint("TOPRIGHT", -2, -1)
            f.perRow = button(f, "1", 18, 18)
            f.perRow:SetPoint("RIGHT", f.del, "LEFT", -2, 0)
            return f
        end)

        card:SetPoint("TOPLEFT", ui.enemyList, "TOPLEFT", x, y)
        card.name:SetText(enemy.name)
        card.name:SetScript("OnEnterPressed", function(self)
            Core.RenameEnemy(state.categoryId, enemy.id, self:GetText())
            self:ClearFocus()
            Edit.RefreshEnemies()
        end)

        card.perRow:SetText(tostring(enemy.perRow or 1))
        card.perRow:SetScript("OnClick", function()
            -- Cycles 1..4. Above 1 the lines fill across instead of stacking,
            -- which is the boss layout without needing a boss type.
            local next = (enemy.perRow or 1) % 4 + 1
            Core.SetEnemyPerRow(state.categoryId, enemy.id, next)
            Edit.RefreshEnemies()
        end)

        card.del:SetScript("OnClick", function()
            Core.DeleteEnemy(state.categoryId, enemy.id)
            if state.enemyId == enemy.id then loadLine(nil, nil) end
            Edit.RefreshEnemies()
        end)

        local ly = -22
        for _, line in ipairs(enemy.lines) do
            local row
            row, li = nextFrom(linePool, li, function()
                local b = CreateFrame("Button", nil, ui.enemyList, "UIPanelButtonTemplate")
                b:SetSize(CARD_W - 26, 18)
                b.remove = button(b:GetParent(), "-", 18, 18)
                return b
            end)

            row:SetPoint("TOPLEFT", card, "TOPLEFT", 4, ly)
            row:SetText(Util.ButtonLabel(line))
            row:SetScript("OnClick", function() loadLine(enemy.id, line.id) end)

            -- Selection is shown by the editor heading, but a highlight here is
            -- what makes "currently editing" obvious at a glance.
            if state.lineId == line.id then
                row:LockHighlight()
            else
                row:UnlockHighlight()
            end

            row.remove:Show()
            row.remove:SetPoint("LEFT", row, "RIGHT", 2, 0)
            row.remove:SetScript("OnClick", function()
                Core.DeleteLine(state.categoryId, enemy.id, line.id)
                if state.lineId == line.id then loadLine(nil, nil) end
                Edit.RefreshEnemies()
            end)

            ly = ly - 20
        end

        local addLine
        addLine, mi = nextFrom(miscPool, mi, function()
            return button(ui.enemyList, "+ line", CARD_W - 8, 18)
        end)
        addLine:SetPoint("TOPLEFT", card, "TOPLEFT", 4, ly)
        addLine:SetScript("OnClick", function()
            local line = Core.AddLine(state.categoryId, enemy.id, "", "")
            loadLine(enemy.id, line.id)
        end)

        local cardH = 22 + (#enemy.lines * 20) + 22
        x = x + CARD_W + 10
        if x + CARD_W > ui.enemyList:GetWidth() then
            x = 6
            y = y - cardH - 10
        end
    end

    local addEnemy
    addEnemy, mi = nextFrom(miscPool, mi, function()
        return button(ui.enemyList, "+ enemy", 100, 22)
    end)
    addEnemy:SetPoint("TOPLEFT", ui.enemyList, "TOPLEFT", x, y)
    addEnemy:SetScript("OnClick", function()
        local enemy = Core.AddEnemy(state.categoryId, "New enemy")
        Edit.RefreshEnemies()
    end)

    ui.enemyList:SetHeight(math.max(60, math.abs(y) + 90))
end

--------------------------------------------------------------------------------
-- Pages sub-view
--------------------------------------------------------------------------------

local pagePool = {}

function Edit.RefreshPages()
    releaseAll(pagePool)
    local pi = 0

    local cat = state.categoryId and Core.GetCategory(state.categoryId)
    if not cat then
        ui.pageName:SetText("")
        return
    end

    if not state.pageId and cat.pages[1] then state.pageId = cat.pages[1].id end
    local page = state.pageId and Core.GetPage(state.categoryId, state.pageId)
    ui.pageName:SetText(page and page.name or "")

    local y = -6
    if page then
        for _, enemy in ipairs(Core.PageEnemies(state.categoryId, page.id)) do
            pi = pi + 1
            local row = pagePool[pi]
            if not row then
                row = CreateFrame("Frame", nil, ui.pageList)
                row:SetSize(300, 20)
                row.name = label(row, "")
                row.name:SetPoint("LEFT", 4, 0)
                row.up = button(row, "^", 20, 18)
                row.up:SetPoint("RIGHT", -46, 0)
                row.down = button(row, "v", 20, 18)
                row.down:SetPoint("RIGHT", -24, 0)
                row.remove = button(row, "x", 20, 18)
                row.remove:SetPoint("RIGHT", -2, 0)
                pagePool[pi] = row
            end

            row:Show()
            row:SetPoint("TOPLEFT", ui.pageList, "TOPLEFT", 4, y)
            row.name:SetText(("%s  |cffaaaaaa(%d line%s)|r")
                :format(enemy.name, #enemy.lines, #enemy.lines == 1 and "" or "s"))

            row.up:SetScript("OnClick", function()
                Core.MoveEnemyOnPage(state.categoryId, page.id, enemy.id, -1)
                Edit.RefreshPages()
            end)
            row.down:SetScript("OnClick", function()
                Core.MoveEnemyOnPage(state.categoryId, page.id, enemy.id, 1)
                Edit.RefreshPages()
            end)
            -- Removes from this page only. Deleting the definition lives on the
            -- Enemies tab, so a page tidy-up cannot destroy the text.
            row.remove:SetScript("OnClick", function()
                Core.RemoveEnemyFromPage(state.categoryId, page.id, enemy.id)
                Edit.RefreshPages()
            end)

            y = y - 22
        end

        for _, enemy in ipairs(cat.enemies) do
            local onPage = false
            for _, e in ipairs(Core.PageEnemies(state.categoryId, page.id)) do
                if e.id == enemy.id then onPage = true break end
            end

            if not onPage then
                pi = pi + 1
                local row = pagePool[pi]
                if not row then
                    row = CreateFrame("Frame", nil, ui.pageList)
                    row:SetSize(300, 20)
                    row.name = label(row, "")
                    row.name:SetPoint("LEFT", 4, 0)
                    row.add = button(row, "add", 44, 18)
                    row.add:SetPoint("RIGHT", -2, 0)
                    row.up = row.add        -- unused slots, kept for pool shape
                    row.down = row.add
                    row.remove = row.add
                    pagePool[pi] = row
                end

                row:Show()
                row:SetPoint("TOPLEFT", ui.pageList, "TOPLEFT", 4, y)
                row.name:SetText("|cff777777" .. enemy.name .. "|r")
                row.add:Show()
                row.add:SetScript("OnClick", function()
                    Core.AddEnemyToPage(state.categoryId, page.id, enemy.id)
                    Edit.RefreshPages()
                end)
                y = y - 22
            end
        end
    end

    ui.pageList:SetHeight(math.max(40, math.abs(y) + 10))
end

--------------------------------------------------------------------------------
-- Dungeons sub-view
--
-- One level above the enemies, because creating a dungeon and writing callouts
-- inside one are different jobs and mixing them buried the former in a corner
-- of the latter.
--
-- The selected dungeon's enemies are listed indented beneath it, so what is
-- inside a dungeon is visible without switching tabs to find out. Clicking one
-- jumps straight to editing it.
--------------------------------------------------------------------------------

local dungeonPool = {}
local forwardSelect   -- selectCategory is defined below; the rows need it now

function Edit.RefreshDungeons()
    releaseAll(dungeonPool)
    local di = 0

    local function row(height)
        di = di + 1
        local f = dungeonPool[di]
        if not f then
            f = CreateFrame("Frame", nil, ui.dungeonList)
            f.name   = editBox(f, 220, 20, 64)
            f.name:SetPoint("LEFT", 4, 0)
            f.open   = button(f, "Enemies", 66, 18)
            f.open:SetPoint("LEFT", f.name, "RIGHT", 6, 0)
            f.pages  = button(f, "Pages", 54, 18)
            f.pages:SetPoint("LEFT", f.open, "RIGHT", 3, 0)
            f.up     = button(f, "^", 20, 18)
            f.up:SetPoint("LEFT", f.pages, "RIGHT", 8, 0)
            f.down   = button(f, "v", 20, 18)
            f.down:SetPoint("LEFT", f.up, "RIGHT", 2, 0)
            f.del    = button(f, "x", 20, 18)
            f.del:SetPoint("LEFT", f.down, "RIGHT", 2, 0)
            f.enemy  = button(f, "", 240, 16)      -- reused as an enemy line
            f.enemy:SetPoint("LEFT", 24, 0)
            dungeonPool[di] = f
        end
        f:SetSize(500, height or 22)
        f:Show()
        return f
    end

    local function asDungeon(f)
        f.name:Show(); f.open:Show(); f.pages:Show()
        f.up:Show(); f.down:Show(); f.del:Show()
        f.enemy:Hide()
    end

    local function asEnemy(f)
        f.name:Hide(); f.open:Hide(); f.pages:Hide()
        f.up:Hide(); f.down:Hide(); f.del:Hide()
        f.enemy:Show()
    end

    local y = -4
    for _, cat in ipairs(Core.Categories()) do
        local f = row(22)
        asDungeon(f)
        f:SetPoint("TOPLEFT", ui.dungeonList, "TOPLEFT", 4, y)

        f.name:SetText(cat.name)
        f.name:SetScript("OnEnterPressed", function(self)
            Core.RenameCategory(cat.id, self:GetText())
            self:ClearFocus()
            Edit.RefreshDungeons()
            MM.UI.RefreshCategories()
        end)

        f.open:SetScript("OnClick", function()
            forwardSelect(cat.id)
            showTab("enemies")
        end)
        f.pages:SetScript("OnClick", function()
            forwardSelect(cat.id)
            showTab("pages")
        end)
        f.up:SetScript("OnClick", function()
            Core.MoveCategory(cat.id, -1); Edit.RefreshDungeons(); MM.UI.RefreshCategories()
        end)
        f.down:SetScript("OnClick", function()
            Core.MoveCategory(cat.id, 1); Edit.RefreshDungeons(); MM.UI.RefreshCategories()
        end)
        f.del:SetScript("OnClick", function()
            Core.DeleteCategory(cat.id)
            if state.categoryId == cat.id then forwardSelect(nil) end
            Edit.RefreshDungeons(); MM.UI.RefreshCategories()
        end)

        y = y - 24

        -- The selected dungeon opens to show what is inside it.
        if cat.id == state.categoryId then
            if #cat.enemies == 0 then
                local e = row(16)
                asEnemy(e)
                e:SetPoint("TOPLEFT", ui.dungeonList, "TOPLEFT", 4, y)
                e.enemy:SetText("|cff777777no enemies yet - use Enemies, or the Add target keybind|r")
                e.enemy:SetScript("OnClick", function() showTab("enemies") end)
                y = y - 18
            else
                for _, enemy in ipairs(cat.enemies) do
                    local e = row(16)
                    asEnemy(e)
                    e:SetPoint("TOPLEFT", ui.dungeonList, "TOPLEFT", 4, y)
                    e.enemy:SetText(("%s  |cffaaaaaa(%d)|r"):format(enemy.name, #enemy.lines))
                    e.enemy:SetScript("OnClick", function()
                        forwardSelect(cat.id)
                        showTab("enemies")
                        if enemy.lines[1] then loadLine(enemy.id, enemy.lines[1].id) end
                    end)
                    y = y - 18
                end
            end
            y = y - 6
        end
    end

    if #Core.Categories() == 0 then
        ui.dungeonEmpty:Show()
    else
        ui.dungeonEmpty:Hide()
    end

    ui.dungeonList:SetHeight(math.max(40, math.abs(y) + 10))
end

--------------------------------------------------------------------------------
-- Category selection and tabs
--------------------------------------------------------------------------------

--- Enemies and Pages both act on one dungeon. Rather than silently showing an
--- empty panel, they say which dungeon they are working on, or that none is
--- chosen and where to choose one.
local function scopeText()
    local cat = state.categoryId and Core.GetCategory(state.categoryId)
    if cat then
        return ("Dungeon: |cffffff00%s|r"):format(cat.name)
    end
    return "|cffd9a441No dungeon selected - pick one on the Dungeons tab.|r"
end

--- The scope labels are the only place the current dungeon is named now that
--- dungeon management has its own tab.
local function refreshCategoryLabel()
    local text = scopeText()
    if ui.scope1 then ui.scope1:SetText(text) end
    if ui.scope2 then ui.scope2:SetText(text) end
end

local function selectCategory(id)
    state.categoryId = id
    MM.Capture.SetCategory(id)   -- the keybind adds to whatever Edit is showing
    state.enemyId, state.lineId, state.pageId = nil, nil, nil
    refreshCategoryLabel()
    loadLine(nil, nil)
    Edit.RefreshEnemies()
    Edit.RefreshPages()
    MM.UI.RefreshCategories()
end

forwardSelect = function(id) selectCategory(id) end

local function showTab(name)
    state.tab = name
    ui.dungeonsPanel:SetShown(name == "dungeons")
    ui.enemiesPanel:SetShown(name == "enemies")
    ui.pagesPanel:SetShown(name == "pages")

    if name == "dungeons" then
        Edit.RefreshDungeons()
    elseif name == "enemies" then
        Edit.RefreshEnemies()
    else
        Edit.RefreshPages()
    end
end

function Edit.ShowTab(name) showTab(name) end


--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function Edit.Build(parent)
    -- Tabs --------------------------------------------------------------------
    local tabDungeons = button(parent, "Dungeons", 76, 20, function() showTab("dungeons") end)
    tabDungeons:SetPoint("TOPLEFT", 8, -8)
    local tabEnemies = button(parent, "Enemies", 70, 20, function() showTab("enemies") end)
    tabEnemies:SetPoint("LEFT", tabDungeons, "RIGHT", 4, 0)
    local tabPages = button(parent, "Pages", 62, 20, function() showTab("pages") end)
    tabPages:SetPoint("LEFT", tabEnemies, "RIGHT", 4, 0)

    local addTarget = button(parent, "Add target", 84, 20, function()
        local name, why = MM.Capture.AddTarget("target")
        if name then
            Util.Print(("added |cffffff00%s|r to %s."):format(name, why))
            Edit.RefreshEnemies()
            Edit.RefreshDungeons()
        else
            Util.Print("|cffff4444" .. (why or "could not add") .. "|r")
        end
    end)
    addTarget:SetPoint("LEFT", tabPages, "RIGHT", 16, 0)

    local exportCat = button(parent, "Export", 58, 20, function()
        if not state.categoryId then
            Util.Print("|cffff4444pick a dungeon first.|r") return
        end
        local str, err = MM.Export.EncodeCategory(state.categoryId)
        if not str then
            Util.Print("|cffff4444" .. (err or "could not export") .. "|r") return
        end
        local cat = Core.GetCategory(state.categoryId)
        Core.MarkExported()
        Edit.RefreshStaleMarker()
        MM.UI.ShowExport(("Export: %s"):format(cat.name), str)
    end)
    exportCat:SetPoint("LEFT", addTarget, "RIGHT", 10, 0)

    local exportAll = button(parent, "Backup all", 78, 20, function()
        local str, err = MM.Export.EncodeProfile()
        if not str then
            Util.Print("|cffff4444" .. (err or "could not export") .. "|r") return
        end
        Core.MarkExported()
        Edit.RefreshStaleMarker()
        MM.UI.ShowExport("Backup of every dungeon", str)
    end)
    exportAll:SetPoint("LEFT", exportCat, "RIGHT", 3, 0)

    local importBtn = button(parent, "Import", 58, 20, function()
        MM.UI.ShowImport("Import", function(text)
            local what, err = MM.Export.Import(text)
            if what then
                Edit.Refresh()
                MM.UI.RefreshCategories()
            end
            return what, err
        end)
    end)
    importBtn:SetPoint("LEFT", exportAll, "RIGHT", 3, 0)

    ui.stale = label(parent, "")
    ui.stale:SetPoint("TOPLEFT", tabDungeons, "BOTTOMLEFT", 2, -4)

    -- Dungeons panel ----------------------------------------------------------
    ui.dungeonsPanel = CreateFrame("Frame", nil, parent)
    ui.dungeonsPanel:SetPoint("TOPLEFT", tabDungeons, "BOTTOMLEFT", 0, -20)
    ui.dungeonsPanel:SetPoint("BOTTOMRIGHT", -8, 8)

    local newDungeon = button(ui.dungeonsPanel, "+ New dungeon", 110, 22, function()
        local cat = Core.AddCategory("New dungeon")
        selectCategory(cat.id)
        Edit.RefreshDungeons()
        MM.UI.RefreshCategories()
    end)
    newDungeon:SetPoint("TOPLEFT", 0, 0)

    local seasonBtn = button(ui.dungeonsPanel, "Add this season's dungeons", 180, 22, function()
        local made, skipped = MM.Starter.Create()
        Edit.RefreshDungeons()
        MM.UI.RefreshCategories()
        Util.Print(("created %d, skipped %d already there."):format(#made, #skipped))
    end)
    seasonBtn:SetPoint("LEFT", newDungeon, "RIGHT", 6, 0)

    ui.dungeonEmpty = label(ui.dungeonsPanel,
        "|cffaaaaaaNo dungeons yet. Create one, or add the season's list.|r")
    ui.dungeonEmpty:SetPoint("TOPLEFT", 2, -30)

    local dungeonScroll = CreateFrame("ScrollFrame", nil, ui.dungeonsPanel,
        "UIPanelScrollFrameTemplate")
    dungeonScroll:SetPoint("TOPLEFT", 0, -30)
    dungeonScroll:SetPoint("BOTTOMRIGHT", -24, 0)
    ui.dungeonList = CreateFrame("Frame", nil, dungeonScroll)
    ui.dungeonList:SetSize(520, 100)
    dungeonScroll:SetScrollChild(ui.dungeonList)

    -- Enemies panel -----------------------------------------------------------
    ui.enemiesPanel = CreateFrame("Frame", nil, parent)
    ui.enemiesPanel:SetPoint("TOPLEFT", tabDungeons, "BOTTOMLEFT", 0, -20)
    ui.enemiesPanel:SetPoint("BOTTOMRIGHT", -8, 8)

    ui.scope1 = label(ui.enemiesPanel, "")
    ui.scope1:SetPoint("TOPLEFT", 0, 0)

    ui.editingWho = label(ui.enemiesPanel, "|cffaaaaaaSelect a line below to edit it.|r")
    ui.editingWho:SetPoint("TOPLEFT", 0, -16)

    local capLabel = label(ui.enemiesPanel, "Caption")
    capLabel:SetPoint("TOPLEFT", 0, -34)
    ui.caption = editBox(ui.enemiesPanel, 120, 20, 24)
    ui.caption:SetPoint("LEFT", capLabel, "RIGHT", 8, 0)

    ui.counter = label(ui.enemiesPanel, "255")
    ui.counter:SetPoint("TOPRIGHT", 0, -36)

    local bodyBox = CreateFrame("ScrollFrame", nil, ui.enemiesPanel,
        "UIPanelScrollFrameTemplate")
    bodyBox:SetPoint("TOPLEFT", 0, -60)
    bodyBox:SetPoint("TOPRIGHT", -24, -60)
    bodyBox:SetHeight(56)

    -- SetMaxLetters counts characters, and the macro cap is in characters, so
    -- this alone enforces the limit. Core trims again on write as a backstop
    -- for anything that arrives without passing through here.
    ui.body = CreateFrame("EditBox", nil, bodyBox)
    ui.body:SetMultiLine(true)
    ui.body:SetMaxLetters(Util.MAX_MACRO_CHARS)
    ui.body:SetAutoFocus(false)
    ui.body:SetFontObject(ChatFontNormal)
    ui.body:SetWidth(420)
    ui.body:SetScript("OnTextChanged", updateCounter)
    ui.body:SetScript("OnEscapePressed", ui.body.ClearFocus)
    bodyBox:SetScrollChild(ui.body)

    local save = button(ui.enemiesPanel, "Save", 60, 20, saveLine)
    save:SetPoint("TOPLEFT", 0, -120)
    local revert = button(ui.enemiesPanel, "Revert", 60, 20, function()
        loadLine(state.enemyId, state.lineId)
    end)
    revert:SetPoint("LEFT", save, "RIGHT", 4, 0)

    local listScroll = CreateFrame("ScrollFrame", nil, ui.enemiesPanel,
        "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 0, -146)
    listScroll:SetPoint("BOTTOMRIGHT", -24, 0)
    ui.enemyList = CreateFrame("Frame", nil, listScroll)
    ui.enemyList:SetSize(560, 100)
    listScroll:SetScrollChild(ui.enemyList)

    -- Pages panel -------------------------------------------------------------
    ui.pagesPanel = CreateFrame("Frame", nil, parent)
    ui.pagesPanel:SetPoint("TOPLEFT", tabDungeons, "BOTTOMLEFT", 0, -20)
    ui.pagesPanel:SetPoint("BOTTOMRIGHT", -8, 8)
    ui.pagesPanel:Hide()

    ui.scope2 = label(ui.pagesPanel, "")
    ui.scope2:SetPoint("TOPLEFT", 0, 0)

    local pagePrev = button(ui.pagesPanel, "<", 20, 20, function()
        local cat = Core.GetCategory(state.categoryId)
        if not cat or #cat.pages == 0 then return end
        local i = (Util.IndexById(cat.pages, state.pageId) or 1) - 1
        if i < 1 then i = #cat.pages end
        state.pageId = cat.pages[i].id
        Edit.RefreshPages()
    end)
    pagePrev:SetPoint("TOPLEFT", 0, -18)

    ui.pageName = editBox(ui.pagesPanel, 200, 20, 40)
    ui.pageName:SetPoint("LEFT", pagePrev, "RIGHT", 8, 0)
    ui.pageName:SetScript("OnEnterPressed", function(self)
        if state.pageId then
            Core.RenamePage(state.categoryId, state.pageId, self:GetText())
        end
        self:ClearFocus()
        Edit.RefreshPages()
    end)

    local pageNext = button(ui.pagesPanel, ">", 20, 20, function()
        local cat = Core.GetCategory(state.categoryId)
        if not cat or #cat.pages == 0 then return end
        local i = (Util.IndexById(cat.pages, state.pageId) or 1) + 1
        if i > #cat.pages then i = 1 end
        state.pageId = cat.pages[i].id
        Edit.RefreshPages()
    end)
    pageNext:SetPoint("LEFT", ui.pageName, "RIGHT", 6, 0)

    local newPage = button(ui.pagesPanel, "New page", 80, 20, function()
        if not state.categoryId then return end
        local page = Core.AddPage(state.categoryId)
        state.pageId = page.id
        Edit.RefreshPages()
    end)
    newPage:SetPoint("LEFT", pageNext, "RIGHT", 8, 0)

    local delPage = button(ui.pagesPanel, "Delete page", 90, 20, function()
        if not state.pageId then return end
        Core.DeletePage(state.categoryId, state.pageId)
        state.pageId = nil
        Edit.RefreshPages()
    end)
    delPage:SetPoint("LEFT", newPage, "RIGHT", 4, 0)

    local pagesScroll = CreateFrame("ScrollFrame", nil, ui.pagesPanel,
        "UIPanelScrollFrameTemplate")
    pagesScroll:SetPoint("TOPLEFT", 0, -46)
    pagesScroll:SetPoint("BOTTOMRIGHT", -24, 0)
    ui.pageList = CreateFrame("Frame", nil, pagesScroll)
    ui.pageList:SetSize(520, 100)
    pagesScroll:SetScrollChild(ui.pageList)

    -- Opens on Dungeons. Nothing is auto-selected: which dungeon you are
    -- working on should be a choice you made, not one you inherited.
    selectCategory(state.categoryId)
    showTab("dungeons")
end

--- The export-staleness marker. Not a nag: it only appears once enough has
--- changed to be worth losing, because SavedVariables is not written until
--- logout or /reload and a crash takes everything since.
function Edit.RefreshStaleMarker()
    if not ui.stale then return end
    local n = Core.EditsSinceExport()
    if n >= 20 then
        ui.stale:SetText(("|cffd9a441%d edits since last export|r"):format(n))
    else
        ui.stale:SetText("")
    end
end

function Edit.Refresh()
    refreshCategoryLabel()
    Edit.RefreshEnemies()
    Edit.RefreshPages()
    Edit.RefreshStaleMarker()
end
