-- tables of rgba values
local dark  = {0,0,0,1}
local light = {0.65,0.65,0.65,1}

return Def.Quad{
	Name="Footer",
	InitCommand=function(self)
		self:draworder(90):zoomto(_screen.w, 32):vertalign(bottom):y(32)
		if ThemePrefs.Get("VisualStyle") == "SRPG8" then
			self:diffuse(GetCurrentColor(true))
		elseif DarkUI() then
			self:diffuse(dark)
		elseif ThemePrefs.Get("VisualStyle") == "Technique" then
			self:diffusealpha(1):diffuse(dark)
		else
			self:diffuse(light)
		end
	end,
	ScreenChangedMessageCommand=function(self)
		local topscreen = SCREENMAN:GetTopScreen():GetName()
		-- Casual mode removed (16:9 only)
		if ThemePrefs.Get("VisualStyle") == "SRPG8" then
			self:diffuse(GetCurrentColor(true))
		end
		if ThemePrefs.Get("VisualStyle") == "Technique" then
			if topscreen == "ScreenSelectMusic" and not ThemePrefs.Get("RainbowMode") then
				self:diffuse(0, 0, 0, 0.5)
			else
				self:diffusealpha(1):diffuse(dark)
			end
		end
	end,
	ColorSelectedMessageCommand=function(self)
		if ThemePrefs.Get("VisualStyle") == "SRPG8" then
			self:diffuse(GetCurrentColor(true))
		end
	end,
	VisualStyleSelectedMessageCommand=function(self)
		if ThemePrefs.Get("VisualStyle") == "Technique" then
			self:diffusealpha(0)
		end
	end,
}
