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
    f.Show          = function(self) self.shown = true end
    f.Hide          = function(self) self.shown = false end
    f.SetShown      = function(self, v) self.shown = not not v end
    f.GetWidth      = function(self) return self.width end
    f.GetHeight     = function(self) return self.height end
    f.SetHeight     = function(self, h) self.height = h end
    f.SetWidth      = function(self, w) self.width = w end
    f.GetScale      = function(self) return self.scale end
    f.SetScale      = function(self, v) self.scale = v end
    f.SetAlpha      = function(self, v) self.alpha = v end
    f.GetPoint      = function(self) return "CENTER", nil, "CENTER", 0, 0 end
    f.SetAttribute  = function(self, k, v) self.attributes[k] = v end
    f.GetAttribute  = function(self, k) return self.attributes[k] end
    f.SetFrameRef   = function(self, k, v) self.attributes["ref:" .. k] = v end
    f.GetFrameRef   = function(self, k) return self.attributes["ref:" .. k] end
    f.SetScript     = function(self, e, fn) self.scripts[e] = fn end
    f.GetScript     = function(self, e) return self.scripts[e] end
    f.HookScript    = function(self, e, fn) self.scripts[e] = fn end
    f.GetText       = function(self) return self.text or "" end
    f.SetText       = function(self, t) self.text = t end
    f.SetTextColor  = function(self, r, g, b, a) self.color = { r, g, b, a } end
    f.SetColorTexture = function(self, r, g, b, a) self.color = { r, g, b, a } end
    f.CreateFontString = function(self) return newFrame("FontString", nil, self) end
    f.CreateTexture    = function(self) return newFrame("Texture", nil, self) end
    f.GetObjectType    = function(self) return frameType end

    -- Frames built from a template gain that template's fields.
    if template and template:find("BasicFrameTemplate") then
        f.TitleBg = newFrame("Frame", nil, f)
    end

    -- Parents keep their children, so a test can walk the tree and find frames
    -- a pool left behind.
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
    _G.InCombatLockdown = function() return false end
    _G.UnitExists = function() return false end
    _G.UnitName   = function() return nil end
    _G.GetTime    = function() return 0 end
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
