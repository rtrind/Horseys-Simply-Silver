# Lua Wheel Implementation Progress

## Phase 1: Foundation ✅ COMPLETE

### What Works
- Custom Lua wheel replaces engine wheel completely
- Group headers with rainbow colors and open/close functionality
- Pulsing highlight on focused songs
- MenuLeft/MenuRight navigation with continuous scrolling
- SortMenu integration working

## Phase 2: Groups & Sorting ✅ COMPLETE

### What Works
- All sort methods implemented with proper filtering
- Smart steps selection for Difficulty sort
- Style filtering (hides incompatible charts)
- Old difficulty sorts removed from menu
- EscapeFromEventMode code disabled
- Songs filter by current style (Single/Double)

## Phase 3: Audio Preview & NoteField Sync ( CRITICAL - COMPLETE)

### Completed Tasks
- [x] **Audio Preview System** (CRITICAL - Project fails without this)
  - [x] Play song preview when focused (respect SAMPLESTART/SAMPLELENGTH from chart)
  - [x] Loop preview or play once (respect user preference setting)
  - [x] Stop audio when changing songs
  - [x] Fade in/out transitions (handled by PlayMusicPart)
  - [x] Handle songs without preview metadata (falls back to stop_music)
- [x] **NoteField Preview Synchronization** (CRITICAL)
  - [x] Sync NoteField to audio playback position (via GAMESTATE:SetSongBeat in Update loop)
  - [x] Respect player modifiers (speed mods, scroll direction, etc.)
  - [x] Update in real-time as audio plays
  - [x] Handle preview loop correctly

### Planned Tasks
- [x] Test audio preview with various song formats
- [x] Test NoteField sync accuracy
- [x] Verify modifier application works correctly

### Bug Fixes
- [x] Fixed initial audio playback not starting on screen entry (added OnCommand delay)

## Phase 4: Favorites & Grades (Not Started)

### Planned Tasks
- [x] Implement favorites section with deduplication
- [x] Add favorites icon to wheel items
- [x] Add grade display (P1/P2) to wheel items
- [x] Add combo line display (yellow/green/white + number when <10)
- [x] Implement favorites toggle (sequence: MenuUp MenuDown MenuUp MenuDown)
- [x] Test favorites workflow
- [x] Reimplement wheel scroll speed

### Bug Fixes
- [x] When changing the sort order, the wheel should be positioned in the same song it was before the change

## Phase 5: Integration & Polish (Not Started)

### Planned Tasks
- [x] Remove all remaining `GetMusicWheel()` calls from theme
- [x] Cleanup metrics.ini SSM
- [x] Change "Reloading screen" message to a proper "loading", just like the transition from profile/style selection to SSM screen
- [x] Change "Title screen" from Simply Love to Simply DDR
- [x] Implement pattern info toggle
- [x] Test with both P1 and P2 profiles
- [x] Performance testing (large libraries, fast scrolling)
- [x] Play sound (same as original wheel) on wheel movement

### Bug Fixes
- [x] Dynamic second player join (pressing enter on an unjoined player) broken (should open the profile selection with the extra player for selection). Right now, it silently adds the player, on the second enter it tries to start gameplay and crashes.
- [x] GetLamp should be called once per song in the wheel
- [x] I can still activate the sort menu while the starting gameplay screen is awaiting for a possible start to go to the options
- [x] Make the difficulty change as a metric on metrics.ini and adjust input handler accordingly
- [x] Do we need to keep SSM codenames on metrics.ini? We either use them on the input handler, or we let them hardcoded there and remove them from the metrics.
- [x] When scrolling fast thru the songs on the wheel, sometimes it stops changing the audio to the current song and continues to play one of the other songs from before. When it finishes, you change to another song and the audio fixes itself.

## Phase 6: Optimization (In Progress)

### Completed Tasks
- [x] Add debug instrumentation for crash diagnosis (90-min crash)
  - Added `SL_Debug` module in `Scripts/06 SL-Utilities.lua` with:
    - Session uptime tracking (HH:MM:SS format)
    - Memory usage monitoring (Lua heap size)
    - Screen transition logging
    - Periodic status logging (every 60 seconds)
    - Performance timing helpers (`StartTimer`/`EndTimer`)
    - Safe function wrapper (`SafeCall`)
    - Error logging with context
  - Added screen change hook in `ScreenSystemLayer overlay.lua`
  - Added performance timing to `RebuildWheelData` and `BuildFavoritesSection`
- [x] Add error handling for missing songs/steps
  - Added safe song accessor functions (`GetSongTitle`, `GetSongDir`, `GetSongGroup`) with pcall wrapping
  - Added error handling to `GetAllSongs`, `GetSongsInGroup`, `GetAllGroups` SONGMAN API calls
  - Added safety checks to `Scroll` and `GetFocusedItem` for empty wheel states
  - Added nil checks throughout FilterSongs and HasValidSteps
- [x] Handle edge cases (empty favorites, single song, empty wheel)
  - Favorites already handled by `if #favorites > 0` check
  - Added placeholder item for empty wheel to prevent crashes
  - Added focus_index bounds checking in GetFocusedItem
- [x] Extract common code patterns to functions
  - Added `CreateSongItem(song, group, opts)` - creates song wheel items
  - Added `CreateGroupHeader(group_name, song_count, index)` - creates group headers
  - Added `AddSongsToItems(items, songs, group, opts)` - batch add songs
  - Added `FilterSongsForCurrentStyle(all_songs)` - filter by current style
  - Added `GetAllSongsForCurrentStyle()` - get all songs filtered
  - Refactored 8 build functions to use these helpers
  - Reduced ~100 lines of duplicated code
- [x] Minimize unused items in metrics.ini
  - Removed `[ScreenSelectCourse]`, `[CourseWheel]`, `[ScreenSelectCourseNonstop]` sections
  - Removed `[CourseCodeDetector]` section
  - Removed `CourseOnCommand` from `[MusicWheelItem]`
  - Removed `NumCourseGroupColors` and `CourseGroupColor1` from `[SongManager]`
  - Added comments documenting removed sections
- [x] Simplify remaining WideScale() calls to 16:9 values only
  - Removed all 30+ WideScale() calls from metrics.ini
  - Replaced with direct 16:9 values (second parameter)
  - Affected sections: MemoryCardDisplay, OptionRow, ScreenSystemLayer, EditMenu, MenuTimer, etc.
- [x] Remove ITL, SRPG, and GrooveStats code (in progress - major refactor)
  - **Deleted script files:**
    - `Scripts/SL_ITL.lua` - ITL tournament integration
    - `Scripts/SL_SRPG6.lua` - SRPG mode support
    - `Scripts/SL-Helpers-GrooveStats.lua` - GrooveStats API
  - **Deleted BGAnimation files:**
    - `ScreenPromptToSetSrpgVisualStyle overlay.lua`
    - `ScreenEvaluation common/Shared/EventOverlay.lua`
    - `ScreenEvaluation common/Shared/AutoSubmitScore.lua`
    - `ScreenEvaluation common/PerPlayer/Upper/EventProgress.lua`
    - `ScreenEvaluation common/PerPlayer/ItlFile.lua`
    - `ScreenEvaluation common/PerPlayer/RpgRatemod.lua`
    - `ScreenSelectMusic overlay/Leaderboard.lua`
    - `ScreenSelectMusic overlay/SortMenu/Leaderboard_InputHandler.lua`
  - **Deleted Graphics files:**
    - `Graphics/MusicWheelItem RPGRate.lua`
    - `Graphics/ITL Online/` folder (14 PNG files)
  - **Modified files:**
    - `Scripts/SL_Init.lua` - Removed ITLData, ApiKey, SL.GrooveStats, SL.Downloads
    - `Scripts/99 SL-ThemePrefs.lua` - Removed SRPG8, EnableGrooveStats, BoogieStats prefs
    - `BGAnimations/ScreenSystemLayer overlay.lua` - Removed GrooveStats service pane
    - `BGAnimations/ScreenSelectMusic overlay/default.lua` - Removed Leaderboard LoadActor
    - `BGAnimations/ScreenSelectMusic overlay/SortMenu/default.lua` - Removed leaderboard options
    - `Graphics/MusicWheelItem Song NormalPart/GetLamp.lua` - Removed ITL lamp logic
  - **Stubbed files (return empty actor):**
    - `BGAnimations/ScreenSelectMusic overlay/PerPlayer/Scorebox.lua`
    - `BGAnimations/ScreenGameplay underlay/PerPlayer/StepStatistics/Scorebox.lua`
  - **Added stub functions in `Scripts/SL-Helpers.lua`:**
    - `IsServiceAllowed()` - Always returns false
    - `IsItlSong()` - Always returns false
    - `UpdatePathMap()` - No-op
    - `WriteItlFile()` - No-op
    - `LoadUnlocksCache()` - Returns empty table
    - `RemoveStaleCachedRequests()` - No-op
    - `RequestResponseActor()` - Returns empty ActorFrame
    - `ParseGrooveStatsIni()` - Returns empty table
    - `GetGrooveStatsIni()` - Returns nil
  - **Status:** Theme loads and runs without errors. Remaining ~540 references are mostly:
    - Comments documenting removed features
    - Language strings (can be cleaned up later)
    - Conditional checks that now always evaluate to false (safe)

### Planned Tasks
- [x] Continue ITL/SRPG/GrooveStats removal (remaining files)
- [x] Remove tournament mode
- [x] Remove files from the original engine wheel
- [x] Remove Outfox online features
- [x] Simplify remaining GAMESTATE:IsCourseMode() calls (reduced from 126 to 0)
- [ ] Optimize lazy loading to prevent stuttering
- [ ] Optimize memory usage (unload off-screen items)
- [ ] Test edge cases (large libraries, fast scrolling)
- [ ] Performance profiling and optimization

### Bug Fixes
- [ ] TBD

## Won't fix
- [ ] Timer is broken on SSM, but I won't ever use it.
- [ ] NotefieldPreview shows some frames of something (I don't know what it is) before showing proper steps (this bug already exists on upstream fork)

## Ideas for the future
- [ ] A way to automate testing and make it easier to detect regressions