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

### 2. Map support
Pull real travel time into "travel" steps instead of hand-entered durations.
- Mark a step as a travel leg with an origin + destination.
- Fetch live drive/walk/bike/transit duration from a maps API and auto-fill the
  step's minutes (re-fetch on demand).
- Possibly show the route inline.
- API choice TBD — Google Directions has transit; this introduces an API key and
  arguably a tiny backend/proxy, which breaks the pure-static constraint. Evaluate
  client-only options or a thin serverless proxy.
- Cross-reference: Trip Shift already researched Google Maps Platform (Directions/
  Places) — reuse that learning.

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
