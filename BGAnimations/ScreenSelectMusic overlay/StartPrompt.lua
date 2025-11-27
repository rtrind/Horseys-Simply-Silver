return Def.ActorFrame{
	InitCommand=function(self) self:draworder(500) end, -- High draworder

	-- Background dim
	Def.Quad{
		InitCommand=function(self) self:FullScreen():diffuse(0,0,0,0) end,
		ShowPressStartForOptionsCommand=function(self) 
			self:diffusealpha(0.5) -- Simple fade to black 50%
		end,
		HidePressStartForOptionsCommand=function(self) self:diffusealpha(0) end
	},

	-- Text prompt
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Bold")..{
		Text=THEME:GetString("ScreenSelectMusic", "Press Start for Options"),
		InitCommand=function(self) 
			self:visible(false):Center():zoom(0.75):draworder(501)
		end,
		ShowPressStartForOptionsCommand=function(self) 
			self:visible(true):diffusealpha(1):pulse():effectmagnitude(1,1.1,1):effectperiod(0.5)
			SM("Showing Start Prompt") -- Debug message
		end,
		HidePressStartForOptionsCommand=function(self) self:visible(false):stopeffect() end,
		ShowEnteringOptionsCommand=function(self) self:visible(true):settext(THEME:GetString("ScreenSelectMusic", "Entering Options...")):stopeffect() end
	}
}
