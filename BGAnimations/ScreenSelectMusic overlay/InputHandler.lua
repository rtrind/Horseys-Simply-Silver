-- Comprehensive Input Handler for ScreenSelectMusic
-- Restores functionality lost by switching to ScreenWithMenuElements
-- Reads codes from metrics.ini to preserve original bindings

-- Keyboard letter to Title sort jump feature
-- Maps DeviceButton_X to uppercase letter for quick navigation
local function GetLetterFromDeviceButton(deviceButton)
	if not deviceButton then return nil end
	-- DeviceButton format: "DeviceButton_a", "DeviceButton_b", etc.
	-- Also handle potential variations like "DeviceButton_A" or with spaces
	local letter = deviceButton:match("DeviceButton_([a-zA-Z])$")
	if letter and #letter == 1 then
		return letter:upper()
	end
	return nil
end

-- Jump to a letter group in Title sort mode
-- Always switches to Title sort and opens the corresponding letter group
local function JumpToLetter(letter)
	if not letter or not SL.MusicWheel then 
		Trace("[KEYBOARD] JumpToLetter: no letter or no SL.MusicWheel")
		return false 
	end
	
	local state = SL.MusicWheel.State
	
	Trace("[KEYBOARD] JumpToLetter: jumping to letter '" .. letter .. "', current sort: " .. tostring(state.sort_order))
	
	-- The letter group name in Title sort is just the uppercase letter
	local targetGroup = letter
	
	-- Switch to Title sort if not already
	if state.sort_order ~= "SortOrder_Title" then
		Trace("[KEYBOARD] Switching to Title sort")
		-- Close all groups and open only the target letter group
		state.open_groups = {}
		state.open_groups[targetGroup] = true
		-- Rebuild wheel with Title sort
		state.sort_order = "SortOrder_Title"
		state.items = SL.MusicWheel.BuildWheelData("SortOrder_Title")
	else
		-- Already in Title sort - just open the target group (close others)
		state.open_groups = {}
		state.open_groups[targetGroup] = true
		state.items = SL.MusicWheel.BuildWheelData("SortOrder_Title")
	end
	
	-- Find the group header for this letter
	local groupIndex = nil
	for i, item in ipairs(state.items) do
		if item.type == "group_header" and item.group_name == targetGroup then
			groupIndex = i
			break
		end
	end
	
	if groupIndex then
		Trace("[KEYBOARD] Found group '" .. targetGroup .. "' at index " .. groupIndex)
		state.focus_index = groupIndex
		
		-- Select the first song in the group if available
		if state.items[groupIndex + 1] and state.items[groupIndex + 1].type == "song" then
			local firstSong = state.items[groupIndex + 1].song
			state.focus_index = groupIndex + 1
			GAMESTATE:SetCurrentSong(firstSong)
			
			-- Update steps for all players
			local stepsType = GAMESTATE:GetCurrentStyle():GetStepsType()
			local compatible_steps = firstSong:GetStepsByStepsType(stepsType)
			if compatible_steps and #compatible_steps > 0 then
				for player in ivalues(GAMESTATE:GetHumanPlayers()) do
					GAMESTATE:SetCurrentSteps(player, compatible_steps[1])
				end
			end
		end
		
		-- Broadcast to update wheel display
		MESSAGEMAN:Broadcast("MusicWheelRebuilt", {letter_jump = letter})
		return true
	else
		Trace("[KEYBOARD] No group found for letter '" .. letter .. "'")
	end
	
	return false
end

-- Shared state for Back button cooldown (set by EscapeFromEventMode)
if not _G.SSM_ignore_back_until then
	_G.SSM_ignore_back_until = 0
end

-- Global lock to prevent multiple overlays (SortMenu, ExitPrompt) from opening simultaneously
if _G.SSM_OverlayActive == nil then
	_G.SSM_OverlayActive = false
end

local function BroadcastMessage(name, pn)
	MESSAGEMAN:Broadcast("CodeMessage", {Name=name, PlayerNumber=pn})
end

-- Read the code definitions from metrics.ini
local function GetCode(codeName)
	return THEME:GetMetric("ScreenSelectMusic", "Code" .. codeName)
end

-- Track which buttons are currently held down per player
local heldButtons = {
	[PLAYER_1] = {},
	[PLAYER_2] = {}
}


-- Track scroll timing for variable speed
local nextScrollTime = {
	[PLAYER_1] = 0,
	[PLAYER_2] = 0
}
local initialScrollDelay = 0.3
local scrollInterval = 0.1 -- Default, will be updated from prefs

-- Helper to update scroll interval from prefs
local function UpdateScrollInterval()
	local speed = PREFSMAN:GetPreference("MusicWheelSwitchSpeed") or 15
	-- Protect against divide by zero or negative
	if speed < 1 then speed = 1 end
	
	-- Since rapid scrolling no longer triggers song previews, we can scroll faster
	-- Speed 1 = 4 items/sec, Speed 15 = 19 items/sec, Speed 25 = 29 items/sec
	local itemsPerSec = speed + 3
	scrollInterval = 1 / itemsPerSec
end

-- Track button sequences for difficulty changes/favorites
local buttonSequence = {
	[PLAYER_1] = {},
	[PLAYER_2] = {}
}
local sequenceTimeout = 0.5

-- Track Start button timing for options prompt
local startPressTime = nil
local startPressPlayer = nil
local optionsPromptTimeout = 3.0  -- seconds to wait for second Start press
local waitingForOptions = false

-- Get the MusicWheel actor
local function GetMusicWheel()
	local screen = SCREENMAN:GetTopScreen()
	if not screen then return nil end
	-- Only try to get MusicWheel on ScreenSelectMusic
	local screenName = screen:GetName()
	if screenName ~= "ScreenSelectMusic" and screenName ~= "ScreenSelectMusicWide" then
		return nil
	end
	local overlay = screen:GetChild("Overlay")
	if overlay and overlay.GetChild then
		return overlay:GetChild("MusicWheel")
	end
	return nil
end

-- Helper to parse metric string into a structured object
-- Format examples:
-- "MenuLeft-MenuRight" -> Chord
-- "@MenuUp-MenuDown" -> Chord (ignore @)
-- "MenuUp,MenuDown,MenuUp,MenuDown" -> Sequence
local function ParseMetricCode(codeString)
	if not codeString or codeString == "" then return nil end
	
	-- Remove @ prefix if present (often used in metrics to denote chords vs taps)
	local cleanCode = codeString:gsub("^@", "")
	
	-- Check for Sequence (commas)
	if cleanCode:find(",") then
		local seq = {}
		for btn in cleanCode:gmatch("([^,]+)") do
			-- Trim whitespace
			table.insert(seq, (btn:gsub("%s+", "")))
		end
		return { type = "sequence", buttons = seq }
	end
	
	-- Check for Chord (dashes)
	if cleanCode:find("-") then
		local chord = {}
		for btn in cleanCode:gmatch("([^-]+)") do
			table.insert(chord, (btn:gsub("%s+", "")))
		end
		return { type = "chord", buttons = chord }
	end
	
	-- Single Button
	return { type = "chord", buttons = { cleanCode } }
end

-- Checks if a specific chord definition is currently held
local function IsChordSatisfied(buttons, pn)
	for _, button in ipairs(buttons) do
		-- If any button in the chord isn't held, fail
		if not heldButtons[pn][button] then
			return false
		end
	end
	return true
end

-- Checks if a sequence definition matches the detailed history
local function IsSequenceSatisfied(targetSequence, history)
	if #history < #targetSequence then return false end
	
	-- Check backwards from the end
	for i = 1, #targetSequence do
		local targetBtn = targetSequence[#targetSequence - i + 1]
		local historyItem = history[#history - i + 1]
		
		if historyItem.button ~= targetBtn then
			return false
		end
	end
	return true
end

-- Pre-load and parse codes from metrics to avoid parsing every frame
local InputCodes = {
	SortList = ParseMetricCode(GetCode("SortList")),
	SortList2 = ParseMetricCode(GetCode("SortList2")),
	ToggleGroup = ParseMetricCode(GetCode("CloseFolder")),
	ToggleFavorite = ParseMetricCode(GetCode("ToggleFavorite")),
	TogglePatternInfo = ParseMetricCode(GetCode("TogglePatternInfo")),
	DifficultyEasier = ParseMetricCode(GetCode("DifficultyEasier")),
	DifficultyHarder = ParseMetricCode(GetCode("DifficultyHarder")),
}

-- Buffer for scroll inputs to allow chord detection prevention
-- When Left is pressed, we wait a tiny bit to see if Right is also pressed.
-- If Right is pressed within the window, it's a chord -> Cancel Scroll.
-- If window expires, it's a tap -> Execute Scroll.
local scrollQueue = {
	[PLAYER_1] = nil,
	[PLAYER_2] = nil
}
local chordDetectionWindow = 0.05 -- 50ms window

local input = function(event)
	-- Keyboard letter jump feature (only when KeyboardFeatures is enabled)
	-- Check for unmapped keyboard letter presses FIRST (before PlayerNumber check)
	-- Keyboard input may not have PlayerNumber set
	if ThemePrefs.Get("KeyboardFeatures") and event.type == "InputEventType_FirstPress" then
		-- event.button is empty string for unmapped keys
		local rawButton = event.button
		if rawButton == "" and event.DeviceInput and event.DeviceInput.button then
			local deviceButton = event.DeviceInput.button
			local letter = GetLetterFromDeviceButton(deviceButton)
			if letter and not _G.SSM_OverlayActive and not waitingForOptions then
				-- Don't process if input is redirected (overlay open)
				local anyRedirected = false
				for player in ivalues(GAMESTATE:GetHumanPlayers()) do
					if SCREENMAN:get_input_redirected(player) then
						anyRedirected = true
						break
					end
				end
				if not anyRedirected and JumpToLetter(letter) then
					return true
				end
			end
		end
	end
	
	-- For other input handling, require PlayerNumber
	if not event.PlayerNumber then return false end
	
	local pn = event.PlayerNumber
	local button = event.GameButton
	local screen = SCREENMAN:GetTopScreen()
	local overlay = screen:GetChild("Overlay")
	local wheel = GetMusicWheel()
	
	-- For other input handling, require GameButton
	if not button then return false end
	
	-- Don't handle input if input is redirected (e.g. SortMenu is open or closing)
	-- Clear held buttons when redirected to prevent phantom scrolling after overlay closes
	if SCREENMAN:get_input_redirected(pn) then
		heldButtons[pn] = {}
		return false
	end
	
	-- Track button state (only when not redirected)
	if event.type == "InputEventType_FirstPress" then
		heldButtons[pn][button] = true
	elseif event.type == "InputEventType_Release" then
		heldButtons[pn][button] = nil
	end

	-- If waiting for options, block most inputs
	if waitingForOptions then
		if event.type == "InputEventType_FirstPress" then
			-- Allow Start (to confirm options) or Back (to cancel)
			if button == "Start" then
				-- Handle 2nd press (Go to options) logic below
			else
				-- Block everything else (SortMenu, Scroll, Back, etc.)
				return true 
			end
		else
			return false
		end
	end

	if event.type == "InputEventType_FirstPress" then
		
		-- 1. Check Chords (Sort Menu, Toggle Group)
		-- We check chords on FirstPress. Since chords require multiple buttons, 
		-- this will trigger when the LAST button of the chord is pressed.
		
		-- Sort Menu
		for _, key in ipairs({"SortList", "SortList2"}) do
			local codeDef = InputCodes[key]
			if codeDef and codeDef.type == "chord" then
				if IsChordSatisfied(codeDef.buttons, pn) then
					if not _G.SSM_OverlayActive then
						-- Cancel any pending scroll since we found a chord
						scrollQueue[pn] = nil
						
						_G.SSM_OverlayActive = true
						overlay:queuecommand("DirectInputToSortMenu")
					end
					return true
				end
			end
		end

		-- Toggle Group
		if InputCodes.ToggleGroup and InputCodes.ToggleGroup.type == "chord" then
			if IsChordSatisfied(InputCodes.ToggleGroup.buttons, pn) then
				-- Cancel any pending scroll
				scrollQueue[pn] = nil
				if wheel then wheel:playcommand("MW_ToggleGroup") end
				return true
			end
		end
		
		-- Handle Back button
		if button == "Back" then
			-- Ignore Back button if we're in cooldown period (just closed quit prompt)
			if GetTimeSinceStart() < _G.SSM_ignore_back_until then
				return true  -- Consume but don't act
			end
			
			-- If Event Mode is ON, Back triggers the Exit Prompt
			if PREFSMAN:GetPreference("EventMode") then
				-- Only open if no other overlay is active
				if not _G.SSM_OverlayActive then
					_G.SSM_OverlayActive = true
					MESSAGEMAN:Broadcast("ShowExitPrompt", {PlayerNumber=pn})
				end
				return true
			else
				-- Normal navigation
				screen:SetNextScreenName(screen:GetPrevScreenName())
				screen:StartTransitioningScreen("SM_GoToPrevScreen")
				return true
			end
		end
		
		if button == "Start" then
			-- If overlay is active, block Start input to prevent race conditions (e.g. while profile screen is opening)
			if _G.SSM_OverlayActive then return true end

			-- If the player is NOT joined, join them and open profile select
			if not GAMESTATE:IsSideJoined(pn) then
				GAMESTATE:JoinPlayer(pn)
				-- Lock input to prevent "Start" mashing from crashing the game before the screen opens
				_G.SSM_OverlayActive = true
				-- "OpenProfileSelectFromJoin" is handled by SortMenu/default.lua
				-- It sets flags for fast profile switching and opens ScreenSelectProfile on top
				MESSAGEMAN:Broadcast("OpenProfileSelectFromJoin")
				return true -- Consume input
			end

			-- Song Selection / Options Logic
			
			-- Check if we're on a group header or song
			local focused_item = SL.MusicWheel.State.items[SL.MusicWheel.State.focus_index]

			-- If on group header, try to toggle it
			if focused_item and focused_item.type == "group_header" then
				if wheel then wheel:playcommand("MW_ToggleGroup") end
				return true
			end

			-- If on a song, handle song selection with options prompt
			if focused_item and focused_item.type == "song" then
				local now = GetTimeSinceStart()

				-- Check if this is a second Start press within timeout
				if startPressTime and (now - startPressTime) < optionsPromptTimeout and startPressPlayer == pn then
					if SL and SL.MusicWheel and SL.MusicWheel.RememberSelectionContext then
						SL.MusicWheel.RememberSelectionContext()
					end
					-- Second press - go to options
					startPressTime = nil
					startPressPlayer = nil
					waitingForOptions = false

					-- Verify we have a valid song selected in GAMESTATE
					if GAMESTATE:GetCurrentSong() then
						-- Show "Entering Options..." and navigate to options
						if screen then
							-- Set PlayMode to Regular (prevents crash)
							GAMESTATE:SetCurrentPlayMode("PlayMode_Regular")

							MESSAGEMAN:Broadcast("ShowEnteringOptions")
							-- Queue transition on overlay (wait for "Entering Options" message)
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
					waitingForOptions = true

					-- Show "Press Start for Options" overlay
					MESSAGEMAN:Broadcast("ShowPressStartForOptions")

					-- Schedule timeout to go directly to gameplay
					if overlay then
						overlay:queuecommand("StartTimeout") -- This will fire GoToGameplay after 3s
					end
					return true
				end
			end
			
			-- Fallback
			return true 
		end
		
		-- Handle Select button
		if button == "Select" then
			BroadcastMessage("Select", pn)
		end


		-- Handle Sequences (Difficulty, Favorites)
		-- Update History
		local currentTime = GetTimeSinceStart()
		local seq = buttonSequence[pn]

		-- Clear old sequence if timeout expired
		if #seq > 0 and (currentTime - seq[#seq].time) > sequenceTimeout then
			buttonSequence[pn] = {}
			seq = buttonSequence[pn]
		end

		-- Add button to sequence
		table.insert(seq, {button = button, time = currentTime})

		-- 1. Toggle Favorite (Dynamic Sequence)
		if InputCodes.ToggleFavorite and InputCodes.ToggleFavorite.type == "sequence" then
			if IsSequenceSatisfied(InputCodes.ToggleFavorite.buttons, seq) then
				if wheel then wheel:playcommand("MW_ToggleFavorite", {PlayerNumber=pn}) end
				buttonSequence[pn] = {} -- Clear after success
				return true
			end
		end

		-- 2. Difficulty Change (Dynamic Sequence)
		-- Easier (e.g. Up, Up)
		if InputCodes.DifficultyEasier and InputCodes.DifficultyEasier.type == "sequence" then
			if IsSequenceSatisfied(InputCodes.DifficultyEasier.buttons, seq) then
				if wheel then wheel:playcommand("MW_DifficultyChange", {PlayerNumber=pn, Direction=-1}) end
				buttonSequence[pn] = {}
				return true
			end
		end
		
		-- Harder (e.g. Down, Down)
		if InputCodes.DifficultyHarder and InputCodes.DifficultyHarder.type == "sequence" then
			if IsSequenceSatisfied(InputCodes.DifficultyHarder.buttons, seq) then
				if wheel then wheel:playcommand("MW_DifficultyChange", {PlayerNumber=pn, Direction=1}) end
				buttonSequence[pn] = {}
				return true
			end
		end

		-- 3. Toggle Pattern Info (e.g. Select, Select)
		if InputCodes.TogglePatternInfo and InputCodes.TogglePatternInfo.type == "sequence" then
			if IsSequenceSatisfied(InputCodes.TogglePatternInfo.buttons, seq) then
				-- Broadcast CodeMessage to trigger the toggle in DensityGraph, ZarzobPanes, PlayerProfiles
				MESSAGEMAN:Broadcast("TogglePatternInfo", {PlayerNumber=pn})
				buttonSequence[pn] = {}
				return true
			end
		end

		-- Initial Scroll Press (Buffered)
		if button == "MenuLeft" or button == "MenuRight" then
			local dir = (button == "MenuLeft") and -1 or 1
			-- Buffer the input instead of executing immediately
			scrollQueue[pn] = {
				dir = dir,
				time = GetTimeSinceStart()
			}
			-- Do NOT update nextScrollTime yet, only on execution
		end
	end
	
	return false
end

-- Update function for continuous scrolling
local function Update(self)
	local now = GetTimeSinceStart()
	local wheel = GetMusicWheel()
	if not wheel then return end
	
	-- Stop scrolling if waiting for options
	if waitingForOptions then return end

	for pn in ivalues(GAMESTATE:GetHumanPlayers()) do
		
		-- Check Buffered Scroll (First Press)
		if scrollQueue[pn] then
			if now >= scrollQueue[pn].time + chordDetectionWindow then
				-- Window expired, no chord intercepted -> Execute
				local dir = scrollQueue[pn].dir
				if wheel then
					if dir == -1 then wheel:playcommand("MW_ScrollLeft", {PlayerNumber=pn})
					else wheel:playcommand("MW_ScrollRight", {PlayerNumber=pn}) end
				end
				nextScrollTime[pn] = now + initialScrollDelay
				scrollQueue[pn] = nil -- Consumed
			end
		end

		-- Only scroll if input is NOT redirected AND no pending single-tap buffer
		if not SCREENMAN:get_input_redirected(pn) and not scrollQueue[pn] then
			local leftHeld = heldButtons[pn]["MenuLeft"]
			local rightHeld = heldButtons[pn]["MenuRight"]
			
			-- Only scroll if exactly one direction is held
			if (leftHeld and not rightHeld) or (rightHeld and not leftHeld) then
				if now >= nextScrollTime[pn] then
					local dir = leftHeld and -1 or 1
					if dir == -1 then wheel:playcommand("MW_ScrollLeft", {PlayerNumber=pn})
					else wheel:playcommand("MW_ScrollRight", {PlayerNumber=pn}) end

					nextScrollTime[pn] = now + scrollInterval
				end
			end
		end
	end
end

return Def.ActorFrame{
	InitCommand=function(self)
		UpdateScrollInterval()
		self:SetUpdateFunction(Update)
		self:queuecommand("Capture")
	end,
	
	CaptureCommand=function(self)
		SCREENMAN:GetTopScreen():AddInputCallback(input)
	end
}
