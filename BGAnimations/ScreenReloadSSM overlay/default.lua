-- Loading screen overlay for ScreenReloadSSM
-- Replicates the ScreenProfileLoad loading animation style

local tweentime = 0.325

return Def.ActorFrame{
	InitCommand=function(self)
		self:Center():draworder(101)
	end,

	Def.Quad{
		Name="FadeToBlack",
		InitCommand=function(self)
			self:horizalign(right):vertalign(bottom):FullScreen()
			self:diffuse( ThemePrefs.Get("RainbowMode") and Color.White or Color.Black ):diffusealpha(0)
		end,
		OnCommand=function(self)
			self:sleep(tweentime):linear(tweentime):diffusealpha(1)
		end
	},

	Def.Quad{
		Name="HorizontalWhiteSwoosh",
		InitCommand=function(self)
			self:horizalign(center):vertalign(middle)
				:diffuse( ThemePrefs.Get("RainbowMode") and Color.Black or Color.White )
				:zoomto(_screen.w + 100,50):faderight(0.1):fadeleft(0.1):cropright(1)
		end,
		OnCommand=function(self)
			-- Animate in, then stay visible until next screen takes over
			self:linear(tweentime):cropright(0):sleep(tweentime)
			self:queuecommand("Transition")
		end,
		TransitionCommand=function(self)
			SCREENMAN:GetTopScreen():StartTransitioningScreen("SM_GoToNextScreen")
		end
	},

	Def.BitmapText{
		Font=ThemePrefs.Get("ThemeFont") .. " Bold",
		Text=THEME:GetString("ScreenReloadSSM","Loading..."),
		InitCommand=function(self)
			self:diffuse( ThemePrefs.Get("RainbowMode") and Color.White or Color.Black ):zoom(0.6)
		end
	}
}
