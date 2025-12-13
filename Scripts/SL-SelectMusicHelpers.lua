-- ----------------------------------------------------------------------------------------
-- functions used by the Lua MusicWheel for preview music playback

-- Play preview music of the current song
-- Invoked each time the MusicWheel changes focus to a song
play_sample_music = function()
	local song = GAMESTATE:GetCurrentSong()

	if song then
		local songpath = song:GetMusicPath()
		local sample_start = song:GetSampleStart()
		local sample_len = song:GetSampleLength()

		if songpath and sample_start and sample_len then
			-- Handle looping preference
			local loop = true
			if ThemePrefs.Get("SampleMusicLoops") == false then
				loop = false
			end

			SOUND:DimMusic(PREFSMAN:GetPreference("SoundVolume"), math.huge)
			SOUND:PlayMusicPart(songpath, sample_start,sample_len, 0.5, 1.5, loop, true)
			
			-- Update Global State for NoteField sync
			if SL.Global.SampleMusic then
				SL.Global.SampleMusic.StartTime = GetTimeSinceStart()
				SL.Global.SampleMusic.StartOffset = sample_start
				SL.Global.SampleMusic.Length = sample_len
				SL.Global.SampleMusic.Loop = loop
				SL.Global.SampleMusic.Playing = true
			end
		else
			stop_music()
		end
	else
		stop_music()
	end
end

-- Stop playing preview music
-- Invoked when MusicWheel focus changes or when closing a group
stop_music = function()
	SOUND:PlayMusicPart("", 0, 0)
	
	-- Reset Global State
	if SL.Global.SampleMusic then
		SL.Global.SampleMusic.Playing = false
	end
end


----------------------------------------------------------------------------------------
-- functions used by ScreenSelectMusic

-- TextBanner is an engine-defined ActorFrame that contains three BitmapText actors named
-- "Title", "Subtitle", and "Artist".  Simply Love's MusicWheel only uses the first two.
--
-- It has two unique Metrics, "AfterSetCommand" and "ArtistPrependString"
-- Simply Love is only concerned with "AfterSetCommand"
-- because the song Artist does not appear in each MusicWheelItem

TextBannerAfterSet = function(self)
	-- acquire handles to two of the BitmapText children of this TextBanner ActorFrame
	-- we'll use them to position each song's Title and Subtitle as they appear in the MusicWheel
	local Title = self:GetChild("Title")
	local Subtitle = self:GetChild("Subtitle")

	-- assume the song's Subtitle is an empty string by default and position the Title
	-- in the vertical middle of the MusicWheelItem
	Title:y(0)

	-- if the Subtitle isn't an empty string
	if Subtitle:GetText() ~= "" then
		-- offset the Title's y() by -6 pixels
		Title:y(-6)
		-- and offset the Subtitle's y() by 6 pixels
		Subtitle:y(6)
	end
end