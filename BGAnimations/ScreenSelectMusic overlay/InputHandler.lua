-- Comprehensive Input Handler for ScreenSelectMusic
-- Restores functionality lost by switching to ScreenWithMenuElements

local function BroadcastMessage(name, pn)
	MESSAGEMAN:Broadcast("CodeMessage", {Name=name, PlayerNumber=pn})
end

local input = function(event)
	if not event.PlayerNumber or not event.GameButton then return false end
	
	local pn = event.PlayerNumber
	
	if event.type == "InputEventType_FirstPress" then
		local button = event.GameButton
		local screen = SCREENMAN:GetTopScreen()
		local overlay = screen:GetChild("Overlay")
		
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
		
		-- Handle Start button
		if button == "Start" then
			-- Check for Sort Menu (Select + Start)
			-- We check if Select is currently being held by the same player
			if INPUTMAPPER:IsBeingPressed("Select", pn) then
				overlay:queuecommand("DirectInputToSortMenu")
				return true
			end
			
			BroadcastMessage("Start", pn)
			-- Don't consume start, let it pass through
		end
		
		-- Handle Select button
		if button == "Select" then
			-- Check for Toggle Pattern Info (Select, Select)
			-- We'd need a timer for this, skipping for now unless requested
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
	end,
	
	-- Listen for the DirectInputToSortMenu command to ensure the overlay handles it
	-- (Though the input handler triggers it on the overlay directly)
}
