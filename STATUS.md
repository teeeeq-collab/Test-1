# Where this is

Written so work can resume from the repository alone, without the conversation
that produced it.

## Works, verified in game

- Panel, sidebar, dungeon list, Run and Edit views, Settings
- Creating dungeons, enemies and lines; editing text in place
- Enemy reordering and sorting; pages and page composition
- Export and import strings
- `/imi starter` (the eight Season 2 dungeons), `Add target` keybind
- Renaming, reordering and deleting dungeons in the Edit sidebar
- Undo and redo across everything Edit changes; hover text on the symbol buttons
- Run callouts take a second line when they need it, and truncate past that
- Resizable window, collapsible dungeon list, wheel-scrolling lists
- Text scale across the whole interface, not only Run

## Known to have been broken, now fixed

**Callout buttons sent nothing** (v0.7 and earlier). Two differences from the
probe's proven-working button were the cause: `RegisterForClicks("AnyUp")` where
the probe registered both directions, and a missing `EnableMouse(true)`. Both
corrected in v0.8, and buttons have since been reported posting to party chat in
a normal dungeon.

Not yet exercised inside a live keystone or during a boss encounter. The probe
measured that path as working, so this is expected to hold, but it is inference
from the probe rather than observation of the addon.

`/imi debug` remains, and is the tool for it if a button ever goes quiet again.
Run it with a dungeon open in Run: it prints each visible button's `type` and
full macro text, and hooks a one-off click reporter, which separates the three
causes that look identical from outside:

| Symptom | Cause |
| ------- | ----- |
| no macro text on the button | the text never arrived |
| text present, no click line | the click is not landing |
| click line prints, nothing sent | the action is being refused |

## Worth verifying in game

The close button, the title-bar drag and the three resize edges now do their
work inside the restricted environment, which is what lets them run in combat.
That the restricted environment permits `StartMoving`, `StopMovingOrSizing` and
`StartSizing` is the one assumption here that was not measured with the probe —
everything else in `DESIGN.md` was. If any of the three misbehaves in a pull,
that assumption is where to look first.

## Also open

- **Interface clarity.** Reported as "could be clearer" after the sidebar
  rewrite. One concrete part of it is now done — the dungeon list can be
  renamed, reordered and pruned — but the rest of the specifics are still not
  gathered.
- **Re-bind after the rename.** The binding identifier moved with everything
  else, so a key bound to **Add target as enemy** under the old name is gone and
  has to be set again under Key Bindings → Inomrah's Mythic Instructions. Saved
  dungeons from the old folder do not carry over either; that was accepted
  explicitly, there being nothing saved yet worth a migration.

## What the design rests on

`DESIGN.md` holds the behaviour measured on 12.1.0, and marks what is still
inference. The short version:

- `macrotext` works, in combat, during a boss encounter and inside a keystone
- chat sent from a button is delivered in all three; only *reading* chat is
  blocked, which this addon never does
- `SetAttribute`, `EditMacro`, `CreateMacro` and `SetScale` are blocked in
  combat, so dungeons load and edits happen out of it
- secure-handler page flipping works in combat on a hardware click, and is
  refused from a script
- the macro cap is 256 **characters**, not bytes

A blocked operation returns no error, so none of that was established by
checking whether a call threw. Each was verified by writing a value and reading
it back, after an earlier round of tests reported everything as permitted purely
because nothing raised.

## Testing

`./tests/run.sh` — syntax checks every file, then runs the pure-Lua suites: the
data model, the length guard, export round trips, the starter set, and a UI
construction pass against a stubbed WoW API.

The stub cannot see rendering. It has caught load-order faults, orphaned frames
and nil calls; it did not catch an edit box with no height, which is why there
was no way to type text in v0.4. Anything visual still needs a person.
