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

local ADDON, MM = ...

MM.UI = {}
local UI = MM.UI
local Core, Runtime, Util = MM.Core, MM.Runtime, MM.Util

local root, bar, body, sidebar, content
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

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

local function fontString(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
    fs:SetText(text or "")
    fs:SetTextColor(unpack(MM.Style.colors.text))
    return fs
end

local function panelButton(parent, text, w, h, onClick, opts)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h or 20)
    MM.Style.Button(b, text, opts)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

--- Hand-skinned, because secure frames must inherit their secure template and
--- nothing else: adding a button template alongside one replaces the secure
--- OnLoad and the frame silently loses SetFrameRef and its handler methods.
local function skin(b, text)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.16, 0.16, 0.21, 0.95)

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

    MM.Style.Background(dd.list, MM.Style.colors.window)
    MM.Style.Border(dd.list, MM.Style.colors.gold)

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
    root:SetAlpha(s.opacity or 1)
    return true
end

--------------------------------------------------------------------------------
-- Sidebar
--------------------------------------------------------------------------------

local sidebarRows = {}

local function selectCategory(id)
    -- Opening a different dungeon ends the previous one's route memory.
    if selected.categoryId and selected.categoryId ~= id then
        lastPage[selected.categoryId] = nil
    end

    selected.categoryId = id
    MM.Capture.SetCategory(id)
    UI.RefreshSidebar()

    if currentView == "run" then
        UI.OpenRun(id)
    elseif currentView == "edit" then
        MM.Edit.SetCategory(id)
    end
end

function UI.SelectedCategory()
    return selected.categoryId
end

function UI.RefreshSidebar()
    for _, row in ipairs(sidebarRows) do row:Hide() end

    local y = -4
    for i, cat in ipairs(Core.Categories()) do
        local row = sidebarRows[i]
        if not row then
            row = panelButton(sidebar.list, "", SIDE_W - 16, 22, nil,
                { justify = "LEFT" })
            sidebarRows[i] = row
        end
        row:SetPoint("TOPLEFT", sidebar.list, "TOPLEFT", 6, y)
        row:SetText(cat.name)
        row:SetScript("OnClick", function() selectCategory(cat.id) end)

        -- The selected dungeon is highlighted, so which one the right panel is
        -- showing never has to be inferred from its heading.
        if cat.id == selected.categoryId then row:LockHighlight() else row:UnlockHighlight() end

        row:Show()
        y = y - 24
    end

    sidebar.empty:SetShown(#Core.Categories() == 0)
    sidebar.list:SetHeight(math.max(20, math.abs(y)))
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
    if currentView == "edit" then MM.Edit.SetCategory(cat.id) end
end

--------------------------------------------------------------------------------
-- Views
--------------------------------------------------------------------------------

local function showView(name)
    for viewName, frame in pairs(views) do
        if viewName == name then frame:Show() else frame:Hide() end
    end

    -- Secure buttons left showing under another view would sit on top of it,
    -- and could not be hidden later if a pull started.
    if name ~= "run" then Runtime.HideAll() end

    currentView = name
    sidebar:SetShown(name ~= "settings")
    sidebar.newBtn:SetShown(name == "edit")

    if bar and bar.tabs then
        for tabName, btn in pairs(bar.tabs) do
            if tabName == name then btn:LockHighlight() else btn:UnlockHighlight() end
        end
    end

    if name == "edit" then
        MM.Edit.SetCategory(selected.categoryId)
    elseif name == "run" and selected.categoryId then
        UI.OpenRun(selected.categoryId)
    end

    UI.RefreshSidebar()
end

function UI.CurrentView() return currentView end
function UI.ShowView(name) showView(name) end

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
    root = CreateFrame("Frame", "MythicMacrosFrame", UIParent)
    root:SetSize(760, 380)
    root:SetPoint("CENTER")
    root:SetMovable(true)
    root:EnableMouse(true)
    root:SetClampedToScreen(true)

    MM.Style.Background(root, MM.Style.colors.window)
    MM.Style.Border(root, MM.Style.colors.gold)

    -- Bar --------------------------------------------------------------------
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

    MM.Style.Background(bar, MM.Style.colors.bar)

    local collapse = panelButton(bar, "-", 22, BAR_H - 4)
    collapse:SetPoint("LEFT", 3, 0)

    -- Run and Edit are where the work happens, so they get the left. Settings,
    -- help and close are occasional, so they sit as icons on the right, out of
    -- the way of the two buttons actually used every session.
    local runBtn  = panelButton(bar, "Run", 60, BAR_H - 4, function() showView("run") end)
    local editBtn = panelButton(bar, "Edit", 60, BAR_H - 4, function() showView("edit") end)
    runBtn:SetPoint("LEFT", collapse, "RIGHT", 4, 0)
    editBtn:SetPoint("LEFT", runBtn, "RIGHT", 2, 0)

    bar.tabs = { run = runBtn, edit = editBtn }

    local close = panelButton(bar, "X", 22, BAR_H - 4, function() root:Hide() end)
    close:SetPoint("RIGHT", -3, 0)

    local gear = panelButton(bar, "*", 22, BAR_H - 4, function()
        showView(currentView == "settings" and "run" or "settings")
    end)
    gear:SetPoint("RIGHT", close, "LEFT", -2, 0)

    local info = panelButton(bar, "?", 22, BAR_H - 4, function() UI.ShowHelp() end)
    info:SetPoint("RIGHT", gear, "LEFT", -2, 0)

    bar.title = MM.Style.Header(bar, "Inomrah's Mythic Instructions")
    bar.title:SetPoint("CENTER", bar, "CENTER", 0, 0)

    body = CreateFrame("Frame", nil, root)
    body:SetPoint("TOPLEFT", bar, "BOTTOMLEFT")
    body:SetPoint("BOTTOMRIGHT")

    collapse:SetScript("OnClick", function(self)
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

    MM.Style.Panel(sidebar)

    sidebar.header = MM.Style.Header(sidebar, "Dungeons")
    sidebar.header:SetPoint("TOP", 0, -6)

    -- Pinned to the bottom, so they stay put however long the list grows.
    sidebar.back = panelButton(sidebar, "Back", SIDE_W - 16, 22, function()
        UI.RememberPage()
        selected.categoryId = nil
        Runtime.HideAll()
        views.run.title:SetText("")
        views.run.prompt:SetText("Pick a dungeon on the left.")
        views.run.prompt:Show()
        if views.run.variant then views.run.variant:Hide() end
        MM.Edit.SetCategory(nil)
        UI.RefreshSidebar()
    end)
    sidebar.back:SetPoint("BOTTOMLEFT", 8, 8)

    sidebar.newBtn = panelButton(sidebar, "New dungeon", SIDE_W - 16, 22, function()
        sidebar.newName:Show()
        sidebar.newName:SetText("")
        sidebar.newName:SetFocus()
    end)
    sidebar.newBtn:SetPoint("BOTTOMLEFT", sidebar.back, "TOPLEFT", 0, 4)

    sidebar.newName = CreateFrame("EditBox", nil, sidebar)
    sidebar.newName:SetFontObject("ChatFontNormal")
    MM.Style.EditBox(sidebar.newName)
    sidebar.newName:SetSize(SIDE_W - 22, 20)
    sidebar.newName:SetPoint("BOTTOMLEFT", sidebar.newBtn, "TOPLEFT", 5, 4)
    sidebar.newName:SetAutoFocus(false)
    sidebar.newName:SetMaxLetters(64)
    sidebar.newName:SetScript("OnEnterPressed", commitNewCategory)
    sidebar.newName:SetScript("OnEscapePressed", function(self)
        self:SetText(""); self:Hide()
    end)
    sidebar.newName:Hide()

    local listScroll = CreateFrame("ScrollFrame", nil, sidebar, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 0, -24)
    listScroll:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -24, 82)
    sidebar.list = CreateFrame("Frame", nil, listScroll)
    sidebar.list:SetSize(SIDE_W - 24, 40)
    listScroll:SetScrollChild(sidebar.list)

    sidebar.empty = fontString(sidebar, "|cffaaaaaaNothing yet.|r")
    sidebar.empty:SetPoint("TOPLEFT", 10, -30)

    -- Content ------------------------------------------------------------------
    content = CreateFrame("Frame", nil, body)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 6, 0)
    content:SetPoint("BOTTOMRIGHT", -6, 6)

    MM.Style.Panel(content)

    views = {}

    -- Run ----------------------------------------------------------------------
    views.run = CreateFrame("Frame", nil, content)
    views.run:SetAllPoints()

    views.run.title = MM.Style.Header(views.run, "")
    views.run.title:SetFontObject("GameFontNormalLarge")
    views.run.title:SetTextColor(unpack(MM.Style.colors.goldText))
    views.run.title:SetPoint("TOP", 0, -6)

    local nextBtn = CreateFrame("Button", "MythicMacrosNext", views.run, "SecureHandlerClickTemplate")
    nextBtn:SetSize(26, 20)
    nextBtn:SetPoint("TOPRIGHT", -8, -6)
    skin(nextBtn, ">")

    local prevBtn = CreateFrame("Button", "MythicMacrosPrev", views.run, "SecureHandlerClickTemplate")
    prevBtn:SetSize(26, 20)
    prevBtn:SetPoint("RIGHT", nextBtn, "LEFT", -4, 0)
    skin(prevBtn, "<")

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
    MM.Edit.Build(views.edit)

    -- Settings -----------------------------------------------------------------
    views.settings = CreateFrame("Frame", nil, body)
    views.settings:SetPoint("TOPLEFT", 12, -12)
    views.settings:SetPoint("BOTTOMRIGHT", -12, 12)
    UI.BuildSettings(views.settings)

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
        MM.Style.EditBox(box)
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
        if MM.Edit and MM.Edit.RefreshSendHint then MM.Edit.RefreshSendHint() end
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

    local resetAll = panelButton(parent, "Reset all", 90, 22, function()
        for key, value in pairs(SETTING_DEFAULTS) do
            Core.Settings()[key] = value
        end
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
        if chanBtn then chanBtn:SetText(Core.Settings().channel or Util.DEFAULT_CHANNEL) end
    end

    UI.RefreshSettings()
end

--------------------------------------------------------------------------------
-- The string window, used for both export and import
--------------------------------------------------------------------------------

local stringWindow

local function ensureStringWindow()
    if stringWindow then return stringWindow end

    local f = CreateFrame("Frame", "MythicMacrosStringWindow", UIParent,
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

    local scroll = CreateFrame("ScrollFrame", "MythicMacrosStringScroll", f,
        "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -32)
    scroll:SetPoint("BOTTOMRIGHT", -34, 44)

    f.editBox = CreateFrame("EditBox", nil, scroll)
    f.editBox:SetMultiLine(true)
    f.editBox:SetMaxLetters(0)
    f.editBox:SetAutoFocus(false)
    f.editBox:SetFontObject(ChatFontNormal)
    f.editBox:SetWidth(500)
    f.editBox:SetHeight(220)
    f.editBox:SetScript("OnEscapePressed", function() f:Hide() end)
    scroll:SetScrollChild(f.editBox)

    f.action = panelButton(f, "", 110, 22)
    f.action:SetPoint("BOTTOMRIGHT", -16, 14)

    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("BOTTOMLEFT", 18, 20)

    stringWindow = f
    return f
end

function UI.ShowExport(title, text)
    local f = ensureStringWindow()
    f.title:SetText(title)
    f.hint:SetText("Already selected - press Cmd-C / Ctrl-C")
    f.editBox:SetText(text or "")
    f.action:SetText("Close")
    f.action:SetScript("OnClick", function() f:Hide() end)
    f:Show()
    f.editBox:SetFocus()
    f.editBox:HighlightText()
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
        "  /imi           open or close  (/mm still works)",
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
