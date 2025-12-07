return Def.Actor{
	OnCommand=function(self)
		SL.Global.Stages.Stats[SL.Global.Stages.PlayedThisGame + 1] = {
			song = GAMESTATE:GetCurrentSong(),
			MusicRate = SL.Global.ActiveModifiers.MusicRate
		}
	end
}