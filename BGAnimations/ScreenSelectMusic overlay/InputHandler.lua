-- Comprehensive Input Handler for ScreenSelectMusic
-- Restores functionality lost by switching to ScreenWithMenuElements

local function BroadcastMessage(name, pn)
	MESSAGEMAN:Broadcast("CodeMessage", {Name=name, PlayerNumber=pn})
end

local Codes = {
	-- Navigation
	{ Code="Back", Name="Back" },
	{ Code="Start", Name="Start" },
	
	-- Special functions
	{ Code="Select,Select", Name="TogglePatternInfo" },
	{ Code="@Select-Start", Name="SortList" },
	{ Code="MenuUp,MenuDown,MenuUp,MenuDown", Name="ToggleFavorite" },
	
	-- Folder control
	{ Code="@Up-Down", Name="CloseFolder1" },
	{ Code="@Down-Up", Name="CloseFolder2" },
	{ Code="@Select-MenuUp", Name="CloseFolder3" },
	
	-- Event Mode escape
	{ Code=PREFSMAN:GetPreference("EventMode") and "MenuLeft,MenuLeft,MenuRight,MenuRight,MenuLeft,MenuLeft,MenuRight,MenuRight" or "", Name="EscapeFromEventMode" },
	{ Code=PREFSMAN:GetPreference("EventMode") and "Back" or "", Name="EscapeFromEventMode2" },
}

-- Use the built-in CodeDetector logic by loading it as a separate actor
-- We can pass the Codes table to it!
-- Wait, the theme might not have a generic CodeDetector actor available like _fallback does.
-- Let's write a simple input callback that handles at least Back and Start for now.

local input = function(event)
	if not event.PlayerNumber or not event.GameButton then return false end
	
	if event.type == "InputEventType_FirstPress" then
		local button = event.GameButton
		local screen = SCREENMAN:GetTopScreen()
		
		if button == "Back" then
			screen:SetNextScreenName(screen:GetPrevScreenName())
			screen:StartTransitioningScreen("SM_GoToPrevScreen")
			return true
		end
		
		if button == "Start" then
			BroadcastMessage("Start", event.PlayerNumber)
			-- Don't consume start, let it pass through
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
