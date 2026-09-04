-- Colour arithmetic. Pure, so it is tested outside the game, which is where
-- every rounding and wrap-around mistake a picker can make actually lives.
local IMI = {}
loadfile("InomrahsMythicInstructions/Color.lua")("InomrahsMythicInstructions", IMI)
local C = IMI.Color

local pass, fail = 0, 0
local function ck(label, cond, got)
    if cond then pass = pass + 1
    else fail = fail + 1; print("  FAIL: " .. label .. (got and ("  got: " .. tostring(got)) or "")) end
end

local function near(a, b) return math.abs(a - b) < 0.002 end
--- Wrapped rather than passed straight through, because HSVtoRGB returns three
--- values and a call that is not the last argument keeps only the first.
local function hsv(h, s, v, er, eg, eb)
    local r, g, b = C.HSVtoRGB(h, s, v)
    return near(r, er) and near(g, eg) and near(b, eb),
           ("%.3f,%.3f,%.3f"):format(r, g, b)
end

-- The six corners of the hue circle.
ck("red",     hsv(0,   1, 1, 1, 0, 0))
ck("yellow",  hsv(60,  1, 1, 1, 1, 0))
ck("green",   hsv(120, 1, 1, 0, 1, 0))
ck("cyan",    hsv(180, 1, 1, 0, 1, 1))
ck("blue",    hsv(240, 1, 1, 0, 0, 1))
ck("magenta", hsv(300, 1, 1, 1, 0, 1))

-- A slider dragged to its maximum must not fall off the end of the sector
-- table and come back black.
ck("360 wraps to red",  hsv(360, 1, 1, 1, 0, 0))
ck("past 360 wraps",    hsv(420, 1, 1, 1, 1, 0))
-- Hue is a circle in both directions: -40 is 320, not 0.
ck("below zero wraps round", hsv(-40, 1, 1, 1, 0, 0.667))

ck("no saturation is grey", hsv(200, 0, 0.5, 0.5, 0.5, 0.5))
ck("no value is black",     hsv(200, 1, 0, 0, 0, 0))

-- Round trips, which is what a picker does every time it opens.
for _, case in ipairs({ { 0, 1, 1 }, { 45, 0.5, 0.9 }, { 137, 0.8, 0.4 },
                        { 210, 0.25, 1 }, { 299, 1, 0.6 } }) do
    local h, s, v = case[1], case[2], case[3]
    local h2, s2, v2 = C.RGBtoHSV(C.HSVtoRGB(h, s, v))
    ck(("round trip %d,%.2f,%.2f"):format(h, s, v),
        near(h, h2) and near(s, s2) and near(v, v2),
        ("%.1f,%.2f,%.2f"):format(h2, s2, v2))
end

-- Grey has no hue. Returning something arbitrary would make the hue control
-- jump the moment saturation was dragged to nothing.
local gh, gs = C.RGBtoHSV(0.4, 0.4, 0.4)
ck("grey keeps hue 0", gh == 0 and gs == 0, gh)

ck("hex", C.ToHex(1, 0.5, 0) == "ff8000", C.ToHex(1, 0.5, 0))
ck("hex clamps", C.ToHex(2, -1, 0.5) == "ff0080", C.ToHex(2, -1, 0.5))

-- Anything malformed has to read as "nothing set" rather than reaching a
-- SetColorTexture call as nil.
ck("a real colour is valid", C.Valid({ 1, 0, 0 }))
ck("nil is not", not C.Valid(nil))
ck("a short table is not", not C.Valid({ 1, 0 }))
ck("strings are not", not C.Valid({ "1", "0", "0" }))

ck("pack clamps", (function()
    local c = C.Pack(2, -1, 0.5)
    return c[1] == 1 and c[2] == 0 and c[3] == 0.5
end)())

ck("unpack falls back", (function()
    local r, g, b = C.Unpack(nil, { 0.1, 0.2, 0.3 })
    return near(r, 0.1) and near(g, 0.2) and near(b, 0.3)
end)())

ck("shade darkens", (function()
    local c = C.Shade({ 0.8, 0.4, 0.2 }, 0.5)
    return near(c[1], 0.4) and near(c[2], 0.2) and near(c[3], 0.1)
end)())

-- A colour chosen very dark is unreadable as text. The point of colouring a
-- dungeon is to recognise it, not to hide it.
local dark = C.ForText({ 0.05, 0.02, 0.02 })
local _, _, dv = C.RGBtoHSV(dark[1], dark[2], dark[3])
ck("dark colours are lifted for text", dv >= 0.55, dv)
local bright = C.ForText({ 1, 0.8, 0.2 })
ck("bright colours are left alone", near(bright[1], 1) and near(bright[2], 0.8), bright[1])

print(("\ncolor: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
