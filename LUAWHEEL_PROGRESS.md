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

## Phase 3: Audio Preview & NoteField Sync (🚧 CRITICAL - Not Started)

### Planned Tasks
- [ ] **Audio Preview System** (CRITICAL - Project fails without this)
  - [ ] Play song preview when focused (respect SAMPLESTART/SAMPLELENGTH from chart)
  - [ ] Loop preview or play once (respect user preference setting)
  - [ ] Stop audio when changing songs
  - [ ] Fade in/out transitions
  - [ ] Handle songs without preview metadata
- [ ] **NoteField Preview Synchronization** (CRITICAL)
  - [ ] Sync NoteField to audio playback position
  - [ ] Respect player modifiers (speed mods, scroll direction, etc.)
  - [ ] Update in real-time as audio plays
  - [ ] Handle preview loop correctly
- [ ] Test audio preview with various song formats
- [ ] Test NoteField sync accuracy
- [ ] Verify modifier application works correctly

### Bug Fixes
- [ ] TBD

## Phase 4: Favorites & Grades (Not Started)

### Planned Tasks
- [ ] Implement favorites section with deduplication
- [ ] Add favorites icon to wheel items
- [ ] Add grade display (P1/P2) to wheel items
- [ ] Add combo line display (yellow/green/white + number when <10)
- [ ] Implement favorites toggle (sequence: MenuUp MenuDown MenuUp MenuDown)
- [ ] Implement highscore caching with context awareness
- [ ] Test favorites workflow

### Bug Fixes
- [ ] TBD

## Phase 5: Integration & Polish (Not Started)

### Planned Tasks
- [ ] Remove all remaining `GetMusicWheel()` calls from theme
- [ ] Test with both P1 and P2 profiles
- [ ] Performance testing (large libraries, fast scrolling)

### Bug Fixes
- [ ] TBD

## Phase 6: Optimization (Not Started)

### Planned Tasks
- [ ] Optimize lazy loading to prevent stuttering
- [ ] Optimize memory usage (unload off-screen items)
- [ ] Test edge cases (empty favorites, single song, etc.)
- [ ] Add error handling for missing songs/steps
- [ ] Performance profiling and optimization
- [ ] Optimize all touched files in the project and extract common code to functions
- [ ] Identify more elements not used in the dedicab and remove them to make build leaner (remove course mode, ITL, unused graphics, ...)

### Bug Fixes
- [ ] TBD

## Notes

### Critical Path
**Phase 3 is CRITICAL** - Audio preview and NoteField synchronization are essential for the project to succeed. All other features are secondary.