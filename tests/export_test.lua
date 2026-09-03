strmatch = string.match
local MM = {}
loadfile("MythicMacros/Libs/LibStub/LibStub.lua")()
loadfile("MythicMacros/Libs/LibDeflate/LibDeflate.lua")()
loadfile("MythicMacros/Libs/LibSerialize/LibSerialize.lua")()
loadfile("MythicMacros/Util.lua")("MythicMacros", MM)
loadfile("MythicMacros/Core.lua")("MythicMacros", MM)
loadfile("MythicMacros/Export.lua")("MythicMacros", MM)
local Core, Export = MM.Core, MM.Export

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
check("has envelope", str:match("^!MM1:%d+!") ~= nil)
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
local oldStr = ("!MM1:%d!%s"):format(Deflate:Adler32(ser),
    Deflate:EncodeForPrint(Deflate:CompressDeflate(ser, { level = 9 })))

local owhat, oerr = Export.Import(oldStr)
vck("a pre-variants export still imports", owhat ~= nil, oerr)
local oldCat = Core.Categories()[#Core.Categories()]
vck("it lands as one variant", #Core.Variants(oldCat.id) == 1)
vck("its content survives", Core.Enemies(oldCat.id)[1].lines[1].body == "/p from an old export",
    Core.Enemies(oldCat.id)[1].lines[1].body)

print(("variants across export: %d passed, %d failed"):format(vp, vf))
if vf > 0 then os.exit(1) end
