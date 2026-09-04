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
- Opacity on the grounds only; per-dungeon and per-user colour palettes

## Known to have been broken, now fixed

**Callouts drew outside the window** (v0.33 and earlier). A dungeon with more
enemy cards than the window was tall laid the extra ones out straight through
the bottom edge and onto the game world. A plain frame does not clip its
children and nothing else was stopping them. The Run panel's cards now live in
a scroll frame, which clips, so what does not fit becomes something you can
scroll to. Fixed in v0.34.

The self-test's "nothing hangs off the edge" check had watched only the left
and right edges, and only the title bar and the Edit bottom row, so it reported
everything fine throughout. It now checks all four edges across the bar, the
Run view, the dungeon column and both Edit rows, and asserts separately that
the callouts are inside something that clips them.

**Long enemy names ran through the buttons beside them** in the Pages tab
(v0.33 and earlier). The row label had a left anchor and no right one, so it
was as wide as its text. It is now bounded by the first button in the row, with
word wrap off, which is what makes a name end in an ellipsis instead.


**The self-test locked the keyboard** (self-test 0.3 and earlier). Running
`/imitest` left the game unable to answer any key, Escape included, and only
`/reload` fixed it. Two faults stacked:

1. `checkClient` built a bare `CreateFrame("EditBox", nil, UIParent)` purely to
   ask which methods an EditBox has. An EditBox is shown the moment it is
   created and its autofocus defaults to on, so an invisible, unnamed,
   zero-size box took focus and ate every key the player pressed.
2. The addon's own escape hatch could not undo it. `keyboardHolders()` walked
   every frame in the game and tested `IsKeyboardEnabled()` unguarded; 12.1
   returns Secret Values from frames an addon has no business reading, and the
   first truth test on one throws. That aborted `ReleaseAllKeys()` before it
   released anything — which is why `/imi unstick` and "Give keyboard back"
   both did nothing. The self-test's own copy of the walk had the same fault,
   and threw during `checkClient`, which is why the last run produced a lockout
   and no report window at all.

Fixed in addon v0.33 and self-test 0.4. Probes are built once on a hidden
parent with autofocus off; every frame read in a walk goes through `isTrue` /
`safeString`, which do the test inside a `pcall` and hand back a plain value;
every self-test section is guarded so one fault cannot take the report with it;
the run releases the keyboard when it finishes and then checks that it did. The
addon also runs a one-second watchdog (`UI.SweepKeyboard`) that releases any
capture frame of ours holding the keyboard with nothing armed, so the next
lockout of this shape heals itself rather than needing a command typed on a
keyboard that has stopped working.


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

## Finding faults without waiting to trip over them

Three things, in rough order of what they catch:

- `./tests/run.sh` — the offline suite. Everything that is arithmetic or data.
- `lua5.1 tests/mutate.lua [file] [limit]` — breaks the source on purpose, one
  small change at a time, and reports every change the suite did not notice. A
  survivor is a claim nothing checks. Most survivors are pixel offsets and are
  not worth a test; read the list and decide. It refuses to run on a dirty tree,
  and if it is interrupted: `git checkout -- InomrahsMythicInstructions`.
- The **self-test addon**, in game: `/imitest`. The only place the rest can be
  answered — whether an API exists on this build, what the restricted
  environment allows, what a font string measures, where a frame lands.

The self-test knows what to look for from `InomrahsMISelfTest/Manifest.lua`,
which is **generated from the addon's source** by `tools/manifest.lua` — every
public function, named frame, slash command, secure attribute and setting this
version has, stamped with the version it was built from. Nothing about it is
maintained by hand, and the offline suite fails if it stops matching the source,
so it cannot quietly describe a version of the addon that no longer exists.

Against a newer addon it degrades rather than breaks: every reach into the addon
is guarded, and the report names anything the manifest lists that is not there.
A check that stopped running says so instead of passing silently.

After changing the addon: `lua5.1 tools/manifest.lua`, which `./tests/run.sh`
will remind you about.

## Measured, no longer assumed

The self-test's first run in the client answered what stood here unverified for
seven versions. `DESIGN.md` has the full list; the short version:

- Showing, hiding and rebinding **do** work inside a snippet, so closing the
  window from a key and the per-page keybinds both work during a pull.
- Moving and resizing **are not available there at all**. The version that
  assumed they were broke dragging and resizing outright, not just in combat,
  because once a snippet is installed it is the only path.

Still unmeasured: whether a key fires the right page's callout after a flip
*during* combat. The calls exist; that they behave is inference until someone
presses one mid-pull.


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
