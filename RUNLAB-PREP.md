# Run Capability Lab — prep pass response

Reply to *CLAUDE_RUN_CAPABILITY_LAB_PROMPT.md*. Nothing has been implemented yet.

The brief is good and the guiding principle is right. This document covers four
things, in order of how much they change the work:

1. **Corrections** — where the brief's account of the source is out of date.
2. **Hazards** — things that will go wrong or mislead if built as written.
3. **A route the brief does not consider**, which may make a third of it moot.
4. **Decisions needed** before code is written.

---

## 1. Corrections to the brief's account of the source

Checked against the actual files, not memory.

### 1.1 The self-test is **0.8**, not 0.7

Version 0.8 already contains combat-scroll probes added for the earlier
scrolling task. They overlap §G:

| §G item | already in 0.8 |
| --- | --- |
| G1 method inventory on a real ScrollFrame handle | yes — `SetVerticalScroll`, `GetVerticalScroll`, `GetVerticalScrollRange`, `SetPoint`, `ClearAllPoints`, `SetHeight` |
| G2 restricted `SetVerticalScroll` attempt | yes, inside a snippet, on a disposable ScrollFrame |
| G3 restricted `SetPoint` on content parenting a protected button | yes |
| G5 which wheel routes exist on this build | yes — probes for `SecureHandlerMouseWheelTemplate`, `SecureHandlerStateTemplate`, `SecureHandlerBaseTemplate`, `SecureHandlerWrapScript` |

**These have never been run in combat**, because the run needs
`/imitest` out of combat first (to build the probe) and then `/imitest combat`
during a fight, and that sequence has not happened yet. So the results are not
missing because the probes are missing.

**Recommendation:** fold these into the lab rather than writing second versions.
Two probe sets answering the same question with different code is exactly how
two incompatible result systems appear, which §19 warns against.

### 1.2 The manifest is already regenerated — but the defect is real, and worse

The brief says the live report shows `manifest built for -- 0.38` against addon
0.41. `Manifest.lua` currently reads `builtFor = "0.41"`, so that specific
mismatch is gone.

The underlying defect is real and is **not** what the brief describes. The check
is not comparing anything at all:

```lua
record("Self-test", "manifest built for", true, tostring(manifest.builtFor or "unknown"))
```

The `true` is hardcoded. It reports the value and always passes. It has never
been capable of failing, at any version. §12A's requirement stands; its
diagnosis needs replacing with this one.

### 1.3 The floating-point failure is already fixed

`SelfTest.lua` line 909 already reads:

```lua
return math.abs(got - 90) < 0.01, ("width came back %s"):format(got)
```

§12B is done. The shared `approximately()` helper it suggests is still worth
having, because the lab will compare geometry in dozens of places.

### 1.4 Production already contains a working example of the D2 case

This is the most useful correction, because it changes what the lab most needs
to find out.

`InomrahsMIToggle` is:

- a `SecureHandlerClickTemplate` button,
- **a child of the production root `InomrahsMIFrame`**,
- 1×1, anchored TOPLEFT, never hidden itself,
- the owner of its own override binding via
  `SetOverrideBindingClick(toggleButton, true, key, toggleButton:GetName())`,
- carrying `TOGGLE_SNIPPET`, which does `window:IsShown()` then `Show()`/`Hide()`.

When the window is closed, the root is hidden, so the toggle button is
inherited-hidden — and **the key still fires it and still shows the root.** That
is D2 and D4 in one, already working in production, for a
`SecureHandlerClickTemplate`.

What this does **not** establish, and what the lab still must measure:

- whether a **`SecureActionButtonTemplate`** behaves the same way when
  inherited-hidden (the brief is right to insist these be tested separately);
- whether it holds **in combat** — the toggle is normally pressed out of combat;
- whether `SetBindingClick` applied from inside a snippet behaves like
  `SetOverrideBindingClick` applied from outside one.

**Recommendation:** keep D2/D3/D4 exactly as specified, but tell the lab to
report this precedent alongside the measurement so the result is read in
context. If the action button behaves differently from the handler button, that
difference is the finding.

### 1.5 Small API errors in the method lists

- `IsClippedToScreen` (§11) is not an API. The pair is
  `SetClampedToScreen` / `IsClampedToScreen`. Probing a name that does not exist
  will always report absent and mean nothing.
- `SetClipsChildren` is listed twice in §D9.
- `SetMouseClickEnabled` does exist on Frame in current clients; worth keeping.

### 1.6 §12D — the sidebar overlap is real, and I can explain it

`[FAIL] dungeon column -- list over hint` is genuine. The cause:

- the dungeon list's scroll frame ends 106px above the sidebar's bottom
  (`layoutSidebar`, when the hint is showing);
- the hint sits above the name box, which sits above **New dungeon**, which sits
  above **Back**, and is two wrapped lines tall;
- those stack to roughly 110px, so the hint's top crosses the list's bottom by a
  few pixels.

The offline geometry suite misses it because it models font metrics
approximately, and the real overlap is about 4px. The in-game check caught it
precisely because it uses the client's real measurements — which is the whole
argument for the self-test existing.

The fix is one number. See §4 for the decision.

### 1.7 Everything else in §2 checks out

`Runtime.EnsureManager`, `Runtime.BindArrow`, `FLIP_SNIPPET`, `BIND_BODY`,
`InomrahsMIPager` (a `SecureHandlerBaseTemplate`), `InomrahsMIPageN`,
`InomrahsMIBtnN_M`, `Runtime.Build/ShowPage/ApplyBindings/SetPageKeys/
CurrentPage/Page/PageButtons/HideAll`, `InomrahsMIFrame`, `InomrahsMINext`/
`InomrahsMIPrev` as `SecureHandlerClickTemplate` — all present as described.
The data model tree is correct.

---

## 2. Hazards

Ordered by how much damage they do if not addressed.

### 2.1 Taint — the one way this lab can break the real addon

Not mentioned in the brief, and it is the only serious risk here.

If insecure lab code touches a production secure frame — even reading certain
fields, even holding a reference that later flows into a secure code path — the
taint spreads, and the **production** addon's combat behaviour breaks for the
rest of that session. The player would see callout buttons stop firing mid-key
and have no idea the test addon caused it.

**Required rules, stricter than §16:**

- the lab creates its own hierarchy and never passes a production frame to
  `SetFrameRef`, `SetAttribute`, or any snippet;
- the lab never calls `ClearOverrideBindings` on a production frame;
- production frames may be *read* for the report (`GetWidth`, `IsShown`) and
  nothing else;
- the report should state, per run, whether it touched any production frame, so
  a later "the addon broke after I ran the lab" is answerable.

### 2.2 `ClearBindings` wipes every binding the header owns

§C asks whether the mode system can clear or overwrite page-specific bindings.
It can, easily, and the brief does not name the mechanism.

Production's `BIND_BODY` calls `ClearBindings()` on the manager and then
re-applies **all** of that page's keys. `ClearBindings` is not selective — it
drops everything that header owns. So if the lab gives mode keys and page keys
to the same header, the first mode switch silently deletes the page keys, and
§C reports a failure that is the lab's own bug rather than a client limitation.

**Recommendation:** two separate binding owners —

- `InomrahsMISelfTestLabPager` owns page/action bindings;
- `InomrahsMISelfTestLabModer` owns mode bindings;

and one deliberate probe that **does** put both on one header, so we measure the
collision on purpose and can report it as a real constraint for the production
design. That answer is worth having; discovering it by accident is not.

### 2.3 `/say` is unreliable evidence

§D wants `CHAT_MSG_SAY` observation. Four problems:

1. **Server-side throttling.** Repeated identical chat messages get dropped. The
   lab presses the same action many times, so a genuine execution can produce no
   event. That reads as `NO` when the truth is `YES`.
2. **Zone restrictions.** `/say` is suppressed in some instanced content.
3. **Other players see it.** Doing this at a city dummy spams `[IMI LAB] PAGE 1
   ACTION` to everyone nearby.
4. It cannot distinguish "the button fired and chat was throttled" from "the
   button did not fire", which is precisely the distinction the lab exists for.

**Recommendation — primary evidence is a counter, not chat:**

```text
macrotext = "/run InomrahsMISelfTestFired(1)"
```

A macro containing `/run` executes ordinary Lua **because the macro ran**. That
is direct evidence the secure button fired, not inference from a binding being
registered — the thing §14 forbids is inferring from *registration*, and this is
observation of *execution*. It cannot be throttled, works in any zone, and is
silent.

Keep `/say` as an optional second line in the same macro for human-visible
confirmation, off by default, with a toggle. Report both.

One thing to measure rather than assume: whether `/run` inside macrotext is
itself permitted when the button fires during combat. The first phase should
establish that out of combat and then in combat, and fall back to `/say` if not.

### 2.4 A live mob is the wrong combat source

§9 says "a harmless solo mob". The lab needs seven phases of combat with many
steps. A mob dies, or kills the player, and combat drops mid-phase.

**Recommendation:** a **training dummy**. They exist in every major city, keep
you in combat indefinitely, cannot die, and cannot kill you. The instruction
should name them specifically. It also removes the risk of the player dying
while the lab has a protected frame parked off-screen.

Second point: the lab should **detect** the combat drop and say so in the
report, rather than recording a phase as inconclusive without explanation.

### 2.5 Hardware-event tests cannot be sequenced by the lab

Most of §9 requires the human to press things in order, in combat, while
reading. Seven phases of that is a lot to hold. If the sequence is only in a
report the player has to scroll, they will lose their place and the results will
have gaps.

**Recommendation:** an on-screen step panel — one line saying what to do now, a
**Done / next step** button, and auto-advance where the lab can observe the step
completed (attribute changed, counter incremented). The player follows a single
instruction at a time rather than a document.

### 2.6 A snippet that errors produces "action blocked" spam

Particularly likely with the `SecureHandlerWrapScript` + `OnMouseWheel`
experiment (§G5), where the wrap may succeed and the snippet then do something
refused. Every wrap must be `pcall`ed, removable, and off by default until the
player opts into that specific probe.

### 2.7 Report volume

The full matrix plus per-test detail for §§A–G is likely 250–400 lines. That is
awkward to read in the window and awkward to paste.

**Recommendation:** `/imitest runlab report` prints the condensed matrix plus
anything that failed or was inconclusive; `/imitest runlab copy` gives the full
detail. §8 already implies this split; make it explicit.

---

## 3. A route the brief does not consider — and it may be the answer

§D and §E assume that making the Run visuals disappear while keeping keybinds
alive requires **secure** show/hide of prebuilt visual children, driven by a
hardware click. That is a lot of machinery, and it may be unnecessary.

**Alpha and scale are not protected properties.**

Combat lockdown protects a specific set of operations on protected frames:
showing, hiding, moving, resizing, reparenting, changing secure attributes. As
far as I know it does **not** protect alpha. If that holds on 12.1, then:

```lua
runRoot:SetAlpha(0)      -- ordinary insecure Lua, during combat
```

would make the entire Run hierarchy invisible while every button remains shown,
positioned, sized, mouse-enabled and key-triggerable — because nothing about it
actually changed except how it is drawn.

If true, that is Minimal Run, in one line, from ordinary code, with no secure
manager, no prebuilt visual children, and no hardware-click requirement. It
would also mean mode switching in combat needs no secure path at all, which
collapses §A, §B and §E to a much smaller problem.

**I am not asserting this works.** It is exactly the kind of claim this project
has been burned by assuming. But it is cheap to measure and it changes the
architecture more than anything else in the brief, so it should be measured
**first**, not last.

**Proposed probes, all insecure Lua, in combat, on a hierarchy containing a
protected `SecureActionButtonTemplate`:**

| # | operation | expected under current understanding |
| --- | --- | --- |
| P1 | `SetAlpha(0)` on the root | allowed |
| P2 | key on the action button while alpha 0 | executes |
| P3 | mouse click on the action button while alpha 0 | probably executes — worth knowing, it may need `EnableMouse(false)` alongside |
| P4 | `SetAlpha(1)` restore | allowed |
| P5 | `SetScale(0.7)` on the root | unknown — scale may be protected |
| P6 | `EnableMouse(false)` on the protected button | probably refused |
| P7 | `SetAlpha(0)` on a single visual child only | allowed |

If P1/P2/P4 come back `YES`, tell GPT before it designs anything around secure
visual children: the honest architecture becomes "alpha for visibility, secure
handlers only for the things that genuinely need them" — page flips and the
bindings themselves.

If they come back `NO`, we have lost twenty lines of probe and gained a
measured fact, and the rest of §D/§E proceeds as written.

---

## 4. Decisions needed before implementation

Answers to these change what gets built. My recommendation is on each.

**Q1 — Evidence mechanism.**
`/run` counter as primary evidence with optional `/say`, per §2.3?
*Recommend: yes.*

**Q2 — Combat source.**
Instruct a training dummy rather than a mob?
*Recommend: yes.*

**Q3 — Measure the alpha route first (§3)?**
It is cheap and may remove a third of the brief.
*Recommend: yes, as Phase 0.5, before any secure mode machinery is written.*

**Q4 — Binding owners.**
Separate owners for mode and page bindings, plus one deliberate collision probe
(§2.2)?
*Recommend: yes.*

**Q5 — Staging.**
This is the largest single task in the project so far — realistically a new
~1200-line `RunLab.lua`, changes to `SelfTest.lua` and the `.toc`, plus the
guided panel. Split into two shippable stages so measurements arrive sooner?

- **Stage 1** — skeleton, rescue control, step panel, method inventories (§11),
  the alpha probes (§3), §D hidden-state action viability, §F geometry effects.
  *Answers: can Minimal exist, and can Compact change geometry in combat.*
- **Stage 2** — §A/§B/§C mode switching and page interaction, §E visual
  children, §G scrolling folded together with the 0.8 probes.
  *Answers: how mode switching is driven, and whether combat scrolling exists.*

*Recommend: yes, staged.* One long run producing everything at once also means
one long combat session where a single mistake invalidates a phase.

**Q6 — The sidebar overlap (§12D).**
Leave it, or fix it now? It is one number, it is a real bug you can see, and
fixing it does not touch anything the lab measures.
*Recommend: fix it separately from this work, in its own version, so the lab
change set stays clean.*

**Q7 — Temporary chords.**
`CTRL-SHIFT-F8`–`F12` are valid syntax and unlikely to collide. Note for GPT:
several hard requirements in §6 are free rather than difficult —
`SetOverrideBindingClick` never touches saved bindings and **cannot** persist
through a reload, so "must not survive logout" and "must not be saved to
SavedVariables" are structurally guaranteed, not things to engineer.
*Recommend: accept the suggested chords.*

**Q8 — Report split.**
`report` = matrix + failures, `copy` = everything (§2.7)?
*Recommend: yes.*

---

## 5. What I am not raising as a problem

For completeness, so GPT knows these were considered and accepted as written:

- the synthetic lab structure in §5 — sound, and mirrors production correctly;
- the rescue control design in §7A — production's own toggle proves the
  mechanism;
- the refusal to accept `:Click()` as evidence (§14) — correct, and matches what
  production already measured;
- the Secret Value defensiveness (§15) — the self-test already works this way
  and the lab will inherit it;
- the "do not implement yet" list (§18) — no objection;
- the reporting format (§10) — good, and the per-result fields are the right
  ones.
