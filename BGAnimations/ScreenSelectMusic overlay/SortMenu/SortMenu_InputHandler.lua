local sort_wheel = ...

-- Guard state to prevent duplicate profile prompt openings and debounce rapid input
local lastProfilePromptAt = -1
local function canOpenProfilePrompt()
    -- If a fast switch/profile prompt is already in progress, block re-entry
    if SL and SL.Global and SL.Global.FastProfileSwitchInProgress then return false end
    if type(GetTimeSinceStart) == "function" then
        local now = GetTimeSinceStart()
        if lastProfilePromptAt > 0 and (now - lastProfilePromptAt) < 0.25 then
            return false
        end
    end
    return true
end
local function markProfilePromptOpened()
    if type(GetTimeSinceStart) == "function" then
        lastProfilePromptAt = GetTimeSinceStart()
    end
end

-- this handles user input while in the SortMenu
local input = function(event)
	if not (event and event.PlayerNumber and event.button) then
		return false
	end
	SOUND:StopMusic()
	local screen   = SCREENMAN:GetTopScreen()
	local overlay  = screen:GetChild("Overlay")
	local sortmenu = overlay:GetChild("SortMenu")
	if event.type ~= "InputEventType_Release" then
		if event.GameButton == "MenuRight" or event.GameButton == "MenuDown" then
			sort_wheel:scroll_by_amount(1)
			sortmenu:GetChild("change_sound"):play()
		elseif event.GameButton == "MenuLeft" or event.GameButton == "MenuUp" then
			sort_wheel:scroll_by_amount(-1)
			sortmenu:GetChild("change_sound"):play()
        elseif event.GameButton == "Start" then
			sortmenu:GetChild("start_sound"):play()
			local focus = sort_wheel:get_actor_item_at_focus_pos()
			if focus.kind == "SortBy" then
				-- Rebuild Lua wheel with new sort order
				SL.MusicWheel.RebuildWheelData(focus.sort_by)
				MESSAGEMAN:Broadcast('Sort', { order = focus.sort_by })
				MESSAGEMAN:Broadcast('ResetHeaderText')
				overlay:queuecommand("DirectInputToEngine")
			elseif focus.kind == "Playlist" then
				local path = THEME:GetPathO("", "Playlists/" .. focus.new_overlay .. ".txt")
				SONGMAN:SetPreferredSongs(path, --[[isAbsolute=]]true);
				if SONGMAN:GetPreferredSortSongs() then
					-- Rebuild Lua wheel with Preferred sort
					SL.MusicWheel.RebuildWheelData("SortOrder_Preferred")
					overlay:queuecommand("DirectInputToEngine")
				end
			-- the player wants to change modes, for example from ITG to FA+
			elseif focus.kind == "ChangeMode" then
				SL.Global.GameMode = focus.change
				for player in ivalues(GAMESTATE:GetHumanPlayers()) do
					ApplyMods(player)
				end
				SetGameModePreferences()
				THEME:ReloadMetrics()
				-- Broadcast that the SL GameMode has changed
				-- SSM's header will update its text and highscore names in the PaneDisplays will refresh
				MESSAGEMAN:Broadcast("SLGameModeChanged")
				-- Reload the SortMenu's available options and queue "DirectInputToEngine"
				-- to return input from Lua back to the engine and hide the SortMenu from view
				sortmenu:playcommand("AssessAvailableChoices"):queuecommand("DirectInputToEngine")
				-- the player wants to change styles, for example from single to double
			elseif focus.kind == "ChangeStyle" then
				-- If the MenuTimer is in effect, we need to make sure the current number of seconds
				-- remaining is preserved so we can reinstate it later. ShowPressStartForOptions
				-- will save the current number of seconds before transitioning to the next screen.
				if PREFSMAN:GetPreference("MenuTimer") then
					overlay:playcommand("ShowPressStartForOptions")
				end
				-- Get the style we want to change to
				local new_style = focus.change:lower()
				-- accommodate techno game
				if GAMESTATE:GetCurrentGame():GetName() == "techno" then new_style = new_style .. "8" end
				-- set it in the engine
				GAMESTATE:SetCurrentStyle(new_style)
				-- Make sure we cancel the request if it's active before trying to switch screens.
				-- This prevents the "Stale ActorFrame" error.
				overlay:GetChild("PaneDisplayMaster"):GetChild("GetScoresRequester"):playcommand("Cancel")
				-- finally, reload the screen
				screen:SetNextScreenName("ScreenReloadSSM")
				screen:StartTransitioningScreen("SM_GoToNextScreen")
            elseif focus.new_overlay then
				if focus.new_overlay == "GoBack" then
					sortmenu:playcommand("AssessAvailableChoices")
				-- if the overlay starts with "Category"
				elseif focus.new_overlay:match("^Category") then
					-- Pass in everything after "Category" to the broadcast
					MESSAGEMAN:Broadcast('EnterCategory', { Category = focus.new_overlay })
				elseif focus.new_overlay == "TestInput" then
					sortmenu:queuecommand("DirectInputToTestInput")
				elseif focus.new_overlay == "SongSearch" then
					-- Direct the input back to the engine, so that the ScreenTextEntry overlay
					-- works correctly.
					overlay:queuecommand("DirectInputToEngineForSongSearch")
				elseif focus.new_overlay == "LoadNewSongs" then
					-- Make sure we cancel the request if it's active before trying to switch screens.
					-- This prevents the "Stale ActorFrame" error.
					overlay:GetChild("PaneDisplayMaster"):GetChild("GetScoresRequester"):playcommand("Cancel")
					overlay:playcommand("DirectInputToEngine")
					SCREENMAN:SetNewScreen("ScreenReloadSongsSSM")
                elseif focus.new_overlay == "SwitchProfile" then
                    -- Prevent duplicate prompt openings and debounce rapid Start presses
                    if not canOpenProfilePrompt() then return true end
                    -- Mark guard before proceeding
                    SL.Global.FastProfileSwitchInProgress = true
                    markProfilePromptOpened()

                    -- Make sure we save any currently active profiles before potentially switching
                    -- to different ones.
                    GAMESTATE:SaveProfiles()
                    PROFILEMAN:SaveMachineProfile()

                    overlay:queuecommand("DirectInputToEngineForSelectProfile")
				elseif focus.new_overlay == "PracticeMode" then
					SCREENMAN:GetTopScreen():SetNextScreenName("ScreenPractice")
					SCREENMAN:GetTopScreen():StartTransitioningScreen("SM_GoToNextScreen")
				end
			end

		elseif event.GameButton == "Back" or event.GameButton == "Select" then
			overlay:queuecommand("DirectInputToEngine")
			return true  -- Consume the event to prevent it from bubbling to other handlers
		end
	end
	return false
end
return input
