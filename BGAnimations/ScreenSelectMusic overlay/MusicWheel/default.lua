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

local function input(event)
	if not event or not event.PlayerNumber or not event.button then
		return false
	end

	local pn = event.PlayerNumber
	local button = event.GameButton

	-- Track button state for chord detection
	if event.type == "InputEventType_FirstPress" then
		heldButtons[pn][button] = true
	elseif event.type == "InputEventType_Release" then
		heldButtons[pn][button] = nil
	end

	-- Only handle if wheel is active
	if not wheel or not wheel.container then
		return false
	end

	-- Check for SortMenu chord FIRST (before redirect check)
	-- Don't consume MenuLeft/MenuRight if both are pressed (SortMenu chord)
	if event.type == "InputEventType_FirstPress" then
		if (button == "MenuLeft" or button == "MenuRight") and
			heldButtons[pn]["MenuLeft"] and heldButtons[pn]["MenuRight"] then
			-- Both buttons pressed - let it pass through to open SortMenu
			return false
		end
	end

	-- Don't handle input if input is redirected (e.g. SortMenu, QuitPrompt)
	if SCREENMAN:get_input_redirected(pn) then
		return false
	end

	-- Don't handle input if SortMenu is visible (legacy check, kept for safety)
	local screen = SCREENMAN:GetTopScreen()
	if screen then
		local sort_menu = screen:GetChild("Overlay"):GetChild("SortMenu")
		if sort_menu and sort_menu:GetVisible() then
			return false
		end
	end

	-- Handle FirstPress for Start button (toggle group or player join)
	if event.type == "InputEventType_FirstPress" then
		-- Check for MenuUp+MenuDown chord to close/open folder
		-- Only trigger if the current button is MenuUp or MenuDown AND both are now held
		if (button == "MenuUp" or button == "MenuDown") and
			heldButtons[pn]["MenuUp"] and heldButtons[pn]["MenuDown"] then
			-- Both MenuUp and MenuDown pressed - toggle group (allow from song)
			if SL.MusicWheel.ToggleGroup(true) then
				-- Group was toggled, update wheel display
				wheel:set_info_set(SL.MusicWheel.State.items, SL.MusicWheel.State.focus_index)
			end
			-- Consume the input to prevent scrolling
			return true
		end

		if event.GameButton == "Start" then
			-- Check if this is a non-enabled player trying to join
			if not GAMESTATE:IsPlayerEnabled(pn) then
				-- Join player and allow existing overlay logic to open profile select
				GAMESTATE:JoinPlayer(pn)
				return true
			end

			-- Player is already enabled - check if we're on a group header or song
			local focused_item = SL.MusicWheel.State.items[SL.MusicWheel.State.focus_index]

			-- If on group header, try to toggle it
			if focused_item and focused_item.type == "group_header" then
				if SL.MusicWheel.ToggleGroup(false) then
					-- Group was toggled, update wheel display
					wheel:set_info_set(SL.MusicWheel.State.items, SL.MusicWheel.State.focus_index)
					return true
				end
			end

			-- If on a song, handle song selection with options prompt
			if focused_item and focused_item.type == "song" then
				local now = GetTimeSinceStart()

				-- Check if this is a second Start press within timeout
				if startPressTime and (now - startPressTime) < optionsPromptTimeout and startPressPlayer == pn then
					-- Second press - go to options
					startPressTime = nil
					startPressPlayer = nil

					-- Verify we have a valid song selected in GAMESTATE
					if GAMESTATE:GetCurrentSong() then
						-- Show "Entering Options..." and navigate to options
						local screen = SCREENMAN:GetTopScreen()
						if screen then
							-- Set PlayMode to Regular (prevents crash)
							GAMESTATE:SetCurrentPlayMode("PlayMode_Regular")

							MESSAGEMAN:Broadcast("ShowEnteringOptions")
							-- Queue transition on overlay (wait for "Entering Options" message)
							local overlay = screen:GetChild("Overlay")
							if overlay then
								overlay:sleep(0.5):queuecommand("GoToOptions")
							end
						end
					end
					return true
				else
					-- First press - show prompt and start timer
					startPressTime = now
					startPressPlayer = pn

					-- Show "Press Start for Options" overlay
					MESSAGEMAN:Broadcast("ShowPressStartForOptions")

					-- Schedule timeout to go directly to gameplay
					local overlay = SCREENMAN:GetTopScreen():GetChild("Overlay")
					if overlay then
						overlay:queuecommand("StartTimeout")
					end
					return true
				end
			end

			-- Not on a song or group - let it pass through
			return false
		end

		-- Handle difficulty changes (Up,Up = easier, Down,Down = harder)
		if button == "MenuUp" or button == "MenuDown" then
			local currentTime = GetTimeSinceStart()
			local seq = buttonSequence[pn]

			-- Clear old sequence if timeout expired
			if #seq > 0 and (currentTime - seq[#seq].time) > sequenceTimeout then
				buttonSequence[pn] = {}
				seq = buttonSequence[pn]
			end

			-- Add button to sequence
			table.insert(seq, {button = button, time = currentTime})

			-- Check for difficulty change sequences (need 2 of the same button)
			if #seq >= 2 and seq[#seq].button == seq[#seq-1].button then
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
						if button == "MenuUp" then
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

				-- Clear sequence after processing
				buttonSequence[pn] = {}
				return true
			end
		end
	end

	-- Handle both FirstPress and Repeat for continuous scrolling
	if event.type == "InputEventType_FirstPress" or event.type == "InputEventType_Repeat" then
		if event.GameButton == "MenuLeft" or event.GameButton == "MenuRight" then
			local scrollDirection = 0
			if event.GameButton == "MenuLeft" then
				scrollDirection = -1
			else
				scrollDirection = 1
			end

			-- MenuLeft - Scroll up (previous song)
			SL.MusicWheel.Scroll(scrollDirection)

			-- Update wheel display
			wheel:scroll_by_amount(scrollDirection)

			-- Update GAMESTATE with focused song or group
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

				MESSAGEMAN:Broadcast("CurrentSongChanged")
				-- Broadcast group focus for banner display
				MESSAGEMAN:Broadcast("FocusedGroupChanged", {group = focused_group})
			end
			return false -- Return false to let InputHandler see the event (for chord detection)
		end
	end

	return false
end

-- ============================================================================
-- ActorFrame Definition
-- ============================================================================

local t = Def.ActorFrame{
	Name = "MusicWheel",

	InitCommand = function(self)
		-- Apply same zoom as original engine wheel FIRST (before positioning)
		self:zoom(0.797)
		self:zoomy(0.772)

		-- Safety check: ensure SL.MusicWheel exists
		if not SL.MusicWheel then
			SM("ERROR: SL.MusicWheel not loaded! Check Scripts/SL_MusicWheel.lua")
			return
		end

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
		-- SL.MusicWheel.Initialize() is now called in overlay/default.lua
		-- to ensure GAMESTATE is ready before NoteField creation

		-- Set initial wheel data
		wheel:set_info_set(SL.MusicWheel.State.items, SL.MusicWheel.State.focus_index)
	end,

	OnCommand = function(self)
		-- Register input handler (do this in OnCommand when screen is ready)
		local screen = SCREENMAN:GetTopScreen()
		if screen then
			screen:AddInputCallback(input)
		end

		-- Ensure initial selection is broadcast to UI (Banner, NoteField, etc.)
		-- Add a small delay to ensure everything is ready before playing audio
		self:sleep(0.05):queuecommand("BroadcastInitialSelection")
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
	CurrentSongChangedMessageCommand = function(self)
		-- Play sample music (defined in Scripts/SL-SelectMusicHelpers.lua)
		if play_sample_music then
			play_sample_music()
		end
	end,

	-- Add the wheel actors (this returns an ActorFrame from sick_wheel)
	wheel:create_actors("WheelContainer", num_items, WheelItem, wheel_x, wheel_y)
}

return t
