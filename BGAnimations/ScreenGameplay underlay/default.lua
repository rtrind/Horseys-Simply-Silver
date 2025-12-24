-- if the MenuTimer is enabled, we should reset SSM's MenuTimer now that we've reached Gameplay
if PREFSMAN:GetPreference("MenuTimer") then
	SL.Global.MenuTimer.ScreenSelectMusic = ThemePrefs.Get("ScreenSelectMusicMenuTimer")
end

-- Reference to actor pool for memory management
local Pool = SL and SL.ActorPool or nil

local Players = GAMESTATE:GetHumanPlayers()
local holdingCtrl = false

local RestartHandler = function(event)
	if not event then return end

	if event.type == "InputEventType_FirstPress" then
		if event.DeviceInput.button == "DeviceButton_left ctrl" then
			holdingCtrl = true
		elseif event.DeviceInput.button == "DeviceButton_r" then
			if holdingCtrl then
				SCREENMAN:GetTopScreen():SetPrevScreenName("ScreenGameplay"):SetNextScreenName("ScreenGameplay"):begin_backing_out()
			end
		end
	elseif event.type == "InputEventType_Release" then
		if event.DeviceInput.button == "DeviceButton_left ctrl" then
			holdingCtrl = false
		end
	end
end

local t = Def.ActorFrame{
	Name="GameplayUnderlay",
	InitCommand=function(self)
		-- Force garbage collection on screen enter to reclaim memory from SSM
		if Pool then Pool.OnScreenEnter("ScreenGameplay") end
	end,
	OnCommand=function(self)
		if ThemePrefs.Get("KeyboardFeatures") and PREFSMAN:GetPreference("EventMode")  then
			SCREENMAN:GetTopScreen():AddInputCallback(RestartHandler)
		end
	end,
	OffCommand=function(self)
		-- Clean up on screen exit
		if Pool then Pool.OnScreenExit("ScreenGameplay") end
	end
}

for player in ivalues(Players) do
	if not SL[ToEnumShortString(player)].ActiveModifiers.BreakUI then
		t[#t+1] = LoadActor("./PerPlayer/Danger.lua", player)
		t[#t+1] = LoadActor("./PerPlayer/StepStatistics/default.lua", player)
		t[#t+1] = LoadActor("./PerPlayer/BackgroundFilter.lua", player)
		t[#t+1] = LoadActor("./PerPlayer/nice.lua", player)
	end
end

-- UI elements shared by both players
t[#t+1] = LoadActor("./Shared/VersusStepStatistics.lua")
t[#t+1] = LoadActor("./Shared/Header.lua")
t[#t+1] = LoadActor("./Shared/SongInfoBar.lua") -- song title and progress bar

-- per-player UI elements
for player in ivalues(Players) do
	t[#t+1] = LoadActor("./PerPlayer/UpperNPSGraph.lua", player)
	t[#t+1] = LoadActor("./PerPlayer/Score.lua", player)
	t[#t+1] = LoadActor("./PerPlayer/DifficultyMeter.lua", player)
	t[#t+1] = LoadActor("./PerPlayer/LifeMeter/default.lua", player)
	t[#t+1] = LoadActor("./PerPlayer/TargetScore/default.lua", player)

	-- All NoteField specific actors are contained in this file.
	t[#t+1] = LoadActor("./PerPlayer/NoteField/default.lua", player)
end

-- add to the ActorFrame last; overlapped by StepStatistics otherwise
t[#t+1] = LoadActor("./Shared/BPMDisplay.lua")

return t
