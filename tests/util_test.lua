-- Exercise the character logic without WoW's strlenutf8 present.
local MM = {}
local chunk = loadfile("MythicMacros/Util.lua")
chunk("MythicMacros", MM)
local U = MM.Util

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
