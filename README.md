# MythicMacros

A personal Mythic+ callout addon for WoW Midnight (12.x): a movable, scalable
grid of buttons holding one short instruction per mob, organised into a page
per dungeon section, so callouts can be fired by clicking rather than by
remembering which numpad key maps to which mob.

## Status

Pre-implementation. The repo currently contains only **MythicMacrosProbe**, a
capability probe.

Midnight's 12.0 addon lockdown changed what is possible here, and the public
reporting on the details conflicts. Rather than build an architecture on a
guess, the probe measures the actual behaviour on live so the real addon can be
written against confirmed facts.

## What the probe answers

A 2x2 matrix of delivery mechanism against payload:

|                          | payload `/run` | payload chat line |
| ------------------------ | -------------- | ----------------- |
| `macrotext` attribute    | test 1         | test 2            |
| real character macro     | test 3         | test 4            |

Comparing **rows** shows whether the `macrotext` attribute still executes.
Comparing **columns** shows whether it is `/run` that is blocked rather than the
delivery mechanism, so a dead cell cannot be misread.

It also reports:

- real macro slot caps and current usage
- whether `SetAttribute` and `EditMacro` are blocked in combat
- whether a secure handler can flip a page frame during combat
- whether a `/p` line from a macro actually lands during an active key

## Installing

Copy the `MythicMacrosProbe` folder into:

```
World of Warcraft/_retail_/Interface/AddOns/
```

Then `/reload`, or restart the client.

## Running it

1. `/mmprobe` opens the panel.
2. **Create macros** — writes two temporary macros (`MMP_RUN`, `MMP_CHAT`).
3. Click all four matrix buttons.
4. Get into combat, then click **Test: combat ops** and **Test: flip page**.
5. In a group inside an active key, click both chat buttons again.
6. `/mmprobe report` prints everything. Copy the output.

Solo testing: chat tests need a group. `/mmprobe say` switches them to `/say`
so they can be checked alone; `/mmprobe party` switches back.

**Remove macros** deletes the temporary macros. The probe only ever deletes
macros it created itself, tracked by name in SavedVariables.

Other commands: `/mmprobe env` re-snapshots the environment, `/mmprobe reset`
clears recorded results.

Results persist across `/reload`, so a key can be run first and the report read
afterwards.
