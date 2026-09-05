# Xbox Elite Series 2 controller proof

This is a physical-device smoke test, not a fixture. It was captured on
2026-08-21 from the signed `build/JoyCoding.app` on macOS 26.3 using the Xbox
Wireless Controller that was connected over Bluetooth at test time.

## Device identity

Both macOS Bluetooth inventory and a direct `IOHIDManager` probe reported one
physical gamepad:

```text
Xbox Wireless Controller (reported name)
transport=Bluetooth Low Energy
vendor=0x045E product=0x0B22
virtual=no
```

PID `0B22` and the controller's 15-button BLE report descriptor identify this
device as an Xbox Elite Series 2. JoyCoding now shows that product-specific name
instead of trusting the generic Bluetooth name.

The app then reported the same device ID, with the built-in Xbox profile seeded:

```json
{"deviceID":"045E:0B22","event":"device","mappedButtons":12,"mappedDirections":12,"name":"Xbox Elite Series 2","productID":2850,"vendorID":1118}
```

## Elite Series 2 Bluetooth button order

The original fork treated `0B22` like a standard Xbox Series controller. A live
dry-run capture of the physical sequence `A, B, X, Y, LB, RB, View, Menu,
Profile` disproved that assumption. The Button-page down events were:

```text
physical A       -> raw usage 1
physical B       -> raw usage 2
physical X       -> raw usage 4
physical Y       -> raw usage 5
physical LB      -> raw usage 7
physical RB      -> raw usage 8
physical View    -> raw usage 11
physical Menu    -> raw usage 12
physical Profile -> no HID event (hardware profile switch)
```

The gaps are real fields in the Elite BLE descriptor, not missing button
presses. The initial proof write-up incorrectly shifted the three centre
controls one position to the right; the raw log and the physical retest show
that View and Menu are Button-page usages 11 and 12, while Profile is handled
entirely by the controller. The fix normalizes those raw usages at the input
boundary:

```text
raw 1 -> A (1)       raw 2 -> B (2)
raw 4 -> X (3)       raw 5 -> Y (4)
raw 7 -> LB (5)      raw 8 -> RB (6)
raw 11 -> View (7)   raw 12 -> Menu (8)
raw 13 -> Xbox (11)  raw 14 -> L3 (9)  raw 15 -> R3 (10)
```

This keeps every stored action on JoyCoding's conventional Xbox IDs. It also
prevents unused raw usages 3, 6, 9, and 10 from masquerading as real controls.
The automated suite asserts the full table, the Elite-specific artwork, and the
unchanged behavior of non-Elite controllers.

## Physical input to JoyCoding action

The trace was recorded with `JOYCODING_PROOF_DRY_RUN=1`. That flag suppresses
only the final `CGEvent` output so the smoke test cannot operate another app.
Device discovery, HID normalization, profile lookup, gesture handling, and
semantic action resolution all run through the production code path.

The following are consecutive stages from the captured JSONL trace (timestamps
omitted here for readability).

### A button

```json
{"usagePage":9,"usage":1,"value":1,"event":"rawInput"}
{"button":1,"down":true,"deviceID":"045E:0B22","event":"button"}
{"button":1,"action":"confirm","deviceID":"045E:0B22","event":"binding"}
{"action":"confirm","event":"action"}
```

### LT and RT analog triggers

LT is HID Simulation usage `0xC5` (197); RT is `0xC4` (196). They become virtual
buttons 20 and 21 with hysteresis. The 10% press threshold also works when an
Elite trigger stop limits travel.

```json
{"usagePage":2,"usage":197,"value":340,"logicalMax":1023,"event":"rawInput"}
{"button":20,"down":true,"deviceID":"045E:0B22","event":"button"}
{"button":20,"action":"ptt","deviceID":"045E:0B22","event":"binding"}
{"action":"pttStart","event":"action"}
{"usagePage":2,"usage":197,"value":40,"logicalMax":1023,"event":"rawInput"}
{"button":20,"down":false,"deviceID":"045E:0B22","event":"button"}
{"action":"pttStop","event":"action"}

{"usagePage":2,"usage":196,"value":284,"logicalMax":1023,"event":"rawInput"}
{"button":21,"down":true,"deviceID":"045E:0B22","event":"button"}
{"button":21,"action":"switchApp","deviceID":"045E:0B22","event":"binding"}
{"usagePage":2,"usage":196,"value":0,"logicalMax":1023,"event":"rawInput"}
{"button":21,"down":false,"deviceID":"045E:0B22","event":"button"}
{"action":"switchApp","event":"action"}
```

### Bluetooth D-pad

The controller declares a one-based hat range (`1...8`) and reports `0` when
centred. JoyCoding now normalizes it to its existing zero-based clockwise form.

```json
{"usagePage":1,"usage":57,"value":1,"logicalMin":1,"logicalMax":8,"event":"rawInput"}
{"direction":0,"channel":"hat","deviceID":"045E:0B22","event":"hat"}
{"action":"scrollUp","event":"action"}

{"usagePage":1,"usage":57,"value":5,"logicalMin":1,"logicalMax":8,"event":"rawInput"}
{"direction":4,"channel":"hat","deviceID":"045E:0B22","event":"hat"}
{"action":"scrollDown","event":"action"}

{"usagePage":1,"usage":57,"value":7,"logicalMin":1,"logicalMax":8,"event":"rawInput"}
{"direction":6,"channel":"hat","deviceID":"045E:0B22","event":"hat"}
{"action":"sessionPrev","event":"action"}
```

### Analog sticks

The same physical trace includes four unsigned `0...65535` Generic Desktop
axes: usages `0x30/0x31` for the left stick and `0x32/0x35` for the right stick.
JoyCoding normalizes each axis to `-1...1`, applies separate engage/release
thresholds, and reduces it to the same clockwise cardinal values used by the
D-pad. The channels stay separate so Test Mode can highlight and configure
`D-pad`, `Left stick directions`, and `Right stick directions` independently.

Existing Xbox profiles are migrated once: an empty D-pad channel is restored,
left-stick directions inherit the navigation defaults, and the right stick
gets arrow-key defaults. Non-empty custom direction maps are preserved. The
direction-learning UI now commits only after all four directions are captured,
so cancelling the wizard cannot erase an existing map again.

## Raycast Dictation: hold LT to speak

This fork follows the exact Dictation binding stored by Raycast on the test Mac:

```text
Raycast command: c:r:dictation::-::dictateText
Raycast shortcut: Right Shift + Return (virtual key code 36)
JoyCoding mode: hold
```

This was read without opening or editing Raycast from its local snapshot at
`~/Library/Application Support/com.raycast.macos/cloud-sync/settings-snapshots/`.
The encrypted/custom `.db` files were not modified. JoyCoding therefore emits
the sided modifier as a real key-code 60
`flagsChanged` event, followed by Return key-code 36. The right-side flag is
preserved in addition to the ordinary Shift flag; emitting only generic Shift
does not match this Raycast shortcut.

The event-plan test asserts this exact sequence in both directions:

```text
LT down:  flagsChanged(keyCode=60, RightShift) -> keyDown(keyCode=36, RightShift)
LT up:    keyUp(keyCode=36, RightShift) -> flagsChanged(keyCode=60, none)
```

The physical trace above proves that Xbox LT (`usage 197`) resolves to
`pttStart` and `pttStop`. The screenshot pair below separately exercises those
same two `Actions` entry points through JoyCoding's authenticated localhost
remote. Splitting the proof this way makes the Raycast boundary repeatable
without claiming that the screenshot itself was triggered by a controller
press.

## Raycast shortcut layer

The same read-only snapshot contained the global hotkeys used by the Xbox
profile. An opt-in integration test loaded the actual file on this Mac—not a
fixture—and asserted all nine bindings:

```text
Open Raycast       ⌘ Space       Arc        ⌥ A
Raycast AI Chat    ⌥ Space       Slack      ⌥ S
Dictation          Right⇧ Return Codex      ⌥ C
Heptabase          ⌥ E           Amp        ⌥ X
Warp               ⌥ W
```

The production action path retains Raycast's macOS virtual key code and emits a
complete physical modifier-down, key-down, key-up, modifier-up chord. Therefore
the controller invokes the same global shortcut Raycast already owns; it does
not launch apps through a separate implementation or rewrite Raycast's
preferences.

Run the machine-specific assertion with:

```bash
JOYCODING_VERIFY_LOCAL_RAYCAST=1 swift test \
  --filter HIDNormalizationTests/testCurrentMacRaycastBindingsWhenExplicitlyRequested
```

On the test Mac this executed 1 test with 0 failures. The ordinary portable
suite separately checks the JSON parser and exact synthesized chord plan using
a fixture.

The installed signed app was also exercised through its authenticated local
action endpoint. The front app started as Slack. JoyCoding ran
`raycastAmp`, Raycast handled its existing `⌥X` global hotkey, and macOS then
reported Amp as frontmost. The same path ran `raycastSlack` (`⌥S`) to restore
the original app:

```text
JoyCoding: ok: raycastAmp
macOS front app: com.hamishbultitude.ampcode (Amp)
JoyCoding: ok: raycastSlack
macOS front app: com.tinyspeck.slackmacgap (Slack)
```

This canary proves the emitted shortcuts were accepted by Raycast and resolved
to their assigned applications. It did not edit Raycast settings.

### While PTT is held

The unedited raw capture shows two independent system/UI signals: Raycast's
orange microphone indicator in the menu bar and its live Dictation Pill near
the bottom of the screen.

![Raycast Dictation active while LT is held](images/proof/raycast-dictation-held-annotated.jpg)

- [Raw held PNG](images/proof/raycast-dictation-held-raw.png) — SHA-256
  `8d73db2a3f06643ab34943cbf0dedce84768cf79f001b181ff83e0167cdf8bed`
- Annotated held JPEG — SHA-256
  `b424be27b09d109c6ca5c396841c4b50f64b431b8815c9a95eb39e96b6525b00`

### After PTT is released

Four seconds after `pttStop`, both the orange microphone indicator and the
Dictation Pill are absent.

![Raycast Dictation stopped after LT is released](images/proof/raycast-dictation-released-annotated.jpg)

- [Raw released PNG](images/proof/raycast-dictation-released-raw.png) — SHA-256
  `39fbf54700f119e6a8b472b30133f02e0780039e59a8a9687cd7ad261a553458`
- Annotated released JPEG — SHA-256
  `1a113679f8718da790c331a42f15e56018c27d7e363b5953b2a2148b54109ea9`

Both raw and annotated captures are `3600 x 2338`. The annotations are
deterministic SVG/Sharp overlays described by the adjacent JSON specs; the raw
pixels and hashes remain untouched.

## Actual macOS event delivery

The physical traces above used dry-run mode to prevent accidental input in an
uncontrolled frontmost app. The final `CGEvent` boundary was tested separately
after macOS Accessibility permission was granted, using the focused receiver in
`tools/keyreceiver` and JoyCoding's authenticated localhost remote. The remote
calls the same `Actions.run("confirm")` function that the physical A binding
resolved above.

Preflight proved the receiver was the target before sending anything:

```json
{"app":"dev.joycoding.proofreceiver","inTarget":true}
```

JoyCoding then returned:

```text
ok: confirm (front=dev.joycoding.proofreceiver)
```

The focused AppKit receiver recorded the actual synthesized Return key:

```json
{"characters":"\r","event":"keyDown","keyCode":36,"time":"2026-08-21T09:46:52Z"}
```

Together, these traces cover the whole chain: physical Xbox A (`usage 1`) →
virtual button 1 → `confirm` binding → production `Actions.run` → `KeySynth` →
macOS receiver key-down (`keyCode 36`).

## Mapping Test Mode

The installed app's Test Mode was enabled from the Mapping toolbar, then a
mapped controller button was pressed. JoyCoding kept the input and binding
resolution visible while stopping before action dispatch:

```text
test mode:     on
last dispatch: Test button 8: Tap: Open Raycast · Hold: Raycast AI Chat
front app:     com.meiease.joycoding (JoyCoding)
```

Without Test Mode, button 8's tap opens Raycast. Here JoyCoding remained
frontmost, proving that Raycast was not invoked. The
safety gate also cancels pending tap/hold/repeat timers, releases an already-held
PTT chord before enabling, and suppresses the release of any press that began in
Test Mode. Leaving Mapping or closing its Settings window turns the mode off.

The 2026-08-21 physical retest recorded the complete requested direction set in
Test Mode:

```json
{
  "directionsByChannel": {
    "hat":   [0, 2, 4, 6],
    "left":  [0, 2, 4, 6],
    "right": [0, 2, 4, 6]
  },
  "suppressed": 36,
  "actionsDispatched": 0
}
```

The same trace records physical View as canonical button 7 and physical Menu as
canonical button 8. The Profile press between Menu and D-pad produced no button
event, matching its onboard-profile behavior. Every recognized direction has a
paired `suppressed` record naming the resolved action, while the trace contains
zero `action` records. This is the safe-input proof: the HID path, normalization,
profile lookup, and action resolution all ran, but dispatch did not.

Closing the installed Settings window was also checked through the authenticated
local state endpoint: `testMode` changed from `true` to `false` and
`lastDispatch` became `Test Mode off`.

## Controller illustration

### Elite Series 2 redraw — 2026-09-05

Elite Series 2 now uses its own complete SVG, referenced from Microsoft's
[official front-view product photo](https://assets.xboxservices.com/assets/de/5c/de5c31bd-b962-4f9f-af98-32a6331ac91b.jpg?n=999666_Buy-Box-Image-0_2_829x799.jpg).
It includes the black faceplate, wraparound textured grips, metal shoulder and
thumbstick rims, nine-face circular D-pad, monochrome ABXY caps, and the Profile
button above three indicator bars. Standard Xbox Series artwork is separate.

The artwork uses an `829 × 610` viewBox starting at `y = 110`. Elite-specific
anchors follow its control centers; canonical input IDs and bindings are
unchanged. Resting Elite controls are entirely in the SVG; SwiftUI adds only
transient highlights and direction cues.

The matching screenshots below use the native Mapping screen in a dark-mode,
isolated `JOYCODING_UI_PREVIEW=xboxElite2` session. They are **UI previews**,
not evidence of a physical controller connection or input event.

Before:

![Elite Series 2 before the redraw](images/proof/elite-series-2-before.jpg)

After:

![Elite Series 2 after the redraw](images/proof/elite-series-2-after.jpg)

Validation: `swift test` completed with 45 passed, one environment-specific
test skipped, and no failures. The universal arm64/x86_64 build and bundled
checks passed via `./build.sh --no-notarize`. The signed app was synced to
`/Applications/JoyCoding.app`; the installed SVG matches the source byte for
byte. Native macOS rendering and the Mapping screen were visually inspected.

### Button-highlight alignment

Front-button highlights now reference the same SVG surfaces as the visible
controls, including the full curved LT/RT and LB/RB surfaces. Face buttons,
thumbstick caps, D-pad, View, Menu, Xbox, and Profile share their geometry with
the corresponding highlight masks. Hovering direction rows previews the
correct stick or D-pad direction; reserved controls can be highlighted without
making them assignable.

The native mask regression tests cover every front input, verify that each
mask contains its actual control center, and check that unrelated shell and
background points remain transparent. `swift test` passed 47 tests with one
opt-in local test skipped. The universal build and bundled checks passed, and
the installed app was reopened with `JOYCODING_UI_PREVIEW=xboxElite2`.

### Previous shared Xbox Series illustration

The previous artwork rendered the controller from Xelu's full Xbox Series SVG
diagram (CC0), rather than approximating the controller with a handful of
SwiftUI curves. JoyCoding adds its own dark shell backing, exact live-input
anchors, colored ABXY caps, and Elite Series 2-specific faceted D-pad and
Profile control over the source geometry. The SVG remains resolution-
independent; live highlights remain app code.

The screenshot below is the signed `/Applications/JoyCoding.app` with the
physical `045E:0B22` device connected and Test Mode enabled. It is not a design
mockup. The deterministic `JOYCODING_UI_PREVIEW=xboxElite2` launch hook is
available for visual regression checks when the controller is asleep, and
labels itself `UI preview` instead of `Connected`.

![JoyCoding controller rendered from the CC0 SVG](images/proof/controller-art-xelu-svg.jpg)

Screenshot SHA-256:
`e0a605bf7f9c5473865c8273f239538b5e58d6ed134d2ad03e7093d328b186a4`

## Reproduce

```bash
swift test
JOYCODING_VERIFY_LOCAL_RAYCAST=1 swift test \
  --filter HIDNormalizationTests/testCurrentMacRaycastBindingsWhenExplicitlyRequested
./build.sh --no-notarize

swiftc -O tools/hidprobe/main.swift -framework IOKit -o .build/hidprobe
.build/hidprobe 15

tools/keyreceiver/build.sh

JOYCODING_CONFIG_DIR="$PWD/.build/proof-config" \
JOYCODING_PROOF_LOG="$PWD/.build/xbox-proof.jsonl" \
JOYCODING_PROOF_DRY_RUN=1 \
build/JoyCoding.app/Contents/MacOS/JoyCoding --settings
```

Press `A, B, X, Y, LB, RB, View, Menu, Profile`, then LT, RT, each D-pad
direction, and both analog sticks while the final command is running. Profile
should produce no HID event. Inspect `.build/xbox-proof.jsonl`
for the same `rawInput -> canonical button/hat -> binding -> action` chain shown
above.

To repeat only the Raycast boundary with the installed app:

```bash
token=$(jq -r '.httpToken' ~/.config/joycoding/config.json)
curl -fsS "http://127.0.0.1:27123/$token/pttStart"
# Raycast microphone indicator and Dictation Pill should now be visible.
curl -fsS "http://127.0.0.1:27123/$token/pttStop"
```
