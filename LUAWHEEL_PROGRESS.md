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
- [ ] Performance testing (large libraries, fast scrolling)

### Bug Fixes
- [x] Dynamic second player join (pressing enter on an unjoined player) broken (should open the profile selection with the extra player for selection). Right now, it silently adds the player, on the second enter it tries to start gameplay and crashes.
- [x] GetLamp should be called once per song in the wheel
- [x] I can still activate the sort menu while the starting gameplay screen is awaiting for a possible start to go to the options
- [x] Make the difficulty change as a metric on metrics.ini and adjust input handler accordingly
- [x] Do we need to keep SSM codenames on metrics.ini? We either use them on the input handler, or we let them hardcoded there and remove them from the metrics.
- [ ] When scrolling fast thru the songs on the wheel, sometimes it stops changing the audio to the current song and continues to play one of the other songs from before. When it finishes, you change to another song and the audio fixes itself.

## Phase 6: More efficient debugging and testing (Not Started)
- [ ] Is there a way for automated tests to happen, considering the game is closed source? This way I could provide a specific testing config and run the tests in a consistent fashion, trying to detect regressions much faster than testing manually, pointing the error to the LLM and finding a fix, creating an easier development loop.

## Phase 7: Optimization (Not Started)

### Planned Tasks
- [ ] Identify more elements not used in the dedicab and remove them to make build leaner (remove course mode, ITL, unused graphics, SRPG, GrooveStats, ...)
- [ ] Minimize unused items in metrics.ini
- [ ] Optimize lazy loading to prevent stuttering
- [ ] Optimize memory usage (unload off-screen items)
- [ ] Test edge cases (empty favorites, single song, etc.)
- [ ] Add error handling for missing songs/steps
- [ ] Performance profiling and optimization
- [ ] Optimize all touched files in the project and extract common code to functions
- [ ] Add debug instrumentation to have more information if the build crashes (on previous build, after 90 minutes there was a usual crash)

### Bug Fixes
- [ ] TBD

## Won't fix
- [ ] Timer is broken on SSM, but I won't ever use it.