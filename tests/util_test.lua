-- Exercise the character logic without WoW's strlenutf8 present.
local IMI = {}
local chunk = loadfile("InomrahsMythicInstructions/Util.lua")
chunk("InomrahsMythicInstructions", IMI)
local U = IMI.Util

local euro = string.rep("\226\130\172", 120)          -- 120 chars, 360 bytes
local ascii = string.rep("x", 300)                     -- 300 chars, 300 bytes

print(("euro : %d chars, %d bytes -> fits=%s")
  :format(U.CharLen(euro), #euro, tostring(U.FitsInMacro(euro))))
print(("ascii: %d chars, %d bytes -> fits=%s")
  :format(U.CharLen(ascii), #ascii, tostring(U.FitsInMacro(ascii))))

local trimmed = U.TrimToChars(ascii)
print(("trim ascii -> %d chars"):format(U.CharLen(trimmed)))

local longEuro = string.rep("\226\130\172", 300)
local te = U.TrimToChars(longEuro)
print(("trim 300 euro -> %d chars, %d bytes (no split char: %s)")
  :format(U.CharLen(te), #te, tostring(#te % 3 == 0)))

print(("mixed label: %s"):format(U.ButtonLabel({ body = "/p Prio kick <Piercing Hiss>" })))
print(("caption wins: %s"):format(U.ButtonLabel({ caption = "Strat", body = "/p whatever" })))

-- Composing: a body with no command does nothing in game, silently, so plain
-- text must gain the channel and a real macro must be left alone.
local function ck(label, cond, got)
    if cond then print("  ok   " .. label)
    else print("  FAIL " .. label .. "  -> " .. tostring(got)); os.exit(1) end
end

print("")
local plain = "[High Evolutionist]: Kick <Envenom>. CC <Evolve>."
ck("plain text gains the channel",
   U.ComposeMacro(plain, "/p") == "/p " .. plain, U.ComposeMacro(plain, "/p"))
ck("a slash command passes through",
   U.ComposeMacro("/cast Blessing of Freedom", "/p") == "/cast Blessing of Freedom")
ck("leading space does not hide a command",
   U.ComposeMacro("  /i watch out", "/p") == "/i watch out", U.ComposeMacro("  /i watch out", "/p"))
ck("empty stays empty", U.ComposeMacro("", "/p") == "")
ck("channel is honoured", U.ComposeMacro("spread", "/raid") == "/raid spread")

-- The typed cap must leave room for the prefix, or a full line composes past
-- the limit and is truncated on write.
ck("typed cap allows for the prefix",
   U.MaxTypedChars("hello", "/p") == 255 - 3, U.MaxTypedChars("hello", "/p"))
ck("a real macro gets the full cap",
   U.MaxTypedChars("/cast x", "/p") == 255)
ck("longer channel leaves less room",
   U.MaxTypedChars("hello", "/raid") == 255 - 6, U.MaxTypedChars("hello", "/raid"))

local longest = string.rep("x", U.MaxTypedChars("x", "/p"))
ck("a full line composes exactly to the cap",
   U.CharLen(U.ComposeMacro(longest, "/p")) == 255,
   U.CharLen(U.ComposeMacro(longest, "/p")))

-- A bound, not the visual limit: a Run button fits two lines and the font
-- string ellipsises at whatever it actually holds, which depends on the text
-- scale and cannot be decided here in characters.
ck("labels are bounded", U.CharLen(U.ButtonLabel({ body = plain })) <= 60,
   U.ButtonLabel({ body = plain }))
ck("a caller can ask for a shorter one",
   U.CharLen(U.ButtonLabel({ body = plain }, 20)) <= 20,
   U.ButtonLabel({ body = plain }, 20))
-- Two lines are only useful if there is enough text left to fill them.
ck("enough survives for a second line",
   U.CharLen(U.ButtonLabel({ body = plain })) > 26, U.ButtonLabel({ body = plain }))
ck("captions are never shortened away", U.ButtonLabel({ caption = "Strat" }) == "Strat")
print("\ncomposing: all ok")
