# Backplan — Backlog

Roadmap for features beyond the MVP. Backplan is a single-file static app
(`index.html`, vanilla JS, localStorage) — keep that constraint in mind; prefer
no-backend / client-only solutions where possible.

## Done
- [x] Backwards time math (target → per-step start times → overall start)
- [x] Timeline strip with "now" marker + countdown
- [x] Templates saved to localStorage
- [x] Previous-day overflow detection
- [x] **Reorder steps** — drag handle (Pointer Events, mouse + touch) and keyboard
  (focus handle, ↑/↓). Smooth make-space animation; commits to `state.steps` on drop.
- [x] **Quick Add tasks** — one-tap chips that append a fully-formed step (name +
  duration, no typing). Web + iOS. Inspired by ReadyBy; our differentiator is free +
  frictionless. Presets live in a shared list (`QUICK_ADDS` / `Starters.quickAdds`).
- [x] **Starter plans (prebuilt templates)** — one-tap full routines (School
  drop-off, Out the door, Catch a flight, Dinner reservation, Bedtime). Replace the
  current step list; keep target/event. Shown above saved templates. Web + iOS.
- [x] **Travel steps / map support** (was item #2 below) — a step can carry a
  drive/bike/walk leg with a From and To, and Backplan fills in the real routed
  duration. Web + iOS, no backend and no API keys.
  - **Routing: `brouter.de`**, key-free and `Access-Control-Allow-Origin: *`.
    Profiles `car-eco` / `trekking` / `hiking-beta`. Rejected `router.project-osrm.org`:
    its demo host ignores the profile entirely and only runs the car graph
    (`driving`, `cycling`, `foot` and even a bogus `bike` all return identical
    results), so `trip-shift/frontend/src/lib/geo.js`'s walk/bike numbers are
    actually car routes. openrouteservice needs a key.
  - **Search: Photon**, two passes merged (proximity-biased + bbox), ranked by
    textual match then distance from the anchor. Each bias alone fails the other's
    cases — measured: proximity-only sends "salt and straw" to Anaheim, bbox sends
    "Forest Grove Oregon" to "South Forest Grove Loop". Nominatim is the fallback.
  - **Saved places + chaining** — a leg with no explicit origin inherits the
    previous leg's destination, else the place marked home.
  - Times are **free-flow** (BRouter has no traffic model); the UI says so and
    padding stays the user's call via the Buffer chip.
- [x] **UI polish pass** — one line system and real containers, web + iOS.
  - **Lines.** Four competing border treatments collapsed to two tokens:
    `--line-strong` (2px ink) bounds a surface, `--line-hair` (1.5px `--rule`)
    divides inside one. The old `--border: #e6e6e6` was invisible on white, which
    is why the From/To fields read as unbounded; it's gone. iOS mirrors this with
    `Color.bpRule` — `bpBorder` survives only as a fill.
  - **Containers.** The result strip, timeline, and countdown were three floating
    blocks describing one fact; they're now one hero card (event name on its own
    line, so the two times share a baseline). Steps / Places / Templates each get
    a real panel instead of bare chips on the page background, and step rows are
    hairline-divided rows inside the Steps panel rather than N mini-cards. On iOS
    step rows became bordered cards (kept as `List` rows — a single `VStack` card
    would break `.onMove` / `.onDelete`).
- [x] **Overview mode** — the Steps section toggles between Edit and Overview
  (web + iOS, persisted: `backplan:view` / `@AppStorage("backplan.view")`).
  - **Why.** The old bar printed step names inside its segments, so it doubled as a
    schedule you could read. Making it a real progress bar took that away, and no
    amount of colour brings it back: at 390px with 7 steps a 15-minute segment has
    no room for a label, which is what put `Dr…` and `S.` on screen. The bar is a
    status indicator; the schedule needed its own surface.
  - **Rows**: start time · name · duration, with travel legs as the same one-line
    summary the collapsed editor row uses (`🚗 from → to · 0.9 mi · 4 min`). State
    mirrors the bar — past steps dim to 45%, the current one gets a lime row and a
    `NOW` badge. The list closes on the target itself in purple, so it ends where
    the plan does.
  - **Editing is fully hidden** in Overview — no text fields, steppers, drag handles,
    or delete buttons. That is the whole point: readable at arm's length.
  - Web gotcha: `.steps` / `.add-row` / `.quick-add` set an author `display`, which
    beats the `hidden` attribute's UA `display:none` — they need it stated
    explicitly. Init must run `applyViewMode()` before the `compute()` that renders
    the overview, or it renders empty.

- [x] **Timeline is a progress bar now** — web + iOS. The strip tinted segments from
  a four-colour cycle (`i % 4`) and drew step names inside them. Past four steps the
  colours repeated and meant nothing, and a 15-minute step inside a 2h35m plan had no
  room for its name — `.narrow` dropped it, `.tiny` dropped the duration too, so most
  segments were anonymous blocks ("Drive to airport" → `Dr…` at 390px).
  - **Colour encodes state**: one lime fill for the elapsed span at 28% opacity,
    `--lime-tint` on the current segment's full span, paper for what's left. The fill
    cuts across the active segment, so progress *through* the current step is free.
    Overrun turns the fill coral to match its status pill — a full lime bar would read
    as "all good" when it actually means the target is blown.
  - **Segments are tick boundaries only.** No text inside the bar at any width, so
    nothing truncates; `.narrow` / `.tiny` are gone. Ticks are ink at 24% alpha, not
    `--rule`, which washes out to nothing under the fill.
  - **The now-flag left the track.** Clipped to the capsule it collided with the corner
    radius and punched a white notch through the last segment; it now rides an unclipped
    rail above, clamped so the pill never hangs off the card.
  - **Upcoming segments alternate two tones of one hue** (`rgba(74,21,75,.16)` on
    even children / `Color.bpPurple.opacity(0.16)` on iOS — shipped at .07 first,
    which read on a desktop monitor and vanished on a phone). State-colour alone left
    the bar an empty white capsule before the plan started — which is the state you
    open a planning app in — so the shape preview the old rainbow gave for free had
    to come back, without meaning attaching to any particular colour. The flag rail
    collapses to 4px outside the plan window rather than holding open empty white.
  - **Naming moved below** into a NOW/NEXT block. iOS renders the timeline only while
    the target is still ahead (`PlanView` swaps in a "time has already passed" banner),
    so the coral overrun state is reachable on web only.
  - **Web splits render from tick.** `compute()` is on a 30s interval and rebuilt the
    strip via `innerHTML`; `tickTimeline()` now moves the fill/marker/text on a 1s
    interval without building DOM, which is what makes the fill glide. Text writes are
    change-guarded because `.hero` is an `aria-live` region.
  - **`PlanStatus`** (`Services/BackwardsPlanner.swift`) is the one place that turns a
    result + "now" into words; `ArmBar` and `PlanTimeline` were computing near-identical
    strings separately.

- [x] **Collapsible travel legs** — once both endpoints resolve, a leg folds to a
  one-line summary (`🚗 from → to · 0.9 mi · 4 min`) with a chevron to reopen. An
  error or a missing endpoint always renders expanded, since the fields are what
  needs fixing. Open/closed state is in-memory only (`travelOpen` / `userExpanded`),
  so reopening the app on a settled leg shows the tidy version.

## Backlog

### 1. Timer integration
Turn the passive countdown into active alerts.
- "Start" button that arms the plan against the real clock.
- Per-step browser notifications ("Time to: Drive there") via the Notifications API.
- Live ticking countdown to the next step boundary, not just a 30s refresh.
- Optional sound/vibration on step transitions.
- Consider: does this need to survive a closed tab? If so, Service Worker +
  `showTrigger` / scheduled notifications (limited browser support) — or keep it
  tab-open only for v1.

### 2. Travel steps — what's still missing
The core is shipped (see Done). Still open:
- **Transit.** No key-free service provides it. Would mean TriMet/OpenTripPlanner,
  which is its own project.
- **Traffic-aware driving times.** BRouter is free-flow only. Real traffic means a
  keyed provider (Google/Mapbox) plus a proxy to hide the key.
- **Route maps.** Duration + distance only today; no map library is loaded.
- **Departure-time awareness.** Backplan knows each step's clock time, so it could
  in principle ask for a time-of-day-specific estimate — but only against a
  provider that models traffic, so this is gated on the item above.

### 3. Sharing
Share a plan with someone else.
- Encode full plan state (event, target, day, steps) into the URL hash / query so
  it's shareable with **no backend** — recipient opens the link and sees the plan.
- "Copy link" button; optionally a "Save as my template" on the receiving end.
- Watch URL length for big plans; compress (e.g. base64 of compact JSON) if needed.

### 4. Saving (cross-device)
Today saving is localStorage only — per-device, no sync.
- Cloud-backed save so templates follow the user across devices.
- Implies accounts/auth and a backend, which is a bigger step than the others —
  scope carefully. A lightweight option: export/import plans as a file or via the
  share-link mechanism (#3) before committing to full accounts.

### 5. Next-day impact (day-pair planning)
Today a plan is an island. But the question that actually matters at 8pm isn't
"when do I start bath" — it's *"if lights-out slips to 9:15, what does tomorrow
morning cost?"* Backwards planning hides that by construction: the target is the
end of the story.
- **Model: two plans, one elastic edge.** The evening plan ends at lights-out;
  the morning plan starts at wake; between them sits a **sleep need** (a minimum,
  not a duration). The morning target is usually fixed and non-negotiable (school
  bell, first meeting), which makes the system solvable in one direction:
  fixed morning target → required wake → minus sleep need → **the real bedtime
  deadline** — which is routinely earlier than the one you set.
- **The headline output** is a second time on the hero card: "lights out by 8:40,
  or tomorrow starts short." And while the evening plan runs late, live: "20 min
  over → wake moves to 6:25 → 15 min short."
- **One sleeper first.** Sleep need is per-person (a 3-year-old's 11h vs an
  adult's 7.5h), and the binding constraint is whichever chain is tightest.
  Ship the kid's chain alone; a second sleeper is a second lane and drags in the
  "who is even in this plan" question that #6 owns.
- **Already seeded.** `overflowsPrevDay` + the "← previous day" tag are the
  degenerate case — a plan whose start lands yesterday. Generalize from "does
  this cross midnight" to "what does this cost the adjacent day."
- Client-only: two plan objects in one localStorage record plus a link field.
- **Guard the scope.** The wedge is *the pair* (tonight → tomorrow morning), one
  edge. A general chain of linked days is a calendar app, and that isn't this.
- Deferred: week-over-week sleep-debt tracking. It needs actual-vs-planned
  logging every night, which is a habit app. The value here is the single
  decision at 8pm, not the trend.

### 6. Two-person plans (assignment + agreement)
The 5pm failure mode isn't arithmetic — it's that both parents assumed the other
one had pickup. Two cheap pieces of this belong in Backplan. The full
coordination product does not.

**In scope, client-only:**
- **Assignee per step.** A step carries an owner. The timeline then draws one
  lane per person, which is the entire point: two steps stacked in one lane at
  the same clock time is a conflict you can *see*, and "every step is in one
  lane" is the argument you were actually having. Unassigned stays a valid,
  visible default — never auto-assign.
- **Share-link round trip** (builds on #3). Send the encoded plan, they edit,
  they send it back. Asynchronous agreement with no backend and no accounts —
  the same shape as texting about it, except the thing being sent has times in
  it. Frame the copy as a *proposal*, not a decision.

**Out of scope — this is the separate app.** Shared live state, two accounts,
push when the other person moves something, recurring weekly patterns ("Tue/Thu
are mine"), multiple kids with per-kid assignment. That's the market gap already
written up in `../family_scheduling/family_scheduling_apps_research.md` — no
existing app combines drag-and-drop + carpool + per-kid parent assignment. It
needs a backend and auth, which breaks the no-signup identity that makes
Backplan free and frictionless.

**The split:** Backplan is the single-plan engine; the coordination app is the
multi-person layer that *consumes* plans. If both get built, the coordination
app imports and exports Backplan share-links instead of reimplementing the math.

**Design note for whichever app ships it:** the hard problem here is social, not
technical. Make disagreement cheap — propose/counter rather than assign; show
slack (whose chain is loosest) rather than a fairness score; and never notify in
a way that reads as nagging.
