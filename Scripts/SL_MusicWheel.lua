-- SL-MusicWheel.lua
-- Custom Lua wheel implementation to replace engine wheel
-- Phase 1: Foundation - Basic data layer and state management

-- ============================================================================
-- Global WheelState Table
-- ============================================================================

if not SL then SL = {} end

-- Only initialize if not already present (preserve state across reloads)
if not SL.MusicWheel then
	SL.MusicWheel = {
		-- Current wheel state
		State = {
			items = {},                    -- Flat list of wheel items (songs + groups)
			focus_index = 1,               -- Current focus position in items array
			sort_order = "SortOrder_Group", -- Current sort order
			open_groups = {},              -- Table of open group names {["Group Name"] = true}
			
			-- Last selected song/steps (persists when on group headers)
			last_song = nil,               -- Last selected song (for grade display)
			last_steps = {},               -- Last selected steps per player {[player] = steps}
			
			-- Caching
			highscore_cache = {},          -- Cached highscores with context
			favorites_cache = {},          -- Deduplicated favorites
			songs_cache = {},              -- Cached songs per style {[steps_type] = songs}
			groups_cache = {},             -- Cached groups per style {[steps_type] = {[group] = songs}}
			cache_steps_type = nil,        -- Steps type the cache was built for
			
			-- Performance
			last_rebuild_time = 0,         -- Timestamp of last rebuild
			preload_queue = {},            -- Items queued for preloading
		},
		
		-- Configuration
		Config = {
			num_visible_items = 11,        -- 9 visible + 1 above + 1 below
			preload_buffer = 10,           -- Number of items to preload ahead
			batch_size = 20,               -- Items to load per batch
		}
	}
end

-- Cache context about the currently focused song so we can restore special
-- sections (like <Favorites>) after returning from gameplay.
function SL.MusicWheel.RememberSelectionContext()
	local state = SL.MusicWheel.State
	if not state or not state.items or #state.items == 0 then return end

	local focused_item = state.items[state.focus_index]
	if not focused_item or focused_item.type ~= "song" or not focused_item.song then
		state.last_selection_context = nil
		return
	end

	local song_dir = focused_item.song:GetSongDir()
	state.last_selection_context = {
		sort_order = state.sort_order,
		song_dir = song_dir,
		is_favorites_song = (focused_item.group == "<Favorites>")
	}
end

-- Determine whether we should force the wheel to reopen the <Favorites> section
-- for the provided song (used when returning from gameplay).
function SL.MusicWheel.ShouldReopenFavorites(target_song)
	if not target_song then return false end
	local song_dir = target_song:GetSongDir()
	if not song_dir then return false end

	local state = SL.MusicWheel.State
	local ctx = state and state.last_selection_context
	if ctx and ctx.sort_order == "SortOrder_Group" and ctx.is_favorites_song and ctx.song_dir == song_dir then
		return true
	end

	-- Fall back to session memory populated when we entered gameplay.
	if SL.Global and SL.Global.LastPlayed then
		for _, data in pairs(SL.Global.LastPlayed) do
			if data and data.song and data.is_favorites_song then
				local data_song_dir = data.song:GetSongDir()
				if data_song_dir == song_dir then
					return true
				end
			end
		end
	end

	return false
end

-- ============================================================================
-- Helper Functions
-- ============================================================================

-- Safe song title accessor - returns empty string if song is nil
local function GetSongTitle(song)
	if not song then return "" end
	local success, result = pcall(function() return song:GetDisplayMainTitle() end)
	if success and result then return result end
	return ""
end

-- Safe song directory accessor
local function GetSongDir(song)
	if not song then return "" end
	local success, result = pcall(function() return song:GetSongDir() end)
	if success and result then return result end
	return ""
end

-- Safe song group accessor
local function GetSongGroup(song)
	if not song then return "" end
	local success, result = pcall(function() return song:GetGroupName() end)
	if success and result then return result end
	return ""
end

-- Build the list of length ranges used for Length sort
-- Returns a table of {min, max, label} entries
-- This is the SINGLE SOURCE OF TRUTH for length classification
local function GetLengthRanges()
	local ranges = {}
	
	-- <3 minutes: groups of 30 seconds (0:00-0:30, 0:31-1:00, etc.)
	-- Start at 0 to catch very short songs
	for i = 0, 150, 30 do
		local min_sec = i
		local max_sec = i + 29.999  -- Use 29.999 to avoid boundary issues
		-- Label shows human-readable range
		local label_min = i == 0 and 1 or i + 1  -- Display as "0:01" not "0:00"
		local label_max = i + 30
		local label = string.format("%d:%02d-%d:%02d", 
			math.floor(label_min / 60), label_min % 60,
			math.floor(label_max / 60), label_max % 60)
		table.insert(ranges, {min = min_sec, max = max_sec, label = label})
	end
	
	-- 3-10 minutes: groups of 1 minute (3:01-4:00, 4:01-5:00, etc.)
	for i = 180, 540, 60 do
		local min_sec = i
		local max_sec = i + 59.999
		local label_min = i + 1
		local label_max = i + 60
		local label = string.format("%d:%02d-%d:%02d", 
			math.floor(label_min / 60), label_min % 60,
			math.floor(label_max / 60), label_max % 60)
		table.insert(ranges, {min = min_sec, max = max_sec, label = label})
	end
	
	-- 10-20 minutes: groups of 5 minutes
	for i = 600, 1140, 300 do
		local min_sec = i
		local max_sec = i + 299.999
		local label_min = i + 1
		local label_max = i + 300
		local label = string.format("%d:%02d-%d:%02d", 
			math.floor(label_min / 60), label_min % 60,
			math.floor(label_max / 60), label_max % 60)
		table.insert(ranges, {min = min_sec, max = max_sec, label = label})
	end
	
	-- 20+ minutes
	table.insert(ranges, {min = 1200, max = math.huge, label = "20:01+"})
	
	return ranges
end

-- Get the length range label for a given song length in seconds
-- Uses the same ranges as GetLengthRanges() for consistency
local function GetLengthRangeLabel(length)
	if not length then return "0:01-0:30" end
	
	local ranges = GetLengthRanges()
	for _, range in ipairs(ranges) do
		if length >= range.min and length <= range.max then
			return range.label
		end
	end
	
	-- Fallback for songs shorter than 1 second
	return "0:01-0:30"
end

-- Check if a song has valid steps for current game mode
local function HasValidSteps(song)
	if not song then return false end
	
	local success, steps = pcall(function() return song:GetAllSteps() end)
	if not success or not steps or #steps == 0 then return false end
	
	-- Check if at least one step is valid for current players
	for _, step in ipairs(steps) do
		if step then
			local meter_ok, meter = pcall(function() return step:GetMeter() end)
			if meter_ok and meter and meter > 0 then
				return true
			end
		end
	end
	
	return false
end

-- Filter songs to only include those with valid steps
local function FilterSongs(songs)
	if not songs then return {} end
	
	local filtered = {}
	
	for _, song in ipairs(songs) do
		if song and HasValidSteps(song) then
			table.insert(filtered, song)
		end
	end
	
	return filtered
end

-- Get all songs from SONGMAN (with error handling)
local function GetAllSongs()
	local success, all_songs = pcall(function() return SONGMAN:GetAllSongs() end)
	if not success or not all_songs then
		if SL_Debug then SL_Debug.LogError("GetAllSongs", "Failed to get songs from SONGMAN") end
		return {}
	end
	return FilterSongs(all_songs)
end

-- Get songs in a specific group (with error handling)
local function GetSongsInGroup(group_name)
	if not group_name or group_name == "" then return {} end
	
	local success, songs = pcall(function() return SONGMAN:GetSongsInGroup(group_name) end)
	if not success or not songs then
		if SL_Debug then SL_Debug.LogError("GetSongsInGroup", "Failed to get songs for group: " .. tostring(group_name)) end
		return {}
	end
	return FilterSongs(songs)
end

-- Get all group names (with error handling)
local function GetAllGroups()
	local success, groups = pcall(function() return SONGMAN:GetSongGroupNames() end)
	if not success or not groups then
		if SL_Debug then SL_Debug.LogError("GetAllGroups", "Failed to get group names") end
		return {}
	end
	return groups
end

-- Get all groups sorted alphabetically (matches wheel display order)
local function GetAllGroupsSorted()
	local groups = GetAllGroups()
	table.sort(groups, function(a, b)
		return a:lower() < b:lower()
	end)
	return groups
end

-- Get numeric value for a difficulty (for comparison)
-- Handles both enum values and string keys
local function GetDifficultyValue(difficulty)
	if not difficulty then return 3 end  -- Default to Medium
	
	-- Map of difficulty values (built lazily to avoid issues with enum loading order)
	local order = {
		[Difficulty_Beginner] = 1,
		[Difficulty_Easy] = 2,
		[Difficulty_Medium] = 3,
		[Difficulty_Hard] = 4,
		[Difficulty_Challenge] = 5,
		[Difficulty_Edit] = 6,
		-- String versions for profile file compatibility
		["Difficulty_Beginner"] = 1,
		["Difficulty_Easy"] = 2,
		["Difficulty_Medium"] = 3,
		["Difficulty_Hard"] = 4,
		["Difficulty_Challenge"] = 5,
		["Difficulty_Edit"] = 6,
	}
	
	return order[difficulty] or 3
end

-- Find the first song item in a list of wheel items
-- Returns: song, index or nil, nil if not found
local function FindFirstSongInItems(items)
	if not items then return nil, nil end
	for i, item in ipairs(items) do
		if item.type == "song" then
			return item.song, i
		end
	end
	return nil, nil
end

-- Find the first group header in a list of wheel items
-- Returns: group_name, index or nil, nil if not found
local function FindFirstGroupHeaderInItems(items)
	if not items then return nil, nil end
	for i, item in ipairs(items) do
		if item.type == "group_header" and item.group_name then
			return item.group_name, i
		end
	end
	return nil, nil
end

-- Find steps matching a preferred difficulty from a list of compatible steps
-- Returns the best matching steps, or first available if no match
-- @param compatible_steps: array of Steps objects
-- @param preferred_difficulty: Difficulty enum or string
-- @return Steps object or nil
local function FindStepsByPreferredDifficulty(compatible_steps, preferred_difficulty)
	if not compatible_steps or #compatible_steps == 0 then return nil end
	
	-- If no preference, return first available
	if not preferred_difficulty then
		return compatible_steps[1]
	end
	
	-- Convert string difficulty to enum if needed
	local diff_to_match = preferred_difficulty
	if type(preferred_difficulty) == "string" then
		diff_to_match = _G[preferred_difficulty] or preferred_difficulty
	end
	
	-- Try to find exact match
	for _, steps in ipairs(compatible_steps) do
		if steps:GetDifficulty() == diff_to_match then
			return steps
		end
	end
	
	-- No exact match - find closest
	local target_value = GetDifficultyValue(diff_to_match)
	local best_steps = nil
	local best_distance = 999
	
	for _, steps in ipairs(compatible_steps) do
		local steps_value = GetDifficultyValue(steps:GetDifficulty())
		local distance = math.abs(steps_value - target_value)
		if distance < best_distance then
			best_distance = distance
			best_steps = steps
		end
	end
	
	return best_steps or compatible_steps[1]
end

-- Get player's preferred difficulty from various sources
-- Priority: 1. Provided difficulties table, 2. Engine preference
-- @param pn: PlayerNumber
-- @param difficulties_table: optional table {[pn] = difficulty}
-- @return Difficulty enum or nil
local function GetPlayerPreferredDifficulty(pn, difficulties_table)
	-- Check provided difficulties table first
	if difficulties_table and difficulties_table[pn] then
		return difficulties_table[pn]
	end
	
	-- Fallback to engine's preferred difficulty
	if PROFILEMAN:IsPersistentProfile(pn) then
		return GAMESTATE:GetPreferredDifficulty(pn)
	end
	
	return nil
end

-- ============================================================================
-- Favorites Management
-- ============================================================================

-- Build deduplicated favorites section
-- Returns: array of song items with favorites metadata
function SL.MusicWheel.BuildFavoritesSection()
	local timer_start = SL_Debug and SL_Debug.StartTimer() or nil
	
	local favorites_set = {}  -- Use as set for deduplication (stores song dirs)
	local favorites_list = {}
	
	-- Collect favorites from all enabled players
	for pn in ivalues(GAMESTATE:GetEnabledPlayers()) do
		local profile = PROFILEMAN:GetProfile(pn)
		if profile then
			-- GetFavorites() returns a table of song paths (strings)
			local fav_paths = profile:GetFavorites()
						
		for _, path in ipairs(fav_paths) do
                -- Normalize path separators
                path = path:gsub("\\", "/")
                
				-- Path format: /Songs/GroupName/SongName/
				-- Extract group and song directory names
				local group_name, song_dir = path:match("/Songs/([^/]+)/([^/]+)/?")
				
                if not group_name then
                    -- Try matching without leading slash
                    group_name, song_dir = path:match("Songs/([^/]+)/([^/]+)/?")
                end

				if group_name and song_dir then
					-- Get all songs in this group
					local group_songs = GetSongsInGroup(group_name)
					
					-- Find the song by matching directory name (case-insensitive, plain text)
					local song = nil
                    local search_dir = song_dir:lower()
					for _, s in ipairs(group_songs) do
                        local s_dir = s:GetSongDir():lower()
						if s_dir:find(search_dir, 1, true) then
							song = s
							break
						end
					end
										
					if song then
						local song_dir_path = song:GetSongDir()
						if not favorites_set[song_dir_path] then
							-- First time seeing this song
							favorites_set[song_dir_path] = true
							table.insert(favorites_list, {
								type = "song",
								song = song,
								group = "<Favorites>",
								is_favorite = true,
								favorited_by = {pn}
							})
						else
							-- Song already in list, just add this player to favorited_by
							for _, item in ipairs(favorites_list) do
								if item.song:GetSongDir() == song_dir_path then
									-- Check if player is already in favorited_by (avoid duplicates there too)
									local already_added = false
									for _, existing_pn in ipairs(item.favorited_by) do
										if existing_pn == pn then
											already_added = true
											break
										end
									end
									if not already_added then
										table.insert(item.favorited_by, pn)
									end
									break
								end
							end
						end
					end
				end
			end
		end
	end

	-- Sort favorites alphabetically
	table.sort(favorites_list, function(a, b)
		return a.song:GetDisplayMainTitle():lower() < b.song:GetDisplayMainTitle():lower()
	end)

	-- Log performance
	if SL_Debug and timer_start then
		SL_Debug.EndTimer(timer_start, "BuildFavoritesSection (" .. #favorites_list .. " songs)", 20)
	end

	return favorites_list
end

-- Update state metadata for favorites changes without rebuilding the full wheel.
-- Returns a table describing which indices changed so the visuals can be refreshed.
-- If needs_rebuild is true, the caller should rebuild the entire wheel.
-- rebuild_type: "favorites_added" (0->1+) or "favorites_removed" (1+->0)
function SL.MusicWheel.UpdateFavoritesMetadata()
	local state = SL.MusicWheel.State
	if not state or not state.items or #state.items == 0 then return nil end

	local result = {
		focused_item_index = nil,
		favorites_header_index = nil,
		favorites_count = nil,
		needs_rebuild = false,  -- True when <Favorites> section needs to appear/disappear
		rebuild_type = nil,     -- "favorites_added" or "favorites_removed"
	}

	-- Update focused song metadata so heart icons and other per-item data stay in sync.
	local focused_item = state.items[state.focus_index]
	if focused_item and focused_item.type == "song" and focused_item.song then
		local favorited_by = {}
		for pn in ivalues(GAMESTATE:GetEnabledPlayers()) do
			local profile = PROFILEMAN:GetProfile(pn)
			if profile and profile:SongIsFavorite(focused_item.song) then
				table.insert(favorited_by, pn)
			end
		end
		focused_item.is_favorite = (#favorited_by > 0)
		focused_item.favorited_by = favorited_by
		result.focused_item_index = state.focus_index
	end

	-- When using Group sort, keep the <Favorites> header count in sync.
	if state.sort_order == "SortOrder_Group" then
		local favorites = SL.MusicWheel.BuildFavoritesSection()
		local new_count = #favorites
		state.favorites_cache = favorites
		result.favorites_count = new_count

		-- Check if <Favorites> header currently exists and find its position
		local header_exists = false
		local header_index = nil
		for index, item in ipairs(state.items) do
			if item.type == "group_header" and item.group_name == "<Favorites>" then
				header_exists = true
				header_index = index
				item.song_count = new_count
				result.favorites_header_index = index
				break
			end
		end

		-- Check if we're currently inside the <Favorites> section
		-- (focused on header or on a song within the favorites group)
		local inside_favorites = false
		if focused_item then
			if focused_item.type == "group_header" and focused_item.group_name == "<Favorites>" then
				inside_favorites = true
			elseif focused_item.type == "song" and focused_item.group == "<Favorites>" then
				inside_favorites = true
			end
		end

		-- Detect transitions that require a full rebuild:
		-- 1. No header exists but we now have favorites (0 -> 1+)
		if not header_exists and new_count > 0 then
			result.needs_rebuild = true
			result.rebuild_type = "favorites_added"
		-- 2. Header exists but we now have 0 favorites (1+ -> 0)
		--    BUT: Don't remove if we're currently inside the favorites section
		elseif header_exists and new_count == 0 and not inside_favorites then
			result.needs_rebuild = true
			result.rebuild_type = "favorites_removed"
		end
	end

	if not result.focused_item_index and not result.favorites_header_index and not result.needs_rebuild then
		return nil
	end

	return result
end

-- ============================================================================
-- Wheel Data Building
-- ============================================================================

-- Helper function: Check if a song has charts for the current style
local function HasChartsForCurrentStyle(song)
	local steps_type = GAMESTATE:GetCurrentStyle():GetStepsType()
	local steps = song:GetStepsByStepsType(steps_type)
	return steps and #steps > 0
end

-- Filter a list of songs to only include those with charts for current style
local function FilterSongsForCurrentStyle(all_songs)
	local songs = {}
	for _, song in ipairs(all_songs) do
		if HasChartsForCurrentStyle(song) then
			table.insert(songs, song)
		end
	end
	return songs
end

-- Get all songs filtered for current style (with caching)
local function GetAllSongsForCurrentStyle()
	local state = SL.MusicWheel.State
	local current_steps_type = GAMESTATE:GetCurrentStyle():GetStepsType()
	
	-- Invalidate cache if style changed
	if state.cache_steps_type ~= current_steps_type then
		state.songs_cache = {}
		state.groups_cache = {}
		state.cache_steps_type = current_steps_type
	end
	
	-- Return cached if available
	if state.songs_cache.all then
		return state.songs_cache.all
	end
	
	-- Build and cache
	local songs = FilterSongsForCurrentStyle(GetAllSongs())
	state.songs_cache.all = songs
	return songs
end

-- Get songs in a group filtered for current style (with caching)
local function GetSongsInGroupForCurrentStyle(group_name)
	local state = SL.MusicWheel.State
	local current_steps_type = GAMESTATE:GetCurrentStyle():GetStepsType()
	
	-- Invalidate cache if style changed
	if state.cache_steps_type ~= current_steps_type then
		state.songs_cache = {}
		state.groups_cache = {}
		state.cache_steps_type = current_steps_type
	end
	
	-- Return cached if available
	if state.groups_cache[group_name] then
		return state.groups_cache[group_name]
	end
	
	-- Build and cache
	local all_songs = GetSongsInGroup(group_name)
	local songs = {}
	for _, song in ipairs(all_songs) do
		if HasChartsForCurrentStyle(song) then
			table.insert(songs, song)
		end
	end
	state.groups_cache[group_name] = songs
	return songs
end

-- Clear song cache (call when songs are added/removed)
function SL.MusicWheel.ClearSongCache()
	local state = SL.MusicWheel.State
	state.songs_cache = {}
	state.groups_cache = {}
	state.cache_steps_type = nil
end

-- ============================================================================
-- Item Creation Helpers (reduce code duplication)
-- ============================================================================

-- Create a song item for the wheel
-- @param song: Song object
-- @param group: Group name string
-- @param opts: Optional table with {is_favorite, favorited_by, steps}
local function CreateSongItem(song, group, opts)
	opts = opts or {}
	return {
		type = "song",
		song = song,
		group = group,
		is_favorite = opts.is_favorite or false,
		favorited_by = opts.favorited_by or {},
		steps = opts.steps or nil,  -- Used by Difficulty sort
	}
end

-- Create a group header item for the wheel
-- @param group_name: Display name for the group
-- @param song_count: Number of songs in the group
-- @param index: Optional group index (default nil)
local function CreateGroupHeader(group_name, song_count, index)
	local is_open = SL.MusicWheel.State.open_groups[group_name] or false
	return {
		type = "group_header",
		group_name = group_name,
		song_count = song_count,
		is_open = is_open,
		index = index or nil,
	}
end

-- Add songs from a list to items array
-- @param items: Target items array
-- @param songs: Array of song objects
-- @param group: Group name for all songs
-- @param opts: Optional table passed to CreateSongItem
local function AddSongsToItems(items, songs, group, opts)
	for _, song in ipairs(songs) do
		table.insert(items, CreateSongItem(song, group, opts))
	end
end

-- Build flat list of wheel items for Group sort
-- Phase 2: Supports open/close groups
function SL.MusicWheel.BuildWheelData_Group()
	local items = {}
	
	-- 1. Add Favorites Group at the top
	local favorites = SL.MusicWheel.BuildFavoritesSection()
	if #favorites > 0 then
		table.insert(items, CreateGroupHeader("<Favorites>", #favorites, 0))
		
		-- Add favorite songs if group is open
		if SL.MusicWheel.State.open_groups["<Favorites>"] then
			for _, item in ipairs(favorites) do
				table.insert(items, item)
			end
		end
	end
	
	-- 2. Add Normal Groups (sorted alphabetically)
	local groups = GetAllGroupsSorted()
	local group_index_counter = 0
	
	-- Add each group as a header, and songs if open
	for _, group_name in ipairs(groups) do
		-- Use cached filtered songs
		local songs = GetSongsInGroupForCurrentStyle(group_name)
		
		-- Only add groups that have compatible songs
		if #songs > 0 then
			group_index_counter = group_index_counter + 1
			table.insert(items, CreateGroupHeader(group_name, #songs, group_index_counter))
			
			-- If group is open, add all songs in the group
			if SL.MusicWheel.State.open_groups[group_name] then
				-- Sort songs alphabetically by title, with symbols at the end
				table.sort(songs, function(a, b)
					local text_a = a:GetDisplayMainTitle():lower()
					local text_b = b:GetDisplayMainTitle():lower()
					
					local char_a = text_a:sub(1, 1):upper()
					local char_b = text_b:sub(1, 1):upper()
					
					local is_letter_a = char_a:match("[A-Z]")
					local is_letter_b = char_b:match("[A-Z]")
					
					-- If both are letters or both are non-letters, sort normally
					if (is_letter_a and is_letter_b) or (not is_letter_a and not is_letter_b) then
						return text_a < text_b
					end
					
					-- If one is a letter and the other isn't, put the letter first (non-letter at end)
					return is_letter_a
				end)
				AddSongsToItems(items, songs, group_name)
			end
		end
	end
	
	return items
end

-- Helper function: Sort songs alphabetically with non-letters forced to the end
-- field_getter: function that takes a song and returns the string to sort by
local function SortSongsAlphabetically(songs, field_getter)
	table.sort(songs, function(a, b)
		local text_a = field_getter(a):lower()
		local text_b = field_getter(b):lower()
		
		local char_a = text_a:sub(1, 1):upper()
		local char_b = text_b:sub(1, 1):upper()
		
		local is_letter_a = char_a:match("[A-Z]")
		local is_letter_b = char_b:match("[A-Z]")
		
		-- If both are letters or both are non-letters, sort normally
		if (is_letter_a and is_letter_b) or (not is_letter_a and not is_letter_b) then
			return text_a < text_b
		end
		
		-- If one is a letter and the other isn't, put the letter first (non-letter at end)
		return is_letter_a
	end)
end

-- Build list of wheel items for Title sort (alphabetical with letter headers)
function SL.MusicWheel.BuildWheelData_Title()
	local items = {}
	local songs = GetAllSongsForCurrentStyle()
	
	-- Sort songs alphabetically by title, but force all non-letters to the top
	SortSongsAlphabetically(songs, function(song) return song:GetDisplayMainTitle() end)
	
	-- Group songs by first letter
	local current_letter = nil
	local letter_index = 0
	
	for _, song in ipairs(songs) do
		local title = song:GetDisplayMainTitle()
		local first_char = title:sub(1, 1):upper()
		
		-- If first character is not a letter, group under "#"
		if not first_char:match("[A-Z]") then
			first_char = "#"
		end
		
		-- Add letter header if we're starting a new letter group
		if first_char ~= current_letter then
			current_letter = first_char
			letter_index = letter_index + 1
			
			-- Count songs in this letter group
			local song_count = 0
			for _, s in ipairs(songs) do
				local s_title = s:GetDisplayMainTitle()
				local s_char = s_title:sub(1, 1):upper()
				if not s_char:match("[A-Z]") then s_char = "#" end
				if s_char == current_letter then
					song_count = song_count + 1
				end
			end
			
			local is_open = SL.MusicWheel.State.open_groups[current_letter] or false
			
			table.insert(items, {
				type = "group_header",
				group_name = current_letter,
				song_count = song_count,
				is_open = is_open,
				group_index = letter_index
			})
			
			-- Only add songs if this letter group is open
			if is_open then
				for _, s in ipairs(songs) do
					local s_title = s:GetDisplayMainTitle()
					local s_char = s_title:sub(1, 1):upper()
					if not s_char:match("[A-Z]") then s_char = "#" end
					
					if s_char == current_letter then
						table.insert(items, {
							type = "song",
							song = s,
							group = current_letter,
							is_favorite = false,
							favorited_by = {}
						})
					end
				end
			end
		end
	end
	
	return items
end

-- Build list of wheel items for Artist sort (alphabetical with letter headers)
function SL.MusicWheel.BuildWheelData_Artist()
	local items = {}
	local songs = GetAllSongsForCurrentStyle()
	
	-- Sort songs alphabetically by artist, but force all non-letters to the top
	SortSongsAlphabetically(songs, function(song) return song:GetDisplayArtist() end)
	
	-- Group songs by first letter of artist
	local current_letter = nil
	local letter_index = 0
	
	for _, song in ipairs(songs) do
		local artist = song:GetDisplayArtist()
		local first_char = artist:sub(1, 1):upper()
		
		-- If first character is not a letter, group under "#"
		if not first_char:match("[A-Z]") then
			first_char = "#"
		end
		
		-- Add letter header if we're starting a new letter group
		if first_char ~= current_letter then
			current_letter = first_char
			letter_index = letter_index + 1
			
			-- Count songs in this letter group
			local song_count = 0
			for _, s in ipairs(songs) do
				local s_artist = s:GetDisplayArtist()
				local s_char = s_artist:sub(1, 1):upper()
				if not s_char:match("[A-Z]") then s_char = "#" end
				if s_char == current_letter then
					song_count = song_count + 1
				end
			end
			
			local is_open = SL.MusicWheel.State.open_groups[current_letter] or false
			
			table.insert(items, {
				type = "group_header",
				group_name = current_letter,
				song_count = song_count,
				is_open = is_open,
				group_index = letter_index
			})
			
			-- Only add songs if this letter group is open
			if is_open then
				for _, s in ipairs(songs) do
					local s_artist = s:GetDisplayArtist()
					local s_char = s_artist:sub(1, 1):upper()
					if not s_char:match("[A-Z]") then s_char = "#" end
					
					if s_char == current_letter then
						table.insert(items, {
							type = "song",
							song = s,
							group = current_letter,
							is_favorite = false,
							favorited_by = {}
						})
					end
				end
			end
		end
	end
	
	return items
end

-- Helper function: Get the most representative BPM for a song
local function GetRepresentativeBPM(song)
	local bpms = song:GetDisplayBpms()
	local max_display_bpm = bpms[1]
	-- Find max display BPM as a safe fallback
	for _, bpm in ipairs(bpms) do
		if bpm > max_display_bpm then max_display_bpm = bpm end
	end
	
	-- If only one BPM, use it
	if #bpms == 1 then return bpms[1] end
	
	-- Try to get timing data
	local timing_data = song:GetTimingData()
	if timing_data then
		-- GetBPMsAndTimes(true) returns a list of {beat, bpm} tables
		local bpm_segments = timing_data:GetBPMsAndTimes(true)
		
		if bpm_segments and #bpm_segments > 0 and type(bpm_segments[1]) == "table" then
			local bpm_durations = {}
			local total_duration = 0
			local max_found_bpm = 0
			local last_beat = song:GetLastBeat()
			
			for i = 1, #bpm_segments do
				local segment = bpm_segments[i]
				local start_beat = segment[1]
				local bpm = segment[2]
				
				if bpm > max_found_bpm then max_found_bpm = bpm end
				
				-- Determine end beat of this segment
				local end_beat
				if i < #bpm_segments then
					end_beat = bpm_segments[i+1][1]
				else
					end_beat = last_beat
				end
				
				-- Calculate duration in seconds
				local start_time = timing_data:GetElapsedTimeFromBeat(start_beat)
				local end_time = timing_data:GetElapsedTimeFromBeat(end_beat)
				local duration = end_time - start_time
				
				if duration > 0 then
					bpm_durations[bpm] = (bpm_durations[bpm] or 0) + duration
					total_duration = total_duration + duration
				end
			end
			
			-- Rule 1: If a BPM is used for >50% of the song, use it
			if total_duration > 0 then
				for bpm, duration in pairs(bpm_durations) do
					if duration > (total_duration * 0.5) then
						return bpm
					end
				end
			end
			
			-- Rule 2: Otherwise, use the highest BPM found
			if max_found_bpm > 0 then
				return max_found_bpm
			end
		end
	end
	
	-- Final Fallback: use the highest display BPM
	return max_display_bpm
end

-- Build list of wheel items for BPM sort (grouped by BPM ranges)
function SL.MusicWheel.BuildWheelData_BPM()
	local items = {}
	local songs = GetAllSongsForCurrentStyle()
	
	-- Define BPM ranges
	local bpm_ranges = {}
	
	-- 1-300 in groups of 20
	for i = 1, 281, 20 do
		table.insert(bpm_ranges, {min = i, max = i + 19, label = i .. "-" .. (i + 19)})
	end
	
	-- 301-1000 in groups of 100
	for i = 301, 901, 100 do
		table.insert(bpm_ranges, {min = i, max = i + 99, label = i .. "-" .. (i + 99)})
	end
	
	-- 1000+
	table.insert(bpm_ranges, {min = 1000, max = math.huge, label = "1000+"})
	
	-- Group songs by BPM range
	local range_index = 0
	for _, range in ipairs(bpm_ranges) do
		local songs_in_range = {}
		
		-- Find all songs in this BPM range
		for _, song in ipairs(songs) do
			local bpm = GetRepresentativeBPM(song)
			
			if bpm >= range.min and bpm <= range.max then
				table.insert(songs_in_range, song)
			end
		end
		
		-- Only add this range if it has songs
		if #songs_in_range > 0 then
			range_index = range_index + 1
			
			-- Sort songs within this range by BPM, then by title
			table.sort(songs_in_range, function(a, b)
				local bpm_a = GetRepresentativeBPM(a)
				local bpm_b = GetRepresentativeBPM(b)
				if bpm_a == bpm_b then
					return a:GetDisplayMainTitle():lower() < b:GetDisplayMainTitle():lower()
				end
				return bpm_a < bpm_b
			end)
			
			local is_open = SL.MusicWheel.State.open_groups[range.label] or false
			
			-- Add range header
			table.insert(items, {
				type = "group_header",
				group_name = range.label,
				song_count = #songs_in_range,
				is_open = is_open,
				group_index = range_index
			})
			
			-- Only add songs if this range is open
			if is_open then
				for _, song in ipairs(songs_in_range) do
					table.insert(items, {
						type = "song",
						song = song,
						group = range.label,
						is_favorite = false,
						favorited_by = {}
					})
				end
			end
		end
	end
	
	return items
end

-- Build list of wheel items for Length sort (grouped by song duration ranges)
function SL.MusicWheel.BuildWheelData_Length()
	local items = {}
	local songs = GetAllSongsForCurrentStyle()
	
	-- Use shared length ranges (single source of truth)
	local length_ranges = GetLengthRanges()
	
	-- Group songs by length range
	local range_index = 0
	for _, range in ipairs(length_ranges) do
		local songs_in_range = {}
		
		-- Find all songs in this length range
		for _, song in ipairs(songs) do
			local length = song:GetLastSecond()
			
			if length >= range.min and length <= range.max then
				table.insert(songs_in_range, song)
			end
		end
		
		-- Only add this range if it has songs
		if #songs_in_range > 0 then
			range_index = range_index + 1
			
			-- Sort songs within this range by length, then by title
			table.sort(songs_in_range, function(a, b)
				local length_a = a:GetLastSecond()
				local length_b = b:GetLastSecond()
				if length_a == length_b then
					return a:GetDisplayMainTitle():lower() < b:GetDisplayMainTitle():lower()
				end
				return length_a < length_b
			end)
			
			local is_open = SL.MusicWheel.State.open_groups[range.label] or false
			
			-- Add range header
			table.insert(items, {
				type = "group_header",
				group_name = range.label,
				song_count = #songs_in_range,
				is_open = is_open,
				group_index = range_index
			})
			
			-- Only add songs if this range is open
			if is_open then
				for _, song in ipairs(songs_in_range) do
					table.insert(items, {
						type = "song",
						song = song,
						group = range.label,
						is_favorite = false,
						favorited_by = {}
					})
				end
			end
		end
	end
	
	return items
end

-- Build list of wheel items for Most Played sort (flat list, no grouping)
-- Combines play counts from all enabled players
function SL.MusicWheel.BuildWheelData_MostPlayed()
	local items = {}
	local songs = GetAllSongsForCurrentStyle()
	
	-- Calculate total play count for each song (sum across all enabled players)
	local song_play_counts = {}
	for _, song in ipairs(songs) do
		local total_plays = 0
		
		-- Sum play counts from all enabled players
		for pn in ivalues(GAMESTATE:GetEnabledPlayers()) do
			local profile = PROFILEMAN:GetProfile(pn)
			if profile then
				total_plays = total_plays + profile:GetSongNumTimesPlayed(song)
			end
		end
		
		song_play_counts[song] = total_plays
	end
	
	-- Sort all songs by play count (descending), then by title
	table.sort(songs, function(a, b)
		local count_a = song_play_counts[a]
		local count_b = song_play_counts[b]
		if count_a == count_b then
			return a:GetDisplayMainTitle():lower() < b:GetDisplayMainTitle():lower()
		end
		return count_a > count_b  -- Descending order (most played first)
	end)
	
	-- Add all songs as flat list
	AddSongsToItems(items, songs, nil)
	
	return items
end

-- Build list of wheel items for Machine Most Played sort (flat list, no grouping)
-- Uses machine profile play counts only
function SL.MusicWheel.BuildWheelData_MachineMostPlayed()
	local items = {}
	local songs = GetAllSongsForCurrentStyle()
	
	-- Calculate machine play count for each song
	local song_play_counts = {}
	local machine_profile = PROFILEMAN:GetMachineProfile()
	
	for _, song in ipairs(songs) do
		local machine_plays = 0
		
		if machine_profile then
			machine_plays = machine_profile:GetSongNumTimesPlayed(song)
		end
		
		song_play_counts[song] = machine_plays
	end
	
	-- Sort all songs by machine play count (descending), then by title
	table.sort(songs, function(a, b)
		local count_a = song_play_counts[a]
		local count_b = song_play_counts[b]
		if count_a == count_b then
			return a:GetDisplayMainTitle():lower() < b:GetDisplayMainTitle():lower()
		end
		return count_a > count_b  -- Descending order (most played first)
	end)
	
	-- Add all songs as flat list
	AddSongsToItems(items, songs, nil)
	
	return items
end

-- Get Peak NPS for a given Steps object using the engine's native method
-- This is much faster than parsing note data manually
-- FIXME: It's still not perfect
local function GetPeakNPS(steps)
	if not steps then return 0 end
	
	-- Use native GetPeakNPS if available (OutFox)
	if steps.GetPeakNPS then
		local nps = steps:GetPeakNPS()
		-- If native GetPeakNPS returns a valid value, use it
		if nps and nps > 0 then return nps end
	end
	
	-- Fallback: Use GetNPSGraph which returns a table of density values
	-- We just need the maximum value from this graph
	if steps.GetNPSGraph then
		local graph = steps:GetNPSGraph()
		if graph and #graph > 0 then
			local max_nps = 0
			for _, val in ipairs(graph) do
				-- Guard against NaN, non-numbers, and invalid values
				if type(val) == "number" and val == val and val > max_nps then
					max_nps = val
				end
			end
			return max_nps
		end
	end
	
	return 0
end

-- Build list of wheel items for Difficulty sort (grouped by numerical meter)
-- Shows ALL charts from ALL songs, grouped by their meter value
-- Sorted by Peak NPS within each group
function SL.MusicWheel.BuildWheelData_Difficulty()
	local items = {}
	local songs = GetAllSongs()
	local steps_type = GAMESTATE:GetCurrentStyle():GetStepsType()
	
	-- Collect all charts with their meter and peak NPS
	local charts_by_meter = {} -- Key = meter value, Value = array of {song, steps, peak_nps}
	
	for _, song in ipairs(songs) do
		local all_steps = song:GetStepsByStepsType(steps_type)
		for _, steps in ipairs(all_steps) do
			local meter = steps:GetMeter()
			
			if not charts_by_meter[meter] then
				charts_by_meter[meter] = {}
			end
			
			-- Calculate and cache Peak NPS for this chart
			local peak_nps = GetPeakNPS(steps)
			
			table.insert(charts_by_meter[meter], {
				song = song,
				steps = steps,
				peak_nps = peak_nps
			})
		end
	end
	
	-- Sort meters numerically
	local sorted_meters = {}
	for meter, _ in pairs(charts_by_meter) do
		table.insert(sorted_meters, meter)
	end
	table.sort(sorted_meters, function(a, b) return a < b end)
	
	-- Build wheel items
	local group_index = 0
	for _, meter in ipairs(sorted_meters) do
		group_index = group_index + 1
		local charts = charts_by_meter[meter]
		
		-- Sort charts by Peak NPS (ascending: Easy -> Hard), then by song title
		table.sort(charts, function(a, b)
			if math.abs(a.peak_nps - b.peak_nps) < 0.01 then
				return a.song:GetDisplayMainTitle():lower() < b.song:GetDisplayMainTitle():lower()
			end
			return a.peak_nps < b.peak_nps
		end)
		
		local group_label = tostring(meter)
		local is_open = SL.MusicWheel.State.open_groups[group_label] or false
		
		-- Add group header
		table.insert(items, {
			type = "group_header",
			group_name = group_label,
			song_count = #charts,
			is_open = is_open,
			group_index = group_index
		})
		
		-- Add charts if group is open
		if is_open then
			for _, chart_data in ipairs(charts) do
				table.insert(items, {
					type = "song",
					song = chart_data.song,
					steps = chart_data.steps, -- Include steps so we can set them when selected
					group = group_label,
					is_favorite = false,
					favorited_by = {},
					peak_nps = chart_data.peak_nps -- Cache for display
				})
			end
		end
	end
	
	return items
end

-- Build list of wheel items for Top Scores sort (grouped by Grade)
-- Considers high scores from all enabled players
-- Uses the highest grade achieved across ALL difficulties for each song
function SL.MusicWheel.BuildWheelData_TopScores()
	local items = {}
	local songs = GetAllSongsForCurrentStyle()
	local steps_type = GAMESTATE:GetCurrentStyle():GetStepsType()
	
	-- Map grades to Simply Love display names and sort order
	-- Groups S+/S/S- into S, etc.
	local grade_map = {
		["Grade_Tier01"] = {label = "★★★★", order = 1},
		["Grade_Tier02"] = {label = "★★★", order = 2},
		["Grade_Tier03"] = {label = "★★", order = 3},
		["Grade_Tier04"] = {label = "★", order = 4},
		["Grade_Tier05"] = {label = "S", order = 5},
		["Grade_Tier06"] = {label = "S", order = 5},
		["Grade_Tier07"] = {label = "S", order = 5},
		["Grade_Tier08"] = {label = "A", order = 6},
		["Grade_Tier09"] = {label = "A", order = 6},
		["Grade_Tier10"] = {label = "A", order = 6},
		["Grade_Tier11"] = {label = "B", order = 7},
		["Grade_Tier12"] = {label = "B", order = 7},
		["Grade_Tier13"] = {label = "B", order = 7},
		["Grade_Tier14"] = {label = "C", order = 8},
		["Grade_Tier15"] = {label = "C", order = 8},
		["Grade_Tier16"] = {label = "C", order = 8},
		["Grade_Tier17"] = {label = "D", order = 9},
		["Grade_Tier18"] = {label = "D", order = 9},
		["Grade_Tier19"] = {label = "D", order = 9},
		["Grade_Tier20"] = {label = "D", order = 9},
		["Grade_Failed"] = {label = "F", order = 10}
	}
	
	local groups = {} -- Key = label, Value = {order=int, songs={}}
	local unplayed_songs = {}
	
	for _, song in ipairs(songs) do
		local best_grade_order = 999
		local best_grade_info = nil
		
		-- Check all enabled players
		for pn in ivalues(GAMESTATE:GetEnabledPlayers()) do
			local profile = PROFILEMAN:GetProfile(pn)
			if profile then
				-- Check scores for current steps type (all difficulties)
				-- We take the BEST grade across all difficulties for this song
				local all_steps = song:GetStepsByStepsType(steps_type)
				for _, steps in ipairs(all_steps) do
					local score_list = profile:GetHighScoreListIfExists(song, steps)
					if score_list then
						local scores = score_list:GetHighScores()
						for _, score in ipairs(scores) do
							local grade = score:GetGrade()
							local info = grade_map[tostring(grade)]
							if info then
								if info.order < best_grade_order then
									best_grade_order = info.order
									best_grade_info = info
								end
							end
						end
					end
				end
			end
		end
		
		if best_grade_info then
			local label = best_grade_info.label
			if not groups[label] then
				groups[label] = {order = best_grade_info.order, songs = {}}
			end
			table.insert(groups[label].songs, song)
		else
			-- No scores found for this song
			table.insert(unplayed_songs, song)
		end
	end
	
	-- Add Unplayed group if needed
	if #unplayed_songs > 0 then
		groups["Unplayed"] = {order = 11, songs = unplayed_songs}
	end
	
	-- Sort groups by order
	local sorted_labels = {}
	for label, data in pairs(groups) do
		table.insert(sorted_labels, {label=label, order=data.order})
	end
	table.sort(sorted_labels, function(a, b) return a.order < b.order end)
	
	-- Build items
	local group_index = 0
	for _, group_info in ipairs(sorted_labels) do
		group_index = group_index + 1
		local label = group_info.label
		local songs_in_group = groups[label].songs
		
		-- Sort songs alphabetically
		table.sort(songs_in_group, function(a, b)
			return a:GetDisplayMainTitle():lower() < b:GetDisplayMainTitle():lower()
		end)
		
		local is_open = SL.MusicWheel.State.open_groups[label] or false
		
		-- Add group header
		table.insert(items, {
			type = "group_header",
			group_name = label,
			song_count = #songs_in_group,
			is_open = is_open,
			group_index = group_index
		})
		
		-- Add songs if group is open
		if is_open then
			for _, song in ipairs(songs_in_group) do
				table.insert(items, {
					type = "song",
					song = song,
					group = label,
					is_favorite = false,
					favorited_by = {}
				})
			end
		end
	end
	return items
end

-- Main entry point: Build wheel data based on current sort order
function SL.MusicWheel.BuildWheelData(sort_order)
	sort_order = sort_order or SL.MusicWheel.State.sort_order
	
	local items = {}
	
	-- Accept both engine enums (SortOrder_*) and SortMenu friendly names (Group, Title, Artist, BPM, Length, MostPlayed, MachineMostPlayed)
	if sort_order == "SortOrder_Group" or sort_order == "Group" then
		items = SL.MusicWheel.BuildWheelData_Group()
		-- Ensure stored state matches the friendly name used by SortMenu if possible, or standard enum
		if sort_order == "Group" then SL.MusicWheel.State.sort_order = "SortOrder_Group" end
		
	elseif sort_order == "SortOrder_Title" or sort_order == "Title" then
		items = SL.MusicWheel.BuildWheelData_Title()
		if sort_order == "Title" then SL.MusicWheel.State.sort_order = "SortOrder_Title" end
		
	elseif sort_order == "SortOrder_Artist" or sort_order == "Artist" then
		items = SL.MusicWheel.BuildWheelData_Artist()
		if sort_order == "Artist" then SL.MusicWheel.State.sort_order = "SortOrder_Artist" end
		
	elseif sort_order == "SortOrder_BPM" or sort_order == "BPM" then
		items = SL.MusicWheel.BuildWheelData_BPM()
		if sort_order == "BPM" then SL.MusicWheel.State.sort_order = "SortOrder_BPM" end
		
	elseif sort_order == "SortOrder_Length" or sort_order == "Length" then
		items = SL.MusicWheel.BuildWheelData_Length()
		if sort_order == "Length" then SL.MusicWheel.State.sort_order = "SortOrder_Length" end
		
	elseif sort_order == "SortOrder_Popularity" or sort_order == "MostPlayed" then
		items = SL.MusicWheel.BuildWheelData_MostPlayed()
		if sort_order == "MostPlayed" then SL.MusicWheel.State.sort_order = "SortOrder_Popularity" end
		
	elseif sort_order == "MachineMostPlayed" then
		items = SL.MusicWheel.BuildWheelData_MachineMostPlayed()
		SL.MusicWheel.State.sort_order = "MachineMostPlayed"
		
	elseif sort_order == "TopScores" then
		items = SL.MusicWheel.BuildWheelData_TopScores()
		SL.MusicWheel.State.sort_order = "TopScores"
		
	elseif sort_order == "SortOrder_ModeMenu" or sort_order == "Difficulty" then
		items = SL.MusicWheel.BuildWheelData_Difficulty()
		if sort_order == "Difficulty" then SL.MusicWheel.State.sort_order = "SortOrder_ModeMenu" end
	
	else
		-- Default to Group sort for unsupported sorts
		items = SL.MusicWheel.BuildWheelData_Group()
	end
	
	return items
end

-- Helper to determine which group a song belongs to in a specific sort order
local function GetGroupForSong(song, sort_order)
	if not song then return nil end
	
	-- Handle friendly names
	if sort_order == "Group" then sort_order = "SortOrder_Group" end
	if sort_order == "Title" then sort_order = "SortOrder_Title" end
	if sort_order == "Artist" then sort_order = "SortOrder_Artist" end
	if sort_order == "BPM" then sort_order = "SortOrder_BPM" end
	if sort_order == "Length" then sort_order = "SortOrder_Length" end
	if sort_order == "MostPlayed" then sort_order = "SortOrder_Popularity" end
	if sort_order == "Difficulty" then sort_order = "SortOrder_ModeMenu" end
	
	if sort_order == "SortOrder_Group" then
		return song:GetGroupName()
		
	elseif sort_order == "SortOrder_Title" then
		local title = song:GetDisplayMainTitle()
		local first_char = title:sub(1, 1):upper()
		if not first_char:match("[A-Z]") then return "#" end
		return first_char
		
	elseif sort_order == "SortOrder_Artist" then
		local artist = song:GetDisplayArtist()
		local first_char = artist:sub(1, 1):upper()
		if not first_char:match("[A-Z]") then return "#" end
		return first_char
		
	elseif sort_order == "SortOrder_BPM" then
		local bpm = GetRepresentativeBPM(song)
		if bpm >= 1000 then return "1000+" end
		if bpm >= 301 then
			local base = math.floor((bpm - 301) / 100) * 100 + 301
			return base .. "-" .. (base + 99)
		end
		local base = math.floor((bpm - 1) / 20) * 20 + 1
		return base .. "-" .. (base + 19)
		
	elseif sort_order == "SortOrder_Length" then
		-- Use shared function (single source of truth)
		local length = song:GetLastSecond()
		return GetLengthRangeLabel(length)
		
	elseif sort_order == "SortOrder_ModeMenu" then
		-- Difficulty sort
		local steps = GAMESTATE:GetCurrentSteps(PLAYER_1)
		if not steps then return nil end
		return tostring(steps:GetMeter())
		
	elseif sort_order == "TopScores" then
		-- Duplicate logic from BuildWheelData_TopScores
		local steps_type = GAMESTATE:GetCurrentStyle():GetStepsType()
		local grade_map = {
			["Grade_Tier01"] = {label = "★★★★", order = 1},
			["Grade_Tier02"] = {label = "★★★", order = 2},
			["Grade_Tier03"] = {label = "★★", order = 3},
			["Grade_Tier04"] = {label = "★", order = 4},
			["Grade_Tier05"] = {label = "S", order = 5},
			["Grade_Tier06"] = {label = "S", order = 5},
			["Grade_Tier07"] = {label = "S", order = 5},
			["Grade_Tier08"] = {label = "A", order = 6},
			["Grade_Tier09"] = {label = "A", order = 6},
			["Grade_Tier10"] = {label = "A", order = 6},
			["Grade_Tier11"] = {label = "B", order = 7},
			["Grade_Tier12"] = {label = "B", order = 7},
			["Grade_Tier13"] = {label = "B", order = 7},
			["Grade_Tier14"] = {label = "C", order = 8},
			["Grade_Tier15"] = {label = "C", order = 8},
			["Grade_Tier16"] = {label = "C", order = 8},
			["Grade_Tier17"] = {label = "D", order = 9},
			["Grade_Tier18"] = {label = "D", order = 9},
			["Grade_Tier19"] = {label = "D", order = 9},
			["Grade_Tier20"] = {label = "D", order = 9},
			["Grade_Failed"] = {label = "F", order = 10}
		}
		
		local best_grade_order = 999
		local best_grade_info = nil
		
		for pn in ivalues(GAMESTATE:GetEnabledPlayers()) do
			local profile = PROFILEMAN:GetProfile(pn)
			if profile then
				local all_steps = song:GetStepsByStepsType(steps_type)
				for _, steps in ipairs(all_steps) do
					local score_list = profile:GetHighScoreListIfExists(song, steps)
					if score_list then
						local scores = score_list:GetHighScores()
						for _, score in ipairs(scores) do
							local grade = score:GetGrade()
							local info = grade_map[tostring(grade)]
							if info and info.order < best_grade_order then
								best_grade_order = info.order
								best_grade_info = info
							end
						end
					end
				end
			end
		end
		
		if best_grade_info then
			return best_grade_info.label
		else
			return "Unplayed"
		end
	end
	
	return nil
end

-- Rebuild wheel data and update state
function SL.MusicWheel.RebuildWheelData(sort_order)
	-- Performance tracking
	local timer_start = SL_Debug and SL_Debug.StartTimer() or nil
	
	sort_order = sort_order or SL.MusicWheel.State.sort_order
	
	if SL_Debug then
		SL_Debug.LogOperation("RebuildWheelData", "sort: " .. tostring(sort_order))
	end
	
	-- Capture current selection before rebuilding
	local target_song = SL.MusicWheel.GetFocusedSong()
	local target_steps = GAMESTATE:GetCurrentSteps(PLAYER_1)
	
	SL.MusicWheel.State.sort_order = sort_order
	
	-- Preserve Favorites group if it was open
	local favorites_was_open = SL.MusicWheel.State.open_groups["<Favorites>"]
	
	-- Reset open groups for the new sort order
	SL.MusicWheel.State.open_groups = {}
	
	-- Restore Favorites if it was open (for returning from gameplay to same section)
	if favorites_was_open then
		SL.MusicWheel.State.open_groups["<Favorites>"] = true
	end
	
	-- If we have a target song, ensure its group is open in the new sort
	if target_song then
		local group_name = GetGroupForSong(target_song, sort_order)
		if group_name then
			SL.MusicWheel.State.open_groups[group_name] = true
		end
	end
	
	SL.MusicWheel.State.items = SL.MusicWheel.BuildWheelData(sort_order)
	SL.MusicWheel.State.last_rebuild_time = GetTimeSinceStart()
	
	-- Handle edge case: empty wheel (no songs available)
	if #SL.MusicWheel.State.items == 0 then
		if SL_Debug then
			SL_Debug.LogError("RebuildWheelData", "Wheel is empty - no songs available for current style/sort")
		end
		-- Add a placeholder item so the wheel doesn't crash
		table.insert(SL.MusicWheel.State.items, {
			type = "placeholder",
			display_text = "No songs available",
			group = "",
		})
	end
	
	-- Try to restore focus to the target song
	local found_index = nil
	
	if target_song then
		local target_dir = target_song:GetSongDir()
		for i, item in ipairs(SL.MusicWheel.State.items) do
			if item.type == "song" and (item.song == target_song or (target_dir and item.song:GetSongDir() == target_dir)) then
				-- For Difficulty sort, also check if steps match (if we have target steps)
				if sort_order == "SortOrder_ModeMenu" or sort_order == "Difficulty" then
					if target_steps and item.steps == target_steps then
						found_index = i
						break
					elseif not found_index then
						-- Partial match (same song, different steps), keep as fallback
						found_index = i
					end
				else
					found_index = i
					break
				end
			end
		end
	end
	
	-- Set focus index (default to 1 if not found)
	SL.MusicWheel.State.focus_index = found_index or 1
	
	-- Broadcast rebuild message
	MESSAGEMAN:Broadcast("MusicWheelRebuilt", {sort_order = sort_order})
	
	-- Log performance
	if SL_Debug and timer_start then
		local item_count = #SL.MusicWheel.State.items
		SL_Debug.EndTimer(timer_start, "RebuildWheelData (" .. item_count .. " items)", 50)
	end
end

-- ============================================================================
-- Group Management
-- ============================================================================

-- Toggle a group open/closed
-- allow_from_song: if true, allows closing group when focused on a song (for MenuUp+MenuDown)
--                  if false, only works when focused on group header (for Start key)
function SL.MusicWheel.ToggleGroup(allow_from_song)
	if allow_from_song == nil then allow_from_song = false end
	
	local state = SL.MusicWheel.State
	local focused_item = state.items[state.focus_index]
	
	if not focused_item then
		return false
	end
	
	local group_name = nil
	
	-- Determine which group to toggle
	if focused_item.type == "group_header" then
		-- Focused on group header - toggle this group
		group_name = focused_item.group_name
	elseif allow_from_song and focused_item.type == "song" and focused_item.group then
		-- Focused on a song - close its parent group (only if allow_from_song is true)
		group_name = focused_item.group
	else
		-- Not on a group or song in a group, or not allowed from song
		return false
	end
	
	-- Toggle the open state
	if state.open_groups[group_name] then
		state.open_groups[group_name] = nil  -- Close group
	else
		-- Close all other groups before opening this one (single group open policy)
		state.open_groups = {}
		state.open_groups[group_name] = true  -- Open group
	end
	
	-- Rebuild wheel data to reflect the change
	state.items = SL.MusicWheel.BuildWheelData(state.sort_order)
	
	-- Always focus on the group header after toggling
	for i, item in ipairs(state.items) do
		if item.type == "group_header" and item.group_name == group_name then
			state.focus_index = i
			break
		end
	end
	
	-- Update GAMESTATE with focused song (if any)
	local focused_song = SL.MusicWheel.GetFocusedSong()
	if focused_song then
		GAMESTATE:SetCurrentSong(focused_song)
	end
	
	-- Broadcast rebuild message
	MESSAGEMAN:Broadcast("MusicWheelRebuilt", {
		sort_order = state.sort_order,
		group_toggled = group_name
	})
	MESSAGEMAN:Broadcast("CurrentSongChanged")
	
	return true
end

-- ============================================================================
-- Wheel Navigation
-- ============================================================================

-- Scroll wheel by offset amount
function SL.MusicWheel.Scroll(offset)
	local state = SL.MusicWheel.State
	
	-- Safety check: ensure we have items to scroll
	if not state or not state.items or #state.items == 0 then
		if SL_Debug then SL_Debug.LogError("Scroll", "Cannot scroll: wheel has no items") end
		return
	end
	
	local new_index = state.focus_index + offset
	
	-- Wrap around (cyclical scrolling)
	if new_index < 1 then
		new_index = #state.items
	elseif new_index > #state.items then
		new_index = 1
	end
	
	state.focus_index = new_index
	
	-- Broadcast scroll message
	MESSAGEMAN:Broadcast("MusicWheelScrolled", {
		direction = offset > 0 and "Down" or "Up",
		focus_index = new_index
	})
end

-- Get currently focused item (with safety checks)
function SL.MusicWheel.GetFocusedItem()
	local state = SL.MusicWheel.State
	if not state or not state.items or #state.items == 0 then
		return nil
	end
	
	-- Ensure focus_index is within bounds
	if state.focus_index < 1 or state.focus_index > #state.items then
		state.focus_index = 1
	end
	
	return state.items[state.focus_index]
end

-- Get currently focused song (if focused item is a song)
function SL.MusicWheel.GetFocusedSong()
	local item = SL.MusicWheel.GetFocusedItem()
	if item and item.type == "song" then
		return item.song
	end
	return nil
end

-- Get currently focused group (if focused item is a group header)
function SL.MusicWheel.GetFocusedGroup()
	local item = SL.MusicWheel.GetFocusedItem()
	if item and item.type == "group_header" then
		return item.group_name
	end
	return nil
end

-- ============================================================================
-- Last Played Song/Difficulty Tracking
-- ============================================================================
-- Custom implementation because engine's GetLastPlayedSong() is unreliable.
-- Priority: Session data first (most recent), then profile file as fallback.

local LAST_PLAYED_FILENAME = "SL-LastPlayed.txt"

-- Load last played data from a player's profile directory
-- Returns: {song = Song, difficulty = string} or nil
function SL.MusicWheel.LoadLastPlayedFromProfile(pn)
	if not PROFILEMAN:IsPersistentProfile(pn) then return nil end
	
	local slot = pn == PLAYER_1 and "ProfileSlot_Player1" or "ProfileSlot_Player2"
	local profile_dir = PROFILEMAN:GetProfileDir(slot)
	if not profile_dir or profile_dir == "" then return nil end
	
	local file_path = profile_dir .. LAST_PLAYED_FILENAME
	if not FILEMAN:DoesFileExist(file_path) then return nil end
	
	-- Read the file (format: song_path\ndifficulty)
	local contents = GetFileContents and GetFileContents(file_path)
	if not contents or #contents < 1 then return nil end
	
	local song_path = contents[1]
	local difficulty = contents[2]  -- May be nil or empty
	
	-- Try to find the song
	local song = SONGMAN:FindSong(song_path)
	if not song then return nil end
	
	return {
		song = song,
		difficulty = difficulty ~= "" and difficulty or nil,
		source = "profile_file"
	}
end

-- Save last played data to a player's profile directory
function SL.MusicWheel.SaveLastPlayedToProfile(pn, song, difficulty)
	if not pn or not song then return end
	if not PROFILEMAN:IsPersistentProfile(pn) then return end
	
	local slot = pn == PLAYER_1 and "ProfileSlot_Player1" or "ProfileSlot_Player2"
	local profile_dir = PROFILEMAN:GetProfileDir(slot)
	if not profile_dir or profile_dir == "" then return end
	
	local file_path = profile_dir .. LAST_PLAYED_FILENAME
	
	-- Get song path (Group/SongDir format)
	local song_path = song:GetSongDir()
	-- Convert to relative path if needed
	if song_path then
		-- Extract just "Group/Song" from full path
		local group = song:GetGroupName()
		local song_dir = song_path:match("([^/\\]+)[/\\]?$") or song_path
		song_path = group .. "/" .. song_dir
	end
	
	-- Convert difficulty enum to string
	local diff_str = difficulty and tostring(difficulty) or ""
	
	-- Write to file (format: song_path\ndifficulty)
	local content = song_path .. "\n" .. diff_str
	
	-- Use RageFileUtil to write the file
	local f = RageFileUtil.CreateRageFile()
	if f then
		if f:Open(file_path, 2) then  -- 2 = write mode
			f:Write(content)
			f:Close()
		end
		f:destroy()
	end
end

-- Save last played song/difficulty to session storage only
-- Called when entering gameplay (so Escape returns to same song)
function SL.MusicWheel.SaveLastPlayedToSession(pn, song, difficulty)
	if not pn or not song then return end
	
	-- Ensure the LastPlayed table exists
	if not SL.Global.LastPlayed then
		SL.Global.LastPlayed = {
			[PLAYER_1] = nil,
			[PLAYER_2] = nil
		}
	end
	
	-- Save to session with timestamp for within-session comparison
	SL.Global.LastPlayed[pn] = {
		song = song,
		difficulty = difficulty,
		timestamp = GetTimeSinceStart()
	}
	
	-- Store whether this song was chosen from <Favorites> so we can reopen that
	-- section after returning from gameplay.
	if SL.MusicWheel and SL.MusicWheel.State then
		local state = SL.MusicWheel.State
		local focused = state.items and state.items[state.focus_index]
		if focused and focused.type == "song" and focused.song == song then
			SL.Global.LastPlayed[pn].is_favorites_song = (focused.group == "<Favorites>")
		else
			local ctx = state.last_selection_context
			if ctx and ctx.song_dir == song:GetSongDir() then
				SL.Global.LastPlayed[pn].is_favorites_song = ctx.is_favorites_song
			end
		end
	end
end

-- Save last played song/difficulty to both session and profile
-- Called after completing a song (on evaluation screen)
function SL.MusicWheel.SaveLastPlayed(pn, song, difficulty)
	if not pn or not song then return end
	
	-- Save to session
	SL.MusicWheel.SaveLastPlayedToSession(pn, song, difficulty)
	
	-- Also save to profile file (if persistent profile)
	SL.MusicWheel.SaveLastPlayedToProfile(pn, song, difficulty)
end

-- Get the best last played song for initialization
-- Priority:
-- 1. Session data (most recent from current session, by timestamp)
-- 2. Profile file data from P1 (fallback when session is empty, e.g., start of game)
-- 3. nil (will use default song list)
-- Returns: {song = Song, difficulties = {[pn] = difficulty}, player = PlayerNumber} or nil
-- The difficulties table contains per-player difficulties when available
function SL.MusicWheel.GetBestLastPlayed()
	local players = GAMESTATE:GetHumanPlayers()
	if #players == 0 then return nil end
	
	-- Collect session data for all players
	local session_data_by_player = {}
	local session_candidates = {}
	
	for _, pn in ipairs(players) do
		local session_data = SL.Global.LastPlayed and SL.Global.LastPlayed[pn]
		if session_data and session_data.song then
			session_data_by_player[pn] = session_data
			table.insert(session_candidates, {
				song = session_data.song,
				difficulty = session_data.difficulty,
				player = pn,
				timestamp = session_data.timestamp or 0,
				source = "session"
			})
		end
	end
	
	-- If we have session data, use the most recent song
	if #session_candidates > 0 then
		table.sort(session_candidates, function(a, b)
			return a.timestamp > b.timestamp
		end)
		
		local best = session_candidates[1]
		
		-- Build per-player difficulties table
		-- Each player gets their own saved difficulty if they played this song
		local difficulties = {}
		for _, pn in ipairs(players) do
			local pn_data = session_data_by_player[pn]
			if pn_data and pn_data.song == best.song then
				-- This player also played the same song, use their difficulty
				difficulties[pn] = pn_data.difficulty
			else
				-- Player didn't play this song, use the best player's difficulty as fallback
				difficulties[pn] = best.difficulty
			end
		end
		
		return {
			song = best.song,
			difficulty = best.difficulty,  -- For backwards compatibility
			difficulties = difficulties,   -- Per-player difficulties
			player = best.player,
			source = "session"
		}
	end
	
	-- No session data - try profile files
	-- P1 takes priority for song selection, but each player gets their own difficulty
	local profile_data_by_player = {}
	local best_song = nil
	local best_player = nil
	
	-- Load profile data for all players
	for _, pn in ipairs({PLAYER_1, PLAYER_2}) do
		local is_playing = false
		for _, p in ipairs(players) do
			if p == pn then is_playing = true break end
		end
		
		if is_playing then
			local profile_data = SL.MusicWheel.LoadLastPlayedFromProfile(pn)
			if profile_data and profile_data.song then
				profile_data_by_player[pn] = profile_data
				-- P1 takes priority for song selection
				if not best_song then
					best_song = profile_data.song
					best_player = pn
				end
			end
		end
	end
	
	if best_song then
		-- Build per-player difficulties
		-- Each player gets their own saved difficulty if available
		local difficulties = {}
		for _, pn in ipairs(players) do
			local pn_data = profile_data_by_player[pn]
			if pn_data then
				difficulties[pn] = pn_data.difficulty
			else
				-- Fallback to the best player's difficulty
				difficulties[pn] = profile_data_by_player[best_player] and profile_data_by_player[best_player].difficulty
			end
		end
		
		return {
			song = best_song,
			difficulty = profile_data_by_player[best_player] and profile_data_by_player[best_player].difficulty,
			difficulties = difficulties,
			player = best_player,
			source = "profile_file"
		}
	end
	
	return nil
end

-- Find a song in the wheel items and return its index
-- Also opens the containing group if needed
-- Returns: index in items array, or nil if not found
function SL.MusicWheel.FindSongIndex(target_song, target_steps)
	if not target_song then return nil end
	
	local state = SL.MusicWheel.State
	
	-- First, check if the song is already visible in current items
	-- If Favorites group is open, prefer finding the song there
	local favorites_open = state.open_groups["<Favorites>"]
	local fallback_index = nil
	
	for i, item in ipairs(state.items) do
		if item.type == "song" and item.song == target_song then
			-- For Difficulty sort, also match steps if provided
			if target_steps and item.steps then
				if item.steps == target_steps then
					return i
				end
				-- Don't set fallback if we're looking for specific steps
				-- (we want exact match or nothing)
			else
				-- If Favorites is open and this is the Favorites version, return it immediately
				if favorites_open and item.group == "<Favorites>" then
					return i
				end
				-- Otherwise, remember this index as a fallback
				if not fallback_index then
					fallback_index = i
				end
			end
		end
	end
	
	-- If we found the song (in any group), return it
	if fallback_index then
		return fallback_index
	end
	
	-- Song not visible - need to find and open its group
	-- Get the song's group name based on current sort order
	local song_group = GetGroupForSong(target_song, state.sort_order)
	if not song_group then
		-- Fallback to pack name if GetGroupForSong fails
		song_group = target_song:GetGroupName()
	end
	
	-- Close all groups and open the target group
	-- But preserve Favorites if it was open
	if not favorites_open then
		state.open_groups = {}
		state.open_groups[song_group] = true
	else
		-- Favorites is open - keep it open and also open the song's group
		state.open_groups[song_group] = true
	end
	
	-- Rebuild wheel data with the new group open
	state.items = SL.MusicWheel.BuildWheelData(state.sort_order)
	
	-- Now find the song in the rebuilt items, preferring Favorites if open
	fallback_index = nil
	for i, item in ipairs(state.items) do
		if item.type == "song" and item.song == target_song then
			-- For Difficulty sort, also match steps if provided
			if target_steps and item.steps then
				if item.steps == target_steps then
					return i
				end
				-- Don't set fallback if we're looking for specific steps
			else
				if favorites_open and item.group == "<Favorites>" then
					return i
				end
				if not fallback_index then
					fallback_index = i
				end
			end
		end
	end
	
	return fallback_index
end

-- ============================================================================
-- Initialization
-- ============================================================================

-- Initialize wheel on screen entry
function SL.MusicWheel.Initialize()
	-- Clear any previously open groups
	SL.MusicWheel.State.open_groups = {}
	
	-- Try to get the best last played song (from profile or session)
	local last_played = SL.MusicWheel.GetBestLastPlayed()
	local target_song = last_played and last_played.song
	local target_difficulty = last_played and last_played.difficulty
	
	-- Store the per-player difficulties for MusicWheel to access
	SL.MusicWheel.State.initial_difficulties = last_played and last_played.difficulties or {}
	
	-- If we have a target song, try to open its group (or Favorites if it came from there)
	local reopen_favorites = SL.MusicWheel.ShouldReopenFavorites(target_song)
	if target_song then
		local song_group = target_song:GetGroupName()
		if reopen_favorites then
			SL.MusicWheel.State.open_groups["<Favorites>"] = true
		else
			SL.MusicWheel.State.open_groups[song_group] = true
		end
	else
		-- Fallback: Open first group that has songs for current style
		local sorted_groups = GetAllGroupsSorted()
		Trace("[MusicWheel] Fallback: checking " .. #sorted_groups .. " groups for songs")
		for _, group_name in ipairs(sorted_groups) do
			local songs = GetSongsInGroupForCurrentStyle(group_name)
			Trace("[MusicWheel] Group '" .. group_name .. "' has " .. #songs .. " songs")
			if #songs > 0 then
				SL.MusicWheel.State.open_groups[group_name] = true
				Trace("[MusicWheel] Opened group: " .. group_name)
				break
			end
		end
	end
	
	-- Log open_groups state
	local open_count = 0
	for k, v in pairs(SL.MusicWheel.State.open_groups) do
		if v then open_count = open_count + 1 end
	end
	Trace("[MusicWheel] Open groups count: " .. open_count)
	
	-- Build initial wheel data (after setting which groups are open)
	-- Use BuildWheelData directly instead of RebuildWheelData to preserve open_groups
	-- Preserve the sort order if it was already set (e.g., returning from gameplay)
	if not SL.MusicWheel.State.sort_order then
		SL.MusicWheel.State.sort_order = "SortOrder_Group"
	end
	SL.MusicWheel.State.items = SL.MusicWheel.BuildWheelData(SL.MusicWheel.State.sort_order)
	SL.MusicWheel.State.last_rebuild_time = GetTimeSinceStart and GetTimeSinceStart() or 0
	
	Trace("[MusicWheel] After rebuild, items count: " .. #SL.MusicWheel.State.items)
	
	-- Try to focus on the target song, or fall back to first song
	local focus_song = nil
	local focus_index = 1
	
	if target_song then
		-- Find the target song in the wheel
		-- For Difficulty sort, also try to match the specific steps
		local target_steps_obj = nil
		if (SL.MusicWheel.State.sort_order == "SortOrder_ModeMenu" or SL.MusicWheel.State.sort_order == "Difficulty") and target_difficulty then
			-- Convert difficulty enum to steps object
			local steps_type = GAMESTATE:GetCurrentStyle():GetStepsType()
			local all_steps = target_song:GetStepsByStepsType(steps_type)
			for _, steps in ipairs(all_steps) do
				if steps:GetDifficulty() == target_difficulty then
					target_steps_obj = steps
					break
				end
			end
		end
		
		local song_index = SL.MusicWheel.FindSongIndex(target_song, target_steps_obj)
		if song_index then
			focus_index = song_index
			focus_song = target_song
		end
	end
	
	-- If no target song found, use first song in wheel
	-- (The fallback logic above ensures at least one group with songs is open)
	if not focus_song then
		focus_song, focus_index = FindFirstSongInItems(SL.MusicWheel.State.items)
		focus_index = focus_index or 1
		Trace("[MusicWheel] FindFirstSongInItems returned: " .. tostring(focus_song and focus_song:GetDisplayMainTitle() or "nil") .. " at index " .. tostring(focus_index))
	end
	
	SL.MusicWheel.State.focus_index = focus_index
	Trace("[MusicWheel] Final focus_index: " .. focus_index .. ", focus_song: " .. tostring(focus_song and focus_song:GetDisplayMainTitle() or "nil"))
	
	-- Set initial song in GAMESTATE
	if focus_song then
		GAMESTATE:SetCurrentSong(focus_song)
		Trace("[MusicWheel] Set GAMESTATE song: " .. focus_song:GetDisplayMainTitle())
		
		-- Set initial steps for all players
		local steps_type = GAMESTATE:GetCurrentStyle():GetStepsType()
		local difficulties_table = last_played and last_played.difficulties
		
		for pn in ivalues(GAMESTATE:GetHumanPlayers()) do
			local player_difficulty = GetPlayerPreferredDifficulty(pn, difficulties_table)
			local compatible_steps = focus_song:GetStepsByStepsType(steps_type)
			local steps_to_set = FindStepsByPreferredDifficulty(compatible_steps, player_difficulty)
			
			if steps_to_set then
				GAMESTATE:SetCurrentSteps(pn, steps_to_set)
			end
		end
		
		MESSAGEMAN:Broadcast("CurrentSongChanged")
		MESSAGEMAN:Broadcast("CurrentStepsP1Changed")
		MESSAGEMAN:Broadcast("CurrentStepsP2Changed")
	end
end

-- ============================================================================
-- Debug Helpers
-- ============================================================================

function SL.MusicWheel.DebugPrintState()
	local state = SL.MusicWheel.State
	SM("=== MusicWheel State ===")
	SM("Sort Order: " .. state.sort_order)
	SM("Focus Index: " .. state.focus_index .. " / " .. #state.items)
	SM("Total Items: " .. #state.items)
	
	local focused = SL.MusicWheel.GetFocusedItem()
	if focused then
		if focused.type == "song" then
			SM("Focused: [SONG] " .. focused.song:GetDisplayMainTitle())
		elseif focused.type == "group_header" then
			SM("Focused: [GROUP] " .. focused.group_name .. " (" .. focused.song_count .. " songs)")
		end
	end
end
