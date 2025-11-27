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
	
	OffCommand=function(self)
		self:linear(0.3):diffusealpha(0)
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
		-- so we have to wait until ScreenSelectMusic is the top screen and
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

	LoadActor("../ScreenSelectMusic overlay/ToggleFavorite.lua"),

	LoadActor("./footer.lua"),
	
	-- Options prompt overlay (Defined inline to ensure loading)
	Def.ActorFrame{
		Name="StartPrompt",
		InitCommand=function(self) 
			self:draworder(500) 
		end,
		OnCommand=function(self) SM("StartPrompt Actor Loaded") end, 

		-- Catch the message at the frame level
		ShowPressStartForOptionsMessageCommand=function(self)
			SM("StartPrompt Frame Received Message")
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
			ShowCommand=function(self) self:diffusealpha(0.5) end,
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
				self:visible(true):diffusealpha(1):pulse():effectmagnitude(1,1.1,1):effectperiod(0.5)
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
			self:sleep(3.0):queuecommand("GoToGameplay")
		end,
		GoToGameplayCommand=function(self)
			-- Hide the prompt if it's visible
			MESSAGEMAN:Broadcast("HidePressStartForOptions")
			
			-- Ensure song and steps are set for all enabled players
			local focused_item = SL.MusicWheel.State.items[SL.MusicWheel.State.focus_index]
			if focused_item and focused_item.type == "song" then
				local song = focused_item.song
				if song then
					GAMESTATE:SetCurrentSong(song)
					
					-- Set steps for each enabled player
					for player in ivalues(GAMESTATE:GetEnabledPlayers()) do
						-- Get current steps type for this player
						local stepsType = GAMESTATE:GetCurrentStyle():GetStepsType()
						
						-- Use focused item's steps if available (Difficulty sort), otherwise find best
						local steps = focused_item.steps
						if not steps then
							-- Find best steps for this player's preference
							local allSteps = song:GetStepsByStepsType(stepsType)
							if #allSteps > 0 then
								steps = allSteps[1]  -- Default to first available
							end
						end
						
						if steps then
							GAMESTATE:SetCurrentSteps(player, steps)
						end
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
		end
	},
}

return af
