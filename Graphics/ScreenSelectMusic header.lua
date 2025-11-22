local bmt_actor
local ses_actor

-- locals for the below commented out code

-- local curScreen = Var "LoadingScreen"
-- local curStage = GAMESTATE:GetCurrentStage()
-- local curStageIndex = GAMESTATE:GetCurrentStageIndex()
-- -----------------------------------------------------------------------

local hours, mins, secs
local hmmss = "%d:%02d:%02d"

-- prefer the engine's SecondsToHMMSS()
-- but define it ourselves if it isn't provided by this version of SM5
local SecondsToHMMSS = SecondsToHMMSS or function(s)
	-- native floor division sounds nice but isn't available in Lua 5.1
	hours = math.floor(s/3600)
	mins  = math.floor((s % 3600) / 60)
	secs  = s - (hours * 3600) - (mins * 60)
	return hmmss:format(hours, mins, secs)
end

local UpdateTimer = function(af, dt)
	local seconds = GetTimeSinceStart() - SL.Global.TimeAtSessionStart
	local totalTime = 0
	local anyPlayer = "P1"
	if #SL["P1"].Stages.Stats == 0 then anyPlayer = "P2" end
	for i,stats in pairs( SL[anyPlayer].Stages.Stats ) do
		totalTime = totalTime + (stats and stats.duration or 0)
	end

	-- if this game session is less than 1 hour in duration so far
	if seconds < 3600 then
		bmt_actor:settext( SecondsToMMSS(seconds) )

	-- somewhere between 1 and 10 hours
	elseif seconds >= 3600 and seconds < 36000 then
		bmt_actor:settext( SecondsToHMMSS(seconds) )

	-- in it for the long haul
	else
		bmt_actor:settext( SecondsToHHMMSS(seconds) )
	end
	
	if totalTime ~= nil then
		-- if this game session is less than 1 hour in duration so far
		if totalTime < 3600 then
			ses_actor:settext( SecondsToMMSS(totalTime) )

		-- somewhere between 1 and 10 hours
		elseif totalTime >= 3600 and totalTime < 36000 then
			ses_actor:settext( SecondsToHMMSS(totalTime) )

		-- in it for the long haul
		else
			ses_actor:settext( SecondsToHHMMSS(totalTime) )
		end
	end
end

-- -----------------------------------------------------------------------

local af = Def.ActorFrame{ OffCommand=function(self) self:linear(0.1):diffusealpha(0) end }

-- only add this InitCommand to the main ActorFrame in EventMode
if PREFSMAN:GetPreference("EventMode") then
	af.InitCommand=function(self)
		-- TimeAtSessionStart will be reset to nil between game sessions
		-- thus, if it's currently nil, we're loading ScreenSelectMusic
		-- for the first time this particular game session
		if SL.Global.TimeAtSessionStart == nil then
			SL.Global.TimeAtSessionStart = GetTimeSinceStart()
		end

		self:SetUpdateFunction( UpdateTimer )
	end
end


-- generic header elements (background Def.Quad, left-aligned screen name)
af[#af+1] = LoadActor( THEME:GetPathG("", "_header.lua") )

-- centered text
-- session timer in EventMode
if PREFSMAN:GetPreference("EventMode") then

	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " numbers")..{
		Name="Session Timer",
		InitCommand=function(self)
			bmt_actor = self
			self:zoom( 0.36 )
			self:y( 3.5 / self:GetZoom() )
			self:diffusealpha(0):x(_screen.cx)
		end,
		OnCommand=function(self)
			self:sleep(0.1):decelerate(0.33):diffusealpha(1)
		end,
	}
	
	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " numbers")..{
		Name="Play Timer",
		InitCommand=function(self)
			ses_actor = self
			self:zoom( 0.36 )
			self:y( 3.5 / self:GetZoom() )
			self:diffusealpha(0):x(_screen.cx + 200)
		end,
		OnCommand=function(self)
			self:sleep(0.1):decelerate(0.33):diffusealpha(1)
		end,
	}

-- stage number when not EventMode (see ScreenSelectMusic StageDisplay.lua for current implementation)
else
	-- FIXME: original code here doesn't work
	-- 		  SSM_Header_StageText() ./Scripts/SL-SelectMusicHelpers.lua doesn't work. This is an upstream issue, see comments there for what's not working.

	-- af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Header")..{
	-- 	Name="Stage Number",
	-- 	Text=SSM_Header_StageText(),
	-- 	InitCommand=function(self)
	-- 		self:zoom( SL_WideScale(0.5, 0.6) )
	-- 		self:y( SL_WideScale(7.5, 9) / self:GetZoom() )
	-- 		self:diffusealpha(0):x(_screen.cx)
	-- 	end,
	-- 	OnCommand=function(self)
	-- 		self:sleep(0.1):decelerate(0.33):diffusealpha(1)
	-- 	end,
	-- }

	-- my attempt to recreate the stage counter from Zmod's Fork
	-- this code wasn't properly displaying when it was the final stage (with song length limits enabled), so it's best to just repurpose Zmod's stage counter instead

	-- af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Header")..{
	-- 	Name="Stage Number",
	-- 	Text="Testing3",
	-- 	-- Text=SSM_Header_StageText(),
	-- 	InitCommand=function(self)
	-- 		self:zoom( SL_WideScale(0.5, 0.6) )
	-- 		self:y( SL_WideScale(7.5, 9) / self:GetZoom() )
	-- 		self:diffusealpha(0):x(_screen.cx)
	-- 			-- if the continue system is enabled, don't worry about determining "Final Stage"
	-- 			-- if ThemePrefs.Get("NumberOfContinuesAllowed") > 0 then
	-- 			-- 	self:settext(THEME:GetString("Stage", "Stage") .. " " .. tostring(SL.Global.Stages.PlayedThisGame + 1))
	-- 			-- else
	-- 			-- 	self:settext(THEME:GetString("Stage", "Stage") .. " " .. tostring(SL.Global.Stages.PlayedThisGame + 1))
	-- 			-- end
	-- 	end,
	-- 	BeginCommand=function(self)
	-- 		local top = SCREENMAN:GetTopScreen()
	-- 		if top then
	-- 			if not string.find(top:GetName(),"ScreenEvaluation") then
	-- 				curStageIndex = curStageIndex + 1
	-- 			end
	-- 		end
	-- 		self:playcommand("Set")
	-- 	end;
	-- 	OnCommand=function(self)
	-- 		self:sleep(0.1):decelerate(0.33):diffusealpha(1)
	-- 	end,
	-- 	SetCommand=function(self)
	-- 		local song = GAMESTATE:GetCurrentSong()
	-- 		local Duration = song:GetLastSecond()
	-- 		local DurationWithRate = Duration / SL.Global.ActiveModifiers.MusicRate

	-- 		local LongCutoff = PREFSMAN:GetPreference("LongVerSongSeconds")
	-- 		local MarathonCutoff = PREFSMAN:GetPreference("MarathonVerSongSeconds")

	-- 		local IsMarathon = (DurationWithRate/MarathonCutoff > 1)
	-- 		local IsLong 	 = (DurationWithRate/LongCutoff > 1)

	-- 		local SongCost = (IsMarathon and 3) or (IsLong and 2) or 1
	-- 		if GAMESTATE:GetCurrentCourse() then
	-- 			self:settext( curStageIndex+1 .. " / " .. GAMESTATE:GetCurrentCourse():GetEstimatedNumStages() )
	-- 		else
	-- 			if SL.Global.Stages.PlayedThisGame + SongCost >= PREFSMAN:GetPreference("SongsPerPlay") then
	-- 				self:settext(THEME:GetString("Stage", "Final"))
	-- 			else
	-- 				self:settext(THEME:GetString("Stage", "Stage") .. " " .. tostring(SL.Global.Stages.PlayedThisGame + SongCost))
	-- 			end
	-- 		end
	-- 	end
	-- }

end

-- "ITG" or "FA+"; aligned to right of screen
af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Header")..{
	Name="GameModeText",
	Text=THEME:GetString("ScreenSelectPlayMode", SL.Global.GameMode),
	InitCommand=function(self)
		self:diffusealpha(0):halign(1):y(15)
		self:zoom( 0.6 )

		-- move the GameMode text further left if MenuTimer is enabled
		if PREFSMAN:GetPreference("MenuTimer") then
			self:x(_screen.w - 125)
		else
			self:x(_screen.w - 62)
		end
	end,
	OnCommand=function(self)
		self:sleep(0.1):decelerate(0.33):diffusealpha(1)
	end,
	SLGameModeChangedMessageCommand=function(self)
		self:settext(THEME:GetString("ScreenSelectPlayMode", SL.Global.GameMode))
	end
}

-- P1 pad
af[#af+1] = LoadActor( THEME:GetPathB("ScreenSelectStyle", "underlay/pad.lua"), {nil, nil, 1, nil} )..{
	InitCommand=function(self)
		self:x(_screen.w - (PREFSMAN:GetPreference("MenuTimer") and 105 or 41))
		self:y( 23.5 ):zoom(0.24)
		self:playcommand("Set", {Player=PLAYER_1})
	end,
	PlayerJoinedMessageCommand=function(self, params)
		if params.Player == PLAYER_1 then
			self:playcommand("Set", {Player=PLAYER_1})
		end
	end
}

-- P2 pad
af[#af+1] = LoadActor( THEME:GetPathB("ScreenSelectStyle", "underlay/pad.lua"), {nil, nil, 2, nil} )..{
	InitCommand=function(self)
		self:x(_screen.w - (PREFSMAN:GetPreference("MenuTimer") and 81 or 17))
		self:y( 23.5 ):zoom(0.24)
		self:playcommand("Set", {Player=PLAYER_2})
	end,
	PlayerJoinedMessageCommand=function(self, params)
		if params.Player == PLAYER_2 then
			self:playcommand("Set", {Player=PLAYER_2})
		end
	end
}

return af