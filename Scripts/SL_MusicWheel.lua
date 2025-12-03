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
		
		-- Last selected song/steps (persists when on group headers)
		last_song = nil,               -- Last selected song (for grade display)
		last_steps = {},               -- Last selected steps per player {[player] = steps}
		
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

-- Helper function: Check if a song has charts for the current style
local function HasChartsForCurrentStyle(song)
	local steps_type = GAMESTATE:GetCurrentStyle():GetStepsType()
	local steps = song:GetStepsByStepsType(steps_type)
	return steps and #steps > 0
end

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
		local all_songs = GetSongsInGroup(group_name)
		
		-- Filter songs to only include those with charts for current style
		local songs = {}
		for _, song in ipairs(all_songs) do
			if HasChartsForCurrentStyle(song) then
				table.insert(songs, song)
			end
		end
		
		-- Only add groups that have compatible songs
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
	local all_songs = GetAllSongs()
	
	-- Filter songs to only include those with charts for current style
	local songs = {}
	for _, song in ipairs(all_songs) do
		if HasChartsForCurrentStyle(song) then
			table.insert(songs, song)
		end
	end
	
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
	local all_songs = GetAllSongs()
	
	-- Filter songs to only include those with charts for current style
	local songs = {}
	for _, song in ipairs(all_songs) do
		if HasChartsForCurrentStyle(song) then
			table.insert(songs, song)
		end
	end
	
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
	local all_songs = GetAllSongs()
	
	-- Filter songs to only include those with charts for current style
	local songs = {}
	for _, song in ipairs(all_songs) do
		if HasChartsForCurrentStyle(song) then
			table.insert(songs, song)
		end
	end
	
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
	local all_songs = GetAllSongs()
	
	-- Filter songs to only include those with charts for current style
	local songs = {}
	for _, song in ipairs(all_songs) do
		if HasChartsForCurrentStyle(song) then
			table.insert(songs, song)
		end
	end
	
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

-- Build list of wheel items for Most Played sort (flat list, no grouping)
-- Combines play counts from all enabled players
function SL.MusicWheel.BuildWheelData_MostPlayed()
	local items = {}
	local all_songs = GetAllSongs()
	
	-- Filter songs to only include those with charts for current style
	local songs = {}
	for _, song in ipairs(all_songs) do
		if HasChartsForCurrentStyle(song) then
			table.insert(songs, song)
		end
	end
	
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
	for _, song in ipairs(songs) do
		table.insert(items, {
			type = "song",
			song = song,
			group = nil,
			is_favorite = false,
			favorited_by = {}
		})
	end
	
	return items
end

-- Build list of wheel items for Machine Most Played sort (flat list, no grouping)
-- Uses machine profile play counts only
function SL.MusicWheel.BuildWheelData_MachineMostPlayed()
	local items = {}
	local all_songs = GetAllSongs()
	
	-- Filter songs to only include those with charts for current style
	local songs = {}
	for _, song in ipairs(all_songs) do
		if HasChartsForCurrentStyle(song) then
			table.insert(songs, song)
		end
	end
	
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
	for _, song in ipairs(songs) do
		table.insert(items, {
			type = "song",
			song = song,
			group = nil,
			is_favorite = false,
			favorited_by = {}
		})
	end
	
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
				if val > max_nps then max_nps = val end
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
	local all_songs = GetAllSongs()
	local steps_type = GAMESTATE:GetCurrentStyle():GetStepsType()
	
	-- Filter songs to only include those with charts for current style
	local songs = {}
	for _, song in ipairs(all_songs) do
		if HasChartsForCurrentStyle(song) then
			table.insert(songs, song)
		end
	end
	
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
function SL.MusicWheel.FindSongIndex(target_song)
	if not target_song then return nil end
	
	local state = SL.MusicWheel.State
	
	-- First, check if the song is already visible in current items
	for i, item in ipairs(state.items) do
		if item.type == "song" and item.song == target_song then
			return i
		end
	end
	
	-- Song not visible - need to find and open its group
	-- Get the song's group name
	local song_group = target_song:GetGroupName()
	
	-- Close all groups and open the target group
	state.open_groups = {}
	state.open_groups[song_group] = true
	
	-- Rebuild wheel data with the new group open
	state.items = SL.MusicWheel.BuildWheelData(state.sort_order)
	
	-- Now find the song in the rebuilt items
	for i, item in ipairs(state.items) do
		if item.type == "song" and item.song == target_song then
			return i
		end
	end
	
	-- Still not found (song might not exist in current sort/filter)
	return nil
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
	
	-- If we have a target song, try to open its group
	if target_song then
		local song_group = target_song:GetGroupName()
		SL.MusicWheel.State.open_groups[song_group] = true
	else
		-- Fallback: Open first group by default
		local groups = GetAllGroups()
		if #groups > 0 then
			SL.MusicWheel.State.open_groups[groups[1]] = true
		end
	end
	
	-- Build initial wheel data
	SL.MusicWheel.RebuildWheelData("SortOrder_Group")
	
	-- Try to focus on the target song, or fall back to first song
	local focus_song = nil
	local focus_index = 1
	
	if target_song then
		-- Find the target song in the wheel
		local song_index = SL.MusicWheel.FindSongIndex(target_song)
		if song_index then
			focus_index = song_index
			focus_song = target_song
		end
	end
	
	-- If no target song found, use first song in wheel
	if not focus_song then
		for i, item in ipairs(SL.MusicWheel.State.items) do
			if item.type == "song" then
				focus_song = item.song
				focus_index = i
				break
			end
		end
	end
	
	SL.MusicWheel.State.focus_index = focus_index
	
	-- Set initial song in GAMESTATE
	if focus_song then
		GAMESTATE:SetCurrentSong(focus_song)
		
		-- Set initial steps for all players
		local steps_type = GAMESTATE:GetCurrentStyle():GetStepsType()
		
		for pn in ivalues(GAMESTATE:GetHumanPlayers()) do
			local steps_to_set = nil
			
			-- Determine the player's preferred difficulty
			-- Priority: 1. Per-player difficulty from last_played, 2. Session data, 3. Engine preference
			local player_difficulty = nil
			
			-- First check per-player difficulties from last_played (includes session data)
			if last_played and last_played.difficulties and last_played.difficulties[pn] then
				player_difficulty = last_played.difficulties[pn]
			end
			
			-- Fallback to engine's preferred difficulty
			if not player_difficulty and PROFILEMAN:IsPersistentProfile(pn) then
				player_difficulty = GAMESTATE:GetPreferredDifficulty(pn)
			end
			
			-- Find steps matching the preferred difficulty
			local compatible_steps = focus_song:GetStepsByStepsType(steps_type)
			if compatible_steps and #compatible_steps > 0 then
				if player_difficulty then
					-- Convert string difficulty to enum if needed (profile file stores as string)
					local diff_to_match = player_difficulty
					if type(player_difficulty) == "string" then
						diff_to_match = _G[player_difficulty] or player_difficulty
					end
					
					-- Try to find exact match
					for _, steps in ipairs(compatible_steps) do
						if steps:GetDifficulty() == diff_to_match then
							steps_to_set = steps
							break
						end
					end
					
					-- If no exact match, find closest
					if not steps_to_set then
						local diff_order = {
							[Difficulty_Beginner] = 1, ["Difficulty_Beginner"] = 1,
							[Difficulty_Easy] = 2, ["Difficulty_Easy"] = 2,
							[Difficulty_Medium] = 3, ["Difficulty_Medium"] = 3,
							[Difficulty_Hard] = 4, ["Difficulty_Hard"] = 4,
							[Difficulty_Challenge] = 5, ["Difficulty_Challenge"] = 5,
							[Difficulty_Edit] = 6, ["Difficulty_Edit"] = 6
						}
						local target_value = diff_order[diff_to_match] or diff_order[player_difficulty] or 3
						local best_distance = 999
						
						for _, steps in ipairs(compatible_steps) do
							local steps_value = diff_order[steps:GetDifficulty()] or 3
							local distance = math.abs(steps_value - target_value)
							if distance < best_distance then
								best_distance = distance
								steps_to_set = steps
							end
						end
					end
				end
				
				-- Fallback to first available steps
				if not steps_to_set then
					steps_to_set = compatible_steps[1]
				end
				
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
