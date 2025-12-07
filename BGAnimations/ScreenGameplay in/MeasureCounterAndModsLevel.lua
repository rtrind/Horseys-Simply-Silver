return function(SongNumberInCourse)
	for player in ivalues(GAMESTATE:GetHumanPlayers()) do

		-- get the PlayerOptions string for any human players and store it now
		-- we'll retrieve it the next time ScreenSelectMusic loads and re-apply those same mods
		-- in this way, we can override the effects of songs that forced modifiers during gameplay
		-- the old-school (ie. ITG) way of GAMESTATE:ApplyGameCommand()
		local pn = ToEnumShortString(player)
		SL[pn].PlayerOptionsString = GAMESTATE:GetPlayerState(player):GetPlayerOptionsString("ModsLevel_Preferred")

		-- Check if MeasureCounter is turned on.  We may need to parse the chart.
		local mods = SL[pn].ActiveModifiers
		if mods.MeasureCounter and mods.MeasureCounter ~= "None" then

			local steps = GAMESTATE:GetCurrentSteps(player)

			-- This will parse out and set all the required info for the chart in the SL.Streams cache,
			-- The function will only do work iff we're parsing a chart different than what's in the cache.
			ParseChartInfo(steps, pn)

			-- Set the actual stream information for the player based on their selected notes threshold.
			local notesThreshold = tonumber(mods.MeasureCounter:match("%d+"))
			SL[pn].Streams.Measures = GetStreamSequences(SL[pn].Streams.NotesPerMeasure, notesThreshold)
		end
	end
end