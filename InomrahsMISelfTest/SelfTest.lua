--------------------------------------------------------------------------------
-- Self-test: the half of the testing that can only happen inside the game.
--
-- The offline suite covers everything that is arithmetic and data. What it
-- cannot cover is the client itself: whether an API exists on this build,
-- whether the restricted environment allows a call, what a font string actually
-- measures, where a frame actually lands. Every one of those has been an
-- assumption in this addon at some point, and assumptions are what ship broken.
--
-- So this runs in the client and reports. It changes nothing and sends nothing.
--
--   /imitest          run everything and show the report
--   /imitest copy     the same report as text you can select and copy
--   /imitest combat   the checks that only mean anything mid-fight
--
-- It is a separate addon on purpose: it is not needed to play, and nothing it
-- does should be able to affect the addon it is testing.
--------------------------------------------------------------------------------

local ADDON = ...

local results = {}
local errorLog = {}

local function record(section, name, ok, detail)
    results[#results + 1] = {
        section = section, name = name, ok = ok, detail = detail,
    }
end

local function check(section, name, fn)
    local ok, valueOrErr, detail = pcall(fn)
    if not ok then
        record(section, name, false, "error: " .. tostring(valueOrErr))
    else
        record(section, name, valueOrErr and true or false, detail)
    end
end

--------------------------------------------------------------------------------
-- 1. Does this client have what the addon assumes?
--
-- A missing global is the cheapest possible failure to detect and one of the
-- most expensive to diagnose from a screenshot.
--------------------------------------------------------------------------------

local REQUIRED_GLOBALS = {
    "CreateFrame", "InCombatLockdown", "UIParent", "GameTooltip",
    "ClearOverrideBindings", "SetOverrideBindingClick", "UISpecialFrames",
    "IsShiftKeyDown", "IsControlKeyDown", "IsAltKeyDown", "GetCursorPosition",
    "SecureHandlerExecute", "UnitExists", "UnitName",
}

local REQUIRED_METHODS = {
    "SetWordWrap", "SetMaxLines", "GetStringWidth", "GetStringHeight",
    "SetResizable", "StartSizing", "StartMoving", "StopMovingOrSizing",
    "EnableMouseWheel", "GetVerticalScrollRange", "SetFrameRef", "GetFrameRef",
    "RegisterForClicks", "SetAttribute", "SetColorTexture", "SetTextInsets",
    "SetMultiLine", "HasFocus", "SetNumeric",
}

local function checkClient()
    for _, name in ipairs(REQUIRED_GLOBALS) do
        check("Client", name, function()
            return _G[name] ~= nil, _G[name] == nil and "missing on this build" or nil
        end)
    end

    local probe = CreateFrame("EditBox", nil, UIParent)
    local fs = probe:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local scroll = CreateFrame("ScrollFrame", nil, UIParent)

    for _, method in ipairs(REQUIRED_METHODS) do
        check("Client", method .. "()", function()
            local owner = (probe[method] and probe)
                or (fs[method] and fs) or (scroll[method] and scroll)
            return owner ~= nil, owner == nil and "no widget here has it" or nil
        end)
    end

    -- SetResizeBounds replaced SetMinResize. The addon asks for whichever this
    -- client has; this says which that was.
    check("Client", "a resize-bounds call exists", function()
        local f = CreateFrame("Frame", nil, UIParent)
        local which = (f.SetResizeBounds and "SetResizeBounds")
            or (f.SetMinResize and "SetMinResize")
        return which ~= nil, which or "neither"
    end)
end

--------------------------------------------------------------------------------
-- 2. What is the restricted environment willing to do?
--
-- This is the one that matters most. Closing, dragging and resizing the window
-- in combat, and rebinding keys on a page flip, all depend on frame handles
-- inside a snippet having methods this addon has never been able to verify from
-- outside the game.
--------------------------------------------------------------------------------

local PROBE_SNIPPET = [==[
    local target = self:GetFrameRef("target")
    local found = ""
    for _, name in ipairs(newtable("Show", "Hide", "IsShown", "SetWidth", "SetHeight",
                                   "SetPoint", "ClearAllPoints", "StartMoving",
                                   "StopMovingOrSizing", "StartSizing", "SetAttribute",
                                   "GetAttribute", "GetFrameRef")) do
        if target[name] then found = found .. name .. " " end
    end
    self:SetAttribute("probeResult", found)

    local mine = ""
    for _, name in ipairs(newtable("ClearBindings", "SetBindingClick", "SetBinding")) do
        if self[name] then mine = mine .. name .. " " end
    end
    self:SetAttribute("headerResult", mine)
]==]

local function checkRestricted()
    if InCombatLockdown() then
        record("Restricted environment", "skipped", false,
            "run this out of combat: setting up the probe is not allowed mid-fight")
        return
    end

    local header = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    local target = CreateFrame("Button", "InomrahsMISelfTestTarget", UIParent,
        "SecureActionButtonTemplate")

    check("Restricted environment", "the template took", function()
        return type(header.SetFrameRef) == "function",
            type(header.SetFrameRef) ~= "function"
                and "SecureHandlerBaseTemplate did not apply — this is the fault that "
                 .. "has broken the addon twice" or nil
    end)

    if type(header.SetFrameRef) ~= "function" then return end
    if type(SecureHandlerExecute) ~= "function" then
        record("Restricted environment", "SecureHandlerExecute", false,
            "missing, so this cannot be probed from here")
        return
    end

    header:SetFrameRef("target", target)
    local ran = pcall(SecureHandlerExecute, header, PROBE_SNIPPET)

    check("Restricted environment", "the snippet ran", function() return ran end)

    local onFrames = header:GetAttribute("probeResult") or ""
    local onHeader = header:GetAttribute("headerResult") or ""

    -- The three the window's combat behaviour rests on.
    for _, name in ipairs({ "Show", "Hide", "IsShown", "StartMoving",
                            "StopMovingOrSizing", "StartSizing" }) do
        check("Restricted environment", "frames can " .. name, function()
            return onFrames:find(name, 1, true) ~= nil,
                onFrames:find(name, 1, true) == nil
                    and "NOT available — the window cannot do this in combat" or nil
        end)
    end

    -- The two the per-page keybinds rest on.
    for _, name in ipairs({ "ClearBindings", "SetBindingClick" }) do
        check("Restricted environment", "the header can " .. name, function()
            return onHeader:find(name, 1, true) ~= nil,
                onHeader:find(name, 1, true) == nil
                    and "NOT available — keys cannot follow a page flip in combat" or nil
        end)
    end

    record("Restricted environment", "everything the probe saw on a frame", true, onFrames)
    record("Restricted environment", "everything the probe saw on the header", true, onHeader)
end

--------------------------------------------------------------------------------
-- 3. Is this self-test still in step with the addon?
--
-- Everything below reaches into the addon through named accessors, and every
-- one of those calls is guarded, so a self-test older than the addon reports
-- what it can rather than erroring. That silence is the danger: a check that
-- quietly stopped running looks exactly like a check that passed.
--
-- So the accessors are listed and their absence is reported. If this section
-- says something is missing, this addon is older than the one it is testing and
-- the checks that used it did not run.
--------------------------------------------------------------------------------

local EXPECTED = {
    { "UI", "root" }, { "UI", "CurrentView" }, { "UI", "ShowView" },
    { "UI", "CloseButton" }, { "UI", "ToggleButton" }, { "UI", "Arrows" },
    { "UI", "BarWidgets" }, { "UI", "SidebarWidgets" }, { "UI", "RunWidgets" },
    { "UI", "PendingView" },
    { "Edit", "HeaderWidgets" }, { "Edit", "BottomRowWidgets" },
    { "Edit", "EnemiesPanelWidgets" }, { "Edit", "PagesPanelWidgets" },
    { "Runtime", "Manager" }, { "Runtime", "PageButtons" },
    { "Core", "Settings" }, { "Binds", "Chord" }, { "Color", "HSVtoRGB" },
}

local function checkVersion()
    local IMI = _G.InomrahsMI
    if type(IMI) ~= "table" then return end

    local missing = {}
    for _, entry in ipairs(EXPECTED) do
        local module, name = entry[1], entry[2]
        if type(IMI[module]) ~= "table" or IMI[module][name] == nil then
            missing[#missing + 1] = module .. "." .. name
        end
    end

    record("Self-test", "in step with the addon", #missing == 0,
        #missing > 0
            and ("this self-test is older than the addon; these checks did not run: "
                 .. table.concat(missing, ", "))
            or ("%d accessors present"):format(#EXPECTED))

    local version = GetAddOnMetadata and GetAddOnMetadata("InomrahsMythicInstructions", "Version")
    record("Self-test", "addon version", true, tostring(version or "unknown"))
end

--------------------------------------------------------------------------------
-- 4. Is the addon wired up the way it thinks it is?
--------------------------------------------------------------------------------

local function checkWiring()
    local IMI = _G.InomrahsMI
    check("Wiring", "the addon exposed itself", function()
        return type(IMI) == "table",
            type(IMI) ~= "table" and "InomrahsMI is missing — is the addon loaded?" or nil
    end)
    if type(IMI) ~= "table" then return end

    check("Wiring", "the window exists", function() return IMI.UI and IMI.UI.root ~= nil end)

    -- A frame whose work is a snippet must accept one click direction, or it
    -- runs twice per press. That shipped once, as the window toggle.
    local function directions(frame)
        if not frame then return nil end
        local n = 0
        for _ in pairs(frame.__clickTypes or {}) do n = n + 1 end
        return n
    end

    check("Wiring", "the close button has a snippet", function()
        local close = IMI.UI.CloseButton and IMI.UI.CloseButton()
        return close and close:GetAttribute("_onclick") ~= nil
    end)

    check("Wiring", "the toggle button has a snippet", function()
        local toggle = IMI.UI.ToggleButton and IMI.UI.ToggleButton()
        return toggle and toggle:GetAttribute("_onclick") ~= nil
    end)

    check("Wiring", "the page arrows are bound to the pager", function()
        local arrows = IMI.UI.Arrows and IMI.UI.Arrows()
        return arrows and arrows.next and arrows.next:GetAttribute("_onclick") ~= nil
    end)

    check("Wiring", "the pager exists", function()
        return IMI.Runtime and IMI.Runtime.Manager and IMI.Runtime.Manager() ~= nil
    end)
end

--------------------------------------------------------------------------------
-- 5. Where things actually are.
--
-- The offline suite resolves anchors into rectangles from what it recorded. The
-- client knows the real answer, including everything the resolver has to guess
-- at — font metrics, templates, scale. This asks it.
--------------------------------------------------------------------------------

local function rectOf(frame)
    if not frame or not frame.GetLeft then return nil end
    local left, right = frame:GetLeft(), frame:GetRight()
    local bottom, top = frame:GetBottom(), frame:GetTop()
    if not (left and right and bottom and top) then return nil end
    return { left = left, right = right, bottom = bottom, top = top }
end

local function overlaps(a, b)
    return a.left + 1 < b.right and b.left + 1 < a.right
       and a.bottom + 1 < b.top and b.bottom + 1 < a.top
end

local function checkGroup(label, widgets)
    local rects, unresolved = {}, 0
    for name, frame in pairs(widgets or {}) do
        if frame and frame.IsVisible and frame:IsVisible() then
            local rect = rectOf(frame)
            if rect then rects[#rects + 1] = { name = name, rect = rect }
            else unresolved = unresolved + 1 end
        end
    end

    local clashes = {}
    for i = 1, #rects do
        for j = i + 1, #rects do
            if overlaps(rects[i].rect, rects[j].rect) then
                clashes[#clashes + 1] = rects[i].name .. " over " .. rects[j].name
            end
        end
    end

    record("Layout", label, #clashes == 0,
        #clashes > 0 and table.concat(clashes, ", ")
            or ("%d checked"):format(#rects))
end

local function checkLayout()
    local IMI = _G.InomrahsMI
    if type(IMI) ~= "table" or not IMI.UI or not IMI.UI.root then return end

    if not IMI.UI.root:IsShown() then
        record("Layout", "skipped", false, "open the window first, then run this again")
        return
    end

    checkGroup("title bar", IMI.UI.BarWidgets and IMI.UI.BarWidgets())
    checkGroup("dungeon column", IMI.UI.SidebarWidgets and IMI.UI.SidebarWidgets())

    if IMI.UI.CurrentView() == "edit" then
        checkGroup("Edit header", IMI.Edit.HeaderWidgets and IMI.Edit.HeaderWidgets())
        checkGroup("Edit bottom row", IMI.Edit.BottomRowWidgets and IMI.Edit.BottomRowWidgets())
        checkGroup("Enemies panel", IMI.Edit.EnemiesPanelWidgets and IMI.Edit.EnemiesPanelWidgets())
        checkGroup("Pages panel", IMI.Edit.PagesPanelWidgets and IMI.Edit.PagesPanelWidgets())
    elseif IMI.UI.CurrentView() == "run" then
        checkGroup("Run view", IMI.UI.RunWidgets and IMI.UI.RunWidgets())
    end

    -- Nothing may hang outside the window it lives in.
    local windowRect = rectOf(IMI.UI.root)
    if windowRect then
        local strays = {}
        local groups = { IMI.UI.BarWidgets and IMI.UI.BarWidgets(),
                         IMI.Edit.BottomRowWidgets and IMI.Edit.BottomRowWidgets() }
        for _, group in ipairs(groups) do
            for name, frame in pairs(group or {}) do
                if frame and frame.IsVisible and frame:IsVisible() then
                    local r = rectOf(frame)
                    if r and (r.right > windowRect.right + 1 or r.left < windowRect.left - 1) then
                        strays[#strays + 1] = name
                    end
                end
            end
        end
        record("Layout", "nothing hangs off the edge", #strays == 0,
            #strays > 0 and table.concat(strays, ", ") or nil)
    end
end

--------------------------------------------------------------------------------
-- 6. Anything the addon threw while you were playing.
--
-- Errors are easy to miss and hard to reproduce. This keeps them so they can be
-- read later, rather than depending on someone catching a red box mid-pull.
--------------------------------------------------------------------------------

local function watchErrors()
    if not _G.geterrorhandler then return end
    local previous = geterrorhandler()

    seterrorhandler(function(message, ...)
        local text = tostring(message)
        if text:find("Inomrah", 1, true) then
            errorLog[#errorLog + 1] = { text = text, when = date("%H:%M:%S") }
            InomrahsMISelfTestDB = InomrahsMISelfTestDB or { errors = {} }
            InomrahsMISelfTestDB.errors = InomrahsMISelfTestDB.errors or {}
            table.insert(InomrahsMISelfTestDB.errors,
                { text = text, when = date("%Y-%m-%d %H:%M:%S") })
        end
        return previous(message, ...)
    end)
end

--------------------------------------------------------------------------------
-- 7. The combat checks, which only mean anything mid-fight.
--------------------------------------------------------------------------------

local function checkCombat()
    if not InCombatLockdown() then
        record("Combat", "not in combat", false,
            "get into a fight and run /imitest combat again")
        return
    end

    local IMI = _G.InomrahsMI
    if type(IMI) ~= "table" then return end

    -- Whether a thing is refused is measured by its effect, never by whether a
    -- call threw: the blocked operations here fail silently.
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetWidth(50)
    check("Combat", "an ordinary frame can still be resized", function()
        frame:SetWidth(90)
        return frame:GetWidth() == 90, ("width came back %s"):format(frame:GetWidth())
    end)

    check("Combat", "the window refuses to switch views", function()
        local before = IMI.UI.CurrentView()
        local wanted = (before == "run") and "edit" or "run"
        local claimed = IMI.UI.ShowView(wanted)
        local after = IMI.UI.CurrentView()
        return claimed == false and after == before,
            ("claimed %s, view is %s"):format(tostring(claimed), tostring(after))
    end)

    check("Combat", "a deferred switch is remembered", function()
        return IMI.UI.PendingView() ~= nil,
            "it should switch by itself when the fight ends"
    end)
end

--------------------------------------------------------------------------------
-- The report
--------------------------------------------------------------------------------

local function runAll()
    results = {}
    checkClient()
    checkRestricted()
    checkVersion()
    checkWiring()
    checkLayout()
end

local function reportText()
    local out = { "Inomrah's Mythic Instructions — self-test",
                  date("%Y-%m-%d %H:%M:%S"),
                  ("client build %s"):format(tostring((select(4, GetBuildInfo())))),
                  "" }

    local section, passed, failed = nil, 0, 0
    for _, r in ipairs(results) do
        if r.section ~= section then
            section = r.section
            out[#out + 1] = ""
            out[#out + 1] = "== " .. section .. " =="
        end
        out[#out + 1] = ("[%s] %s%s"):format(r.ok and "ok  " or "FAIL", r.name,
            r.detail and ("  -- " .. r.detail) or "")
        if r.ok then passed = passed + 1 else failed = failed + 1 end
    end

    out[#out + 1] = ""
    out[#out + 1] = ("%d ok, %d failed"):format(passed, failed)

    local stored = (InomrahsMISelfTestDB and InomrahsMISelfTestDB.errors) or {}
    out[#out + 1] = ""
    out[#out + 1] = ("== Errors seen (%d) =="):format(#stored)
    for i = math.max(1, #stored - 20), #stored do
        if stored[i] then out[#out + 1] = stored[i].when .. "  " .. stored[i].text end
    end

    return table.concat(out, "\n")
end

--------------------------------------------------------------------------------
-- A window to read it in, because a hundred lines in the chat frame is not
-- something anyone can copy.
--------------------------------------------------------------------------------

local window

local function showReport(text)
    if not window then
        window = CreateFrame("Frame", "InomrahsMISelfTestWindow", UIParent,
            "BasicFrameTemplateWithInset")
        window:SetSize(700, 500)
        window:SetPoint("CENTER")
        window:SetFrameStrata("DIALOG")
        window:SetMovable(true)
        window:EnableMouse(true)
        window:RegisterForDrag("LeftButton")
        window:SetScript("OnDragStart", window.StartMoving)
        window:SetScript("OnDragStop", window.StopMovingOrSizing)

        local scroll = CreateFrame("ScrollFrame", "InomrahsMISelfTestScroll", window,
            "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 14, -32)
        scroll:SetPoint("BOTTOMRIGHT", -34, 14)

        window.box = CreateFrame("EditBox", nil, scroll)
        window.box:SetMultiLine(true)
        window.box:SetFontObject("ChatFontNormal")
        window.box:SetWidth(640)
        window.box:SetAutoFocus(false)
        window.box:SetScript("OnEscapePressed", function() window:Hide() end)
        scroll:SetScrollChild(window.box)

        tinsert(UISpecialFrames, "InomrahsMISelfTestWindow")
    end

    window.box:SetText(text)
    window.box:HighlightText()
    window:Show()
end

--------------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    InomrahsMISelfTestDB = InomrahsMISelfTestDB or { errors = {} }
    watchErrors()
    print("|cff8f7fe8MI Self-Test|r loaded. |cffffff00/imitest|r runs it.")
end)

SLASH_INOMRAHSMISELFTEST1 = "/imitest"
SlashCmdList.INOMRAHSMISELFTEST = function(arg)
    arg = (arg or ""):lower():match("^%s*(.-)%s*$")

    if arg == "combat" then
        results = {}
        checkCombat()
        showReport(reportText())
        return
    end

    if arg == "clear" then
        InomrahsMISelfTestDB.errors = {}
        print("|cff8f7fe8MI Self-Test|r error log cleared.")
        return
    end

    runAll()
    local text = reportText()

    if arg == "copy" then
        showReport(text)
        return
    end

    local failed = 0
    for _, r in ipairs(results) do
        if not r.ok then failed = failed + 1 end
    end
    print(("|cff8f7fe8MI Self-Test|r %d checks, |cff%s%d failed|r. Showing the report.")
        :format(#results, failed > 0 and "ff4444" or "44ff44", failed))
    showReport(text)
end
