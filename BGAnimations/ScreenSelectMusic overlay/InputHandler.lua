-- Comprehensive Input Handler for ScreenSelectMusic
-- Restores functionality lost by switching to ScreenWithMenuElements
-- Reads codes from metrics.ini to preserve original bindings

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

-- Check if a chord (simultaneous buttons) is being pressed
local function IsChordPressed(code, pn)
	-- Format: "Button1-Button2" means both pressed simultaneously
	if code:find("-") and not code:find("@") then
		local buttons = {}
		for button in code:gmatch("([^-]+)") do
			table.insert(buttons, button)
		end
		
		-- Check if all buttons in the chord are currently held
		for _, buttonName in ipairs(buttons) do
			if not heldButtons[pn][buttonName] then
				return false
			end
		end
		return true
	end
	return false
end


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
	
	-- Use square root curve to compress high speeds
	-- Formula: ItemsPerSec = sqrt(Speed) * 3
	local itemsPerSec = math.sqrt(speed) * 3
	scrollInterval = 1 / itemsPerSec
end

-- Track button sequences for difficulty changes/favorites
local buttonSequence = {
	[PLAYER_1] = {},
	[PLAYER_2] = {}
}
local sequenceTimeout = 0.5

-- Get the MusicWheel actor
local function GetMusicWheel()
	local screen = SCREENMAN:GetTopScreen()
	if screen then
		local overlay = screen:GetChild("Overlay")
		if overlay then
			return overlay:GetChild("MusicWheel")
		end
	end
	return nil
end

local input = function(event)
	if not event.PlayerNumber or not event.GameButton then return false end
	
	local pn = event.PlayerNumber
	local button = event.GameButton
	local screen = SCREENMAN:GetTopScreen()
	local overlay = screen:GetChild("Overlay")
	local wheel = GetMusicWheel()
	
	-- Track button state
	if event.type == "InputEventType_FirstPress" then
		heldButtons[pn][button] = true
	elseif event.type == "InputEventType_Release" then
		heldButtons[pn][button] = nil
	end
	
	-- Don't handle input if input is redirected (e.g. SortMenu is open or closing)
	if SCREENMAN:get_input_redirected(pn) then
		return false
	end

	if event.type == "InputEventType_FirstPress" then
		
		-- Check for Sort Menu codes FIRST (before handling individual buttons)
		for i = 1, 2 do
			local codeName = i == 1 and "SortList" or ("SortList" .. i)
			local code = GetCode(codeName)
			
			if code and code ~= "" and code ~= "false" then
				-- Check if this is a chord and if it's currently pressed
				if IsChordPressed(code, pn) then
					-- Only open if no other overlay is active
					if not _G.SSM_OverlayActive then
						_G.SSM_OverlayActive = true
						overlay:queuecommand("DirectInputToSortMenu")
					end
					return true
				end
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

			-- Normal Start behavior -> Delegate to MusicWheel
			if wheel then
				wheel:playcommand("MW_Start", {PlayerNumber=pn})
			end
			return true -- Consume start
		end
		
		-- Handle Select button
		if button == "Select" then
			BroadcastMessage("Select", pn)
		end


		-- Handle Difficulty Changes and Favorites (Up/Down sequences)
		if button == "MenuUp" or button == "MenuDown" then
			
			-- First check for ToggleGroup Chord (Up+Down)
			if heldButtons[pn]["MenuUp"] and heldButtons[pn]["MenuDown"] then
				if wheel then wheel:playcommand("MW_ToggleGroup") end
				return true
			end

			-- Check Sequences
			local currentTime = GetTimeSinceStart()
			local seq = buttonSequence[pn]

			-- Clear old sequence if timeout expired
			if #seq > 0 and (currentTime - seq[#seq].time) > sequenceTimeout then
				buttonSequence[pn] = {}
				seq = buttonSequence[pn]
			end

			-- Add button to sequence
			table.insert(seq, {button = button, time = currentTime})

			-- Check for favorites toggle sequence (Up,Down,Up,Down)
			if #seq >= 4 then
				if seq[#seq-3].button == "MenuUp" and 
				   seq[#seq-2].button == "MenuDown" and 
				   seq[#seq-1].button == "MenuUp" and 
				   seq[#seq].button == "MenuDown" then
					
					if wheel then wheel:playcommand("MW_ToggleFavorite", {PlayerNumber=pn}) end
					
					-- Clear sequence after processing
					buttonSequence[pn] = {}
					return true
				end
			end

			-- Check for difficulty change sequences (need 2 of the same button)
			if #seq >= 2 and seq[#seq].button == seq[#seq-1].button then
				local dir = (button == "MenuUp") and -1 or 1 -- Up = Easier (- index), Down = Harder (+ index)
				if wheel then wheel:playcommand("MW_DifficultyChange", {PlayerNumber=pn, Direction=dir}) end

				-- Clear sequence after processing
				buttonSequence[pn] = {}
				return true
			end
		end

		-- Initial Scroll Press
		if button == "MenuLeft" or button == "MenuRight" then
			local dir = (button == "MenuLeft") and -1 or 1
			if wheel then
				if dir == -1 then wheel:playcommand("MW_ScrollLeft", {PlayerNumber=pn})
				else wheel:playcommand("MW_ScrollRight", {PlayerNumber=pn}) end
			end
			nextScrollTime[pn] = GetTimeSinceStart() + initialScrollDelay
		end
	end
	
	return false
end

-- Update function for continuous scrolling
local function Update(self)
	local now = GetTimeSinceStart()
	local wheel = GetMusicWheel()
	if not wheel then return end

	for pn in ivalues(GAMESTATE:GetHumanPlayers()) do
		-- Only scroll if input is NOT redirected
		if not SCREENMAN:get_input_redirected(pn) then
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
