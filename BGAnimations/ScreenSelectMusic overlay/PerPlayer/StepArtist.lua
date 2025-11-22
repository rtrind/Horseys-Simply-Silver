local player = ...
local pn = ToEnumShortString(player)
local p = PlayerNumber:Reverse()[player]

local text_table, marquee_index

-- EX score is a number like 92.67
local GetPointsForSong = function(maxPoints, exScore)
	local thresholdEx = 50.0
	local percentPoints = 40.0

	-- Helper function to take the logarithm with a specific base.
	local logn = function(x, y)
		return math.log(x) / math.log(y)
	end

	-- The first half (logarithmic portion) of the scoring curve.
	local first = logn(
		math.min(exScore, thresholdEx) + 1,
		math.pow(thresholdEx + 1, 1 / percentPoints)
	)

	-- The seconf half (exponential portion) of the scoring curve.
	local second = math.pow(
		100 - percentPoints + 1,
		math.max(0, exScore - thresholdEx) / (100 - thresholdEx)
	) - 1

	-- Helper function to round to a specific number of decimal places.
	-- We want 100% EX to actually grant 100% of the points.
	-- We don't want to  lose out on any single points if possible. E.g. If
	-- 100% EX returns a number like 0.9999999999999997 and the chart points is
	-- 6500, then 6500 * 0.9999999999999997 = 6499.99999999999805, where
	-- flooring would give us 6499 which is wrong.
	local roundPlaces = function(x, places)
		local factor = 10 ^ places
		return math.floor(x * factor + 0.5) / factor
	end

	local percent = roundPlaces((first + second) / 100.0, 6)
	return math.floor(maxPoints * percent)
end

return Def.ActorFrame{
	Name="StepArtistAF_" .. pn,

	-- song and course changes
	OnCommand=function(self) self:queuecommand("Reset") end,
	["CurrentSteps"..pn.."ChangedMessageCommand"]=function(self) self:queuecommand("Reset") end,
	CurrentSongChangedMessageCommand=function(self) self:queuecommand("Reset") end,
	CurrentCourseChangedMessageCommand=function(self) self:queuecommand("Reset") end,

	--since we're now resetting ScreenSelectMusicWide when a new player joins, we don't want this animation to play
	-- PlayerJoinedMessageCommand=function(self, params)
	-- 	if params.Player == player then
	-- 		self:queuecommand("Appear" .. pn)
	-- 	end
	-- end,

	-- Simply Love doesn't support player unjoining (that I'm aware of!) but this
	-- animation is left here as a reminder to a future me to maybe look into it.
	PlayerUnjoinedMessageCommand=function(self, params)
		if params.Player == player then
			self:accelerate(0.1):zoomy(0.6):decelerate(0.2):zoomy(1):accelerate(0.2):sleep(0.2):zoomy(0):visible(false)
		end
	end,

	-- depending on the value of pn, this will either become
	-- an AppearP1Command or an AppearP2Command when the screen initializes
	["Appear"..pn.."Command"]=function(self) self:visible(true):zoomy(0):sleep(0.2):accelerate(0.2):zoomy(1):decelerate(0.2):zoomy(0.6):accelerate(0.1):zoomy(1) end,

	InitCommand=function(self)
		self:visible( false ):halign( p )
		if GAMESTATE:GetNumPlayersEnabled() == 2 then
			self:y(_screen.cy + 27)
		else
			self:y(_screen.cy - 24)
		end

		if player == PLAYER_1 then
			self:x(_screen.cx-452.5)
		else
			self:x(_screen.cx+114.5)
		end

		if GAMESTATE:IsHumanPlayer(player) then
			self:queuecommand("Appear" .. pn)
		end
	end,

	-- background
	Def.ActorMultiVertex{
		InitCommand=function(self)
			-- don't set verts in InitCommand because late joining will not reset the dimensions of this element belonging to the first joined player
			self:diffuse(GetCurrentColor())
			self:zoom(0.5)
			self:queuecommand("Reset")
		end,
		ResetCommand=function(self)
			local StepsOrTrail = GAMESTATE:IsCourseMode() and GAMESTATE:GetCurrentTrail(player) or GAMESTATE:GetCurrentSteps(player)
			if StepsOrTrail then
				local difficulty = StepsOrTrail:GetDifficulty()
				self:diffuse( DifficultyColor(difficulty) )
			else
				self:diffuse( PlayerColor(player) )
			end

			-- these coordinates aren't neat and tidy, but they do create three triangles
			-- that fit together to approximate hurtpiggypig's original png asset

			-- since ScreenSelectMusicWide doesn't necessitate different background elements, we're trimming the unused code

			-- coordinates at matrix spot explanation: +307.5 adds length, -104 changes the height, and +14 moves the "carrot" to under "STEPS"
			local StepCreditBGVerts = {
				--   x   y  z    r,g,b,a
				{{-113, -104, 0}, {1,1,1,1}},
				{{113+307.5, -104, 0}, {1,1,1,1}},
				{{113+307.5, 16, 0}, {1,1,1,1}},
				{{113+307.5, 16, 0}, {1,1,1,1}},
				{{-113, 16, 0}, {1,1,1,1}},
				{{-113, -104, 0}, {1,1,1,1}},
				{{ -98+14, 16, 0}, {1,1,1,1}},
				{{ -78+14, 16, 0}, {1,1,1,1}},
				{{ -88+14, 29, 0}, {1,1,1,1}},
			}

			self:SetDrawState({Mode="DrawMode_Triangles"}):SetVertices(StepCreditBGVerts)

			if player == PLAYER_1 then
				self:xy(82,40)
			else
				-- something is wrong here... DensityGraph and PaneDisplay are off
				-- since this UI will only be used in legacy 4:3 aspect ratio let's just be lazy and nudge things into the correct spot 
				-- without rotating this element about the y axis, there is a single pixel difference between P1 and P2 locations
				self:xy(256,40)
				self:rotationy(180)
			end
			if ThemePrefs.Get("VisualStyle") == "Technique" then
				self:diffusealpha(0.5)
			end
		end
	},

	--STEPS label
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Text=Screen.String("STEPS"),
		InitCommand=function(self)
			self:maxwidth(40):zoom(0.8):y(-2)
			if player == PLAYER_1 then
				self:horizalign(left):x(30)
			else
				self:horizalign(right):x(306)
			end
			if ThemePrefs.Get("VisualStyle") == "Technique" then
				self:diffuse(Color.White)
			else
				self:diffuse(Color.Black)
			end
		end,
	},

	--stepartist text
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		InitCommand=function(self)
			-- if we don't set vertalign here, latejoining will cause the text to be center aligned until a ResetCommand is initiated (by changing the selected song)
			-- there's nothing to lose here by just Top_Aligning all text and just changing the y-positions to match
			self:zoom(0.8):vertalign("VertAlign_Top")
			if ThemePrefs.Get("VisualStyle") == "Technique" then
				self:diffuse(Color.White)
			else
				self:diffuse(Color.Black)
			end
			self:queuecommand("Reset")
		end,
		ResetCommand=function(self)

			local SongOrCourse = GAMESTATE:IsCourseMode() and GAMESTATE:GetCurrentCourse() or GAMESTATE:GetCurrentSong()
			local StepsOrTrail = GAMESTATE:IsCourseMode() and GAMESTATE:GetCurrentTrail(player) or GAMESTATE:GetCurrentSteps(player)

			-- always stop tweening when steps change in case a MarqueeCommand is queued
			self:stoptweening()

			self:maxwidth(272):y(-8)
			if player == PLAYER_1 then
				self:horizalign(left):x(70)
			else
				self:horizalign(right):x(266)
			end

			if SongOrCourse and StepsOrTrail then

				text_table = GetStepsCredit(player)
				marquee_index = 0

				-- don't queue a Marquee in CourseMode
				-- each TrailEntry text change will be broadcast from CourseContentsList.lua
				-- to ensure it stays synced with the scrolling list of songs
				if not GAMESTATE:IsCourseMode() then
					-- only queue a Marquee if there are things in the text_table to display

					if #text_table > 0 then
						local fulldesc = ""
						for i=1,#text_table do
							local curText = text_table[i]
							fulldesc = fulldesc .. curText .. "\n"
						end
						self:settext(fulldesc)
						DiffuseEmojis(self, fulldesc)
						if GAMESTATE:GetCurrentSteps(player):IsAutogen() then
							self:settext(THEME:GetString("ScreenSelectMusic", "AUTOGEN"))
							DiffuseEmojis(self)
						end
					else
						-- no credit information was specified in the simfile for this stepchart, so just set to an empty string
						self:settext("")
					end
				end
			else
				-- there wasn't a song/course or a steps object, so the MusicWheel is probably hovering
				-- on a group title, which means we want to set the stepartist text to an empty string for now
				self:settext("")
			end
		end,
		ITLCommand=function(self)
			if #GAMESTATE:GetHumanPlayers() == 1 then
				local SongOrCourse = GAMESTATE:IsCourseMode() and GAMESTATE:GetCurrentCourse() or GAMESTATE:GetCurrentSong()
				local StepsOrTrail = GAMESTATE:IsCourseMode() and GAMESTATE:GetCurrentTrail(player) or GAMESTATE:GetCurrentSteps(player)

				-- always stop tweening when steps change in case a MarqueeCommand is queued
				self:stoptweening()

				if SongOrCourse and StepsOrTrail then

					text_table = GetStepsCredit(player)
					marquee_index = 0

					-- don't queue a Marquee in CourseMode
					-- each TrailEntry text change will be broadcast from CourseContentsList.lua
					-- to ensure it stays synced with the scrolling list of songs
					if not GAMESTATE:IsCourseMode() then
						-- only queue a Marquee if there are things in the text_table to display
						if #text_table > 0 then
							-- self:queuecommand("Marquee")
							local fulldesc = ""
							for i=1,#text_table do
								local curText = text_table[i]
								if string.sub(curText, string.len(curText) - 3, string.len(curText)) == " pts" then
									local max_points = string.sub(curText, 1, string.len(curText) - 4)
									local exscore = tonumber(SL[pn].itlScore)/100
									local max_point_multiplier = 0
									if exscore then
										local points = GetPointsForSong(max_points, exscore)
										local pointsPercent = string.format("%.2f%%", points / max_points * 100)
										curText = points .. "/" .. curText .. " ("..pointsPercent..")"
									end
								end
								fulldesc = fulldesc .. curText .. "\n"
							end
							self:settext(fulldesc)
							DiffuseEmojis(self, fulldesc)
							if GAMESTATE:GetCurrentSteps(player):IsAutogen() then
								self:settext(THEME:GetString("ScreenSelectMusic", "AUTOGEN"))
								DiffuseEmojis(self)
							end
						else
							-- no credit information was specified in the simfile for this stepchart, so just set to an empty string
							self:settext("")
						end
					end
				else
					-- there wasn't a song/course or a steps object, so the MusicWheel is probably hovering
					-- on a group title, which means we want to set the stepartist text to an empty string for now
					self:settext("")
				end
			end
		end,
		OffCommand=function(self) self:stoptweening() end
	}
}