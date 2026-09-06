# Run Capability Lab — Stage 1 findings

What the client actually permits during combat, measured on WoW Midnight
12.1 (build 120100) against Inomrah's Mythic Instructions v0.41.

Everything below was observed in the live client. Where a result is inferred
rather than measured, it says so. Several conclusions in the raw reports were
wrong and are corrected here; the errors are listed at the end, because a
finding you cannot audit is not much better than a guess.

---

## The result that mattered

**A `SecureActionButton` fires from a keybind in combat no matter how it is
hidden.** Measured on the execution counter, every variant:

| state during the keypress | executions |
| --- | --- |
| root alpha 0 | 2 → 3 |
| root hidden | 6 → 7 |
| page ancestor hidden | 7 → 8 |
| the action button itself hidden | 8 → 9 |
| resized to 1×1 | 12 → 13 |
| clipped out of a viewport | 0 → 1 |

A keybind-first mode with nothing at all on screen is viable. This was the
question the lab existed to answer.

---

## What a secure snippet may do in combat

Reached by a hardware click on a `SecureHandlerClickTemplate`.

| call | verdict |
| --- | --- |
| `Show` / `Hide` | allowed |
| `SetWidth` / `SetHeight` | allowed — 300×142 → 150×71, honoured exactly |
| `SetScale` | allowed — 1.0 → 0.6 |
| `SetAlpha` | allowed — 1.0 → 0.2510 |
| `EnableMouse(false)` | allowed |
| `ClearAllPoints` | allowed |
| `SetAllPoints()` | allowed — but anchors to the **screen**, not the parent |
| `SetPoint(point)` | allowed |
| `SetPoint(point, x, y)` on a protected ancestor | **refused**, re-measured cleanly |
| `SetPoint(point, x, y)` | **refused** |
| `SetPoint(point, frame, point)` | **refused** |
| `SetPoint(point, frame, point, x, y)` | **refused** |
| `SetParent` | **refused** |
| any scroll method | **absent from the handle entirely** |

Restricted `SetPoint` takes exactly one argument. Anything after the point —
offsets, a relative frame, or both — throws.

The refusal of `SetPoint` was re-measured on the corrected instrumentation,
which reports it the way it should always have been reported:

```
[NO] secure re-anchor of a protected ancestor
  before: left 916.6666 top 764.9999
  after:  left unreadable top unreadable
  note:   snippet ran 0 -> 0, entered 0 -> 1, clicks 0 -> 0
```

`entered 1, ran 0` says the click arrived and the snippet died inside itself.
`after: unreadable` says the frame was left with no anchor at all — the
`ClearAllPoints` before it had succeeded. `clicks 0` is the insecure hook not
firing because the script it hooks threw first, which is why that counter is
no longer trusted on its own.

The resize on the same ancestor, in the same run, was honoured exactly:

```
[YES] secure width and height on a protected ancestor
  before: 300.0000 x 142.0000
  requested: 150.0000 x 71.0000
  after: 150.0000 x 71.0000
```

So one protected frame, one snippet, one combat: resize yes, move no.

`SetScale` and `EnableMouse(false)` were **refused to ordinary code** in the
same session. The snippet route is not a workaround; for those two it is the
difference between impossible and routine.

`SetPoint`, `SetParent` and the scroll methods all appear in the restricted
method inventory. Being listed is not being callable — every refusal above is
a method the inventory reports as present.

## What ordinary code may do in combat

| call | verdict |
| --- | --- |
| `SetAlpha` on an unprotected frame | allowed, including repeated 0 → 1 → 0.35 → 1 |
| resizing an unprotected frame | allowed |
| `SetScale` on a protected ancestor | refused |
| `EnableMouse(false)` | refused |
| `SetVerticalScroll` on the Run view | refused |

The Run view's scroll frame contains the callout buttons, which are
`SecureActionButtonTemplate`. Protected children make the scroll frame
protected, and a protected scroll frame will not scroll mid-fight. This is
structural, not a version quirk.

## Mouse

An alpha-0 frame does **not** intercept clicks — they passed through to the
underlay beneath it (0 → 1, then 1 → 2) while the action counter stayed put.
Invisible and click-through, without needing `EnableMouse` at all.

Measured once cleanly; a second attempt recorded neither observer firing and
proves nothing either way.

---

## What this means for the addon

**Layout is fixed when combat starts.** No repositioning, no re-parenting, no
scrolling. Every anchor has to be set beforehand.

**Anything that changes mid-fight must be expressible as size, scale,
visibility or alpha.** That is a real vocabulary, not a crippled one: a page
can shrink, fade, go invisible, become click-through, or vanish entirely, and
its keybind keeps working throughout.

**A mode that needs different things in different places needs a separate
pre-anchored frame per mode**, shown and hidden rather than moved. Stage 2's
"prebuilt visual-state wrappers" is not an optimisation — it is the only
construction the client allows.

**Run overflow during a fight must be paged, never scrolled.** The page system
already built is the only workable answer.

**Full / Compact / Minimal** all survive this. Compact is `SetHeight` on
pre-anchored pages. Minimal is alpha 0, or `Hide`, with the keybind still
live. Both are reachable from a snippet on a hardware click.

---

## Corrections

Every one of these was stated as a finding and was wrong.

**"`SetPoint` from a snippet is refused."** Inferred from a park button whose
click never reached it. `SetPoint(point)` works.

**"A protected frame cannot be moved in combat."** Same cause. It can be
pinned to any of its parent's nine anchor points.

**"The button was never clicked", three times.** The insecure click counter
does not fire when the snippet errors first — a hooked `OnClick` never runs if
the script it hooks throws. Those buttons were clicked. Fixed by stamping
`entered` inside the snippet, before anything that can fail.

**"Action key while the button is parked off screen — YES."** Recorded against
a button the same entry shows at 160×34 in its usual place. An unreadable
position was being counted as "parked".

**Four probes reported "the snippet never ran"** across two whole runs. The
lab's scroll viewport was covering six of its own operation buttons; they
rendered perfectly and ate every click. Nothing about the client.

The pattern in all five: a missing measurement was reported as a result.
The instrumentation now separates *the click arrived*, *the snippet started*,
*the call succeeded* and *the state changed*, and a step that cannot read its
state stalls instead of guessing.

---

## Still unmeasured

- The action key with only the decoration hidden. Hiding the decoration itself
  is permitted; the keypress under that exact state was never cleanly
  captured. It fires with the whole button hidden, so this is very likely yes,
  but it is inference.
- Whether a keybind reaches the right page's callout after a page flip *during*
  combat. Untouched by Stage 1.
- `ClearBindings` colliding between two binding owners — deliberately deferred.
