local player = ...
local pn = ToEnumShortString(player)
local p = PlayerNumber:Reverse()[player]
local profile_name = PROFILEMAN:GetProfile(player):GetDisplayName(player)
local profile = PROFILEMAN:GetProfile(player)
local avatar = GetPlayerAvatarPath(player)

local quads = profile.GetTotalScoresWithGrade and profile:GetTotalScoresWithGrade('Grade_Tier01') or -1
local tristars = profile.GetTotalScoresWithGrade and profile:GetTotalScoresWithGrade('Grade_Tier02') or -1
local doublestars = profile.GetTotalScoresWithGrade and profile:GetTotalScoresWithGrade('Grade_Tier03') or -1
local singlestars = profile.GetTotalScoresWithGrade and profile:GetTotalScoresWithGrade('Grade_Tier04') or -1

local noGetTotalScoresWithGrade = "OutFox Alpha 0.4.15 or newer required to display star counts (missing GetTotalScoresWithGrade() function)"

local w = 267
local h = 171.5
local w2 = 159
local h2 = 223.5
local offset = 44.25
local time_displayed = 5
local marquee_animation = 0.5

local showPatternInfo = true

--used to calculate the scroll speed with respect to rate mod, speed mod type, BPM ranges all respective to each player
--this was copied from ScreenPlayerOptions overlay/default.lua
--this function will eventually need to be updated to accomodate the new speed mod types supported by OutFox

local CalculateScrollSpeed = function(player)
	player   = player or GAMESTATE:GetMasterPlayerNumber()
	local pn = ToEnumShortString(player)

	local Steps = GAMESTATE:GetCurrentSong()
	local MusicRate    = SL.Global.ActiveModifiers.MusicRate or 1

	local SpeedModType = SL[pn].ActiveModifiers.SpeedModType
	local SpeedMod     = SL[pn].ActiveModifiers.SpeedMod

	local bpms = GetDisplayBPMs(player, Steps, MusicRate)
	if not (bpms and bpms[1] and bpms[2]) then return "" end

	if SpeedModType=="X" then
		bpms[1] = bpms[1] * SpeedMod
		bpms[2] = bpms[2] * SpeedMod

	elseif SpeedModType=="M" then
		bpms[1] = bpms[1] * (SpeedMod/bpms[2])
		bpms[2] = SpeedMod

	elseif SpeedModType=="C" then
		bpms[1] = SpeedMod
		bpms[2] = SpeedMod
	end

	-- format as strings
	bpms[1] = ("%.0f"):format(bpms[1])
	bpms[2] = ("%.0f"):format(bpms[2])

	if bpms[1] == bpms[2] then
		return bpms[1]
	end

	return ("%s-%s"):format(bpms[1], bpms[2])
end

-- Helper to get a profile by GUID (empty string = machine profile)
local function GetProfileByGUID(guid)
	if guid == "" then
		return PROFILEMAN:GetMachineProfile()
	end
	for i = 0, PROFILEMAN:GetNumLocalProfiles() - 1 do
		local profile = PROFILEMAN:GetLocalProfileFromIndex(i)
		if profile:GetGUID() == guid then
			return profile
		end
	end
	return nil
end

-- Helper to format lifetime gameplay time into readable text
local function FormatLifetimeText(lifetime_seconds)
	local TotalDays = math.floor(lifetime_seconds/86400)
	local TotalHours = math.floor(math.fmod(lifetime_seconds, 86400)/3600)
	local TotalMinutes = math.floor(math.fmod(lifetime_seconds,3600)/60)
	
	if TotalDays > 1 and TotalHours == 1 then
		return TotalDays .. " days, " .. TotalHours .. " hr"
	elseif TotalDays > 1 and TotalHours ~= 1 then
		return TotalDays .. " days, " .. TotalHours .. " hrs"
	elseif TotalDays == 1 and TotalHours == 1 then
		return TotalDays .. " day, " .. TotalHours .. " hr"
	elseif TotalDays == 1 and TotalHours ~= 1 then
		return TotalDays .. " day, " .. TotalHours .. " hrs"
	elseif TotalDays <= 0 and TotalHours > 1 and TotalMinutes > 1 then
		return TotalHours .. " hrs, " .. TotalMinutes .. " mins"
	elseif TotalDays <= 0 and TotalHours > 1 and TotalMinutes == 0 then
		return TotalHours .. " hrs, " .. TotalMinutes .. " mins"
	elseif TotalDays <= 0 and TotalHours > 1 and TotalMinutes == 1 then
		return TotalHours .. " hrs, " .. TotalMinutes .. " min"
	elseif TotalDays <= 0 and TotalHours == 1 and TotalMinutes == 1 then
		return TotalHours .. " hr, " .. TotalMinutes .. " min"
	elseif TotalDays <= 0 and TotalHours == 1 and TotalMinutes ~= 1 then
		return TotalHours .. " hr, " .. TotalMinutes .. " mins"
	elseif TotalDays <= 0 and TotalHours <= 0 and TotalMinutes ~= 1 then
		return TotalMinutes .. " mins"
	elseif TotalDays <= 0 and TotalHours <= 0 and TotalMinutes == 1 then
		return TotalMinutes .. " min"
	end
end

--this code was taken from ScreenGameOver overlay/PlayerStatsWithoutProfile.lua
--this code will calculate Steps Hit during the session and for how long a session lasted
local totalTime = 0
local songsPlayedThisGame = 0
local notesHitThisGame = 0

-- Use pairs here (instead of ipairs) because this player might have late-joined
-- which will result in nil entries in the the Stats table, which halts ipairs.
-- We're just summing total time anyway, so order doesn't matter.
for i,stats in pairs( SL[ToEnumShortString(player)].Stages.Stats ) do
	totalTime = totalTime + (stats and stats.duration or 0)
	songsPlayedThisGame = songsPlayedThisGame + (stats and 1 or 0)

	if stats and stats.column_judgments then
		-- increment notesHitThisGame by the total number of tapnotes hit in this particular stepchart by using the per-column data
		-- don't rely on the engine's non-Miss judgment counts here for two reasons:
		-- 1. we want jumps/hands to count as more than 1 here
		-- 2. stepcharts can have non-1 #COMBOS parameters set which would artbitraily inflate notesHitThisGame

		for column, judgments in ipairs(stats.column_judgments) do
			if judgments then
				for judgment, judgment_count in pairs(judgments) do
					if judgment ~= "Miss" then
						notesHitThisGame = notesHitThisGame + judgment_count
					end
				end
			end
		end
	end
end

local hours = math.floor(totalTime/3600)
local minutes = math.floor((totalTime-(hours*3600))/60)
local seconds = round(totalTime%60)

----------Single Player Mode Player Profile
if GAMESTATE:GetNumPlayersEnabled() == 1 then return Def.ActorFrame{
	Name="PlayerProfile_" .. pn,

	PlayerJoinedMessageCommand=function(self, params)
		if params.Player == player then
			self:queuecommand("Appear" .. pn)
		end
	end,

	PlayerUnjoinedMessageCommand=function(self, params)
		if params.Player == player then
			self:queuecommand("Appear" .. pn)
		end
	end,

    -- When a new profile is selected from ScreenSelectProfile, reset to Guest defaults if needed
    NewProfileSelectedMessageCommand=function(self, params)
        if params and params.PlayerNumber == player then
            if (not params.NewProfileGUID) or params.NewProfileGUID == "" then
                LoadGuest(player)
                ApplyMods(player)
            end
        end
    end,

	-- depending on the value of pn, this will either become
	-- an AppearP1Command or an AppearP2Command when the screen initializes
	["Appear"..pn.."Command"]=function(self)
		--rather than deal with Guest profile tracking, let's just not show a profile card for players that didn't bother to set up a profile
		if PROFILEMAN:IsPersistentProfile(player) then
			self:visible(true)
		else
			self:visible(false)
		end
	end,

	InitCommand=function(self)
		self:visible( false ):halign( p )
		self:y(SCREEN_TOP + 73)

		if player == PLAYER_1 then
			self:x( _screen.cx - 293.5)

		elseif player == PLAYER_2 then
				self:x( _screen.cx + 294)
		end

		if GAMESTATE:IsHumanPlayer(player) then
			self:queuecommand("Appear" .. pn)
		end
	end,

	CodeMessageCommand=function(self, params)
		-- on ScreenSelectMusic, this screen code is reused to instead toggle player profile views
		if params.Name == "TogglePatternInfo" and params.PlayerNumber == player then
            if (ThemePrefs.Get("FolderStats")) or not (ThemePrefs.Get("MusicWheelGS") ~= "Scorebox") then
                showPatternInfo = not showPatternInfo
                self:queuecommand("TogglePatternInfo")
            end
		end
	end,

	TogglePatternInfoCommand=function(self)
		self:visible(not showPatternInfo)
	end,

  	--background quad
	Def.Quad{
    	InitCommand = function(self)
        	self:zoomto(w,h)
        	self:diffuse(color("#1e282f")):diffusealpha(0.65)
			self:y(offset)
      	end
	},

 	--Profile Name
  	LoadFont("Common Normal")..{
      	Text = "Profile Name",
      	InitCommand = function(self)
			self:horizalign(center)
			self:xy(42,-30)
			self:settext(profile_name)
      	end,
		NewProfileSelectedMessageCommand = function(self, params)
			if params and params.PlayerNumber == player and params.NewProfileGUID then
				local new_profile = GetProfileByGUID(params.NewProfileGUID)
				if new_profile then
					self:settext(new_profile:GetDisplayName())
				end
			end
		end,
  	},

	--Total Number Of Songs Completed
  	LoadFont("Common Normal")..{
      	Text = "Total Songs Completed",
     	InitCommand = function(self)
			self:horizalign(center)
			self:xy(42,-5)
			self:zoom(0.8)
			self:settext("Total Songs Completed: ".. commify(profile:GetNumTotalSongsPlayed()))
      	end,
		NewProfileSelectedMessageCommand = function(self, params)
			if params and params.PlayerNumber == player and params.NewProfileGUID then
				local new_profile = GetProfileByGUID(params.NewProfileGUID)
				if new_profile then
					self:settext("Total Songs Completed: ".. commify(new_profile:GetNumTotalSongsPlayed()))
				end
			end
		end,
 	},

	-- Profile photo
	Def.Sprite{
		InitCommand=function(self)
			self:x(-92)
		end,

		OnCommand=function(self)
			if avatar == nil and self:GetTexture() ~= nil then
				self:Load(nil):diffusealpha(0):visible(false)
				return
			end

			-- only read from disk if not currently set
			if self:GetTexture() == nil then
				self:Load(avatar):finishtweening():linear(0.075):diffusealpha(1)

				self:horizalign(center)

				self:setsize(80,80)
			end
		end,
	},

	-- fallback avatar
	Def.ActorFrame{
		InitCommand=function(self) self:visible(false):xy(-132,-40) end,
		OnCommand=function(self)
			if avatar == nil then
				self:visible(true)
			else
				self:visible(false)
			end
		end,

		Def.Quad{
			InitCommand=function(self)
				self:align(0,0):zoomto(80,80):diffuse(color("#283239aa"))
			end
		},
		LoadActor(THEME:GetPathG("", "_VisualStyles/".. ThemePrefs.Get("VisualStyle") .."/SelectColor"))..{
			InitCommand=function(self)
				self:align(0.5,0):zoom(0.09):diffusealpha(0.9):xy(40,8)
			end
		},
		LoadFont("Common Normal")..{
			Text=THEME:GetString("ProfileAvatar","NoAvatar"),
			InitCommand=function(self)
				self:horizalign(center):zoom(0.815):diffusealpha(0.9):xy(40,71)
			end,
		}
	},

 	-- Quad Star
	Def.Sprite{
    	Texture = (THEME:GetPathG("","_grades/smallgrades 1x18.png")),
    	InitCommand = function(self)
			self:animate(false):setstate(0)
			self:zoom(0.2):xy(-25,15)
		end,
 	},

	--Quads Value
	LoadFont("Common Normal")..{
		Text = "",
		InitCommand = function(self)
			self:horizalign(center)
			self:xy(-25,32)
			if quads >= 0 then
				self:settext(commify(quads))
			else end
			self:zoom(0.7):maxwidth(40)
		end,
		NewProfileSelectedMessageCommand = function(self, params)
			if params and params.PlayerNumber == player and params.NewProfileGUID then
				local new_profile = GetProfileByGUID(params.NewProfileGUID)
				if new_profile and new_profile.GetTotalScoresWithGrade then
					local quads = new_profile.GetTotalScoresWithGrade and new_profile:GetTotalScoresWithGrade('Grade_Tier01') or -1
					self:settext(commify(quads))
				end
			end
		end,
	},

	-- Tri Star
	Def.Sprite{
		Texture = (THEME:GetPathG("","_grades/smallgrades 1x18.png")),
		InitCommand = function(self)
			self:animate(false):setstate(1)
			self:zoom(0.2):xy(18.5,15)
		end,
	},

	--Tri Value
	LoadFont("Common Normal")..{
		Text = "",
		InitCommand = function(self)
			self:horizalign(center)
			self:xy(18.5,32)
			if tristars >= 0 then
				self:settext(commify(tristars))
			else end
			self:zoom(0.7)
		end,
		NewProfileSelectedMessageCommand = function(self, params)
			if params and params.PlayerNumber == player and params.NewProfileGUID then
				local new_profile = GetProfileByGUID(params.NewProfileGUID)
				if new_profile and new_profile.GetTotalScoresWithGrade then
					local tristars = new_profile.GetTotalScoresWithGrade and new_profile:GetTotalScoresWithGrade('Grade_Tier02') or -1
					self:settext(commify(tristars))
				end
			end
		end,
	},

	-- Double Star
	Def.Sprite{
		Texture = (THEME:GetPathG("","_grades/smallgrades 1x18.png")),
		InitCommand = function(self)
			self:animate(false):setstate(2)
			self:zoom(0.2):xy(62,15)
		end,
	},

	--Double Value
	LoadFont("Common Normal")..{
		Text = "",
		InitCommand = function(self)
			self:horizalign(center)
			self:xy(62,32)
			if doublestars >= 0 then
				self:settext(commify(doublestars))
			else end
			self:zoom(0.7)
		end,
		NewProfileSelectedMessageCommand = function(self, params)
			if params and params.PlayerNumber == player and params.NewProfileGUID then
				local new_profile = GetProfileByGUID(params.NewProfileGUID)
				if new_profile and new_profile.GetTotalScoresWithGrade then
					local doublestars = new_profile.GetTotalScoresWithGrade and new_profile:GetTotalScoresWithGrade('Grade_Tier03') or -1
					self:settext(commify(doublestars))
				end
			end
		end,
	},

	-- Single Star
	Def.Sprite{
		Texture = (THEME:GetPathG("","_grades/smallgrades 1x18.png")),
		InitCommand = function(self)
			self:animate(false):setstate(3)
			self:zoom(0.2):xy(105,15)
		end,
	},

	--Single Value
	LoadFont("Common Normal")..{
		Text = "",
		InitCommand = function(self)
			self:horizalign(center)
			self:xy(105,32)
			if singlestars >= 0 then
				self:settext(commify(singlestars))
			else end
			self:zoom(0.7)
		end,
		NewProfileSelectedMessageCommand = function(self, params)
			if params and params.PlayerNumber == player and params.NewProfileGUID then
				local new_profile = GetProfileByGUID(params.NewProfileGUID)
				if new_profile and new_profile.GetTotalScoresWithGrade then
					local singlestars = new_profile.GetTotalScoresWithGrade and new_profile:GetTotalScoresWithGrade('Grade_Tier04') or -1
					self:settext(commify(singlestars))
				end
			end
		end,
	},

	--error message displayed to users if GetTotalScoresWithGrade() function isn't available
	LoadFont("Common Normal")..{
		Text = "",
		InitCommand = function(self)
			self:horizalign(center)
			self:xy(42,33)
			self:zoom(0.5)
			self:wrapwidthpixels(350)
			self:vertspacing(-5)
			if quads < 0 then
				self:settext(noGetTotalScoresWithGrade)
			else end
		end,
	},

	-- thin white line separating stats from mods
	Def.Quad {
		InitCommand=function(self)
			self:zoomto(w-20,2):xy(0,47):diffusealpha(0.5)
		end,
	},

	--Number of times current song attemped
	LoadFont("Common Normal")..{
		Text = "Number Times Song Attempted",
		CurrentSongChangedMessageCommand=function(self) self:playcommand("Set") end,
		InitCommand = function(self)
			self:horizalign(center)
			self:y(59)
			self:zoom(0.8)
		end,
		SetCommand=function(self)
			if GAMESTATE:GetCurrentSong() == nil then
				self:settext("")
			else
				self:settext("Times Song Attempted: "..commify(PROFILEMAN:GetSongNumTimesPlayed(GAMESTATE:GetCurrentSong(),p)))
			end
		end,
		NewProfileSelectedMessageCommand = function(self, params)
			if params and params.PlayerNumber == player and params.NewProfileGUID then
				local new_profile = GetProfileByGUID(params.NewProfileGUID)
				if new_profile and GAMESTATE:GetCurrentSong() then
					self:settext("Times Song Attempted: "..commify(new_profile:GetSongNumTimesPlayed(GAMESTATE:GetCurrentSong())))
				end
			end
		end,
	},

	--Speed Mod Label
	LoadFont("Common Normal")..{
		Text = "SPEED MOD",
		InitCommand = function(self)
			self:horizalign(left)
			self:xy(-127,77)
			self:zoom(0.7)
			self:diffuse(color("0.5,0.5,0.5,1"))
		end,
	},

	--Speed Mod Value
  	LoadFont("Common Normal")..{
		Text = "Speed Mod",
		InitCommand = function(self)
			self:horizalign(left)
			self:xy(-73,77)
			self:zoom(0.7)
			self:queuecommand("Set")
  		end,
		CurrentSongChangedMessageCommand=function(self) self:playcommand("Set") end,
		SetCommand=function(self)
			if GAMESTATE:GetCurrentSong() == nil then
				self:settext("")
			else
				self:settext(SL[pn].ActiveModifiers.SpeedModType..SL[pn].ActiveModifiers.SpeedMod)
			end
		end,
	},

	--Scroll Rate Label
	LoadFont("Common Normal")..{
		Text = "SCROLL RATE",
		InitCommand = function(self)
			self:horizalign(right)
			self:xy(127,77)
			self:zoom(0.7)
			self:diffuse(color("0.5,0.5,0.5,1"))
		end,
	},

	--Scroll Rate Value
	LoadFont("Common Normal")..{
		Text = "Scroll Rate",
		InitCommand = function(self)
			self:horizalign(right)
			self:xy(65,77)
			self:zoom(0.7)
			self:queuecommand("Set")
		end,
		CurrentSongChangedMessageCommand=function(self) self:playcommand("Set") end,
		SetCommand=function(self)
			if GAMESTATE:GetCurrentSong() == nil then
				self:settext("")
			else
				self:settext(("%s%s"):format(SL[pn].ActiveModifiers.SpeedModType, CalculateScrollSpeed(player)))
			end
		end,
	},

	-- thin white line separating mods from profile stats
	Def.Quad {
		InitCommand=function(self)
			self:zoomto(w-20,2):xy(0,90):diffusealpha(0.5)
		end,
	},

	--lifetime stats, marquee in and out, starts as visible
	Def.ActorFrame{
		InitCommand=function(self)
			-- add extra 0.5 sec sleep commands so that, visually, one element is nearly completely faded out before the next one starts to fade in
			self:diffusealpha(1):sleep(time_displayed):linear(marquee_animation):diffusealpha(0):sleep(0.5):sleep(time_displayed+0.5):linear(marquee_animation):diffusealpha(1):queuecommand("Init")
		end,
		OffCommand=function(self) self:stoptweening() end,

		--Time Spent In Gameplay Label (Lifetime)
		LoadFont("Common Normal")..{
			Text = "LIFETIME PLAYED",
			InitCommand = function(self)
				self:horizalign(center)
				self:xy(-51,102)
				self:zoom(0.7)
				self:diffuse(color("0.5,0.5,0.5,1"))
			end,
		},
		--Time Spent In Gameplay (Lifetime)
		LoadFont("Common Normal")..{
			Text = "LifetimeGameplayValue",
			InitCommand = function(self)
				local Lifetime = profile:GetTotalGameplaySeconds()
				self:horizalign(center)
				self:xy(-51,116)
				self:zoom(0.7)
				self:settext(FormatLifetimeText(Lifetime))
			end,
			NewProfileSelectedMessageCommand = function(self, params)
				if params and params.PlayerNumber == player and params.NewProfileGUID then
					local new_profile = GetProfileByGUID(params.NewProfileGUID)
					if new_profile then
						local Lifetime = new_profile:GetTotalGameplaySeconds()
						self:settext(FormatLifetimeText(Lifetime))
					end
				end
			end,
		},

		--Lifetime Steps Label
		LoadFont("Common Normal")..{
			Text = "LIFETIME STEPS",
			InitCommand = function(self)
				self:horizalign(center)
				self:xy(51,102)
				self:zoom(0.7)
				self:diffuse(color("0.5,0.5,0.5,1"))
			end,
		},

		--Lifetime Steps Value
	    LoadFont("Common Normal")..{
			Text = "NotesHitLifetimeValue",
			InitCommand = function(self)
				self:horizalign(center)
				self:xy(51,116)
				self:zoom(0.7)
				self:settext(commify(profile:GetTotalTapsAndHolds()))
			end,
			NewProfileSelectedMessageCommand = function(self, params)
				if params and params.PlayerNumber == player and params.NewProfileGUID then
					local new_profile = GetProfileByGUID(params.NewProfileGUID)
					if new_profile then
						self:settext(commify(new_profile:GetTotalTapsAndHolds()))
					end
				end
			end,
	    },
	},

	--in Pay Modes, I understand that these set metrics might not make sense to most users
	--even though the data shown would be per-set and not per-day, I think that's overall valuable to the player and should not be removed in pay modes

	--set stats, marquee in and out, starts as hidden
	Def.ActorFrame{
		InitCommand=function(self)
			-- add extra 0.5 sec sleep commands so that, visually, one element is nearly completely faded out before the next one starts to fade in
			self:diffusealpha(0):sleep(time_displayed+0.5):linear(marquee_animation):diffusealpha(1):sleep(time_displayed):linear(marquee_animation):diffusealpha(0):sleep(0.5):queuecommand("Init")
		end,
		OffCommand=function(self) self:stoptweening() end,

			
		--Time Spent In Gameplay Label
		LoadFont("Common Normal")..{
			Text = "TIME PLAYED",
			InitCommand = function(self)
				self:horizalign(center)
				self:xy(-89,102)
				self:zoom(0.7)
				self:diffuse(color("0.5,0.5,0.5,1"))
			end,
		},

		--Time Spent In Gameplay Value
		LoadFont("Common Normal")..{
			Text = "TimePlayedThisSetValue",
			InitCommand = function(self)
				self:horizalign(center)
				self:xy(-89,116)
				self:zoom(0.7)
				if hours > 1 then
					self:settext(hours .. " hrs, " .. minutes .. " mins")
				elseif hours == 1 then
					self:settext(hours .. " hr, " .. minutes .. " mins")
				else
					self:settext(minutes .. " mins")
				end
			end,
		},

		--Songs Played This Set Label
		LoadFont("Common Normal")..{
			Text = "PLAYED THIS SET",
			InitCommand = function(self)
				self:horizalign(center)
				self:y(102)
				self:zoom(0.7)
				self:diffuse(color("0.5,0.5,0.5,1"))
			end,
		},

		--Songs Played This Set Value
		LoadFont("Common Normal")..{
			Text = "SongsPlayedThisSetValue",
			InitCommand = function(self)
				self:horizalign(center)
				self:y(116)
				self:zoom(0.7)
				if songsPlayedThisGame == 1 then
					self:settext(songsPlayedThisGame.." Song")
				else
					self:settext(songsPlayedThisGame.." Songs")
				end
			end,
		},

		--Steps Hit This Set Label
		LoadFont("Common Normal")..{
			Text = "STEPS HIT",
			InitCommand = function(self)
				self:horizalign(center)
				self:xy(89,102)
				self:zoom(0.7)
				self:diffuse(color("0.5,0.5,0.5,1"))
			end,
		},

		--Steps Hit This Set Value
		LoadFont("Common Normal")..{
			Text = "notesHitThisGameValue",
			InitCommand = function(self)
				self:horizalign(center)
				self:xy(89,116)
				self:zoom(0.7)
				self:settext(commify(notesHitThisGame))
			end,
		},
	},

	--NoteSkin prieview

	--can't be used because loads at first as the default noteskin then after going to player mods and exiting out or going to GAMEPLAY will correctly display the player's chosen NoteSkin
	-- GetNoteSkinActor() is defined in ./Scripts/SL-Helpers.lua, and performs some
	-- rudimentary error handling because NoteSkins From The Internet™ may contain Lua errors
	-- LoadActor(THEME:GetPathB("","_modules/NoteSkinPreview.lua"), {noteskin_name=noteskin})..{
	-- 	OnCommand=function(self)
	-- 		self:xy(-104,76):zoom(0.55):visible(true)
	-- 	end
	-- },
}
end

----------2 Player Mode Player Profile
--the UI has to be significantly different with 2 players joined because of space constraints

if GAMESTATE:GetNumPlayersEnabled() == 2 then return Def.ActorFrame{
	Name="PlayerProfile_" .. pn,

	PlayerJoinedMessageCommand=function(self, params)
		if params.Player == player then
			self:queuecommand("Appear" .. pn)
		end
	end,

	PlayerUnjoinedMessageCommand=function(self, params)
		if params.Player == player then
			self:queuecommand("Appear" .. pn)
		end
	end,

	-- depending on the value of pn, this will either become
	-- an AppearP1Command or an AppearP2Command when the screen initializes
	["Appear"..pn.."Command"]=function(self)
		--rather than deal with Guest profile tracking, let's just not show a profile card for players that didn't bother to set up a profile
		if PROFILEMAN:IsPersistentProfile(player) then
			self:visible(true)
		else
			self:visible(false)
		end
	end,

	InitCommand=function(self)
		self:visible( false ):halign( p )
		self:y(SCREEN_TOP + 68)

		if player == PLAYER_1 then
			self:x( _screen.cx  - 347.5)

		elseif player == PLAYER_2 then
				self:x( _screen.cx + 348)
		end

		if GAMESTATE:IsHumanPlayer(player) then
			self:queuecommand("Appear" .. pn)
		end
	end,

	CodeMessageCommand=function(self, params)
		-- on ScreenSelectMusic, this screen code is reused to instead toggle player profile views
		if params.Name == "TogglePatternInfo" and params.PlayerNumber == player then
            if (ThemePrefs.Get("FolderStats")) or not (ThemePrefs.Get("MusicWheelGS") ~= "Scorebox") then
                showPatternInfo = not showPatternInfo
                self:queuecommand("TogglePatternInfo")
            end
		end
	end,

	TogglePatternInfoCommand=function(self)
		self:visible(not showPatternInfo)
	end,

	--background quad
	Def.Quad{
		InitCommand = function(self)
			self:zoomto(w2,h2)
			self:diffuse(color("#1e282f")):diffusealpha(0.65)
			self:y(75.5)
		end
	},

	--Profile Name
	LoadFont("Common Normal")..{
    	Text = "Profile Name",
    	InitCommand = function(self)
			self:horizalign(center)
			self:y(-28)
			self:zoom(0.7)
			self:settext(profile_name)
    	end,
		NewProfileSelectedMessageCommand = function(self, params)
			if params and params.PlayerNumber == player and params.NewProfileGUID then
				local new_profile = GetProfileByGUID(params.NewProfileGUID)
				if new_profile then
					self:settext(new_profile:GetDisplayName())
				end
			end
		end,
	},

	-- Profile photo
	Def.Sprite{
		InitCommand=function(self)
			self:y(15)
		end,
		OnCommand=function(self)
			if avatar == nil and self:GetTexture() ~= nil then
				self:Load(nil):diffusealpha(0):visible(false)
				return
			end

			-- only read from disk if not currently set
			if self:GetTexture() == nil then
				self:Load(avatar):finishtweening():linear(0.075):diffusealpha(1)
				self:horizalign(center)
				self:setsize(70,70)
			end
		end,
	},

	-- fallback avatar
	Def.ActorFrame{
		InitCommand=function(self) self:visible(false):y(15) end,
		OnCommand=function(self)
			if avatar == nil then
				self:visible(true)
			else
				self:visible(false)
			end
		end,

		Def.Quad{
			InitCommand=function(self)
				self:zoomto(70,70):diffuse(color("#283239aa"))
			end
		},
		LoadActor(THEME:GetPathG("", "_VisualStyles/".. ThemePrefs.Get("VisualStyle") .."/SelectColor"))..{
			InitCommand=function(self)
				self:zoom(0.09):diffusealpha(0.9):y(-5)
			end
		},
		LoadFont("Common Normal")..{
			Text=THEME:GetString("ProfileAvatar","NoAvatar"),
			InitCommand=function(self)
				self:zoom(0.55):diffusealpha(0.9):y(28)
			end,
		}
	},

	-- Quad Star
	Def.Sprite{
    	Texture = (THEME:GetPathG("","_grades/smallgrades 1x18.png")),
    	InitCommand = function(self)
			self:animate(false):setstate(0)
			self:zoom(0.15):xy(-55,-13)
		end,
	},

	--Quads Value
	LoadFont("Common Normal")..{
		Text = "???",
		InitCommand = function(self)
			self:horizalign(center)
			self:xy(-55,2)
			if quads >= 0 then
				self:settext(commify(quads))
			else end
			self:zoom(0.55):maxwidth(40)
		end,
		NewProfileSelectedMessageCommand = function(self, params)
			if params and params.PlayerNumber == player and params.NewProfileGUID then
				local new_profile = GetProfileByGUID(params.NewProfileGUID)
				if new_profile then
					local quads = new_profile.GetTotalScoresWithGrade and new_profile:GetTotalScoresWithGrade('Grade_Tier01') or -1
					if quads >= 0 then
						self:settext(commify(quads))
					end
				end
			end
		end,
	},

	-- Tri Star
	Def.Sprite{
		Texture = (THEME:GetPathG("","_grades/smallgrades 1x18.png")),
		InitCommand = function(self)
			self:animate(false):setstate(1)
			self:zoom(0.15):xy(55,-13)
		end,
	},

	--Tri Value
	LoadFont("Common Normal")..{
		Text = "???",
		InitCommand = function(self)
			self:horizalign(center)
			self:xy(55,2)
			if tristars >= 0 then
				self:settext(commify(tristars))
			else end
			self:zoom(0.55)
		end,
		NewProfileSelectedMessageCommand = function(self, params)
			if params and params.PlayerNumber == player and params.NewProfileGUID then
				local new_profile = GetProfileByGUID(params.NewProfileGUID)
				if new_profile then
					local tristars = new_profile.GetTotalScoresWithGrade and new_profile:GetTotalScoresWithGrade('Grade_Tier02') or -1
					if tristars >= 0 then
						self:settext(commify(tristars))
					end
				end
			end
		end,
	},

	-- Double Star
	Def.Sprite{
		Texture = (THEME:GetPathG("","_grades/smallgrades 1x18.png")),
		InitCommand = function(self)
			self:animate(false):setstate(2)
			self:zoom(0.15):xy(-55,27)
		end,
	},

	--Double Value
	LoadFont("Common Normal")..{
		Text = "???",
		InitCommand = function(self)
			self:horizalign(center)
			self:xy(-55,44)
			if doublestars >= 0 then
				self:settext(commify(doublestars))
			else end
			self:zoom(0.55)
		end,
		NewProfileSelectedMessageCommand = function(self, params)
			if params and params.PlayerNumber == player and params.NewProfileGUID then
				local new_profile = GetProfileByGUID(params.NewProfileGUID)
				if new_profile then
					local doublestars = new_profile.GetTotalScoresWithGrade and new_profile:GetTotalScoresWithGrade('Grade_Tier03') or -1
					if doublestars >= 0 then
						self:settext(commify(doublestars))
					end
				end
			end
		end,
	},

	-- Single Star
	Def.Sprite{
		Texture = (THEME:GetPathG("","_grades/smallgrades 1x18.png")),
		InitCommand = function(self)
			self:animate(false):setstate(3)
			self:zoom(0.15):xy(55,27)
		end,
	},

	--Single Value
	LoadFont("Common Normal")..{
		Text = "???",
		InitCommand = function(self)
			self:horizalign(center)
			self:xy(55,44)
			if singlestars >= 0 then
				self:settext(commify(singlestars))
			else end
			self:zoom(0.55)
		end,
		NewProfileSelectedMessageCommand = function(self, params)
			if params and params.PlayerNumber == player and params.NewProfileGUID then
				local new_profile = GetProfileByGUID(params.NewProfileGUID)
				if new_profile then
					local singlestars = new_profile.GetTotalScoresWithGrade and new_profile:GetTotalScoresWithGrade('Grade_Tier04') or -1
					if singlestars >= 0 then
						self:settext(commify(singlestars))
					end
				end
			end
		end,
	},

	--error message displayed to users if GetTotalScoresWithGrade() function isn't available
	Def.Quad {
		InitCommand=function(self)
			self:zoomto(w2-20,35):diffuse(Color.Red):diffusealpha(0.5):rainbow():y(12)
		end,
		Condition=quads < 0
	},

	LoadFont("Common Normal")..{
		Text = "",
		InitCommand = function(self)
			self:y(12)
			self:horizalign(center)
			self:zoom(0.5)
			self:wrapwidthpixels(270)
			self:vertspacing(-5)
			if quads < 0 then
				self:settext(noGetTotalScoresWithGrade)
			else end
		end,
	},

	--Total Number Of Songs Completed
	LoadFont("Common Normal")..{
    	Text = "Total Songs Completed",
    	InitCommand = function(self)
			self:horizalign(center)
			self:y(59)
			self:zoom(0.55)
			self:settext("Total Songs Completed: ".. commify(profile:GetNumTotalSongsPlayed()))
    	end,
		NewProfileSelectedMessageCommand = function(self, params)
			if params and params.PlayerNumber == player and params.NewProfileGUID then
				local new_profile = GetProfileByGUID(params.NewProfileGUID)
				if new_profile then
					self:settext("Total Songs Completed: ".. commify(new_profile:GetNumTotalSongsPlayed()))
				end
			end
		end,
	},

	-- thin white line separating stats from mods
	Def.Quad {
		InitCommand=function(self)
			self:zoomto(w2-20,2):y(69):diffusealpha(0.5)
		end,
	},

	--Number of times current song attemped
	LoadFont("Common Normal")..{
		Text = "Number Times Song Attempted",
		CurrentSongChangedMessageCommand=function(self) self:playcommand("Set") end,
		InitCommand = function(self)
			self:horizalign(center)
			self:y(78)
			self:zoom(0.55)
		end,
		SetCommand=function(self)
			if GAMESTATE:GetCurrentSong() == nil then
				self:settext("")
			else
				self:settext("Times Song Attempted: "..commify(PROFILEMAN:GetSongNumTimesPlayed(GAMESTATE:GetCurrentSong(),p)))
			end
		end,
		NewProfileSelectedMessageCommand = function(self, params)
			if params and params.PlayerNumber == player and params.NewProfileGUID then
				local new_profile = GetProfileByGUID(params.NewProfileGUID)
				if new_profile and GAMESTATE:GetCurrentSong() then
					self:settext("Times Song Attempted: "..commify(new_profile:GetSongNumTimesPlayed(GAMESTATE:GetCurrentSong())))
				end
			end
		end,
	},

	--Speed Mod Label
	LoadFont("Common Normal")..{
		Text = "SPEED MOD",
		InitCommand = function(self)
			self:horizalign(center)
			self:xy(-40,93)
			self:zoom(0.55)
			self:diffuse(color("0.5,0.5,0.5,1"))
		end,
	},

	--Speed Mod Value
	LoadFont("Common Normal")..{
    	Text = "Speed Mod",
   		InitCommand = function(self)
			self:horizalign(center)
			self:xy(-40,104)
			self:zoom(0.55)
			self:queuecommand("Set")
    	end,
		CurrentSongChangedMessageCommand=function(self) self:playcommand("Set") end,
		SetCommand=function(self)
			if GAMESTATE:GetCurrentSong() == nil then
				self:settext("")
			else
				self:settext(SL[pn].ActiveModifiers.SpeedModType..SL[pn].ActiveModifiers.SpeedMod)
			end
		end,
	},

	--Scroll Rate Label
	LoadFont("Common Normal")..{
		Text = "SCROLL RATE",
		InitCommand = function(self)
			self:horizalign(center)
			self:xy(40,93)
			self:zoom(0.55)
			self:diffuse(color("0.5,0.5,0.5,1"))
		end,
	},

	--Scroll Rate Value
	LoadFont("Common Normal")..{
		Text = "Scroll Rate",
		InitCommand = function(self)
			self:horizalign(center)
			self:xy(40,104)
			self:zoom(0.55)
			self:queuecommand("Set")
		end,
		CurrentSongChangedMessageCommand=function(self) self:playcommand("Set") end,
		SetCommand=function(self)
			if GAMESTATE:GetCurrentSong() == nil then
				self:settext("")
			else
				self:settext(("%s%s"):format(SL[pn].ActiveModifiers.SpeedModType, CalculateScrollSpeed(player)))
			end
		end,
	},

	-- thin white line separating mods from profile stats
	Def.Quad {
		InitCommand=function(self)
			self:zoomto(w2-20,2):y(114):diffusealpha(0.5)
		end,
	},

	--in Pay Modes, I understand that these set metrics might not make sense to most users
	--even though the data shown would be per-set and not per-day, I think that's overall valuable to the player and should not be removed in pay modes

	--Time Spent In Gameplay Label
	LoadFont("Common Normal")..{
		Text = "TIME PLAYED",
		InitCommand = function(self)
			self:horizalign(center)
			self:xy(-40,122)
			self:zoom(0.55)
			self:diffuse(color("0.5,0.5,0.5,1"))
		end,
	},

	--Time Spent In Gameplay Value
	LoadFont("Common Normal")..{
		Text = "TimePlayedThisSetValue",
		InitCommand = function(self)
			self:horizalign(center)
			self:xy(-40,132)
			self:zoom(0.55)
			if hours > 1 then
				self:settext(hours .. " hrs, " .. minutes .. " mins")
			elseif hours == 1 then
				self:settext(hours .. " hr, " .. minutes .. " mins")
			else
				self:settext(minutes .. " mins")
			end
		end,
	},

	--Steps Hit This Set Label
	LoadFont("Common Normal")..{
		Text = "STEPS HIT",
		InitCommand = function(self)
			self:horizalign(center)
			self:xy(40,122)
			self:zoom(0.55)
			self:diffuse(color("0.5,0.5,0.5,1"))
		end,
	},

	--Steps Hit This Set Value
	LoadFont("Common Normal")..{
		Text = "notesHitThisGameValue",
		InitCommand = function(self)
			self:horizalign(center)
			self:xy(40,132)
			self:zoom(0.55)
			self:settext(commify(notesHitThisGame))
		end,
	},

	--Songs Played This Set Label
	LoadFont("Common Normal")..{
		Text = "PLAYED THIS SET",
		InitCommand = function(self)
			self:horizalign(center)
			self:y(144)
			self:zoom(0.55)
			self:diffuse(color("0.5,0.5,0.5,1"))
		end,
	},

	--Songs Played This Set Value
	LoadFont("Common Normal")..{
		Text = "SongsPlayedThisSetValue",
		InitCommand = function(self)
			self:horizalign(center)
			self:y(154)
			self:zoom(0.55)
			if songsPlayedThisGame == 1 then
				self:settext(songsPlayedThisGame.." Song")
			else
				self:settext(songsPlayedThisGame.." Songs")
			end
		end,
	},

	--lifetime stats

	--Time Spent In Gameplay Label (Lifetime)
	LoadFont("Common Normal")..{
		Text = "LIFETIME PLAYED",
		InitCommand = function(self)
			self:horizalign(center)
			self:xy(-40,168)
			self:zoom(0.55)
			self:diffuse(color("0.5,0.5,0.5,1"))
		end,
	},
	--Time Spent In Gameplay (Lifetime)
	LoadFont("Common Normal")..{
		Text = "LifetimeGameplayValue",
		InitCommand = function(self)
			local Lifetime = profile:GetTotalGameplaySeconds()
			self:horizalign(center)
			self:xy(-40,178)
			self:zoom(0.55)
			self:settext(FormatLifetimeText(Lifetime))
		end,
		NewProfileSelectedMessageCommand = function(self, params)
			if params and params.PlayerNumber == player and params.NewProfileGUID then
				local new_profile = GetProfileByGUID(params.NewProfileGUID)
				if new_profile then
					local Lifetime = new_profile:GetTotalGameplaySeconds()
					self:settext(FormatLifetimeText(Lifetime))
				end
			end
		end,
	},

	--Lifetime Steps Label
	LoadFont("Common Normal")..{
		Text = "LIFETIME STEPS",
		InitCommand = function(self)
			self:horizalign(center)
			self:xy(40,168)
			self:zoom(0.55)
			self:diffuse(color("0.5,0.5,0.5,1"))
		end,
	},

	--Lifetime Steps Value
	LoadFont("Common Normal")..{
		Text = "NotesHitLifetimeValue",
		InitCommand = function(self)
			self:horizalign(center)
			self:xy(40,178)
			self:zoom(0.55)
			self:settext(commify(profile:GetTotalTapsAndHolds()))
		end,
		NewProfileSelectedMessageCommand = function(self, params)
			if params and params.PlayerNumber == player and params.NewProfileGUID then
				local new_profile = GetProfileByGUID(params.NewProfileGUID)
				if new_profile then
					self:settext(commify(new_profile:GetTotalTapsAndHolds()))
				end
			end
		end,
	},
}
end
