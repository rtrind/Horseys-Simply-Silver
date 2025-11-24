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
	
	-- Add each group as a header, and songs if open
	for _, group_name in ipairs(groups) do
		local songs = GetSongsInGroup(group_name)
		
		-- Only add groups that have songs
		if #songs > 0 then
			local is_open = SL.MusicWheel.State.open_groups[group_name] or false
			
			-- Add group header
			table.insert(items, {
				type = "group_header",
				group_name = group_name,
				song_count = #songs,
				is_open = is_open
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

-- Build flat list of wheel items for Title sort (alphabetical)
-- Phase 1: Simple flat list of all songs
function SL.MusicWheel.BuildWheelData_Title()
	local items = {}
	local songs = GetAllSongs()
	
	-- Sort songs alphabetically by title
	table.sort(songs, function(a, b)
		return a:GetDisplayMainTitle():lower() < b:GetDisplayMainTitle():lower()
	end)
	
	-- Add all songs as items
	for _, song in ipairs(songs) do
		table.insert(items, {
			type = "song",
			song = song,
			group = song:GetGroupName(),
			is_favorite = false,
			favorited_by = {}
		})
	end
	
	return items
end

-- Main entry point: Build wheel data based on current sort order
function SL.MusicWheel.BuildWheelData(sort_order)
	sort_order = sort_order or SL.MusicWheel.State.sort_order
	
	local items = {}
	
	-- Phase 1: Only support Group and Title sorts
	if sort_order == "SortOrder_Group" then
		items = SL.MusicWheel.BuildWheelData_Group()
	elseif sort_order == "SortOrder_Title" then
		items = SL.MusicWheel.BuildWheelData_Title()
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
function SL.MusicWheel.ToggleGroup()
	local state = SL.MusicWheel.State
	local focused_item = state.items[state.focus_index]
	
	-- Only toggle if focused on a group header
	if not focused_item or focused_item.type ~= "group_header" then
		return false
	end
	
	local group_name = focused_item.group_name
	
	-- Toggle the open state
	if state.open_groups[group_name] then
		state.open_groups[group_name] = nil  -- Close group
	else
		state.open_groups[group_name] = true  -- Open group
	end
	
	-- Rebuild wheel data to reflect the change
	local old_focus_index = state.focus_index
	state.items = SL.MusicWheel.BuildWheelData(state.sort_order)
	
	-- Try to maintain focus on the same group header
	-- After rebuild, find the group header again
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
		MESSAGEMAN:Broadcast("CurrentSongChanged")
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
