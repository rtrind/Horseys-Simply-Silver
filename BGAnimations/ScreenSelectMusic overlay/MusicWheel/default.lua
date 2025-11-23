-- MusicWheel/default.lua
-- Main wheel container using sick_wheel framework
-- Phase 1: Basic scrollable wheel with songs and groups

-- Load the WheelItem metatable
local WheelItem = LoadActor("WheelItem.lua")

-- Create sick_wheel instance
local wheel = setmetatable({}, sick_wheel_mt)

-- Wheel configuration
local num_items = 11  -- 9 visible + 1 above + 1 below
-- Position wheel on left side of screen, vertically centered
local wheel_x = SCREEN_CENTER_X - 200  -- Slightly more left
local wheel_y = SCREEN_CENTER_Y - 20   -- Slightly higher, more centered

-- ============================================================================
-- Input Handler
-- ============================================================================

local function input(event)
	if not event or not event.PlayerNumber or not event.button then
		return false
	end
	
	-- Only handle if wheel is active
	if not wheel or not wheel.container then
		return false
	end
	
	-- Handle both FirstPress and Repeat for continuous scrolling
	if event.type == "InputEventType_FirstPress" or event.type == "InputEventType_Repeat" then
		-- MenuLeft - Scroll up (previous song)
		if event.GameButton == "MenuLeft" then
			SL.MusicWheel.Scroll(-1)
			
			-- Update wheel display
			wheel:scroll_by_amount(-1)
			
			-- Update GAMESTATE with focused song
			local focused_song = SL.MusicWheel.GetFocusedSong()
			if focused_song then
				GAMESTATE:SetCurrentSong(focused_song)
				MESSAGEMAN:Broadcast("CurrentSongChanged")
			end
			
			return true
		
		-- MenuRight - Scroll down (next song)
		elseif event.GameButton == "MenuRight" then
			SL.MusicWheel.Scroll(1)
			
			-- Update wheel display
			wheel:scroll_by_amount(1)
			
			-- Update GAMESTATE with focused song
			local focused_song = SL.MusicWheel.GetFocusedSong()
			if focused_song then
				GAMESTATE:SetCurrentSong(focused_song)
				MESSAGEMAN:Broadcast("CurrentSongChanged")
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
	
	-- Debug: Print wheel state on Select+Start
	CodeMessageCommand = function(self, params)
		if params.Name == "SortList" then
			SL.MusicWheel.DebugPrintState()
		end
	end,
	
	-- Add the wheel actors (this returns an ActorFrame from sick_wheel)
	wheel:create_actors("WheelContainer", num_items, WheelItem, wheel_x, wheel_y)
}

return t
