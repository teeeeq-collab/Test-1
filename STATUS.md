# Where this is

Written so work can resume from the repository alone, without the conversation
that produced it.

## Works, verified in game

- Panel, sidebar, dungeon list, Run and Edit views, Settings
- Creating dungeons, enemies and lines; editing text in place
- Enemy reordering and sorting; pages and page composition
- Export and import strings
- `/imi starter` (the eight Season 2 dungeons), `Add target` keybind

## Not yet confirmed working

**Pressing a callout button sends nothing.** This is the open item.

Ruled out so far: it happens on `/p`, `/i` and `/say`, so it is not a chat
restriction; the buttons render and carry labels, so the layout and the data are
fine; a follower dungeon behaves the same as a real one.

Two differences from the probe's proven-working button were found and corrected
in v0.8 — `RegisterForClicks("AnyUp")` where the probe used both directions, and
a missing `EnableMouse(true)`. Whether that fixed it is unconfirmed.

`/imi debug` exists for exactly this. Run it with a dungeon open in Run: it
prints each visible button's `type` and full macro text, and hooks a one-off
click reporter. That separates the three causes that look identical from
outside:

| Symptom | Cause |
| ------- | ----- |
| no macro text on the button | the text never arrived |
| text present, no click line | the click is not landing |
| click line prints, nothing sent | the action is being refused |

## Also open

- **Interface clarity.** Reported as "could be clearer" after the sidebar
  rewrite; specifics not yet gathered.
- **Folder rename.** The addon displays as Inomrah's Mythic Instructions but its
  folder is still `MythicMacros`, because WoW keys saved data to the folder name
  and renaming it would orphan everything entered. Needs a migration before
  publishing. The keybinding identifier is unchanged for the same reason:
  changing it silently drops the bound key.

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
