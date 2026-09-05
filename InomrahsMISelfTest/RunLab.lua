--------------------------------------------------------------------------------
-- RunLab: a synthetic hierarchy for measuring what combat actually permits.
--
-- Stage 1. The question behind all of it is whether a future Run presentation
-- can become visually absent while its callout keys keep working -- and, just
-- as importantly, without leaving a large invisible frame that eats mouse
-- clicks meant for the game. A transparent UI that steals clicks is not a
-- Minimal mode; it is a bug with a nice description.
--
-- Everything here is synthetic. The lab builds its own frames, its own secure
-- manager, its own action buttons and its own bindings, and never touches the
-- production addon. That is not tidiness: insecure code that reaches into a
-- production secure frame taints it, and the player would find their real
-- callouts silently dead mid-key with no idea a test addon did it. There is no
-- code path in this file that mutates a production frame, and the report says
-- so from a fact rather than from a promise.
--
-- What is measured and what is merely observed are kept apart throughout:
--
--   * a method appearing on a restricted handle is not a capability;
--   * a call returning without error is not an effect;
--   * a binding being registered is not an execution;
--   * a snippet believing it ran is not the frame having changed.
--
-- So every probe records what it asked for, what the client reported
-- afterwards, and -- where it matters -- whether the synthetic secure action
-- actually fired. The three are reported separately and can disagree.
--------------------------------------------------------------------------------

local ADDON = ...

local API = _G.InomrahsMISelfTestAPI or {}
local approximately = API.Approximately or function(a, b, e)
    e = e or 0.01
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= e
end

InomrahsMISelfTestRunLab = {}
local Lab = InomrahsMISelfTestRunLab

local PREFIX = "|cff8f7fe8MI RunLab|r "
--- Chat, and optionally the report window as well.
---
--- preflight and arm printed to chat only, which was a mistake: a dozen lines
--- scroll past, the report window still holds whatever was in it before, and a
--- copy taken from that window is the ordinary self-test report. The two are
--- indistinguishable in a screenshot, so the lab now puts its own output in the
--- window every time rather than relying on the reader to notice.
local capture = nil

local function say(...)
    local text = string.format(...)
    print(PREFIX .. text)
    if capture then
        -- Colour escapes are markup for the chat frame; in an EditBox they show
        -- up as literal |cffffd200, which is worse than no colour at all.
        local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        capture[#capture + 1] = plain
    end
end

local function beginCapture()
    capture = {}
end

--- Close the buffer and show it. Never called from a combat path: the window
--- is insecure and opening one mid-fight is exactly the kind of surprise this
--- addon is supposed to avoid.
local function endCapture(title)
    local lines = capture
    capture = nil
    if not lines or #lines == 0 then return end
    -- status is the one command that answers during a fight. Covering the
    -- screen with a report window at that moment would hide the step panel the
    -- lab is asking the reader to follow. Chat already has every line.
    if InCombatLockdown() then return end
    local text = ("RUN CAPABILITY LAB -- %s\n%s\n\n%s\n")
        :format(title, ("="):rep(62), table.concat(lines, "\n"))
    if API.Report then API.Report(text) else print(text) end
end

--------------------------------------------------------------------------------
-- Results
--
-- One shape for every observation, because the report is meant to be pasted
-- into another conversation and read by someone who was not here. A conclusion
-- on its own is worth very little; a conclusion next to what was asked for and
-- what came back can be argued with.
--------------------------------------------------------------------------------

local results = {}

--- @param r table with any of: capability, context, trigger, target, operation,
---   before, requested, after, visible, execBefore, execAfter, underlayBefore,
---   underlayAfter, intercept, restore, restoreResult, err, conclusion, note
local function record(r)
    r.at = #results + 1
    results[#results + 1] = r
    return r
end

local function conclusionOf(name)
    for i = #results, 1, -1 do
        if results[i].capability == name then return results[i].conclusion end
    end
    return nil
end

--- YES/NO for the condensed matrix, from whatever the detailed result said.
local function yesNo(name)
    local c = conclusionOf(name)
    if not c then return "not run" end
    if c:match("^YES") then return "YES" end
    if c:match("^NO") then return "NO" end
    if c:match("^NOT AVAILABLE") then return "NOT AVAILABLE" end
    return "INCONCLUSIVE"
end

--------------------------------------------------------------------------------
-- Safe reads
--
-- 12.x hands back Secret Values from frames an addon has no business reading.
-- The lab only reads its own frames, so this should never fire -- which is
-- exactly why it is here: the one place it does fire is the place we would
-- otherwise lose the whole session to.
--------------------------------------------------------------------------------

local function num(fn, frame)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, frame)
    if ok and type(value) == "number" then return value end
    return nil
end

local function width(f)  return f and num(f.GetWidth, f) end
local function height(f) return f and num(f.GetHeight, f) end
local function alpha(f)  return f and num(f.GetAlpha, f) end
local function top(f)    return f and num(f.GetTop, f) end
local function left(f)   return f and num(f.GetLeft, f) end

local function shown(f)
    if not f or type(f.IsShown) ~= "function" then return nil end
    local ok, value = pcall(function() return f:IsShown() == true end)
    if ok then return value end
    return nil
end

local function visible(f)
    if not f or type(f.IsVisible) ~= "function" then return nil end
    local ok, value = pcall(function() return f:IsVisible() == true end)
    if ok then return value end
    return nil
end

local function tri(value)
    if value == true then return "yes" end
    if value == false then return "no" end
    return "unreadable"
end

local function fmt(value)
    if type(value) == "number" then return ("%.4f"):format(value) end
    if value == nil then return "unreadable" end
    return tostring(value)
end

--------------------------------------------------------------------------------
-- Evidence that the synthetic secure action really executed
--
-- A macro containing /run executes ordinary Lua *because the macro ran*. That
-- is an observation of execution, not an inference from a binding being
-- registered -- the thing that must never be counted as proof. It cannot be
-- throttled the way chat can, works in any zone, and is silent.
--
-- The mechanism is not trusted until it has been seen working twice: once out
-- of combat and once in combat with the button in its ordinary visible state.
-- Only then is a zero count from a hidden state evidence of anything.
--------------------------------------------------------------------------------

local fired = { [1] = 0, [2] = 0 }
local sayEnabled = false
local saySeq = 0

function InomrahsMISelfTestRunLabFired(which)
    which = tonumber(which) or 1
    fired[which] = (fired[which] or 0) + 1
end

--- The optional human-visible confirmation. Off by default: the default test
--- mechanism must not spam everyone standing at the dummy. Each message carries
--- a sequence number so the server's duplicate-message throttle cannot swallow
--- a genuine execution and make it look like a refusal.
function InomrahsMISelfTestRunLabSay(which)
    if not sayEnabled then return end
    saySeq = saySeq + 1
    local ok = pcall(SendChatMessage,
        ("[IMI LAB] action %d #%d"):format(tonumber(which) or 1, saySeq), "SAY")
    if not ok then sayEnabled = false end
end

local function macroFor(which)
    return ("/run InomrahsMISelfTestRunLabFired(%d)\n/run InomrahsMISelfTestRunLabSay(%d)")
        :format(which, which)
end

--------------------------------------------------------------------------------
-- The frames
--
-- Names are all InomrahsMISelfTestRunLab-prefixed. Production uses InomrahsMI
-- without the SelfTest, so nothing here can collide with it.
--------------------------------------------------------------------------------

local F = {}                     -- every lab frame, by short name
local built = false
local armed = false
local baseline = {}              -- canonical geometry, captured at build time

-- The root is sized from its contents rather than the contents squeezed into
-- the root. It was the other way round, and the scroll viewport -- anchored to
-- the bottom edge -- ended up sitting on top of two thirds of the operation
-- buttons. They rendered perfectly and swallowed every click, and three of the
-- four "the snippet never ran" results in the first live run were that, not
-- the client refusing anything.
local ROOT_W = 320
local ANC_W, ANC_H = ROOT_W - 20, 142          -- the protected ancestor
local OPS_TOP = 24 + ANC_H + 8                 -- below the ancestor
local OPS_ROWS, OPS_ROW_H = 4, 20
local VIEW_H = 26
local ROOT_H = OPS_TOP + OPS_ROWS * OPS_ROW_H + 10 + VIEW_H + 8
local ACTION_W, ACTION_H = 160, 34
local PARK_X, PARK_Y = 1200, -1200   -- far off any real UI, and lab-owned

--- The snippet every toggle uses.
--
-- Two things beyond the flip itself. It counts its own runs, so a state that
-- did not change can be told apart from a snippet that never ran at all -- the
-- difference between "combat refused it" and "your click missed". And it
-- records what it believes the new state to be, so insecure code can compare
-- the snippet's belief against what the client actually reports. Those two
-- disagreeing is a finding in itself.
local TOGGLE_SHOW = [==[
    self:SetAttribute("entered", (self:GetAttribute("entered") or 0) + 1)

    local target = self:GetFrameRef("target")
    if not target then return end

    if target:IsShown() then target:Hide() else target:Show() end

    self:SetAttribute("ran", (self:GetAttribute("ran") or 0) + 1)
    self:SetAttribute("wanted", target:IsShown() and "shown" or "hidden")
]==]

--- Moves the action between its home anchor and a parked one far outside the
--- visible area. A candidate for Minimal if alpha turns out to steal clicks:
--- a frame nobody can reach cannot intercept anything.
local TOGGLE_PARK = [==[
    self:SetAttribute("entered", (self:GetAttribute("entered") or 0) + 1)

    local target = self:GetFrameRef("target")
    local home = self:GetFrameRef("home")
    if not target or not home then return end

    -- The intent is recorded before the move is attempted. It was recorded
    -- after, so a refused SetPoint left the toggle believing it had never
    -- parked: the next click took the same branch, was refused in the same
    -- place, and the button could never come back.
    target:ClearAllPoints()
    self:SetAttribute("cleared", (self:GetAttribute("cleared") or 0) + 1)

    if self:GetAttribute("parked") then
        self:SetAttribute("parked", false)
        target:SetPoint("TOPLEFT", home, "TOPLEFT", 0, 0)
    else
        self:SetAttribute("parked", true)
        target:SetPoint("TOPLEFT", home, "TOPLEFT", PARK_X_VALUE, PARK_Y_VALUE)
    end
    self:SetAttribute("pointed", (self:GetAttribute("pointed") or 0) + 1)

    self:SetAttribute("ran", (self:GetAttribute("ran") or 0) + 1)
]==]

--- Shrinks the action to 1x1 and back. Deliberately not zero: a zero dimension
--- is rejected outright by the client and would measure the rejection rather
--- than the capability.
local TOGGLE_SIZE = [==[
    self:SetAttribute("entered", (self:GetAttribute("entered") or 0) + 1)

    local target = self:GetFrameRef("target")
    if not target then return end

    if self:GetAttribute("small") then
        target:SetWidth(NORMAL_W)
        target:SetHeight(NORMAL_H)
        self:SetAttribute("small", false)
    else
        target:SetWidth(1)
        target:SetHeight(1)
        self:SetAttribute("small", true)
    end

    self:SetAttribute("ran", (self:GetAttribute("ran") or 0) + 1)
]==]

--- Geometry on the protected ancestor: the shape a future Compact would need.
--- Width and height are toggled together and the anchor separately, so a client
--- that allows one and refuses the other is not reported as allowing both.
local TOGGLE_GEO = [==[
    self:SetAttribute("entered", (self:GetAttribute("entered") or 0) + 1)

    local target = self:GetFrameRef("target")
    if not target then return end

    if self:GetAttribute("narrow") then
        target:SetWidth(WIDE_W)
        target:SetHeight(TALL_H)
        self:SetAttribute("narrow", false)
    else
        target:SetWidth(WIDE_W / 2)
        target:SetHeight(TALL_H / 2)
        self:SetAttribute("narrow", true)
    end

    self:SetAttribute("ran", (self:GetAttribute("ran") or 0) + 1)
]==]

local TOGGLE_ANCHOR = [==[
    self:SetAttribute("entered", (self:GetAttribute("entered") or 0) + 1)

    local target = self:GetFrameRef("target")
    local home = self:GetFrameRef("home")
    if not target or not home then return end

    target:ClearAllPoints()
    self:SetAttribute("cleared", (self:GetAttribute("cleared") or 0) + 1)

    if self:GetAttribute("moved") then
        self:SetAttribute("moved", false)
        target:SetPoint("TOPLEFT", home, "TOPLEFT", 0, 0)
    else
        self:SetAttribute("moved", true)
        target:SetPoint("TOPLEFT", home, "TOPLEFT", 40, -40)
    end
    self:SetAttribute("pointed", (self:GetAttribute("pointed") or 0) + 1)

    self:SetAttribute("ran", (self:GetAttribute("ran") or 0) + 1)
]==]

--- The operations ordinary Lua was refused in combat, attempted from a snippet
--- instead. The restricted method inventory lists SetScale, EnableMouse and
--- SetAlpha as available to snippets, and Stage 1 watched insecure code be
--- refused all three. Whether a method is listed and whether calling it is
--- permitted are different facts, and only this tells them apart.
local SNIPPET_SCALE = [==[
    self:SetAttribute("entered", (self:GetAttribute("entered") or 0) + 1)

    local target = self:GetFrameRef("target")
    if not target then return end

    if self:GetAttribute("scaled") then
        target:SetScale(1)
        self:SetAttribute("scaled", false)
    else
        target:SetScale(0.6)
        self:SetAttribute("scaled", true)
    end

    self:SetAttribute("ran", (self:GetAttribute("ran") or 0) + 1)
]==]

local SNIPPET_MOUSE = [==[
    self:SetAttribute("entered", (self:GetAttribute("entered") or 0) + 1)

    local target = self:GetFrameRef("target")
    if not target then return end

    if self:GetAttribute("nomouse") then
        target:EnableMouse(true)
        self:SetAttribute("nomouse", false)
    else
        target:EnableMouse(false)
        self:SetAttribute("nomouse", true)
    end

    self:SetAttribute("ran", (self:GetAttribute("ran") or 0) + 1)
]==]

--- 0.25 rather than 0 on purpose: a surface you can still see is a surface you
--- can still click to undo, and this probe is about whether the call lands.
local SNIPPET_ALPHA = [==[
    self:SetAttribute("entered", (self:GetAttribute("entered") or 0) + 1)

    local target = self:GetFrameRef("target")
    if not target then return end

    if self:GetAttribute("faded") then
        target:SetAlpha(1)
        self:SetAttribute("faded", false)
    else
        target:SetAlpha(0.25)
        self:SetAttribute("faded", true)
    end

    self:SetAttribute("ran", (self:GetAttribute("ran") or 0) + 1)
]==]

--- The same re-anchor, without a second frame.
---
--- park/unpark and ancestor anchor are the only two snippets that hand another
--- frame to SetPoint, and they are the only two whose buttons register nothing
--- at all -- not a click, not a snippet run -- while their immediate
--- neighbours register both, out of combat, at identical positions and sizes.
--- If this one works and those do not, the constraint is passing a second
--- frame handle, not moving a frame.
local TOGGLE_SELF_ANCHOR = [==[
    self:SetAttribute("entered", (self:GetAttribute("entered") or 0) + 1)
    local target = self:GetFrameRef("target")
    if not target then return end

    -- A stamp between every call, because a snippet that throws stops dead and
    -- everything after it is silent. entered/cleared/pointed/ran names the
    -- exact call that is refused instead of leaving a gap to be theorised over.
    target:ClearAllPoints()
    self:SetAttribute("cleared", (self:GetAttribute("cleared") or 0) + 1)

    if self:GetAttribute("selfmoved") then
        self:SetAttribute("selfmoved", false)
        target:SetPoint("TOPLEFT", 10, -24)
    else
        self:SetAttribute("selfmoved", true)
        target:SetPoint("TOPLEFT", 50, -64)
    end
    self:SetAttribute("pointed", (self:GetAttribute("pointed") or 0) + 1)

    self:SetAttribute("ran", (self:GetAttribute("ran") or 0) + 1)
]==]

--- Is any anchoring permitted, or none?
---
--- SetPoint is refused in both forms tested -- with a frame handle and against
--- the parent -- while ClearAllPoints succeeds, out of combat, on three
--- different buttons. This tries the two remaining shapes an anchor can take,
--- each stamped separately so the first refusal is named rather than hiding
--- the ones behind it. If SetAllPoints works, a protected frame can still be
--- made to fill its parent in combat, which is not nothing: it is the one
--- repositioning a Compact mode could still rely on.
local TOGGLE_ANCHOR_FORMS = [==[
    self:SetAttribute("entered", (self:GetAttribute("entered") or 0) + 1)
    local target = self:GetFrameRef("target")
    if not target then return end

    target:SetAllPoints()
    self:SetAttribute("allpoints", (self:GetAttribute("allpoints") or 0) + 1)

    target:SetPoint("CENTER")
    self:SetAttribute("centered", (self:GetAttribute("centered") or 0) + 1)

    self:SetAttribute("ran", (self:GetAttribute("ran") or 0) + 1)
]==]

--- Which of the two differences actually matters.
---
--- SetPoint("CENTER") works. SetPoint("TOPLEFT", 10, -24) does not, and neither
--- does the version with a frame handle. Two things separate them and only one
--- can be the cause:
---
---   offsets      the working call passes none, the failing ones pass numbers
---   ClearAllPoints  the failing ones call it first, the working one does not
---
--- The consequence is not small. If offsets are refused, a protected frame can
--- only be pinned to whole anchors and a Compact mode cannot nudge anything.
--- If ClearAllPoints is what poisons the handle, repositioning is fully
--- available in combat provided nothing clears first -- and "a protected frame
--- cannot be moved", which I have now said twice, is wrong.
---
--- Ordered so the first refusal is named: a snippet stops where it throws, so
--- the offset test has to come before anything clears.
local TOGGLE_ANCHOR_CAUSE = [==[
    self:SetAttribute("entered", (self:GetAttribute("entered") or 0) + 1)
    local target = self:GetFrameRef("target")
    if not target then return end

    target:SetPoint("CENTER", 40, -40)
    self:SetAttribute("offset", (self:GetAttribute("offset") or 0) + 1)

    target:ClearAllPoints()
    self:SetAttribute("cleared", (self:GetAttribute("cleared") or 0) + 1)

    target:SetPoint("CENTER")
    self:SetAttribute("afterclear", (self:GetAttribute("afterclear") or 0) + 1)

    self:SetAttribute("ran", (self:GetAttribute("ran") or 0) + 1)
]==]

--- The one form left, and the one that would be useful.
---
--- SetPoint("CENTER") and SetAllPoints() both run. SetPoint("CENTER", 40, -40)
--- throws on the offsets, before anything else in its snippet. So a point is
--- accepted and numbers after it are not.
---
--- That leaves anchoring to another frame with no offsets at all. If it works,
--- there is a whole architecture behind it: place invisible anchor frames
--- wherever a layout needs them, out of combat where offsets are free, then
--- snap a protected frame onto one of them during a fight with a single
--- offset-free call. A Compact mode could move things after all -- to
--- positions decided in advance, which is all it ever needed.
local TOGGLE_ANCHOR_FRAME = [==[
    self:SetAttribute("entered", (self:GetAttribute("entered") or 0) + 1)
    local target = self:GetFrameRef("target")
    local home = self:GetFrameRef("home")
    if not target or not home then return end

    target:SetPoint("TOPLEFT", home, "TOPLEFT")
    self:SetAttribute("toframe", (self:GetAttribute("toframe") or 0) + 1)

    -- Only reached if the above is allowed: are zero offsets still offsets?
    target:SetPoint("CENTER", 0, 0)
    self:SetAttribute("zerooffset", (self:GetAttribute("zerooffset") or 0) + 1)

    self:SetAttribute("ran", (self:GetAttribute("ran") or 0) + 1)
]==]

--- Re-parenting: the last route to a position that was chosen in advance.
---
--- Restricted SetPoint turns out to accept exactly one argument. A point, and
--- nothing after it -- no offsets, no relative frame. So a protected frame can
--- be pinned to one of its parent's nine anchor points, or made to fill it, and
--- that is the whole vocabulary.
---
--- But SetParent is in the method inventory for both the generic frame and the
--- action button, and has never been called. If it is permitted, the vocabulary
--- is enough after all: build empty slot frames out of combat, positioned to
--- the pixel wherever a layout wants them, and in combat move a protected frame
--- between slots and fill each one. Arbitrary positions, all decided before the
--- fight, reached with the two calls that are allowed during it.
local TOGGLE_REPARENT = [==[
    self:SetAttribute("entered", (self:GetAttribute("entered") or 0) + 1)
    local target = self:GetFrameRef("target")
    local slotA = self:GetFrameRef("slotA")
    local slotB = self:GetFrameRef("slotB")
    if not target or not slotA or not slotB then return end

    local slot = slotA
    if self:GetAttribute("inB") then
        self:SetAttribute("inB", false)
    else
        self:SetAttribute("inB", true)
        slot = slotB
    end

    target:SetParent(slot)
    self:SetAttribute("reparented", (self:GetAttribute("reparented") or 0) + 1)

    target:SetAllPoints()
    self:SetAttribute("filled", (self:GetAttribute("filled") or 0) + 1)

    self:SetAttribute("ran", (self:GetAttribute("ran") or 0) + 1)
]==]

--- The rescue. Shows everything the lab can hide, unconditionally, in one
--- click. It is the reason a destructive probe is safe to run at all, so it
--- takes no arguments, reads no state, and cannot be told not to.
local RESCUE = [==[
    self:SetAttribute("entered", (self:GetAttribute("entered") or 0) + 1)

    for _, name in ipairs(newtable("root", "ancestor", "action", "visual")) do
        local target = self:GetFrameRef(name)
        if target then
            target:Show()
            -- Show alone left an alpha-0 surface just as invisible as before,
            -- which made the one unconditional escape hatch conditional.
            target:SetAlpha(1)
        end
    end

    local action = self:GetFrameRef("action")
    local home = self:GetFrameRef("home")
    if action and home then
        action:ClearAllPoints()
        action:SetPoint("TOPLEFT", home, "TOPLEFT", 0, 0)
        action:SetWidth(NORMAL_W)
        action:SetHeight(NORMAL_H)
    end

    self:SetAttribute("ran", (self:GetAttribute("ran") or 0) + 1)
]==]

--- Substitutes the numbers a snippet needs into it.
---
--- Snippets are strings and cannot see upvalues, so the alternative is writing
--- the constants twice and letting them drift. Done here, once, where both
--- halves are visible together.
local function withNumbers(snippet)
    return (snippet
        :gsub("PARK_X_VALUE", tostring(PARK_X))
        :gsub("PARK_Y_VALUE", tostring(PARK_Y))
        :gsub("NORMAL_W", tostring(ACTION_W))
        :gsub("NORMAL_H", tostring(ACTION_H))
        :gsub("WIDE_W", tostring(ANC_W))
        :gsub("TALL_H", tostring(ANC_H)))
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

local function plainButton(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.16, 0.16, 0.22, 0.95)

    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.label:SetAllPoints()
    b.label:SetText(text)

    b:SetScript("OnEnter", function() bg:SetColorTexture(0.26, 0.26, 0.34, 0.95) end)
    b:SetScript("OnLeave", function() bg:SetColorTexture(0.16, 0.16, 0.22, 0.95) end)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

--- A secure handler button carrying one snippet.
---
--- Templates are never combined. Mixing a secure template with a button
--- template has silently dropped the secure OnLoad in this project before, and
--- the frame then looks fine and has no handler methods at all.
local function secureButton(name, parent, text, snippet, refs)
    local b = CreateFrame("Button", "InomrahsMISelfTestRunLab" .. name, parent,
        "SecureHandlerClickTemplate")
    b:SetSize(96, 20)
    b:RegisterForClicks("AnyUp")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.30, 0.20, 0.08, 0.95)

    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.label:SetAllPoints()
    b.label:SetText(text)

    for key, frame in pairs(refs or {}) do b:SetFrameRef(key, frame) end
    b:SetAttribute("_onclick", withNumbers(snippet))

    -- Two counters, deliberately. "ran" is the snippet's, written from the
    -- restricted side; "clicks" is this one, written from ordinary Lua. With
    -- only the first, a button that was never pressed and a snippet the client
    -- refused to run are the same number, and Stage 1 could not tell them
    -- apart for three of its results. With both, they never look alike.
    b.clicks = 0
    b:HookScript("OnClick", function(self)
        self.clicks = (self.clicks or 0) + 1
    end)
    return b
end

local function build()
    if built then return true end
    if InCombatLockdown() then return false, "combat" end

    ----------------------------------------------------------------------------
    -- The underlay, first and lowest.
    --
    -- Its whole job is to answer a question nothing else can: when the test
    -- surface above it is invisible, does a click land on the game or on the
    -- invisible frame? Without something underneath to catch the click, an
    -- alpha-zero frame that swallows input looks identical to one that lets it
    -- through.
    ----------------------------------------------------------------------------
    F.underlay = CreateFrame("Button", "InomrahsMISelfTestRunLabUnderlay", UIParent)
    F.underlay:SetFrameStrata("LOW")
    F.underlay:SetSize(ACTION_W, ACTION_H)
    F.underlay:RegisterForClicks("AnyUp")
    -- Anchored below, once the home marker exists. Its position has to be
    -- exactly where the action normally sits, and has to stay there when the
    -- action is parked away: the question every mouse probe asks is "what
    -- happens to a click at the place the button used to be".

    local ubg = F.underlay:CreateTexture(nil, "BACKGROUND")
    ubg:SetAllPoints()
    ubg:SetColorTexture(0.10, 0.35, 0.10, 0.85)
    F.underlay.label = F.underlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    F.underlay.label:SetAllPoints()
    F.underlay.label:SetText("UNDERLAY 0")

    F.underlay.count = 0
    F.underlay:SetScript("OnClick", function(self)
        self.count = self.count + 1
        self.label:SetText("UNDERLAY " .. self.count)
    end)

    ----------------------------------------------------------------------------
    -- The lab root and the protected hierarchy inside it.
    ----------------------------------------------------------------------------
    F.root = CreateFrame("Frame", "InomrahsMISelfTestRunLabRoot", UIParent)
    F.root:SetFrameStrata("MEDIUM")
    F.root:SetSize(ROOT_W, ROOT_H)
    F.root:SetPoint("CENTER", UIParent, "CENTER", 0, 40)

    local rbg = F.root:CreateTexture(nil, "BACKGROUND")
    rbg:SetAllPoints()
    rbg:SetColorTexture(0.06, 0.06, 0.10, 0.95)

    F.rootLabel = F.root:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    F.rootLabel:SetPoint("TOP", 0, -6)
    F.rootLabel:SetText("|cffffd200RunLab test surface|r")

    -- The page-like protected ancestor: same template production gives a page,
    -- so a result here is about the shape production would actually use.
    F.ancestor = CreateFrame("Frame", "InomrahsMISelfTestRunLabAncestor", F.root,
        "SecureHandlerBaseTemplate")
    F.ancestor:SetSize(ANC_W, ANC_H)
    F.ancestor:SetPoint("TOPLEFT", 10, -24)

    local abg = F.ancestor:CreateTexture(nil, "BACKGROUND")
    abg:SetAllPoints()
    abg:SetColorTexture(0.12, 0.12, 0.18, 0.95)

    -- Where the action lives when nothing has moved it. An empty anchor frame
    -- rather than a remembered offset, because a snippet can hold a frame
    -- reference and cannot hold a number it was told out of combat.
    F.home = CreateFrame("Frame", "InomrahsMISelfTestRunLabHome", F.ancestor)
    F.home:SetSize(ACTION_W, ACTION_H)
    F.home:SetPoint("TOPLEFT", 8, -8)

    -- Two empty slots, positioned to the pixel out of combat. Nothing draws
    -- them; their only job is to be somewhere exact that a snippet can name.
    F.slotA = CreateFrame("Frame", "InomrahsMISelfTestRunLabSlotA", F.ancestor)
    F.slotA:SetSize(ACTION_W, ACTION_H)
    F.slotA:SetPoint("TOPLEFT", 8, -8)

    F.slotB = CreateFrame("Frame", "InomrahsMISelfTestRunLabSlotB", F.ancestor)
    F.slotB:SetSize(ACTION_W / 2, ACTION_H)
    F.slotB:SetPoint("TOPRIGHT", -8, -48)

    -- Now the underlay can take its position from the one frame no probe moves.
    F.underlay:SetPoint("TOPLEFT", F.home, "TOPLEFT", 0, 0)

    F.action = CreateFrame("Button", "InomrahsMISelfTestRunLabAction", F.ancestor,
        "SecureActionButtonTemplate")
    F.action:SetSize(ACTION_W, ACTION_H)
    F.action:SetPoint("TOPLEFT", F.home, "TOPLEFT", 0, 0)
    F.action:RegisterForClicks("AnyUp", "AnyDown")
    F.action:SetAttribute("type", "macro")
    F.action:SetAttribute("macrotext", macroFor(1))

    -- The visual child: everything you can see about the action lives in here,
    -- so presentation can be taken away without touching the button. This is
    -- the shape a future Minimal would use if hiding the button itself turns
    -- out to kill its keybind.
    F.visual = CreateFrame("Frame", "InomrahsMISelfTestRunLabVisual", F.action)
    F.visual:SetAllPoints()
    local vbg = F.visual:CreateTexture(nil, "BACKGROUND")
    vbg:SetAllPoints()
    vbg:SetColorTexture(0.85, 0.55, 0.15, 0.95)
    F.visualLabel = F.visual:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    F.visualLabel:SetAllPoints()
    F.visualLabel:SetText("ACTION 1")

    ----------------------------------------------------------------------------
    -- A clipping viewport with its own action, for the clipped-out-of-view
    -- question. Separate from the main action so one probe cannot leave the
    -- other in a state it did not ask for.
    ----------------------------------------------------------------------------
    F.viewport = CreateFrame("ScrollFrame", "InomrahsMISelfTestRunLabViewport", F.root)
    F.viewport:SetSize(ANC_W, VIEW_H)
    F.viewport:SetPoint("BOTTOMLEFT", 10, 8)

    F.content = CreateFrame("Frame", "InomrahsMISelfTestRunLabContent", F.viewport)
    F.content:SetSize(ROOT_W - 20, 120)
    F.viewport:SetScrollChild(F.content)

    F.clipped = CreateFrame("Button", "InomrahsMISelfTestRunLabClipped", F.content,
        "SecureActionButtonTemplate")
    F.clipped:SetSize(ACTION_W, 22)
    F.clipped:SetPoint("TOPLEFT", 0, -60)          -- below the fold, so clipped
    F.clipped:RegisterForClicks("AnyUp", "AnyDown")
    F.clipped:SetAttribute("type", "macro")
    F.clipped:SetAttribute("macrotext", macroFor(2))

    local cbg = F.clipped:CreateTexture(nil, "BACKGROUND")
    cbg:SetAllPoints()
    cbg:SetColorTexture(0.20, 0.35, 0.60, 0.95)
    local clabel = F.clipped:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clabel:SetAllPoints()
    clabel:SetText("ACTION 2 (clipped)")

    ----------------------------------------------------------------------------
    -- The binding owner. One owner for everything Stage 1 arms, so cleanup is a
    -- single call and cannot half-happen. Stage 2 will want a second owner for
    -- mode keys, because ClearBindings is not selective and one owner holding
    -- both would delete page keys every time a mode key was re-applied.
    ----------------------------------------------------------------------------
    F.pager = CreateFrame("Frame", "InomrahsMISelfTestRunLabPager", UIParent,
        "SecureHandlerBaseTemplate")
    F.pager:Hide()

    ----------------------------------------------------------------------------
    -- The rescue layer. Parented to UIParent, never hidden, never moved, never
    -- resized, never alpha'd. Nothing in this file may take it away.
    ----------------------------------------------------------------------------
    F.rescueBar = CreateFrame("Frame", "InomrahsMISelfTestRunLabRescueBar", UIParent)
    F.rescueBar:SetFrameStrata("FULLSCREEN")
    F.rescueBar:SetSize(344, 78)
    F.rescueBar:SetPoint("TOP", UIParent, "TOP", 0, -40)

    local rescueBg = F.rescueBar:CreateTexture(nil, "BACKGROUND")
    rescueBg:SetAllPoints()
    rescueBg:SetColorTexture(0.35, 0.05, 0.05, 0.95)

    F.rescue = secureButton("Rescue", F.rescueBar, "RESTORE LAB", RESCUE, {
        root = F.root, ancestor = F.ancestor, action = F.action,
        visual = F.visual, home = F.home,
    })
    F.rescue:SetSize(112, 22)
    F.rescue:SetPoint("TOPLEFT", 6, -6)

    F.resetBtn = plainButton(F.rescueBar, "RESET LAB", 112, 22, function()
        Lab.Command("reset")
    end)
    F.resetBtn:SetPoint("TOPRIGHT", -6, -6)

    -- The command row. Every one of these has a slash command behind it and
    -- does nothing the slash command does not; they exist because a mistyped
    -- command falls through to the whole self-test and produces a report that
    -- looks exactly like a successful run. A button cannot be mistyped.
    F.cmdButtons = {}
    local commands = {
        { text = "PREFLIGHT", cmd = "preflight" },
        { text = "ARM",       cmd = "arm" },
        { text = "STATUS",    cmd = "status" },
        { text = "COPY",      cmd = "copy" },
    }
    for index, entry in ipairs(commands) do
        local b = plainButton(F.rescueBar, entry.text, 80, 22, function()
            Lab.Command(entry.cmd)
        end)
        b:SetPoint("TOPLEFT", 6 + (index - 1) * 84, -32)
        F.cmdButtons[index] = b
    end

    F.rescueNote = F.rescueBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    F.rescueNote:SetPoint("BOTTOM", 0, 4)
    F.rescueNote:SetText("|cffffaaaaRunLab — restore is always here|r")

    ----------------------------------------------------------------------------
    -- The secure operation buttons. One per operation, each with its own fixed
    -- snippet.
    --
    -- One button with a dispatch table would be tidier and wrong: choosing
    -- which operation to run would mean writing an attribute from insecure code
    -- during combat, which is the thing combat forbids. A button per operation
    -- needs no such write.
    ----------------------------------------------------------------------------
    F.ops = {}
    local function op(name, text, snippet, refs)
        local b = secureButton(name, F.root, text, snippet, refs)
        F.ops[#F.ops + 1] = { key = name:lower(), button = b, text = text }
        return b
    end

    op("OpRoot",   "hide/show root",     TOGGLE_SHOW, { target = F.root })
    op("OpAnc",    "hide/show ancestor", TOGGLE_SHOW, { target = F.ancestor })
    op("OpAction", "hide/show action",   TOGGLE_SHOW, { target = F.action })
    op("OpVisual", "hide/show visual",   TOGGLE_SHOW, { target = F.visual })
    op("OpPark",   "park/unpark",        TOGGLE_PARK, { target = F.action, home = F.home })
    op("OpSize",   "1x1 / normal",       TOGGLE_SIZE, { target = F.action })
    op("OpGeo",    "ancestor w/h",       TOGGLE_GEO,  { target = F.ancestor })
    op("OpAnchor", "ancestor anchor",    TOGGLE_ANCHOR, { target = F.ancestor, home = F.root })
    op("OpScale",  "ancestor scale",     SNIPPET_SCALE, { target = F.ancestor })
    op("OpMouse",  "root mouse off",     SNIPPET_MOUSE, { target = F.root })
    op("OpFade",   "root fade",          SNIPPET_ALPHA, { target = F.root })
    op("OpSelfAnc", "anchor, no ref",    TOGGLE_SELF_ANCHOR, { target = F.ancestor })
    op("OpForms",  "anchor forms",       TOGGLE_ANCHOR_FORMS, { target = F.ancestor })
    op("OpCause",  "anchor: which",      TOGGLE_ANCHOR_CAUSE, { target = F.ancestor })
    op("OpToFrame", "anchor: to frame",  TOGGLE_ANCHOR_FRAME,
        { target = F.action, home = F.home })
    op("OpReparent", "reparent to slot", TOGGLE_REPARENT,
        { target = F.action, slotA = F.slotA, slotB = F.slotB })

    for i, entry in ipairs(F.ops) do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        entry.button:SetSize(98, 18)
        entry.button:SetPoint("TOPLEFT", F.root, "TOPLEFT",
            6 + col * 102, -OPS_TOP + row * -OPS_ROW_H)
    end

    ----------------------------------------------------------------------------
    -- Baseline, captured once, from the client rather than from the constants
    -- above. Restoring to what was asked for and restoring to what the client
    -- actually produced are different, and the second is the one that matches.
    ----------------------------------------------------------------------------
    baseline = {
        rootW = width(F.root), rootH = height(F.root),
        ancW = width(F.ancestor), ancH = height(F.ancestor),
        actW = width(F.action), actH = height(F.action),
    }

    built = true
    return true
end

--------------------------------------------------------------------------------
-- Bindings
--
-- Override bindings owned by one lab frame. They cannot reach SavedVariables,
-- cannot alter a Blizzard binding, and cannot survive a reload -- that is how
-- override bindings work, not something arranged here. Cleanup is one call.
--------------------------------------------------------------------------------

local CHORDS = {
    { key = "CTRL-SHIFT-F12", what = "synthetic action 1", target = "action" },
    { key = "CTRL-SHIFT-F11", what = "synthetic action 2 (clipped)", target = "clipped" },
}

local function clearBindings()
    if not F.pager then return true end
    if InCombatLockdown() then return false end
    if type(ClearOverrideBindings) ~= "function" then return false end
    ClearOverrideBindings(F.pager)
    armed = false
    return true
end

local function armBindings()
    if InCombatLockdown() then return false, "combat" end
    if type(SetOverrideBindingClick) ~= "function" then return false, "no override API" end

    ClearOverrideBindings(F.pager)
    for _, chord in ipairs(CHORDS) do
        local button = F[chord.target]
        if button then
            SetOverrideBindingClick(F.pager, true, chord.key, button:GetName())
        end
    end
    armed = true
    return true
end

--- What the client says already answers to a chord, so the lab reports a
--- collision rather than quietly taking someone's key for the session.
local function existingBinding(chord)
    if type(GetBindingAction) ~= "function" then return nil end
    local ok, action = pcall(GetBindingAction, chord)
    if ok and type(action) == "string" and action ~= "" then return action end
    return nil
end

--------------------------------------------------------------------------------
-- Restoring
--
-- Ordinary code, run out of combat or when combat ends. It is deliberately not
-- a measurement: anything it fixes is recorded as "restored after combat", never
-- as the operation having succeeded.
--------------------------------------------------------------------------------

-- While a later stage is using the panel, Stage 1's own surface stays out of
-- the way. Without this its restore -- which runs every time combat ends --
-- would put a second window back on top of the one under test, mid-run.
local hibernating = false

function Lab.Hibernate(on)
    hibernating = on and true or false
    if hibernating and F.root then pcall(function() F.root:Hide() end) end
    return hibernating
end

local function restoreBaseline()
    if not built then return end

    for _, key in ipairs({ "root", "ancestor", "action", "visual", "viewport",
                           "underlay", "rescueBar" }) do
        local frame = F[key]
        if frame then
            pcall(function()
                if not (hibernating and key == "root") then frame:Show() end
                frame:SetAlpha(1)
                frame:EnableMouse(true)
            end)
        end
    end

    pcall(function()
        -- A re-parented action button stays re-parented until something says
        -- otherwise, and every later measurement would be taken in the wrong
        -- place without this.
        F.action:SetParent(F.ancestor)
        F.action:ClearAllPoints()
        F.action:SetPoint("TOPLEFT", F.home, "TOPLEFT", 0, 0)
        F.action:SetWidth(baseline.actW or ACTION_W)
        F.action:SetHeight(baseline.actH or ACTION_H)

        F.ancestor:ClearAllPoints()
        F.ancestor:SetPoint("TOPLEFT", F.root, "TOPLEFT", 10, -24)
        F.ancestor:SetWidth(baseline.ancW or ANC_W)
        F.ancestor:SetHeight(baseline.ancH or ANC_H)

        F.viewport:SetVerticalScroll(0)
    end)

    -- The snippets keep their own idea of which way each toggle is pointing.
    -- Left alone it would disagree with the frames after a reset, and the next
    -- click would appear to do nothing.
    for _, entry in ipairs(F.ops or {}) do
        pcall(function()
            entry.button:SetAttribute("parked", false)
            entry.button:SetAttribute("small", false)
            entry.button:SetAttribute("narrow", false)
            entry.button:SetAttribute("moved", false)
        end)
    end
end

--------------------------------------------------------------------------------
-- The step panel
--
-- One instruction at a time. Seven phases of combat testing held in the
-- player's head is how results come back with gaps in them.
--
-- A step advances either because the lab observed the thing it was waiting for
-- or because the player said they did it. Those are different: the observation
-- is evidence, the acknowledgement is not, and only the observation is ever
-- written into a result.
--------------------------------------------------------------------------------

local steps, stepIndex = {}, 0
local watching = false
local stepMode = nil

-- A sequence handed in by a later stage. While one is set, reset re-drives it
-- rather than rebuilding Stage 1's, which would silently swap the run out from
-- under whoever is halfway through it.
local externalSteps, externalRestore = nil, nil

local function currentStep() return steps[stepIndex] end

local function stopWatching()
    watching = false
    if F.step then F.step:SetScript("OnUpdate", nil) end
end

local function paintStep()
    if not F.step then return end
    local step = currentStep()

    if not step then
        F.step.title:SetText("|cff44ff44RunLab — sequence complete|r")
        F.step.body:SetText("Leave combat, then run |cffffd200/imitest runlab copy|r "
            .. "and send the report back.")
        F.step.next:Hide()
        if F.step.skip then F.step.skip:Hide() end
        return
    end

    -- Skip is on every step, from the moment it opens. It appeared only after
    -- a 90 second timeout, then only on steps that declared a state to check,
    -- which meant the steps most likely to be unsatisfiable -- the restores --
    -- were the ones that made you sit and wait for permission to move on.
    if F.step.skip then F.step.skip:Show() end
    F.step.title:SetText(("|cffffd200STEP %d / %d|r   %s")
        :format(stepIndex, #steps, step.phase or ""))
    F.step.body:SetText(step.text or "")
    F.step.next:SetShown(step.manual == true)
    F.step.next.label:SetText(step.buttonText or "I did this")
end

local function advance()
    stopWatching()
    stepIndex = stepIndex + 1

    local step = currentStep()
    if step and step.enter then pcall(step.enter) end
    paintStep()

    -- Only a step that can be observed gets a watcher, and only while it is the
    -- current step. Nothing here polls when the lab is idle.
    if step and step.observe then
        watching = true
        local elapsed, waited = 0, 0
        F.step:SetScript("OnUpdate", function(_, delta)
            if not watching then return end
            elapsed = elapsed + (delta or 0)
            waited = waited + (delta or 0)
            if elapsed < 0.2 then return end
            elapsed = 0

            local done, why = step.observe()
            if done then
                if step.done then pcall(step.done) end
                advance()
            elseif waited > (step.timeout or 120) then
                -- A step that measures counters knows more about what happened
                -- than "nothing observed" does. Its own record is written even
                -- when it never advanced: the snippet ran, or it did not, and
                -- that is the whole question for these steps.
                if step.recordOnTimeout and step.done then
                    pcall(step.done)
                else
                    record({
                        capability = step.capability or ("step " .. stepIndex),
                        context = "combat", trigger = "waiting for the player",
                        conclusion = "INCONCLUSIVE — nothing observed within "
                            .. tostring(step.timeout or 120) .. " seconds",
                        note = why or "",
                    })
                end
                stopWatching()
                F.step.body:SetText((step.text or "")
                    .. "\n\n|cffff6666Timed out. Press Retry, or /imitest runlab report.|r")
                F.step.next:Show()
                F.step.next.label:SetText("Retry step")
                if F.step.skip then F.step.skip:Show() end
                step.manual = true
                step.retry = true
            end
        end)
    end
end

local function buildStepPanel()
    if F.step then return F.step end

    -- On UIParent, not on the lab root: the root is one of the things the
    -- sequence hides, and instructions that vanish at the moment the test gets
    -- interesting are worse than none.
    local f = CreateFrame("Frame", "InomrahsMISelfTestRunLabStep", UIParent)
    f:SetFrameStrata("FULLSCREEN")
    f:SetSize(430, 96)
    f:SetPoint("TOP", UIParent, "TOP", 0, -100)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.04, 0.07, 1)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 10, -8)

    f.body = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.body:SetPoint("TOPLEFT", 10, -28)
    f.body:SetPoint("TOPRIGHT", -10, -28)
    f.body:SetJustifyH("LEFT")
    f.body:SetJustifyV("TOP")
    f.body:SetWordWrap(true)

    f.next = plainButton(f, "I did this", 110, 20, function()
        local step = currentStep()
        if step and step.retry then
            step.retry, step.manual = nil, nil
            stepIndex = stepIndex - 1
            advance()
            return
        end
        if step and step.done then pcall(step.done) end
        advance()
    end)
    f.next:SetPoint("BOTTOMRIGHT", -10, 8)

    -- A step that cannot be satisfied used to offer only Retry, which re-ran
    -- the same step forever. Skipping records an honest INCONCLUSIVE and moves
    -- on, so one stuck question does not cost the rest of the sequence.
    f.skip = plainButton(f, "Skip step", 90, 20, function()
        local step = currentStep()
        if step and step.recordOnTimeout and step.done then
            step.retry, step.manual = nil, nil
            pcall(step.done)
            stopWatching()
            advance()
            return
        end
        if step then
            step.retry, step.manual = nil, nil
            record({
                capability = step.capability or ("step " .. stepIndex),
                -- inCombat() is declared further down the file and would be a
                -- nil global from inside this closure.
                context = InCombatLockdown() and "combat" or "out of combat",
                trigger = "skipped by the player",
                conclusion = "INCONCLUSIVE — step skipped",
            })
        end
        stopWatching()
        advance()
    end)
    f.skip:SetPoint("BOTTOMRIGHT", -126, 8)
    f.skip:Hide()

    F.step = f
    return f
end

--------------------------------------------------------------------------------
-- Probes
--
-- Insecure ones run from an ordinary button and are honest about it: they are
-- measuring whether ordinary code is allowed to do a thing during combat, which
-- is exactly the question for alpha.
--------------------------------------------------------------------------------

local function inCombat() return InCombatLockdown() == true end

--- Runs an insecure operation and records what actually happened to the frame,
--- never whether the call returned.
local function insecureProbe(name, frame, operation, read, requested, apply)
    local before = read(frame)
    local ok, err = pcall(apply)
    local after = read(frame)

    local moved = (type(before) == "number" and type(after) == "number")
        and not approximately(before, after, 0.001)
        or (before ~= after)

    -- If it already held the requested value, a refusal and a successful no-op
    -- are indistinguishable. Reporting that as "NO -- observed refusal" is a
    -- confident wrong answer, which is the one thing this report must not do.
    local alreadyThere = (type(before) == "number" and type(requested) == "number")
        and approximately(before, requested, 0.001)
        or (before == requested)

    return record({
        capability = name,
        context = inCombat() and "combat" or "out of combat",
        trigger = "insecure Lua from an ordinary button",
        target = frame and frame:GetName() or "?",
        operation = operation,
        before = fmt(before), requested = fmt(requested), after = fmt(after),
        err = (not ok) and tostring(err) or nil,
        conclusion = moved and "YES — observed"
            or (alreadyThere
                and "INCONCLUSIVE — it already held the requested value, so a "
                    .. "refusal and a successful no-op look identical"
                or "NO — observed refusal"),
    })
end

--- What a restricted handle actually offers, per handle type. Kept apart on
--- purpose: assuming a scroll frame's handle looks like a plain frame's is the
--- shape of mistake this whole exercise exists to stop.
local INVENTORY = [==[
    local target = self:GetFrameRef("target")
    local found = ""
    if target then
        for _, name in ipairs(newtable(NAMES)) do
            if target[name] then found = found .. name .. " " end
        end
    end
    self:SetAttribute("inventory", found)
]==]

local GENERIC_METHODS = {
    "Show", "Hide", "IsShown", "SetWidth", "SetHeight", "GetWidth", "GetHeight",
    "SetPoint", "GetPoint", "ClearAllPoints", "SetAllPoints", "SetAlpha",
    "GetAlpha", "SetScale", "GetScale", "SetShown", "SetParent", "GetParent",
    "EnableMouse", "IsMouseEnabled", "SetMouseClickEnabled", "IsMouseClickEnabled",
    "SetMouseMotionEnabled", "IsMouseMotionEnabled", "SetClipsChildren",
    "SetClampedToScreen", "IsClampedToScreen", "SetAttribute", "GetAttribute",
    "GetFrameRef",
}

local SCROLL_METHODS = {
    "SetVerticalScroll", "GetVerticalScroll", "GetVerticalScrollRange",
    "GetScrollChild", "SetScrollChild", "UpdateScrollChildRect",
    "SetHorizontalScroll", "SetPoint", "ClearAllPoints", "SetHeight",
}

local HEADER_METHODS = {
    "Show", "Hide", "IsShown", "SetWidth", "SetHeight", "SetPoint",
    "ClearAllPoints", "SetAttribute", "GetAttribute", "SetFrameRef",
    "GetFrameRef", "ClearBindings", "SetBindingClick", "SetBinding",
}

local function inventory(label, target, names)
    if InCombatLockdown() then
        record({ capability = "restricted methods: " .. label,
                 conclusion = "INCONCLUSIVE — must be probed out of combat" })
        return
    end
    if type(SecureHandlerExecute) ~= "function" then
        record({ capability = "restricted methods: " .. label,
                 conclusion = "NOT AVAILABLE — SecureHandlerExecute is absent" })
        return
    end

    local header = F.inventoryHeader
    if not header then
        header = CreateFrame("Frame", "InomrahsMISelfTestRunLabInv", UIParent,
            "SecureHandlerBaseTemplate")
        header:Hide()
        F.inventoryHeader = header
    end
    if type(header.SetFrameRef) ~= "function" then
        record({ capability = "restricted methods: " .. label,
                 conclusion = "NOT AVAILABLE — SecureHandlerBaseTemplate did not apply" })
        return
    end

    local quoted = {}
    for _, name in ipairs(names) do quoted[#quoted + 1] = ("%q"):format(name) end

    header:SetFrameRef("target", target)
    local ok, err = pcall(SecureHandlerExecute, header,
        (INVENTORY:gsub("NAMES", table.concat(quoted, ", "))))

    local found = ok and (header:GetAttribute("inventory") or "") or ""
    local missing = {}
    for _, name in ipairs(names) do
        if not found:find(name .. " ", 1, true) then missing[#missing + 1] = name end
    end

    record({
        capability = "restricted methods: " .. label,
        context = "out of combat", trigger = "SecureHandlerExecute",
        target = target and target:GetName() or "?",
        after = found ~= "" and found or "nothing",
        note = #missing > 0 and ("absent: " .. table.concat(missing, " ")) or "all present",
        err = (not ok) and tostring(err) or nil,
        conclusion = ok and "YES — observed" or "INCONCLUSIVE — the probe did not run",
    })
end

--------------------------------------------------------------------------------
-- The guided sequence
--------------------------------------------------------------------------------

local function firedSince(which, mark) return (fired[which] or 0) > mark end

--- Builds one "press the key, did the action fire" step.
---
--- `which` selects the action: 1 is the ordinary button, 2 the clipped one in
--- the viewport, each with its own key, its own counter and its own frame. It
--- was hardcoded to 1, so the clipped step told the reader to press F11, F11
--- correctly incremented counter 2, and the step sat watching counter 1 until
--- it timed out -- turning the one question that step exists to answer into an
--- INCONCLUSIVE no matter what the client actually did.
--- `expect` is the state the step is asking about: {text=, check=}. Without it
--- a step measures whatever happens to be on screen, so forgetting to click the
--- hide button first produced a confident YES for "the key works while hidden"
--- measured against a button that was never hidden. A wrong answer here is worse
--- than no answer, because nothing downstream would question it.
local function actionStep(phase, capability, text, prepare, restore, which, expect)
    which = which or 1
    local mark, before
    local chord = CHORDS[which]
    local function target() return which == 2 and F.clipped or F.action end
    local function ready()
        if not expect then return true end
        local ok, result = pcall(expect.check)
        return ok and result == true
    end
    local warned = false
    return {
        phase = phase,
        capability = capability,
        text = text,
        timeout = 90,
        enter = function()
            if prepare then pcall(prepare) end
            mark = fired[which] or 0
            local frame = target()
            before = {
                shown = shown(frame), visible = visible(frame),
                alpha = alpha(frame), w = width(frame), h = height(frame),
                left = left(frame), top = top(frame),
            }
        end,
        observe = function()
            if not inCombat() then
                return false, "combat ended"
            end
            if not ready() then
                -- Re-mark, so a press made while the state was wrong is not
                -- counted once the state becomes right.
                mark = fired[which] or 0
                if not warned and F.step then
                    warned = true
                    F.step.body:SetText((text or "") .. "\n\n|cffff8800Not yet: "
                        .. (expect.text or "the state this step needs is not set")
                        .. ".|r")
                    -- Offered immediately. Making someone wait out 90 seconds
                    -- for permission to move on is a worse kind of stuck.
                    if F.step.skip then F.step.skip:Show() end
                end
                return false, "the state this step needs was never set: "
                    .. (expect.text or "?")
            end
            if warned and F.step then
                warned = false
                F.step.body:SetText((text or "") .. "\n\n|cff44ff44Ready — press the key.|r")
            end
            return firedSince(which, mark)
        end,
        done = function()
            record({
                capability = capability,
                context = inCombat() and "combat" or "combat ended before measuring",
                trigger = "override key " .. (chord and chord.key or "?"),
                target = "SecureActionButtonTemplate",
                operation = "press the bound key",
                before = ("shown %s, visible %s, alpha %s, %sx%s")
                    :format(tri(before.shown), tri(before.visible),
                            fmt(before.alpha), fmt(before.w), fmt(before.h)),
                execBefore = mark, execAfter = fired[which],
                conclusion = firedSince(which, mark)
                    and "YES — observed" or "NO — observed refusal",
            })
            if restore then pcall(restore) end
        end,
    }
end

--- The follow-up run: the questions Stage 1 left open, and nothing else.
---
--- Named rather than rebuilt. A second hand-written sequence would be a second
--- thing to keep right, and the first time it drifted from the real one the
--- report would still look convincing.
local FOLLOWUP = {
    ["secure Hide on the visual-only child"] = true,
    ["action key with only the visual child hidden"] = true,
    ["restore: the decoration is visible again"] = true,
    ["secure re-anchor of the action button"] = true,
    ["action key while the button is parked off screen"] = true,
    ["restore: the button is back in place"] = true,
    ["secure width and height on a protected ancestor"] = true,
    ["secure re-anchor of a protected ancestor"] = true,
    ["secure SetScale on a protected ancestor"] = true,
    ["secure EnableMouse(false) on the lab root"] = true,
    ["secure SetAlpha on the lab root"] = true,
}

local function buildSteps(mode)
    steps = {}
    local function add(step) steps[#steps + 1] = step end

    ----------------------------------------------------------------------------
    -- Phase 0 — prove the evidence mechanism before trusting it.
    ----------------------------------------------------------------------------

    -- The sequence used to open on "press the key", with a 120 second clock,
    -- before anything had bound that key. Reading the preflight output was
    -- enough to time it out, and the first thing the lab did was fail at a
    -- step that could not have succeeded. It waits now.
    add({
        phase = "setup",
        text = "Press |cffffd200PREFLIGHT|r on the red bar, then |cffffd200ARM|r.\n"
            .. "Nothing else works until the test keys are armed.\n"
            .. "This step moves on by itself the moment they are.",
        timeout = 3600,
        observe = function()
            if armed then return true end
            return false, "the test keys were never armed"
        end,
    })

    add({
        phase = "evidence, out of combat",
        capability = "/run counter, out of combat",
        text = "Press |cffffd200" .. CHORDS[1].key .. "|r once, out of combat.\n"
            .. "This proves the counter works before anything relies on it.",
        timeout = 120,
        enter = function() Lab.mark = fired[1] or 0 end,
        observe = function() return firedSince(1, Lab.mark) end,
        done = function()
            record({
                capability = "/run counter, out of combat",
                context = "out of combat", trigger = "override key " .. CHORDS[1].key,
                target = "SecureActionButtonTemplate", operation = "press the bound key",
                execBefore = Lab.mark, execAfter = fired[1],
                conclusion = "YES — observed",
            })
        end,
    })

    add({
        phase = "combat",
        manual = true,
        buttonText = "I am in combat",
        text = "|cffff8800Attack a training dummy.|r Do not run this during a real key.\n"
            .. "A dummy keeps you in combat and cannot die or kill you.\n"
            .. "Press the button below once you are in combat.",
    })

    add(actionStep("evidence, in combat", "/run counter, in combat",
        "Still in combat, press |cffffd200" .. CHORDS[1].key .. "|r again.\n"
        .. "Nothing is hidden yet. This is the baseline every later result is "
        .. "measured against."))

    ----------------------------------------------------------------------------
    -- Phase 1 — alpha, and the invisible hitbox.
    ----------------------------------------------------------------------------
    add(actionStep("alpha", "action key at root alpha 0",
        "The test surface is now |cffffd200invisible|r (alpha 0), but nothing was "
        .. "hidden or moved.\nPress " .. CHORDS[1].key .. ".",
        function()
            insecureProbe("insecure SetAlpha(0) on lab root", F.root,
                "SetAlpha(0)", alpha, 0, function() F.root:SetAlpha(0) end)
        end))

    add({
        phase = "alpha",
        capability = "alpha-0 root intercepts the mouse",
        manual = true,
        buttonText = "I clicked there",
        text = "The surface is still invisible. |cffffd200Click where the orange "
            .. "ACTION button was|r — just above the middle of the screen.\n"
            .. "We are finding out whether an invisible frame steals the click.",
        enter = function()
            Lab.mark = fired[1] or 0
            Lab.underMark = F.underlay.count
        end,
        done = function()
            local actionFired = firedSince(1, Lab.mark)
            local underFired = F.underlay.count > Lab.underMark

            local conclusion
            if actionFired then
                conclusion = "YES — observed: the invisible frame took the click"
            elseif underFired then
                conclusion = "NO — observed: the click passed through to what was beneath"
            else
                conclusion = "INCONCLUSIVE — neither the action nor the underlay saw it"
            end

            record({
                capability = "alpha-0 root intercepts the mouse",
                context = inCombat() and "combat" or "out of combat",
                trigger = "physical mouse click",
                target = "SecureActionButtonTemplate under an alpha-0 ancestor",
                operation = "click where the button was",
                execBefore = Lab.mark, execAfter = fired[1],
                underlayBefore = Lab.underMark, underlayAfter = F.underlay.count,
                intercept = actionFired and "intercepted" or (underFired and "click-through"
                    or "neither"),
                conclusion = conclusion,
            })
        end,
    })

    add({
        phase = "alpha",
        capability = "mouse can be disabled during combat",
        manual = true,
        buttonText = "I clicked there again",
        text = "Now the lab has tried to |cffffd200turn the mouse off|r on the "
            .. "invisible surface.\nClick the same spot once more.\n"
            .. "If the green UNDERLAY counter goes up, clicks are getting through.",
        enter = function()
            insecureProbe("insecure EnableMouse(false) on lab root", F.root,
                "EnableMouse(false)",
                function(f) return tri(f.IsMouseEnabled and f:IsMouseEnabled()) end,
                "no", function() F.root:EnableMouse(false) end)
            Lab.mark = fired[1] or 0
            Lab.underMark = F.underlay.count
        end,
        done = function()
            local actionFired = firedSince(1, Lab.mark)
            local underFired = F.underlay.count > Lab.underMark
            record({
                capability = "alpha 0 plus mouse disabled: click-through",
                context = inCombat() and "combat" or "out of combat",
                trigger = "physical mouse click",
                target = "lab root with mouse disabled",
                operation = "click where the button was",
                execBefore = Lab.mark, execAfter = fired[1],
                underlayBefore = Lab.underMark, underlayAfter = F.underlay.count,
                intercept = actionFired and "intercepted" or (underFired and "click-through"
                    or "neither"),
                conclusion = underFired and "YES — observed"
                    or (actionFired and "NO — observed refusal"
                        or "INCONCLUSIVE — neither observer fired"),
            })
        end,
    })

    add(actionStep("alpha", "action key with alpha 0 and mouse disabled",
        "Press |cffffd200" .. CHORDS[1].key .. "|r once more.\n"
        .. "The key must still work even with the mouse turned off — that is the "
        .. "combination a keybind-first mode would use."))

    add(actionStep("alpha", "action key after alpha restore",
        "Everything is |cffffd200visible again|r. Press " .. CHORDS[1].key .. ".\n"
        .. "This checks the invisible state was not one-way.",
        function()
            pcall(function() F.root:EnableMouse(true) end)
            insecureProbe("insecure SetAlpha(1) restore on lab root", F.root,
                "SetAlpha(1)", alpha, 1, function() F.root:SetAlpha(1) end)

            -- Several transitions, because a mode you can toggle once is not a
            -- mode. A future Minimal would be switched repeatedly, mid-fight.
            local stuck = false
            for _, value in ipairs({ 0, 1, 0.35, 1 }) do
                pcall(function() F.root:SetAlpha(value) end)
                if not approximately(alpha(F.root), value, 0.02) then stuck = true end
            end
            record({
                capability = "repeated alpha transitions restore cleanly",
                context = inCombat() and "combat" or "out of combat",
                trigger = "insecure Lua", target = "lab root",
                operation = "alpha 0 -> 1 -> 0.35 -> 1",
                after = fmt(alpha(F.root)),
                conclusion = stuck and "NO — observed refusal" or "YES — observed",
            })
        end))

    add(actionStep("alpha", "action key with the visual child alpha 0",
        "Only the |cffffd200decoration|r of the button is invisible now; the button "
        .. "itself is untouched.\nPress " .. CHORDS[1].key .. ".",
        function()
            insecureProbe("insecure SetAlpha(0) on the visual-only child", F.visual,
                "SetAlpha(0)", alpha, 0, function() F.visual:SetAlpha(0) end)
        end,
        function() pcall(function() F.visual:SetAlpha(1) end) end))

    add({
        phase = "alpha",
        capability = "insecure SetScale on a protected ancestor",
        manual = true,
        buttonText = "Next",
        text = "Checking whether |cffffd200scale|r can be changed in combat.\n"
            .. "Nothing for you to do — press Next.",
        enter = function()
            insecureProbe("insecure SetScale on a protected ancestor", F.ancestor,
                "SetScale(0.6)",
                function(f) return num(f.GetScale, f) end, 0.6,
                function() F.ancestor:SetScale(0.6) end)
            pcall(function() F.ancestor:SetScale(1) end)
        end,
    })

    ----------------------------------------------------------------------------
    -- Phase 2 — hidden-state strategies, each through a secure hardware click.
    ----------------------------------------------------------------------------
    local function secureOpStep(phase, capability, buttonText, instruction, opKey)
        return {
            phase = phase,
            manual = true,
            buttonText = "I clicked it",
            capability = capability,
            text = instruction,
            enter = function()
                local button = nil
                for _, entry in ipairs(F.ops) do
                    if entry.key == opKey then button = entry.button end
                end
                Lab.opButton = button
                Lab.opRan = button and (tonumber(button:GetAttribute("ran")) or 0) or 0
                Lab.opClicks = button and (button.clicks or 0) or 0
                Lab.opEntered = ranCount(opKey, "entered")
            end,
            done = function()
                local button = Lab.opButton
                local ran = button and (tonumber(button:GetAttribute("ran")) or 0) or 0
                local clicks = button and (button.clicks or 0) or 0
                local entered = ranCount(opKey, "entered")

                -- The insecure click counter is not proof of anything on its
                -- own: a hooked OnClick does not fire when the script it hooks
                -- errors first, so a snippet that threw looked exactly like a
                -- button nobody pressed. This lab reported "the button was
                -- never clicked" three times about buttons that were clicked.
                -- "entered" is stamped inside the snippet, before anything can
                -- fail, and it is what says the click arrived.
                local arrived = entered > Lab.opEntered or clicks > Lab.opClicks

                local conclusion
                if ran > Lab.opRan then
                    conclusion = "YES — observed"
                elseif arrived then
                    conclusion = "NO — observed refusal: the snippet was entered "
                        .. "and did not reach the end"
                else
                    conclusion = "INCONCLUSIVE — the snippet was never entered"
                end

                record({
                    capability = capability .. " (the snippet ran)",
                    context = inCombat() and "combat" or "out of combat",
                    trigger = "hardware click on SecureHandlerClickTemplate",
                    target = buttonText,
                    before = Lab.opRan, after = ran,
                    note = ("entered %d -> %d, clicks %d -> %d")
                        :format(Lab.opEntered, entered, Lab.opClicks, clicks),
                    conclusion = conclusion,
                })
            end,
        }
    end

    add(secureOpStep("hidden states", "secure Hide on the lab root", "hide/show root",
        "In the lab window, click |cffffd200hide/show root|r.\n"
        .. "The whole surface should vanish. RESTORE LAB at the top always brings "
        .. "it back.", "oproot"))

    add(actionStep("hidden states", "action key with the root hidden",
        "The root is hidden. Press |cffffd200" .. CHORDS[1].key .. "|r.\n"
        .. "This is the question that decides whether a keybind-first mode can "
        .. "exist with nothing on screen.",
        nil, nil, 1,
        { text = "the root is not hidden — click hide/show root",
          check = function() return shown(F.root) == false end }))

    add({
        phase = "hidden states",
        manual = true,
        buttonText = "I clicked RESTORE LAB",
        capability = "secure restore of a hidden root during combat",
        text = "Click the red |cffffd200RESTORE LAB|r button at the top of the screen.\n"
            .. "The lab should come back while you are still in combat.",
        enter = function() Lab.rescueRan = F.rescue:GetAttribute("ran") or 0 end,
        done = function()
            record({
                capability = "secure restore of a hidden root during combat",
                context = inCombat() and "combat" or "out of combat",
                trigger = "hardware click on the external rescue button",
                target = "lab root", operation = "Show from a snippet",
                before = "hidden", after = tri(shown(F.root)),
                conclusion = shown(F.root) == true and "YES — observed"
                    or "NO — observed refusal",
            })
        end,
    })

    -- One click per step, always. These used to read "click X to bring it back,
    -- then click Y" -- two actions, one button, one measurement. Clicking only
    -- the first and pressing "I clicked it" left the next step measuring a
    -- state that was never set, and the mistake only surfaced two steps later.
    local function restoreStep(label, opLabel, check)
        return {
            phase = "hidden states",
            capability = "restore: " .. label,
            text = "Click |cffffd200" .. opLabel .. "|r to bring it back.\n"
                .. "This step moves on by itself once " .. label .. ".",
            timeout = 90,
            observe = function()
                local ok, result = pcall(check)
                if ok and result == true then return true end
                return false, "still waiting for: " .. label
            end,
        }
    end

    local function opButton(opKey)
        for _, entry in ipairs(F.ops or {}) do
            if entry.key == opKey then return entry.button end
        end
        return nil
    end

    local function ranCount(opKey, attribute)
        local button = opButton(opKey)
        if not button then return 0 end
        local ok, value = pcall(button.GetAttribute, button, attribute or "ran")
        return (ok and tonumber(value)) or 0
    end

    -- Asking the snippet whether it thinks it parked the button was the wrong
    -- question twice over: the answer comes back from the restricted side and
    -- may not be readable, and it is the snippet's belief rather than the
    -- client's behaviour. These read the frame instead, using the same values
    -- runlab status prints without trouble.
    --
    -- An unreadable position is unknown, not parked.
    --
    -- It counted as parked, on the theory that an unanchored frame is what a
    -- refused SetPoint leaves behind. That theory was wrong -- the click had
    -- never reached the button -- and the cost was the worst kind of result:
    -- "action key while the button is parked off screen: YES" recorded against
    -- a button sitting at 160x34 in its usual place. A step that cannot read
    -- the state must stall and be skipped, never guess and pass.
    local function awayFromHome()
        local here, home = left(F.action), left(F.home)
        if here == nil or home == nil then return nil end
        return math.abs(here - home) > 50
    end

    local function atHome()
        local away = awayFromHome()
        if away == nil then return nil end
        return away == false
    end

    local function tiny()
        local w = width(F.action)
        if w == nil then return nil end
        return w <= 2
    end

    local function normalSize()
        local small = tiny()
        if small == nil then return nil end
        return small == false
    end

    add(secureOpStep("hidden states", "secure Hide on the protected ancestor",
        "hide/show ancestor",
        "Click |cffffd200hide/show ancestor|r. Only the inner panel should go.",
        "opanc"))
    add(actionStep("hidden states", "action key with the ancestor hidden",
        "The ancestor is hidden. Press |cffffd200" .. CHORDS[1].key .. "|r.",
        nil, nil, 1,
        { text = "the ancestor is not hidden — click hide/show ancestor",
          check = function() return shown(F.ancestor) == false end }))

    add(restoreStep("the ancestor is visible again", "hide/show ancestor",
        function() return shown(F.ancestor) == true end))

    add(secureOpStep("hidden states", "secure Hide on the action button",
        "hide/show action",
        "Click |cffffd200hide/show action|r. The orange button should go, and "
        .. "nothing else.", "opaction"))
    add(actionStep("hidden states", "action key with the action button hidden",
        "The button itself is hidden. Press |cffffd200" .. CHORDS[1].key .. "|r.\n"
        .. "Production's toggle key proves a secure *handler* still answers when "
        .. "hidden. Whether an action button does is a different question.",
        nil, nil, 1,
        { text = "the action button is not hidden — click hide/show action",
          check = function() return shown(F.action) == false end }))

    add(restoreStep("the action button is visible again", "hide/show action",
        function() return shown(F.action) == true end))

    add(secureOpStep("hidden states", "secure Hide on the visual-only child",
        "hide/show visual",
        "Click |cffffd200hide/show visual|r. Only the button's decoration goes; "
        .. "the button stays.", "opvisual"))
    add(actionStep("hidden states", "action key with only the visual child hidden",
        "The button is shown; only its decoration is gone.\n"
        .. "Press |cffffd200" .. CHORDS[1].key .. "|r.",
        nil, nil, 1,
        { text = "the decoration is not hidden — click hide/show visual",
          check = function() return shown(F.visual) == false end }))

    add(restoreStep("the decoration is visible again", "hide/show visual",
        function() return shown(F.visual) == true end))

    add(secureOpStep("hidden states", "secure re-anchor of the action button",
        "park/unpark",
        "Click |cffffd200park/unpark|r to move the button far off screen.",
        "oppark"))
    add(actionStep("hidden states", "action key while the button is parked off screen",
        "The button is parked off screen. Press |cffffd200" .. CHORDS[1].key .. "|r.",
        nil, nil, 1,
        { text = "the button is not parked — click park/unpark",
          check = awayFromHome }))

    add(restoreStep("the button is back in place", "park/unpark", atHome))

    add(secureOpStep("hidden states", "secure resize of the action button to 1x1",
        "1x1 / normal",
        "Click |cffffd2001x1 / normal|r to shrink the button to one pixel.",
        "opsize"))
    add(actionStep("hidden states", "action key while the button is 1x1",
        "The button is one pixel. Press |cffffd200" .. CHORDS[1].key .. "|r.",
        nil, nil, 1,
        { text = "the button is not 1x1 — click 1x1 / normal",
          check = tiny }))

    add(restoreStep("the button is its normal size again", "1x1 / normal", normalSize))

    add(actionStep("hidden states", "action key on a clipped button",
        "Press |cffffd200" .. CHORDS[2].key .. "|r — the second action, which is "
        .. "inside a viewport and scrolled out of sight.\n"
        .. "It is shown, but clipped away.",
        nil, nil, 2))

    ----------------------------------------------------------------------------
    -- Phase 3 — geometry on the protected ancestor: the Compact question.
    ----------------------------------------------------------------------------
    add({
        phase = "geometry",
        capability = "secure width and height on a protected ancestor",
        timeout = 90,
        recordOnTimeout = true,
        text = "Click |cffffd200ancestor w/h|r in the lab window.\n"
            .. "This is the shape a denser Run layout would need in combat.\n"
            .. "This step moves on by itself once it sees the click.",
        enter = function()
            Lab.geoW, Lab.geoH = width(F.ancestor), height(F.ancestor)
            Lab.geoBtn = opButton("opgeo")
            Lab.geoRan = ranCount("opgeo")
            Lab.geoClicks = Lab.geoBtn and (Lab.geoBtn.clicks or 0) or 0
            Lab.geoEntered = ranCount("opgeo", "entered")
        end,
        -- Waits for the click, not for you to say you clicked. A step that
        -- advanced on trust could not report whether the operation was refused
        -- or the button was never pressed, and it reported both as the same.
        observe = function()
            if ranCount("opgeo", "entered") > (Lab.geoEntered or 0) then return true end
            local clicks = Lab.geoBtn and (Lab.geoBtn.clicks or 0) or 0
            if clicks > Lab.geoClicks then return true end
            return false, "the ancestor w/h snippet was never entered"
        end,
        done = function()
            local ran = ranCount("opgeo")
            local entered = ranCount("opgeo", "entered")
            local clicks = Lab.geoBtn and (Lab.geoBtn.clicks or 0) or 0
            local nowW, nowH = width(F.ancestor), height(F.ancestor)
            local changed = not approximately(Lab.geoW, nowW)
                or not approximately(Lab.geoH, nowH)

            record({
                capability = "secure width and height on a protected ancestor",
                context = inCombat() and "combat" or "out of combat",
                trigger = "hardware click on SecureHandlerClickTemplate",
                target = "SecureHandlerBaseTemplate containing a SecureActionButton",
                operation = "SetWidth and SetHeight from a snippet",
                before = ("%s x %s"):format(fmt(Lab.geoW), fmt(Lab.geoH)),
                -- The snippet halves the ancestor's own size. This line
                -- recomputed it from ROOT_H - 90, which stopped being the
                -- ancestor's height when the window was re-laid out, and the
                -- report then claimed a request that was never made: 104 next
                -- to an "after" of 71 that had in fact been honoured exactly.
                requested = ("%s x %s"):format(fmt(ANC_W / 2), fmt(ANC_H / 2)),
                after = ("%s x %s"):format(fmt(nowW), fmt(nowH)),
                note = ("snippet ran %d -> %d, entered %d -> %d, clicks %d -> %d")
                    :format(Lab.geoRan, ran, Lab.geoEntered or 0, entered,
                            Lab.geoClicks, clicks),
                conclusion = (ran > Lab.geoRan and changed) and "YES — observed"
                    or (ran > Lab.geoRan and "NO — the snippet ran and nothing moved")
                    or ((entered > (Lab.geoEntered or 0) or clicks > Lab.geoClicks)
                        and "NO — observed refusal: the snippet was entered and "
                            .. "did not reach the end")
                    or "INCONCLUSIVE — the snippet was never entered",
            })
        end,
    })

    add({
        phase = "geometry",
        capability = "secure re-anchor of a protected ancestor",
        timeout = 90,
        recordOnTimeout = true,
        text = "Click |cffffd200ancestor anchor|r.\n"
            .. "The inner panel should shift down and right.\n"
            .. "This step moves on by itself once it sees the click.",
        enter = function()
            Lab.ancLeft, Lab.ancTop = left(F.ancestor), top(F.ancestor)
            Lab.ancBtn = opButton("opanchor")
            Lab.ancRan = ranCount("opanchor")
            Lab.ancClicks = Lab.ancBtn and (Lab.ancBtn.clicks or 0) or 0
            Lab.ancEntered = ranCount("opanchor", "entered")
        end,
        observe = function()
            if ranCount("opanchor", "entered") > (Lab.ancEntered or 0) then return true end
            local clicks = Lab.ancBtn and (Lab.ancBtn.clicks or 0) or 0
            if clicks > Lab.ancClicks then return true end
            return false, "the ancestor anchor snippet was never entered"
        end,
        done = function()
            local ran = ranCount("opanchor")
            local entered = ranCount("opanchor", "entered")
            local clicks = Lab.ancBtn and (Lab.ancBtn.clicks or 0) or 0
            local nowLeft, nowTop = left(F.ancestor), top(F.ancestor)
            local moved = not approximately(Lab.ancLeft, nowLeft)
                or not approximately(Lab.ancTop, nowTop)

            record({
                capability = "secure re-anchor of a protected ancestor",
                context = inCombat() and "combat" or "out of combat",
                trigger = "hardware click on SecureHandlerClickTemplate",
                target = "SecureHandlerBaseTemplate containing a SecureActionButton",
                operation = "ClearAllPoints and SetPoint from a snippet",
                before = ("left %s top %s"):format(fmt(Lab.ancLeft), fmt(Lab.ancTop)),
                after = ("left %s top %s"):format(fmt(nowLeft), fmt(nowTop)),
                note = ("snippet ran %d -> %d, entered %d -> %d, clicks %d -> %d")
                    :format(Lab.ancRan, ran, Lab.ancEntered or 0, entered,
                            Lab.ancClicks, clicks),
                conclusion = (ran > Lab.ancRan and moved) and "YES — observed"
                    or (ran > Lab.ancRan and "NO — the snippet ran and nothing moved")
                    or ((entered > (Lab.ancEntered or 0) or clicks > Lab.ancClicks)
                        and "NO — observed refusal: the snippet was entered and "
                            .. "did not reach the end")
                    or "INCONCLUSIVE — the snippet was never entered",
            })
        end,
    })

    ----------------------------------------------------------------------------
    -- Phase 4 — the same operations, from a snippet instead.
    --
    -- Every one of these was refused to insecure code in combat, and every one
    -- appears in the restricted method inventory. Listed and permitted are not
    -- the same thing, and guessing which way it falls is how a mode gets built
    -- on an assumption that only breaks mid-fight.
    ----------------------------------------------------------------------------
    local function snippetOpStep(capability, opLabel, opKey, targetName, operation, read)
        local button, ran0, clicks0, entered0, before
        return {
            phase = "snippet route",
            capability = capability,
            timeout = 90,
            recordOnTimeout = true,
            text = "Click |cffffd200" .. opLabel .. "|r in the lab window.\n"
                .. "Ordinary code was refused this in combat. A snippet may not be.\n"
                .. "This step moves on by itself once it sees the click.",
            enter = function()
                button = opButton(opKey)
                ran0 = ranCount(opKey)
                clicks0 = button and (button.clicks or 0) or 0
                entered0 = ranCount(opKey, "entered")
                before = read()
            end,
            observe = function()
                if ranCount(opKey, "entered") > entered0 then return true end
                local clicks = button and (button.clicks or 0) or 0
                if clicks > clicks0 then return true end
                return false, "the " .. opLabel .. " snippet was never entered"
            end,
            done = function()
                local ran = ranCount(opKey)
                local clicks = button and (button.clicks or 0) or 0
                local after = read()

                record({
                    capability = capability,
                    context = inCombat() and "combat" or "out of combat",
                    trigger = "hardware click on SecureHandlerClickTemplate",
                    target = targetName,
                    operation = operation,
                    before = before, after = after,
                    note = ("snippet ran %d -> %d, entered %d -> %d, clicks %d -> %d")
                        :format(ran0, ran, entered0, ranCount(opKey, "entered"),
                                clicks0, clicks),
                    conclusion = (ran > ran0 and before ~= after) and "YES — observed"
                        or (ran > ran0 and "NO — the snippet ran and nothing changed")
                        or ((ranCount(opKey, "entered") > entered0 or clicks > clicks0)
                            and "NO — observed refusal: the snippet was entered and "
                                .. "did not reach the end")
                        or "INCONCLUSIVE — the snippet was never entered",
                })
            end,
        }
    end

    add(snippetOpStep("secure SetScale on a protected ancestor", "ancestor scale",
        "opscale", "SecureHandlerBaseTemplate containing a SecureActionButton",
        "SetScale(0.6) from a snippet",
        function() return fmt(num(F.ancestor.GetScale, F.ancestor)) end))

    add(snippetOpStep("secure EnableMouse(false) on the lab root", "root mouse off",
        "opmouse", "lab root", "EnableMouse(false) from a snippet",
        function()
            local ok, value = pcall(function() return F.root:IsMouseEnabled() end)
            return ok and tri(value) or "unreadable"
        end))

    add(snippetOpStep("secure SetAlpha on the lab root", "root fade",
        "opfade", "lab root", "SetAlpha(0.25) from a snippet",
        function() return fmt(alpha(F.root)) end))

    ----------------------------------------------------------------------------
    -- Phase 5 — the scroll probes that already exist, run at last.
    -- (marker: the follow-up filter runs after everything below is added)
    ----------------------------------------------------------------------------
    add({
        phase = "scrolling",
        manual = true,
        buttonText = "I ran it",
        text = "Type |cffffd200/imitest combat|r now, while still in combat.\n"
            .. "That runs the scroll probes that have been in the self-test since "
            .. "0.8 and have never been run in a fight.\n"
            .. "Then press the button below.",
    })

    add({
        phase = "done",
        manual = true,
        buttonText = "Finish",
        text = "|cff44ff44That is everything in combat.|r\n"
            .. "Leave combat, then run |cffffd200/imitest runlab copy|r and send "
            .. "the whole report back.",
        done = function()
            restoreBaseline()
        end,
    })

    -- The follow-up is the full sequence with everything already answered
    -- taken out, so its steps are literally the same objects the full run
    -- uses. The setup, combat and closing steps stay because a sequence with
    -- no keys armed, nobody in combat and no ending is not a sequence.
    if mode == "followup" then
        local keep = {}
        for _, step in ipairs(steps) do
            local wanted = step.phase == "setup" or step.phase == "combat"
                or step.phase == "done"
                or (step.capability and FOLLOWUP[step.capability])
            if wanted then keep[#keep + 1] = step end
        end
        steps = keep
    end
end

--------------------------------------------------------------------------------
-- Combat watching
--
-- A step measured while combat has quietly ended is not a combat measurement.
-- Rather than let that pass unnoticed, the sequence pauses and says so.
--------------------------------------------------------------------------------

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:RegisterEvent("PLAYER_LOGOUT")
watcher:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGOUT" then
        pcall(clearBindings)
        return
    end

    if event ~= "PLAYER_REGEN_ENABLED" then return end
    if not built then return end

    local step = currentStep()
    if step and watching and step.capability then
        record({
            capability = step.capability,
            context = "combat ended mid-step",
            conclusion = "INCONCLUSIVE — combat ended before the hardware action "
                .. "was measured; re-enter combat and retry this step",
        })
        stopWatching()
        if F.step then
            F.step.body:SetText((step.text or "")
                .. "\n\n|cffff6666Combat ended. Get back on the dummy and press "
                .. "Retry.|r")
            F.step.next:Show()
            F.step.next.label:SetText("Retry step")
            step.manual, step.retry = true, true
        end
    end

    -- Anything a probe left behind goes back to baseline the moment it is safe,
    -- after the result has been recorded rather than before it.
    restoreBaseline()
end)

--------------------------------------------------------------------------------
-- The report
--------------------------------------------------------------------------------

local function detailLines()
    local out = {}
    local function line(...) out[#out + 1] = string.format(...) end

    line("== Run Capability Lab — Stage 1 ==")

    -- Guarded like every other client read here. A report that throws while
    -- being written is a report nobody gets, and the report is the deliverable.
    local okBuild, build = pcall(function() return select(4, GetBuildInfo()) end)
    line("client build %s", okBuild and tostring(build) or "unreadable")

    local reader = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    line("addon %s, self-test %s",
        tostring(reader and reader("InomrahsMythicInstructions", "Version") or "?"),
        tostring(reader and reader("InomrahsMISelfTest", "Version") or "?"))
    line("armed chords: %s", armed and (CHORDS[1].key .. ", " .. CHORDS[2].key) or "none")
    line("")

    for _, r in ipairs(results) do
        line("[%s] %s", (r.conclusion or "INCONCLUSIVE"):match("^%a[%a%s]*") or "?",
            r.capability or "?")
        if r.context then line("  context: %s", r.context) end
        if r.trigger then line("  trigger: %s", r.trigger) end
        if r.target then line("  target: %s", r.target) end
        if r.operation then line("  operation: %s", r.operation) end
        if r.before ~= nil then line("  before: %s", tostring(r.before)) end
        if r.requested ~= nil then line("  requested: %s", tostring(r.requested)) end
        if r.after ~= nil then line("  after: %s", tostring(r.after)) end
        if r.execBefore ~= nil then
            line("  action executions: %s -> %s", tostring(r.execBefore),
                tostring(r.execAfter))
        end
        if r.underlayBefore ~= nil then
            line("  underlay clicks: %s -> %s", tostring(r.underlayBefore),
                tostring(r.underlayAfter))
        end
        if r.intercept then line("  mouse: %s", r.intercept) end
        if r.note then line("  note: %s", r.note) end
        if r.err then line("  error: %s", r.err) end
        line("  conclusion: %s", r.conclusion or "INCONCLUSIVE")
        line("")
    end

    return out
end

local MATRIX = {
    { "Evidence", nil },
    { "Visible SecureActionButton /run counter OOC", "/run counter, out of combat" },
    { "Visible SecureActionButton /run counter combat", "/run counter, in combat" },
    { "Alpha / input", nil },
    { "Insecure root SetAlpha(0) effect in combat", "insecure SetAlpha(0) on lab root" },
    { "Action key works at root alpha 0", "action key at root alpha 0" },
    { "Root alpha 0 intercepts mouse", "alpha-0 root intercepts the mouse" },
    { "Mouse can be disabled in combat", "insecure EnableMouse(false) on lab root" },
    { "Alpha 0 + mouse-disabled click-through", "alpha 0 plus mouse disabled: click-through" },
    { "Alpha 0 + mouse-disabled action key", "action key with alpha 0 and mouse disabled" },
    { "Visual-child alpha can change in combat", "insecure SetAlpha(0) on the visual-only child" },
    { "Action usable when visual child alpha 0", "action key with the visual child alpha 0" },
    { "Repeated alpha transitions restore cleanly", "repeated alpha transitions restore cleanly" },
    { "Insecure SetScale on protected ancestor", "insecure SetScale on a protected ancestor" },
    { "Visibility strategies", nil },
    { "Action key with root inherited-hidden", "action key with the root hidden" },
    { "Action key with page ancestor hidden", "action key with the ancestor hidden" },
    { "Action key with action button hidden", "action key with the action button hidden" },
    { "Action key with visual child hidden only", "action key with only the visual child hidden" },
    { "Action key while parked off screen", "action key while the button is parked off screen" },
    { "Action key while resized to 1x1", "action key while the button is 1x1" },
    { "Action key while clipped out of view", "action key on a clipped button" },
    { "Geometry", nil },
    { "Secure width/height on protected ancestor", "secure width and height on a protected ancestor" },
    { "Secure re-anchor protected ancestor", "secure re-anchor of a protected ancestor" },
    { "Secure Hide on protected ancestor", "secure Hide on the protected ancestor (the snippet ran)" },
    { "Hidden root restored in combat", "secure restore of a hidden root during combat" },
}

local function matrixLines()
    local out = {}
    out[#out + 1] = "== Stage 1 Architecture Summary =="
    out[#out + 1] = ""
    for _, entry in ipairs(MATRIX) do
        if not entry[2] then
            out[#out + 1] = ""
            out[#out + 1] = entry[1]
            out[#out + 1] = ("-"):rep(#entry[1])
        else
            out[#out + 1] = ("%-52s %s"):format(entry[1], yesNo(entry[2]))
        end
    end

    out[#out + 1] = ""
    out[#out + 1] = "Safety"
    out[#out + 1] = "------"
    out[#out + 1] = ("%-52s %s"):format("Production frames mutated by lab", "NO")
    out[#out + 1] = ("%-52s %s"):format("Production SavedVariables modified", "NO")
    out[#out + 1] = ("%-52s %s"):format("Lab rescue remained available",
        shown(F.rescueBar) == true and "YES" or "CHECK")
    out[#out + 1] = ("%-52s %s"):format("Lab override bindings still armed",
        armed and "YES — run /imitest runlab release" or "NO")
    out[#out + 1] = ("%-52s %s"):format("Lab holds keyboard focus", "NO")
    out[#out + 1] = ""
    out[#out + 1] = "== Still to run =="
    out[#out + 1] = "The v0.8 combat scroll probes are reported by /imitest combat,"
    out[#out + 1] = "under the Combat section. Paste that report alongside this one."
    return out
end

--- Extra summary blocks, registered by later stages.
---
--- Stage 2 lives in its own file but must appear in the same report: two
--- reports for one run is how half a result gets pasted back. It registers a
--- function here rather than printing its own.
Lab.summaries = Lab.summaries or {}

function Lab.Summary(fn)
    Lab.summaries[#Lab.summaries + 1] = fn
end

local function report(full)
    local out = {}
    for _, l in ipairs(matrixLines()) do out[#out + 1] = l end
    out[#out + 1] = ""

    for _, fn in ipairs(Lab.summaries) do
        local ok, lines = pcall(fn)
        if ok and type(lines) == "table" then
            for _, l in ipairs(lines) do out[#out + 1] = l end
            out[#out + 1] = ""
        end
    end

    if full then
        for _, l in ipairs(detailLines()) do out[#out + 1] = l end
    else
        out[#out + 1] = "== Anything not a plain YES =="
        out[#out + 1] = ""
        for _, r in ipairs(results) do
            if not (r.conclusion or ""):match("^YES") then
                out[#out + 1] = ("[%s] %s"):format(r.conclusion or "?", r.capability or "?")
            end
        end
        out[#out + 1] = ""
        out[#out + 1] = "Run /imitest runlab copy for the full detail."
    end

    return table.concat(out, "\n")
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local HELP = {
    "RunLab — Stage 1. Measures what combat allows, on synthetic frames only.",
    "",
    "  /imitest runlab setup      build it (out of combat)",
    "  /imitest runlab preflight  check it before you start",
    "  /imitest runlab arm        turn the test keys on",
    "  /imitest runlab status     where things stand",
    "  /imitest runlab report     the summary",
    "  /imitest runlab copy       everything, to paste back",
    "  /imitest runlab reset      back to baseline",
    "  /imitest runlab release    emergency: unbind, restore, let go",
    "",
    "runlab followup  the short run: only what Stage 1 left open",
    "runlab clicks    which operation buttons receive clicks, and where",
    "",
    "runlab stage2    build Stage 2: pages x modes x hidden root",
    "runlab stage2 preflight | arm | status | reset | release",
    "runlab goto <n>   resume at step n, out of combat",
    "",
    "The lab guides you a step at a time once it is set up.",
    "Use a training dummy. Never during a real key.",
    "",
    "PREFLIGHT, ARM, STATUS and COPY are also buttons on the red bar at the",
    "top of the screen, so none of them has to be typed.",
}

--------------------------------------------------------------------------------
-- What a later stage may borrow
--
-- Deliberately small, and deliberately the same objects Stage 1 uses: the step
-- panel with its timeout, skip and combat-recovery behaviour, and the one
-- record/report path. A second panel would be a second thing to debug, and a
-- second evidence system is exactly what the Stage 2 brief forbids.
--------------------------------------------------------------------------------

--- Write a result into the shared report.
function Lab.Record(entry) return record(entry) end

--- Is the lab built? Stage 2 needs the rescue bar and panel to exist.
function Lab.Built() return built end

--- Hand the panel a sequence to drive. `restore` is called by reset/release.
function Lab.Drive(list, restore)
    if type(list) ~= "table" or #list == 0 then return false end
    externalSteps, externalRestore = list, restore
    steps = list
    stepIndex = 0
    advance()
    if F.step then F.step:Show() end
    if F.rescueBar then F.rescueBar:Show() end
    return true
end

--- Give the panel back to Stage 1's own sequence.
function Lab.Release()
    externalSteps, externalRestore = nil, nil
end

function Lab.Command(arg)
    arg = (arg or ""):lower():match("^%s*(.-)%s*$")

    -- Stage 2 owns everything after "stage2". It loads after this file, so it
    -- is reached through the global: Stage 1 must keep working without it.
    local stage2Arg = (arg == "stage2") and "" or arg:match("^stage2%s+(.*)$")
    if stage2Arg then
        local s2 = _G.InomrahsMISelfTestStage2
        if type(s2) ~= "table" or type(s2.Command) ~= "function" then
            say("Stage 2 is not loaded.")
            return
        end
        s2.Command(stage2Arg)
        return
    end

    if arg == "" or arg == "help" then
        beginCapture()
        for _, line in ipairs(HELP) do say("%s", line) end
        endCapture("help")
        return
    end

    if arg == "setup" then
        if InCombatLockdown() then
            say("|cffff4444out of combat only.|r nothing was built.")
            return
        end
        local ok = build()
        if not ok then say("could not build the lab.") return end

        restoreBaseline()
        buildStepPanel()
        results = {}
        fired[1], fired[2] = 0, 0
        F.underlay.count = 0
        F.underlay.label:SetText("UNDERLAY 0")
        stepMode = nil
        buildSteps(stepMode)
        stepIndex = 0
        advance()

        F.step:Show()
        F.rescueBar:Show()
        F.root:Show()
        say("built. run |cffffd200/imitest runlab preflight|r next.")
        return
    end

    if not built then
        say("run |cffffd200/imitest runlab setup|r first.")
        return
    end

    -- The short run: only what Stage 1 could not answer. Results already
    -- recorded are kept, so one report can carry both runs.
    if arg == "followup" then
        if InCombatLockdown() then say("|cffff4444out of combat only.|r") return end
        restoreBaseline()
        stepMode = "followup"
        buildSteps(stepMode)
        stepIndex = 0
        advance()
        F.step:Show()
        F.rescueBar:Show()
        F.root:Show()
        say("follow-up sequence: |cffffd200%d steps|r. anything already "
            .. "recorded is kept.", #steps)
        say("press |cffffd200PREFLIGHT|r then |cffffd200ARM|r, then follow the panel.")
        return
    end

    if arg == "preflight" then
        if InCombatLockdown() then say("|cffff4444out of combat only.|r") return end

        beginCapture()
        local missing = {}
        for _, key in ipairs({ "root", "ancestor", "action", "visual", "viewport",
                               "clipped", "underlay", "rescue", "rescueBar",
                               "pager", "step" }) do
            if not F[key] then missing[#missing + 1] = key end
        end
        say("frames: %s", #missing == 0 and "all built"
            or ("MISSING " .. table.concat(missing, ", ")))

        say("action macro: %s",
            (F.action:GetAttribute("macrotext") or ""):find("RunLabFired", 1, true)
                and "prepared" or "MISSING")
        say("rescue is outside the lab root: %s",
            F.rescue:GetParent() == F.rescueBar and "yes" or "NO")

        for _, chord in ipairs(CHORDS) do
            local existing = existingBinding(chord.key)
            say("%s -> %s%s", chord.key, chord.what,
                existing and ("  |cffff8800(currently bound to " .. existing .. ")|r") or "")
        end

        -- The inventories, per handle type. Absence here is information, not a
        -- failure: it tells Stage 2 which architectures are not worth writing.
        inventory("generic frame", F.root, GENERIC_METHODS)
        inventory("SecureActionButtonTemplate", F.action, GENERIC_METHODS)
        inventory("secure header", F.ancestor, HEADER_METHODS)
        inventory("ScrollFrame", F.viewport, SCROLL_METHODS)
        say("restricted method inventories recorded — see the report.")
        endCapture("preflight")
        return
    end

    if arg == "arm" then
        if InCombatLockdown() then say("|cffff4444out of combat only.|r") return end
        local ok, why = armBindings()
        if not ok then say("could not arm: %s", tostring(why)) return end

        beginCapture()
        say("TEST KEYS ARMED — these are temporary.")
        for _, chord in ipairs(CHORDS) do
            say("  |cffffd200%s|r  %s", chord.key, chord.what)
        end
        say("they vanish on /reload, and on |cffffd200/imitest runlab release|r.")
        say("now get on a |cffffd200training dummy|r and follow the panel.")
        endCapture("arm")
        return
    end

    -- Resuming. A run that dies at step 24 of 28 should not cost the 23 steps
    -- that already worked: copy the report, reinstall, and start again where it
    -- stopped. Everything before the target is recorded as not attempted, so a
    -- resumed report can never be mistaken for a complete one.
    local target = arg:match("^goto%s+(%d+)$")
    if target then
        if InCombatLockdown() then say("|cffff4444out of combat only.|r") return end
        target = tonumber(target)
        if not target or target < 1 or target > #steps then
            say("step numbers run 1 to %d.", #steps)
            return
        end
        restoreBaseline()
        stepIndex = target - 1
        for index = 1, stepIndex do
            local step = steps[index]
            if step and step.capability then
                record({
                    capability = step.capability,
                    context = "not attempted",
                    trigger = "skipped by |cffffd200runlab goto|r",
                    conclusion = "INCONCLUSIVE — not attempted in this run",
                })
            end
        end
        advance()
        say("resuming at step %d of %d. steps 1-%d are marked not attempted.",
            target, #steps, stepIndex)
        return
    end

    -- Which operation buttons are actually receiving clicks, and where they
    -- are. Three of them recorded no clicks in a run where their neighbours
    -- recorded one each, and no theory about the layout explains that pattern.
    -- Guessing again is worse than measuring: click each button once, out of
    -- combat, and read this.
    if arg == "clicks" then
        beginCapture()
        say("click each operation button once, then run this again.")
        for _, entry in ipairs(F.ops or {}) do
            local button = entry.button
            local l, t = left(button), top(button)
            local w, h = width(button), height(button)
            local function attr(name)
                local ok, value = pcall(button.GetAttribute, button, name)
                return (ok and tonumber(value)) or 0
            end
            -- entered says the snippet began; ran says it reached the end.
            -- entered 1 with ran 0 is a snippet that threw partway, which is a
            -- different fact from a click that never arrived, and the two were
            -- indistinguishable before.
            say("%-18s entered %s cleared %s pointed %s allpoints %s centered %s "
                .. "offset %s afterclear %s ran %s",
                entry.text,
                tostring(attr("entered")), tostring(attr("cleared")),
                tostring(attr("pointed")), tostring(attr("allpoints")),
                tostring(attr("centered")), tostring(attr("offset")),
                tostring(attr("afterclear")), tostring(attr("ran")))
            if entry.key == "optoframe" then
                say("    %-14s toframe %s  zerooffset %s",
                    "", tostring(attr("toframe")), tostring(attr("zerooffset")))
            elseif entry.key == "opreparent" then
                say("    %-14s reparented %s  filled %s",
                    "", tostring(attr("reparented")), tostring(attr("filled")))
            end
        end
        endCapture("which buttons receive clicks")
        return
    end

    if arg == "status" then
        beginCapture()
        say("combat: %s | step %d/%d", inCombat() and "yes" or "no", stepIndex, #steps)
        say("root shown %s, visible %s, alpha %s",
            tri(shown(F.root)), tri(visible(F.root)), fmt(alpha(F.root)))
        say("action shown %s, %s x %s at %s,%s",
            tri(shown(F.action)), fmt(width(F.action)), fmt(height(F.action)),
            fmt(left(F.action)), fmt(top(F.action)))
        say("action fired %d and %d | underlay clicks %d",
            fired[1] or 0, fired[2] or 0, F.underlay.count or 0)
        say("bindings armed: %s | rescue present: %s",
            armed and "yes" or "no", F.rescue and "yes" or "no")
        endCapture("status")
        return
    end

    if arg == "report" then
        if API.Report then API.Report(report(false)) else print(report(false)) end
        return
    end

    if arg == "copy" then
        if API.Report then API.Report(report(true)) else print(report(true)) end
        return
    end

    if arg == "reset" then
        if InCombatLockdown() then
            say("|cffff4444out of combat only|r — but RESTORE LAB works mid-fight.")
            return
        end
        restoreBaseline()
        if externalRestore then pcall(externalRestore) end
        stepIndex = 0
        if externalSteps then steps = externalSteps else buildSteps(stepMode) end
        advance()
        say("back to baseline. results kept — /imitest runlab copy still works.")
        return
    end

    if arg == "release" then
        stopWatching()
        local cleared = clearBindings()
        restoreBaseline()
        if F.step then F.step:Hide() end

        if API.ReleaseKeyboard then pcall(API.ReleaseKeyboard) end
        say("bindings cleared: %s | frames restored | keyboard: %s",
            cleared and "yes" or "IN COMBAT — try again after",
            API.KeyboardReport and API.KeyboardReport() or "not checked")
        return
    end

    say("unknown: %s. try |cffffd200/imitest runlab help|r.", arg)
end

--- For the acceptance checks and for anything that needs to know the lab is
--- here without reaching into it.
function Lab.Built() return built end
function Lab.Armed() return armed end
function Lab.Results() return results end
