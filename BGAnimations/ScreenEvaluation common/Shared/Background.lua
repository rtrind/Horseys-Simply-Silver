if not ThemePrefs.Get("ResultsBG") then return end
local SongOrCourse = GAMESTATE:GetCurrentSong()
local af = Def.ActorFrame{ InitCommand=function(self) self:xy(0, 32):horizalign(0):vertalign(0) end }

if SongOrCourse and SongOrCourse:HasBackground() then
	--song or course banner, if there is one
	af[#af+1] = Def.Sprite{
		Name="Background",
		InitCommand=function(self)
			local Path = GAMESTATE:GetCurrentSong():GetBackgroundPath()
			if Path then
				self:Load( Path ):visible(true):horizalign(0):vertalign(0):diffusealpha(0.3):SetHeight(_screen.cy*2-32):SetWidth(_screen.cx*2):blend("BlendMode_Add")
			else
				self:visible(false)
			end
		end,
	}
end

return af