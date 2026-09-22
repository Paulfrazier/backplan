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

- [x] **Timer integration — live tracking** (was Backlog #1) — a plan can now be
  armed against the real clock: a countdown to the moment you have to start, a
  phase, browser/local notifications at every step, and an iOS Live Activity on
  the Lock Screen and Dynamic Island. Web + iOS.
  - **"Start countdown", not "Arm".** The internal vocabulary stays *armed*
    (`TimerController`, `KEY_ARMED`), but the button says what it does. iOS's
    old "Arm plan" / "Disarm" moved to match the web rather than the reverse —
    "arm" is a word this app's users never say out loud.
  - **The snapshot is the feature.** Arming freezes the resolved chain
    (segments, absolute start/end times, the target) to `backplan:armed` /
    `backplan.armed`. Re-deriving it on every tick was the obvious alternative
    and it is wrong: an edit — or a midnight rollover — would silently slide the
    countdown under someone who is currently *relying* on it. Frozen, any
    divergence gets **reported** instead. The stale banner ("Plan changed since
    you started the countdown" + Re-arm) is that report, and it is compared
    against the armed *half* of the night pair, not the half being edited —
    switching tabs is not a change to the armed plan.
  - **Two clocks, deliberately.** `PlanStatus` says what is *happening*
    ("Get dressed · 4 min left"). The new `PlanCountdown` / `tickArm()` says what
    to *count to*: the chain start before the plan begins, the end of the running
    step while it does, the target once the last step is running. A clock aimed
    at anything else runs past zero and stops meaning anything. Phase words are
    Not started / Start now / Step N of M / Running over — "Start now" is the
    last minute before the chain start, because at T-30s "not started" is the
    wrong thing to tell someone.
  - **Web got the `PlanStatus` consolidation too.** iOS already had one place
    that turns a result + "now" into words; web had that logic inlined in
    `tickTimeline`. It is now `planStatus(segments, chainEnd, now, precise)`,
    shared by the timeline strip and the arm strip, with `precise` swapping
    minutes for an H:MM:SS clock. `compute()` also lost its copy of the backwards
    walk to `planSegments(plan)` — arming and the stale check need that walk for
    a plan that isn't the one on screen.
  - **The arm strip lives outside `.hero` on purpose.** The hero is an
    `aria-live` region; a clock that reprints every second inside one never stops
    announcing itself. Only the phase word is live, and it changes at boundaries.
    Same reason the clock uses `font-variant-numeric: tabular-nums` /
    `.monospacedDigit()` — proportional figures make it jitter sideways once a
    second, and it is the only thing on the page repainting that fast.
  - **Guards, both platforms:** never arm a target that has already passed, never
    arm a plan with no *timed* steps. A plan of zero-duration steps produces no
    segments and would arm a countdown with nothing in it. The button disables
    itself and says which one it is.
  - **Notifications degrade rather than block.** Permission is requested on the
    click that arms (browsers drop a request with no gesture behind it), and the
    note under the button states the outcome — granted / blocked / unsupported —
    with the countdown running either way. Boundaries already in the past are
    marked fired *silently* on arm and on restore: reopening the tab after lunch
    should not dump six alerts about steps that finished an hour ago.
  - **Live Activity (iOS).** New `BackplanWidgets` app-extension target; the
    `ActivityAttributes` lives in `ios/Shared` and compiles into both processes so
    the payload's shape can't drift. Lock Screen card + Dynamic Island compact /
    minimal / expanded.
    - Every countdown is `Text(timerInterval:)`, never a formatted string. **The
      system owns the seconds**, so the app pushes a new state only when the
      *words* change — at a step boundary. A one-second push loop would be
      rate-limited into uselessness; a seven-step plan needs eight updates, and
      `TimerController` gets them by sleeping until the next boundary rather than
      polling.
    - **`Activity` is not `Sendable`.** Holding one in a `@MainActor` property and
      then `await`ing a method on it is a hard Swift 6 error ("sending 'activity'
      risks causing data races"). `LiveActivityService` is therefore a stateless
      enum that looks the live activity up from `Activity.activities` inside each
      call — which also means it survives a relaunch, where a stored handle would
      have been lost while the card kept running.
    - **The Dynamic Island's ground is black and cannot be tinted**, unlike the
      Lock Screen card (`activityBackgroundTint(.bpPaper)` keeps that one on
      paper). The first build used the paper palette's inks there — `bpPurple`
      #4A154B, `bpLimeInk` #3F6212 — and the island opened to its wider Live
      Activity shape with nothing legible inside it. `islandAccent` is the same
      three hues lifted for a dark ground; the Lock Screen keeps `accent`.
    - `NSSupportsLiveActivities: true` is required in the *app's* Info.plist.
      Without it `Activity.request` throws and nothing appears — no error in the
      UI, no card, no log worth reading.
    - Once the target is behind us there is nothing left to say, so the card is
      ended with `.after(target + 1h)` rather than left open: an overrun nobody
      disarms would otherwise sit on the Lock Screen until the system's own
      8-hour cap. Disarm still ends it `.immediate` — a disarm that leaves the
      card up reads as the button not having worked.
    - **Known limit:** local `Activity.update` only lands while the app is alive.
      A suspended app cannot advance the step name, so every state carries a
      `staleDate` set to the next boundary and the system dims the card rather
      than showing a confidently wrong step. Foregrounding re-syncs
      (`scenePhase`). Doing better needs push tokens and a server.
  - **iOS armed state now persists** (`backplan.armed`, `PlanResult` became
    `Codable`) to match the web's reload behaviour. Both sides discard a snapshot
    whose target is more than 6 hours behind — otherwise the app reopens onto a
    dead countdown insisting you are nine hours late for yesterday.

- [x] **Track to sleep** — the night edge (#5) read forwards from *now*. Web + iOS.
  - **The question.** You're out somewhere at 10pm. The pair answers "given the
    bedtime I set, does tomorrow survive?" — but standing in someone else's
    kitchen you never set a bedtime, and the thing you actually want is *"if I
    walk out the door right now, how much sleep do I get?"*, ticking down while
    you decide. Chain: **leave now → travel home → the wind-down → asleep →
    wake**. Output is a live sleep figure plus its inverse, the latest departure
    that still buys the full need.
  - **One model, three lenses — not two sleep models.** This is the decision that
    mattered. Wake, sleep need and the real lights-out deadline all still come
    from the pair's record; the shared arithmetic was extracted into
    `solveNight()` / `NightSolve.solve` so the bridge and the tracker can never
    drift into two answers for "when is lights out really". The tracker adds
    exactly two things the pair has nowhere to put: **the ride home**, and a near
    end anchored to the wall clock instead of to a typed target. Turning the mode
    on turns the pair's edge on, and turning that edge off takes the mode with
    it. Rejected: a standalone `trackSleepNeed` / `trackWake`, which would have
    been quicker and would have left two half-overlapping sleep models in a
    3,700-line file.
  - **Same edge, opposite anchor.** The pair pins *both* ends (a lights-out you
    chose, a morning you can't move) and measures the gap. The tracker pins only
    the far end and lets the near one ride the clock — one minute of sleep lost
    per minute spent deciding. That is the whole difference, and it is why this
    does **not** violate #5's guard: it is a third framing of the *same single
    edge*, not a second edge, not a chain of days.
  - **This subsumes #5's live line as the headline.** The pair already computed
    `startNowLightsOut` / `latestStart` and printed them as a grey footnote
    ("Start the evening by 10:04 — 22 min from now"). That footnote *was* this
    feature in miniature; track mode promotes it to 56px and adds the leg it was
    missing. The bridge keeps the footnote for the at-home case, where there is
    no trip to count.
  - **The ride home reuses the travel machinery wholesale** — same `routeLeg` /
    `RouteService`, same cache, same "free-flow" wording, same place search. But
    it is **not** a step in the evening plan: the wind-down routine is the same
    every night and the ride home is tonight-only, so parking it in the step list
    would leave a phantom "Drive home" in the bedtime plan forever and would
    double-count against the pair's own `latestStart`. It lives on the track
    record as a plain `Travel`.
  - **Destination is home, and only the origin is a field.** "Back-plan to home"
    is the premise; making the destination editable turns this back into a trip
    planner. `to` is resolved from the home place at refresh time rather than
    stored, so moving house doesn't strand the leg. No home place → the ride
    contributes **zero minutes** and says so. An unrouted leg contributing a
    guess would be indistinguishable from a routed one in the headline figure.
  - **Wake is editable only where it is genuinely free.** With an empty morning
    plan, wake *is* the morning target, so the field writes straight through.
    With a morning routine present, wake is derived (obligation − routine) and
    the field is disabled with the derivation spelled out — a control that
    silently moved the school bell would be a lie. Entering track mode therefore
    enables the pair *without* seeding `MORNING_SEED`, unlike the Chain checkbox:
    the tracker's question is sleep, and an empty morning is what makes the wake
    time directly settable.
  - **The morning offset is the one piece of genuinely new math.** The pair
    derives which day the morning lands on from the *evening plan's*
    Today/Tomorrow toggle. Track mode has no such toggle and, worse, is the one
    mode routinely used after midnight — so it takes the **next occurrence of
    wake after now** (`solveNight(0).wake > now ? 0 : 1`). Without this, a 12:40am
    departure plans for the 6am 29 hours away and reports 28 hours of sleep.
  - **Sleep is floored, not rounded.** Claiming a minute you don't have is the
    one error the headline number is not allowed to make.
  - **Two clock resolutions on purpose.** The sleep figure is minute-grain (it
    visibly drops once a minute); the departure deadline carries a H:MM:SS hand,
    because that is the thing genuinely running out. Verdict bands match the
    bridge exactly — on track / tight (≤15 min short) / short — so one night
    can't read "tight" in one lens and "fine" in the other.
  - **The mode swaps surfaces, it doesn't stack.** Hero, plan tabs, bridge and
    the target card all step back: every one of them reads out from a bedtime you
    didn't type here. The Steps list stays and is retitled **Wind-down**, because
    trimming it is the one lever the figure answers to. Wake and sleep need come
    along into the tracker card, since the card that normally holds them is the
    one being hidden. iOS additionally hides the arm bar — "Arm plan" beside a
    card deriving lights-out from now would be arming a different question.
  - **Web gotchas.** The whole section is `aria-live`, so it keeps the same
    render-once / tick-often split the bridge uses: `renderTrack()` rebuilds the
    ride controls and never touches them via `innerHTML` (the origin is a live
    text input someone may be mid-search in), `renderTrackLive()` runs on the 1s
    interval. `.field` only stacks its label inside `.target-row`, so `.track-tail`
    has to restate it. The origin autocomplete gets its own handler pair rather
    than joining the step list's delegation — the same shape the Places
    add-field already has — while reusing `renderPlaceMenu` / `menuResults` so
    the three fields can't drift.
  - **iOS gotchas.** `TrackState` needs a hand-written lenient `init(from:)` and
    `PairSnapshot.track` has to be `Optional`: a default value does **not** make
    a key optional to the synthesized decoder (same trap `PlaceRef` documents),
    and one missing key would take the whole saved pair down with it. The
    ticking `TimelineView` wraps only the figure and verdict — wrapping the ride
    controls too would rebuild their sheet/loading `@State` every second.
  - **Mode state is persisted.** Losing it on a refresh mid-evening is worse than
    opening in it once, and Exit is one tap. The storage record stays `v: 2` with
    an additive `track` key, so it round-trips through a build that predates it.

- [x] **Collapsible travel legs** — once both endpoints resolve, a leg folds to a
  one-line summary (`🚗 from → to · 0.9 mi · 4 min`) with a chevron to reopen. An
  error or a missing endpoint always renders expanded, since the fields are what
  needs fixing. Open/closed state is in-memory only (`travelOpen` / `userExpanded`),
  so reopening the app on a settled leg shows the tidy version.

## Backlog

### 1. Timer integration — what's still missing
The core shipped (see Done). Still open:
- **Surviving a closed tab (web).** v1 is explicitly tab-open-only: the countdown
  and its alerts run on the page's own 1s interval, so closing the tab stops
  both. Fixing it means a Service Worker plus scheduled notifications
  (`showTrigger`), which only Chromium ships — Safari and Firefox have neither,
  and Safari is where a phone-shaped user actually is. A Service Worker that only
  helps one browser is worth doing once there is a second reason to add one.
- **Pushing the Live Activity from outside the app (iOS).** Same shape of
  problem: local updates only land while the app is running, so a card the user
  never opens the app for goes stale at the first boundary. Real fix is
  ActivityKit push tokens and a server to send them, which Backplan does not have
  and which would break the no-backend constraint.
- **Sound / vibration on step transitions.** Notifications carry the default
  sound today. A distinct per-step tone, or a haptic on iOS, is unclaimed.
- **Snooze / "I'm running late".** The countdown reports overrun but offers
  nothing to do about it. Shifting the whole remaining chain by N minutes is the
  obvious move and it interacts with the night bridge (#5), which already knows
  what a slip costs tomorrow.

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
**Shipped** — see the pair and **Track to sleep** in Done. Track mode is a third
lens on this same one edge, anchored at *now* instead of at a bedtime you typed;
it promoted this item's "if the evening started right now" line from a footnote
to the headline and gave it the ride home the pair had nowhere to put. The
original write-up is kept below because the model reasoning is still the model.

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
