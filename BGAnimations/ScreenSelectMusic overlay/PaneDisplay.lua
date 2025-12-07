-- PaneDisplay.lua - Shows local profile scores

local machine_profile = PROFILEMAN:GetMachineProfile()

local footer_height = GAMESTATE:GetNumPlayersEnabled() == 2 and 0 or 32
local pane_height = GAMESTATE:GetNumPlayersEnabled() == 2 and 59 or 60
local text_zoom = 0.7

-- -----------------------------------------------------------------------
local GetSongAndSteps = function(player)
	local SongOrCourse = GAMESTATE:GetCurrentSong()
	local StepsOrTrail = GAMESTATE:GetCurrentSteps(player)
	return SongOrCourse, StepsOrTrail
end

local GetScoreFromProfile = function(profile, SongOrCourse, StepsOrTrail)
	if not (profile and SongOrCourse and StepsOrTrail) then return nil end
	return profile:GetHighScoreList(SongOrCourse, StepsOrTrail):GetHighScores()[1]
end

local GetScoreForPlayer = function(player)
	local highScore
	if PROFILEMAN:IsPersistentProfile(player) then
		local SongOrCourse, StepsOrTrail = GetSongAndSteps(player)
		highScore = GetScoreFromProfile(PROFILEMAN:GetProfile(player), SongOrCourse, StepsOrTrail)
	end
	return highScore
end

-- -----------------------------------------------------------------------
local pos = {
	col = { -100, -36, 54, 150 },
	row = { -24, -9, 6, 21, 36, 50 }
}

local PaneItems = {
	{ name=THEME:GetString("RadarCategory","Taps"),  rc='RadarCategory_TapsAndHolds'},
	{ name=THEME:GetString("RadarCategory","Holds"), rc='RadarCategory_Holds'},
	{ name=THEME:GetString("RadarCategory","Rolls"), rc='RadarCategory_Rolls'},
	{ name=THEME:GetString("RadarCategory","Jumps"), rc='RadarCategory_Jumps'},
	{ name=THEME:GetString("RadarCategory","Hands"), rc='RadarCategory_Hands'},
	{ name=THEME:GetString("RadarCategory","Mines"), rc='RadarCategory_Mines'},
}

-- -----------------------------------------------------------------------
local af = Def.ActorFrame{ Name="PaneDisplayMaster" }

for player in ivalues(PlayerNumber) do
	local pn = ToEnumShortString(player)

	af[#af+1] = Def.ActorFrame{ Name="PaneDisplay"..pn }
	local af2 = af[#af]

	af2.InitCommand=function(self)
		self:visible(GAMESTATE:IsHumanPlayer(player))
		if player == PLAYER_1 then
			self:x(_screen.w * 0.25 - 80)
		elseif player == PLAYER_2 then
			self:x(_screen.w * 0.75 + 80)
		end
		self:y(_screen.h - footer_height - pane_height)
	end

	af2.PlayerUnjoinedMessageCommand=function(self, params)
		if player==params.Player then self:visible(false) end
	end

	af2.PlayerProfileSetMessageCommand=function(self, params)
		if player == params.Player then self:playcommand("Set") end
	end

	af2.OnCommand=function(self) self:playcommand("Set") end
	af2.SLGameModeChangedMessageCommand=function(self) self:playcommand("Set") end
	af2.CurrentCourseChangedMessageCommand=function(self) self:playcommand("Set") end
	af2.CurrentSongChangedMessageCommand=function(self) self:playcommand("Set") end
	af2["CurrentSteps"..pn.."ChangedMessageCommand"]=function(self) self:playcommand("Set") end
	af2["CurrentTrail"..pn.."ChangedMessageCommand"]=function(self) self:playcommand("Set") end

	-- Background Quad
	af2[#af2+1] = Def.Quad{
		Name="BackgroundQuad",
		InitCommand=function(self)
			self:zoomtowidth(267):zoomtoheight(pane_height*2):addy(-pane_height):vertalign(top)
		end,
		SetCommand=function(self)
			local SongOrCourse, StepsOrTrail = GetSongAndSteps(player)
			if GAMESTATE:IsHumanPlayer(player) then
				if StepsOrTrail then
					self:diffuse(DifficultyColor(StepsOrTrail:GetDifficulty()))
				else
					self:diffuse(PlayerColor(player))
				end
				if ThemePrefs.Get("VisualStyle") == "Technique" then
					self:diffusealpha(0.5)
				end
			end
		end
	}

	-- Radar values (Taps, Holds, Rolls, etc.)
	for i, item in ipairs(PaneItems) do
		local row = i
		af2[#af2+1] = Def.ActorFrame{
			Name=item.name,
			-- Value
			LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
				InitCommand=function(self)
					self:zoom(text_zoom):horizalign(right):maxwidth(40)
					self:x(pos.col[1]):y(pos.row[row])
					self:diffuse(ThemePrefs.Get("VisualStyle") == "Technique" and Color.White or Color.Black)
				end,
				SetCommand=function(self)
					local SongOrCourse, StepsOrTrail = GetSongAndSteps(player)
					if not SongOrCourse then self:settext("?"); return end
					if not StepsOrTrail then self:settext(""); return end
					if item.rc then
						local val = StepsOrTrail:GetRadarValues(player):GetValue(item.rc)
						self:settext(val >= 0 and val or "?")
					end
				end
			},
			-- Label
			LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
				Text=item.name,
				InitCommand=function(self)
					self:zoom(text_zoom):horizalign(left)
					self:x(pos.col[1]+3):y(pos.row[row])
					self:diffuse(ThemePrefs.Get("VisualStyle") == "Technique" and Color.White or Color.Black)
				end
			},
		}
	end

	-- Machine HighScore Name
	af2[#af2+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="MachineHighScoreName",
		InitCommand=function(self)
			self:zoom(text_zoom):maxwidth(30)
			self:x(pos.col[3]+25*text_zoom):y(pos.row[1])
			self:diffuse(ThemePrefs.Get("VisualStyle") == "Technique" and Color.White or Color.Black)
		end,
		SetCommand=function(self)
			local SongOrCourse, StepsOrTrail = GetSongAndSteps(player)
			local machineScore = GetScoreFromProfile(machine_profile, SongOrCourse, StepsOrTrail)
			self:settext(machineScore and machineScore:GetName() or "----")
			DiffuseEmojis(self:ClearAttributes())
		end
	}

	-- Machine HighScore
	af2[#af2+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="MachineHighScore",
		InitCommand=function(self)
			self:zoom(text_zoom):horizalign(right)
			self:x(pos.col[3]+105*text_zoom):y(pos.row[1])
			self:diffuse(ThemePrefs.Get("VisualStyle") == "Technique" and Color.White or Color.Black)
		end,
		SetCommand=function(self)
			local SongOrCourse, StepsOrTrail = GetSongAndSteps(player)
			local machineScore = GetScoreFromProfile(machine_profile, SongOrCourse, StepsOrTrail)
			if machineScore then
				self:settext(FormatPercentScore(machineScore:GetPercentDP()))
			else
				self:settext("??.??%")
			end
		end
	}

	-- Player HighScore Name
	af2[#af2+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="PlayerHighScoreName",
		InitCommand=function(self)
			self:zoom(text_zoom):maxwidth(30)
			self:x(pos.col[3]+25*text_zoom):y(pos.row[2])
			self:diffuse(ThemePrefs.Get("VisualStyle") == "Technique" and Color.White or Color.Black)
		end,
		SetCommand=function(self)
			local playerScore = GetScoreForPlayer(player)
			self:settext(playerScore and playerScore:GetName() or "----")
			DiffuseEmojis(self:ClearAttributes())
		end
	}

	-- Player HighScore
	af2[#af2+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="PlayerHighScore",
		InitCommand=function(self)
			self:zoom(text_zoom):horizalign(right)
			self:x(pos.col[3]+105*text_zoom):y(pos.row[2])
			self:diffuse(ThemePrefs.Get("VisualStyle") == "Technique" and Color.White or Color.Black)
		end,
		SetCommand=function(self)
			local playerScore = GetScoreForPlayer(player)
			if playerScore then
				self:settext(FormatPercentScore(playerScore:GetPercentDP()))
			else
				self:settext("??.??%")
			end
		end
	}

	-- Chart Difficulty Meter
	af2[#af2+1] = LoadFont("Wendy/_wendy small")..{
		Name="DifficultyMeter",
		InitCommand=function(self)
			self:horizalign(center):xy(pos.col[3]+41, pos.row[5]-7):maxwidth(45)
			self:diffuse(ThemePrefs.Get("VisualStyle") == "Technique" and Color.White or Color.Black)
		end,
		SetCommand=function(self)
			local SongOrCourse, StepsOrTrail = GetSongAndSteps(player)
			if not SongOrCourse then self:settext(""); return end
			local meter = StepsOrTrail and StepsOrTrail:GetMeter() or "?"
			self:settext(meter)
		end
	}
end

return af
