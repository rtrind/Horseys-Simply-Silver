local Players = GAMESTATE:GetHumanPlayers()
local NumPanes = 10

local InputHandler = nil
local EventOverlayInputHandler = nil

if ThemePrefs.Get("WriteCustomScores") then
	WriteScores()
end

local t = Def.ActorFrame{Name="ScreenEval Common"}

t.OnCommand=function(self)
	PROFILEMAN:SaveMachineProfile()
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

-- text to display BPM range (and ratemod if ~= 1.0) and song length immediately
-- under the banner
t[#t+1] = LoadActor("./Shared/SongFeatures.lua")

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

	-- Generate the .itl file for the player.
	-- When the event isn't active, this actor is nil.
	t[#t+1] = LoadActor("./PerPlayer/ItlFile.lua", player)

	-- Generate the .rpg file for the player to keep track of best rate mod on the songwheel
	-- When the event isn't active, this actor is nil.
	t[#t+1] = LoadActor("./PerPlayer/RpgRatemod.lua", player)
	
	
end

-- -----------------------------------------------------------------------
-- Then load the Panes.

t[#t+1] = LoadActor("./Panes/default.lua", NumPanes)

-- code for handling score vocalization
t[#t+1] = LoadActor("./ScoreVocalization.lua")
-- -----------------------------------------------------------------------

-- The actor that will automatically upload scores to GrooveStats.
-- This is only added in "dance" mode and if the service is available.
-- Since this actor also spawns the event overlay it must go on top of everything else
t[#t+1] = LoadActor("./Shared/AutoSubmitScore.lua")

return t
