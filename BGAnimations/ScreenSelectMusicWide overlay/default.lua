local af = Def.ActorFrame{
	-- GameplayReloadCheck is a kludgy global variable used in ScreenGameplay in.lua to check
	-- if ScreenGameplay is being entered "properly" or being reloaded by a scripted mod-chart.
	-- If we're here in SelectMusic, set GameplayReloadCheck to false, signifying that the next
	-- time ScreenGameplay loads, it should have a properly animated entrance.
	InitCommand=function(self)
		SL.Global.GameplayReloadCheck = false
		generateFavoritesForMusicWheel()
		
		-- reset song start time here in case player force-escaped
		start_time = -1

		-- While other SM versions don't need this, Outfox resets the
		-- the music rate to 1 between songs, but we want to be using
		-- the preselected music rate.
		local songOptions = GAMESTATE:GetSongOptionsObject("ModsLevel_Preferred")
		songOptions:MusicRate(SL.Global.ActiveModifiers.MusicRate)

		-- here we're going to set the preferred song of the music wheel when [no player profile is loaded] or [a player profile is loaded and does not have a preferred song]
		-- see 06 SL-Utilities.lua for function definitions
		SetPreferredSong()
	end,

	PlayerProfileSetMessageCommand=function(self, params)
		if not PROFILEMAN:IsPersistentProfile(params.Player) then
			LoadGuest(params.Player)
		end
		generateFavoritesForMusicWheel()
		ApplyMods(params.Player)
	end,

	PlayerJoinedMessageCommand=function(self, params)
        -- Instead of reloading abruptly, open the profile selection screen
		MESSAGEMAN:Broadcast("OpenProfileSelectFromJoin")	
	end,

	SSM_RequestReloadMessageCommand=function(self, params)
        -- Defer one frame to ensure we're still on the profile screen as top
        self:sleep(0.01):queuecommand("DoReload")
    end,

    DoReloadCommand=function(self, params)
		-- For some reason we cannot reload the screen after a profile switch,
		-- so we have to wait until ScreenSelectMusicWide is the top screen and
		-- no other screen is on top of it. Then reload the entire screen...
        local s = SCREENMAN:GetTopScreen()
        if s then
			SM("Reloading screen...")
            s:SetNextScreenName("ScreenReloadSSM")
            s:StartTransitioningScreen("SM_GoToNextScreen")
        end
    end,

	-- ---------------------------------------------------
	--  first, load files that contain no visual elements, just code that needs to run

	-- MenuTimer code for preserving SSM's timer value when going 
	-- from SSM to a different screen and back to SSM (i.e. returning from PlayerOptions).
	LoadActor("./PreserveMenuTimer.lua"),
	-- Apply player modifiers from profile
	LoadActor("./PlayerModifiers.lua"),

	-- ---------------------------------------------------
	-- next, load visual elements; the order of these matters
	-- i.e. content in PerPlayer/Over needs to draw on top of content from PerPlayer/Under

	LoadActor("./NotefieldPreview.lua"),

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

	LoadActor("../ScreenSelectMusic overlay/ToggleFavorite.lua"),

	LoadActor("./footer.lua"),
}

return af
