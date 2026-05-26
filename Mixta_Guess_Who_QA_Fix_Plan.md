# Mixta's Guess Who — QA Fix Plan

**Source:** `Mixta_Guess_Who_QA_Testing_Report_v2.pdf` (May 02, 2026)  
**App:** `mixta_flutter` · package `com.mixta.gtc`  
**Status:** Planning — not started  
**Last updated:** 2026-05-26

## Objective

Close QA findings in priority order for Google Play closed testing and production readiness, without changing immutable core managers unless unavoidable. Most work lives in `mixta_flutter/lib/plugins/` and shared UI (`drawer_base`, `screen_base`, `navigation_manager`).

## Recommended fix order

| Phase | Issues | Why this order |
|-------|--------|----------------|
| **1 — Ops (no app build)** | #1 Privacy Policy | **Play Console only:** hosted `policy.html` + same URL in Store listing (no in-app link required for our approach) |
| **2 — Ship first (app)** | #3 Description scroll, #4 Answer feedback, #2 Back navigation | **Major** gameplay + navigation; highest impact for QA retest |
| **3 — Polish release** | #5 Loading lag, #6 Slow username, #7 Leaderboard drawer | **Minor**; shared “perceived performance” theme |
| **4 — Later** | #8–#14 Suggestions | Not required for closed testing |

Google only requires **one** update during the 14-day closed testing window; minimum viable **app** release: **at least two Major items (#3, #4, or #2)**. Policy URL is handled outside the app (see #1).

---

## Phase 1 — Critical (ops only, no Flutter changes)

### Issue #1 — Missing Privacy Policy

**Severity:** Critical · **Priority:** High · **Owner:** ops / content (not app code)

**Approach (chosen):** Publish a public HTML page and set the URL in **Google Play Console**. Users see the policy on the Store listing; **no in-app menu link required** for this release.

**Steps**

1. Create and deploy `https://gtc.mixta.mt/legal/policy.html` (HTTPS, no login).
2. Cover: data collected (username, scores, progress, device/cache), use, retention, third parties (e.g. AdMob, API host), contact email, deletion (mention in-app “Delete my data” on Profile if applicable).
3. Play Console → **App content** → **Privacy policy** → paste the **same URL**.
4. Smoke-test the URL in a mobile browser before submitting for production.

**Optional (already in repo):** `AndroidManifest.xml` `privacy_policy_url` meta-data points at the same URL — informational only, not shown in UI.

**Note for QA:** Fiverr report asked for an in-app link; if retest still flags #1, either add in-app links later or document Store listing URL for the tester.

---

## Phase 2 — Major (gameplay + navigation)

### Issue #2 — Back button closes app instead of stepping back

**Severity:** Major · **Priority:** High

**Problem:** Android system back exits the app from every screen.

**Likely root cause:** Navigation uses `context.go(path)` everywhere (e.g. `drawer_base.dart`). **`go` replaces** the route stack instead of pushing, so GoRouter often has **nothing to pop** → back finishes the activity.

**How to fix**

1. **Use stack navigation for inner screens**
   - Drawer and deep links: change `context.go(route.path)` → `context.push(route.path)` for non-home routes.
   - Home stays `context.go('/')` when resetting to root.

2. **Central back handling**
   - Wrap app or routes with GoRouter’s back button dispatcher, or per-screen `PopScope` / `BackButtonListener`:
     ```dart
     PopScope(
       canPop: false,
       onPopInvokedWithResult: (didPop, result) async {
         if (didPop) return;
         if (GoRouter.of(context).canPop()) {
           context.pop();
         } else {
           // on home only: double-back-to-exit
         }
       },
       child: ...
     )
     ```
   - Implement **double-back-to-exit** on `/` only: first back → SnackBar “Press back again to exit”; second within ~2s → `SystemNavigator.pop()`.

3. **Places to audit**
   - `lib/core/00_base/drawer_base.dart`
   - `lib/plugins/main_plugin/screens/home_screen.dart`
   - `lib/plugins/game_plugin/screens/progress_screen/progress_screen.dart` (`context.go('/preferences')`)
   - `lib/plugins/game_plugin/modules/leaderboard_module/leaderboard_module.dart`
   - `Navigator.pushReplacementNamed` usages in `game_screen.dart`, `level_up_screen.dart` — prefer router `push`/`replace` consistently

4. **Verify**
   - Home → Game → Back → Home (app stays open).
   - Home → Back → Back → app exits (with toast if implemented).

**Files (expected touch):**

- `mixta_flutter/lib/core/00_base/drawer_base.dart`
- `mixta_flutter/lib/core/managers/navigation_manager.dart` (optional: shell routes / `parentNavigatorKey`)
- `mixta_flutter/lib/core/00_base/screen_base.dart` or `main.dart` (global PopScope / exit handler)
- Call sites using `go` / `pushReplacementNamed`

---

### Issue #3 — Description scroll unreliable on Guess Who page

**Severity:** Major · **Priority:** High

**Problem:** Long clue text in the fact/description area does not scroll reliably.

**Likely root cause:** **Nested scrollables** — outer `SingleChildScrollView` in `game_screen.dart` wraps `FactBox`, which has its own `ListView` (`fact_box.dart`). Parent and child compete for vertical drag gestures.

**How to fix**

1. **Remove nested scrolling (preferred)**
   - Option A: Give `FactBox` a fixed max height and **only** scroll inside `FactBox` (keep inner `ListView`); remove `FactBox` from the outer `SingleChildScrollView` column OR replace outer scroll with a single `CustomScrollView` + slivers.
   - Option B: Make `FactBox` non-scrollable: use `Text` with `maxLines` + “Read more” → `showModalBottomSheet` / dialog with full scrollable text (QA’s “tap to expand” fallback).

2. **Gesture fixes (if keeping nested structure)**
   - Inner list: `physics: const ClampingScrollPhysics()` and wrap with `NotificationListener<ScrollNotification>` to prevent parent from stealing overscroll.
   - Or set outer scroll `physics: NeverScrollableScrollPhysics()` for the section containing `FactBox`.

3. **UX polish**
   - Visible `Scrollbar` (already in `fact_box.dart`) + optional “Expand clues” icon on long content.
   - `Semantics(identifier: 'game_description', ...)` on scroll region.

4. **Verify**
   - Longest celebrity clue on small phone (e.g. 5.5") — full text reachable by scroll or expand.

**Files (expected touch):**

- `mixta_flutter/lib/plugins/game_plugin/screens/game_screen/game_screen.dart` (layout around line ~394)
- `mixta_flutter/lib/plugins/game_plugin/screens/game_screen/components/fact_box.dart`

---

### Issue #4 — Answer background always green (wrong answers too)

**Severity:** Major · **Priority:** High

**Problem:** Selecting any answer shows green feedback, even when wrong.

**Root cause (code):** `game_image_grid.dart` applies **`Colors.greenAccent` border and glow for any selected image**, not based on correctness:

```dart
color: isSelected ? Colors.greenAccent : ...
```

`FeedbackMessage` already distinguishes correct vs incorrect text color (`feedback.contains("Correct")`), but the **grid selection styling** is always green.

**How to fix**

1. **Pass correctness into the grid**
   - After `checkAnswer` in `game_play_module.dart`, expose `bool? lastAnswerCorrect` (or pass `isCorrect` into callback before showing feedback).
   - `GameImageGrid`: add optional `bool? selectedWasCorrect` or derive from parent state set in `_handleAnswer` callback alongside `feedbackMessage`.

2. **Conditional styling**
   - Selected + correct → green border / glow (`AppColors` success semantic if added).
   - Selected + wrong → red border / glow (`AppColors.redAccent`).
   - Unselected → existing accent/grey.

3. **Optional alignment with overlay**
   - `feedback_message.dart`: tint overlay green/red lightly behind the modal (not only text).
   - Close button: green theme only when correct (line ~117 currently always `AppColors.accentColor`).

4. **Verify**
   - Wrong answer → red selection + “Incorrect” overlay; correct → green + confetti.

**Files (expected touch):**

- `mixta_flutter/lib/plugins/game_plugin/screens/game_screen/components/game_image_grid.dart`
- `mixta_flutter/lib/plugins/game_plugin/screens/game_screen/game_screen.dart` (`_handleAnswer`)
- `mixta_flutter/lib/plugins/game_plugin/modules/game_play_module/game_play_module.dart` (optional: return `bool` from `checkAnswer`)
- `mixta_flutter/lib/plugins/game_plugin/screens/game_screen/components/feedback_message.dart` (optional polish)

---

## Phase 3 — Minor (performance & interaction)

### Issue #5 — App loading delays and lag

**Severity:** Minor · **Priority:** Medium

**How to fix**

1. **Measure**
   - Flutter DevTools timeline on cold start, Game screen round load, Leaderboard, Progress.
   - Log timestamps already in `game_screen.dart` / modules — compare before/after.

2. **Common wins in this codebase**
   - Ensure loading overlay (`screen_overlay.dart`) shows whenever `game_round` waits on images + facts.
   - Defer non-critical work post-frame (`addPostFrameCallback`).
   - Cache network images (already `cached_network_image`); prefetch next round images if API returns URLs early.
   - Avoid redundant `setState` / `force: true` state updates in hot paths.

3. **Perceived speed**
   - Skeleton placeholders on Leaderboard / Progress while API loads.
   - Spinner on any action > ~300ms.

**Files to profile:** `game_screen.dart`, `game_play_module.dart`, `leaderboard_module.dart`, `progress_screen.dart`, `main.dart` (init / `appManager.initializeApp`).

---

### Issue #6 — Username creation slow

**Severity:** Minor · **Priority:** Medium

**How to fix**

1. **Client**
   - `preferences_screen.dart` + `user_register.dart`: show `CircularProgressIndicator` on submit; disable form while `registerUser` runs.
   - SnackBar on timeout / slow network.

2. **Server / API**
   - Profile `LoginModule.registerUser` → `ConnectionsModule` endpoint: uniqueness check, extra round trips, large payload on register.
   - Add server-side index on username; return quickly with minimal body.

3. **Optional optimistic UI** (only if API is reliable)
   - Show success UI immediately; reconcile on failure (revert + error).

**Files:** `login_module.dart`, `user_register.dart`, `preferences_screen.dart`, backend user/register route in `mixta_flask` (if slow queries found).

---

### Issue #7 — Leaderboard drawer tap inconsistent; menu stays open

**Severity:** Minor · **Priority:** Medium

**Problem:** Tap sometimes missed; drawer stays open during navigation.

**How to fix**

1. **Close drawer first**
   ```dart
   onTap: () {
     Navigator.of(context).pop(); // close drawer
     context.push(route.path);
   }
   ```

2. **Hit target**
   - Ensure no overlay absorbs taps; `ListTile` fills width; enable `splashColor` / Material ripple.

3. **Loading on destination**
   - Leaderboard screen shows progress while module fetches; do not block drawer close on fetch.

**Files:** `drawer_base.dart`, `leaderboard_screen.dart`, `leaderboard_module.dart`.

---

## Phase 4 — Suggestions (post closed testing)

| # | Title | Approach summary |
|---|--------|------------------|
| 8 | UI/UX polish | Theme tokens in `theme_consts.dart`; consistent `AppPadding` / `AppTextStyles`; light motion on score updates |
| 9 | Account section | Extend Profile: list stored fields, link to privacy/delete (partially exists) |
| 10 | Light/dark theme | `ThemeMode` + persistence in `SharedPrefManager`; avoid hardcoded `ThemeData.dark()` in `main.dart` |
| 11 | Share scores | `share_plus` on level-up / progress; `ACTION_SEND` with Play Store link |
| 12 | Help & support | Settings section: FAQ URL + `mailto:` support |
| 13 | Onboarding | First-launch flag in shared prefs; 3–4 page `PageView` with Skip |
| 14 | Premium | Play Billing + Settings “Premium” screen (larger scope; separate plan) |

---

## Suggested implementation checklist

Use this as a working task list; check off as completed.

### Release A (closed testing minimum)

- [ ] **#1** Policy page live + Play Console URL (hosted HTML only — no app change)
- [x] **#3** Fix fact/description scrolling + Expand bottom sheet (2026-05-26)
- [x] **#4** Green/red answer feedback on grid + feedback Close button (2026-05-26)
- [ ] **#2** `push` vs `go` + home double-back-to-exit
- [ ] QA smoke on physical Android build (`version` bump in `pubspec.yaml`)

### Release B (quality)

- [ ] **#5** Profile + loading indicators on slow screens
- [ ] **#6** Register spinner + backend profiling
- [ ] **#7** Drawer close + Leaderboard navigation

### Release C (backlog)

- [ ] **#8–#14** Per product priority

---

## Testing notes for QA retest

After **Release A**, ask QA to verify:

1. Privacy Policy opens from menu and Profile.
2. Back stack: inner screens → home → exit.
3. Long descriptions fully readable.
4. Wrong answers show red; correct show green.

Document build number sent to closed track in Play Console.

---

## Architecture constraints

Per project rules:

- Prefer changes in **plugins** and **utils**, not core managers (`StateManager`, `NavigationManager` singleton behavior) unless registration-only or agreed extension.
- UI colors/spacing: **`AppColors`**, **`AppTextStyles`**, **`AppPadding`** — replace hardcoded `Colors.greenAccent` / raw `EdgeInsets` when touching those files.
- No new managers/modules without explicit approval.

---

## References

- QA report: `Mixta_Guess_Who_QA_Testing_Report_v2.pdf`
- Flutter app root: `mixta_flutter/`
- Package ID: `com.mixta.gtc`
