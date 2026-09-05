# Claude Engineering Prompt — Build a Combat Run Capability Lab for Inomrah's Mythic Instructions

## Read this first

You are working on **Inomrah's Mythic Instructions**, a World of Warcraft *Midnight* addon for client build **12.1.0 / 120100**.

Use the current production addon as the source of truth:

- **InomrahsMythicInstructions v0.41**
- Companion test addon currently **InomrahsMISelfTest v0.7**

You should have both addon folders available. Inspect the code before changing anything, especially:

- `Runtime.lua`
- `UI.lua`
- `Binds.lua`
- `Capture.lua`
- `Style.lua`
- `Core.lua`
- `Main.lua`
- the self-test addon's `SelfTest.lua`
- `Manifest.lua`
- both `.toc` files

Do **not** assume the architectural description below is more authoritative than the actual v0.41 source. If the source differs, report the difference explicitly.

This task is **not a UI redesign** and is **not a request to implement Full/Compact/Minimal Run in the production addon yet**.

The purpose of this task is to extend the companion self-test into a deliberately isolated **Run Capability Lab** that experimentally establishes what the WoW 12.1 secure/restricted environment actually permits during combat.

The results of this lab will be used to decide the architecture of a later UI redesign.

The guiding rule of this project is:

> **Measure the live client. Do not infer combat capabilities from API names, documentation, normal-frame behavior, or whether a call throws.**

WoW often silently refuses protected operations. A successful function call is not proof. The test must measure the resulting state/effect.

---

# 1. Why this lab is needed

The production addon is a prepared Mythic+ callout board.

The relevant existing data model is:

```text
Profile
└── Dungeon                 -- internally called category
    └── Variant
        ├── Enemy           -- CURRENT internal/UI name; terminology may change later
        │   └── Line        -- chat instruction or explicit macro command
        └── Page
```

Important terminology warning for this task:

- In current v0.41 code, the card-like object is called **Enemy**.
- The future UI may rename that concept because it can represent a boss, route note, utility note, Bloodlust, etc.
- **Do not rename Enemy in this task.**
- Do **not** introduce “Group” as a new production term in this task either. In Mythic+ jargon “group” can mean a pack of mobs and could create a different ambiguity.
- In comments inside the test lab, if you need a neutral term, use **content card**, **card**, or **enemy/card**.
- The terminology redesign belongs to the later UI design pass.

A Line currently behaves as follows:

- plain text gets a chat command prepended according to the page/dungeon/profile channel;
- text beginning with `/` is executed as written as macro text;
- one Line is therefore potentially either a callout **or a manually triggered macro action**.

Pages are more than pagination: page-specific keybinds make a page a manually selected contextual action set.

The production addon deliberately does **not** detect dungeon state, casts, bosses, group composition, etc. The player chooses the dungeon/page and presses the action. Preserve that philosophy.

---

# 2. Existing secure architecture that must be understood before writing the lab

Inspect v0.41, but at present the important architecture includes:

## `Runtime.lua`

Current comments document these measured facts:

- production callouts use `SecureActionButtonTemplate`;
- `macrotext` works in combat when prepared out of combat;
- `SetAttribute` from ordinary/insecure code is blocked in combat;
- ordinary `Hide()` on a frame with protected children is blocked in combat;
- pages are prebuilt out of combat;
- current page flipping occurs inside a secure-handler snippet;
- the page manager owns override bindings;
- the manager's secure snippet calls `ClearBindings()` and `SetBindingClick()` so the same physical key can target a different line after a page flip.

Relevant production structures/functions include, at minimum:

- `Runtime.EnsureManager`
- the secure pager manager `InomrahsMIPager`
- `Runtime.BindArrow`
- `FLIP_SNIPPET`
- `BIND_BODY`
- per-page secure frames `InomrahsMIPageN`
- per-line `SecureActionButtonTemplate` buttons `InomrahsMIBtnN_M`
- `Runtime.Build`
- `Runtime.ShowPage`
- `Runtime.ApplyBindings`
- `Runtime.SetPageKeys`
- `Runtime.CurrentPage`
- `Runtime.Page`
- `Runtime.PageButtons`
- `Runtime.HideAll`

Do not casually change these production paths for the purpose of testing.

## `UI.lua`

Current production root is `InomrahsMIFrame`.

Relevant facts include:

- root itself is a normal Frame but contains protected descendants;
- current open/close has a hidden secure handler button `InomrahsMIToggle`;
- that handler can `Show()` / `Hide()` the root from restricted code;
- the current Run previous/next buttons are secure handlers;
- normal view switching / resizing / moving are refused during combat;
- current Run content is in a `ScrollFrame`;
- ordinary `ScrollFrame:SetVerticalScroll()` was tested in combat and stayed at zero.

The existing restricted-environment probe has measured frame handles exposing:

```text
Show
Hide
IsShown
SetWidth
SetHeight
SetPoint
ClearAllPoints
SetAttribute
GetAttribute
GetFrameRef
```

and the secure header exposing:

```text
ClearBindings
SetBindingClick
SetBinding
```

It has measured these as absent in that restricted context:

```text
StartMoving
StopMovingOrSizing
StartSizing
```

Do not extrapolate beyond those measurements.

## Current observed combat-scroll result

The user has already run the live self-test on client 120100 with a genuinely overflowing Run page.

Ordinary insecure code:

```lua
scroll:SetVerticalScroll(target)
```

during combat resulted in:

```text
scrolling the callouts -- refused — it stayed at 0
```

The user also manually confirmed that the Run list could not be mouse-wheel scrolled in combat.

This proves only that **the current ordinary scroll path does not work**.

It does **not** yet prove any of these:

- that `SetVerticalScroll` cannot work from a secure/restricted snippet;
- that a secure scroll button cannot move the content;
- that a page/content frame cannot be re-anchored inside a clipping viewport;
- that `OnMouseWheel` cannot be securely wrapped;
- that a custom secure scroll implementation is impossible.

The existing separate combat-scrolling investigation may continue, but this new Run Capability Lab should include compatible probes so we get one coherent capability report.

---

# 3. Future Run presentation concepts — THESE DO NOT EXIST YET

You must understand these because the lab needs to test whether they are technically possible.

Do **not** assume the current production addon already has them.

Do **not** implement polished versions of them.

Do **not** invent final visuals.

They are conceptual future presentation states of **the same Run data and secure actions**.

## FULL RUN — future concept

Purpose:

- primarily mouse-first;
- closest to current normal Run;
- dungeon/page context visible;
- enemy/card headings visible;
- normal readable clickable callout buttons visible;
- optional keybind badges;
- intended to remain open through a dungeon.

It should favor legibility and forgiving mouse hit targets.

## COMPACT RUN — future concept

Purpose:

- hybrid mouse + keybind use;
- same current page and same underlying actions;
- still clickable;
- significantly reduced nonessential chrome;
- denser visual presentation than Full;
- exact final layout is intentionally undecided.

Do not assume “Compact” merely means `SetScale(0.8)`.
The eventual UI may change spacing, button treatment, sidebar visibility, card layout, etc.

The lab's job is to determine which combat-safe primitives are available, not to design Compact.

## MINIMAL RUN — future concept

Purpose:

- keybind-first;
- for players who know their contextual bindings and want almost no UI obstruction;
- likely visible information is only:
  - dungeon identity;
  - current page identity / page number;
  - previous/next page controls;
  - Run presentation-state control;
- normal callout buttons are probably **not visibly shown**;
- perhaps enemy/card names could be optionally shown later, but that is not decided.

The critical engineering question is:

> Can the secure callout infrastructure remain alive and key-triggerable while its normal visual representation is hidden, clipped, parked, collapsed, or otherwise removed from view?

If a fully hidden production root causes keybound callouts to stop working, that is not necessarily a failure. Minimal Run may become the supported “background” state instead.

## Mode switching requirement being investigated

The intended product direction is:

- presentation switching should be available directly from Run;
- it should be fast;
- ideally it should work during combat;
- it should likely be keybindable;
- users may eventually have:
  - one `Cycle Run mode` binding;
  - and optionally direct bindings for Full / Compact / Minimal.

A dropdown is **not** the intended combat interaction. The eventual UI is more likely a direct three-state control / segmented control or another one-action-per-state mechanism.

Again: the lab must not implement the final UI. It must determine whether the required secure state changes can work.

---

# 4. Primary questions the lab must answer

The lab must answer these with live, effect-based tests.

For each question, report one of:

- `YES — observed`
- `NO — observed refusal`
- `INCONCLUSIVE — <reason>`
- `NOT AVAILABLE — API/method absent`

Do not turn expected client limitations into scary generic `[FAIL]` lines. This is a capability survey. A “No” may be a completely valid result.

## A. Combat mode-state switching

Can a hardware click on a secure handler, while in combat:

1. change a secure `mode` attribute;
2. switch between three predeclared mode states;
3. show/hide prebuilt presentation frames;
4. resize protected frames/ancestors;
5. re-anchor protected frames/ancestors;
6. show/hide visual-only child frames while leaving the secure action button itself alive?

Test actual effect after each operation.

## B. Keybind-driven mode switching

Can a temporary override binding, owned/applied through a secure manager, activate during combat:

1. `Full`;
2. `Compact`;
3. `Minimal`;
4. `Cycle mode`;

and produce the same secure state transition as physically clicking the mode control?

## C. Page switching after a mode switch

Starting in combat:

1. current page = page 1;
2. switch mode;
3. page forward;
4. verify page 2 is actually current;
5. verify its page-specific action binding is the live one;
6. switch mode again;
7. page backward;
8. verify page 1's action binding returns.

The mode system must not accidentally clear or overwrite page-specific bindings.

## D. Callout key viability under different visibility strategies

This is one of the most important parts of the lab.

Create a synthetic secure action for page 1 and page 2 with clearly distinguishable effects.

Prefer to test **actual `SecureActionButtonTemplate` execution**, not only a generic secure handler, because hidden/shown behavior may differ between them.

A simple explicit lab-only macro is acceptable, for example:

```text
/say [IMI LAB] PAGE 1 ACTION
/say [IMI LAB] PAGE 2 ACTION
```

The lab should listen for the user's own exact `CHAT_MSG_SAY` message if practical and record that the secure action truly executed. Do not infer success merely from a handler receiving a binding.

If chat-event observation becomes unreliable, provide both:
- a secure-handler counter probe;
- and the visible chat macro as a manual confirmation.

Test the same action key under each of the following states:

### D1. Normal
Root shown, page shown, button shown.

### D2. Entire lab/Run root hidden
Manager/target hierarchy should mimic production as closely as practical.

Question:
- does the action binding still execute while the root and button are inherited-hidden?

Also:
- can a dedicated secure mode/show key restore the root in combat?

### D3. Page/ancestor hidden
Root shown, active page wrapper hidden.

Question:
- does the bound secure action still execute when the action button is hidden only through an ancestor?

### D4. Secure action button itself hidden
Question:
- does `SetBindingClick` still invoke a hidden `SecureActionButtonTemplate`?

### D5. Secure action button remains shown, but its visual child wrapper is hidden
Create the synthetic action button with its *visual presentation* inside a separate child Frame so that the visual child can be independently shown/hidden by secure code.

Question:
- can the button remain secure-action-capable and binding-capable while the separate presentation Frame is hidden?

This is a key candidate for future Minimal Run.

### D6. Secure action button remains shown but is clipped out of view
Place it inside a clipping viewport / ScrollFrame-like arrangement.

Question:
- if the button is still technically shown but not visible because its region is clipped, does its override binding still execute?

### D7. Secure action button remains shown but is securely moved/re-anchored out of the visible content region
Question:
- does the key still execute?
- can it be restored in combat?

### D8. Secure action button remains shown but is securely resized to an extremely small dimension
Test `SetWidth`/`SetHeight` from secure code on the actual protected button or suitable protected ancestor.

Do **not** use exactly zero unless you first establish that zero dimensions are safe. Start with e.g. 1×1.

Question:
- does binding execution persist?
- can normal geometry be restored in combat?

### D9. Alpha / scale only if actually available
The current restricted probe did not report `SetAlpha` or `SetScale`.

Extend the method-availability probe to include at least:

```text
SetAlpha
GetAlpha
SetScale
GetScale
SetShown
SetAllPoints
SetParent
EnableMouse
SetMouseClickEnabled
SetClipsChildren
SetClipsChildren
```

Do not assume any of these exist in the restricted handle.

If `SetAlpha` or `SetScale` is available, test effect.
If absent, report absence and move on.

Do not build a future architecture around a method merely because ordinary Lua frames have it.

## E. Visual-only presentation switching

Because restricted code cannot be assumed to call `FontString:SetText()` or change arbitrary style data, test a **prebuilt visual-state pattern**:

- one secure action button remains constant;
- it has prebuilt child Frames for e.g. `fullVisual`, `compactVisual`, `minimalVisual`;
- each child frame contains whatever nonsecure regions are needed (textures/fontstrings) but the containing child Frame is the object the secure handler references;
- combat mode switch only calls `Show()` / `Hide()` on these child Frames.

Questions:

1. Can the secure handler show/hide those child Frames during combat?
2. Does the secure action button remain usable with mouse in the visual states where it should?
3. Does the keybinding remain usable in all states where the button is technically shown?
4. Does hiding a visual child affect the protected status/operation of the parent?
5. Can the child visual states be switched repeatedly without becoming stuck?

This probe is deliberately architectural, not aesthetic.

## F. Protected hierarchy geometry changes

The current restricted probe says `SetWidth`, `SetHeight`, `SetPoint`, and `ClearAllPoints` are present on a frame handle.

That does **not** prove the calls succeed on a frame that is protected or has protected descendants.

Test effect during combat on:

1. a plain frame;
2. a `SecureHandlerBaseTemplate` frame;
3. a `SecureActionButtonTemplate`;
4. a plain ancestor containing a protected action button;
5. a secure page ancestor containing a protected action button;
6. a clipping viewport/scroll child hierarchy containing protected actions.

For each of:

- width;
- height;
- anchor / point;
- show/hide.

Record before/requested/after values with a tolerance for floating-point geometry.

Do not use exact equality for frame dimensions.

Recommended tolerance:

```lua
math.abs(actual - requested) < 0.01
```

or another explicitly justified tolerance.

This is directly relevant to whether Full/Compact/Minimal can use one secure hierarchy whose layout changes in combat.

## G. Combat scrolling capability

Preserve the already known result:

> Current insecure `ScrollFrame:SetVerticalScroll()` is refused while combat-locked.

Then test possible secure alternatives separately.

### G1. Method availability on actual ScrollFrame handle in restricted code

The old restricted probe uses a generic target frame. Add a separate actual `ScrollFrame` probe and report whether its restricted handle exposes:

- `GetVerticalScroll`
- `SetVerticalScroll`
- `GetVerticalScrollRange`
- `GetScrollChild`
- `SetScrollChild`
- `UpdateScrollChildRect`
- `SetHorizontalScroll`
- any other scroll-specific methods Claude finds relevant **after inspecting the live API surface**

Do not make absence/presence claims from normal Lua methods.

### G2. Secure hardware button -> restricted `SetVerticalScroll`

If `SetVerticalScroll` appears available in the restricted handle:

- prebuild a secure scroll-down handler;
- click it physically in combat;
- request a known nonzero offset;
- read the real offset afterward;
- verify content visibly moved;
- restore it with another secure handler.

If the method is absent, do not attempt to call it.

### G3. Secure repositioning instead of ScrollFrame offset

If a protected page/content host can be re-anchored during combat:

- place it inside a viewport that clips;
- a secure scroll-down button changes its Y anchor by a known amount;
- verify the real top/bottom/point changed;
- verify content visibly moved;
- verify an action button that becomes visible after the move is still clickable and key-triggerable;
- verify restoring to top works.

This is a serious candidate architecture and must be tested even if `SetVerticalScroll` itself fails.

### G4. Secure custom scrollbar/thumb feasibility

Do not implement polished scrollbar UI.

Only determine whether:
- a secure handler can reposition a prebuilt thumb frame in combat;
- the thumb can remain synchronized with a secure stored offset.

If yes, record it as a capability.

### G5. Mouse wheel -> restricted secure path

Do not assume `OnMouseWheel` is a valid secure hardware path.

Probe availability of any relevant API such as `SecureHandlerWrapScript` on this client.

If available, create the smallest possible isolated experiment:

- a wheel-enabled frame;
- a secure handler/header;
- securely wrap an `OnMouseWheel` path if the API permits;
- wheel during combat;
- have restricted code update a secure attribute or move a test content frame;
- verify the state actually changes.

If the wrapping API refuses `OnMouseWheel`, the wheel event never enters the restricted snippet, or the effect is blocked, report precisely where the chain fails.

Do not “solve” this by calling a protected button's `:Click()` from ordinary `OnMouseWheel`; production comments already say scripted secure clicks are refused.

### G6. Secure up/down scroll buttons

Even if mouse-wheel secure scrolling is impossible, test whether explicit secure scroll up/down buttons can work.

This distinction matters:
- mouse wheel may be impossible;
- direct secure scroll controls may still be viable.

Report those independently.

---

# 5. The lab must mimic production security characteristics without modifying production state

The safest design is a **synthetic lab**, not destructive manipulation of the user's real dungeon/profile.

Create the lab entirely inside the companion self-test addon.

Do not write test dungeons into the user's profile.
Do not change existing page bindings.
Do not change production SavedVariables.
Do not send or replace profile data.
Do not reuse the user's current callout text.

The synthetic lab should include at least:

```text
Lab Root
├── always-available rescue control
├── secure manager/header
├── mode controls
│   ├── Full
│   ├── Compact
│   ├── Minimal
│   └── Cycle
├── page navigation controls
│   ├── Previous
│   └── Next
├── clipping/scroll viewport
│   ├── Page 1
│   │   └── synthetic secure action button
│   └── Page 2
│       └── synthetic secure action button
└── status/diagnostic presentation
```

The actual final architecture may differ. This structure is only intended to probe capability.

Where possible, mirror production template choices:

- pager/manager: `SecureHandlerBaseTemplate`
- page switch controls: same secure handler template pattern as production
- action targets: `SecureActionButtonTemplate`
- mode controls: secure handlers suitable for a hardware click
- binding owner: secure manager using the same `ClearBindings` / `SetBindingClick` mechanism as production

Do not combine multiple secure templates on one frame merely for convenience. The project has previously broken controls by assuming template combinations would compose cleanly.

If a test needs a different template, isolate it as a separate probe and label it.

---

# 6. Temporary test keybinds

We need to prove actual key-triggered behavior, but this tester must not become another source of keyboard lockouts or permanently steal player bindings.

## Hard requirements

- No test binding may be persisted in SavedVariables.
- No test binding may survive closing/disabling the lab.
- No test binding may survive logout/reload due to the test addon saving it.
- All temporary override bindings must have one obvious cleanup owner.
- Provide a one-click **Clear test bindings** action out of combat.
- Clear test bindings automatically when the lab is torn down.
- If possible, clear them automatically on logout/player leaving world.
- Do not alter the user's normal Blizzard keybinds.
- Do not overwrite production addon settings such as `pageNextKey`, `pagePrevKey`, or `toggleKey`.

## Avoid new keyboard-capture code if possible

The production project has had two previous full keyboard lockouts.

Do **not** invent a new long-lived `EnableKeyboard(true)` capture system just for this lab.

Preferred options, in order:

1. Use explicit temporary hard-coded lab chords that are clearly shown and only active while the lab is armed.
2. Before arming them, report whether they appear to have an existing binding if the client exposes that safely.
3. Use override bindings owned by the lab, so cleanup is centralized.
4. If you absolutely need configurable test keys, reuse the production addon's already-defensive key-capture helper rather than writing another capture mechanism, and preserve every release path and timeout.

Suggested temporary chords if they are valid on this client and do not conflict with something critical:

```text
CTRL-SHIFT-F8   = Full
CTRL-SHIFT-F9   = Compact
CTRL-SHIFT-F10  = Minimal
CTRL-SHIFT-F11  = Cycle
CTRL-SHIFT-F12  = Synthetic page action
```

You may choose safer valid chords after checking WoW key syntax.

The exact keys do not matter. The report must print them.

A visible click path must also exist for every state change so a keybind failure does not strand the lab.

---

# 7. Absolute failsafes

This lab will intentionally test hiding/resizing/repositioning protected hierarchies in combat. It must therefore be harder to get stuck than the thing it is testing.

## A. Rescue control

Create an **always-visible rescue/show control** that is:

- parented outside the lab root whose visibility is being tested;
- prebuilt out of combat;
- a secure hardware-click handler;
- able to `Show()` and restore the lab root using only already-measured restricted operations;
- never hidden as part of a test state.

Label it unmistakably, e.g.:

```text
RESTORE LAB
```

This is test-only UI, so visual elegance does not matter.

## B. Reset after combat

On `PLAYER_REGEN_ENABLED`, ordinary code may restore all lab geometry/visibility/bindings to baseline.

If any test state cannot be safely undone during combat, record that fact and restore immediately when combat ends.

## C. No test-created keyboard focus

The lab should not auto-focus EditBoxes.

The `/imitest` report window's existing keyboard-release principles remain in force.

After every lab teardown/report:
- no self-test frame may own keyboard focus;
- no test frame may have keyboard input enabled unless explicitly part of a short bounded capture;
- run the self-test's keyboard ownership audit.

## D. Idempotence

These operations should be safe to repeat:

```text
/imitest runlab setup
/imitest runlab setup
/imitest runlab reset
/imitest runlab reset
```

Do not leak a new frame tree every time.

Reuse a frame pool or create once.

---

# 8. Suggested command surface

Integrate the lab with `/imitest` rather than creating another slash-command namespace unless there is a strong reason.

A suggested command set:

```text
/imitest runlab
/imitest runlab setup
/imitest runlab help
/imitest runlab preflight
/imitest runlab arm
/imitest runlab status
/imitest runlab combat
/imitest runlab report
/imitest runlab copy
/imitest runlab reset
/imitest runlab release
```

Exact wording may change, but the user workflow must be simple.

## `/imitest runlab setup`

Out of combat only.

- lazily builds the synthetic secure lab;
- resets it to known baseline;
- does not arm temporary keybinds unless explicitly requested;
- opens a small instruction panel;
- performs noncombat structural validation;
- records client build and addon/test versions.

## `/imitest runlab preflight`

Out of combat only.

Verify:
- all expected frames/templates built;
- all needed frame refs set;
- action macros prepared;
- mode attributes prepared;
- page count/index prepared;
- rescue button wired;
- no temporary binding currently active unexpectedly;
- root/page/action visibility baseline;
- geometry baseline;
- relevant restricted method-availability probes.

## `/imitest runlab arm`

Out of combat only.

- applies temporary override bindings;
- prints exact chords;
- prints a large warning that these are test-only;
- tells the user to fight a harmless solo mob;
- never modifies production bindings/settings.

## `/imitest runlab combat`

This command itself may perform **insecure baseline attempts** such as current `SetVerticalScroll`, but it cannot substitute for hardware tests.

It should report the current secure attributes/effects already generated by the user's hardware clicks/keys.

Do not use this command to fake hardware events.

## `/imitest runlab status`

May be run during combat.

Print concise state:
- combat yes/no;
- current lab mode;
- current page;
- lab root shown?
- active page shown?
- active action shown?
- test action execution count if observable;
- last detected synthetic chat action;
- scroll offset / content anchor;
- temporary bindings armed?
- whether rescue path exists.

Be careful reading secret values; follow the existing self-test's guarded access approach.

## `/imitest runlab report`

Prefer after combat.

Produces the detailed capability matrix.

## `/imitest runlab copy`

Opens copyable report text using the existing safe report-window infrastructure.

## `/imitest runlab reset`

Out of combat:
- restore baseline geometry;
- show all required frames;
- mode Full;
- page 1;
- top scroll position;
- clear temporary binding owner;
- clear transient lab results if appropriate;
- do not destroy frame objects.

## `/imitest runlab release`

Emergency cleanup:
- give keyboard back;
- clear test bindings;
- show/restore frames;
- remove test `OnUpdate`/event state;
- preferably usable even if a normal lab path failed.

---

# 9. Guided in-game test sequence

The lab should give the user a numbered sequence rather than requiring them to invent steps.

A good test workflow would be something like this.

## Phase 0 — out of combat

1. `/imitest runlab setup`
2. `/imitest runlab preflight`
3. `/imitest runlab arm`
4. Verify the visible synthetic action works out of combat.
5. Verify page next/previous works out of combat.
6. Verify Full/Compact/Minimal/Cycle controls work out of combat.
7. Reset to Full + Page 1.

The UI/report should explicitly say:

> Now enter combat against a harmless solo mob. Do not use this lab during a real key.

## Phase 1 — normal combat secure action

In combat:

1. Press synthetic Action key on Page 1.
2. Expected visible evidence: `[IMI LAB] PAGE 1 ACTION`.
3. Click/press Next Page.
4. Press same synthetic Action key.
5. Expected: `[IMI LAB] PAGE 2 ACTION`.
6. Previous Page.
7. Press action again.
8. Expected Page 1.

This establishes page-specific binding integrity before mode manipulation.

## Phase 2 — mode buttons by mouse

In combat:

1. Click Compact.
2. Confirm secure mode attribute changed and intended synthetic geometry/visibility change occurred.
3. Press action.
4. Click Minimal.
5. Press action.
6. Click Full.
7. Press action.

Record every effect separately.

## Phase 3 — mode switching by keys

In combat:

1. Press Compact test chord.
2. Verify actual state.
3. Press Minimal chord.
4. Verify.
5. Press Full chord.
6. Verify.
7. Press Cycle three times and verify sequence.

Do not report pass solely because the binding was registered. Read the resulting secure mode attribute / visibility / geometry.

## Phase 4 — page + mode combination

In combat:

1. Start Page 1 Full.
2. switch Compact;
3. next page;
4. press action -> must be Page 2;
5. switch Minimal;
6. press action -> test whether strategy permits;
7. previous page;
8. press action -> must be Page 1;
9. return Full.

This checks binding ownership collision.

## Phase 5 — hidden-state strategies

Run each strategy as an individually labeled subtest.

The lab must always provide a visible external rescue button.

Test:

- root hidden;
- page hidden;
- action button hidden;
- visual child hidden only;
- action clipped out of view;
- action re-anchored/parked;
- action resized small.

For each:
1. enter/apply state through secure hardware action while already in combat;
2. press Action key;
3. record whether actual secure action executed;
4. restore using a secure hardware path;
5. verify normal action still works after restoration.

Do not chain all hidden strategies into one opaque script; we need to know exactly which primitive caused failure.

## Phase 6 — scrolling

On a synthetic page tall enough to overflow:

1. ordinary mouse wheel / insecure path — confirm known refusal;
2. secure scroll down button if implemented;
3. secure scroll up;
4. if possible, mouse wheel through secure wrapper;
5. test key/click on action initially below the fold after it becomes visible;
6. restore top.

Record separately:
- ScrollFrame offset;
- content anchor;
- visual movement;
- action click/key viability.

## Phase 7 — post-combat recovery

Leave combat.

The lab should automatically or manually:
- restore Full;
- restore Page 1;
- restore geometry;
- restore scroll top;
- show all lab infrastructure;
- clear temporary bindings if lab session ends;
- verify no keyboard holder remains;
- produce report.

---

# 10. Reporting requirements

Do not return only `ok/fail`.

This lab is intended to produce an engineering capability matrix that can be pasted into another AI conversation.

Every result should include:

- **Capability name**
- **Context**: out of combat / combat
- **Trigger**: insecure Lua / secure mouse hardware click / temporary override key
- **Target type**
- **Requested operation**
- **Before**
- **Requested**
- **After**
- **Observed visible effect**
- **Action execution result if relevant**
- **Conclusion**
- **Any error/message**

Example:

```text
== Run Capability Lab: protected page ancestor geometry ==

[YES] secure SetHeight on ancestor containing SecureActionButton
  context: combat
  trigger: hardware click on SecureHandlerClickTemplate
  target: SecureHandlerBaseTemplate page containing protected action
  before: 260.0000
  requested: 120
  after: 120.0000
  action key after change: executed PAGE 1 ACTION
  restore in combat: yes
```

Example refusal:

```text
[NO] insecure SetVerticalScroll on Run-like ScrollFrame
  context: combat
  trigger: ordinary Lua
  before: 0
  requested: 24
  after: 0
  visible movement: no
  conclusion: silently refused
```

Example unavailable:

```text
[NOT AVAILABLE] SetVerticalScroll on restricted ScrollFrame handle
  method present in normal Lua: yes
  method exposed in restricted handle: no
  no call attempted
```

Example inconclusive:

```text
[INCONCLUSIVE] mouse-wheel secure wrapper
  SecureHandlerWrapScript exists
  wrapping OnMouseWheel succeeded out of combat
  but no restricted state change was observed in combat
  cannot distinguish event not entering wrapper from operation being refused
  next probe needed: wrapper should set a harmless secure attribute only
```

The report should end with a condensed matrix:

```text
== Architecture Summary ==

Combat page flip by secure click                     YES/NO
Combat page flip by override key                     YES/NO
Combat Full/Compact/Minimal state attr change        YES/NO
Combat mode switch by direct key                     YES/NO
Combat mode cycle key                                YES/NO

Callout key with root shown                          YES/NO
Callout key with root hidden                         YES/NO
Callout key with page hidden                         YES/NO
Callout key with action button hidden                YES/NO
Callout key with visuals hidden only                 YES/NO
Callout key while action is clipped                  YES/NO
Callout key while action is parked/reanchored        YES/NO
Callout key while action is 1x1                      YES/NO

Secure resize protected ancestor                     YES/NO
Secure re-anchor protected ancestor                  YES/NO
Secure show/hide protected ancestor                  YES/NO
Secure show/hide visual-only child                   YES/NO

Restricted ScrollFrame:SetVerticalScroll exists      YES/NO
Secure SetVerticalScroll effect                      YES/NO
Secure content-anchor scrolling                      YES/NO
Secure scroll buttons                                YES/NO
Secure mouse-wheel route                             YES/NO

Mode switch -> page switch -> correct page bind      YES/NO
Page switch -> mode switch -> correct page bind      YES/NO

Fully hidden root can be restored in combat          YES/NO
Lab recovered cleanly after combat                   YES/NO
Lab left keyboard focus behind                       YES/NO
Lab left temporary override bindings behind          YES/NO
```

Then add a plain-English section:

```text
== Implications for future Run UI ==

- Full/Compact/Minimal can/cannot be switched in combat because...
- A near-invisible Minimal mode can most safely be built by...
- Fully closing the root while preserving callout keybinds does/does not work.
- Mouse-wheel scrolling in combat is/is not viable.
- If mouse wheel is not viable, secure scroll buttons are/are not viable.
- Compact mode may/may not change protected geometry in combat.
- The safest architecture appears to be...
```

Do not overstate conclusions. Clearly distinguish:
- observed behavior;
- reasonable engineering inference;
- untested hypothesis.

---

# 11. Method-probe improvements

Expand the current restricted-environment method inventory.

The existing probe is useful but too generic for the upcoming architecture.

Create separate inventories for at least:

## Generic Frame in restricted env

Current list plus useful future-mode methods:

```text
Show
Hide
IsShown
SetWidth
SetHeight
GetWidth
GetHeight
SetPoint
GetPoint
ClearAllPoints
SetAllPoints
SetAlpha
GetAlpha
SetScale
GetScale
SetShown
SetParent
GetParent
EnableMouse
IsMouseEnabled
SetClipsChildren
IsClippedToScreen
SetAttribute
GetAttribute
GetFrameRef
```

Only include methods that can be safely inspected.

## SecureActionButton handle

Same relevant geometry/visibility list, because method exposure may differ.

## ScrollFrame handle

Scroll-specific list from section G1.

## Secure manager/header

Current list plus anything relevant to mode bindings.

Do not mark the entire lab failed because a nonessential method is absent.

---

# 12. Existing self-test defects to fix while touching the tester

Please make these small self-test maintenance corrections as part of this work unless there is a strong reason not to.

## A. Stale manifest must fail loudly

Current live report on v0.41 says:

```text
manifest built for -- 0.38
addon version -- 0.41
```

yet still reports `[ok]`.

That defeats the purpose of the manifest drift guard.

Requirements:

- regenerate `Manifest.lua` from **v0.41**;
- change the test so `manifest.builtFor ~= addon version` is a **failure/warning that cannot look like a pass**;
- continue checking every manifest function/frame/setting that the mechanism is intended to cover.

Do not hide drift.

## B. Floating-point resize false failure

Current combat check does exact:

```lua
frame:GetWidth() == 90
```

The live client returned:

```text
90.000007629395
```

after setting 90.

Change geometry equality to tolerant comparison.

Use a shared helper if this pattern occurs in several places.

For example:

```lua
local function approximately(a, b, epsilon)
    epsilon = epsilon or 0.01
    return type(a) == "number"
       and type(b) == "number"
       and math.abs(a - b) <= epsilon
end
```

Do not assume all geometry APIs round exactly.

## C. Preserve the current keyboard safety audit

Do not regress:

```text
no probe of ours holds the keyboard
the run left focus alone
```

The lab must participate in those checks.

## D. Do not “fix” the current sidebar geometry bug as part of this capability lab unless necessary

Current report also showed:

```text
[FAIL] dungeon column -- list over hint
```

That is a genuine UI/layout issue that belongs to the later redesign.

Do not mix unrelated production UI changes into this security/capability experiment.

You may preserve/report it.

---

# 13. Combat lockdown rules for the lab itself

The lab must differentiate:

## Setup operations
Allowed only out of combat:

- `CreateFrame`
- template construction
- `SetFrameRef`
- setting initial secure attributes/snippets
- writing macrotext
- establishing test bindings with insecure top-level API
- building page structures

If user tries `/imitest runlab setup` or structural rebuild in combat:
- refuse clearly;
- do not half-build.

## Operations being tested in combat
Must be initiated through the intended secure hardware route where that is the point of the test.

Never make a result look successful because the lab silently performed the operation after `PLAYER_REGEN_ENABLED`.

If something is deferred for cleanup, report:

```text
combat operation refused; restored after combat
```

not “success”.

---

# 14. Do not use simulated clicks as evidence

This is critical.

Production already observed that scripted `:Click()` on a secure handler is refused / not equivalent to a hardware event.

Therefore:

- do not use `button:Click()` from ordinary Lua to “test” combat mode switching;
- do not use `OnMouseWheel -> protectedButton:Click()` and declare success;
- do not use insecure event handlers that merely set a variable and then infer a secure action would work.

Tests whose question is “does a hardware secure path work?” require:
- actual mouse hardware click;
- actual temporary override binding;
- or a secure wrapper proven to execute from the hardware event.

The lab should display instructions when human interaction is required.

---

# 15. Secret Values / defensive reads

WoW 12.x may return Secret Values from arbitrary frames.

Follow the existing self-test's defensive pattern:

- guard frame enumeration;
- guard reads;
- do comparisons inside `pcall` where necessary;
- convert test results to plain booleans/strings before storing/reporting;
- never let one inaccessible frame abort the whole lab.

Do not perform broad arbitrary frame walks unless necessary.

The synthetic lab's own named frames should be directly referenced rather than rediscovered by enumeration.

---

# 16. Production-code isolation

Preferred outcome:

- all capability-lab code lives in `InomrahsMISelfTest`;
- production addon gets **zero behavioral changes** for this task.

If a production accessor is genuinely required to observe something:
- add the smallest read-only accessor possible;
- explain why;
- do not create a general test backdoor;
- do not change runtime behavior merely to make it easier to test.

The final CurseForge addon will not depend on the self-test addon.

The self-test is developer infrastructure only.

---

# 17. Performance

This is a tiny synthetic lab. Keep it simple.

Do not introduce:
- continuous per-frame polling unless a specific test needs it;
- heavy `OnUpdate` loops;
- frame enumeration every frame;
- combat-log scanning;
- dungeon/game-state detection.

If an `OnUpdate` is required for one visual probe:
- enable it only for the active probe;
- remove it immediately afterward;
- report that it was used.

---

# 18. What NOT to implement yet

Do **not** use this task as an excuse to redesign the addon.

Specifically, do not yet:

- implement polished Full/Compact/Minimal production modes;
- rename Enemy;
- introduce a new “Group” concept;
- redesign the Run header;
- redesign cards;
- redesign keybind badges;
- change Run opacity behavior;
- split Run/Edit geometry;
- add onboarding;
- change Settings;
- change dropdowns;
- change page terminology;
- add localization;
- add RTL support;
- rewrite Runtime around a speculative secure-scroll architecture;
- permanently add mode settings to production SavedVariables.

If a capability test proves a promising architecture, report it. Do not adopt it in production until the UI design specification is written.

---

# 19. Code quality expectations

This project is intentionally defensive because the owner cannot repair Lua code manually.

Please:

- comment **why** a secure test exists, not merely what it calls;
- isolate snippets as named constants rather than building unreadable string concatenations everywhere;
- keep restricted snippets small;
- avoid duplicated “current page binding” logic if a shared snippet fragment can safely be reused;
- name lab frames uniquely with an `InomrahsMISelfTest...` prefix;
- never collide with production frame names;
- make teardown/reset explicit;
- make every risky branch observable in the report;
- prefer a longer boring implementation over a clever implementation that is difficult to diagnose.

If you create a `RunLab.lua`, keep it focused on the lab rather than moving unrelated self-test code into it.

If sharing the report helpers requires exposing a tiny self-test internal API, do that deliberately rather than duplicating report formatting and creating two incompatible result systems.

---

# 20. Acceptance criteria for the implementation itself

Before handing the lab back, verify out of combat that:

1. self-test addon loads with no Lua errors;
2. `/imitest` still works;
3. `/imitest copy` still works;
4. `/imitest combat` still works;
5. existing keyboard release command still works;
6. the manifest version check correctly recognizes v0.41;
7. no production profile/settings are mutated;
8. `/imitest runlab setup` can be run repeatedly;
9. lab reset leaves no temporary bindings;
10. lab report can be copied;
11. lab frame names do not collide with production;
12. hiding/showing/resetting lab does not alter the real addon window;
13. the rescue control remains reachable through every destructive visibility experiment;
14. no self-test-created frame retains keyboard focus after lab close;
15. reload with the lab previously used starts cleanly.

Then give the user exact live-test instructions.

---

# 21. What I want back from you after coding

Your response after implementing should contain five sections.

## 1. Files changed

List every changed/created file.

Example:

```text
InomrahsMISelfTest/
  SelfTest.lua
  RunLab.lua
  Manifest.lua
  InomrahsMISelfTest.toc
```

and any production file only if absolutely necessary.

## 2. What the lab tests

Briefly map the implementation to the capability matrix above.

## 3. Exact user procedure

Write a numbered procedure that a non-programmer can follow.

Assume the user can:
- copy addon folders;
- `/reload`;
- type slash commands;
- enter combat with a harmless mob;
- click buttons;
- press keys;
- paste the resulting report.

Do not assume the user can inspect or edit Lua.

## 4. Expected report

Show what successful/inconclusive/refused lines look like so the user knows what to copy.

## 5. Safety / recovery

Give explicit instructions for:
- restoring the lab if a hidden-state probe gets stuck;
- clearing temporary test bindings;
- giving the keyboard back;
- leaving combat and resetting;
- disabling/removing the self-test addon if something behaves unexpectedly.

---

# 22. The most important engineering outcome

The purpose is **not** to make every capability say YES.

A negative result is valuable.

We need enough evidence to choose among architectures such as:

### Architecture possibility A
One protected Run hierarchy, securely resized/re-anchored and visual children switched between Full/Compact/Minimal.

### Architecture possibility B
One stable secure action hierarchy with separate prebuilt visual wrappers; Minimal hides only presentation while keeping action buttons alive.

### Architecture possibility C
A visible Minimal shell plus protected actions kept shown but clipped/parked so contextual keybinds remain active.

### Architecture possibility D
Parallel prebuilt secure presentation trees shown/hidden by a secure manager.

### Architecture possibility E
Full root can actually be hidden while bound callouts continue to work.

### Architecture possibility F
Combat mode switching cannot safely alter enough geometry, so presentation mode must be selected before combat.

### Scrolling possibility 1
Normal ScrollFrame scrolling works from restricted code even though insecure `SetVerticalScroll` is blocked.

### Scrolling possibility 2
ScrollFrame scrolling is unavailable, but secure anchor-based content movement works.

### Scrolling possibility 3
Mouse wheel cannot enter a secure route, but explicit secure scroll buttons work.

### Scrolling possibility 4
No viable combat scrolling exists; page design must guarantee access another way.

The lab should let the live client select among these possibilities.

Do not select one from theory.

---

# 23. Final principle

This project has already shipped bugs because an API was **assumed** to exist in the restricted environment.

The rule now is:

> **If a future Run design depends on a combat behavior, there must be a live-client test that observes that exact behavior on the exact kind of protected hierarchy that production will use.**

Please build the Run Capability Lab around that principle.
