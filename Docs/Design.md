# Horseys-Simply-Silver — Out-of-Gameplay Design

This document explains how the theme behaves outside of gameplay: the screen flow, mode selection, and dynamic player join/leave. It is intended for maintainers and contributors.

## Table of contents
- Overview
- Screen flow map (high-level)
- Mode selection
- Player join/leave lifecycle
- State and configuration
- Known edge cases and safeguards
- Validation notes
- Maintenance

## Overview
Purpose: document out-of-game UX and the underlying theme logic so future changes are safe and predictable.

Scope:
- Title → Profile/Style/Mode → Select Music → Options/Ready → Evaluation
- When and how players can join/leave without returning to Title
- Where configuration and preferences influence the above

Glossary:
- Mode: a theme-defined pathway that influences screens, filters, and options (e.g., Casual/ITG/Competitive).
- Late join: a player joining after the initial entry screen (e.g., at Select Music).

Sources to consult while reading:
- Scripts
  - `Scripts/SL-Branches.lua` (routing and NextScreen logic)
  - `Scripts/SL-SelectMusicHelpers.lua` (Select Music behaviors)
  - `Scripts/SL-PlayerOptions.lua` (player options lifecycle)
  - `Scripts/SL-PlayerProfiles.lua` (profile attach/detach)
  - `Scripts/SL-Utilities.lua`, `Scripts/SL-Helpers.lua` (shared helpers/messages)
  - `Scripts/SL-OperatorMenuOptions.lua` (prefs altering flow)
- Screens/overlays
  - `BGAnimations/ScreenTitleMenu/*`
  - `BGAnimations/ScreenSelectStyle/*` (or mode-select equivalents)
  - `BGAnimations/ScreenSelectMusic/*`
  - `BGAnimations/ScreenPlayerOptions/*`
  - `BGAnimations/ScreenEvaluation/*`
- Config
  - `metrics.ini` (screen classes/options affecting availability/transitions)
  - `Other/*.txt` (Casual/ITG mode artifacts)
- Logs
  - `c:/Games/OutFox 0.5.0 Alpha Win64 a40b/Logs/ProjectOutfox-Horseys-Simply-Silver.ThemeLua.*.log`

## Screen flow map (high-level)
High-level path:
```
ScreenTitleMenu → (Profile/Style/Mode Select) → ScreenSelectMusic → (Player Options/Ready) → ScreenEvaluation
```
Notes:
- Join is typically allowed at Title, Style/Mode selection, and Select Music; leaving is allowed until gameplay starts, and after gameplay at Evaluation.
- Branching for modes/styles is handled via `Scripts/SL-Branches.lua` and `metrics.ini`.

Join/leave per major screen (details in sections below):
- ScreenTitleMenu: join available; may branch to profile/style/mode screens.
- Style/Mode Select: join/leave available; affects style and downstream options.
- ScreenSelectMusic: late join allowed; back can unjoin a side.
- Player Options/Ready: join/leave may be restricted by metrics/prefs.
- ScreenEvaluation: leaving returns to Select Music or title depending on prefs.

Concrete routing (sources):
- `metrics.ini`
  - `ScreenTitleMenu` → `Branch.AllowScreenSelectProfile()` for Dance Mode
  - `ScreenSelectProfile` → `Branch.AllowScreenSelectColor()`
  - `ScreenSelectColor` → `Branch.AfterScreenSelectColor()`
  - `ScreenSelectStyle` → `ScreenProfileLoad`
  - `ScreenSelectPlayMode` (modes) → Casual → `ScreenProfileLoad`; ITG → `ScreenSelectPlayMode2`
  - `ScreenSelectPlayMode2` (Regular/Marathon) → `ScreenProfileLoad`
  - `ScreenProfileLoad` → `Branch.AfterSelectPlayMode()`
  - `ScreenSelectMusic`/`ScreenSelectMusicWide` → `Branch.AfterSelectMusic()`
  - `ScreenEvaluationStage` → `Branch.AfterEvaluationStage()`
- `Scripts/SL-Branches.lua`
  - `SelectMusicOrCourse()` returns `ScreenSelectMusicCasual` for Casual mode, else `ScreenSelectMusicWide` or `ScreenSelectMusic`
  - `AfterSelectMusic()` chooses `ScreenPlayerOptions` or goes straight to gameplay
  - `AfterProfileSave()` decides set continuation vs eval summary, handling continues and stage math
  - `SSMCancel()` and `AllowScreenEvalSummary()` provide back-paths from Select Music and post-game screens

## Mode selection
Describe available modes, how the selection UI works, and how modes alter the subsequent flow:
- Sources: `Scripts/SL-Branches.lua`, `metrics.ini`, overlays under `BGAnimations/Screen*`.
- Document how mode affects: song/pack filters, options rows, and next screens.

What exists in this theme:
- `metrics.ini:[ScreenSelectPlayMode]` choices: Casual, ITG. Default choice bound to `SL.Global.GameMode`.
- `metrics.ini:[ScreenSelectPlayMode2]` (shown after ITG): Regular (PlayMode Regular) and Marathon (Nonstop).
- `Scripts/SL-Helpers.lua:SetGameModePreferences()` applies preferences when mode changes (timing windows, fail type, profile stats prefix) and enforces consistent per-player options.
- `Scripts/SL-Branches.lua:SelectMusicOrCourse()` routes to `ScreenSelectMusicCasual` in Casual mode; otherwise a wide/narrow variant of Select Music.

Downstream impacts:
- Casual mode disables profile save and name entry paths and routes directly back after evaluation (see `Branch.AfterEvaluationStage()` and `AllowScreenNameEntry()`).
- Casual mode reduces timing windows (Decents/WayOffs off) via `SetGameModePreferences()`.
- ITG/Regular/Marathon affect `PlayMode` and which evaluation screen is used (`ScreenEvaluationStage` vs `ScreenEvaluationNonstop`).
- Select Music variant: Casual uses `ScreenSelectMusicCasual`; ITG uses `ScreenSelectMusic` or `ScreenSelectMusicWide` depending on aspect ratio (`IsUsingWideScreen()`).
- Profile load occurs after mode/style via `metrics.ini:[ScreenProfileLoad] → NextScreen=Branch.AfterSelectPlayMode()`.

## Player join/leave lifecycle
Events and inputs:
- Inputs: Start/Back (and coins/credits if enabled).
- Messages: `PlayerJoinedMessage`, `PlayerUnjoinedMessage`, plus screen-specific messages.

Per-screen behavior:
- Title/Style/Mode: handle join/unjoin, set style and attach profiles (`Scripts/SL-PlayerProfiles.lua`).
- Select Music: allow late join; update UI and modifiers (`Scripts/SL-SelectMusicHelpers.lua`).
- Player Options/Ready: persist options (`Scripts/SL-PlayerOptions.lua`).
- Evaluation: allow leaving or returning based on prefs.

Constraints:
- Join may require credits, a selected style, and/or an available side.
- Unjoining may be gated on screen state (e.g., disabled once loading gameplay).

Details and sources:
- Credits/premium logic for continues and pay mode in `Scripts/SL-Branches.lua:EnoughCreditsToContinue()` and `AfterProfileSave()`.
- AutoStyle handling in `Branch.AfterScreenSelectColor()` can forcibly join/unjoin sides and set style before profile load.
- Late join: theme applies mods for late-joined players via `Scripts/SL-PlayerOptions.lua:ApplyMods()` (invoked on `PlayerJoinedMessage` in Select Music overlay) and `Scripts/SL-PlayerProfiles.lua:LoadGuest()` to reset profile modifiers when a guest joins.
- Back-paths: `metrics.ini:[ScreenSelectMusic].PrevScreen=Branch.SSMCancel()`; in early stages Back returns to Title, after gameplay it may go to eval summary.
- Select Profile: underlay listens for join/unjoin to update UI
  - `BGAnimations/ScreenSelectProfile underlay/default.lua` uses `PlayerJoinedMessageCommand`/`PlayerUnjoinedMessageCommand` to refresh.
- Select Music (standard): overlay handles late join/unjoin, guest init, and mod application
  - `BGAnimations/ScreenSelectMusic overlay/default.lua` reacts to `PlayerJoinedMessage` with `LoadGuest(params.Player)` then `ApplyMods(params.Player)`; mirrors `PlayerUnjoinedMessage` for cleanup.
  - Per-player components under `BGAnimations/ScreenSelectMusic overlay/PerPlayer/*` update scoreboxes, density graphs, folder stats, cursors on join/unjoin.
- Select Music (wide): mirrors the above in `BGAnimations/ScreenSelectMusicWide overlay/*` with the same `LoadGuest`/`ApplyMods` flow.
- System layer: `BGAnimations/ScreenSystemLayer overlay.lua` updates credits UI on join/unjoin.
- Evaluation: per-player profile UI updates on join/unjoin events in `BGAnimations/ScreenEvaluation common/PerPlayer/Upper/PlayerProfiles.lua`.

## State and configuration
Primary state sources and their impact:
- ThemePrefs (see `Scripts/SL-OperatorMenuOptions.lua` and helpers): toggle behaviors (e.g., late join, confirmation flows).
- `metrics.ini`: screen classes, allow back/join, delays, and transitions.
- Profiles: attached/detached in `Scripts/SL-PlayerProfiles.lua`, influence options availability.
- Environment/theme state: helpers in `Scripts/SL-Utilities.lua`, `Scripts/SL-Helpers.lua`.

Key toggles to be aware of (examples; see `ThemePrefsRows` used in `metrics.ini:[ScreenThemeOptions]`):
- `AllowScreenSelectProfile`, `AllowScreenSelectColor`, `AllowScreenEvalSummary`, `AllowScreenNameEntry`, `AllowScreenGameOver`.
- `AutoStyle` impacts pre-join style and whether players are auto-joined.
- `DefaultGameMode` sets initial mode; `NumberOfContinuesAllowed` affects post-set flow; `AllowFailingOutOfSet` ends set early on fail.
- `MusicWheelStyle` determines wheel behavior (IIDX style hides inactive section).
- Operator menu options under `Scripts/SL-OperatorMenuOptions.lua` set engine prefs like `VideoRenderers`, offsets, custom songs limits; some options conditionally appear depending on platform/engine.
- Metrics determine back-navigation (`PrevScreen`/`NextScreen`) and which classes are used per screen (e.g., `ScreenSelectMusicWide`).

## Known edge cases and safeguards
- Late join at Select Music should correctly initialize modifiers and UI.
- Leaving at Evaluation should clean up profiles and return flow predictably.
- No-profile or guest-profile scenarios should not block joining.

Additional cases from sources:
- AutoStyle "versus" forces both joins; AutoStyle "single" with both already joined will unjoin P2 (`SL-Branches.lua`).
- Continues only available in CoinMode_Pay, subject to credits and premium; otherwise branch to eval summary (`AfterProfileSave()`).
- Cancel/back from Select Music uses `Branch.SSMCancel()`; after at least one stage played, it routes to eval summary instead of title.
- Event mode back codes are disabled in `metrics.ini:[CodeDetector] BackInEventMode=""` to avoid accidental back out of evaluation.
- In Marathon/Nonstop, evaluation uses `ScreenEvaluationNonstop` which routes directly to `ScreenProfileSave`.

## Validation notes
Test scenarios (verify in logs under `Logs/ProjectOutfox-Horseys-Simply-Silver.ThemeLua.*.log`):
1) From Title, 1P joins, selects mode, reaches Select Music; log contains screen transitions and `PlayerJoinedMessage`.
2) At Select Music, 2P late joins; UI and state update; log shows `PlayerJoinedMessage` and modifiers initialization.
3) After a song, at Evaluation, 2P unjoins; verify return flow and cleanup in logs.

Suggested in-app checks:
- Toggle `AutoStyle` and verify forced join/unjoin behavior on `ScreenSelectColor`/style path.
- Switch between Casual and ITG: confirm Select Music variant, options availability, and evaluation path changes.
- In Pay mode with premium variations, verify continues gate correctly (`EnoughCreditsToContinue`) and route to `ScreenPlayAgain` when available.

## Maintenance
- When adding/changing a screen, update `Screen flow map` and list its join/leave rules.
- When changing prefs or metrics, update `State and configuration` and affected behaviors.

