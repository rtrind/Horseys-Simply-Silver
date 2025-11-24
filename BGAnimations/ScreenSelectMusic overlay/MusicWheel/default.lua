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
	
	-- Don't consume MenuLeft/MenuRight if both are pressed (SortMenu chord)
	if event.type == "InputEventType_FirstPress" then
		if (button == "MenuLeft" or button == "MenuRight") and 
		   heldButtons[pn]["MenuLeft"] and heldButtons[pn]["MenuRight"] then
			-- Both buttons pressed - let it pass through to open SortMenu
			return false
		end
	end
	
	-- Handle FirstPress for Start button (toggle group)
	if event.type == "InputEventType_FirstPress" then
		if event.GameButton == "Start" then
			-- Try to toggle group (only works if on group header)
			if SL.MusicWheel.ToggleGroup() then
				-- Group was toggled, update wheel display
				wheel:set_info_set(SL.MusicWheel.State.items, SL.MusicWheel.State.focus_index)
				return true
			end
			-- If not on group header, let Start pass through (for song selection)
			return false
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
				MESSAGEMAN:Broadcast("CurrentSongChanged")
			elseif focused_group then
				-- Clear current song when on group header
				GAMESTATE:SetCurrentSong(nil)
				MESSAGEMAN:Broadcast("CurrentSongChanged")
				-- Broadcast group focus for banner display
				MESSAGEMAN:Broadcast("FocusedGroupChanged", {group = focused_group})
			end
			return true
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
		
		-- Initialize wheel data
		SL.MusicWheel.Initialize()
		
		-- Set initial wheel data
		wheel:set_info_set(SL.MusicWheel.State.items, SL.MusicWheel.State.focus_index)
	end,
	
	OnCommand = function(self)
		-- Register input handler (do this in OnCommand when screen is ready)
		local screen = SCREENMAN:GetTopScreen()
		if screen then
			screen:AddInputCallback(input)
		end
		
		-- Ensure initial selection is broadcast to UI (Banner, etc.)
		-- We do this in OnCommand because InitCommand messages might be missed
		local focused_song = SL.MusicWheel.GetFocusedSong()
		local focused_group = SL.MusicWheel.GetFocusedGroup()
		
		if focused_song then
			GAMESTATE:SetCurrentSong(focused_song)
			MESSAGEMAN:Broadcast("CurrentSongChanged")
		elseif focused_group then
			GAMESTATE:SetCurrentSong(nil)
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
		end
	end,
	
	-- Add the wheel actors (this returns an ActorFrame from sick_wheel)
	wheel:create_actors("WheelContainer", num_items, WheelItem, wheel_x, wheel_y)
}

return t
