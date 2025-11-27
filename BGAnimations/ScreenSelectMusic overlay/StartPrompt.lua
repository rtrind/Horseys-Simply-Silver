return Def.ActorFrame{
	InitCommand=function(self) self:draworder(200) end,

	-- Background dim (initially invisible)
	Def.Quad{
		InitCommand=function(self) self:diffuse(0,0,0,0):FullScreen():cropbottom(1):fadebottom(0.5) end,
		ShowPressStartForOptionsCommand=function(self) self:diffusealpha(1):cropbottom(1):linear(0.3):cropbottom(-0.5) end,
		HidePressStartForOptionsCommand=function(self) self:linear(0.3):cropbottom(1):diffusealpha(0) end
	},

	-- Text prompt
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Bold")..{
		Text=THEME:GetString("ScreenSelectMusic", "Press Start for Options"),
		InitCommand=function(self) self:visible(false):Center():zoom(0.75) end,
		ShowPressStartForOptionsCommand=function(self) self:visible(true):diffusealpha(1) end,
		HidePressStartForOptionsCommand=function(self) self:visible(false) end,
		ShowEnteringOptionsCommand=function(self) self:linear(0.125):diffusealpha(0):queuecommand("NewText") end,
		NewTextCommand=function(self) self:hibernate(0.1):settext(THEME:GetString("ScreenSelectMusic", "Entering Options...")):linear(0.125):diffusealpha(1):sleep(1) end
	}
}
