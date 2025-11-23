-- Comprehensive Input Handler for ScreenSelectMusic
-- Restores functionality lost by switching to ScreenWithMenuElements
-- Reads codes from metrics.ini to preserve original bindings

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

local input = function(event)
	if not event.PlayerNumber or not event.GameButton then return false end
	
	local pn = event.PlayerNumber
	local button = event.GameButton
	local screen = SCREENMAN:GetTopScreen()
	local overlay = screen:GetChild("Overlay")
	
	-- Track button state
	if event.type == "InputEventType_FirstPress" then
		heldButtons[pn][button] = true
	elseif event.type == "InputEventType_Release" then
		heldButtons[pn][button] = nil
	end
	
	if event.type == "InputEventType_FirstPress" then
		
		-- Check for Sort Menu codes FIRST (before handling individual buttons)
		-- These are chords like "MenuLeft-MenuRight" or "Left-Right"
		for i = 1, 2 do
			local codeName = i == 1 and "SortList" or ("SortList" .. i)
			local code = GetCode(codeName)
			
			if code and code ~= "" and code ~= "false" then
				-- Check if this is a chord and if it's currently pressed
				if IsChordPressed(code, pn) then
					overlay:queuecommand("DirectInputToSortMenu")
					return true
				end
			end
		end
		
		-- Handle Back button
		if button == "Back" then
			-- If Event Mode is ON, Back triggers the Exit Prompt
			if PREFSMAN:GetPreference("EventMode") then
				BroadcastMessage("EscapeFromEventMode2", pn)
				return true
			else
				-- Normal navigation
				screen:SetNextScreenName(screen:GetPrevScreenName())
				screen:StartTransitioningScreen("SM_GoToPrevScreen")
				return true
			end
		end
		
		-- Handle Start button (for future use, e.g., song selection)
		if button == "Start" then
			BroadcastMessage("Start", pn)
			-- Don't consume start, let it pass through
		end
		
		-- Handle Select button
		if button == "Select" then
			BroadcastMessage("Select", pn)
		end
	end
	
	return false
end

return Def.ActorFrame{
	InitCommand=function(self)
		self:queuecommand("Capture")
	end,
	
	CaptureCommand=function(self)
		SCREENMAN:GetTopScreen():AddInputCallback(input)
	end
}
