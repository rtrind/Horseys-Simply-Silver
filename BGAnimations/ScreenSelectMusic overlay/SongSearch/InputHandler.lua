local candidatesScroller = ...

local input = function(event)
	if not (event and event.PlayerNumber and event.button) then
		return false
	end

	local overlay = SCREENMAN:GetTopScreen():GetChild("Overlay"):GetChild("SongSearch")

	if event.type ~= "InputEventType_Release" then
		local info = candidatesScroller:get_info_at_focus_pos()
		local index = type(info)=="table" and info.index or 0
		local num_items = type(info)=="table" and info.totalItems or candidatesScroller.num_items
		if event.GameButton == "MenuRight" or event.GameButton == "MenuDown" then
			candidatesScroller:scroll_by_amount(1)
		elseif event.GameButton == "MenuLeft" or event.GameButton == "MenuUp" then
			candidatesScroller:scroll_by_amount(-1)
		elseif event.GameButton == "Start" then
			local focus = candidatesScroller:get_actor_item_at_focus_pos()
			local songOrExit = focus.song_name.songOrExit
			if type(songOrExit) ~= "string" then
				-- Focus on the selected song in the LuaWheel without reloading
				local song_index = SL.MusicWheel.FindSongIndex(songOrExit)
				if song_index then
					SL.MusicWheel.State.focus_index = song_index
					GAMESTATE:SetCurrentSong(songOrExit)
					
					-- Update steps for all players
					local steps_type = GAMESTATE:GetCurrentStyle():GetStepsType()
					local compatible_steps = songOrExit:GetStepsByStepsType(steps_type)
					if compatible_steps and #compatible_steps > 0 then
						for player in ivalues(GAMESTATE:GetHumanPlayers()) do
							GAMESTATE:SetCurrentSteps(player, compatible_steps[1])
						end
					end
					
					-- Broadcast to update the wheel display (triggers set_info_set)
					MESSAGEMAN:Broadcast("MusicWheelRebuilt", {song_search = true})
				end
			end
			overlay:queuecommand("DirectInputToEngine")
		elseif event.GameButton == "Back" or event.GameButton == "Select" then
			overlay:queuecommand("DirectInputToEngine")
		end
	end
	return false
end

return input