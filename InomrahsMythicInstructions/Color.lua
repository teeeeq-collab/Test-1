--------------------------------------------------------------------------------
-- Color: conversions, and the palette a dungeon or the user can override.
--
-- Kept apart from Style because it is arithmetic and nothing else: no frames,
-- no client, so it can be tested outside the game. Every mistake a colour
-- picker makes is a rounding or a wrap-around, and those are exactly the things
-- worth having a test for.
--------------------------------------------------------------------------------

local ADDON, IMI = ...

IMI.Color = {}
local Color = IMI.Color

local function clamp(v, low, high)
    v = tonumber(v) or low
    if v < low then return low end
    if v > high then return high end
    return v
end

--- Hue in degrees 0-360, saturation and value 0-1, out to r, g, b in 0-1.
---
--- 360 is the same colour as 0, so it wraps rather than falling off the end of
--- the sector table — a slider dragged to its maximum must not go black.
function Color.HSVtoRGB(h, s, v)
    -- Wrapped, not clamped. Hue is a circle: clamping first turned 420 into
    -- 360 and then into 0, so a value past the end came back red instead of
    -- coming back round to yellow.
    h = (tonumber(h) or 0) % 360
    s = clamp(s, 0, 1)
    v = clamp(v, 0, 1)

    local c = v * s
    local x = c * (1 - math.abs((h / 60) % 2 - 1))
    local m = v - c

    local r, g, b
    if     h <  60 then r, g, b = c, x, 0
    elseif h < 120 then r, g, b = x, c, 0
    elseif h < 180 then r, g, b = 0, c, x
    elseif h < 240 then r, g, b = 0, x, c
    elseif h < 300 then r, g, b = x, 0, c
    else                r, g, b = c, 0, x
    end

    return r + m, g + m, b + m
end

--- The way back. Grey has no hue; rather than returning something arbitrary it
--- keeps 0, which is what a picker wants so the hue control does not jump when
--- saturation is dragged to nothing.
function Color.RGBtoHSV(r, g, b)
    r, g, b = clamp(r, 0, 1), clamp(g, 0, 1), clamp(b, 0, 1)

    local max = math.max(r, g, b)
    local min = math.min(r, g, b)
    local delta = max - min

    local h = 0
    if delta > 0 then
        if max == r then
            h = 60 * (((g - b) / delta) % 6)
        elseif max == g then
            h = 60 * (((b - r) / delta) + 2)
        else
            h = 60 * (((r - g) / delta) + 4)
        end
    end
    if h < 0 then h = h + 360 end

    local s = (max == 0) and 0 or (delta / max)
    return h, s, max
end

--- WoW's own colour escape, for putting a colour into a printed line.
function Color.ToHex(r, g, b)
    return ("%02x%02x%02x"):format(
        math.floor(clamp(r, 0, 1) * 255 + 0.5),
        math.floor(clamp(g, 0, 1) * 255 + 0.5),
        math.floor(clamp(b, 0, 1) * 255 + 0.5))
end

--- Stored colours are plain tables so they serialise and export like the rest
--- of the schema. Anything malformed reads as "no colour set" rather than
--- reaching a SetColorTexture call as nil.
function Color.Valid(c)
    return type(c) == "table"
        and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number"
end

function Color.Pack(r, g, b)
    return { clamp(r, 0, 1), clamp(g, 0, 1), clamp(b, 0, 1) }
end

function Color.Unpack(c, fallback)
    if not Color.Valid(c) then
        if fallback then return fallback[1], fallback[2], fallback[3], fallback[4] or 1 end
        return 1, 1, 1, 1
    end
    return c[1], c[2], c[3], c[4] or 1
end

--- A dimmer or brighter version, for deriving the hover shade of a chosen
--- colour rather than making the user pick two.
function Color.Shade(c, factor)
    local r, g, b, a = Color.Unpack(c)
    return { clamp(r * factor, 0, 1), clamp(g * factor, 0, 1), clamp(b * factor, 0, 1), a }
end

--- Readable text against a dark panel. A colour picked at very low brightness
--- is unreadable as text, so text derived from a chosen colour is floored: the
--- point of colouring a dungeon is to recognise it, not to hide it.
function Color.ForText(c)
    local h, s, v = Color.RGBtoHSV(Color.Unpack(c))
    if v < 0.55 then v = 0.55 end
    local r, g, b = Color.HSVtoRGB(h, s, v)
    return { r, g, b, 1 }
end
