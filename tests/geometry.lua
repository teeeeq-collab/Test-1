--------------------------------------------------------------------------------
-- Resolving what the stub recorded into actual rectangles.
--
-- The stub records anchors; it does not work out where anything ends up. That
-- gap is exactly where overlapping widgets live: every overlap this addon has
-- shipped was two anchors whose arithmetic nobody added up. This adds it up.
--
-- Best effort by design. A frame whose size cannot be worked out is reported as
-- unresolved rather than guessed at, and the caller decides whether that
-- matters. A wrong rectangle would be worse than no rectangle.
--------------------------------------------------------------------------------

local M = {}

-- The screen. Only its size matters, since everything here is relative.
local SCREEN_W, SCREEN_H = 1024, 768

--- Where one named point of a rect sits.
local function anchorOf(rect, point)
    local midX = (rect.left + rect.right) / 2
    local midY = (rect.bottom + rect.top) / 2

    if point == "TOPLEFT"     then return rect.left,  rect.top end
    if point == "TOPRIGHT"    then return rect.right, rect.top end
    if point == "BOTTOMLEFT"  then return rect.left,  rect.bottom end
    if point == "BOTTOMRIGHT" then return rect.right, rect.bottom end
    if point == "LEFT"        then return rect.left,  midY end
    if point == "RIGHT"       then return rect.right, midY end
    if point == "TOP"         then return midX,       rect.top end
    if point == "BOTTOM"      then return midX,       rect.bottom end
    return midX, midY                                   -- CENTER
end

--- What a frame measures, which is not always what it was told.
---
--- A font string is usually never given a size: it is as big as its text. The
--- stub hands every frame a default size at birth, and taking that for a font
--- string's real one produced 600x300 labels that appeared to overlap
--- everything on the panel.
function M.size(frame)
    local w, h = frame.width, frame.height

    if frame.frameType == "FontString" then
        if not frame.widthSet and frame.GetStringWidth then
            w = frame:GetStringWidth()
        end
        if not frame.heightSet and frame.GetStringHeight then
            local lineHeight = frame:GetStringHeight()
            h = lineHeight * math.max(1, frame.maxLines or 1)
        end
    end

    return w, h
end

local resolving = {}

--- The rectangle a frame occupies, or nil with a reason.
function M.rect(frame)
    if type(frame) ~= "table" then return nil, "not a frame" end
    if frame.__rect then return frame.__rect end
    if resolving[frame] then return nil, "anchored in a circle" end

    if frame.name == "UIParent" or not frame.parent then
        frame.__rect = { left = 0, bottom = 0, right = SCREEN_W, top = SCREEN_H }
        return frame.__rect
    end

    resolving[frame] = true
    local rect = M.resolve(frame)
    resolving[frame] = nil

    frame.__rect = rect
    return rect
end

function M.resolve(frame)
    local points = frame.points or {}
    if #points == 0 then return nil, "no anchors" end

    -- SetAllPoints: exactly the target's rectangle.
    if points[1].point == "ALL" then
        local target = points[1].rel or frame.parent
        local parentRect = M.rect(target)
        if not parentRect then return nil, "target unresolved" end
        return { left = parentRect.left, right = parentRect.right,
                 bottom = parentRect.bottom, top = parentRect.top }
    end

    local left, right, top, bottom

    for _, p in ipairs(points) do
        local target = p.rel or frame.parent
        local targetRect = M.rect(target)
        if not targetRect then return nil, "anchor target unresolved" end

        local ax, ay = anchorOf(targetRect, p.relPoint or p.point)
        ax = ax + (p.x or 0)
        ay = ay + (p.y or 0)

        local point = p.point
        if point:find("LEFT")   then left   = ax end
        if point:find("RIGHT")  then right  = ax end
        if point:find("TOP")    then top    = ay end
        if point:find("BOTTOM") then bottom = ay end
        if point == "CENTER" then
            local w, h = M.size(frame)
            if not (w and h) then return nil, "centred with no size" end
            left, right = ax - w / 2, ax + w / 2
            bottom, top = ay - h / 2, ay + h / 2
        end
        -- A bare TOP or BOTTOM also fixes the horizontal centre.
        if point == "TOP" or point == "BOTTOM" then
            local w = M.size(frame)
            if w then left, right = ax - w / 2, ax + w / 2 end
        end
        if point == "LEFT" or point == "RIGHT" then
            local _, h = M.size(frame)
            if h then bottom, top = ay - h / 2, ay + h / 2 end
        end
    end

    -- Fill whichever edges the anchors did not give, from the size.
    local w, h = M.size(frame)
    if left and not right and w then right  = left + w end
    if right and not left and w then left   = right - w end
    if top and not bottom and h then bottom = top - h end
    if bottom and not top and h then top    = bottom + h end

    if not (left and right and top and bottom) then return nil, "size unknown" end
    return { left = left, right = right, bottom = bottom, top = top }
end

--- Clears cached rectangles. Anything that moves a frame invalidates them, so
--- a test calls this after a refresh rather than trusting stale numbers.
function M.reset(frames)
    for _, f in ipairs(frames or {}) do f.__rect = nil end
end

function M.resetAll(root, stub)
    root.__rect = nil
    for _, f in ipairs(stub.descendants(root)) do f.__rect = nil end
end

--- Do two rectangles share any area? Touching edges do not count.
function M.overlaps(a, b, slack)
    slack = slack or 0
    if not (a and b) then return false end
    return a.left + slack < b.right and b.left + slack < a.right
       and a.bottom + slack < b.top and b.bottom + slack < a.top
end

function M.describe(rect)
    if not rect then return "unresolved" end
    return ("(%d,%d)-(%d,%d)"):format(rect.left, rect.bottom, rect.right, rect.top)
end

return M
