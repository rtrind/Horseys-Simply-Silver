-- MusicWheel/default.lua
-- Main wheel container using sick_wheel framework
-- Phase 1: Basic scrollable wheel with songs and groups

-- Load the WheelItem metatable
local WheelItem = LoadActor("WheelItem.lua")

-- Create sick_wheel instance
local wheel = setmetatable({}, sick_wheel_mt)

-- Wheel configuration
local num_items = 13  -- 9 visible + 2 above + 2 below
local wheel_x = SCREEN_CENTER_X + 109
local wheel_y = SCREEN_CENTER_Y + 197

-- ============================================================================
-- Song Preview Debounce System
-- ============================================================================
-- Prevents audio stuttering when rapidly scrolling (holding the button).
-- Single taps play the preview immediately for responsiveness.
-- Continuous scrolling waits until you stop before playing.

local scroll_settle_delay = 0.15     -- seconds to wait after rapid scroll stops before updating GAMESTATE
local scroll_rapid_threshold = 0.20  -- if next scroll comes within this time, it's "rapid"
local last_scroll_time = 0           -- timestamp of last scroll action
local is_rapid_scrolling = false     -- true when user is holding the button
local gamestate_update_pending = false  -- whether we need to update GAMESTATE after scrolling stops
-- Debug
-- local wheel_x = SCREEN_CENTER_X + 309
-- local wheel_y = SCREEN_CENTER_Y + 28
-- ============================================================================
-- Input Handler
-- ============================================================================

-- Track which buttons are currently held down per player
local heldButtons = {
	[PLAYER_1] = {},
	[PLAYER_2] = {}
}

-- Track Start button timing for options prompt
local startPressTime = nil
local startPressPlayer = nil
local optionsPromptTimeout = 3.0  -- seconds to wait for second Start press

-- Track button sequences for difficulty changes (Up,Up = easier, Down,Down = harder)
local buttonSequence = {
	[PLAYER_1] = {},
	[PLAYER_2] = {}
}
local sequenceTimeout = 0.5  -- Time window for sequence detection (seconds)

-- Track each player's preferred difficulty (by difficulty enum, not steps object)
-- This persists across song changes
local preferredDifficulty = {
	[PLAYER_1] = nil,  -- Will be set to Difficulty enum (e.g., "Difficulty_Easy")
	[PLAYER_2] = nil
}

-- Helper function to find the best matching steps for a preferred difficulty
-- Returns the steps object that best matches the preference
local function FindBestSteps(song, stepsType, preferredDiff)
	local allSteps = song:GetStepsByStepsType(stepsType)
	if #allSteps == 0 then return nil end

	-- If no preference, return first available
	if not preferredDiff then
		return allSteps[1]
	end

	-- Try exact match first
	for _, steps in ipairs(allSteps) do
		if steps:GetDifficulty() == preferredDiff then
			return steps
		end
	end

	-- No exact match - find closest, preferring easier
	-- Difficulty order: Beginner < Easy < Medium < Hard < Challenge < Edit
	local difficultyOrder = {
		Difficulty_Beginner = 1,
		Difficulty_Easy = 2,
		Difficulty_Medium = 3,
		Difficulty_Hard = 4,
		Difficulty_Challenge = 5,
		Difficulty_Edit = 6
	}

	local preferredValue = difficultyOrder[preferredDiff] or 3
	local bestSteps = allSteps[1]
	local bestDistance = 999

	for _, steps in ipairs(allSteps) do
		local stepsDiff = steps:GetDifficulty()
		local stepsValue = difficultyOrder[stepsDiff] or 3
		local distance = math.abs(stepsValue - preferredValue)

		-- If same distance, prefer easier (lower value)
		if distance < bestDistance or (distance == bestDistance and stepsValue < difficultyOrder[bestSteps:GetDifficulty()]) then
			bestSteps = steps
			bestDistance = distance
		end
	end

	return bestSteps
end

-- Check if we're in rapid scrolling mode
-- Returns true if we should defer GAMESTATE updates
local function CheckRapidScrolling()
	local now = GetTimeSinceStart()
	local time_since_last = now - last_scroll_time
	last_scroll_time = now
	
	-- Detect if this is rapid scrolling (button held) vs single tap
	if time_since_last < scroll_rapid_threshold and time_since_last > 0 then
		-- This scroll came quickly after the last one = rapid scrolling
		if not is_rapid_scrolling then
			-- Just started rapid scrolling - stop music once
			is_rapid_scrolling = true
			if stop_music then
				stop_music()
			end
		end
		return true  -- Defer GAMESTATE update
	else
		-- Single tap (or first scroll after a pause)
		is_rapid_scrolling = false
		return false  -- Update GAMESTATE immediately
	end
end

-- Apply the focused song to GAMESTATE and broadcast messages
-- Called either immediately (single tap) or after rapid scrolling stops
local function ApplyFocusedSongToGamestate()
	local focused_song = SL.MusicWheel.GetFocusedSong()
	local focused_group = SL.MusicWheel.GetFocusedGroup()

	if focused_song then
		GAMESTATE:SetCurrentSong(focused_song)
		
		-- Track last song for grade display when on group headers
		SL.MusicWheel.State.last_song = focused_song

		-- Get the focused item to check if it has specific steps (Difficulty sort)
		local focused_item = SL.MusicWheel.GetFocusedItem()

		-- Set steps for each player
		for player in ivalues(GAMESTATE:GetHumanPlayers()) do
			local stepsToSet = nil

			-- If the item has specific steps (Difficulty sort), use those
			if focused_item and focused_item.steps then
				stepsToSet = focused_item.steps
			else
				-- Otherwise, find best matching steps for player's preferred difficulty
				local stepsType = GAMESTATE:GetCurrentStyle():GetStepsType()
				stepsToSet = FindBestSteps(focused_song, stepsType, preferredDifficulty[player])

				-- Update preference if we found steps
				if stepsToSet and not preferredDifficulty[player] then
					preferredDifficulty[player] = stepsToSet:GetDifficulty()
				end
			end

			if stepsToSet then
				GAMESTATE:SetCurrentSteps(player, stepsToSet)
				-- Track last steps for grade display when on group headers
				SL.MusicWheel.State.last_steps[player] = stepsToSet
			else
				-- No steps available for this song/style
				GAMESTATE:SetCurrentSteps(player, nil)
			end

			-- Broadcast steps changed for NoteField preview
			MESSAGEMAN:Broadcast("CurrentStepsP" .. (player == PLAYER_1 and "1" or "2") .. "Changed")
		end

		MESSAGEMAN:Broadcast("CurrentSongChanged")
	elseif focused_group then
		-- Clear current song when on group header
		GAMESTATE:SetCurrentSong(nil)

		-- Clear steps for each player
		for player in ivalues(GAMESTATE:GetHumanPlayers()) do
			GAMESTATE:SetCurrentSteps(player, nil)
		end

		if stop_music then
			stop_music()
		end

		MESSAGEMAN:Broadcast("CurrentSongChanged")
		-- Broadcast group focus for banner display
		MESSAGEMAN:Broadcast("FocusedGroupChanged", {group = focused_group})
	end
	
	gamestate_update_pending = false
end

-- Sound actor reference (set in InitCommand)
local wheel_change_sound = nil

local function PerformScroll(direction, pn)
	-- Final check: don't scroll if input is redirected (Sort Menu open)
	if SCREENMAN:get_input_redirected(pn) then return end

	-- Play wheel change sound
	if wheel_change_sound then
		wheel_change_sound:play()
	end

	-- Update wheel data and display (visual only)
	SL.MusicWheel.Scroll(direction)
	wheel:scroll_by_amount(direction)

	-- Check if we're rapid scrolling
	local defer_gamestate = CheckRapidScrolling()
	
	if defer_gamestate then
		-- Rapid scrolling - just mark that we need to update GAMESTATE later
		gamestate_update_pending = true
	else
		-- Single tap - update GAMESTATE immediately
		ApplyFocusedSongToGamestate()
	end
end

-- ============================================================================
-- ActorFrame Definition
-- ============================================================================

local t = Def.ActorFrame{
	Name = "MusicWheel",

	InitCommand = function(self)
		-- Store reference for debounce system
		preview_actor = self
		
		-- Apply same zoom as original engine wheel FIRST (before positioning)
		self:zoom(0.797)
		self:zoomy(0.772)

		-- Safety check: ensure SL.MusicWheel exists
		if not SL.MusicWheel then
			SM("ERROR: SL.MusicWheel not loaded! Check Scripts/SL_MusicWheel.lua")
			return
		end
		
		-- Set up the update function for deferred GAMESTATE updates
		-- Only triggers after rapid scrolling stops
		self:SetUpdateFunction(function(actor)
			if gamestate_update_pending and is_rapid_scrolling then
				local now = GetTimeSinceStart()
				if now - last_scroll_time >= scroll_settle_delay then
					-- Rapid scrolling has stopped, now update GAMESTATE
					is_rapid_scrolling = false
					ApplyFocusedSongToGamestate()
				end
			end
		end)
		
		-- Initialize scroll interval (Consumed by InputHandler mostly, but kept here for reference if needed)
		-- UpdateScrollInterval() -- Removed, logic moved to InputHandler

		-- Initialize preferred difficulty from session data or profile
		-- Priority: 1. Session data, 2. Initial difficulties from Initialize(), 3. Current steps, 4. Engine preference
		local initial_diffs = SL.MusicWheel.State and SL.MusicWheel.State.initial_difficulties or {}
		
		for player in ivalues(GAMESTATE:GetHumanPlayers()) do
			-- First check session data (highest priority)
			local session_data = SL.Global.LastPlayed and SL.Global.LastPlayed[player]
			if session_data and session_data.difficulty then
				preferredDifficulty[player] = session_data.difficulty
			end
			
			-- If no session data, check the per-player difficulties from Initialize()
			if not preferredDifficulty[player] and initial_diffs[player] then
				preferredDifficulty[player] = initial_diffs[player]
			end
			
			-- If still nothing, try current steps (set by Initialize)
			if not preferredDifficulty[player] then
				local current_steps = GAMESTATE:GetCurrentSteps(player)
				if current_steps then
					preferredDifficulty[player] = current_steps:GetDifficulty()
				end
			end
			
			-- Fallback to engine preference
			if not preferredDifficulty[player] and PROFILEMAN:IsPersistentProfile(player) then
				preferredDifficulty[player] = GAMESTATE:GetPreferredDifficulty(player)
			end
		end

		-- Initialize wheel data
		wheel:set_info_set(SL.MusicWheel.State.items, SL.MusicWheel.State.focus_index)
	end,

	OnCommand = function(self)
		-- Removed AddInputCallback logic - handled by InputHandler.lua
		-- Removed Update loop for scrolling - handled by InputHandler.lua (sending MW_Scroll commands)

		-- Ensure initial selection is broadcast to UI (Banner, NoteField, etc.)
		-- Add a small delay to ensure everything is ready before playing audio
		self:sleep(0.05):queuecommand("BroadcastInitialSelection")
	end,

	-- Exposed Commands for InputHandler
	MW_ScrollLeftCommand = function(self, params) PerformScroll(-1, params.PlayerNumber) end,
	MW_ScrollRightCommand = function(self, params) PerformScroll(1, params.PlayerNumber) end,
	
	MW_ToggleGroupCommand = function(self)
		if SL.MusicWheel.ToggleGroup(true) then
			wheel:set_info_set(SL.MusicWheel.State.items, SL.MusicWheel.State.focus_index)
		end
	end,


	MW_ToggleFavoriteCommand = function(self, params)
		local pn = params.PlayerNumber
		local song = GAMESTATE:GetCurrentSong()
		if song then
			local profile = PROFILEMAN:GetProfile(pn)
			if profile then
				if profile:SongIsFavorite(song) then
					profile:RemoveSongFromFavorites(song)
				else
					profile:AddSongToFavorites(song)
				end
				-- Broadcast to update heart icons
				MESSAGEMAN:Broadcast("FavoritesChanged")
			end
		end
	end,

	MW_DifficultyChangeCommand = function(self, params)
		local pn = params.PlayerNumber
		local dir = params.Direction -- -1 for easier, 1 for harder
		
		local focused_song = SL.MusicWheel.GetFocusedSong()
		if focused_song then
			local stepsType = GAMESTATE:GetCurrentStyle():GetStepsType()
			local allSteps = focused_song:GetStepsByStepsType(stepsType)
			local currentSteps = GAMESTATE:GetCurrentSteps(pn)

			if #allSteps > 0 and currentSteps then
				-- Find current difficulty index
				local currentIndex = 1
				for i, steps in ipairs(allSteps) do
					if steps == currentSteps then
						currentIndex = i
						break
					end
				end

				-- Change difficulty
				local newIndex = currentIndex
				if dir == -1 then
					-- Easier (lower index)
					newIndex = math.max(1, currentIndex - 1)
				else
					-- Harder (higher index)
					newIndex = math.min(#allSteps, currentIndex + 1)
				end

				if newIndex ~= currentIndex then
					local newSteps = allSteps[newIndex]
					GAMESTATE:SetCurrentSteps(pn, newSteps)
					-- Save this as the player's preferred difficulty
					preferredDifficulty[pn] = newSteps:GetDifficulty()
					MESSAGEMAN:Broadcast("CurrentStepsP" .. (pn == PLAYER_1 and "1" or "2") .. "Changed")
				end
			end
		end
	end,

	BroadcastInitialSelectionCommand = function(self)
		-- Ensure initial selection is broadcast to UI (Banner, NoteField, etc.)
		local focused_song = SL.MusicWheel.GetFocusedSong()
		local focused_group = SL.MusicWheel.GetFocusedGroup()

		if focused_song then
			GAMESTATE:SetCurrentSong(focused_song)

			-- Get the focused item to check if it has specific steps (Difficulty sort)
			local focused_item = SL.MusicWheel.GetFocusedItem()

			-- Set steps for each player
			for player in ivalues(GAMESTATE:GetHumanPlayers()) do
				local stepsToSet = nil

				-- If the item has specific steps (Difficulty sort), use those
				if focused_item and focused_item.steps then
					stepsToSet = focused_item.steps
				else
					-- Otherwise, find best matching steps for player's preferred difficulty
					local stepsType = GAMESTATE:GetCurrentStyle():GetStepsType()
					stepsToSet = FindBestSteps(focused_song, stepsType, preferredDifficulty[player])

					-- Update preference if we found steps
					if stepsToSet and not preferredDifficulty[player] then
						preferredDifficulty[player] = stepsToSet:GetDifficulty()
					end
				end

				if stepsToSet then
					GAMESTATE:SetCurrentSteps(player, stepsToSet)
				else
					GAMESTATE:SetCurrentSteps(player, nil)
				end

				-- Broadcast steps changed for NoteField preview
				MESSAGEMAN:Broadcast("CurrentStepsP" .. (player == PLAYER_1 and "1" or "2") .. "Changed")
			end

			MESSAGEMAN:Broadcast("CurrentSongChanged")
		elseif focused_group then
			GAMESTATE:SetCurrentSong(nil)

			-- Clear steps for each player
			for player in ivalues(GAMESTATE:GetHumanPlayers()) do
				GAMESTATE:SetCurrentSteps(player, nil)
			end

			MESSAGEMAN:Broadcast("CurrentSongChanged")
			MESSAGEMAN:Broadcast("FocusedGroupChanged", {group = focused_group})
		end

		-- Fade in
		self:diffusealpha(0)
		self:sleep(0.2)
		self:linear(0.3)
		self:diffusealpha(1)
	end,

	OffCommand = function(self)
		-- Fade out
		self:linear(0.2)
		self:diffusealpha(0)
	end,

	-- Handle wheel rebuild (when sort order changes)
	MusicWheelRebuiltMessageCommand = function(self, params)
		-- Rebuild wheel data
		wheel:set_info_set(SL.MusicWheel.State.items, SL.MusicWheel.State.focus_index)

		-- Update GAMESTATE with focused song
		local focused_song = SL.MusicWheel.GetFocusedSong()
		if focused_song then
			GAMESTATE:SetCurrentSong(focused_song)
			MESSAGEMAN:Broadcast("CurrentSongChanged")

			-- Get the focused item to check if it has specific steps (Difficulty sort)
			local focused_item = SL.MusicWheel.GetFocusedItem()

			-- Ensure steps are set for both players and broadcast for NoteField preview
			for pn in ivalues(GAMESTATE:GetHumanPlayers()) do
				local stepsToSet = nil

				-- If the item has specific steps (Difficulty sort), use those
				if focused_item and focused_item.steps then
					stepsToSet = focused_item.steps
				else
					-- Otherwise, check if steps are already set, or use first available
					stepsToSet = GAMESTATE:GetCurrentSteps(pn)
					if not stepsToSet then
						local song_steps = focused_song:GetAllSteps()
						if song_steps and #song_steps > 0 then
							stepsToSet = song_steps[1]
						end
					end
				end

				if stepsToSet then
					GAMESTATE:SetCurrentSteps(pn, stepsToSet)
				end
			end

			-- Broadcast steps changed for NoteField preview
			MESSAGEMAN:Broadcast("CurrentStepsP1Changed")
			MESSAGEMAN:Broadcast("CurrentStepsP2Changed")
		else
			-- If focused item is not a song (e.g. group header), clear current song
			GAMESTATE:SetCurrentSong(nil)
			MESSAGEMAN:Broadcast("CurrentSongChanged")
		end
	end,

	-- Handle song change to play preview music
	CurrentSongChangedMessageCommand = function(self, params)
		-- Play sample music (defined in Scripts/SL-SelectMusicHelpers.lua)
		if play_sample_music then
			play_sample_music()
		end
	end,

	FavoritesChangedMessageCommand = function(self)
		if not (SL and SL.MusicWheel and SL.MusicWheel.UpdateFavoritesMetadata) then return end
		local updates = SL.MusicWheel.UpdateFavoritesMetadata()
		if not updates then return end

		local state = SL.MusicWheel.State
		if updates.focused_item_index and state.items[updates.focused_item_index] then
			wheel:set_element_info(updates.focused_item_index, state.items[updates.focused_item_index])
		end

		if updates.favorites_header_index and state.items[updates.favorites_header_index] then
			wheel:set_element_info(updates.favorites_header_index, state.items[updates.favorites_header_index])
		end
	end,

	-- FavoritesChangedMessageCommand removed - heart icons update themselves via UpdateGrade

	-- Add the wheel actors (this returns an ActorFrame from sick_wheel)
	wheel:create_actors("WheelContainer", num_items, WheelItem, wheel_x, wheel_y),
	
	-- Wheel change sound
	Def.Sound{
		Name = "WheelChangeSound",
		File = THEME:GetPathS("MusicWheel", "change"),
		InitCommand = function(self)
			wheel_change_sound = self
		end,
	},
}

return t
