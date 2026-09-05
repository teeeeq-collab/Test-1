--------------------------------------------------------------------------------
-- A stub of the WoW API, just deep enough to construct the addon's frames.
--
-- It cannot test behaviour: nothing here knows what a secure button is. What it
-- does catch is the class of bug that syntax checking misses and that only
-- surfaces on someone else's machine — a function called before its local is
-- declared, a widget method that does not exist, a nil field on a frame. The
-- Edit rewrite shipped exactly that kind of fault, and this is the cheapest
-- thing that would have caught it.
--------------------------------------------------------------------------------

local M = {}

local function noop() end

local function newFrame(frameType, name, parent, template)
    local f = {
        frameType = frameType, name = name, parent = parent, template = template,
        shown = true, attributes = {}, scripts = {}, points = {},
        width = 600, height = 300, scale = 1, alpha = 1,
    }

    local mt = {}
    mt.__index = function(t, key)
        -- Widget methods are PascalCase; the addon's own fields are lowercase.
        -- So an unmodelled method becomes a no-op and chained calls keep
        -- working, while an unset field returns nil exactly as it would in
        -- game. Returning a function for everything made `frame.headers` look
        -- truthy and produced a failure the real client would never see.
        if type(key) == "string" and key:match("^%u") then
            return function(self, ...) return self end
        end
        return nil
    end

    -- Methods whose return value the addon actually reads.
    f.IsShown       = function(self) return self.shown end
    -- Own state and every ancestor's, which is what "on screen" actually means.
    -- Without this the stub reports a child of a hidden frame as visible, and
    -- an orphaned button left behind by a pool looks fine to it.
    f.IsVisible     = function(self)
        local node = self
        while node do
            if not node.shown then return false end
            node = node.parent
        end
        return true
    end
    -- Showing and hiding run the scripts, because code hangs real work off
    -- them: releasing the keyboard when a box goes away is done in OnHide, and
    -- a stub that only flips a flag says that work happened when it did not.
    local function setShown(self, value)
        value = not not value
        if self.shown == value then return end
        self.shown = value
        local script = self.scripts and self.scripts[value and "OnShow" or "OnHide"]
        if script then script(self) end
    end
    f.Show          = function(self) setShown(self, true) end
    f.Hide          = function(self) setShown(self, false) end
    f.SetShown      = function(self, v) setShown(self, v) end
    f.GetWidth      = function(self) return self.width end
    f.GetHeight     = function(self) return self.height end
    -- Flagged as well as stored, so the geometry resolver can tell a size that
    -- was asked for from the default it was born with. A font string sized by
    -- its text is a very different rectangle from a 600x300 default.
    f.SetHeight     = function(self, h) self.height, self.heightSet = h, true end
    f.SetWidth      = function(self, w) self.width, self.widthSet = w, true end
    f.SetSize       = function(self, w, h)
        self.width, self.height = w, h
        self.widthSet, self.heightSet = true, true
    end
    f.GetScale      = function(self) return self.scale end
    f.SetScale      = function(self, v) self.scale = v end
    f.SetAlpha      = function(self, v) self.alpha = v end
    f.GetAlpha      = function(self) return self.alpha end
    f.GetPoint      = function(self) return "CENTER", nil, "CENTER", 0, 0 end
    -- Recorded, so a test can ask what a frame is anchored to. GetPoint stays
    -- the fixed answer above: the addon reads it only to save the window's
    -- position, and that wants a plausible tuple rather than this list.
    -- SetPoint has several shapes: (point), (point, x, y), (point, relTo),
    -- (point, relTo, relPoint) and (point, relTo, relPoint, x, y). Told apart
    -- by type, because recording (point, x, y) as though the x offset were the
    -- frame to anchor to makes every descendant unresolvable — which is exactly
    -- what it did.
    f.SetPoint      = function(self, point, a, b, c, d)
        local rel, relPoint, x, y
        if a == nil or type(a) == "number" then
            x, y = a, b
        else
            rel = a
            if type(b) == "number" then x, y = b, c else relPoint, x, y = b, c, d end
        end
        self.points[#self.points + 1] =
            { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
    end
    f.ClearAllPoints = function(self) self.points = {} end
    -- Recorded like any other anchor, so the geometry resolver can follow it.
    f.SetAllPoints  = function(self, target)
        self.points = { { point = "ALL", rel = target } }
    end
    f.SetWordWrap   = function(self, v) self.wordWrap = v end
    -- Enough of a font model to answer "does this text fit on one line", which
    -- is a real decision the layout makes. Half the point size per character is
    -- not any real font's metrics, but it is monotonic in length and in size,
    -- which is what the code under test actually depends on.
    f.SetFont       = function(self, file, size, flags)
        self.fontFile, self.fontSize, self.fontFlags = file, size, flags
    end
    f.GetFont       = function(self)
        return self.fontFile or "Fonts/FRIZQT__.TTF", self.fontSize or 10, self.fontFlags or ""
    end
    f.GetStringWidth  = function(self)
        return #tostring(self.text or "") * (self.fontSize or 10) * 0.5
    end
    -- Wrapped height, not a constant. A box is sized from what its text
    -- measures once wrapped, and a stub that reported one line for everything
    -- could not tell a box that fits its text from one painting its last line
    -- over the row beneath it.
    f.GetStringHeight = function(self)
        local line = (self.fontSize or 10) * 1.2
        if not (self.widthSet and type(self.width) == "number" and self.width > 0
            and self.wordWrap ~= false) then
            return line
        end

        -- Packed word by word, not divided width by width. Wrapping breaks at
        -- spaces, so text measuring twice the box can still need three lines
        -- -- and a stub that divided agreed exactly with the code that
        -- divided, which is how a box one line short of its text passed.
        local perChar = (self.fontSize or 10) * 0.5
        local lines, used = 1, 0
        for word in tostring(self.text or ""):gmatch("%S+") do
            local wordWidth = #word * perChar
            local needed = (used > 0) and (used + perChar + wordWidth) or wordWidth
            if used > 0 and needed > self.width then
                lines = lines + 1
                used = wordWidth
            else
                used = needed
            end
        end
        return line * lines
    end
    -- Scrolling, enough to check the wheel clamps at both ends.
    f.verticalScroll     = 0
    f.scrollRange        = 100
    f.GetVerticalScroll  = function(self) return self.verticalScroll end
    f.SetVerticalScroll  = function(self, v) self.verticalScroll = v end
    f.GetVerticalScrollRange = function(self) return self.scrollRange end
    -- Focus, so a refresh can tell which box is being typed into.
    f.HasFocus      = function(self) return self.focused == true end
    f.SetFocus      = function(self) self.focused = true; M.focused = self end
    f.ClearFocus    = function(self)
        self.focused = false
        if M.focused == self then M.focused = nil end
    end
    f.SetMaxLines   = function(self, v) self.maxLines = v end
    -- Screen geometry. Modelled because the unmodelled-method fallback returns
    -- the frame itself, and the drag maths would then do arithmetic on a table
    -- — an error the stub would be inventing rather than catching.
    f.GetTop            = function(self) return 600 end
    f.GetBottom         = function(self) return 0 end
    f.GetLeft           = function(self) return 0 end
    f.GetRight          = function(self) return self.width end
    f.GetEffectiveScale = function(self) return self.scale end
    f.GetFrameLevel     = function(self) return self.level or 1 end
    f.EnableKeyboard    = function(self, v) self.keyboard = v end
    f.SetFrameLevel     = function(self, v) self.level = v end
    f.SetAttribute  = function(self, k, v) self.attributes[k] = v end
    f.GetAttribute  = function(self, k) return self.attributes[k] end
    f.SetFrameRef   = function(self, k, v) self.attributes["ref:" .. k] = v end
    -- Event registration, so a test can fire what the client would.
    f.events        = nil
    f.RegisterEvent = function(self, e)
        self.events = self.events or {}
        self.events[e] = true
    end
    f.UnregisterEvent = function(self, e) if self.events then self.events[e] = nil end end
    f.UnregisterAllEvents = function(self) self.events = nil end
    f.IsEventRegistered = function(self, e) return (self.events and self.events[e]) == true end
    f.GetFrameRef   = function(self, k) return self.attributes["ref:" .. k] end
    -- Recorded, because how many directions a button accepts decides whether
    -- its snippet runs once or twice per press.
    f.RegisterForClicks = function(self, ...) self.clickTypes = { ... } end
    f.SetScript     = function(self, e, fn) self.scripts[e] = fn end
    f.GetScript     = function(self, e) return self.scripts[e] end
    -- Chains rather than replaces, which is the difference that matters: code
    -- hooking a script it does not own expects the original to keep running,
    -- and a stub that silently drops it hides exactly the bug being guarded
    -- against.
    f.HookScript    = function(self, e, fn)
        local existing = self.scripts[e]
        if existing then
            self.scripts[e] = function(...) existing(...) return fn(...) end
        else
            self.scripts[e] = fn
        end
    end
    f.GetText       = function(self) return self.text or "" end
    f.SetText       = function(self, t) self.text = t end
    f.SetTextColor  = function(self, r, g, b, a) self.color = { r, g, b, a } end
    f.SetColorTexture = function(self, r, g, b, a) self.color = { r, g, b, a } end
    f.CreateFontString = function(self) return newFrame("FontString", nil, self) end
    f.CreateTexture    = function(self) return newFrame("Texture", nil, self) end
    f.GetObjectType    = function(self) return frameType end
    -- Real strings and real frames. Unmodelled, the PascalCase fallback hands
    -- back the frame itself, so code that reads a name gets a table and fails
    -- somewhere unrelated to where the mistake is.
    f.GetName          = function(self) return self.name end
    f.GetParent        = function(self) return self.parent end

    -- Frames built from a template gain that template's fields.
    if template and template:find("BasicFrameTemplate") then
        f.TitleBg = newFrame("Frame", nil, f)
    end
    -- The scroll templates ship a bar, and the addon shows and hides it by
    -- reaching for it by name. Without one modelled, RefreshScrollBar found a
    -- function where it wanted a frame and quietly did nothing, so no test
    -- could tell a bar that appears when it should from one that never does.
    if template and template:find("ScrollFrameTemplate") then
        f.ScrollBar = newFrame("Frame", nil, f)
    end
    -- Blizzard's slider template is a fixed height that the addon never sets,
    -- so without this every slider is 300 tall here and appears to overlap the
    -- whole Settings panel -- which buried the real overlaps in that panel
    -- under a page of noise.
    if template and template:find("SliderTemplate") then
        f.height, f.heightSet = 17, true
        f.Low, f.High, f.Text = newFrame("FontString", nil, f),
            newFrame("FontString", nil, f), newFrame("FontString", nil, f)
    end

    -- What a scroll frame is actually scrolling. Recorded rather than ignored:
    -- the callouts overflowed the window because nothing clipped them, and the
    -- fix is a child in here, which a test has to be able to see.
    f.SetScrollChild = function(self, child)
        self.scrollChild = child
        if child then child.parent = self end
        return self
    end
    f.GetScrollChild = function(self) return self.scrollChild end

    -- A named frame is a global in the client, which is how one addon reaches
    -- another's frame and how a test reaches either. Without this, everything
    -- that looks itself up by name came back nil and the check quietly passed
    -- on nothing.
    if type(name) == "string" and name ~= "" then _G[name] = f end

    -- Parents keep their children, so a test can walk the tree and find frames
    -- a pool left behind.
    M.allFrames = M.allFrames or {}
    M.allFrames[#M.allFrames + 1] = f

    f.IsKeyboardEnabled = function(self) return self.keyboard == true end

    f.children = {}
    if parent and type(parent) == "table" and parent.children then
        parent.children[#parent.children + 1] = f
    end

    setmetatable(f, mt)
    return f
end

--- Every descendant of a frame, depth first.
function M.descendants(frame, out)
    out = out or {}
    for _, child in ipairs(frame.children or {}) do
        out[#out + 1] = child
        M.descendants(child, out)
    end
    return out
end

function M.install()
    _G.UIParent   = newFrame("Frame", "UIParent")
    _G.CreateFrame = function(t, n, p, tpl) return newFrame(t, n, p, tpl) end
    -- Settable, so a test can ask what the interface does during a pull. Every
    -- combat rule in this addon is a branch on this one call.
    M.inCombat = false
    _G.InCombatLockdown = function() return M.inCombat end
    _G.UnitExists = function() return false end
    _G.UnitName   = function() return nil end
    _G.GetTime    = function() return 0 end
    -- Version, build, date, interface. Only the fourth is read anywhere.
    _G.GetBuildInfo = function() return "12.1.0", "60000", "Jan 1 2026", 120100 end
    _G.GetBindingAction = function() return "" end
    _G.SendChatMessage = function() end
    _G.GetCursorPosition = function() return 0, 0 end
    -- Whichever edit box holds the keyboard, which is how the client answers it.
    _G.GetCurrentKeyBoardFocus = function() return M.focused end
    -- Walks every frame, which is how the addon finds what is holding the
    -- keyboard when clearing focus is not enough.
    _G.EnumerateFrames = function(previous)
        local list = M.allFrames or {}
        if not previous then return list[1] end
        for i, f in ipairs(list) do
            if f == previous then return list[i + 1] end
        end
        return nil
    end
    -- Modifier state, so a test can press a chord.
    M.shift, M.ctrl, M.alt = false, false, false
    _G.IsShiftKeyDown   = function() return M.shift end
    _G.IsControlKeyDown = function() return M.ctrl end
    _G.IsAltKeyDown     = function() return M.alt end
    -- Override bindings, recorded so a test can see what is live.
    M.bindings = {}
    _G.ClearOverrideBindings = function(owner) M.bindings[owner] = {} end
    _G.SetOverrideBindingClick = function(owner, priority, key, button)
        M.bindings[owner] = M.bindings[owner] or {}
        M.bindings[owner][key] = button
    end
    _G.wipe       = function(t) for k in pairs(t) do t[k] = nil end return t end
    _G.ChatFontNormal = {}
    _G.SlashCmdList = {}
    _G.strlenutf8 = nil
    _G.print = function() end   -- the addon chatters on load; keep output clean
    _G.date = os.date
    _G.time = os.time
    _G.strmatch = string.match
end

return M
