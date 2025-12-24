local Players = GAMESTATE:GetHumanPlayers()
local NumPanes = 6

-- Reference to actor pool for memory management
local Pool = SL and SL.ActorPool or nil

local InputHandler = nil
local EventOverlayInputHandler = nil

if ThemePrefs.Get("WriteCustomScores") then
	WriteScores()
end

-- Save last played song/difficulty for each player
-- This is done here (instead of ScreenGameplay out.lua) because force-failing
-- by holding Start may not trigger the OffCommand in gameplay
local song = GAMESTATE:GetCurrentSong()
if song and SL.MusicWheel and SL.MusicWheel.SaveLastPlayed then
	for player in ivalues(Players) do
		local steps = GAMESTATE:GetCurrentSteps(player)
		local difficulty = steps and steps:GetDifficulty() or nil
		SL.MusicWheel.SaveLastPlayed(player, song, difficulty)
	end
end

local t = Def.ActorFrame{Name="ScreenEval Common"}

-- add a lua-based InputCallback to this screen so that we can navigate
-- through multiple panes of information; pass a reference to this ActorFrame
-- and the number of panes there are to InputHandler.lua
t.InitCommand=function(self)
	-- Force garbage collection on screen enter to reclaim memory from Gameplay
	if Pool then Pool.OnScreenEnter("ScreenEvaluation") end
end
t.OnCommand=function(self)
	InputHandler = LoadActor("./InputHandler.lua", {self, NumPanes})
	EventOverlayInputHandler = LoadActor("./Shared/EventInputHandler.lua")
	SCREENMAN:GetTopScreen():AddInputCallback(InputHandler)
	PROFILEMAN:SaveMachineProfile()
end
t.OffCommand=function(self)
	-- Clean up on screen exit
	if Pool then Pool.OnScreenExit("ScreenEvaluation") end
end
t.DirectInputToEngineCommand=function(self)
	SCREENMAN:GetTopScreen():RemoveInputCallback(EventOverlayInputHandler)
	SCREENMAN:GetTopScreen():AddInputCallback(InputHandler)

	for player in ivalues(PlayerNumber) do
		SCREENMAN:set_input_redirected(player, false)
	end
end
t.DirectInputToEventOverlayHandlerCommand=function(self)
	SCREENMAN:GetTopScreen():RemoveInputCallback(InputHandler)
	SCREENMAN:GetTopScreen():AddInputCallback(EventOverlayInputHandler)

	for player in ivalues(PlayerNumber) do
		SCREENMAN:set_input_redirected(player, true)
	end
end

-- -----------------------------------------------------------------------
-- First, add actors that would be the same whether 1 or 2 players are joined.

-- code for triggering a screenshot and animating a "screenshot" texture
t[#t+1] = LoadActor("./Shared/ScreenshotHandler.lua")

-- code for immediately retrying the song that was just played
t[#t+1] = LoadActor("./Shared/RestartHandler.lua")

-- song background
t[#t+1] = LoadActor("./Shared/Background.lua")

-- the title of the song and its graphical banner, if there is one
t[#t+1] = LoadActor("./Shared/TitleAndBanner.lua")

-- store some attributes of this playthrough of this song in the global SL table
-- for later retrieval on ScreenEvaluationSummary
t[#t+1] = LoadActor("./Shared/GlobalStorage.lua")

-- -----------------------------------------------------------------------
-- Then, load player-specific actors.

for player in ivalues(Players) do

	-- store player stats for later retrieval on EvaluationSummary and NameEntryTraditional
	-- this doesn't draw anything to the screen, it just runs some code
	t[#t+1] = LoadActor("./PerPlayer/Storage.lua", player)

	-- the per-player upper half of ScreenEvaluation, including: letter grade, nice
	-- stepartist, difficulty text, difficulty meter, machine/personal HighScore text
	t[#t+1] = LoadActor("./PerPlayer/Upper/default.lua", player)

	-- the per-player lower half of ScreenEvaluation, including:
	-- judgment scatterplot, modifier list, disqualified text
	t[#t+1] = LoadActor("./PerPlayer/Lower/default.lua", player)

	-- Save Ghost Data if player has improved their score
	t[#t+1] = LoadActor("./PerPlayer/SaveGhostData.lua", player)
end

-- -----------------------------------------------------------------------
-- Then load the Panes.

t[#t+1] = LoadActor("./Panes/default.lua", NumPanes)

-- -----------------------------------------------------------------------

return t
