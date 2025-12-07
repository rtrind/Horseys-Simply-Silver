local player = ...
local pn = ToEnumShortString(player)
local info
local w, h

info = GetStepsCredit(player)

local marquee_index = 0

return Def.ActorFrame{
	
	-- coloured box behind Stepartist text
  	Def.Quad{
		InitCommand=function(self)
			self:zoomto(140.5,40)
			self:x(40.5)
			self:y( _screen.cy-76)
			if player == PLAYER_1 then
				self:x( self:GetX() * -1 )
			end
			--hide this colored box element if there is no credit data to display
			if #info == 0 then
				self:visible(false)
			end
			local currentSteps = GAMESTATE:GetCurrentSteps(player)
			if currentSteps then
				local currentDifficulty = currentSteps:GetDifficulty()
					if ThemePrefs.Get("RainbowMode") then
						self:diffuse(ColorLightTone(DifficultyColor(currentDifficulty)), true )
					else
						self:diffuse(ColorDarkTone(DifficultyColor(currentDifficulty)), true )
					end
			end
		end,
	},

	-- stepartist text
	LoadFont("Common Normal")..{
		InitCommand=function(self)
			self:zoom(0.75)
			self:y(_screen.cy-77)
		   self:horizalign(center)
		   if ThemePrefs.Get("RainbowMode") then self:diffuse(Color.Black) end
			self:x(40)
			self:maxwidth(180)
		end,
	   OnCommand=function(self)
		   if player == PLAYER_1 then
			   self:x( self:GetX() * -1 )
		   end
   
		   if type(info)=="table" and #info > 0 then
			   self:playcommand("Marquee")
		   elseif type(info)=="string" then
			   self:settext(info)
		   end
	   end,
	   MarqueeCommand=function(self)
		   -- increment the marquee_index, and keep it in bounds
		   marquee_index = (marquee_index % #info) + 1
		   -- retrieve the text we want to display
		   local text = GAMESTATE:GetCurrentSteps(player):IsAutogen() and THEME:GetString("ScreenSelectMusic", "AUTOGEN") or info[marquee_index]
   
		   -- set this BitmapText actor to display that text
		   self:settext( text )
		   DiffuseEmojis(self, text)
   
		   -- sleep 2 seconds before queueing the next Marquee command to do this again
		   if #info > 1 then
			   self:sleep(2):queuecommand("Marquee")
		   end
	   end,
	   OffCommand=function(self) self:stoptweening() end
   }
}
