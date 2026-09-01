--------------------------------------------------------------------------------
-- UI: the collapsible bar, and the Run view.
--
-- The bar is the root. Collapsed, it is nearly invisible, which is its resting
-- state during a key. Run, Edit and Settings hang off it.
--------------------------------------------------------------------------------

local ADDON, MM = ...

MM.UI = {}
local UI = MM.UI
local Core, Runtime, Util = MM.Core, MM.Runtime, MM.Util

local root, bar, views, currentView
local runState = { categoryId = nil }

local BAR_H = 22

--------------------------------------------------------------------------------
-- Small shared widgets
--------------------------------------------------------------------------------

local function button(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h or 22)
    b:SetText(text)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

local function fontString(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
    fs:SetText(text or "")
    return fs
end

--- Applies the user's scale, opacity and drag position.
function UI.ApplySettings()
    local s = Core.Settings()
    if InCombatLockdown() then return false end   -- SetScale is blocked in combat
    root:SetScale(s.scale or 1)
    root:SetAlpha(s.opacity or 1)
    return true
end

--------------------------------------------------------------------------------
-- Views
--------------------------------------------------------------------------------

local function showView(name)
    for viewName, frame in pairs(views) do
        if viewName == name then frame:Show() else frame:Hide() end
    end
    if name ~= "run" then Runtime.HideAll() end
    currentView = name
end

function UI.CurrentView() return currentView end

--------------------------------------------------------------------------------
-- Run: category list, then the pages
--------------------------------------------------------------------------------

local runList, runPlay

local function buildCategoryList()
    for _, child in ipairs(runList.buttons) do child:Hide() end
    wipe(runList.buttons)

    local y = -4
    for _, cat in ipairs(Core.Categories()) do
        local b = button(runList, cat.name, 260, 24, function()
            UI.LoadCategory(cat.id)
        end)
        b:SetPoint("TOPLEFT", 8, y)
        b:Show()
        runList.buttons[#runList.buttons + 1] = b
        y = y - 28
    end

    if #Core.Categories() == 0 then
        runList.empty:Show()
    else
        runList.empty:Hide()
    end

    runList:SetHeight(math.max(60, math.abs(y) + 12))
end

--- Selecting a category is what writes every button's macro text, so it can
--- only happen out of combat. Refusing here, loudly, is the whole guard: there
--- is no half-built state to recover from because nothing is written until it
--- succeeds.
function UI.LoadCategory(catId)
    local ok, err = Runtime.Build(runPlay.pages, catId, Core.Settings())
    if not ok then
        Util.Print("|cffff4444" .. (err or "could not load") .. "|r")
        return false
    end

    local cat = Core.GetCategory(catId)
    runState.categoryId = catId
    runPlay.categoryName:SetText(cat and cat.name or "")
    runPlay:Show()
    runList:Hide()
    return true
end

local function backToCategoryList()
    if InCombatLockdown() then
        Util.Print("|cffff4444can't switch dungeon in combat.|r")
        return
    end
    Runtime.HideAll()
    runState.categoryId = nil
    runPlay:Hide()
    buildCategoryList()
    runList:Show()
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function UI.Init()
    root = CreateFrame("Frame", "MythicMacrosFrame", UIParent)
    root:SetSize(620, 300)
    root:SetPoint("CENTER")
    root:SetMovable(true)
    root:EnableMouse(true)
    root:SetClampedToScreen(true)

    -- The bar ----------------------------------------------------------------
    bar = CreateFrame("Frame", nil, root)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(BAR_H)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() root:StartMoving() end)
    bar:SetScript("OnDragStop", function()
        root:StopMovingOrSizing()
        local point, _, rel, x, y = root:GetPoint()
        Core.Settings().point = { point = point, relativePoint = rel, x = x, y = y }
    end)

    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(0.08, 0.08, 0.11, 0.9)

    local collapse = button(bar, "-", 22, BAR_H - 2)
    collapse:SetPoint("LEFT", 2, 0)

    local runBtn      = button(bar, "Run", 54, BAR_H - 2, function() showView("run") end)
    local editBtn     = button(bar, "Edit", 54, BAR_H - 2, function() showView("edit") end)
    local settingsBtn = button(bar, "Settings", 74, BAR_H - 2, function() showView("settings") end)
    runBtn:SetPoint("LEFT", collapse, "RIGHT", 4, 0)
    editBtn:SetPoint("LEFT", runBtn, "RIGHT", 2, 0)
    settingsBtn:SetPoint("LEFT", editBtn, "RIGHT", 2, 0)

    local body = CreateFrame("Frame", nil, root)
    body:SetPoint("TOPLEFT", bar, "BOTTOMLEFT")
    body:SetPoint("BOTTOMRIGHT")
    local bodyBg = body:CreateTexture(nil, "BACKGROUND")
    bodyBg:SetAllPoints()
    bodyBg:SetColorTexture(0.05, 0.05, 0.07, 0.85)

    collapse:SetScript("OnClick", function(self)
        if body:IsShown() then
            body:Hide(); self:SetText("+"); root:SetHeight(BAR_H)
        else
            body:Show(); self:SetText("-"); root:SetHeight(300)
        end
    end)

    views = {}

    -- Run: the category list -------------------------------------------------
    views.run = CreateFrame("Frame", nil, body)
    views.run:SetAllPoints()

    runList = CreateFrame("Frame", nil, views.run)
    runList:SetPoint("TOPLEFT", 0, 0)
    runList:SetPoint("TOPRIGHT", 0, 0)
    runList.buttons = {}
    runList.empty = fontString(runList,
        "No dungeons yet. Add one under Edit.")
    runList.empty:SetPoint("TOPLEFT", 10, -10)

    -- Run: the pages ---------------------------------------------------------
    runPlay = CreateFrame("Frame", nil, views.run)
    runPlay:SetAllPoints()
    runPlay:Hide()

    local back = button(runPlay, "<", 22, 20, backToCategoryList)
    back:SetPoint("TOPLEFT", 6, -4)

    runPlay.categoryName = fontString(runPlay, "", "GameFontNormal")
    runPlay.categoryName:SetPoint("TOP", runPlay, "TOP", -40, -6)

    -- The arrows are secure handlers. They must be created before Runtime is
    -- asked to bind them, and never clicked from script.
    local nextBtn = CreateFrame("Button", "MythicMacrosNext", runPlay,
        "SecureHandlerClickTemplate,UIPanelButtonTemplate")
    nextBtn:SetSize(24, 20)
    nextBtn:SetPoint("TOPRIGHT", -6, -4)
    nextBtn:SetText(">")

    local prevBtn = CreateFrame("Button", "MythicMacrosPrev", runPlay,
        "SecureHandlerClickTemplate,UIPanelButtonTemplate")
    prevBtn:SetSize(24, 20)
    prevBtn:SetPoint("RIGHT", nextBtn, "LEFT", -4, 0)
    prevBtn:SetText("<")

    runPlay.pages = CreateFrame("Frame", nil, runPlay)
    runPlay.pages:SetPoint("TOPLEFT", 10, -30)
    runPlay.pages:SetPoint("BOTTOMRIGHT", -10, 10)

    runPlay.arrows = { prev = prevBtn, next = nextBtn }

    -- Edit and Settings ------------------------------------------------------
    views.edit = CreateFrame("Frame", nil, body)
    views.edit:SetAllPoints()
    local editSoon = fontString(views.edit, "Edit is not built yet.")
    editSoon:SetPoint("TOPLEFT", 10, -10)

    views.settings = CreateFrame("Frame", nil, body)
    views.settings:SetAllPoints()
    UI.BuildSettings(views.settings)

    buildCategoryList()
    showView("run")

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

function UI.BuildSettings(parent)
    local y = -12

    local function slider(label, key, minv, maxv)
        local text = fontString(parent, label)
        text:SetPoint("TOPLEFT", 12, y)

        local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
        s:SetPoint("TOPLEFT", 130, y + 4)
        s:SetWidth(180)
        s:SetMinMaxValues(minv, maxv)
        s:SetValueStep(0.05)
        s:SetObeyStepOnDrag(true)
        s:SetValue(Core.Settings()[key] or 1)

        local value = fontString(parent, ("%.2f"):format(Core.Settings()[key] or 1))
        value:SetPoint("LEFT", s, "RIGHT", 10, 0)

        s:SetScript("OnValueChanged", function(_, v)
            Core.Settings()[key] = v
            value:SetText(("%.2f"):format(v))
            if not UI.ApplySettings() then
                Util.Print("|cffff4444settings apply out of combat.|r")
            end
        end)

        y = y - 34
        return s
    end

    slider("Opacity", "opacity", 0.2, 1.0)
    slider("Scale", "scale", 0.6, 1.6)
    slider("Button scale", "buttonScale", 0.6, 1.8)
    slider("Text scale", "textScale", 0.6, 1.6)

    local note = fontString(parent,
        "|cffaaaaaaScale and opacity apply out of combat only.|r")
    note:SetPoint("TOPLEFT", 12, y - 6)
end

--------------------------------------------------------------------------------
-- Entry points
--------------------------------------------------------------------------------

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
    if runList then buildCategoryList() end
end

function UI.Arrows()
    return runPlay and runPlay.arrows
end
