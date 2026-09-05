strmatch = string.match
local IMI = {}
loadfile("InomrahsMythicInstructions/Libs/LibStub/LibStub.lua")()
loadfile("InomrahsMythicInstructions/Libs/LibDeflate/LibDeflate.lua")()
loadfile("InomrahsMythicInstructions/Libs/LibSerialize/LibSerialize.lua")()
loadfile("InomrahsMythicInstructions/Util.lua")("InomrahsMythicInstructions", IMI)
loadfile("InomrahsMythicInstructions/Core.lua")("InomrahsMythicInstructions", IMI)
loadfile("InomrahsMythicInstructions/Export.lua")("InomrahsMythicInstructions", IMI)
local Core, Export = IMI.Core, IMI.Export

local pass, fail = 0, 0
local function check(label, cond, extra)
    if cond then pass = pass + 1
    else fail = fail + 1; print("  FAIL: " .. label .. (extra and ("  -> " .. tostring(extra)) or "")) end
end

Core.Init({})
local cat = Core.AddCategory("Den of Nalorakk")
local a = Core.AddEnemy(cat.id, "Twinfang Harrower")
Core.AddLine(cat.id, a.id, "Strat", "/p freedom the snare on the tank")
Core.AddLine(cat.id, a.id, "Panic", "/p FRENZY - kite it")
local m = Core.AddEnemy(cat.id, "Matriarch", 3)
Core.AddLine(cat.id, m.id, "Open", "/p CC the adds first")
local p1 = Core.AddPage(cat.id, "Trash before Ra'Vi")
local p2 = Core.AddPage(cat.id, "Boss 1: Ra'Vi")
Core.AddEnemyToPage(cat.id, p1.id, a.id)
Core.AddEnemyToPage(cat.id, p1.id, m.id)
Core.AddEnemyToPage(cat.id, p2.id, m.id)   -- shared across pages

-- Round trip -----------------------------------------------------------------
local str = Export.EncodeCategory(cat.id)
check("encodes", type(str) == "string")
check("has envelope", str:match("^!IMI1:%d+!") ~= nil)
print(("  category string: %d chars"):format(#str))

local before = #Core.Categories()
local what, err = Export.Import(str)
check("imports", what ~= nil, err)
check("landed as a new category", #Core.Categories() == before + 1)

local imported = Core.Categories()[#Core.Categories()]
local impEnemies = Core.Enemies(imported.id)
local impPages   = Core.Pages(imported.id)
check("name preserved", imported.name == "Den of Nalorakk")
check("enemies preserved", #impEnemies == 2)
check("perRow preserved", impEnemies[2].perRow == 3)
check("lines preserved", #impEnemies[1].lines == 2)
check("body preserved", impEnemies[1].lines[1].body == "/p freedom the snare on the tank")
check("apostrophe survives", impPages[1].name == "Trash before Ra'Vi")

-- Ids must be regenerated, or an import collides with existing data
check("ids regenerated", impEnemies[1].id ~= a.id)
check("page refs remapped",
      #Core.PageEnemies(imported.id, impPages[1].id) == 2)
check("sharing survives import",
      #Core.PageEnemies(imported.id, impPages[2].id) == 1 and
      Core.PageEnemies(imported.id, impPages[2].id)[1].id ==
      Core.PageEnemies(imported.id, impPages[1].id)[2].id)

-- The failure everyone actually hits -----------------------------------------
local truncated = str:sub(1, #str - 15)
local ok2, err2 = Export.Import(truncated)
check("truncated paste refused", ok2 == nil)
check("truncation named precisely", err2 and err2:find("incomplete") ~= nil, err2)
print(("  truncated message: %s"):format(err2))

local ok3, err3 = Export.Import("just some text a friend pasted wrong")
check("garbage refused", ok3 == nil)
print(("  garbage message:   %s"):format(err3))

local ok4, err4 = Export.Import("")
check("empty refused", ok4 == nil)

-- Corruption in the middle survives decode but must fail the checksum
local middle = str:sub(1, 40) .. "XY" .. str:sub(43)
local ok5, err5 = Export.Import(middle)
check("corrupted body refused", ok5 == nil)
print(("  corrupted message: %s"):format(err5))

-- Profile round trip ----------------------------------------------------------
local pstr = Export.EncodeProfile()
check("profile encodes", type(pstr) == "string")
print(("  profile string:  %d chars"):format(#pstr))
local pwhat, perr = Export.Import(pstr)
check("profile imports", pwhat ~= nil, perr)

print(("\n%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end

-- Variants across an export ------------------------------------------------
print("")
local vp, vf = 0, 0
local function vck(label, cond, got)
    if cond then vp = vp + 1 else vf = vf + 1 print("  FAIL " .. label .. " -> " .. tostring(got)) end
end

local multi = Core.AddCategory("Two ways")
local m1 = Core.AddEnemy(multi.id, "Pack")
Core.AddLine(multi.id, m1.id, "", "/p normal route")
local second = Core.AddVariant(multi.id, "Big pull", Core.ActiveVariantId(multi.id))
Core.SetActiveVariant(multi.id, second.id)
Core.SetLine(multi.id, Core.Enemies(multi.id)[1].id,
             Core.Enemies(multi.id)[1].lines[1].id, nil, "/p chain pull it")
Core.SetActiveVariant(multi.id, Core.Variants(multi.id)[1].id)

local mstr = Export.EncodeCategory(multi.id)
local mwhat, merr = Export.Import(mstr)
vck("a category with variants imports", mwhat ~= nil, merr)

local back = Core.Categories()[#Core.Categories()]
vck("both variants arrive", #Core.Variants(back.id) == 2, #Core.Variants(back.id))
vck("first variant name kept", Core.Variants(back.id)[1].name == "Default",
    Core.Variants(back.id)[1].name)
vck("second variant name kept", Core.Variants(back.id)[2].name == "Big pull",
    Core.Variants(back.id)[2].name)

Core.SetActiveVariant(back.id, Core.Variants(back.id)[1].id)
vck("first variant text", Core.Enemies(back.id)[1].lines[1].body == "/p normal route",
    Core.Enemies(back.id)[1].lines[1].body)
Core.SetActiveVariant(back.id, Core.Variants(back.id)[2].id)
vck("second variant text", Core.Enemies(back.id)[1].lines[1].body == "/p chain pull it",
    Core.Enemies(back.id)[1].lines[1].body)

-- A backup made before variants existed must still import, or a backup is
-- worth nothing the moment the format moves.
local legacy = {
    name = "Made before variants",
    enemies = { { id = "x1", name = "Old mob", perRow = 1,
                  lines = { { id = "y1", caption = "Strat", body = "/p from an old export" } } } },
    pages   = { { id = "z1", name = "Old page", enemyIds = { "x1" } } },
}
local Deflate   = LibStub("LibDeflate")
local Serialize = LibStub("LibSerialize")
local ser = Serialize:Serialize({ v = 1, kind = "category", data = legacy })
local oldStr = ("!IMI1:%d!%s"):format(Deflate:Adler32(ser),
    Deflate:EncodeForPrint(Deflate:CompressDeflate(ser, { level = 9 })))

local owhat, oerr = Export.Import(oldStr)
vck("a pre-variants export still imports", owhat ~= nil, oerr)
local oldCat = Core.Categories()[#Core.Categories()]
vck("it lands as one variant", #Core.Variants(oldCat.id) == 1)
vck("its content survives", Core.Enemies(oldCat.id)[1].lines[1].body == "/p from an old export",
    Core.Enemies(oldCat.id)[1].lines[1].body)

print(("variants across export: %d passed, %d failed"):format(vp, vf))
if vf > 0 then os.exit(1) end

--------------------------------------------------------------------------------
-- Importing over a profile
--
-- The destructive path. It replaces what is loaded rather than adding to it,
-- which is what makes the dialog in front of it necessary and what makes these
-- checks worth having.
--------------------------------------------------------------------------------

local pr, fr = 0, 0
local function ckr(label, cond, got)
    if cond then pr = pr + 1
    else fr = fr + 1; print("  FAIL: " .. label .. (got and ("  " .. tostring(got)) or "")) end
end

IMI.Core.Init({})
local mine = IMI.Core.AddCategory("Mine")
local mob = IMI.Core.AddEnemy(mine.id, "My mob")
IMI.Core.AddLine(mine.id, mob.id, "", "/p mine")
IMI.Core.AddPage(mine.id, "My page")
IMI.Core.Settings().textScale = 1.25

local profileString = IMI.Export.EncodeProfile()

-- A different profile entirely, to import over the first.
IMI.Core.Init({})
local theirs = IMI.Core.AddCategory("Theirs")
local theirMob = IMI.Core.AddEnemy(theirs.id, "Their mob")
IMI.Core.AddLine(theirs.id, theirMob.id, "", "/p theirs")
IMI.Core.AddPage(theirs.id, "Their page")

local preview, err, count = IMI.Export.Preview(profileString)
ckr("a string can be inspected before it is applied", preview ~= nil, err)
ckr("and says how much it will replace", count == 1, count)
ckr("without applying any of it", IMI.Core.Categories()[1].name == "Theirs")

local what, err2 = IMI.Export.ImportReplacing(profileString)
ckr("importing reports what arrived", what == "1 dungeon", what or err2)
ckr("what was there is gone", #IMI.Core.Categories() == 1)
ckr("and what arrived is loaded", IMI.Core.Categories()[1].name == "Mine")
ckr("with its contents", #IMI.Core.Enemies(IMI.Core.Categories()[1].id) == 1)
ckr("and the look it was saved with", IMI.Core.Settings().textScale == 1.25)

-- Ids are minted fresh on the way in, so a string carrying ids that clash with
-- the file's own cannot poison it.
local imported = IMI.Core.Categories()[1]
ckr("the imported dungeon has an id of its own", imported.id ~= mine.id,
    imported.id)

-- A single-dungeon string is a profile with one dungeon in it, so the same
-- path handles both rather than needing a second kind of import.
IMI.Core.Init({})
IMI.Core.AddCategory("Before")
local catString = IMI.Export.EncodeCategory(IMI.Core.Categories()[1].id)
IMI.Core.AddCategory("Also before")
local what2 = IMI.Export.ImportReplacing(catString)
ckr("a category string replaces too", what2 == "1 dungeon", what2)
ckr("and leaves only itself", #IMI.Core.Categories() == 1
    and IMI.Core.Categories()[1].name == "Before")

local bad, badErr = IMI.Export.Preview("not a string at all")
ckr("a bad paste is refused before anything is destroyed", bad == nil)
ckr("with a reason", type(badErr) == "string" and badErr ~= "", badErr)

print(("\nimport over profile: %d passed, %d failed"):format(pr, fr))
if fr > 0 then os.exit(1) end
