local player = ...
local pn = PlayerNumber:Reverse()[player]

return Def.ActorFrame{

	-- colored square as the background for the difficulty meter
	Def.Quad{
		InitCommand=function(self)
			self:zoomto(40,40)
			self:y( _screen.cy-76 )
			self:x(129.5 * (player==PLAYER_1 and -1 or 1))

			local currentSteps = GAMESTATE:GetCurrentSteps(player)
			if currentSteps then
				local currentDifficulty = currentSteps:GetDifficulty()
				self:diffuse( DifficultyColor(currentDifficulty), true )
			end
		end
	},

	-- numerical difficulty meter
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Bold")..{
		InitCommand=function(self)
			self:diffuse(Color.Black):zoom( 0.55 )
			
			self:y( _screen.cy-82 )
			self:x(129.5 * (player==PLAYER_1 and -1 or 1))

			local steps = GAMESTATE:GetCurrentSteps(player)
			if steps then self:settext(steps:GetMeter()) end
			self:maxwidth(70)
		end
	},
	
	-- difficulty text ("beginner" or "expert" or etc.)
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		InitCommand=function(self)
			self:y(_screen.cy-65)
			self:halign(pn)

			if player==PLAYER_1 then
 				self:x(-130)
 			elseif player==PLAYER_2 then
 				self:x(130)
 			end
 			self:horizalign(center):zoom(0.6)
 			self:diffuse(Color.Black)
 			self:maxwidth(56)

			local steps = GAMESTATE:GetCurrentSteps(player)
			-- GetDifficulty() returns a value from the Difficulty Enum such as "Difficulty_Hard"
			-- ToEnumShortString() removes the characters up to and including the
			-- underscore, transforming a string like "Difficulty_Hard" into "Hard"
			local difficulty = ToEnumShortString( steps:GetDifficulty() )
			difficulty = THEME:GetString("Difficulty", difficulty)

			self:settext(difficulty)
		end
	},

	--there is no reason to print the style (single/double) because it is shown graphically in the top right of the screen
}
