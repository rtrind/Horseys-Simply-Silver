# Lua Wheel Implementation Progress

## Phase 1: Foundation ✅ COMPLETE

### Completed Tasks
- [x] Created `Scripts/SL_MusicWheel.lua` with WheelState table
- [x] Implemented `BuildWheelData()` for flat song list (Group and Title sorts)
- [x] Created `BGAnimations/ScreenSelectMusic overlay/MusicWheel/WheelItem.lua` metatable
- [x] Implemented basic `create_actors()` with song title + banner + group headers
- [x] Created `BGAnimations/ScreenSelectMusic overlay/MusicWheel/default.lua` with sick_wheel instance
- [x] Integrated wheel into ScreenSelectMusic overlay
- [x] Fixed script loading order (renamed to SL_MusicWheel.lua)
- [x] Fixed input handler registration (moved to OnCommand)
- [x] Changed controls to MenuLeft/MenuRight (theme uses L/R for songs, U/D for difficulty)
- [x] Added InputEventType_Repeat for continuous scrolling when holding button
- [x] **ENGINE WHEEL FULLY DISABLED** - Changed to ScreenWithMenuElements class
- [x] **CUSTOM INPUT HANDLER** - Added handler for SortMenu and quit screen
- [x] Test scrolling with MenuLeft/MenuRight - WORKING
- [x] Verify song selection updates GAMESTATE correctly - WORKING
- [x] Test group headers display properly - WORKING
- [x] **VISUAL ENHANCEMENTS** - Pulsing highlight for focused songs
- [x] **RAINBOW COLORS** - Group headers have rainbow colors based on index
- [x] **MESSAGE BROADCASTING** - CurrentStepsP1/P2Changed messages broadcast on song change
- [x] **API MIGRATION** - SongDescription.lua updated to use SL.MusicWheel API

### Files Created
1. **Scripts/SL_MusicWheel.lua** (340 lines) - RENAMED from SL-MusicWheel.lua to load after SL_Init.lua
   - WheelState global table
   - BuildWheelData_Group() - Groups with headers
   - BuildWheelData_Title() - Flat alphabetical list
   - Scroll() - Navigation with wrapping
   - Initialize() - Setup on screen entry

2. **BGAnimations/ScreenSelectMusic overlay/MusicWheel/WheelItem.lua** (220 lines)
   - create_actors() - Banner, title, group name, song count, pulsing background
   - transform() - Positioning with focus effects, pulsing animation control
   - set() - Updates display for songs and groups
   - set_song() - Song-specific display with pulsing effect
   - set_group_header() - Group-specific display with rainbow colors
   - Rainbow color calculation based on group_index (HSV color wheel)

3. **BGAnimations/ScreenSelectMusic overlay/MusicWheel/default.lua** (390 lines)
   - sick_wheel instance creation
   - Input handler for MenuLeft/MenuRight
   - Message handlers for rebuild
   - Integration with GAMESTATE
   - Broadcasts CurrentStepsP1/P2Changed on song change and wheel rebuild
   - Ensures steps are always set for both players
   - MusicWheelRebuiltMessageCommand updates GAMESTATE and broadcasts steps messages

### Files Modified
1. **BGAnimations/ScreenSelectMusic overlay/default.lua**
   - Added LoadActor("./MusicWheel/default.lua")
2. **metrics.ini**
   - Changed Class to `ScreenWithMenuElements` (removes engine wheel entirely)
   - Removed `SampleMusicLoops`, `SampleMusicFallbackFadeInSeconds`, `DoRouletteOnMenuTimer`
   - Simplified CodeNames (removed engine wheel specific codes)
   - Added custom input handler for SortMenu and quit screen
3. **Scripts/SL_MusicWheel.lua**
   - Added group_index field to group headers for rainbow coloring
4. **BGAnimations/ScreenSelectMusic overlay/SongDescription/SongDescription.lua**
   - Replaced GetMusicWheel() calls with SL.MusicWheel.GetFocusedItem()
   - Updated duration and BPM display logic for Lua wheel API
5. **BGAnimations/ScreenSelectMusic overlay/NotefieldPreview.lua**
   - Reverted to original implementation (working correctly)
   - Preview tied to audio timing - will be enhanced with audio preview
6. **BGAnimations/ScreenSelectMusic overlay/SortMenu/SortMenu_InputHandler.lua**
   - Replaced GetMusicWheel():ChangeSort() calls with SL.MusicWheel.RebuildWheelData()
   - Updated favorites toggle to rebuild wheel instead of nudging engine wheel
   - Updated playlist loading to use Lua wheel rebuild

### Phase 1 Complete! ✅
The Lua wheel is now the **sole music wheel** in the theme. Engine wheel is completely disabled at the class level.

### Known Limitations (Phase 1)
- Groups are always closed (no open/close yet)
- No favorites section yet
- No grades/highscores displayed
- No favorites icons
- Only Group and Title sorts supported
- No cascade animation yet
- No audio preview (needed for NoteField preview to show properly)

## Phase 2: Groups & Sorting (IN PROGRESS)

### Completed Tasks
- [x] Extend WheelItem metatable to handle group_header type
- [x] Add group song count display
- [x] Add empty group hiding
- [x] Add rainbow colors for group headers
- [x] Add pulsing highlight effect for focused songs
- [x] Fix message broadcasting (CurrentStepsP1/P2Changed)
- [x] Update SongDescription to use Lua wheel API
- [x] Implement group open/close logic in `ToggleGroup()`
- [x] Add songs to wheel when group is opened
- [x] Implement `RebuildWheelData()` for sort changes (triggered by existing SortMenu)
- [x] Update SortMenu_InputHandler to use Lua wheel API

### Bug Fixes
- [x] Fixed NoteField preview not updating after wheel rebuild
- [x] Fixed multiple groups opening on screen load (state persistence issue)
- [x] Fixed NoteField preview not loading on initial screen entry (timing issue)
- [x] Fixed NoteField warnings about missing columns (initialized GAMESTATE before actor creation)

### Remaining Tasks
- [ ] Test folder navigation (Start key to open/close groups)
- [ ] Test sort order changes from SortMenu
- [ ] Add sample music preview when song is focused
- [ ] Fix NoteField preview visibility (requires audio preview first)

## Phase 3: Favorites & Grades (Not Started)

### Planned Tasks
- [ ] Implement `BuildFavoritesSection()` with deduplication
- [ ] Add favorites icon to WheelItem display
- [ ] Implement `GetSongHighscores()` with context-aware caching
- [ ] Add grade display (P1/P2) to WheelItem
- [ ] Add combo line display (yellow/green/number)
- [ ] Implement favorites toggle (MenuUp+MenuDown)
- [ ] Test favorites workflow and verify no highscore bugs between contexts

## Phase 4: Integration & Polish (Not Started)

### Planned Tasks
- [x] Create custom input handler - DONE (you handled this)
- [x] Broadcast `CurrentSongChangedMessage` on focus change - DONE
- [x] Update metrics.ini to disable engine wheel - DONE (ScreenWithMenuElements)
- [ ] Update `SortMenu_InputHandler.lua` to call Lua wheel rebuild instead of engine wheel
- [ ] Remove all `GetMusicWheel()` calls from theme (cleanup phase)
- [ ] Add animations (cascade, highlight effects)
- [ ] Test with both P1 and P2 profiles
- [ ] Performance testing (large libraries, fast scrolling)

## Phase 5: Bug Fixes & Optimization (Not Started)

### Planned Tasks
- [ ] Fix any stuttering issues (optimize lazy loading)
- [ ] Fix highscore cache invalidation edge cases
- [ ] Optimize memory usage (unload off-screen items)
- [ ] Test with edge cases (empty favorites, single song, etc.)
- [ ] Add error handling for missing songs/steps
- [ ] Test group context switching thoroughly
- [ ] Performance profiling and optimization

## Testing Checklist

### Phase 1 Testing ✅ COMPLETE
- [x] Wheel displays on ScreenSelectMusic
- [x] MenuLeft scrolls up through items
- [x] MenuRight scrolls down through items
- [x] Scrolling wraps around (cyclical)
- [x] Song titles display correctly
- [x] Banners load correctly
- [x] Group headers display with song counts
- [x] Focused item is highlighted
- [x] GAMESTATE:GetCurrentSong() returns focused song
- [x] No Lua errors in log
- [x] Continuous scrolling when holding button
- [x] Pulsing highlight effect on focused songs
- [x] Rainbow colors on group headers (Group sort only)
- [x] Message broadcasting updates left panel correctly
- [x] SongDescription displays correct duration/BPM

### Integration Testing (Later Phases)
- [ ] SortMenu changes sort order correctly
- [ ] Favorites section appears when songs favorited
- [ ] No duplicate favorites with multiple players
- [ ] Highscores display correctly in all contexts
- [ ] Group open/close works properly
- [ ] Performance is smooth with large libraries

## Notes

### Current Behavior
- **Engine wheel is FULLY DISABLED** (ScreenWithMenuElements class - no engine wheel at all)
- **Lua wheel is the ONLY wheel** - no conflicts
- **Custom input handler** manages SortMenu and quit screen
- **Phase 1 COMPLETE** - Ready for Phase 2!

### Debug Commands
- Select+Start: Print wheel state to log (via SL.MusicWheel.DebugPrintState())

### Configuration
- Wheel position: X = SCREEN_CENTER_X - 186, Y = SCREEN_CENTER_Y + 98
- Number of items: 11 (9 visible + 1 above + 1 below)
- Item spacing: 72 pixels
- Item size: 400x70 pixels
- Banner size: 100x60 pixels
