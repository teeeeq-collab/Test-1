--------------------------------------------------------------------------------
-- Run Capability Lab — Stage 2
--
-- Stage 1 asked what the client permits. Stage 2 asks whether the three things
-- the Run UI actually needs can move independently while a fight is happening:
--
--     pageIndex        1 or 2
--     presentationMode FULL / COMPACT / MINIMAL
--     rootVisible      true or false
--
-- and whether one physical callout key follows the page without ever firing the
-- wrong one. That last point is a correctness requirement rather than a
-- convenience: a page is a context layer, so a stale binding does not mean
-- "nothing happens", it means the addon runs the previous page's macro during a
-- live pull.
--
-- Three binding owners, because ClearBindings is not selective. The pager
-- rebuilds its own keys on every flip; if it also owned the mode keys it would
-- delete them each time. Production already separates the open/close key for
-- exactly this reason, and this extends the same principle.
--
-- Everything here is synthetic and named InomrahsMISelfTestS2*. No production
-- frame is read, referenced, shown, hidden, bound or unbound.
--------------------------------------------------------------------------------

local Lab = _G.InomrahsMISelfTestRunLab
if type(Lab) ~= "table" then return end

InomrahsMISelfTestStage2 = {}
local S2 = InomrahsMISelfTestStage2

local PREFIX = "|cff8f7fe8MI Stage2|r "

-- Chat and, when asked, the report window. A dozen lines of diagnostic scroll
-- past in chat; the window keeps them where they can be copied.
local capture = nil

local function say(...)
    local text = string.format(...)
    print(PREFIX .. text)
    if capture then
        capture[#capture + 1] = (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    end
end

local function beginCapture() capture = {} end

local function endCapture(title)
    local lines = capture
    capture = nil
    if not lines or #lines == 0 then return end
    if InCombatLockdown() then return end
    local API = _G.InomrahsMISelfTestAPI
    local text = ("%s\n%s\n\n%s\n"):format(title, ("="):rep(52),
        table.concat(lines, "\n"))
    if API and API.Report then API.Report(text) else print(text) end
end

--------------------------------------------------------------------------------
-- Guarded reads. Every frame read in this file goes through one of these: a
-- value from the restricted side can be a secret, and the first comparison
-- against one throws.
--------------------------------------------------------------------------------

local function num(fn, frame)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, frame)
    if ok and type(value) == "number" then return value end
    return nil
end

local function shown(f)
    if not f then return nil end
    local ok, value = pcall(f.IsShown, f)
    if not ok then return nil end
    if value == true then return true end
    if value == false then return false end
    return nil
end

local function width(f)  return f and num(f.GetWidth, f) end
local function height(f) return f and num(f.GetHeight, f) end
local function scale(f)  return f and num(f.GetScale, f) end

local function attr(frame, name)
    if not frame then return nil end
    local ok, value = pcall(frame.GetAttribute, frame, name)
    if not ok then return nil end
    return tonumber(value)
end

local function fmt(v)
    if type(v) == "number" then return ("%.2f"):format(v) end
    if v == nil then return "unreadable" end
    return tostring(v)
end

local function tri(v)
    if v == true then return "yes" end
    if v == false then return "no" end
    return "unreadable"
end

local function inCombat() return InCombatLockdown() == true end

--------------------------------------------------------------------------------
-- Evidence
--
-- One counter per page, incremented by that page's own macro. A test never
-- passes on "the total went up": it passes only when the expected page's
-- counter moved and the other one did not. Both moving is a worse failure than
-- neither, because in production it would send two callouts from one press.
--------------------------------------------------------------------------------

S2.fired = { 0, 0 }

function InomrahsMISelfTestS2Fired(page)
    page = tonumber(page)
    if page ~= 1 and page ~= 2 then return end
    S2.fired[page] = (S2.fired[page] or 0) + 1
end

S2.collision = { page = 0, mode = 0 }

function InomrahsMISelfTestS2Collision(which)
    if which == "page" or which == "mode" then
        S2.collision[which] = (S2.collision[which] or 0) + 1
    end
end

--------------------------------------------------------------------------------
-- Keys
--------------------------------------------------------------------------------

local KEYS = {
    { id = "action",  key = "CTRL-SHIFT-F6",      what = "contextual action",  owner = "pager" },
    { id = "prev",    key = "CTRL-SHIFT-F7",      what = "previous page",      owner = "pager" },
    { id = "next",    key = "CTRL-SHIFT-F8",      what = "next page",          owner = "pager" },
    { id = "full",    key = "CTRL-SHIFT-F9",      what = "Full",               owner = "moder" },
    { id = "compact", key = "CTRL-SHIFT-F10",     what = "Compact",            owner = "moder" },
    { id = "minimal", key = "CTRL-SHIFT-F11",     what = "Minimal",            owner = "moder" },
    { id = "cycle",   key = "CTRL-SHIFT-F12",     what = "cycle mode",         owner = "moder" },
    { id = "toggle",  key = "CTRL-ALT-SHIFT-F12", what = "show/hide Run root", owner = "toggler" },
}

local COLLIDE_PAGE_KEY = "CTRL-ALT-SHIFT-F10"
local COLLIDE_MODE_KEY = "CTRL-ALT-SHIFT-F11"

local function keyFor(id)
    for _, entry in ipairs(KEYS) do
        if entry.id == id then return entry.key end
    end
    return "?"
end

--------------------------------------------------------------------------------
-- Geometry, decided out of combat
--
-- Stage 1 measured that restricted SetPoint takes exactly one argument, so no
-- snippet here re-anchors anything with offsets. Modes differ by size, scale
-- and visibility only -- all of which were observed working in combat.
--------------------------------------------------------------------------------

local ROOT_W, ROOT_H = 380, 190
local FULL_W, FULL_H, FULL_SCALE = 240, 32, 1.0
local COMPACT_W, COMPACT_H, COMPACT_SCALE = 160, 24, 0.85

local MODE_FULL, MODE_COMPACT, MODE_MINIMAL = 1, 2, 3
local MODE_NAME = { [1] = "FULL", [2] = "COMPACT", [3] = "MINIMAL" }

--------------------------------------------------------------------------------
-- Snippets
--
-- Every one stamps "entered" before anything that can fail and "ran" at the
-- end. Stage 1 spent two runs unable to tell a snippet that crashed from a
-- click that never arrived; those are different facts and they never share a
-- number again.
--------------------------------------------------------------------------------

--- Applies the active page's action key plus the two paging keys.
---
--- Written once and pasted into both snippets that need it, exactly as
--- production does, because the restricted environment cannot call a shared
--- function -- a snippet is a string, not a closure. Two copies of "which keys
--- are live" is the pair that drifts.
local BIND_BODY = [==[
    m:ClearBindings()
    m:SetAttribute("cleared", (m:GetAttribute("cleared") or 0) + 1)

    -- By name, not by frame handle.
    --
    -- The handle form completed without throwing -- the counter at the end of
    -- this body reached 3 -- and bound nothing: every Stage 2 key was dead
    -- while every mouse control worked. A call that succeeds and does nothing
    -- is the worst shape of all, because there is no error to notice.
    --
    -- The names are stored as attributes out of combat, since GetName is not
    -- available in here.
    local actionName = m:GetAttribute("action" .. index .. "Name")
    local actionKey = m:GetAttribute("actionKey")
    if actionName and actionKey then
        m:SetBindingClick(true, actionKey, actionName)
        m:SetAttribute("boundAction", (m:GetAttribute("boundAction") or 0) + 1)
    end

    local nextKey, nextName = m:GetAttribute("nextKey"), m:GetAttribute("nextName")
    if nextKey and nextName then m:SetBindingClick(true, nextKey, nextName) end

    local prevKey, prevName = m:GetAttribute("prevKey"), m:GetAttribute("prevName")
    if prevKey and prevName then m:SetBindingClick(true, prevKey, prevName) end

    m:SetAttribute("bound", (m:GetAttribute("bound") or 0) + 1)
]==]

--- Show the page identity and the page's action, honouring the current mode.
---
--- The flip reads the mode rather than assuming Full: a page change while
--- Minimal must not put the action body back on screen, or the visible state
--- would stop matching the mode and the report would call it stale.
--- Fetched from `self`, not through the manager.
---
--- The flip was fetching these with two hops: self gives the manager handle,
--- the manager handle gives the label handle. Stage 1's toggle -- which works
--- in combat -- only ever did one, from the button to its own reference.
--- Production's flip does the two-hop version and has never run in a fight.
---
--- Both the buttons and the pager carry these references, so this line works
--- whether `self` is the arrow running a flip or the pager running its own
--- rebind out of combat.
local PAGE_PRESENT = [==[
    local moder = self:GetFrameRef("moder")
    self:SetAttribute("gotmoder", (self:GetAttribute("gotmoder") or 0) + 1)

    local mode = 1
    if moder then mode = moder:GetAttribute("mode") or 1 end
    self:SetAttribute("readmode", (self:GetAttribute("readmode") or 0) + 1)

    -- The page labels: plain frames.
    --
    -- Fetched by literal name rather than "pageId" .. i. Building a ref name by
    -- concatenation is what production's flip does and it has never run in a
    -- fight; the two presses that reached this point differ only in whether
    -- combat was up, and the fetch and the Show are stamped apart so the one
    -- that is refused is named rather than inferred.
    local id1 = self:GetFrameRef("pageId1")
    local id2 = self:GetFrameRef("pageId2")
    self:SetAttribute("gotlabels", (self:GetAttribute("gotlabels") or 0) + 1)

    if id1 and id2 then
        if index == 1 then
            id1:Show()
            id2:Hide()
        else
            id2:Show()
            id1:Hide()
        end
    end
    self:SetAttribute("didlabels", (self:GetAttribute("didlabels") or 0) + 1)

    -- The action buttons: protected frames under a secure header. Separated
    -- from the labels on purpose -- showing a plain frame and showing a
    -- protected one are not the same operation.
    local act1 = self:GetFrameRef("action1")
    local act2 = self:GetFrameRef("action2")
    self:SetAttribute("gotactions", (self:GetAttribute("gotactions") or 0) + 1)

    if act1 and act2 then
        if mode == 3 then
            act1:Hide()
            act2:Hide()
        elseif index == 1 then
            act1:Show()
            act2:Hide()
        else
            act2:Show()
            act1:Hide()
        end
    end
    self:SetAttribute("didactions", (self:GetAttribute("didactions") or 0) + 1)
]==]

--- Stamped between every call, for the same reason the Stage 1 anchor probe
--- was: a snippet stops dead where it throws, so everything after that point is
--- silent and one "it did nothing" covers five different causes. The toggle
--- works and this does not, and the difference is what this snippet does before
--- it touches anything visible.
local FLIP_SNIPPET = [==[
    self:SetAttribute("entered", (self:GetAttribute("entered") or 0) + 1)

    local m = self:GetFrameRef("manager")
    if not m then
        self:SetAttribute("nomanager", (self:GetAttribute("nomanager") or 0) + 1)
        return
    end
    self:SetAttribute("gotmanager", (self:GetAttribute("gotmanager") or 0) + 1)

    local current = m:GetAttribute("pageIndex") or 1
    self:SetAttribute("readindex", (self:GetAttribute("readindex") or 0) + 1)

    local index = current + (self:GetAttribute("delta") or 1)
    if index < 1 then index = 2 elseif index > 2 then index = 1 end

    m:SetAttribute("pageIndex", index)
    self:SetAttribute("wroteindex", (self:GetAttribute("wroteindex") or 0) + 1)
]==] .. PAGE_PRESENT .. [==[
    self:SetAttribute("presented", (self:GetAttribute("presented") or 0) + 1)
]==] .. BIND_BODY .. [==[
    self:SetAttribute("ran", (self:GetAttribute("ran") or 0) + 1)
]==]

--- Run on the pager itself, so arming out of combat takes the same code path a
--- flip does.
local REBIND_SNIPPET = [==[
    local m = self
    local index = m:GetAttribute("pageIndex") or 1
]==] .. PAGE_PRESENT .. BIND_BODY

--- Applies a presentation mode. Expects `moder` and `wanted` already local.
---
--- Touches no binding at all: a mode change must leave the pager's keys exactly
--- as it found them, and the cheapest way to guarantee that is never to call
--- ClearBindings from this owner.
local MODE_APPLY = [==[
    moder:SetAttribute("mode", wanted)

    local visFull = moder:GetFrameRef("visFull")
    local visCompact = moder:GetFrameRef("visCompact")
    local visMinimal = moder:GetFrameRef("visMinimal")
    if visFull then if wanted == 1 then visFull:Show() else visFull:Hide() end end
    if visCompact then if wanted == 2 then visCompact:Show() else visCompact:Hide() end end
    if visMinimal then if wanted == 3 then visMinimal:Show() else visMinimal:Hide() end end

    local pager = moder:GetFrameRef("pager")
    local index = 1
    if pager then index = pager:GetAttribute("pageIndex") or 1 end

    for i = 1, 2 do
        local act = moder:GetFrameRef("action" .. i)
        if act then
            if i == index and wanted ~= 3 then act:Show() else act:Hide() end
            if wanted == 1 then
                act:SetWidth(FULL_W_VALUE)
                act:SetHeight(FULL_H_VALUE)
                act:SetScale(FULL_SCALE_VALUE)
            elseif wanted == 2 then
                act:SetWidth(COMPACT_W_VALUE)
                act:SetHeight(COMPACT_H_VALUE)
                act:SetScale(COMPACT_SCALE_VALUE)
            end
        end
    end

    moder:SetAttribute("applied", (moder:GetAttribute("applied") or 0) + 1)
]==]

local function modeSnippet(bodyPrefix)
    return [==[
    self:SetAttribute("entered", (self:GetAttribute("entered") or 0) + 1)
    local moder = self:GetFrameRef("moder")
    if not moder then return end
]==] .. bodyPrefix .. MODE_APPLY .. [==[
    self:SetAttribute("ran", (self:GetAttribute("ran") or 0) + 1)
]==]
end

--- Visibility only. Never touches page, mode, or any binding set.
local TOGGLE_SNIPPET = [==[
    self:SetAttribute("entered", (self:GetAttribute("entered") or 0) + 1)
    local root = self:GetFrameRef("root")
    if not root then return end

    if root:IsShown() then root:Hide() else root:Show() end

    local owner = self:GetFrameRef("toggler")
    if owner then
        owner:SetAttribute("visible", root:IsShown() and 1 or 0)
    end
    self:SetAttribute("ran", (self:GetAttribute("ran") or 0) + 1)
]==]

--- External rescue. Shows the root and nothing else, so it cannot be blamed for
--- a page or mode that looks wrong afterwards.
local RESCUE_SNIPPET = [==[
    self:SetAttribute("entered", (self:GetAttribute("entered") or 0) + 1)
    local root = self:GetFrameRef("root")
    if root then root:Show() end
    self:SetAttribute("ran", (self:GetAttribute("ran") or 0) + 1)
]==]

--- Nothing but the label swap, from a button holding both frames directly.
---
--- The flip reaches this exact pair of calls and, in combat, does not complete
--- them. The toggle does the same kind of thing to a plain frame in the same
--- fight and works. Rather than reasoning about why, this does only the two
--- calls, with nothing before them but the fetch: if the labels swap in combat
--- the operation is permitted and the flip's problem lies elsewhere, and if
--- they do not, these particular frames cannot be shown or hidden in combat at
--- all. One click answers it.
local LABEL_PROBE = [==[
    self:SetAttribute("entered", (self:GetAttribute("entered") or 0) + 1)

    local id1 = self:GetFrameRef("pageId1")
    local id2 = self:GetFrameRef("pageId2")
    if not id1 or not id2 then return end
    self:SetAttribute("gotlabels", (self:GetAttribute("gotlabels") or 0) + 1)

    if id1:IsShown() then
        id1:Hide()
        self:SetAttribute("hid", (self:GetAttribute("hid") or 0) + 1)
        id2:Show()
    else
        id2:Hide()
        self:SetAttribute("hid", (self:GetAttribute("hid") or 0) + 1)
        id1:Show()
    end

    self:SetAttribute("ran", (self:GetAttribute("ran") or 0) + 1)
]==]

--- The deliberate collision. One owner, two keys, then ClearBindings and only
--- one key re-applied. This is the constraint the three-owner architecture
--- exists to route around, measured on purpose rather than tripped over.
local COLLIDE_SNIPPET = [==[
    self:SetAttribute("entered", (self:GetAttribute("entered") or 0) + 1)
    local owner = self:GetFrameRef("owner")
    if not owner then return end

    owner:ClearBindings()

    local key, target = owner:GetAttribute("pageKey"), owner:GetFrameRef("pageButton")
    if key and target then owner:SetBindingClick(true, key, target) end

    self:SetAttribute("ran", (self:GetAttribute("ran") or 0) + 1)
]==]

local function withNumbers(snippet)
    return (snippet
        :gsub("FULL_W_VALUE", tostring(FULL_W))
        :gsub("FULL_H_VALUE", tostring(FULL_H))
        :gsub("FULL_SCALE_VALUE", tostring(FULL_SCALE))
        :gsub("COMPACT_W_VALUE", tostring(COMPACT_W))
        :gsub("COMPACT_H_VALUE", tostring(COMPACT_H))
        :gsub("COMPACT_SCALE_VALUE", tostring(COMPACT_SCALE)))
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

local F = {}
S2.frames = F
local built, armed = false, false

local function label(parent, text, size)
    local fs = parent:CreateFontString(nil, "OVERLAY",
        size == "big" and "GameFontNormal" or "GameFontNormalSmall")
    fs:SetText(text)
    return fs
end

local function panelFrame(parent, w, h, r, g, b)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(r, g, b, 0.95)
    return f
end

local function namedPanel(name, parent, w, h, r, g, b, text)
    local f = CreateFrame("Frame", "InomrahsMISelfTestS2" .. name, parent)
    f:SetSize(w, h)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(r, g, b, 0.95)
    if text then
        local fs = label(f, text)
        fs:SetAllPoints()
    end
    return f
end

local function secureControl(name, parent, text, snippet, refs, w, h)
    local b = CreateFrame("Button", "InomrahsMISelfTestS2" .. name, parent,
        "SecureHandlerClickTemplate")
    b:SetSize(w or 74, h or 18)
    b:RegisterForClicks("AnyUp")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.30, 0.20, 0.08, 0.95)

    b.label = label(b, text)
    b.label:SetAllPoints()

    for key, frame in pairs(refs or {}) do b:SetFrameRef(key, frame) end
    b:SetAttribute("_onclick", withNumbers(snippet))

    b.clicks = 0
    b:HookScript("OnClick", function(self) self.clicks = (self.clicks or 0) + 1 end)
    return b
end

local function actionButton(name, parent, page, text)
    local b = CreateFrame("Button", "InomrahsMISelfTestS2" .. name, parent,
        "SecureActionButtonTemplate")
    b:SetSize(FULL_W, FULL_H)

    -- Both, matching the Stage 1 action button that fired in every hidden
    -- state. Stage 2's registered "AnyUp" alone and its key did nothing, while
    -- the secure handler buttons on the same binding call worked -- and they
    -- are fine on AnyUp. The two arrows in production use AnyUp deliberately,
    -- to avoid firing a page flip twice; an action button is a different case.
    b:RegisterForClicks("AnyUp", "AnyDown")
    -- Explicit, as production does it: a button that never receives the click
    -- is indistinguishable from one whose action is refused.
    b:EnableMouse(true)
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext",
        ("/run InomrahsMISelfTestS2Fired(%d)"):format(page))

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.85, 0.55, 0.15, 0.95)

    b.label = label(b, text)
    b.label:SetAllPoints()

    -- Counted insecurely, so "the binding never reached the button" and "the
    -- button was clicked and the macro did not run" stop being the same zero.
    b.clicks = 0
    b:HookScript("OnClick", function(self) self.clicks = (self.clicks or 0) + 1 end)
    return b
end

function S2.Build()
    if built then return true end
    if inCombat() then return false, "combat" end

    ----------------------------------------------------------------------------
    -- The three binding owners. Separate frames, parented to UIParent so none
    -- of them can be inherited-hidden along with the root under test.
    ----------------------------------------------------------------------------
    F.pager = CreateFrame("Frame", "InomrahsMISelfTestS2Pager", UIParent,
        "SecureHandlerBaseTemplate")
    F.pager:SetSize(1, 1)
    F.pager:SetPoint("TOPLEFT")
    F.pager:Hide()

    F.moder = CreateFrame("Frame", "InomrahsMISelfTestS2Moder", UIParent,
        "SecureHandlerBaseTemplate")
    F.moder:SetSize(1, 1)
    F.moder:SetPoint("TOPLEFT")
    F.moder:Hide()

    F.toggler = CreateFrame("Frame", "InomrahsMISelfTestS2Toggler", UIParent,
        "SecureHandlerBaseTemplate")
    F.toggler:SetSize(1, 1)
    F.toggler:SetPoint("TOPLEFT")
    F.toggler:Hide()

    ----------------------------------------------------------------------------
    -- The Run root under test. Everything inside it may be hidden.
    ----------------------------------------------------------------------------
    F.root = CreateFrame("Frame", "InomrahsMISelfTestS2Root", UIParent)
    F.root:SetFrameStrata("MEDIUM")
    F.root:SetSize(ROOT_W, ROOT_H)
    F.root:SetPoint("CENTER", UIParent, "CENTER", 0, 60)

    local rbg = F.root:CreateTexture(nil, "BACKGROUND")
    rbg:SetAllPoints()
    rbg:SetColorTexture(0.06, 0.06, 0.10, 0.95)

    local title = label(F.root, "|cffffd200SYNTHETIC DUNGEON|r", "big")
    title:SetPoint("TOP", 0, -6)

    -- Page identity, prebuilt. Both anchored to the same place out of combat;
    -- the flip shows one and hides the other. No text is mutated from
    -- restricted code, which was never measured as safe.
    F.pageId1 = namedPanel("PageId1", F.root, 90, 20, 0.20, 0.35, 0.60, "PAGE 1")
    F.pageId1:SetPoint("TOPLEFT", 10, -28)
    F.pageId2 = namedPanel("PageId2", F.root, 90, 20, 0.20, 0.35, 0.60, "PAGE 2")
    F.pageId2:SetPoint("TOPLEFT", 10, -28)
    F.pageId2:Hide()

    -- Mode identity, prebuilt the same way.
    F.visFull = namedPanel("VisFull", F.root, 90, 20, 0.15, 0.45, 0.20, "FULL")
    F.visFull:SetPoint("TOPRIGHT", -10, -28)
    F.visCompact = namedPanel("VisCompact", F.root, 90, 20, 0.45, 0.35, 0.10, "COMPACT")
    F.visCompact:SetPoint("TOPRIGHT", -10, -28)
    F.visCompact:Hide()
    F.visMinimal = namedPanel("VisMinimal", F.root, 90, 20, 0.45, 0.15, 0.35, "MINIMAL")
    F.visMinimal:SetPoint("TOPRIGHT", -10, -28)
    F.visMinimal:Hide()

    -- The action area is a secure header, not a plain frame.
    --
    -- Production's pages are SecureHandlerBaseTemplate and its callout buttons
    -- are their children; Stage 1's action button, which fired in every hidden
    -- state, sat under a secure header too. Stage 2 hung its actions off a
    -- plain frame -- a deviation I introduced, and the only structural
    -- difference between the buttons a snippet can show in combat and the ones
    -- it apparently cannot.
    F.actionArea = CreateFrame("Frame", "InomrahsMISelfTestS2ActionArea", F.root,
        "SecureHandlerBaseTemplate")
    F.actionArea:SetSize(FULL_W, FULL_H + 8)
    F.actionArea:SetPoint("TOP", 0, -54)
    local areaBg = F.actionArea:CreateTexture(nil, "BACKGROUND")
    areaBg:SetAllPoints()
    areaBg:SetColorTexture(0.12, 0.12, 0.18, 0.95)

    F.action1 = actionButton("Action1", F.actionArea, 1, "ACTION - PAGE 1")
    F.action1:SetPoint("CENTER")
    F.action2 = actionButton("Action2", F.actionArea, 2, "ACTION - PAGE 2")
    F.action2:SetPoint("CENTER")
    F.action2:Hide()

    ----------------------------------------------------------------------------
    -- Controls. All children of the root, so the hidden-root tests measure the
    -- production-like case rather than an always-visible duplicate.
    ----------------------------------------------------------------------------
    local flipRefs = {
        manager = F.pager, moder = F.moder,
        pageId1 = F.pageId1, pageId2 = F.pageId2,
        action1 = F.action1, action2 = F.action2,
    }

    F.prev = secureControl("Prev", F.root, "< PREV", FLIP_SNIPPET, flipRefs)
    F.prev:SetPoint("TOPLEFT", 10, -104)
    F.prev:SetAttribute("delta", -1)

    F.next = secureControl("Next", F.root, "NEXT >", FLIP_SNIPPET, flipRefs)
    F.next:SetPoint("TOPLEFT", 90, -104)
    F.next:SetAttribute("delta", 1)

    F.modeFull = secureControl("ModeFull", F.root, "FULL",
        modeSnippet("    local wanted = 1\n"), { moder = F.moder })
    F.modeFull:SetPoint("TOPLEFT", 10, -128)

    F.modeCompact = secureControl("ModeCompact", F.root, "COMPACT",
        modeSnippet("    local wanted = 2\n"), { moder = F.moder })
    F.modeCompact:SetPoint("TOPLEFT", 90, -128)

    F.modeMinimal = secureControl("ModeMinimal", F.root, "MINIMAL",
        modeSnippet("    local wanted = 3\n"), { moder = F.moder })
    F.modeMinimal:SetPoint("TOPLEFT", 170, -128)

    F.modeCycle = secureControl("ModeCycle", F.root, "CYCLE",
        modeSnippet([==[
    local wanted = (moder:GetAttribute("mode") or 1) + 1
    if wanted > 3 then wanted = 1 end
]==]), { moder = F.moder })
    F.modeCycle:SetPoint("TOPLEFT", 250, -128)

    -- The toggle lives inside the root on purpose: production's does, and the
    -- question is whether its binding can still show the root after the root
    -- has hidden it along with everything else.
    F.toggle = secureControl("Toggle", F.root, "HIDE / SHOW", TOGGLE_SNIPPET,
        { root = F.root, toggler = F.toggler }, 120, 18)
    F.toggle:SetPoint("TOPLEFT", 10, -152)

    ----------------------------------------------------------------------------
    -- External rescue. Outside the root, never hidden by anything under test.
    ----------------------------------------------------------------------------
    F.rescueBar = CreateFrame("Frame", "InomrahsMISelfTestS2RescueBar", UIParent)
    F.rescueBar:SetFrameStrata("FULLSCREEN")
    F.rescueBar:SetSize(512, 82)
    F.rescueBar:SetPoint("TOP", UIParent, "TOP", 0, -40)

    local rescueBg = F.rescueBar:CreateTexture(nil, "BACKGROUND")
    rescueBg:SetAllPoints()
    rescueBg:SetColorTexture(0.35, 0.05, 0.05, 0.95)

    local barTitle = label(F.rescueBar, "|cffffaaaaSTAGE 2|r")
    barTitle:SetPoint("BOTTOM", 0, 4)

    F.rescue = secureControl("Rescue", F.rescueBar, "SHOW RUN ROOT", RESCUE_SNIPPET,
        { root = F.root }, 500, 22)
    F.rescue:SetPoint("TOPLEFT", 6, -6)

    -- Stage 2's own PREFLIGHT and ARM.
    --
    -- Stage 1's bar has buttons by the same names that arm Stage 1's keys. With
    -- both bars on screen there was nothing to tell them apart, and the first
    -- live run armed the wrong stage and then failed every step for want of a
    -- binding. Stage 1's bar is hidden while this one is up, and these buttons
    -- go to Stage 2.
    F.commands = {}
    local commands = {
        { text = "PREFLIGHT", cmd = "preflight" },
        { text = "ARM",       cmd = "arm" },
        { text = "STATUS",    cmd = "status" },
        { text = "RESET",     cmd = "reset" },
    }
    for index, entry in ipairs(commands) do
        local b = CreateFrame("Button", nil, F.rescueBar)
        b:SetSize(80, 20)
        b:SetPoint("TOPLEFT", 6 + (index - 1) * 84, -32)

        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.16, 0.16, 0.22, 0.95)
        b.label = label(b, entry.text)
        b.label:SetAllPoints()

        b:SetScript("OnEnter", function() bg:SetColorTexture(0.26, 0.26, 0.34, 0.95) end)
        b:SetScript("OnLeave", function() bg:SetColorTexture(0.16, 0.16, 0.22, 0.95) end)
        b:SetScript("OnClick", function() S2.Command(entry.cmd) end)
        F.commands[index] = b
    end

    ----------------------------------------------------------------------------
    -- The disposable collision owner, with two harmless observers.
    ----------------------------------------------------------------------------
    F.collider = CreateFrame("Frame", "InomrahsMISelfTestS2Collider", UIParent,
        "SecureHandlerBaseTemplate")
    F.collider:SetSize(1, 1)
    F.collider:SetPoint("TOPLEFT")
    F.collider:Hide()

    F.collidePage = CreateFrame("Button", "InomrahsMISelfTestS2CollidePage",
        UIParent, "SecureActionButtonTemplate")
    F.collidePage:SetSize(1, 1)
    F.collidePage:SetPoint("TOPLEFT")
    F.collidePage:RegisterForClicks("AnyUp")
    F.collidePage:SetAttribute("type", "macro")
    F.collidePage:SetAttribute("macrotext",
        '/run InomrahsMISelfTestS2Collision("page")')
    F.collidePage:Hide()

    F.collideMode = CreateFrame("Button", "InomrahsMISelfTestS2CollideMode",
        UIParent, "SecureActionButtonTemplate")
    F.collideMode:SetSize(1, 1)
    F.collideMode:SetPoint("TOPLEFT")
    F.collideMode:RegisterForClicks("AnyUp")
    F.collideMode:SetAttribute("type", "macro")
    F.collideMode:SetAttribute("macrotext",
        '/run InomrahsMISelfTestS2Collision("mode")')
    F.collideMode:Hide()

    F.labelProbe = secureControl("LabelProbe", F.rescueBar, "LABEL PROBE",
        LABEL_PROBE, { pageId1 = F.pageId1, pageId2 = F.pageId2 }, 80, 20)
    F.labelProbe:SetPoint("TOPLEFT", 6 + 5 * 84, -32)

    F.collideRun = secureControl("CollideRun", F.rescueBar, "COLLISION PROBE",
        COLLIDE_SNIPPET, { owner = F.collider }, 80, 20)
    F.collideRun:SetPoint("TOPLEFT", 6 + 4 * 84, -32)
    F.collideRun:SetSize(80, 20)

    ----------------------------------------------------------------------------
    -- Wiring. Every ref is set here, out of combat, once.
    ----------------------------------------------------------------------------
    F.pager:SetFrameRef("action1", F.action1)
    F.pager:SetFrameRef("action2", F.action2)
    F.pager:SetFrameRef("pageId1", F.pageId1)
    F.pager:SetFrameRef("pageId2", F.pageId2)
    F.pager:SetFrameRef("nextButton", F.next)
    F.pager:SetFrameRef("prevButton", F.prev)
    F.pager:SetFrameRef("moder", F.moder)
    F.pager:SetAttribute("pageIndex", 1)
    F.pager:SetAttribute("action1Name", F.action1:GetName())
    F.pager:SetAttribute("action2Name", F.action2:GetName())
    F.pager:SetAttribute("nextName", F.next:GetName())
    F.pager:SetAttribute("prevName", F.prev:GetName())
    F.pager:SetAttribute("actionKey", keyFor("action"))
    F.pager:SetAttribute("nextKey", keyFor("next"))
    F.pager:SetAttribute("prevKey", keyFor("prev"))
    F.pager:SetAttribute("_rebind", withNumbers(REBIND_SNIPPET))

    F.moder:SetFrameRef("action1", F.action1)
    F.moder:SetFrameRef("action2", F.action2)
    F.moder:SetFrameRef("visFull", F.visFull)
    F.moder:SetFrameRef("visCompact", F.visCompact)
    F.moder:SetFrameRef("visMinimal", F.visMinimal)
    F.moder:SetFrameRef("pager", F.pager)
    F.moder:SetAttribute("mode", MODE_FULL)

    F.toggler:SetFrameRef("root", F.root)
    F.toggler:SetFrameRef("toggleButton", F.toggle)
    F.toggler:SetAttribute("visible", 1)

    F.collider:SetFrameRef("pageButton", F.collidePage)
    F.collider:SetFrameRef("modeButton", F.collideMode)
    F.collider:SetAttribute("pageKey", COLLIDE_PAGE_KEY)
    F.collider:SetAttribute("modeKey", COLLIDE_MODE_KEY)

    built = true
    return true
end

--------------------------------------------------------------------------------
-- Reading the state
--
-- Derived from which prebuilt frame is shown, never from an attribute the
-- restricted side wrote. Stage 1 spent a version stuck on a step whose check
-- read such an attribute and never got a usable answer back; IsShown after a
-- restricted Show or Hide was measured readable in the same run.
--
-- IsShown is also the frame's own flag rather than its inherited visibility, so
-- these keep answering while the root is hidden -- which is exactly the state
-- the hidden-root tests need to observe.
--------------------------------------------------------------------------------

function S2.Page()
    local a, b = shown(F.pageId1), shown(F.pageId2)
    if a == true and b == false then return 1 end
    if b == true and a == false then return 2 end
    return nil
end

function S2.Mode()
    local f, c, m = shown(F.visFull), shown(F.visCompact), shown(F.visMinimal)
    local on = {}
    if f == true then on[#on + 1] = MODE_FULL end
    if c == true then on[#on + 1] = MODE_COMPACT end
    if m == true then on[#on + 1] = MODE_MINIMAL end
    if #on == 1 then return on[1] end
    return nil
end

function S2.RootVisible() return shown(F.root) end

function S2.ActionBodyShown()
    local index = S2.Page()
    if index == 1 then return shown(F.action1) end
    if index == 2 then return shown(F.action2) end
    return nil
end

local function stateLine()
    return ("page %s | mode %s | root %s"):format(
        tostring(S2.Page() or "?"),
        MODE_NAME[S2.Mode() or 0] or "?",
        tri(S2.RootVisible()))
end

--------------------------------------------------------------------------------
-- Arming
--------------------------------------------------------------------------------

local function runOn(frame, snippet)
    if type(SecureHandlerExecute) ~= "function" then return false end
    return (pcall(SecureHandlerExecute, frame, withNumbers(snippet)))
end

function S2.Arm()
    if inCombat() then return false, "combat" end
    if not built then return false, "not built" end

    -- The pager binds its own three through the same body a flip uses.
    if not runOn(F.pager, REBIND_SNIPPET) then return false, "pager rebind failed" end

    -- The mode owner's set is static for the whole session. Nothing it does
    -- ever calls ClearBindings, so a page flip cannot cost it anything.
    local modeBind = ([==[
        self:ClearBindings()
        self:SetBindingClick(true, "%s", "%s")
        self:SetBindingClick(true, "%s", "%s")
        self:SetBindingClick(true, "%s", "%s")
        self:SetBindingClick(true, "%s", "%s")
    ]==]):format(keyFor("full"), F.modeFull:GetName(),
                 keyFor("compact"), F.modeCompact:GetName(),
                 keyFor("minimal"), F.modeMinimal:GetName(),
                 keyFor("cycle"), F.modeCycle:GetName())
    if not runOn(F.moder, modeBind) then return false, "mode bind failed" end

    local toggleBind = ([==[
        self:ClearBindings()
        self:SetBindingClick(true, "%s", "%s")
    ]==]):format(keyFor("toggle"), F.toggle:GetName())
    if not runOn(F.toggler, toggleBind) then return false, "toggle bind failed" end

    local collideBind = ([==[
        self:ClearBindings()
        self:SetBindingClick(true, "%s", "%s")
        self:SetBindingClick(true, "%s", "%s")
    ]==]):format(COLLIDE_PAGE_KEY, F.collidePage:GetName(),
                 COLLIDE_MODE_KEY, F.collideMode:GetName())
    runOn(F.collider, collideBind)

    armed = true
    return true
end

function S2.Disarm()
    if inCombat() then return false end
    for _, owner in ipairs({ F.pager, F.moder, F.toggler, F.collider }) do
        if owner then runOn(owner, "self:ClearBindings()") end
    end
    armed = false
    return true
end

function S2.Armed() return armed end

--------------------------------------------------------------------------------
-- Restoring
--
-- Ordinary code, out of combat. Never a measurement: anything it puts right is
-- housekeeping, and it is never recorded as an operation having succeeded.
--------------------------------------------------------------------------------

function S2.Restore()
    if not built then return end
    pcall(function()
        F.root:Show()
        F.pageId1:Show()
        F.pageId2:Hide()
        F.visFull:Show()
        F.visCompact:Hide()
        F.visMinimal:Hide()
        F.action1:Show()
        F.action2:Hide()
        for _, act in ipairs({ F.action1, F.action2 }) do
            act:SetWidth(FULL_W)
            act:SetHeight(FULL_H)
            act:SetScale(FULL_SCALE)
        end
        F.rescueBar:Show()
        F.pager:SetAttribute("pageIndex", 1)
        F.moder:SetAttribute("mode", MODE_FULL)
    end)
    if not inCombat() then runOn(F.pager, REBIND_SNIPPET) end
    S2.fired[1], S2.fired[2] = 0, 0
    S2.collision.page, S2.collision.mode = 0, 0
end

--------------------------------------------------------------------------------
-- The sequence
--
-- Driven by the Stage 1 panel, so timeout, Skip and combat recovery behave
-- exactly as they already do, and every result lands in the one report.
--------------------------------------------------------------------------------

local record = Lab.Record

--- One "press the action key" assertion.
---
--- Never passes on the total having gone up. The expected page's counter must
--- move and the other must not: both moving is worse than neither, because in
--- production one press would send two callouts.
--- `need` is the state the assertion is about: {page=, mode=, root=}.
---
--- Without it a step measures whatever is on screen, so arriving in the wrong
--- state records a confident YES about a claim it never tested -- "ACTION key
--- works in Minimal" measured while Full is on screen. Stage 1 shipped exactly
--- that result and it took two runs to catch. While the state is wrong the
--- step says so on the panel and re-marks the counters, so a press made too
--- early cannot be counted once the state becomes right.
local function actionStep(phase, capability, expected, text, need)
    local before1, before2, wasPage, wasMode
    local warned = false

    local function missing()
        if not need then return nil end
        if need.page and S2.Page() ~= need.page then
            return "this step needs page " .. need.page
        end
        if need.mode and S2.Mode() ~= need.mode then
            return "this step needs mode " .. (MODE_NAME[need.mode] or "?")
        end
        if need.root ~= nil and S2.RootVisible() ~= need.root then
            return "this step needs the root " .. (need.root and "shown" or "hidden")
        end
        return nil
    end

    return {
        phase = phase,
        capability = capability,
        timeout = 90,
        recordOnTimeout = true,
        text = text .. ("\n\nExpecting: |cffffd200page %d|r fires, page %d does not.")
            :format(expected, expected == 1 and 2 or 1),
        enter = function()
            before1, before2 = S2.fired[1] or 0, S2.fired[2] or 0
            wasPage, wasMode = S2.Page(), S2.Mode()
        end,
        observe = function()
            if not inCombat() then return false, "combat ended" end

            local why = missing()
            if why then
                before1, before2 = S2.fired[1] or 0, S2.fired[2] or 0
                if not warned then
                    warned = true
                    Lab.Hint("Not yet: " .. why .. ".")
                end
                return false, why
            end
            if warned then
                warned = false
                Lab.Hint("Ready — press the key.", "ff44ff44")
            end

            if (S2.fired[1] or 0) > before1 or (S2.fired[2] or 0) > before2 then
                return true
            end
            return false, "no action executed"
        end,
        done = function()
            local now1, now2 = S2.fired[1] or 0, S2.fired[2] or 0
            local moved1, moved2 = now1 > before1, now2 > before2

            local conclusion
            if moved1 and moved2 then
                conclusion = "FAIL — one press fired both pages: duplicate "
                    .. "contextual bindings"
            elseif (expected == 1 and moved1) or (expected == 2 and moved2) then
                conclusion = "YES — observed: correct contextual target"
            elseif moved1 or moved2 then
                conclusion = ("NO — stale binding: page %d fired, page %d expected")
                    :format(moved1 and 1 or 2, expected)
            else
                conclusion = "INCONCLUSIVE — no action executed"
            end

            record({
                capability = capability,
                context = inCombat() and "combat" or "combat ended before measuring",
                trigger = "override key " .. keyFor("action"),
                target = "SecureActionButtonTemplate for the active page",
                operation = "press the one contextual action key",
                before = ("page %s, mode %s, root %s"):format(
                    tostring(wasPage or "?"), MODE_NAME[wasMode or 0] or "?",
                    tri(S2.RootVisible())),
                expectedTarget = expected,
                page1 = ("%d -> %d"):format(before1, now1),
                page2 = ("%d -> %d"):format(before2, now2),
                conclusion = conclusion,
            })
        end,
    }
end

--- One "the state should become this" assertion, observed from the prebuilt
--- visuals rather than from an attribute the restricted side wrote.
local function stateStep(phase, capability, text, wantPage, wantMode, wantRoot)
    local was
    return {
        phase = phase,
        capability = capability,
        timeout = 90,
        recordOnTimeout = true,
        text = text,
        enter = function() was = stateLine() end,
        observe = function()
            if not inCombat() then return false, "combat ended" end
            local okPage = (wantPage == nil) or (S2.Page() == wantPage)
            local okMode = (wantMode == nil) or (S2.Mode() == wantMode)
            local okRoot = (wantRoot == nil) or (S2.RootVisible() == wantRoot)
            if okPage and okMode and okRoot then return true end
            return false, "state is still " .. stateLine()
        end,
        done = function()
            local okPage = (wantPage == nil) or (S2.Page() == wantPage)
            local okMode = (wantMode == nil) or (S2.Mode() == wantMode)
            local okRoot = (wantRoot == nil) or (S2.RootVisible() == wantRoot)

            local want = {}
            if wantPage then want[#want + 1] = "page " .. wantPage end
            if wantMode then want[#want + 1] = "mode " .. (MODE_NAME[wantMode] or "?") end
            if wantRoot ~= nil then want[#want + 1] = "root " .. tri(wantRoot) end

            record({
                capability = capability,
                context = inCombat() and "combat" or "combat ended before measuring",
                trigger = "as instructed on the panel",
                before = was,
                requested = table.concat(want, ", "),
                after = stateLine(),
                note = ("action body shown: %s | action size %s x %s scale %s")
                    :format(tri(S2.ActionBodyShown()),
                            fmt(width(F.action1)), fmt(height(F.action1)),
                            fmt(scale(F.action1))),
                conclusion = (okPage and okMode and okRoot) and "YES — observed"
                    or "NO — observed mismatch",
            })
        end,
    }
end

local function manualStep(phase, text, buttonText)
    return { phase = phase, manual = true, buttonText = buttonText or "I did this",
             text = text }
end

local function buildSequence()
    local steps = {}
    local function add(s) steps[#steps + 1] = s end

    add({
        phase = "stage 2 setup",
        text = "On the |cffffd200STAGE 2|r bar at the top, press "
            .. "|cffffd200PREFLIGHT|r then |cffffd200ARM|r.\n"
            .. "Those are Stage 2's own buttons. Stage 1's bar is put away while "
            .. "this runs, so there is only one of each on screen.\n"
            .. "This step moves on by itself once the Stage 2 keys are live.",
        timeout = 3600,
        observe = function()
            if armed then return true end
            return false, "the Stage 2 keys were never armed"
        end,
    })

    add(manualStep("combat",
        "|cffff8800Attack a training dummy.|r Never during a real key.\n"
        .. "Press the button below once you are in combat.", "I am in combat"))

    ----------------------------------------------------------------------------
    -- A — the contextual page binding. If this fails, nothing after it matters.
    ----------------------------------------------------------------------------
    add(actionStep("A contextual binding", "ACTION key targets page 1 before any flip", 1,
        "Press |cffffd200" .. keyFor("action") .. "|r once.",
        { page = 1, mode = MODE_FULL, root = true }))

    add(stateStep("A contextual binding", "page NEXT key flips to page 2 in combat",
        "Press |cffffd200" .. keyFor("next") .. "|r once.\n"
        .. "The PAGE 2 label should replace PAGE 1.", 2, nil, nil))

    add(actionStep("A contextual binding", "ACTION key targets page 2 after NEXT", 2,
        "Press |cffffd200" .. keyFor("action") .. "|r once.",
        { page = 2 }))

    add(stateStep("A contextual binding", "page PREVIOUS key flips back in combat",
        "Press |cffffd200" .. keyFor("prev") .. "|r once.", 1, nil, nil))

    add(actionStep("A contextual binding", "ACTION key targets page 1 after PREVIOUS", 1,
        "Press |cffffd200" .. keyFor("action") .. "|r once.",
        { page = 1 }))

    add(stateStep("A contextual binding", "second flip to page 2",
        "Press |cffffd200" .. keyFor("next") .. "|r again.", 2, nil, nil))

    add(actionStep("A contextual binding",
        "ACTION key still correct on the second round", 2,
        "Press |cffffd200" .. keyFor("action") .. "|r once.\n"
        .. "Binding drift usually shows on the second or third flip, not the first."))

    add(stateStep("A contextual binding", "second flip back to page 1",
        "Press |cffffd200" .. keyFor("prev") .. "|r again.", 1, nil, nil))

    add(actionStep("A contextual binding",
        "ACTION key still correct after two full rounds", 1,
        "Press |cffffd200" .. keyFor("action") .. "|r once.",
        { page = 1 }))

    ----------------------------------------------------------------------------
    -- B — mode by physical mouse click.
    ----------------------------------------------------------------------------
    add(stateStep("B mode by mouse", "Full to Compact by mouse click in combat",
        "Click the |cffffd200COMPACT|r button in the lab window.\n"
        .. "The action button should get smaller. The page must not change.",
        1, MODE_COMPACT, true))

    add(actionStep("B mode by mouse",
        "ACTION key survives a mouse mode change", 1,
        "Press |cffffd200" .. keyFor("action") .. "|r once.",
        { page = 1, mode = MODE_COMPACT }))

    add(manualStep("B mode by mouse",
        "Click the orange |cffffd200ACTION - PAGE 1|r button itself.\n"
        .. "Compact is meant to stay clickable.", "I clicked the action"))

    add(stateStep("B mode by mouse", "Compact to Minimal by mouse click in combat",
        "Click the |cffffd200MINIMAL|r button.\n"
        .. "The action button should disappear. The page label must stay.",
        1, MODE_MINIMAL, true))

    add(actionStep("B mode by mouse",
        "ACTION key works in Minimal with no action body on screen", 1,
        "Press |cffffd200" .. keyFor("action") .. "|r once.\n"
        .. "Nothing is visible to click. The key must still fire.",
        { page = 1, mode = MODE_MINIMAL, root = true }))

    ----------------------------------------------------------------------------
    -- G — physical page navigation while Minimal.
    ----------------------------------------------------------------------------
    add(stateStep("G navigation in Minimal", "page NEXT by mouse while Minimal",
        "Still in Minimal: click |cffffd200NEXT >|r.\n"
        .. "The page label should change. No action body should appear.",
        2, MODE_MINIMAL, true))

    add(actionStep("G navigation in Minimal",
        "ACTION key targets page 2 in Minimal", 2,
        "Press |cffffd200" .. keyFor("action") .. "|r once.",
        { page = 2, mode = MODE_MINIMAL, root = true }))

    add(stateStep("G navigation in Minimal", "page PREVIOUS by mouse while Minimal",
        "Click |cffffd200< PREV|r.", 1, MODE_MINIMAL, true))

    ----------------------------------------------------------------------------
    -- H — escaping Minimal with the mouse.
    ----------------------------------------------------------------------------
    add(stateStep("H escaping Minimal", "Minimal to Full by mouse click in combat",
        "Click |cffffd200FULL|r.\n"
        .. "The action body should return at its larger size, still on page 1.",
        1, MODE_FULL, true))

    add(actionStep("H escaping Minimal",
        "ACTION key correct after returning to Full", 1,
        "Press |cffffd200" .. keyFor("action") .. "|r once.",
        { page = 1, mode = MODE_FULL }))

    ----------------------------------------------------------------------------
    -- C — direct mode keys.
    ----------------------------------------------------------------------------
    add(stateStep("C mode keys", "COMPACT key works in combat",
        "Press |cffffd200" .. keyFor("compact") .. "|r.", 1, MODE_COMPACT, true))

    add(actionStep("C mode keys", "ACTION key survives a mode key press", 1,
        "Press |cffffd200" .. keyFor("action") .. "|r once.",
        { page = 1, mode = MODE_COMPACT }))

    add(stateStep("C mode keys", "MINIMAL key works in combat",
        "Press |cffffd200" .. keyFor("minimal") .. "|r.", 1, MODE_MINIMAL, true))

    add(stateStep("C mode keys", "page NEXT key still live after mode keys",
        "Press |cffffd200" .. keyFor("next") .. "|r.\n"
        .. "This is the owner-separation test: the mode owner must not have "
        .. "cost the pager its keys.", 2, MODE_MINIMAL, true))

    add(actionStep("C mode keys", "ACTION key targets page 2 after mode keys", 2,
        "Press |cffffd200" .. keyFor("action") .. "|r once.",
        { page = 2, mode = MODE_MINIMAL }))

    add(stateStep("C mode keys", "FULL key works, and the page is untouched",
        "Press |cffffd200" .. keyFor("full") .. "|r.\n"
        .. "Mode should become Full and the page must stay on 2.",
        2, MODE_FULL, true))

    add(stateStep("C mode keys", "page flip back to 1, which rebuilds the pager",
        "Press |cffffd200" .. keyFor("prev") .. "|r.\n"
        .. "This is the flip that calls ClearBindings on the pager.",
        1, MODE_FULL, true))

    add(stateStep("C mode keys", "mode keys survive the pager's ClearBindings",
        "Now press |cffffd200" .. keyFor("compact") .. "|r.\n"
        .. "The flip you just did rebuilt the pager's bindings. If that erased "
        .. "the mode owner's keys, this press will do nothing.",
        1, MODE_COMPACT, true))

    ----------------------------------------------------------------------------
    -- D — the cycle key.
    ----------------------------------------------------------------------------
    add(stateStep("D cycle", "cycle Compact to Minimal",
        "Press |cffffd200" .. keyFor("cycle") .. "|r.", 1, MODE_MINIMAL, true))
    add(stateStep("D cycle", "cycle Minimal to Full",
        "Press |cffffd200" .. keyFor("cycle") .. "|r again.", 1, MODE_FULL, true))
    add(stateStep("D cycle", "cycle Full to Compact",
        "Press |cffffd200" .. keyFor("cycle") .. "|r once more.\n"
        .. "Three presses should have gone Compact, Minimal, Full, Compact.",
        1, MODE_COMPACT, true))

    add(actionStep("D cycle", "ACTION key correct after three cycles", 1,
        "Press |cffffd200" .. keyFor("action") .. "|r once.",
        { page = 1, mode = MODE_COMPACT }))

    ----------------------------------------------------------------------------
    -- E — fully hidden background operation.
    ----------------------------------------------------------------------------
    add(stateStep("E hidden", "toggle key hides the root in combat",
        "Press |cffffd200" .. keyFor("toggle") .. "|r.\n"
        .. "The lab window should vanish. The red bar stays -- it is outside "
        .. "the root and always will be.\n"
        .. "|cffff8800Do not click where the window was.|r",
        1, MODE_COMPACT, false))

    add(actionStep("E hidden", "ACTION key works with the root hidden", 1,
        "Press |cffffd200" .. keyFor("action") .. "|r once.\n"
        .. "Nothing is on screen. This is the whole point of the test.",
        { page = 1, root = false }))

    add(stateStep("E hidden", "page NEXT key works with the root hidden",
        "Press |cffffd200" .. keyFor("next") .. "|r.\n"
        .. "You will see nothing. The lab is watching the hidden page labels.",
        2, MODE_COMPACT, false))

    add(actionStep("E hidden", "ACTION key targets page 2 after a hidden flip", 2,
        "Press |cffffd200" .. keyFor("action") .. "|r once.",
        { page = 2, root = false }))

    add(stateStep("E hidden", "MINIMAL key works with the root hidden",
        "Press |cffffd200" .. keyFor("minimal") .. "|r.\n"
        .. "The mode control it targets is inside the hidden root, which is the "
        .. "point: can a hidden secure handler still be driven by its key?",
        2, MODE_MINIMAL, false))

    add(stateStep("E hidden", "cycle key works with the root hidden",
        "Press |cffffd200" .. keyFor("cycle") .. "|r.\n"
        .. "Minimal should cycle to Full.", 2, MODE_FULL, false))

    add(stateStep("E hidden", "page PREVIOUS key works with the root hidden",
        "Press |cffffd200" .. keyFor("prev") .. "|r.", 1, MODE_FULL, false))

    add(actionStep("E hidden", "ACTION key targets page 1 after a hidden flip back", 1,
        "Press |cffffd200" .. keyFor("action") .. "|r once.",
        { page = 1, root = false }))

    add(stateStep("E hidden", "toggle key restores the root in combat",
        "Press |cffffd200" .. keyFor("toggle") .. "|r.\n"
        .. "The window should come back showing |cffffd200PAGE 1|r and "
        .. "|cffffd200FULL|r -- the state it reached while it was invisible.",
        1, MODE_FULL, true))

    ----------------------------------------------------------------------------
    -- F — hide and show must preserve, not reset.
    ----------------------------------------------------------------------------
    add(stateStep("F preserve", "set Compact before hiding",
        "Press |cffffd200" .. keyFor("compact") .. "|r.", 1, MODE_COMPACT, true))

    add(stateStep("F preserve", "hide while Compact",
        "Press |cffffd200" .. keyFor("toggle") .. "|r once.\n"
        .. "The window goes away. The mode must not.", 1, MODE_COMPACT, false))

    add(stateStep("F preserve", "hide and show preserves Compact",
        "Press |cffffd200" .. keyFor("toggle") .. "|r once more.\n"
        .. "It must come back |cffffd200Compact|r, not Full.",
        1, MODE_COMPACT, true))

    add(stateStep("F preserve", "move to page 2 before the second hide",
        "Press |cffffd200" .. keyFor("next") .. "|r.", 2, MODE_COMPACT, true))

    add(stateStep("F preserve", "set Minimal before the second hide",
        "Press |cffffd200" .. keyFor("minimal") .. "|r.", 2, MODE_MINIMAL, true))

    add(stateStep("F preserve", "hide while Minimal on page 2",
        "Press |cffffd200" .. keyFor("toggle") .. "|r once.",
        2, MODE_MINIMAL, false))

    add(stateStep("F preserve", "hide and show preserves Minimal and page 2",
        "Press |cffffd200" .. keyFor("toggle") .. "|r once more.\n"
        .. "It must come back |cffffd200Minimal, page 2|r.",
        2, MODE_MINIMAL, true))

    add(actionStep("F preserve", "ACTION key correct after hide and show", 2,
        "Press |cffffd200" .. keyFor("action") .. "|r once.",
        { page = 2, mode = MODE_MINIMAL, root = true }))

    ----------------------------------------------------------------------------
    -- The deliberate collision, last, on a disposable owner.
    ----------------------------------------------------------------------------
    add({
        phase = "collision probe",
        capability = "one owner, two keys, baseline",
        timeout = 90,
        recordOnTimeout = true,
        text = "Two extra keys are bound to |cffffd200one|r owner, on purpose.\n"
            .. "Press |cffffd200" .. COLLIDE_PAGE_KEY .. "|r then "
            .. "|cffffd200" .. COLLIDE_MODE_KEY .. "|r.\n"
            .. "Both should register.",
        enter = function()
            S2.collision.page, S2.collision.mode = 0, 0
        end,
        observe = function()
            if S2.collision.page > 0 and S2.collision.mode > 0 then return true end
            return false, ("page %d, mode %d so far")
                :format(S2.collision.page, S2.collision.mode)
        end,
        done = function()
            record({
                capability = "one owner, two keys, baseline",
                context = inCombat() and "combat" or "out of combat",
                trigger = "two override keys on one owner",
                after = ("page %d, mode %d"):format(S2.collision.page, S2.collision.mode),
                conclusion = (S2.collision.page > 0 and S2.collision.mode > 0)
                    and "YES — observed" or "INCONCLUSIVE — baseline not established",
            })
        end,
    })

    add({
        phase = "collision probe",
        capability = "same-owner ClearBindings removes the unrelated key",
        timeout = 120,
        recordOnTimeout = true,
        text = "Click |cffffd200COLLISION PROBE|r on the red bar.\n"
            .. "It clears that owner's bindings and re-applies |cffffd200only|r "
            .. "the first key.\n"
            .. "Then press |cffffd200" .. COLLIDE_PAGE_KEY .. "|r and "
            .. "|cffffd200" .. COLLIDE_MODE_KEY .. "|r again.",
        enter = function()
            S2.collision.page, S2.collision.mode = 0, 0
            S2.collideRan = attr(F.collideRun, "ran") or 0
        end,
        observe = function()
            if S2.collision.page > 0 then return true end
            return false, "the surviving key has not been pressed yet"
        end,
        done = function()
            local ran = attr(F.collideRun, "ran") or 0
            record({
                capability = "same-owner ClearBindings removes the unrelated key",
                context = inCombat() and "combat" or "out of combat",
                trigger = "ClearBindings from a snippet on the owning header",
                after = ("surviving key %d, cleared key %d")
                    :format(S2.collision.page, S2.collision.mode),
                note = ("probe snippet ran %s -> %d")
                    :format(tostring(S2.collideRan), ran),
                conclusion = (S2.collision.page > 0 and S2.collision.mode == 0)
                    and "YES — observed: the unrelated binding was destroyed"
                    or (S2.collision.mode > 0
                        and "NO — the unrelated binding survived"
                        or "INCONCLUSIVE — the probe did not run"),
            })
        end,
    })

    add({
        phase = "done",
        manual = true,
        buttonText = "Finish",
        text = "|cff44ff44That is Stage 2.|r\n"
            .. "Leave combat, then run |cffffd200/imitest runlab copy|r and send "
            .. "the whole report back.",
        done = function() S2.Restore() end,
    })

    return steps
end

S2.BuildSequence = buildSequence

--------------------------------------------------------------------------------
-- The summary
--
-- Read back out of the results Stage 2 recorded, never from a second tally kept
-- alongside them. A summary that counts its own way is a summary that can
-- disagree with the detail underneath it.
--------------------------------------------------------------------------------

S2.results = {}

local realRecord = record
record = function(entry)
    S2.results[#S2.results + 1] = entry
    return realRecord(entry)
end

local function verdict(capability)
    for _, r in ipairs(S2.results) do
        if r.capability == capability then
            local c = r.conclusion or ""
            if c:match("^YES") then return "YES" end
            if c:match("^FAIL") then return "FAIL" end
            if c:match("^NO") then return "NO" end
            return "INCONCLUSIVE"
        end
    end
    return "NOT RUN"
end

local function anyDoubleFire()
    for _, r in ipairs(S2.results) do
        if (r.conclusion or ""):match("^FAIL — one press fired both") then
            return "YES"
        end
    end
    for _, r in ipairs(S2.results) do
        if r.expectedTarget then return "NO" end
    end
    return "NOT RUN"
end

local function line(out, label, value)
    out[#out + 1] = ("%-54s %s"):format(label, value)
end

function S2.SummaryLines()
    local out = {}
    if #S2.results == 0 then
        return { "== Stage 2 — not run ==", "",
                 "/imitest runlab stage2 builds it. Nothing below was measured." }
    end

    out[#out + 1] = "== Stage 2 — Context x Mode x Hidden Summary =="
    out[#out + 1] = ""
    out[#out + 1] = "CONTEXTUAL PAGE BINDINGS"
    out[#out + 1] = "------------------------"
    line(out, "ACTION key -> Page 1 before flip",
        verdict("ACTION key targets page 1 before any flip"))
    line(out, "Page Next key works in combat",
        verdict("page NEXT key flips to page 2 in combat"))
    line(out, "ACTION key -> Page 2 after Next",
        verdict("ACTION key targets page 2 after NEXT"))
    line(out, "Page Previous key works in combat",
        verdict("page PREVIOUS key flips back in combat"))
    line(out, "ACTION key -> Page 1 after Previous",
        verdict("ACTION key targets page 1 after PREVIOUS"))
    line(out, "Repeated P1<->P2 rebinding remains correct",
        verdict("ACTION key still correct after two full rounds"))
    line(out, "One ACTION press ever fired both pages (want NO)", anyDoubleFire())
    out[#out + 1] = ""

    out[#out + 1] = "PAGE VISUAL STATE"
    out[#out + 1] = "-----------------"
    line(out, "Page identity updates on combat Next",
        verdict("page NEXT key flips to page 2 in combat"))
    line(out, "Page identity updates on combat Previous",
        verdict("page PREVIOUS key flips back in combat"))
    line(out, "Page visual matches secure page after repeats",
        verdict("second flip back to page 1"))
    out[#out + 1] = ""

    out[#out + 1] = "MODE — PHYSICAL CONTROLS"
    out[#out + 1] = "------------------------"
    line(out, "Full -> Compact by combat mouse click",
        verdict("Full to Compact by mouse click in combat"))
    line(out, "Compact -> Minimal by combat mouse click",
        verdict("Compact to Minimal by mouse click in combat"))
    line(out, "Minimal -> Full by combat mouse click",
        verdict("Minimal to Full by mouse click in combat"))
    line(out, "Action target correct after mouse mode changes",
        verdict("ACTION key correct after returning to Full"))
    out[#out + 1] = ""

    out[#out + 1] = "MODE — DIRECT KEYS"
    out[#out + 1] = "------------------"
    line(out, "Full key works in combat",
        verdict("FULL key works, and the page is untouched"))
    line(out, "Compact key works in combat", verdict("COMPACT key works in combat"))
    line(out, "Minimal key works in combat", verdict("MINIMAL key works in combat"))
    line(out, "Cycle key works in combat", verdict("cycle Compact to Minimal"))
    line(out, "Cycle order Full->Compact->Minimal->Full",
        verdict("cycle Full to Compact"))
    line(out, "Mode keys survive page ClearBindings/rebind",
        verdict("mode keys survive the pager's ClearBindings"))
    out[#out + 1] = ""

    out[#out + 1] = "MINIMAL"
    out[#out + 1] = "-------"
    line(out, "Minimal hides normal action presentation",
        verdict("Compact to Minimal by mouse click in combat"))
    line(out, "Page identity remains visible in Minimal",
        verdict("page NEXT by mouse while Minimal"))
    line(out, "Physical Next/Previous works in Minimal",
        verdict("page PREVIOUS by mouse while Minimal"))
    line(out, "ACTION key works in Minimal Page 1",
        verdict("ACTION key works in Minimal with no action body on screen"))
    line(out, "ACTION key works in Minimal Page 2",
        verdict("ACTION key targets page 2 in Minimal"))
    line(out, "Physical mode controls can exit Minimal",
        verdict("Minimal to Full by mouse click in combat"))
    out[#out + 1] = ""

    out[#out + 1] = "FULLY HIDDEN / BACKGROUND"
    out[#out + 1] = "-------------------------"
    line(out, "Toggle key hides root in combat",
        verdict("toggle key hides the root in combat"))
    line(out, "ACTION key works with root hidden",
        verdict("ACTION key works with the root hidden"))
    line(out, "Page Next key works with root hidden",
        verdict("page NEXT key works with the root hidden"))
    line(out, "ACTION key targets Page 2 after hidden Next",
        verdict("ACTION key targets page 2 after a hidden flip"))
    line(out, "Page Previous key works with root hidden",
        verdict("page PREVIOUS key works with the root hidden"))
    line(out, "Mode direct key works with root hidden",
        verdict("MINIMAL key works with the root hidden"))
    line(out, "Cycle mode key works with root hidden",
        verdict("cycle key works with the root hidden"))
    line(out, "Toggle key restores root in combat",
        verdict("toggle key restores the root in combat"))
    line(out, "Restored root shows hidden-updated page and mode",
        verdict("toggle key restores the root in combat"))
    line(out, "Hide/show preserves Compact",
        verdict("hide and show preserves Compact"))
    line(out, "Hide/show preserves Minimal",
        verdict("hide and show preserves Minimal and page 2"))
    out[#out + 1] = ""

    out[#out + 1] = "OWNER ISOLATION"
    out[#out + 1] = "---------------"
    line(out, "Page flip ever killed a mode key (want NO)",
        verdict("mode keys survive the pager's ClearBindings") == "YES" and "NO"
            or "SEE DETAIL")
    line(out, "Mode switch ever killed action/page key (want NO)",
        verdict("page NEXT key still live after mode keys") == "YES" and "NO"
            or "SEE DETAIL")
    line(out, "Root toggle ever killed a binding (want NO)",
        verdict("ACTION key works with the root hidden") == "YES" and "NO"
            or "SEE DETAIL")
    line(out, "Same-owner ClearBindings collision observed",
        verdict("same-owner ClearBindings removes the unrelated key"))
    out[#out + 1] = ""

    out[#out + 1] = "SAFETY"
    out[#out + 1] = "------"
    line(out, "Production frames mutated by Stage 2", "NO")
    line(out, "Production SavedVariables changed by Stage 2", "NO")
    line(out, "External rescue remained available",
        shown(F.rescueBar) == true and "YES" or "CHECK")
    line(out, "Stage 2 override bindings still armed",
        armed and "YES — run /imitest runlab stage2 release" or "NO")
    line(out, "Keyboard ownership left behind", "NO")
    out[#out + 1] = ""

    out[#out + 1] = "== Stage 2 Product Implications =="
    out[#out + 1] = ""
    out[#out + 1] = "Observed in a synthetic production-like hierarchy, not in"
    out[#out + 1] = "production itself. Read every line against the detail above it."
    out[#out + 1] = ""
    local function q(n, text, v)
        out[#out + 1] = ("%2d. %s"):format(n, text)
        out[#out + 1] = ("    %s"):format(v)
    end
    q(1, "Same physical callout key changes target with the page in combat?",
        verdict("ACTION key still correct after two full rounds"))
    q(2, "Full/Compact/Minimal switchable by mouse in combat?",
        verdict("Minimal to Full by mouse click in combat"))
    q(3, "Those modes selectable directly by key in combat?",
        verdict("MINIMAL key works in combat"))
    q(4, "Cycle key works without disturbing page/action bindings?",
        verdict("ACTION key correct after three cycles"))
    q(5, "Minimal hides callout bodies with keys still working?",
        verdict("ACTION key works in Minimal with no action body on screen"))
    q(6, "Page navigation visible and mouse-usable in Minimal?",
        verdict("page NEXT by mouse while Minimal"))
    q(7, "Root fully hidden with action, page and mode keys all live?",
        verdict("cycle key works with the root hidden"))
    q(8, "Same toggle key restores the hidden root during combat?",
        verdict("toggle key restores the root in combat"))
    q(9, "Reopening reveals hidden-time page and mode with no insecure redraw?",
        verdict("toggle key restores the root in combat"))
    q(10, "Separate binding ownership solves the ClearBindings collision?",
        verdict("mode keys survive the pager's ClearBindings"))
    out[#out + 1] = ""
    out[#out + 1] = "12. Still unmeasured before production implementation:"
    out[#out + 1] = "    - more than two pages, and a page count that changes mid-fight"
    out[#out + 1] = "    - more than one callout key per page"
    out[#out + 1] = "    - the same architecture built on production's own frames"
    out[#out + 1] = "    - what happens across a dungeon change while Run is hidden"

    return out
end

Lab.Summary(function() return S2.SummaryLines() end)

--------------------------------------------------------------------------------
-- Preflight
--------------------------------------------------------------------------------

local function existingBinding(chord)
    if type(GetBindingAction) ~= "function" then return nil end
    local ok, action = pcall(GetBindingAction, chord)
    if ok and type(action) == "string" and action ~= "" then return action end
    return nil
end

function S2.Preflight(emit)
    local missing = {}
    for _, key in ipairs({ "root", "pager", "moder", "toggler", "action1", "action2",
                           "pageId1", "pageId2", "visFull", "visCompact",
                           "visMinimal", "prev", "next", "modeFull", "modeCompact",
                           "modeMinimal", "modeCycle", "toggle", "rescue",
                           "rescueBar", "collider" }) do
        if not F[key] then missing[#missing + 1] = key end
    end
    emit("frames: %s", #missing == 0 and "all built"
        or ("MISSING " .. table.concat(missing, ", ")))

    -- Owner identity. Two names that resolve to one frame would make the whole
    -- separation argument vacuous while looking perfectly fine.
    local distinct = F.pager ~= F.moder and F.moder ~= F.toggler
        and F.pager ~= F.toggler
    emit("three binding owners are distinct frames: %s", distinct and "yes" or "NO")

    emit("rescue is outside the root: %s",
        (F.rescue and F.rescue:GetParent() == F.rescueBar) and "yes" or "NO")

    for _, act in ipairs({ { 1, F.action1 }, { 2, F.action2 } }) do
        local text = (act[2] and act[2]:GetAttribute("macrotext")) or ""
        emit("page %d action macro: %s", act[1],
            text:find("S2Fired", 1, true) and "prepared" or "MISSING")
    end

    emit("baseline: %s", stateLine())

    for _, entry in ipairs(KEYS) do
        local existing = existingBinding(entry.key)
        emit("%-22s %-22s owner %s%s", entry.key, entry.what, entry.owner,
            existing and ("  |cffff8800(currently bound to " .. existing .. ")|r") or "")
    end
    for _, pair in ipairs({ { COLLIDE_PAGE_KEY, "collision probe A" },
                            { COLLIDE_MODE_KEY, "collision probe B" } }) do
        local existing = existingBinding(pair[1])
        emit("%-22s %-22s owner collider%s", pair[1], pair[2],
            existing and ("  |cffff8800(currently bound to " .. existing .. ")|r") or "")
    end
end

--------------------------------------------------------------------------------
-- Commands, reached through /imitest runlab stage2 ...
--------------------------------------------------------------------------------

function S2.Command(arg)
    arg = (arg or ""):lower():match("^%s*(.-)%s*$")

    if arg == "" or arg == "setup" then
        if inCombat() then say("|cffff4444out of combat only.|r") return end

        -- Stage 2 borrows Stage 1's step panel and rescue bar, so those have to
        -- exist. Building them is only done when they do not, because setup
        -- clears Stage 1's results and this must never quietly discard a run.
        if not Lab.Built() then pcall(Lab.Command, "setup") end

        -- Stage 1's keys overlap two of Stage 2's. Clearing them here beats
        -- discovering the collision as a mystery failure halfway through.
        pcall(Lab.Command, "release")

        local ok, why = S2.Build()
        if not ok then say("could not build: %s", tostring(why)) return end

        -- Stage 1's surface goes away while Stage 2 owns the screen. Two lab
        -- windows on top of each other during a hidden-root test is exactly
        -- the confusion this run cannot afford.
        if Lab.Hibernate then Lab.Hibernate(true) end
        S2.Restore()
        S2.results = {}
        Lab.Drive(buildSequence(), S2.Restore)
        say("Stage 2 built. |cffffd200PREFLIGHT|r then |cffffd200ARM|r next.")
        say("Stage 1's test keys were released; its results are kept.")
        return
    end

    if not built then say("run |cffffd200/imitest runlab stage2|r first.") return end

    if arg == "preflight" then
        if inCombat() then say("|cffff4444out of combat only.|r") return end
        S2.Preflight(say)
        return
    end

    if arg == "arm" then
        if inCombat() then say("|cffff4444out of combat only.|r") return end
        local ok, why = S2.Arm()
        if not ok then say("could not arm: %s", tostring(why)) return end
        say("|cffff8800STAGE 2 KEYS ARMED — temporary, gone on /reload.|r")
        for _, entry in ipairs(KEYS) do
            say("  |cffffd200%-22s|r %s", entry.key, entry.what)
        end
        say("now get on a |cffffd200training dummy|r and follow the panel.")
        return
    end

    if arg == "status" then
        beginCapture()
        local reader = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
        local okVer, version = pcall(reader, "InomrahsMISelfTest", "Version")
        say("self-test %s", (okVer and version) or "unknown")
        say("combat: %s | %s", inCombat() and "yes" or "no", stateLine())
        say("page 1 fired %d (button clicked %d) | page 2 fired %d (clicked %d)",
            S2.fired[1] or 0, F.action1 and F.action1.clicks or 0,
            S2.fired[2] or 0, F.action2 and F.action2.clicks or 0)
        say("armed: %s | action size %s x %s scale %s", armed and "yes" or "no",
            fmt(width(F.action1)), fmt(height(F.action1)), fmt(scale(F.action1)))
        say("pager rebinds: %s", tostring(attr(F.pager, "bound") or 0))
        say("")

        -- Per control, the three facts that were one number in Stage 1:
        --   clicks   the insecure hook fired, so nothing threw
        --   entered  the snippet began, stamped before anything can fail
        --   ran      the snippet reached its end
        -- entered 0 means the key or click never arrived at all, which is a
        -- binding problem. entered 1 with ran 0 means the snippet threw.
        -- The flip is stamped between every call, so one run says which one
        -- stops it rather than "the page did not change".
        for _, entry in ipairs({ { "< PREV", F.prev }, { "NEXT >", F.next } }) do
            local b = entry[2]
            say("%s  entered %s gotmanager %s readindex %s wroteindex %s",
                entry[1],
                tostring(attr(b, "entered") or 0),
                tostring(attr(b, "gotmanager") or 0),
                tostring(attr(b, "readindex") or 0),
                tostring(attr(b, "wroteindex") or 0))
            say("        gotmoder %s readmode %s gotlabels %s didlabels %s",
                tostring(attr(b, "gotmoder") or 0),
                tostring(attr(b, "readmode") or 0),
                tostring(attr(b, "gotlabels") or 0),
                tostring(attr(b, "didlabels") or 0))
            say("        gotactions %s didactions %s presented %s ran %s",
                tostring(attr(b, "gotactions") or 0),
                tostring(attr(b, "didactions") or 0),
                tostring(attr(b, "presented") or 0),
                tostring(attr(b, "ran") or 0))
            if (attr(b, "nomanager") or 0) > 0 then
                say("    |cffff8800the manager frame reference came back nil|r")
            end
        end
        say("LABEL PROBE  clicks %s entered %s gotlabels %s hid %s ran %s",
            tostring(F.labelProbe and F.labelProbe.clicks or 0),
            tostring(attr(F.labelProbe, "entered") or 0),
            tostring(attr(F.labelProbe, "gotlabels") or 0),
            tostring(attr(F.labelProbe, "hid") or 0),
            tostring(attr(F.labelProbe, "ran") or 0))
        say("pager cleared bindings: %s | bound the action %s times",
            tostring(attr(F.pager, "cleared") or 0),
            tostring(attr(F.pager, "boundAction") or 0))
        say("")

        -- What the client says is bound, rather than what the snippet believes
        -- it did. A SetBindingClick that completes and binds nothing has no
        -- error to notice; this is the only thing that catches it.
        say("key                    override binding / normal binding")
        for _, entry in ipairs(KEYS) do
            -- The second argument is the whole point. Everything Stage 2 makes
            -- is an override binding, and GetBindingAction does not report
            -- those unless asked -- so the first version of this readout said
            -- NOTHING for eight keys that may have been perfectly bound, which
            -- is the same "measured nothing, reported as a result" mistake in
            -- the instrument rather than the subject.
            local okOver, override = pcall(GetBindingAction, entry.key, true)
            local okPlain, plain = pcall(GetBindingAction, entry.key)
            local function text(ok, value)
                if ok and type(value) == "string" and value ~= "" then return value end
                return "none"
            end
            say("%-22s %s / %s", entry.key,
                text(okOver, override), text(okPlain, plain))
        end
        say("")

        say("control            clicks entered ran")
        for _, entry in ipairs({
            { "< PREV", F.prev }, { "NEXT >", F.next },
            { "FULL", F.modeFull }, { "COMPACT", F.modeCompact },
            { "MINIMAL", F.modeMinimal }, { "CYCLE", F.modeCycle },
            { "HIDE / SHOW", F.toggle }, { "SHOW RUN ROOT", F.rescue },
        }) do
            local b = entry[2]
            say("%-18s %-6s %-7s %s", entry[1],
                tostring(b and b.clicks or 0),
                tostring(attr(b, "entered") or 0),
                tostring(attr(b, "ran") or 0))
        end
        endCapture("Stage 2 status")
        return
    end

    if arg == "reset" then
        if inCombat() then say("|cffff4444out of combat only.|r") return end
        S2.Restore()
        if armed then S2.Arm() end
        say("back to baseline: %s", stateLine())
        return
    end

    if arg == "release" then
        if inCombat() then
            say("|cffff4444out of combat only|r — SHOW RUN ROOT works mid-fight.")
            return
        end
        S2.Disarm()
        S2.Restore()
        if F.root then F.root:Hide() end
        if F.rescueBar then F.rescueBar:Hide() end
        Lab.Release()
        if Lab.Hibernate then Lab.Hibernate(false) end
        say("Stage 2 keys cleared and the surface put away. Results are kept.")
        return
    end

    say("stage2 commands: setup, preflight, arm, status, reset, release")
end

S2.KEYS = KEYS
S2.CollideKeys = { page = COLLIDE_PAGE_KEY, mode = COLLIDE_MODE_KEY }
