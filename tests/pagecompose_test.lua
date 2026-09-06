--------------------------------------------------------------------------------
-- Page composition: disabled lines, page order, and per-field overrides.
--
-- The three sparse tables added in Phase 1. Sparse is the whole design: absence
-- means inherit, so a page that has never been composed must read exactly as it
-- did before these existed, and every test here is as much about what is NOT
-- stored as what is.
--------------------------------------------------------------------------------

local realPrint = print
package.path = "tests/?.lua;" .. package.path
local stub = require("wowstub")
stub.install()

local pass, fail = 0, 0
local function check(label, fn)
    local ok, err = pcall(fn)
    if ok then pass = pass + 1
    else fail = fail + 1; realPrint("  FAIL: " .. label .. "\n         " .. tostring(err)) end
end

local IMI = {}
for _, f in ipairs({ "Libs/LibStub/LibStub", "Libs/LibDeflate/LibDeflate",
                     "Libs/LibSerialize/LibSerialize" }) do
    loadfile("InomrahsMythicInstructions/" .. f .. ".lua")()
end
for _, f in ipairs({ "Util", "Color", "Core" }) do
    loadfile("InomrahsMythicInstructions/" .. f .. ".lua")("InomrahsMythicInstructions", IMI)
end
local Core, Util = IMI.Core, IMI.Util

--- A dungeon with one enemy carrying three lines, and one page holding it.
local function fixture()
    Core.Init({})
    local cat = Core.AddCategory("Altar of Fangs")
    local enemy = Core.AddEnemy(cat.id, "Ravenous Descendant")
    local a = Core.AddLine(cat.id, enemy.id, "Kick", "Kick the Enrage")
    local b = Core.AddLine(cat.id, enemy.id, "", "Dispel the leech")
    local c = Core.AddLine(cat.id, enemy.id, "", "/target Ravenous Descendant")
    local page = Core.AddPage(cat.id, "Area 1")
    Core.AddEnemyToPage(cat.id, page.id, enemy.id)
    return cat, enemy, page, a, b, c
end

local function ids(list)
    local out = {}
    for _, item in ipairs(list) do out[#out + 1] = item.id end
    return table.concat(out, ",")
end

--------------------------------------------------------------------------------

check("an uncomposed page stores nothing and inherits everything", function()
    local cat, enemy, page, a, b, c = fixture()

    if page.lineDisabled or page.lineOrder or page.lineOverrides then
        error("a fresh page already carries composition tables")
    end

    local lines = Core.PageEditorLines(cat.id, page.id, enemy.id)
    if ids(lines) ~= table.concat({ a.id, b.id, c.id }, ",") then
        error("inherited order is wrong: " .. ids(lines))
    end
    for _, line in ipairs(lines) do
        if not line.enabled then error("a line is disabled by default") end
    end
end)

check("the macro flag comes from the one classifier", function()
    local cat, enemy, page, a, _, c = fixture()
    local lines = Core.PageEditorLines(cat.id, page.id, enemy.id)

    local byId = {}
    for _, line in ipairs(lines) do byId[line.id] = line end
    if byId[a.id].isMacro then error("a chat line was classified as a macro") end
    if not byId[c.id].isMacro then error("a slash line was not classified as a macro") end
    if Util.IsMacroLine("/p hi") ~= Util.HasCommand("/p hi") then
        error("IsMacroLine and HasCommand disagree")
    end
end)

--------------------------------------------------------------------------------
-- Disabling
--------------------------------------------------------------------------------

check("a disabled line stays visible to the editor and leaves Run", function()
    local cat, enemy, page, a, b = fixture()
    Core.SetLineEnabledOnPage(cat.id, page.id, b.id, false)

    local editor = Core.PageEditorLines(cat.id, page.id, enemy.id)
    if #editor ~= 3 then error("the editor lost a line") end

    local run = Core.PageRunLines(cat.id, page.id, enemy.id)
    if #run ~= 2 then error("Run kept a disabled line") end
    for _, line in ipairs(run) do
        if line.id == b.id then error("the disabled line reached Run") end
    end

    local active, total = Core.PageLineCounts(cat.id, page.id, enemy.id)
    if active ~= 2 or total ~= 3 then
        error(("counts are %d of %d"):format(active, total))
    end
end)

check("re-enabling clears the table rather than leaving an empty one", function()
    local cat, _, page, _, b = fixture()
    Core.SetLineEnabledOnPage(cat.id, page.id, b.id, false)
    Core.SetLineEnabledOnPage(cat.id, page.id, b.id, true)

    if page.lineDisabled ~= nil then
        error("an empty disabled table was left behind")
    end
    if not Core.IsLineEnabledOnPage(cat.id, page.id, b.id) then
        error("the line did not come back")
    end
end)

check("disabling is per page", function()
    local cat, enemy, page, _, b = fixture()
    local other = Core.AddPage(cat.id, "Area 2")
    Core.AddEnemyToPage(cat.id, other.id, enemy.id)

    Core.SetLineEnabledOnPage(cat.id, page.id, b.id, false)
    if not Core.IsLineEnabledOnPage(cat.id, other.id, b.id) then
        error("disabling on one page disabled it on another")
    end
end)

--------------------------------------------------------------------------------
-- Order
--------------------------------------------------------------------------------

check("a page order survives lines being added and deleted at the source", function()
    local cat, enemy, page, a, b, c = fixture()

    Core.MoveLineOnPageTo(cat.id, page.id, enemy.id, c.id, 1)
    if ids(Core.PageEditorLines(cat.id, page.id, enemy.id))
        ~= table.concat({ c.id, a.id, b.id }, ",") then
        error("the move did not take")
    end

    -- A line added afterwards has no place in the stored order, and must land
    -- at the end rather than disappearing.
    local d = Core.AddLine(cat.id, enemy.id, "", "Bloodlust now")
    if ids(Core.PageEditorLines(cat.id, page.id, enemy.id))
        ~= table.concat({ c.id, a.id, b.id, d.id }, ",") then
        error("a newly added source line did not appear at the end")
    end

    -- And a deleted one must leave no hole.
    Core.DeleteLine(cat.id, enemy.id, a.id)
    if ids(Core.PageEditorLines(cat.id, page.id, enemy.id))
        ~= table.concat({ c.id, b.id, d.id }, ",") then
        error("a deleted line left a hole in the page order")
    end
end)

check("moving to the same place changes nothing, and bounds are clamped", function()
    local cat, enemy, page, a, _, c = fixture()
    if Core.MoveLineOnPageTo(cat.id, page.id, enemy.id, a.id, 1) ~= 1 then
        error("a no-op move reported a different position")
    end
    if Core.MoveLineOnPageTo(cat.id, page.id, enemy.id, c.id, 99) ~= 3 then
        error("an out-of-range target was not clamped")
    end
end)

check("resetting the order returns to the enemy's own", function()
    local cat, enemy, page, a, b, c = fixture()
    Core.MoveLineOnPageTo(cat.id, page.id, enemy.id, c.id, 1)
    if not Core.HasPageLineOrder(cat.id, page.id, enemy.id) then
        error("the override was not recorded")
    end

    Core.ResetPageLineOrder(cat.id, page.id, enemy.id)
    if Core.HasPageLineOrder(cat.id, page.id, enemy.id) then
        error("the override survived a reset")
    end
    if page.lineOrder ~= nil then error("an empty order table was left behind") end
    if ids(Core.PageEditorLines(cat.id, page.id, enemy.id))
        ~= table.concat({ a.id, b.id, c.id }, ",") then
        error("reset did not restore the source order")
    end
end)

check("enemies move to an absolute position on the page", function()
    local cat, _, page = fixture()
    local second = Core.AddEnemy(cat.id, "Venom Leech")
    local third = Core.AddEnemy(cat.id, "Ritual Chieftain")
    Core.AddEnemyToPage(cat.id, page.id, second.id)
    Core.AddEnemyToPage(cat.id, page.id, third.id)

    Core.MoveEnemyOnPageTo(cat.id, page.id, third.id, 1)
    if page.enemyIds[1] ~= third.id then error("the enemy did not move to first") end
    if #page.enemyIds ~= 3 then error("the move changed how many enemies there are") end
end)

--------------------------------------------------------------------------------
-- Overrides: the part where truthiness would silently lose data
--------------------------------------------------------------------------------

check("an override is per field, so the other field keeps inheriting", function()
    local cat, enemy, page, a = fixture()
    Core.SetLineOverride(cat.id, page.id, a.id, "caption", "Kick FIRST")

    local resolved = Core.ResolveLine(cat.id, page.id, enemy.id, a.id)
    if resolved.caption ~= "Kick FIRST" then error("the caption did not override") end
    if resolved.body ~= "Kick the Enrage" then
        error("the body stopped inheriting: " .. tostring(resolved.body))
    end

    -- Fixing the source wording must still reach this page.
    Core.SetLine(cat.id, enemy.id, a.id, "Kick", "Kick the Enrage NOW")
    resolved = Core.ResolveLine(cat.id, page.id, enemy.id, a.id)
    if resolved.body ~= "Kick the Enrage NOW" then
        error("a source edit did not reach a page that only overrode the caption")
    end
    if resolved.caption ~= "Kick FIRST" then
        error("the source edit overwrote the page's own caption")
    end
end)

check("an empty override is a value, not an absence", function()
    local cat, enemy, page, a = fixture()
    Core.SetLineOverride(cat.id, page.id, a.id, "caption", "")

    local resolved = Core.ResolveLine(cat.id, page.id, enemy.id, a.id)
    if resolved.caption ~= "" then
        error("an empty caption fell back to the source: " .. tostring(resolved.caption))
    end
    if not Core.HasLineOverride(cat.id, page.id, a.id, "caption") then
        error("an empty override is not reported as present")
    end
end)

check("clearing one field leaves the other, and clearing both removes the entry", function()
    local cat, enemy, page, a = fixture()
    Core.SetLineOverride(cat.id, page.id, a.id, "caption", "Local")
    Core.SetLineOverride(cat.id, page.id, a.id, "body", "/p local")

    Core.SetLineOverride(cat.id, page.id, a.id, "caption", nil)
    local resolved = Core.ResolveLine(cat.id, page.id, enemy.id, a.id)
    if resolved.caption ~= "Kick" then error("the caption did not return to source") end
    if resolved.body ~= "/p local" then error("clearing the caption cleared the body") end

    Core.SetLineOverride(cat.id, page.id, a.id, "body", nil)
    if page.lineOverrides ~= nil then error("an empty override table was left behind") end
end)

check("an overridden body decides the macro flag", function()
    local cat, enemy, page, a = fixture()
    Core.SetLineOverride(cat.id, page.id, a.id, "body", "/target Boss")

    local resolved = Core.ResolveLine(cat.id, page.id, enemy.id, a.id)
    if not resolved.isMacro then
        error("a page that overrode a chat line into a macro is not marked as one")
    end
end)

check("resolving hands back a copy, not the stored line", function()
    local cat, enemy, page, a = fixture()
    local resolved = Core.ResolveLine(cat.id, page.id, enemy.id, a.id)
    resolved.body = "vandalised"

    if Core.GetLine(cat.id, enemy.id, a.id).body == "vandalised" then
        error("writing to a resolved line edited the source")
    end
end)

--------------------------------------------------------------------------------
-- Cleanup: stale entries are invisible until an id is reused
--------------------------------------------------------------------------------

check("deleting a line forgets it everywhere", function()
    local cat, enemy, page, a, b, c = fixture()
    Core.SetLineEnabledOnPage(cat.id, page.id, b.id, false)
    Core.SetLineOverride(cat.id, page.id, b.id, "caption", "gone soon")
    Core.MoveLineOnPageTo(cat.id, page.id, enemy.id, b.id, 1)

    Core.DeleteLine(cat.id, enemy.id, b.id)

    if page.lineDisabled and page.lineDisabled[b.id] then
        error("a deleted line is still disabled")
    end
    if page.lineOverrides and page.lineOverrides[b.id] then
        error("a deleted line still has an override")
    end
    local order = page.lineOrder and page.lineOrder[enemy.id]
    for _, id in ipairs(order or {}) do
        if id == b.id then error("a deleted line is still in the page order") end
    end
end)

check("deleting an enemy forgets its lines everywhere", function()
    local cat, enemy, page, a, b = fixture()
    Core.SetLineEnabledOnPage(cat.id, page.id, a.id, false)
    Core.SetLineOverride(cat.id, page.id, b.id, "body", "/p local")
    Core.MoveLineOnPageTo(cat.id, page.id, enemy.id, b.id, 1)

    Core.DeleteEnemy(cat.id, enemy.id)

    if page.lineDisabled then error("a deleted enemy left a disabled entry") end
    if page.lineOverrides then error("a deleted enemy left an override") end
    if page.lineOrder then error("a deleted enemy left a page order") end
end)

check("removing an enemy from a page forgets that page's composition of it", function()
    local cat, enemy, page, a, b = fixture()
    Core.SetLineEnabledOnPage(cat.id, page.id, a.id, false)
    Core.SetLineOverride(cat.id, page.id, b.id, "caption", "local")
    Core.MoveLineOnPageTo(cat.id, page.id, enemy.id, b.id, 1)

    Core.RemoveEnemyFromPage(cat.id, page.id, enemy.id)

    if page.lineDisabled then error("the disabled flag outlived the enemy on the page") end
    if page.lineOverrides then error("the override outlived the enemy on the page") end
    if page.lineOrder then error("the order outlived the enemy on the page") end

    -- And the source itself is untouched: the enemy still exists.
    if not Core.GetEnemy(cat.id, enemy.id) then
        error("removing an enemy from a page deleted the enemy")
    end
end)

--------------------------------------------------------------------------------
-- Duplication: an unremapped id is inert and invisible
--------------------------------------------------------------------------------

check("duplicating a variant remaps every composition table", function()
    local cat, enemy, page, a, b, c = fixture()
    Core.SetLineEnabledOnPage(cat.id, page.id, b.id, false)
    Core.SetLineOverride(cat.id, page.id, a.id, "caption", "Kick FIRST")
    Core.MoveLineOnPageTo(cat.id, page.id, enemy.id, c.id, 1)

    local copy = Core.AddVariant(cat.id, "Push", Core.ActiveVariantId(cat.id))
    if not copy then error("the variant was not created") end
    Core.SetActiveVariant(cat.id, copy.id)

    local newEnemy = Core.Enemies(cat.id)[1]
    local newPage = Core.Pages(cat.id)[1]
    if not newEnemy or not newPage then error("the copy is missing content") end

    -- Nothing may still point at the original ids.
    for oldId in pairs(newPage.lineDisabled or {}) do
        if oldId == b.id then error("a disabled entry kept the original line id") end
    end
    for oldId in pairs(newPage.lineOverrides or {}) do
        if oldId == a.id then error("an override kept the original line id") end
    end
    if newPage.lineOrder and newPage.lineOrder[enemy.id] then
        error("the page order kept the original enemy id")
    end

    -- And the composition must actually still work on the copy.
    local lines = Core.PageEditorLines(cat.id, newPage.id, newEnemy.id)
    if #lines ~= 3 then error("the copied page lost lines") end
    if lines[1].body ~= "/target Ravenous Descendant" then
        error("the copied page did not keep its order: " .. tostring(lines[1].body))
    end

    local disabled, overridden = 0, 0
    for _, line in ipairs(lines) do
        if not line.enabled then disabled = disabled + 1 end
        if line.captionLocal then overridden = overridden + 1 end
    end
    if disabled ~= 1 then error("the copied page lost its disabled line") end
    if overridden ~= 1 then error("the copied page lost its caption override") end
end)

--------------------------------------------------------------------------------

check("the enemy badge counts split chat from macro", function()
    local cat, enemy = fixture()
    local chat, macro = Core.EnemyLineCounts(cat.id, enemy.id)
    if chat ~= 2 or macro ~= 1 then
        error(("counts are %d chat and %d macro"):format(chat, macro))
    end
end)

--------------------------------------------------------------------------------
-- Export round trip: import mints new ids, so anything keyed by an id has to
-- be translated on the way in. An untranslated entry is not an error -- it is
-- a silently inert one, which is the harder kind to notice.
--------------------------------------------------------------------------------

loadfile("InomrahsMythicInstructions/Export.lua")("InomrahsMythicInstructions", IMI)
local Export = IMI.Export

check("a composed page survives export and import", function()
    local cat, enemy, page, a, b, c = fixture()
    Core.SetLineEnabledOnPage(cat.id, page.id, b.id, false)
    Core.SetLineOverride(cat.id, page.id, a.id, "caption", "Kick FIRST")
    Core.SetLineOverride(cat.id, page.id, a.id, "body", "/p kick it")
    Core.MoveLineOnPageTo(cat.id, page.id, enemy.id, c.id, 1)

    local str = Export.EncodeCategory(cat.id)
    if not str then error("the category did not encode") end

    local ok, err = Export.Import(str)
    if not ok then error("import failed: " .. tostring(err)) end

    -- The import lands as a second category; find it rather than assuming.
    local categories = Core.Categories()
    local imported = categories[#categories]
    if imported.id == cat.id then error("import did not create a new category") end

    local newEnemy = Core.Enemies(imported.id)[1]
    local newPage = Core.Pages(imported.id)[1]
    local lines = Core.PageEditorLines(imported.id, newPage.id, newEnemy.id)

    if #lines ~= 3 then error("the imported page has " .. #lines .. " lines") end
    if lines[1].body ~= "/target Ravenous Descendant" then
        error("the page order did not survive import: " .. tostring(lines[1].body))
    end

    local disabled, captioned = 0, 0
    for _, line in ipairs(lines) do
        if not line.enabled then disabled = disabled + 1 end
        if line.caption == "Kick FIRST" then
            captioned = captioned + 1
            if line.body ~= "/p kick it" then
                error("the body override did not survive import")
            end
            if not line.isMacro then
                error("the imported override is not classified as a macro")
            end
        end
    end
    if disabled ~= 1 then error("the disabled line did not survive import") end
    if captioned ~= 1 then error("the caption override did not survive import") end
end)

check("an import from an older build without composition still works", function()
    Core.Init({})
    local cat = Core.AddCategory("Old")
    local enemy = Core.AddEnemy(cat.id, "Enemy")
    Core.AddLine(cat.id, enemy.id, "", "Kick")
    local page = Core.AddPage(cat.id, "Page")
    Core.AddEnemyToPage(cat.id, page.id, enemy.id)

    local str = Export.EncodeCategory(cat.id)
    local ok, err = Export.Import(str)
    if not ok then error("import failed: " .. tostring(err)) end

    local imported = Core.Categories()[#Core.Categories()]
    local newPage = Core.Pages(imported.id)[1]
    if newPage.lineDisabled or newPage.lineOrder or newPage.lineOverrides then
        error("an uncomposed page gained composition tables on import")
    end
end)

realPrint(("\npage composition: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
