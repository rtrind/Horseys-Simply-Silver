# Horseys-Simply-Silver

## ⚠️ Important Disclaimer

**This is a personal fork for my dedicated home cabinet (dedicab).** It is provided as-is with:

- **No support** - Issues and questions may not be answered
- **No feature requests** - Development follows my personal needs only
- **No guarantees** - May break, may have bugs, may change without notice
- **Supported by AI** - The code has no guarantees about using the best practices for Lua and SM Themes.

**You are welcome to use this theme, fork it, or extract any code you find useful.** Just don't expect help.

---

## What Is This?

A heavily modified fork of [Horsey's Simply Love](https://github.com/Horsey-/Horseys-Simply-Love) optimized for a 16:9 widescreen dedicab running Project OutFox. The theme has been stripped down, streamlined, and enhanced with features specific to home arcade use.

---

## Features Added / Reimplemented

### Custom Lua Music Wheel
Completely replaced the engine's music wheel with a custom Lua implementation:
- **Proper favorites handling** - Deduplicates favorites when both players favorite the same song
- **Custom pack type icons** - Visual indicators for different song pack types
- **Clean group names** - Automatically removes ordering specific prefix pattern (like "O2000a - Pack Name" → "Pack Name")
- **Reworked sort methods** - Title, Artist, BPM, Length, Difficulty Number, Top Scores, Most Played

### BPM Change Lines
Visual indicators during gameplay showing when BPM changes occur:
- Colored horizontal lines on the notefield at BPM change points
- Profile-saved preference per player
- Works with all scroll speed modes (X, C, M, A)

---

## Features Removed (Simplification)

This fork removes features I don't use to keep things simple and reduce bugs:

### Game Modes
- **Casual Mode** - Removed entirely
- **FA+ Mode** - Removed from selection (ITG mode only)
- **Course/Marathon Mode** - Removed completely
- **Practice Mode** - Removed

### Online Services
- **GrooveStats integration** - Removed (leaderboards, score submission, QR codes)
- **ITL (In The Groove League)** - Removed
- **SRPG (Story RPG) mode** - Removed
- **OutFox Online features** - Removed

### Display Support
- **4:3 aspect ratio** - Removed (16:9 widescreen only)
- **CRT support** - Not tested, likely broken

### Languages
- Kept only **English** and **Brazilian Portuguese**
- Removed: German, Spanish, French, Japanese, Italian, and others

### Other Removals
- Genre sort (most packs don't supply correct genre data)
- Tournament mode
- Various unused graphics and sounds
- Score vocalization

---

## Bug Fixes Included

Many fixes from upstream and new fixes for this fork:

- Fixed Mini mod not always applying correctly
- Fixed wrong highscore display on favorites wheel
- Fixed duplicate favorites when both players favorite same song
- Fixed profile switching softlocks
- Fixed dynamic second player join
- Many more small fixes throughout

---

## Inherited from Upstream

This theme is built on top of excellent work from others:

### From [Horsey's Simply Love](https://github.com/Horsey-/Horseys-Simply-Love)
- Z-Mod features merged
- Widescreen (SSMWide) layout
- Many quality-of-life improvements

### From [Simply Love](https://github.com/Simply-Love/Simply-Love-SM5) (original, now does not support Outfox anymore)
- Core theme architecture
- ITG timing and scoring
- Measure counter and density graphs
- Step statistics and pattern analysis
- Error bar and offset tracking
- Pacemaker and target score features
- Custom judgment graphics support
- Profile avatar system
- And much more

---

## Requirements

- **Project OutFox 0.4.18 LTS or newer**
- **16:9 widescreen display** (4:3 not supported)

### Links
- [Project OutFox](https://projectoutfox.com)
- [OutFox Discord](https://discord.gg/fXSX2TaRr5)

---

## Credits

- **Simply Love Team** - Original theme (dguzek, dbk2, quietly-turning)
- **Horsey** - Horsey's Simply Love fork with Z-Mod
- **Silverdrone (rtrind)** - This fork

See upstream repositories for full credits and acknowledgments.
