--------------------------------------------------------------------------------
-- Every pair of siblings, in every view.
--
-- The named-group checks are precise and only see what somebody remembered to
-- name. This is the wide net: every visible frame under the same parent as
-- another, in Run, Edit and Settings, at the default size and at the smallest
-- the window goes.
--
-- Nested frames overlap by definition, so only siblings are compared. The
-- handful of widgets that genuinely sit on top of something -- a resize grip
-- on the window edge, the handle on the divider, the invisible hover target
-- over a heading, the click layer over a name box -- carry
-- `overlapsOnPurpose`, which is a claim in the code rather than a rectangle in
-- this file that goes stale the moment anything moves.
--------------------------------------------------------------------------------

local realPrint = print
package.path = "tests/?.lua;" .. package.path
local stub = require("wowstub")
stub.install()
local geom = require("geometry")

local IMI = {}
for _, f in ipairs({ "Libs/LibStub/LibStub", "Libs/LibDeflate/LibDeflate",
                     "Libs/LibSerialize/LibSerialize" }) do
    loadfile("InomrahsMythicInstructions/" .. f .. ".lua")()
end
for _, f in ipairs({ "Util", "Color", "Style", "Core", "History", "Runtime", "UI",
                     "Picker", "Binds", "Edit", "Export", "Sheet", "Starter",
                     "Capture" }) do
    local chunk, err = loadfile("InomrahsMythicInstructions/" .. f .. ".lua")
    if not chunk then realPrint("  FAIL loading " .. f .. ": " .. tostring(err)); os.exit(1) end
    chunk("InomrahsMythicInstructions", IMI)
end

local pass, fail = 0, 0
local function ck(label, cond, got)
    if cond then pass = pass + 1
    else fail = fail + 1; realPrint("  FAIL: " .. label .. (got and ("\n         " .. got) or "")) end
end

InomrahsMythicInstructionsDB = IMI.Core.Init({})
IMI.UI.Init()

local cat = IMI.Core.AddCategory("Sweep")
local mob = IMI.Core.AddEnemy(cat.id, "A mob with a fairly long name")
IMI.Core.AddLine(cat.id, mob.id, "",
    "/p a callout long enough to wrap onto a second line and then some more")
IMI.Core.AddLine(cat.id, mob.id, "short", "/p kick")
local page = IMI.Core.AddPage(cat.id, "Route")
IMI.Core.AddEnemyToPage(cat.id, page.id, mob.id)

-- With both overrides on, so their dropdowns are on screen and get checked.
IMI.Core.SetCategoryChannel(cat.id, "/raid")
IMI.Core.SetPageChannel(cat.id, page.id, "/i")

local function siblingsOf(root)
    local byParent = {}
    for _, f in ipairs(stub.descendants(root)) do
        if f:IsVisible() and f.parent then
            byParent[f.parent] = byParent[f.parent] or {}
            table.insert(byParent[f.parent], f)
        end
    end
    return byParent
end

local function tag(f)
    return ("%s[%s]"):format(f.frameType,
        tostring(f.text or f.name or ""):sub(1, 30))
end

local function sweep(what)
    geom.resetAll(IMI.UI.root, stub)

    local clashes = {}
    for _, kids in pairs(siblingsOf(IMI.UI.root)) do
        for i = 1, #kids do
            for j = i + 1, #kids do
                local a, b = kids[i], kids[j]
                -- Textures are grounds and borders; they are meant to sit
                -- under what is drawn on them.
                if a.frameType ~= "Texture" and b.frameType ~= "Texture"
                    and not a.overlapsOnPurpose and not b.overlapsOnPurpose then
                    local ra, rb = geom.rect(a), geom.rect(b)
                    if ra and rb and geom.overlaps(ra, rb, 1) then
                        clashes[#clashes + 1] = ("%s %s  and  %s %s"):format(
                            tag(a), geom.describe(ra), tag(b), geom.describe(rb))
                    end
                end
            end
        end
    end

    ck(what .. ": nothing is drawn on top of anything else",
        #clashes == 0, table.concat(clashes, "\n         "))
end

local function everyView(what)
    IMI.UI.Show("run")
    IMI.UI.OpenRun(cat.id)
    sweep(what .. ", Run")

    IMI.UI.Show("edit")
    IMI.Edit.SetCategory(cat.id)
    IMI.Edit.ShowTab("enemies")
    sweep(what .. ", Edit enemies")

    IMI.Edit.ShowTab("pages")
    IMI.Edit.RefreshPages()
    sweep(what .. ", Edit pages")

    IMI.UI.Show("settings")
    sweep(what .. ", Settings")
end

everyView("default size")

IMI.UI.root:SetSize(IMI.UI.MinSize())
IMI.UI.Relayout()
everyView("minimum size")

realPrint(("\nsweep: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
