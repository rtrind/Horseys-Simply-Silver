-- Ensure MusicWheel is initialized and GAMESTATE has steps BEFORE loading any actors
-- This prevents NoteField warnings about missing columns/steps
if SL.MusicWheel then
	SL.MusicWheel.Initialize()
end

local af = Def.ActorFrame{
	-- GameplayReloadCheck is a kludgy global variable used in ScreenGameplay in.lua to check
	-- if ScreenGameplay is being entered "properly" or being reloaded by a scripted mod-chart.
	-- If we're here in SelectMusic, set GameplayReloadCheck to false, signifying that the next
	-- time ScreenGameplay loads, it should have a properly animated entrance.
	InitCommand=function(self)
		-- Clear the GetLamp cache to ensure fresh data
		if WheelHelpers.ClearCache then
			WheelHelpers.ClearCache()
		end

		SL.Global.GameplayReloadCheck = false

		-- reset song start time here in case player force-escaped
		start_time = -1

		-- While other SM versions don't need this, Outfox resets the
		-- the music rate to 1 between songs, but we want to be using
		-- the preselected music rate.
		local songOptions = GAMESTATE:GetSongOptionsObject("ModsLevel_Preferred")
		songOptions:MusicRate(SL.Global.ActiveModifiers.MusicRate)

		-- Note: Last played song is now handled by SL.MusicWheel.Initialize()
		-- which is called at the top of this file before actors are loaded.
		-- It uses profile's GetLastPlayedSong(), session data, or falls back
		-- to a random song from ITG-Mode-DefaultSongs.txt
	end,


	SSM_RequestReloadMessageCommand=function(self, params)
		-- Defer one frame to ensure we're still on the profile screen as top
		self:sleep(0.01):queuecommand("DoReload")
	end,

    DoReloadCommand=function(self, params)
		-- For some reason we cannot reload the screen after a profile switch,
		-- so we have to wait until ScreenSelectMusic is the top screen and
		-- no other screen is on top of it. Then reload the entire screen...
		local s = SCREENMAN:GetTopScreen()
		if s then
			SM("Reloading screen...")
			s:SetNextScreenName("ScreenReloadSSM")
			s:StartTransitioningScreen("SM_GoToNextScreen")
		end
	end,

	GoToOptionsCommand = function(self)
		local screen = SCREENMAN:GetTopScreen()
		if screen then
			screen:SetNextScreenName("ScreenPlayerOptions")
			screen:StartTransitioningScreen("SM_GoToNextScreen")
		end
	end,

	-- ---------------------------------------------------
	--  first, load files that contain no visual elements, just code that needs to run

	-- MenuTimer code for preserving SSM's timer value when going
	-- from SSM to a different screen and back to SSM (i.e. returning from PlayerOptions).
	LoadActor("./PreserveMenuTimer.lua"),
	-- Apply player modifiers from profile
	LoadActor("./PlayerModifiers.lua"),
	-- Custom Input Handler for ScreenWithMenuElements
	LoadActor("./InputHandler.lua"),

	-- ---------------------------------------------------
	-- next, load visual elements; the order of these matters
	-- i.e. content in PerPlayer/Over needs to draw on top of content from PerPlayer/Under

	LoadActor("./NotefieldPreview.lua"),

	-- Custom Lua Music Wheel (Phase 1)
	LoadActor("./MusicWheel/default.lua"),

	-- number of steps, jumps, holds, etc., and high scores associated with the current stepchart
	LoadActor("./PaneDisplay.lua"),

	-- elements we need two of (one for each player) that draw underneath the StepsDisplayList
	-- this includes the stepartist boxes, the density graph, and the cursors.
	LoadActor("./PerPlayer/default.lua"),

	-- Song's Musical Artist, BPM, Duration
	LoadActor("./SongDescription/SongDescription.lua"),

	-- Banner Art
	LoadActor("./Banner.lua"),

	-- The grid for the difficulty picker
	LoadActor("./StepsDisplayList/default.lua"),

	-- ---------------------------------------------------
	-- finally, load the overlay used for sorting the MusicWheel (and more), hidden by default
	LoadActor("./SortMenu/default.lua"),
	-- a Test Input overlay can (maybe) be accessed from the SortMenu
	LoadActor("./TestInput.lua"),

	-- The GrooveStats leaderboard that can (maybe) be accessed from the SortMenu
	-- This is only added in "dance" mode and if the service is available.
	LoadActor("./Leaderboard.lua"),

	-- a yes/no prompt overlay for backing out of SelectMusic when in EventMode can be
	-- activated via "CodeEscapeFromEventMode" under [ScreenSelectMusic] in Metrics.ini
	LoadActor("./EscapeFromEventMode.lua"),

	LoadActor("./SongSearch/default.lua"),


	LoadActor("./footer.lua"),

	-- Options prompt overlay (Defined inline to ensure loading)
	Def.ActorFrame{
		Name="StartPrompt",
		InitCommand=function(self) 
			self:draworder(500)
		end,

		-- Catch the message at the frame level
		ShowPressStartForOptionsMessageCommand=function(self)
			self:GetChild("Dim"):playcommand("Show")
			self:GetChild("Text"):playcommand("Show")
		end,

		HidePressStartForOptionsMessageCommand=function(self)
			self:GetChild("Dim"):playcommand("Hide")
			self:GetChild("Text"):playcommand("Hide")
		end,

		ShowEnteringOptionsMessageCommand=function(self)
			self:GetChild("Text"):playcommand("EnterOptions")
		end,

		-- Background dim
		Def.Quad{
			Name="Dim",
			InitCommand=function(self) self:FullScreen():diffuse(0,0,0,0) end,
			ShowCommand=function(self) self:diffusealpha(0.7) end, -- Darker (70%)
			HideCommand=function(self) self:diffusealpha(0) end
		},

		-- Text prompt
		LoadFont(ThemePrefs.Get("ThemeFont") .. " Bold")..{
			Name="Text",
			Text=THEME:GetString("ScreenSelectMusic", "Press Start for Options"),
			InitCommand=function(self) 
				self:visible(false):Center():zoom(0.75):draworder(501)
			end,
			ShowCommand=function(self) 
				-- Slower pulse (1.0s period)
				self:visible(true):diffusealpha(1):pulse():effectmagnitude(1,1.1,1):effectperiod(1.0)
			end,
			HideCommand=function(self) self:visible(false):stopeffect() end,
			EnterOptionsCommand=function(self) self:visible(true):settext(THEME:GetString("ScreenSelectMusic", "Entering Options...")):stopeffect() end
		}
	},

	-- Handle Start button timeout for going directly to gameplay
	Def.ActorFrame{
		Name="StartTimeoutHandler",
		StartTimeoutCommand=function(self)
			-- Wait for the timeout period (3.0 seconds)
			self:sleep(3.0):queuecommand("FadeToBlack")
		end,
		FadeToBlackCommand=function(self)
			-- Fade in the black transition quad (prompt will naturally disappear)
			self:GetParent():GetChild("TransitionQuad"):playcommand("FadeIn")

			-- Wait for fade then go to gameplay
			self:sleep(0.5):queuecommand("GoToGameplay")
		end,
		GoToGameplayCommand=function(self)
			-- Verify we have a valid song selected in GAMESTATE
			if GAMESTATE:GetCurrentSong() then
				-- Remember the selection context (for restoring <Favorites> after gameplay)
				if SL and SL.MusicWheel and SL.MusicWheel.RememberSelectionContext then
					SL.MusicWheel.RememberSelectionContext()
				end
				
				-- Set PlayMode to Regular (prevents crash)
				GAMESTATE:SetCurrentPlayMode("PlayMode_Regular")

				-- Navigate directly to gameplay (skip options)
				local screen = SCREENMAN:GetTopScreen()
				if screen then
					-- Determine which gameplay screen to use (routine vs normal)
					local style = GAMESTATE:GetCurrentStyle():GetName()
					if style == "routine" then
						screen:SetNextScreenName("ScreenGameplayShared")
					else
						screen:SetNextScreenName("ScreenGameplay")
					end
					screen:StartTransitioningScreen("SM_GoToNextScreen")
				end
			end
		end
	},

	-- Manual Fade to Black transition quad
	Def.Quad{
		Name="TransitionQuad",
		InitCommand=function(self) 
			self:FullScreen():diffuse(0,0,0,0):draworder(1000) -- Topmost
		end,
		FadeInCommand=function(self)
			self:linear(0.5):diffusealpha(1)
		end
	}
}

return af
