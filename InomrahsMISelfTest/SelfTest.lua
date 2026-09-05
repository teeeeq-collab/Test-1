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
-- Who has the keyboard
--
-- Its own copy, not the addon's, so it works whichever version of the addon is
-- installed and keeps working if the addon is the thing that has gone wrong.
--
-- Two ways to hold the keyboard and they look identical from outside: an edit
-- box with focus, and a frame with EnableKeyboard set. EnumerateFrames walks
-- every frame in the game, which is the only way to find the second.
--------------------------------------------------------------------------------

--- A frame walk meets frames this addon has no business reading, and 12.1
--- hands those back as Secret Values: the read succeeds and the first truth
--- test on the result throws. So every test happens inside a pcall and the
--- caller only sees a plain boolean or a plain string. Without this the walk
--- aborts on the first such frame -- which is what broke the addon's own
--- release path and is exactly the kind of thing this report exists to survive.
local function isTrue(frame, method)
    local fn = frame and frame[method]
    if type(fn) ~= "function" then return false end
    local ok, result = pcall(function() return fn(frame) == true end)
    return ok and result == true
end

local function safeString(frame, method)
    local fn = frame and frame[method]
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(function()
        local v = fn(frame)
        if type(v) == "string" and v ~= "" then return v end
        return nil
    end)
    if ok then return value end
    return nil
end

local function describeFrame(frame)
    local name = safeString(frame, "GetName")
    if name then return name end

    local ok, parent = pcall(function() return frame:GetParent() end)
    local parentName = ok and parent and safeString(parent, "GetName")
    return ("unnamed %s in %s"):format(
        tostring(safeString(frame, "GetObjectType") or "?"),
        tostring(parentName or "?"))
end

--- Declared here because the report window's handler is written above it. A
--- local used before its declaration resolves to a global and is nil.
local releaseOurFrames

local function keyboardReport()
    local parts = {}

    local focused = _G.GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if focused then
        parts[#parts + 1] = "focus: " .. describeFrame(focused)
    else
        parts[#parts + 1] = "focus: nothing"
    end

    local holders, skipped = {}, 0
    if type(EnumerateFrames) == "function" then
        local frame = EnumerateFrames()
        while frame do
            if isTrue(frame, "IsKeyboardEnabled") and isTrue(frame, "IsVisible") then
                holders[#holders + 1] = describeFrame(frame)
            end

            local ok, nextFrame = pcall(EnumerateFrames, frame)
            if not ok then
                skipped = skipped + 1
                break
            end
            frame = nextFrame
        end
    else
        holders[#holders + 1] = "EnumerateFrames missing, cannot look"
    end

    parts[#parts + 1] = ("keyboard enabled on: %s"):format(
        #holders > 0 and table.concat(holders, ", ") or "nothing")
    if skipped > 0 then
        parts[#parts + 1] = ("%d frame(s) unreadable"):format(skipped)
    end

    -- Override bindings are the third way keys can stop doing what they should,
    -- and the only one a reload fixes that nothing else does.
    if type(GetBindingKey) == "function" then
        parts[#parts + 1] = ("jump is bound to: %s")
            :format(tostring(GetBindingKey("JUMP") or "nothing"))
    end

    return table.concat(parts, " | ")
end

--- Puts the keyboard back the way the run found it.
---
--- Run before and after every self-test, because a diagnostic that leaves the
--- game unplayable is worse than no diagnostic. It touches only frames this
--- suite or the addon built, plus anything holding focus while off screen --
--- which nothing legitimate does, and which is precisely the state an
--- invisible probe box leaves behind.
function releaseOurFrames()
    local freed = 0

    local focused = _G.GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if focused and focused.ClearFocus then
        local name = safeString(focused, "GetName")
        if not isTrue(focused, "IsVisible")
            or (name and name:find("InomrahsMI", 1, true)) then
            pcall(function() focused:ClearFocus() end)
            freed = freed + 1
        end
    end

    if InomrahsMI and InomrahsMI.UI and InomrahsMI.UI.ReleaseAllKeys then
        pcall(InomrahsMI.UI.ReleaseAllKeys)
    end

    if type(EnumerateFrames) ~= "function" then return freed end

    local frame = EnumerateFrames()
    while frame do
        local name = safeString(frame, "GetName")
        if name and name:find("InomrahsMI", 1, true)
            and isTrue(frame, "IsKeyboardEnabled") then
            pcall(function()
                frame:EnableKeyboard(false)
                if frame.SetPropagateKeyboardInput then
                    frame:SetPropagateKeyboardInput(true)
                end
            end)
            freed = freed + 1
        end

        local ok, nextFrame = pcall(EnumerateFrames, frame)
        if not ok then break end
        frame = nextFrame
    end

    return freed
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

-- Each method against a widget that would actually have it. Asking an edit box
-- for SetColorTexture and reporting the answer as a missing API was this file's
-- own bug: it failed four methods that are all present, on widget types it
-- never looked at.
local REQUIRED_METHODS = {
    { "SetWordWrap", "fontstring" }, { "SetMaxLines", "fontstring" },
    { "GetStringWidth", "fontstring" }, { "GetStringHeight", "fontstring" },
    { "SetResizable", "frame" }, { "StartSizing", "frame" },
    { "StartMoving", "frame" }, { "StopMovingOrSizing", "frame" },
    { "SetAttribute", "frame" }, { "SetFrameLevel", "frame" },
    { "EnableMouseWheel", "scroll" }, { "GetVerticalScrollRange", "scroll" },
    -- SetFrameRef is an insecure call: it is how a frame is handed to a
    -- snippet. GetFrameRef is not — it exists on a handle inside the
    -- restricted environment, and the section below is where it is checked.
    -- Asking a widget for it and calling the answer a missing API was wrong.
    { "SetFrameRef", "secure" },
    { "RegisterForClicks", "button" },
    { "SetColorTexture", "texture" }, { "SetGradient", "texture" },
    { "SetTextInsets", "editbox" }, { "SetMultiLine", "editbox" },
    { "HasFocus", "editbox" }, { "SetNumeric", "editbox" },
}

local probes

local function checkClient()
    for _, name in ipairs(REQUIRED_GLOBALS) do
        check("Client", name, function()
            return _G[name] ~= nil, _G[name] == nil and "missing on this build" or nil
        end)
    end

    -- Probes live on a hidden parent and are built once.
    --
    -- This is the bug that made running the self-test lock the keyboard. An
    -- EditBox is shown the moment it is created and its autofocus defaults to
    -- on, so a bare CreateFrame("EditBox", nil, UIParent) -- built here only to
    -- ask which methods it has -- silently took focus and ate every key the
    -- player pressed, from an invisible, unnamed, zero-size box. A reload was
    -- the only way out, which is exactly what was reported. Nothing built for
    -- inspection may be visible or take focus.
    if not probes then
        local hidden = CreateFrame("Frame", nil, UIParent)
        hidden:Hide()

        local frame = CreateFrame("Frame", nil, hidden)
        local editbox = CreateFrame("EditBox", nil, hidden)
        editbox:SetAutoFocus(false)
        editbox:ClearFocus()
        editbox:EnableKeyboard(false)
        editbox:Hide()

        probes = {
            frame      = frame,
            editbox    = editbox,
            button     = CreateFrame("Button", nil, hidden),
            scroll     = CreateFrame("ScrollFrame", nil, hidden),
            secure     = CreateFrame("Frame", nil, hidden, "SecureHandlerBaseTemplate"),
            fontstring = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"),
            texture    = frame:CreateTexture(nil, "ARTWORK"),
        }
    end
    local widgets = probes

    for _, entry in ipairs(REQUIRED_METHODS) do
        local method, kind = entry[1], entry[2]
        check("Client", ("%s() on a %s"):format(method, kind), function()
            local widget = widgets[kind]
            return widget ~= nil and widget[method] ~= nil,
                (widget and widget[method] == nil) and "missing on this build" or nil
        end)
    end

    -- SetResizeBounds replaced SetMinResize. The addon asks for whichever this
    -- client has; this says which that was.
    -- Recorded on every run, so a report sent after a lockout carries the
    -- answer even when nobody thought to ask for it.
    -- Guarded: this used to be a bare call, and when the frame walk inside it
    -- met a Secret Value it threw -- aborting the entire run, which is why a
    -- locked-out player got no report window at all.
    local okReport, report = pcall(keyboardReport)
    record("Client", "who has the keyboard", true,
        okReport and report or ("could not be read: " .. tostring(report)))

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
    target:Hide()

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

    -- What the addon needs from here, and must have.
    for _, name in ipairs({ "Show", "Hide", "IsShown" }) do
        check("Restricted environment", "frames can " .. name, function()
            return onFrames:find(name, 1, true) ~= nil,
                onFrames:find(name, 1, true) == nil
                    and "NOT available — closing from a key cannot work in combat" or nil
        end)
    end

    for _, name in ipairs({ "ClearBindings", "SetBindingClick" }) do
        check("Restricted environment", "the header can " .. name, function()
            return onHeader:find(name, 1, true) ~= nil,
                onHeader:find(name, 1, true) == nil
                    and "NOT available — keys cannot follow a page flip in combat" or nil
        end)
    end

    -- What is known to be absent. Reported as a measurement, not a failure: the
    -- addon stopped assuming these once this probe first said so, and a report
    -- that cries wolf about a settled question is worse than no report.
    for _, name in ipairs({ "StartMoving", "StopMovingOrSizing", "StartSizing" }) do
        local present = onFrames:find(name, 1, true) ~= nil
        record("Restricted environment", name .. " (expected absent)", true,
            present
                and "PRESENT — this changed. Moving and resizing could work in combat now."
                or "absent, as expected; moving and resizing stay out of combat")
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

--- Compares what is loaded against the manifest generated from the addon's
--- source, rather than a list written from memory. A hand-kept list rots: add a
--- panel, forget the line, and the check for it stops running — which looks
--- exactly like a check that passed.
local function checkVersion()
    local manifest = _G.InomrahsMISelfTestManifest
    record("Self-test", "the manifest loaded", type(manifest) == "table",
        type(manifest) ~= "table" and "Manifest.lua is missing from this addon" or nil)

    local IMI = _G.InomrahsMI
    if type(manifest) ~= "table" or type(IMI) ~= "table" then return end

    local missing = {}
    for _, path in ipairs(manifest.functions or {}) do
        local module, name = path:match("^(%w+)%.(%w+)$")
        if module and (type(IMI[module]) ~= "table" or IMI[module][name] == nil) then
            missing[#missing + 1] = path
        end
    end
    record("Self-test", "every function the source defines is loaded", #missing == 0,
        #missing > 0
            and ("this self-test is out of step with the addon; missing: "
                 .. table.concat(missing, ", "))
            or ("%d checked"):format(#(manifest.functions or {})))

    local absentFrames = {}
    for _, name in ipairs(manifest.frames or {}) do
        if _G[name] == nil then absentFrames[#absentFrames + 1] = name end
    end
    -- A named frame absent at run time is usually just not built yet, so this
    -- reports rather than fails.
    record("Self-test", "named frames built", true,
        #absentFrames > 0
            and ("not built yet: " .. table.concat(absentFrames, ", "))
            or ("all %d built"):format(#(manifest.frames or {})))

    -- Each entry is "SLASH_INOMRAHSMI1=/imi": the global that has to hold the
    -- command, and the command it has to hold. Both halves are checked, plus
    -- the handler the game dispatches to, since a command registered with no
    -- handler behind it types the same as one that was never registered.
    local absentSlash = {}
    for _, entry in ipairs(manifest.slash or {}) do
        local global, key, command = entry:match("^(SLASH_(.-)%d+)=(.+)$")
        if global then
            local registered = _G[global] == command
                and type((SlashCmdList or {})[key]) == "function"
            if not registered then absentSlash[#absentSlash + 1] = command end
        end
    end
    record("Self-test", "slash commands registered", #absentSlash == 0,
        #absentSlash > 0 and table.concat(absentSlash, ", ") or nil)

    local absentSettings = {}
    local settings = IMI.Core and IMI.Core.Settings and IMI.Core.Settings()
    if type(settings) == "table" then
        for _, key in ipairs(manifest.settings or {}) do
            if settings[key] == nil then absentSettings[#absentSettings + 1] = key end
        end
    end
    -- A setting with no value yet is normal; one the source no longer defaults
    -- is the interesting case, and this is where it would show.
    record("Self-test", "settings with no value", true,
        #absentSettings > 0 and table.concat(absentSettings, ", ") or "none")

    record("Self-test", "manifest built for", true, tostring(manifest.builtFor or "unknown"))

    -- Moved under C_AddOns; asking for the old global reported "unknown".
    local reader = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = reader and reader("InomrahsMythicInstructions", "Version")
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
    -- Some widgets are meant to sit on top of another: the "no enemies yet"
    -- message is drawn over the empty list it is describing. Exempted by name,
    -- one pair at a time, rather than by dropping either from the check.
    local allowed = {}
    for _, pair in ipairs((widgets or {}).__allow or {}) do allowed[pair] = true end

    local rects, unresolved = {}, 0
    for name, frame in pairs(widgets or {}) do
        if name ~= "__allow" and frame and frame.IsVisible and frame:IsVisible() then
            local rect = rectOf(frame)
            if rect then rects[#rects + 1] = { name = name, rect = rect }
            else unresolved = unresolved + 1 end
        end
    end

    local clashes = {}
    for i = 1, #rects do
        for j = i + 1, #rects do
            local a, b = rects[i].name, rects[j].name
            if overlaps(rects[i].rect, rects[j].rect)
                and not (allowed[a .. ":" .. b] or allowed[b .. ":" .. a]) then
                clashes[#clashes + 1] = a .. " over " .. b
            end
        end
    end

    record("Layout", label, #clashes == 0,
        #clashes > 0 and table.concat(clashes, ", ")
            or ("%d checked"):format(#rects))
end

--- Opens the window and walks both views, then puts everything back.
---
--- It used to ask you to open the window and run it again, which meant the
--- section most likely to find something was the section most often skipped.
--- Frames only have a position once they are on screen, so there is no way to
--- measure this without showing them — but there is no reason you should have
--- to be the one to do it.
local function checkLayout()
    local IMI = _G.InomrahsMI
    if type(IMI) ~= "table" or not IMI.UI or not IMI.UI.root then return end

    if InCombatLockdown() then
        record("Layout", "skipped", false,
            "this opens the window and switches tabs, which combat refuses")
        return
    end

    local wasShown = IMI.UI.root:IsShown()
    local wasView = IMI.UI.CurrentView and IMI.UI.CurrentView()
    local wasTab = IMI.Edit and IMI.Edit.Context and IMI.Edit.Context().tab

    if not wasShown then IMI.UI.root:Show() end

    checkGroup("title bar", IMI.UI.BarWidgets and IMI.UI.BarWidgets())
    checkGroup("dungeon column", IMI.UI.SidebarWidgets and IMI.UI.SidebarWidgets())

    if IMI.UI.ShowView then IMI.UI.ShowView("run") end
    checkGroup("Run view", IMI.UI.RunWidgets and IMI.UI.RunWidgets())

    if IMI.UI.ShowView then IMI.UI.ShowView("edit") end
    checkGroup("Edit header", IMI.Edit.HeaderWidgets and IMI.Edit.HeaderWidgets())
    checkGroup("Edit bottom row", IMI.Edit.BottomRowWidgets and IMI.Edit.BottomRowWidgets())

    if IMI.Edit.ShowTab then IMI.Edit.ShowTab("enemies") end
    checkGroup("Enemies panel", IMI.Edit.EnemiesPanelWidgets and IMI.Edit.EnemiesPanelWidgets())

    if IMI.Edit.ShowTab then IMI.Edit.ShowTab("pages") end
    checkGroup("Pages panel", IMI.Edit.PagesPanelWidgets and IMI.Edit.PagesPanelWidgets())
    checkGroup("Chat overrides", IMI.Edit.ChannelWidgets and IMI.Edit.ChannelWidgets())

    if IMI.UI.Show and IMI.UI.ProfileWidgets then
        IMI.UI.Show("settings")
        checkGroup("Profile row", IMI.UI.ProfileWidgets())
        IMI.UI.Show("edit")
    end

    -- Back where you left it.
    if IMI.Edit.ShowTab and wasTab then IMI.Edit.ShowTab(wasTab) end
    if IMI.UI.ShowView and wasView then IMI.UI.ShowView(wasView) end
    if not wasShown then IMI.UI.root:Hide() end

    -- Where a callout actually goes. Three levels decide it, and the one that
    -- matters is the one that reaches the macro text on the button.
    if IMI.Core and IMI.Core.ChannelFor then
        local cat = IMI.Core.Categories and IMI.Core.Categories()[1]
        if cat then
            local channel, from = IMI.Core.ChannelFor(cat.id)
            record("Wiring", "where this dungeon's plain text goes", true,
                ("%s (from the %s)"):format(tostring(channel), tostring(from)))
        end
    end

    -- Nothing may hang outside the window it lives in. Measured while it is
    -- still open, before the state above is restored.
    -- All four edges, not two. The callouts overflowed the bottom and drew
    -- onto the game world for a version and a half while this check watched
    -- only the sides and reported everything fine.
    local windowRect = rectOf(IMI.UI.root)
    if windowRect then
        local strays = {}
        local groups = { IMI.UI.BarWidgets and IMI.UI.BarWidgets(),
                         IMI.UI.RunWidgets and IMI.UI.RunWidgets(),
                         IMI.UI.SidebarWidgets and IMI.UI.SidebarWidgets(),
                         IMI.Edit.HeaderWidgets and IMI.Edit.HeaderWidgets(),
                         IMI.Edit.BottomRowWidgets and IMI.Edit.BottomRowWidgets() }
        for _, group in ipairs(groups) do
            for name, frame in pairs(group or {}) do
                if name ~= "__allow" and type(frame) == "table"
                    and frame.IsVisible and frame:IsVisible() then
                    local r = rectOf(frame)
                    if r and (r.right > windowRect.right + 1
                        or r.left < windowRect.left - 1
                        or r.top > windowRect.top + 1
                        or r.bottom < windowRect.bottom - 1) then
                        strays[#strays + 1] = name
                    end
                end
            end
        end

        -- The callouts are not checked against the window one by one: the
        -- scroll frame clips them, so one below the fold is correct rather
        -- than stray. What has to hold is that they are inside it at all.
        if IMI.UI.RunScroll then
            local scroll, host = IMI.UI.RunScroll()
            local inside = scroll and host and scroll.GetScrollChild
                and scroll:GetScrollChild() == host
            record("Layout", "the callouts are in something that clips them",
                inside == true,
                inside ~= true and "the Run panel is not scrolling its cards — "
                    .. "content taller than the window will draw over the game" or nil)
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

--- The addon's version, as the client reports it. Moved under C_AddOns, so
--- asking for the old global answers "unknown".
local function addonVersion()
    local reader = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return tostring((reader and reader("InomrahsMythicInstructions", "Version")) or "?")
end

local function watchErrors()
    if not _G.geterrorhandler then return end
    local previous = geterrorhandler()

    seterrorhandler(function(message, ...)
        local text = tostring(message)
        if text:find("Inomrah", 1, true) then
            errorLog[#errorLog + 1] = { text = text, when = date("%H:%M:%S") }
            InomrahsMISelfTestDB = InomrahsMISelfTestDB or { errors = {} }
            InomrahsMISelfTestDB.errors = InomrahsMISelfTestDB.errors or {}
            -- Stamped with the version that threw it. The log outlives an
            -- install, so a report full of errors from a version that has
            -- already been fixed reads exactly like a version that has not.
            table.insert(InomrahsMISelfTestDB.errors,
                { text = text, when = date("%Y-%m-%d %H:%M:%S"),
                  version = addonVersion() })
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

    -- The callouts sit in a scroll frame, and scrolling it moves a plain frame
    -- that happens to parent protected buttons. Whether combat allows that has
    -- never been measured, and guessing about the restricted environment is
    -- what broke dragging for six versions. Recorded, not failed: if it is
    -- refused, the answer is a smaller scale or another page, not a bug.
    if IMI.UI.RunScroll then
        local scroll = IMI.UI.RunScroll()
        if scroll and scroll.GetVerticalScrollRange then
            local range = scroll:GetVerticalScrollRange() or 0
            if type(range) ~= "number" or range <= 0 then
                record("Combat", "scrolling the callouts", true,
                    "nothing to scroll — open a dungeon with more cards than fit "
                    .. "and run this again")
            else
                local before = scroll:GetVerticalScroll() or 0
                local target = (before > 0) and 0 or math.min(20, range)
                scroll:SetVerticalScroll(target)
                local after = scroll:GetVerticalScroll() or 0
                scroll:SetVerticalScroll(before)
                record("Combat", "scrolling the callouts", true,
                    (math.abs(after - target) < 1)
                        and "allowed — the list can be scrolled mid-fight"
                        or ("refused — it stayed at %s"):format(tostring(after)))
            end
        end
    end
end

--------------------------------------------------------------------------------
-- The report
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 6. Did the self-test itself behave?
--
-- A diagnostic that breaks the game while measuring it is worse than none, and
-- this suite did exactly that: a probe EditBox took focus and locked the
-- keyboard. These check the measuring instrument, so that never ships twice.
--------------------------------------------------------------------------------

local function checkHygiene()
    check("Self-test", "no probe of ours holds the keyboard", function()
        if not probes then return true, "not built yet" end
        for kind, widget in pairs(probes) do
            if isTrue(widget, "IsKeyboardEnabled") then
                return false, kind .. " has the keyboard enabled"
            end
            if isTrue(widget, "IsVisible") then
                return false, kind .. " is on screen"
            end
        end
        return true, "all hidden, none listening"
    end)

    check("Self-test", "the run left focus alone", function()
        local focused = _G.GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        if not focused then return true, "nothing has focus" end
        if not isTrue(focused, "IsVisible") then
            return false, "something off screen has focus: " .. describeFrame(focused)
        end
        return true, "focus is on " .. describeFrame(focused)
    end)
end

--- Every section runs even if one of them throws.
---
--- A run that aborted halfway produced no report at all, which is the worst
--- possible outcome: the fault that stopped it is the one thing nobody can
--- then see. Each section is guarded, and a section that throws records the
--- error as a result instead of taking the rest of the run with it.
local SECTIONS = {
    { "Client", checkClient },
    { "Restricted environment", checkRestricted },
    { "Self-test", checkVersion },
    { "Wiring", checkWiring },
    { "Layout", checkLayout },
}

local function runAll()
    results = {}
    for _, section in ipairs(SECTIONS) do
        local name, fn = section[1], section[2]
        local ok, err = pcall(fn)
        if not ok then
            record(name, "this section could not finish", false, tostring(err))
        end
    end

    -- Nothing this run built may still be holding the keyboard. The run itself
    -- was the lockout once -- so release first, then check, and the check is
    -- about the state the player is actually left in.
    pcall(releaseOurFrames)

    local ok, err = pcall(checkHygiene)
    if not ok then
        record("Self-test", "this section could not finish", false, tostring(err))
    end
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

    -- Split by version, because the log survives an install: an error thrown
    -- by a version that has since been fixed is history, not a fault, and
    -- mixing the two in one list makes a clean run look broken.
    local stored = (InomrahsMISelfTestDB and InomrahsMISelfTestDB.errors) or {}
    local running = addonVersion()
    local current, older = {}, 0
    for _, entry in ipairs(stored) do
        if (entry.version or "?") == running then
            current[#current + 1] = entry
        else
            older = older + 1
        end
    end

    out[#out + 1] = ""
    out[#out + 1] = ("== Errors on this version (%d of %d logged) =="):format(
        #current, #stored)
    if #current == 0 then
        out[#out + 1] = ("nothing thrown by v%s"):format(running)
    end
    for i = math.max(1, #current - 20), #current do
        if current[i] then out[#out + 1] = current[i].when .. "  " .. current[i].text end
    end
    if older > 0 then
        out[#out + 1] = ""
        out[#out + 1] = ("%d older error(s) from earlier versions, kept but not shown. "
            .. "/imitest clear forgets them."):format(older)
    end

    return table.concat(out, "\n")
end

--------------------------------------------------------------------------------
-- A window to read it in, because a hundred lines in the chat frame is not
-- something anyone can copy.
--------------------------------------------------------------------------------

local window

--- Shows the report in a window you can copy from.
---
--- Nothing here takes focus by itself. An earlier version called HighlightText
--- so the report was ready to copy, and that pulls focus into a multi-line edit
--- box — which then receives every key you press, including the ones you need
--- to play. Selecting is a button you press when you want it, and the box lets
--- go the moment the window closes.
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
        scroll:SetPoint("BOTTOMRIGHT", -34, 40)

        window.box = CreateFrame("EditBox", nil, scroll)
        window.box:SetMultiLine(true)
        window.box:SetFontObject("ChatFontNormal")
        window.box:SetWidth(640)
        window.box:SetAutoFocus(false)
        window.box:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            window:Hide()
        end)
        scroll:SetScrollChild(window.box)

        -- Two ways out that need no keyboard at all, because the keyboard is
        -- exactly what you may not have.
        window.select = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
        window.select:SetSize(110, 22)
        window.select:SetPoint("BOTTOMLEFT", 14, 12)
        window.select:SetText("Select all")
        window.select:SetScript("OnClick", function()
            window.box:SetFocus()
            window.box:HighlightText()
        end)

        window.release = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
        window.release:SetSize(150, 22)
        window.release:SetPoint("BOTTOMLEFT", window.select, "BOTTOMRIGHT", 8, 0)
        window.release:SetText("Give keyboard back")
        window.release:SetScript("OnClick", function()
            -- Says what it found before and after, so a click that changes
            -- nothing is still worth something: the last one did nothing and
            -- there was no way to know what it had failed to release.
            print("|cff8f7fe8MI Self-Test|r before: " .. keyboardReport())

            window.box:ClearFocus()
            if InomrahsMI and InomrahsMI.UI and InomrahsMI.UI.ReleaseAllKeys then
                InomrahsMI.UI.ReleaseAllKeys()
            end

            -- Anything of ours still holding it, whichever addon built it.
            releaseOurFrames()

            print("|cff8f7fe8MI Self-Test|r after:  " .. keyboardReport())
        end)

        -- Closing it must never leave the box holding the keyboard.
        window:HookScript("OnHide", function() window.box:ClearFocus() end)

        tinsert(UISpecialFrames, "InomrahsMISelfTestWindow")
    end

    window.box:SetText(text)
    window.box:ClearFocus()
    window:Show()
end

--- Shows the report, and says it in chat if it cannot.
---
--- The window is built from a Blizzard template and a template that goes away
--- in a patch takes the whole report with it -- exactly when the report is what
--- you need. Chat is ugly and always there.
local function showReportSafely(text)
    if pcall(showReport, text) then return end

    print("|cff8f7fe8MI Self-Test|r the report window could not be built. "
        .. "Printing it instead:")
    for line in tostring(text):gmatch("[^\n]*") do
        if line ~= "" then print(line) end
    end
end

--------------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    InomrahsMISelfTestDB = InomrahsMISelfTestDB or { errors = {} }
    watchErrors()
    print("|cff8f7fe8MI Self-Test|r loaded. |cffffff00/imitest|r runs it, "
        .. "|cffffff00/imitest release|r frees the keyboard.")
end)

SLASH_INOMRAHSMISELFTEST1 = "/imitest"
SlashCmdList.INOMRAHSMISELFTEST = function(arg)
    arg = (arg or ""):lower():match("^%s*(.-)%s*$")

    if arg == "combat" then
        results = {}
        pcall(checkCombat)
        showReportSafely(reportText())
        return
    end

    if arg == "keyboard" then
        print("|cff8f7fe8MI Self-Test|r " .. keyboardReport())
        return
    end

    if arg == "release" then
        if window and window.box then window.box:ClearFocus() end
        if window then window:Hide() end
        print("|cff8f7fe8MI Self-Test|r before: " .. keyboardReport())
        releaseOurFrames()
        print("|cff8f7fe8MI Self-Test|r after:  " .. keyboardReport())
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
        showReportSafely(text)
        return
    end

    local failed = 0
    for _, r in ipairs(results) do
        if not r.ok then failed = failed + 1 end
    end
    print(("|cff8f7fe8MI Self-Test|r %d checks, |cff%s%d failed|r. Showing the report.")
        :format(#results, failed > 0 and "ff4444" or "44ff44", failed))
    showReportSafely(text)
end
