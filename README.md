# MythicMacros

A personal Mythic+ callout addon for WoW Midnight (12.x): a movable, scalable
panel of labelled buttons, each firing a real macro — typically one short
instruction to the party. Organised into a page per dungeon section, so callouts
are pressed by sight rather than recalled as numpad positions.

See `DESIGN.md` for the full design.

## Status

`MythicMacros/` — the addon. In progress, not yet runnable.
`MythicMacrosProbe/` — a capability probe. **Run this first.**

Midnight's 12.0 lockdown changed what is possible here, and the public reporting
on the details contradicts itself. The probe measures the actual behaviour on
live so the addon is written against confirmed facts.

## What the probe measures

**A. Limits.** Macro slot caps, how long a macro name may be, and whether the
macro body cap is really 255 *bytes*. It writes a body of 120 multi-byte
characters — 360 bytes but only 120 characters — and reports what came back. The
input guard in the addon depends on the answer.

**B. Execution.** A 2x2 matrix:

|                       | payload `/run` | payload chat line |
| --------------------- | -------------- | ----------------- |
| `macrotext` attribute | test           | test              |
| real character macro  | test           | test              |

Rows show whether `macrotext` still executes. Columns show whether `/run` is the
blocked element rather than the delivery mechanism, so a dead cell cannot be
misread as the wrong conclusion.

**C. Combat.** Which of `SetAttribute`, `EditMacro`, `CreateMacro` and
`SetScale` are refused once a pull starts. The lock design assumes all of them
are.

**D. Paging.** Two mechanisms. `D1` asks whether plain insecure `Hide()` works
on a frame containing a protected button during combat; `D2` asks whether the
secure-handler route works. If D1 passes, the addon avoids a large amount of
machinery — which is why both are tested rather than assuming the harder one is
needed.

**E. EditBox.** Whether `SetMaxLetters` counts bytes or characters.

**F. Batch.** Whether ~20 macros can be created in one go, and what happens at
the cap.

## Installing

Copy `MythicMacrosProbe` into:

```
World of Warcraft/_retail_/Interface/AddOns/
```

Then `/reload`.

## Running it

1. `/mmprobe` opens the panel.
2. Out of combat, press **A. Limits**, **E. EditBox**, **F. Batch x20**.
3. Press **Create macros**, then all four buttons of the execution matrix.
4. Pull something. In combat, press **C. Combat ops**, **D1. Plain Hide()** and
   **D2. Secure flip**. Watch whether the box on the right actually changes.
5. In a group inside an active key, press the two chat buttons again.
6. **Print report**, or `/mmprobe report`. Copy the output.

Solo: chat tests need a group. `/mmprobe say` switches them to `/say` so they
can be checked alone; `/mmprobe party` switches back.

**Remove macros** deletes what the probe created. It only ever deletes macros it
created itself, tracked by name in SavedVariables.

Results persist across `/reload`, so a key can be run first and the report read
afterwards.
