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

local ADDON, IMI = ...

IMI.Edit = {}
local Edit = IMI.Edit
local Core, Util = IMI.Core, IMI.Util

local state = { categoryId = nil, pageId = nil, tab = "enemies" }
local ui = {}

local ROW_H, CARD_GAP, INDENT = 22, 8, 14

-- A callout is one line of macro text, but it is often longer than one line of
-- panel. Two lines when you are only reading it, more while you are typing,
-- because the box you are editing is the one you need to see all of.
local LINES_IDLE, LINES_EDITING = 2, 6

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

local function button(parent, text, w, h, onClick, opts)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h or 20)
    IMI.Style.Button(b, text, opts)
    if onClick then b:SetScript("OnClick", onClick) end
    -- The single-character buttons on the cards are the ones that need this
    -- most: "^", "v", "x" and "-" are shapes, not words.
    if opts and opts.tip then IMI.Style.Tooltip(b, opts.tip, opts.tipDetail) end
    return b
end

local function label(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
    fs:SetText(text or "")
    fs:SetTextColor(unpack(IMI.Style.colors.text))
    return fs
end

local function editBox(parent, maxLetters)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetFontObject("ChatFontNormal")
    IMI.Style.EditBox(eb)
    eb:SetHeight(20)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(maxLetters or 64)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    return eb
end

--- A box that shows its text wrapped instead of scrolling it sideways.
---
--- Multi-line, which is what makes it wrap, with one consequence handled: in a
--- multi-line box Enter inserts a newline rather than committing, and a newline
--- in a macro body would break the macro. So a newline arriving from the
--- keyboard is turned back into what Enter used to do — tidy the text, save,
--- and let go. The body can therefore never contain one, whatever the client
--- does with the key.
local function growingBox(parent, maxLetters, onCommit)
    local eb = editBox(parent, maxLetters)
    eb:SetMultiLine(true)

    eb:SetScript("OnTextChanged", function(self, userInput)
        local text = self:GetText() or ""
        if userInput and text:find("[\r\n]") then
            local flat = text:gsub("%s*[\r\n]+%s*", " "):gsub("%s+$", "")
            self:SetText(flat)
            if onCommit then onCommit(self) end
            self:ClearFocus()
            return
        end
        if self.onTextUpdate then self.onTextUpdate(self) end
    end)

    return eb
end

--- How tall a box has to be for the text in it, in whole lines.
---
--- Measured against the box's own width with the font it is actually using,
--- because how much fits depends on the text scale and on which characters they
--- are. One hidden font string does the measuring for every box.
local measureFS
local function boxHeight(parent, eb, text, maxLines)
    if not measureFS then
        measureFS = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        measureFS:Hide()
    end

    local file, size, flags = eb:GetFont()
    if file and size then measureFS:SetFont(file, size, flags) end
    measureFS:SetText(text or "")

    local textWidth = measureFS:GetStringWidth()
    local lineHeight = measureFS:GetStringHeight()
    if type(lineHeight) ~= "number" or lineHeight <= 0 then return ROW_H - 2, 1 end

    local available = (eb:GetWidth() or 200) - 12
    local lines = 1
    if type(textWidth) == "number" and available > 0 and textWidth > available then
        lines = math.min(maxLines, math.ceil(textWidth / available))
    end

    -- The single-line height is what every other row uses, so a one-line box
    -- still lines up with the buttons beside it.
    return math.max(ROW_H - 2, lines * lineHeight + 6), lines
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

--- The character counter follows whichever box has focus.
---
--- Left as a hook rather than three SetScripts: the box owns OnTextChanged, for
--- turning a typed newline back into a commit, and the focus scripts are rebuilt
--- on every refresh. Setting them here as well meant whichever ran last won,
--- which is not a thing to leave to file order.
local function attachCounter(eb)
    eb.onTextUpdate = function(self)
        if self:HasFocus() then updateCounter(self) end
    end
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
            eb.up = button(eb, "^", 20, 18, nil, { tip = "Move up" })
            eb.up:SetPoint("LEFT", eb, "RIGHT", 6, 0)
            eb.down = button(eb, "v", 20, 18, nil, { tip = "Move down" })
            eb.down:SetPoint("LEFT", eb.up, "RIGHT", 2, 0)
            eb.del = button(eb, "x", 20, 18, nil, { danger = true,
                tip = "Delete enemy", tipDetail = "Removes it from every page too." })
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
            IMI.UI.RefreshSidebar()
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
                local eb = growingBox(ui.enemyList, Util.MAX_MACRO_CHARS, function(self)
                    if self.commit then self.commit(self) end
                end)
                eb.del = button(eb, "-", 20, 18, nil, { danger = true,
                    tip = "Delete this line" })
                eb.del:SetPoint("TOPLEFT", eb, "TOPRIGHT", 6, -1)
                attachCounter(eb)
                return eb
            end)
            li = li + 1

            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", ui.enemyList, "TOPLEFT", 10 + INDENT, y)
            box:SetWidth(width - 140 - INDENT)

            -- Not while it is being typed into: SetText moves the caret to the
            -- end, and a relayout happens the moment a box gains focus.
            if not box:HasFocus() then box:SetText(line.body or "") end

            -- Committed on Enter and on losing focus, so clicking away keeps
            -- what was typed rather than discarding it.
            local function commit(self)
                Core.SetLine(state.categoryId, enemy.id, line.id, nil, self:GetText())
            end
            box.commit = commit
            box:SetScript("OnEnterPressed", function(self) commit(self) self:ClearFocus() end)

            -- Gaining or losing focus changes how many lines this box shows, so
            -- everything below it moves. Refresh does not disturb the box being
            -- typed into, which is what makes it safe to call from here.
            box:SetScript("OnEditFocusGained", function(self)
                updateCounter(self)
                Edit.RefreshEnemies()
            end)
            box:SetScript("OnEditFocusLost", function(self)
                commit(self)
                if ui.counter then ui.counter:Hide() end
                Edit.RefreshEnemies()
            end)

            box.del:SetScript("OnClick", function()
                Core.DeleteLine(state.categoryId, enemy.id, line.id)
                Edit.RefreshEnemies()
            end)

            local boxH = boxHeight(ui.enemyList, box, box:GetText(),
                box:HasFocus() and LINES_EDITING or LINES_IDLE)
            box:SetHeight(boxH)

            y = y - boxH - 2
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

    ui.enemyEmpty:SetShown(#Core.Enemies(state.categoryId) == 0)
    ui.enemyList:SetHeight(math.max(20, math.abs(y) + 10))
    IMI.Style.RefreshScrollBar(ui.enemyScroll, math.abs(y) + 10)
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
        local pages = Core.Pages(state.categoryId)
        state.pageId = pages[1] and pages[1].id or nil
    end

    local page = state.pageId and Core.GetPage(state.categoryId, state.pageId)
    ui.pageName:SetText(page and page.name or "")
    ui.pageIndex:SetText(page
        and ("page %d of %d"):format(Util.IndexById(Core.Pages(state.categoryId), page.id) or 1,
            #Core.Pages(state.categoryId))
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
        for _, enemy in ipairs(Core.Enemies(state.categoryId)) do
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
    IMI.Style.RefreshScrollBar(ui.pagesScroll, math.abs(y) + 10)
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
    Edit.RefreshColorSwatch()

    ui.variantLabel:SetShown(cat ~= nil)
    ui.variant:SetShown(cat ~= nil)
    ui.variantNew:SetShown(cat ~= nil)
    ui.variantRename:SetShown(cat ~= nil)
    ui.variantDelete:SetShown(cat ~= nil)
    if not cat then ui.variantName:Hide() end

    Edit.RefreshVariants()
    if cat then showTab(state.tab) end
    Edit.RefreshSendHint()
    Edit.RefreshStaleMarker()
end

--- Opens the picker on this dungeon's colour, applying as it changes so the
--- colour is judged on the interface it will be used on rather than on a
--- preview square.
function Edit.ShowColorPicker()
    if not state.categoryId then
        Util.Print("|cffff4444pick a dungeon on the left first.|r")
        return false
    end

    local catId = state.categoryId
    IMI.Picker.Open({
        title = "Dungeon UI Color",
        color = Core.CategoryColor(catId),
        onChange = function(color)
            Core.SetCategoryColor(catId, color)
            if IMI.UI.SelectedCategory() == catId then
                IMI.Style.SetDungeonColor(color)
            end
            Edit.RefreshColorSwatch()
        end,
        onReset = function()
            Core.SetCategoryColor(catId, nil)
            if IMI.UI.SelectedCategory() == catId then
                IMI.Style.SetDungeonColor(nil)
            end
            Edit.RefreshColorSwatch()
        end,
    })
    return true
end

--- The square beside the button, showing what is set without opening anything.
function Edit.RefreshColorSwatch()
    if not ui.colorSwatch then return end
    local color = state.categoryId and Core.CategoryColor(state.categoryId)
    ui.colorSwatch:SetColorTexture(IMI.Color.Unpack(color, IMI.Style.colors.gold))
    ui.colorSwatchFrame:SetShown(state.categoryId ~= nil)
    ui.colorBtn:SetShown(state.categoryId ~= nil)
end

function Edit.Category() return state.categoryId end

--- Rows whose anchoring is the behaviour under test: both chain right to left
--- from a panel edge, and both were overhanging before they did.
function Edit.VariantRow()
    return { new = ui.variantNew, rename = ui.variantRename, delete = ui.variantDelete }
end

function Edit.AddRow()
    return { box = ui.addBox, add = ui.addBtn, addTarget = ui.addTarget,
             export = ui.exportBtn, import = ui.importBtn }
end

function Edit.SendHint() return ui.sendHint end

--- The line boxes as laid out, for tests: their heights are the behaviour.
function Edit.LineBoxes() return linePool end

--- Where the editor is standing. Recorded with every change, so undo can put
--- the editor back on the page the change was made on rather than leaving you
--- to work out what just moved somewhere off screen.
function Edit.Context()
    return {
        categoryId = state.categoryId,
        tab = state.tab,
        pageId = state.pageId,
        variantId = state.categoryId and Core.ActiveVariantId(state.categoryId) or nil,
    }
end

--- Goes back to a recorded position, skipping any part of it that no longer
--- exists — undoing past the creation of a dungeon leaves nothing to return to,
--- and that is not an error.
function Edit.RestoreContext(ctx)
    if type(ctx) ~= "table" then return end

    local cat = ctx.categoryId and Core.GetCategory(ctx.categoryId)
    if cat then
        if ctx.variantId and Util.FindById(Core.Variants(ctx.categoryId), ctx.variantId) then
            Core.SetActiveVariant(ctx.categoryId, ctx.variantId)
        end
        -- Through the sidebar, so the row highlights too: being taken somewhere
        -- without being shown where is worse than not being taken.
        IMI.UI.SelectCategory(ctx.categoryId)
    end

    -- After SetCategory, which clears the page as part of opening a dungeon.
    state.pageId = ctx.pageId
    showTab(ctx.tab or "enemies")
    Edit.RefreshVariants()
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function Edit.Build(parent)
    -- Directly under the bar's icons, which is where the window's other
    -- whole-panel controls already live.
    ui.redo = button(parent, "->", 26, 20, function() IMI.UI.Redo() end,
        { tip = "Redo" })
    ui.redo:SetPoint("TOPRIGHT", -8, -5)
    ui.undo = button(parent, "<-", 26, 20, function() IMI.UI.Undo() end,
        { tip = "Undo" })
    ui.undo:SetPoint("RIGHT", ui.redo, "LEFT", -3, 0)
    ui.undo:SetEnabled(false)
    ui.redo:SetEnabled(false)
    parent.history = { undo = ui.undo, redo = ui.redo }

    ui.title = IMI.Style.Header(parent, "")
    ui.title:SetFontObject("GameFontNormalLarge")
    ui.title:SetTextColor(unpack(IMI.Style.colors.goldText))
    ui.title:SetPoint("TOP", 0, -6)

    ui.prompt = label(parent, "Pick a dungeon on the left, or make one with New dungeon.")
    ui.prompt:SetPoint("TOPLEFT", 12, -34)

    -- Above the variant row, at the left, because it is a property of the
    -- dungeon rather than of the set of enemies you happen to be editing.
    ui.colorBtn = button(parent, "Dungeon UI Color", 122, 20, function()
        Edit.ShowColorPicker()
    end, { tip = "Dungeon UI Color",
           tipDetail = "Colours this dungeon's headings, panel edges and selection, "
                    .. "so you can tell at a glance which one is open. "
                    .. "The callouts themselves are left alone." })
    ui.colorBtn:SetPoint("TOPLEFT", 8, -28)

    ui.colorSwatchFrame = CreateFrame("Frame", nil, parent)
    ui.colorSwatchFrame:SetSize(18, 18)
    ui.colorSwatchFrame:SetPoint("LEFT", ui.colorBtn, "RIGHT", 6, 0)
    IMI.Style.Border(ui.colorSwatchFrame, IMI.Style.colors.rowEdge)
    ui.colorSwatch = ui.colorSwatchFrame:CreateTexture(nil, "ARTWORK")
    ui.colorSwatch:SetAllPoints()

    -- Variants sit above the tabs, because which set you are editing is a level
    -- above whether you are editing its enemies or its pages.
    ui.variantLabel = label(parent, "Variant")
    ui.variantLabel:SetPoint("TOPLEFT", 8, -52)

    ui.variant = IMI.UI.Dropdown(parent, 120)
    ui.variant:SetPoint("LEFT", ui.variantLabel, "RIGHT", 6, 0)

    ui.variantNew = button(parent, "New", 42, 20, function() Edit.ShowVariantDialog() end,
        { tip = "New variant",
          tipDetail = "A second set of enemies and pages for the same dungeon." })


    ui.variantRename = button(parent, "Rename", 62, 20, function()
        local variant = Core.Variant(state.categoryId)
        if not variant then return end
        ui.variantName:SetText(variant.name)
        ui.variantName:Show()
        ui.variantName:SetFocus()
    end)
    IMI.Style.Tooltip(ui.variantRename, "Rename this variant")

    ui.variantDelete = button(parent, "Delete", 56, 20, function()
        local variant = Core.Variant(state.categoryId)
        if not variant then return end
        if not Core.DeleteVariant(state.categoryId, variant.id) then
            Util.Print("|cffff4444a dungeon needs at least one variant.|r")
            return
        end
        Edit.RefreshVariants()
        Edit.RefreshEnemies()
        Edit.RefreshPages()
    end)
    -- Right to left from the panel edge, and only once all three exist:
    -- anchoring to a button that has not been made yet silently anchors to the
    -- parent instead. Chained the other way the row's width was a sum that had
    -- to come to less than the panel's, and in a narrow window it did not.
    ui.variantDelete:SetPoint("TOPRIGHT", -8, -52)
    ui.variantRename:SetPoint("RIGHT", ui.variantDelete, "LEFT", -3, 0)
    ui.variantNew:SetPoint("RIGHT", ui.variantRename, "LEFT", -3, 0)
    IMI.Style.Tooltip(ui.variantDelete, "Delete this variant",
        "A dungeon always keeps at least one.")

    ui.variantName = editBox(parent, 40)
    -- Over the chooser it renames, rather than in a sixth column the row has no
    -- room for. It is only on screen while a rename is in progress.
    ui.variantName:SetPoint("TOPLEFT", ui.variant, "TOPLEFT", 0, 0)
    ui.variantName:SetPoint("BOTTOMRIGHT", ui.variant, "BOTTOMRIGHT", 0, 0)
    ui.variantName:Hide()
    ui.variantName:SetScript("OnEnterPressed", function(self)
        local variant = Core.Variant(state.categoryId)
        if variant then
            Core.RenameVariant(state.categoryId, variant.id, self:GetText())
        end
        self:Hide()
        self:ClearFocus()
        Edit.RefreshVariants()
    end)
    ui.variantName:SetScript("OnEscapePressed", function(self) self:Hide() end)

    ui.tabEnemies = button(parent, "Enemies", 70, 20, function() showTab("enemies") end)
    ui.tabEnemies:SetPoint("TOPLEFT", 8, -76)
    IMI.Style.Tooltip(ui.tabEnemies, "Enemies", "The callouts themselves, one card per enemy.")
    ui.tabPages = button(parent, "Pages", 62, 20, function() showTab("pages") end)
    ui.tabPages:SetPoint("LEFT", ui.tabEnemies, "RIGHT", 4, 0)
    IMI.Style.Tooltip(ui.tabPages, "Pages", "Which enemies appear on which page in Run.")

    ui.counter = label(parent, "")
    ui.counter:SetPoint("TOPRIGHT", -10, -56)
    ui.counter:Hide()

    ui.stale = label(parent, "")
    ui.stale:SetPoint("TOPRIGHT", ui.counter, "TOPLEFT", -12, 0)

    -- Enemies ------------------------------------------------------------------
    ui.enemiesPanel = CreateFrame("Frame", nil, parent)
    ui.enemiesPanel:SetPoint("TOPLEFT", 6, -100)
    ui.enemiesPanel:SetPoint("BOTTOMRIGHT", -6, 58)

    -- Bounded on both sides and allowed two lines. With only a left anchor it
    -- ran off the panel and was cut off mid-sentence in a narrow window.
    ui.sendHint = label(ui.enemiesPanel, "")
    ui.sendHint:SetPoint("TOPLEFT", 10, -4)
    ui.sendHint:SetPoint("TOPRIGHT", -10, -4)
    ui.sendHint:SetJustifyH("LEFT")
    ui.sendHint:SetWordWrap(true)
    ui.sendHint:SetMaxLines(2)

    -- Sorting is a view, not a rewrite. Changing how the list is displayed
    -- should never quietly discard an arrangement someone built by hand, so
    -- baking it in is a separate, deliberate button.
    ui.sortBtn = button(ui.enemiesPanel, "", 110, 18, function()
        local s = Core.Settings()
        s.enemySort = (s.enemySort == "name") and "manual" or "name"
        Edit.RefreshEnemies()
    end)
    ui.sortBtn:SetPoint("TOPLEFT", ui.sendHint, "BOTTOMLEFT", 0, -4)

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
    ui.enemyEmpty:SetPoint("TOPLEFT", ui.sortBtn, "BOTTOMLEFT", 0, -6)
    ui.enemyEmpty:SetPoint("RIGHT", ui.enemiesPanel, "RIGHT", -10, 0)
    ui.enemyEmpty:SetJustifyH("LEFT")

    local enemyScroll = CreateFrame("ScrollFrame", nil, ui.enemiesPanel, "UIPanelScrollFrameTemplate")
    ui.enemyScroll = IMI.Style.WheelScroll(enemyScroll)
    enemyScroll:SetPoint("TOPLEFT", ui.sortBtn, "BOTTOMLEFT", -10, -6)
    enemyScroll:SetPoint("BOTTOMRIGHT", -24, 0)
    ui.enemyList = CreateFrame("Frame", nil, enemyScroll)
    ui.enemyList:SetSize(470, 40)
    enemyScroll:SetScrollChild(ui.enemyList)

    -- Pages --------------------------------------------------------------------
    ui.pagesPanel = CreateFrame("Frame", nil, parent)
    ui.pagesPanel:SetPoint("TOPLEFT", 6, -76)
    ui.pagesPanel:SetPoint("BOTTOMRIGHT", -6, 58)
    ui.pagesPanel:Hide()

    local pagePrev = button(ui.pagesPanel, "<", 22, 20, function()
        local cat = Core.GetCategory(state.categoryId)
        local pages = Core.Pages(state.categoryId)
        if not cat or #pages == 0 then return end
        local i = (Util.IndexById(pages, state.pageId) or 1) - 1
        if i < 1 then i = #pages end
        state.pageId = pages[i].id
        Edit.RefreshPages()
    end)
    pagePrev:SetPoint("TOPLEFT", 4, -2)
    IMI.Style.Tooltip(pagePrev, "Previous page")

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
        local pages = Core.Pages(state.categoryId)
        if not cat or #pages == 0 then return end
        local i = (Util.IndexById(pages, state.pageId) or 1) + 1
        if i > #pages then i = 1 end
        state.pageId = pages[i].id
        Edit.RefreshPages()
    end)
    pageNext:SetPoint("LEFT", ui.pageName, "RIGHT", 6, 0)
    IMI.Style.Tooltip(pageNext, "Next page")

    ui.pageIndex = label(ui.pagesPanel, "")
    ui.pageIndex:SetPoint("LEFT", pageNext, "RIGHT", 10, 0)

    local delPage = button(ui.pagesPanel, "Delete page", 86, 20, function()
        if not state.pageId then return end
        Core.DeletePage(state.categoryId, state.pageId)
        state.pageId = nil
        Edit.RefreshPages()
    end)
    delPage:SetPoint("TOPRIGHT", -4, -2)
    IMI.Style.Tooltip(delPage, "Delete page",
        "The enemies stay; only the page goes.")

    local pagesScroll = CreateFrame("ScrollFrame", nil, ui.pagesPanel, "UIPanelScrollFrameTemplate")
    ui.pagesScroll = IMI.Style.WheelScroll(pagesScroll)
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
    -- The right edge is set once the buttons beside it exist, below.

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
    ui.addBtn = button(parent, "Add", 50, 20, commitAdd,
        { tip = "Add", tipDetail = "Adds what is typed in the box to the left." })
    -- Chained from the right edge of the panel, not from the box on the left.
    -- Anchored the other way the row's width was a sum of six numbers that had
    -- to come to less than the gap left for it, and it did not: Import hung off
    -- the side of the panel.

    ui.addTarget = button(parent, "Add target", 78, 20, function()
        local name, why = IMI.Capture.AddTarget("target")
        if name then
            Util.Print(("added |cffffff00%s|r to %s."):format(name, why))
            Edit.RefreshEnemies()
        else
            Util.Print("|cffff4444" .. (why or "could not add") .. "|r")
        end
    end)
    IMI.Style.Tooltip(ui.addTarget, "Add target",
        "Adds whatever you have targeted, by its exact name. The keybind does the same.")

    ui.exportBtn = button(parent, "Export", 54, 20, function()
        if not state.categoryId then
            Util.Print("|cffff4444pick a dungeon first.|r") return
        end
        local str, err = IMI.Export.EncodeCategory(state.categoryId)
        if not str then Util.Print("|cffff4444" .. (err or "failed") .. "|r") return end
        Core.MarkExported()
        Edit.RefreshStaleMarker()
        IMI.UI.ShowExport(("Export: %s"):format(Core.GetCategory(state.categoryId).name), str)
    end)
    IMI.Style.Tooltip(exportBtn, "Export",
        "A string you can copy out, to back up or to share.")

    ui.importBtn = button(parent, "Import", 54, 20, function()
        IMI.UI.ShowImport("Import", function(text)
            local what, err = IMI.Export.Import(text)
            if what then
                IMI.UI.RefreshCategories()
                Edit.RefreshEnemies()
            end
            return what, err
        end)
    end)
    local exportBtn, importBtn = ui.exportBtn, ui.importBtn
    importBtn:SetPoint("BOTTOMRIGHT", -10, 12)
    exportBtn:SetPoint("RIGHT", importBtn, "LEFT", -4, 0)
    ui.addTarget:SetPoint("RIGHT", exportBtn, "LEFT", -4, 0)
    ui.addBtn:SetPoint("RIGHT", ui.addTarget, "LEFT", -4, 0)
    ui.addBox:SetPoint("BOTTOMRIGHT", ui.addBtn, "BOTTOMLEFT", -6, 0)

    IMI.Style.Tooltip(importBtn, "Import",
        "Paste a string in. It is added alongside what you have; nothing is overwritten.")

    Edit.RefreshSendHint()
    Edit.SetCategory(nil)
end

--- Only appears once enough has changed to be worth losing. SavedVariables is
--- not written until logout or a reload, and a crash takes everything since.
--- Creating a variant asks the one question that matters: start blank, or start
--- from what is already there. Copying the open variant covers the practical
--- case, and picking a different source is a dropdown change away.
function Edit.ShowVariantDialog()
    if not state.categoryId then
        Util.Print("|cffff4444pick a dungeon on the left first.|r")
        return
    end

    if not ui.dialog then
        local d = CreateFrame("Frame", nil, IMI.UI.root, "BasicFrameTemplateWithInset")
        d:SetSize(320, 130)
        d:SetPoint("CENTER")
        d:SetFrameStrata("FULLSCREEN_DIALOG")

        d.title = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        d.title:SetPoint("TOP", d.TitleBg, "TOP", 0, -5)
        d.title:SetText("New variant")

        d.prompt = label(d, "Name")
        d.prompt:SetPoint("TOPLEFT", 16, -34)

        d.name = editBox(d, 40)
        d.name:SetPoint("TOPLEFT", 60, -32)
        d.name:SetWidth(230)

        d.source = label(d, "")
        d.source:SetPoint("TOPLEFT", 16, -58)

        d.empty = button(d, "Start empty", 100, 22)
        d.empty:SetPoint("BOTTOMLEFT", 16, 14)

        d.copy = button(d, "Copy current", 110, 22)
        d.copy:SetPoint("LEFT", d.empty, "RIGHT", 6, 0)

        d.cancel = button(d, "Cancel", 70, 22, function() d:Hide() end)
        d.cancel:SetPoint("LEFT", d.copy, "RIGHT", 6, 0)

        ui.dialog = d
    end

    local d = ui.dialog
    local current = Core.Variant(state.categoryId)
    local suggested = ("Variant %d"):format(#Core.Variants(state.categoryId) + 1)

    d.name:SetText(suggested)
    d.source:SetText(("|cffaaaaaaCopying would start from|r |cffffff00%s|r")
        :format(current and current.name or "?"))

    local function create(copyFrom)
        local variant = Core.AddVariant(state.categoryId, d.name:GetText(), copyFrom)
        if variant then
            Core.SetActiveVariant(state.categoryId, variant.id)
            state.pageId = nil
            Edit.RefreshVariants()
            Edit.RefreshEnemies()
            Edit.RefreshPages()
        end
        d:Hide()
    end

    d.empty:SetScript("OnClick", function() create(nil) end)
    d.copy:SetScript("OnClick", function() create(current and current.id) end)

    d:Show()
    d.name:SetFocus()
    d.name:HighlightText()
end

--- Fills the chooser and keeps the delete button honest about the last one.
function Edit.RefreshVariants()
    if not ui.variant then return end

    local variants = state.categoryId and Core.Variants(state.categoryId) or {}
    local items = {}
    for _, variant in ipairs(variants) do
        items[#items + 1] = { text = variant.name, value = variant.id }
    end

    ui.variant:SetItems(items, function(variantId)
        Core.SetActiveVariant(state.categoryId, variantId)
        state.pageId = nil
        Edit.RefreshVariants()
        Edit.RefreshEnemies()
        Edit.RefreshPages()
    end)

    local current = state.categoryId and Core.Variant(state.categoryId)
    ui.variant:SetText(current and current.name or "-")
    ui.variantDelete:SetEnabled(#variants > 1)
end

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
    IMI.UI.RefreshSidebar()
end

--- Just the heading. Renaming a dungeon from the sidebar must not go through
--- SetCategory, which clears the selected page: changing a name should not move
--- you somewhere else in the editor.
function Edit.RefreshTitle()
    local cat = state.categoryId and Core.GetCategory(state.categoryId)
    ui.title:SetText(cat and cat.name or "")
end
