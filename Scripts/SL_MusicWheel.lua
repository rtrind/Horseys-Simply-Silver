-- SL-MusicWheel.lua
-- Custom Lua wheel implementation to replace engine wheel
-- Phase 1: Foundation - Basic data layer and state management

-- ============================================================================
-- Global WheelState Table
-- ============================================================================

if not SL then SL = {} end

SL.MusicWheel = {
	-- Current wheel state
	State = {
		items = {},                    -- Flat list of wheel items (songs + groups)
		focus_index = 1,               -- Current focus position in items array
		sort_order = "SortOrder_Group", -- Current sort order
		open_groups = {},              -- Table of open group names {["Group Name"] = true}
		
		-- Caching
		highscore_cache = {},          -- Cached highscores with context
		favorites_cache = {},          -- Deduplicated favorites
		
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

-- ============================================================================
-- Helper Functions
-- ============================================================================

-- Check if a song has valid steps for current game mode
local function HasValidSteps(song)
	if not song then return false end
	
	local steps = song:GetAllSteps()
	if not steps or #steps == 0 then return false end
	
	-- Check if at least one step is valid for current players
	for _, step in ipairs(steps) do
		if step and step:GetMeter() > 0 then
			return true
		end
	end
	
	return false
end

-- Filter songs to only include those with valid steps
local function FilterSongs(songs)
	local filtered = {}
	
	for _, song in ipairs(songs) do
		if HasValidSteps(song) then
			table.insert(filtered, song)
		end
	end
	
	return filtered
end

-- Get all songs from SONGMAN
local function GetAllSongs()
	local all_songs = SONGMAN:GetAllSongs()
	return FilterSongs(all_songs)
end

-- Get songs in a specific group
local function GetSongsInGroup(group_name)
	local songs = SONGMAN:GetSongsInGroup(group_name)
	return FilterSongs(songs)
end

-- Get all group names
local function GetAllGroups()
	return SONGMAN:GetSongGroupNames()
end

-- ============================================================================
-- Favorites Management
-- ============================================================================

-- Build deduplicated favorites section
-- Returns: array of song items with favorites metadata
function SL.MusicWheel.BuildFavoritesSection()
	local favorites_set = {}  -- Use as set for deduplication
	local favorites_list = {}
	
	-- Collect favorites from all enabled players
	for pn in ivalues(GAMESTATE:GetEnabledPlayers()) do
		local player_favorites = SL[ToEnumShortString(pn)].Favorites or {}
		
		for _, song in ipairs(player_favorites) do
			if song then
				if not favorites_set[song] then
					-- First time seeing this song
					favorites_set[song] = true
					table.insert(favorites_list, {
						type = "song",
						song = song,
						group = "<Favorites>",
						is_favorite = true,
						favorited_by = {pn}
					})
				else
					-- Song already in list, add player to favorited_by
					for _, item in ipairs(favorites_list) do
						if item.song == song then
							table.insert(item.favorited_by, pn)
							break
						end
					end
				end
			end
		end
	end
	
	-- Sort favorites alphabetically by title
	table.sort(favorites_list, function(a, b)
		return a.song:GetDisplayMainTitle():lower() < b.song:GetDisplayMainTitle():lower()
	end)
	
	return favorites_list
end

-- ============================================================================
-- Wheel Data Building
-- ============================================================================

-- Build flat list of wheel items for Group sort
-- Phase 2: Supports open/close groups
function SL.MusicWheel.BuildWheelData_Group()
	local items = {}
	local groups = GetAllGroups()
	
	-- Sort groups alphabetically
	table.sort(groups, function(a, b)
		return a:lower() < b:lower()
	end)
	
	local group_index_counter = 0
	
	-- Add each group as a header, and songs if open
	for _, group_name in ipairs(groups) do
		local songs = GetSongsInGroup(group_name)
		
		-- Only add groups that have songs
		if #songs > 0 then
			group_index_counter = group_index_counter + 1
			local is_open = SL.MusicWheel.State.open_groups[group_name] or false
			
			-- Add group header
			table.insert(items, {
				type = "group_header",
				group_name = group_name,
				song_count = #songs,
				is_open = is_open,
				index = group_index_counter
			})
			
			-- If group is open, add all songs in the group
			if is_open then
				-- Sort songs alphabetically by title
				table.sort(songs, function(a, b)
					return a:GetDisplayMainTitle():lower() < b:GetDisplayMainTitle():lower()
				end)
				
				for _, song in ipairs(songs) do
					table.insert(items, {
						type = "song",
						song = song,
						group = group_name,
						is_favorite = false,
						favorited_by = {}
					})
				end
			end
		end
	end
	
	return items
end

-- Helper function: Sort songs alphabetically with non-letters forced to the top
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
		
		-- If one is a letter and the other isn't, put the non-letter first
		return not is_letter_a
	end)
end

-- Build list of wheel items for Title sort (alphabetical with letter headers)
function SL.MusicWheel.BuildWheelData_Title()
	local items = {}
	local songs = GetAllSongs()
	
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
	local songs = GetAllSongs()
	
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
	local songs = GetAllSongs()
	
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
	local songs = GetAllSongs()
	
	-- Define length ranges (in seconds)
	local length_ranges = {}
	
	-- <3 minutes: groups of 30 seconds (0:01-0:30, 0:31-1:00, etc.)
	for i = 1, 151, 30 do
		local min_sec = i
		local max_sec = i + 29
		local label = string.format("%d:%02d-%d:%02d", 
			math.floor(min_sec / 60), min_sec % 60,
			math.floor(max_sec / 60), max_sec % 60)
		table.insert(length_ranges, {min = min_sec, max = max_sec, label = label})
	end
	
	-- 3-10 minutes: groups of 1 minute
	for i = 181, 541, 60 do
		local min_sec = i
		local max_sec = i + 59
		local label = string.format("%d:%02d-%d:%02d", 
			math.floor(min_sec / 60), min_sec % 60,
			math.floor(max_sec / 60), max_sec % 60)
		table.insert(length_ranges, {min = min_sec, max = max_sec, label = label})
	end
	
	-- 10-20 minutes: groups of 5 minutes
	for i = 601, 1141, 300 do
		local min_sec = i
		local max_sec = i + 299
		local label = string.format("%d:%02d-%d:%02d", 
			math.floor(min_sec / 60), min_sec % 60,
			math.floor(max_sec / 60), max_sec % 60)
		table.insert(length_ranges, {min = min_sec, max = max_sec, label = label})
	end
	
	-- 20+ minutes
	table.insert(length_ranges, {min = 1201, max = math.huge, label = "20:01+"})
	
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

-- Main entry point: Build wheel data based on current sort order
function SL.MusicWheel.BuildWheelData(sort_order)
	sort_order = sort_order or SL.MusicWheel.State.sort_order
	
	local items = {}
	
	-- Accept both engine enums (SortOrder_*) and SortMenu friendly names (Group, Title, Artist, BPM, Length)
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
		
	else
		-- Default to Group sort for unsupported sorts
		items = SL.MusicWheel.BuildWheelData_Group()
	end
	
	return items
end

-- Rebuild wheel data and update state
function SL.MusicWheel.RebuildWheelData(sort_order)
	sort_order = sort_order or SL.MusicWheel.State.sort_order
	
	SL.MusicWheel.State.sort_order = sort_order
	SL.MusicWheel.State.items = SL.MusicWheel.BuildWheelData(sort_order)
	SL.MusicWheel.State.last_rebuild_time = GetTimeSinceStart()
	
	-- Reset focus to first item
	SL.MusicWheel.State.focus_index = 1
	
	-- Broadcast rebuild message
	MESSAGEMAN:Broadcast("MusicWheelRebuilt", {sort_order = sort_order})
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

-- Get currently focused item
function SL.MusicWheel.GetFocusedItem()
	local state = SL.MusicWheel.State
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
-- Initialization
-- ============================================================================

-- Initialize wheel on screen entry
function SL.MusicWheel.Initialize()
	-- Clear any previously open groups
	SL.MusicWheel.State.open_groups = {}
	
	-- Open first group by default
	local groups = GetAllGroups()
	if #groups > 0 then
		SL.MusicWheel.State.open_groups[groups[1]] = true
	end
	
	-- Build initial wheel data with first group open
	SL.MusicWheel.RebuildWheelData("SortOrder_Group")
	
	-- Find first song in the wheel and focus on it
	local first_song = nil
	for i, item in ipairs(SL.MusicWheel.State.items) do
		if item.type == "song" then
			first_song = item.song
			SL.MusicWheel.State.focus_index = i  -- Focus on first song
			break
		end
	end
	
	-- Set initial song in GAMESTATE
	if first_song then
		GAMESTATE:SetCurrentSong(first_song)
		
		-- Set initial steps for all players
		for pn in ivalues(GAMESTATE:GetHumanPlayers()) do
			local steps = GAMESTATE:GetCurrentSteps(pn)
			if not steps then
				local all_steps = first_song:GetAllSteps()
				if all_steps and #all_steps > 0 then
					GAMESTATE:SetCurrentSteps(pn, all_steps[1])
				end
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
