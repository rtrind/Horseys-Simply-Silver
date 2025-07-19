-- We want to be able to display the time spent in gameplay across the entire set
-- for ScreenGameover.  We could call GAMESTATE:GetCurrentSong():MusicLengthSeconds(),
-- store that, and sum each value at ScreenGameover, but that wouldn't (easily) handle
-- early quitting/escaping out of songs accurately.
--
-- So instead, calculate the duration of time actually spent in ScreenGameplay when its
-- OffCommand is called.
------------------------------------------------------------

local player = ...

local actor = Def.Actor{
	OnCommand=function(self)
		if not self.start_time or self.start_time == -1 then
			self.start_time = GetTimeSinceStart()
		end
	end,
	OffCommand=function(self)
		if (self.start_time and self.start_time > 0) then
			SL[ToEnumShortString(player)].Stages.Stats[SL.Global.Stages.PlayedThisGame + 1].duration = GetTimeSinceStart() - (self.start_time or 0)
			self.start_time = -1
		end
	end
}

return actor