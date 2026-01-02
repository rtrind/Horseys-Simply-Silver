local path = "/"..THEME:GetCurrentThemeDirectory().."Graphics/_FallbackBanners/"..ThemePrefs.Get("VisualStyle")
local banner_directory = FILEMAN:DoesFileExist(path) and path or THEME:GetPathG("","_FallbackBanners/Arrows")

local song = GAMESTATE:GetCurrentSong()

-- Reference to actor pool for memory management
local Pool = SL and SL.ActorPool or nil

local bannerWidth = 418
local bannerHeight = 164

local t = Def.ActorFrame{
	OnCommand=function(self)
		self:zoom(0.7655)
		self:xy(_screen.cx, SCREEN_TOP+94.5)
	end
}

-- fallback banner
t[#t+1] = Def.Sprite{
	Name="FallbackBanner",
	Texture=banner_directory.."/banner"..SL.Global.ActiveColorIndex.." (doubleres).png",
	InitCommand=function(self) 
		self:setsize(bannerWidth, bannerHeight) 
		-- Register with pool for tracking
		if Pool then Pool.RegisterBanner("FallbackBannerSprite", self) end
	end,

	CurrentSongChangedMessageCommand=function(self) self:playcommand("Set") end,
	CurrentCourseChangedMessageCommand=function(self) self:playcommand("Set") end,
	FocusedGroupChangedMessageCommand=function(self, params)
		-- Show fallback if group has no banner
		if params and params.group then
			local group_banner_path = SONGMAN:GetSongGroupBannerPath(params.group)
			if not group_banner_path or group_banner_path == "" then
				self:visible(true)
			else
				self:visible(false)
			end
		else
			self:visible(false)
		end
	end,

	SetCommand=function(self)
		-- if ShowBanners preference is false, always just show the fallback banner
		-- don't bother assessing whether to draw or not draw
		if PREFSMAN:GetPreference("ShowBanners") == false then return end

		if song and song:HasBanner() then
			self:visible(false)
		else
			self:visible(true)
		end
	end
}

t[#t+1] = Def.Sprite{
	Name="GroupBanner",
	InitCommand=function(self)
		self:setsize(bannerWidth, bannerHeight)
		self:visible(false)
		-- Register with pool for tracking
		if Pool then Pool.RegisterBanner("GroupBannerSprite", self) end
	end,
	OnCommand=function(self)
		self:playcommand("Set")
	end,
	CurrentSongChangedMessageCommand=function(self)
		self:playcommand("Set")
	end,
	CurrentCourseChangedMessageCommand=function(self)
		self:playcommand("Set")
	end,
	FocusedGroupChangedMessageCommand=function(self, params)
		-- Show group banner when group is focused
		if params and params.group then
			local group_banner_path = SONGMAN:GetSongGroupBannerPath(params.group)
			if group_banner_path and group_banner_path ~= "" then
				self:Load(group_banner_path)
				self:setsize(bannerWidth, bannerHeight)
				self:visible(true)
			else
				self:visible(false)
			end
		else
			self:visible(false)
		end
	end,
	SetCommand=function(self)
		-- Show group banner as fallback if song has no banner
		song = GAMESTATE:GetCurrentSong()
		if song and not song:HasBanner() then
			local group_banner_path = SONGMAN:GetSongGroupBannerPath(song:GetGroupName())
			if group_banner_path and group_banner_path ~= "" then
				self:Load(group_banner_path)
				self:setsize(bannerWidth, bannerHeight)
				self:visible(true)
			else
				self:visible(false)
			end
		else
			self:visible(false)
		end
	end,
}

if PREFSMAN:GetPreference("ShowBanners") then
	t[#t+1] = Def.Banner{
		Name="SongBanner",
		InitCommand=function(self)
			self:setsize(bannerWidth, bannerHeight)
			-- Register with pool for tracking
			if Pool then Pool.RegisterBanner("BannerSprite", self) end
		end,
		CurrentSongChangedMessageCommand=function(self)
			self:playcommand("Set")
		end,
		CurrentCourseChangedMessageCommand=function(self)
			self:playcommand("Set")
		end,
		SetCommand=function(self)
			song = GAMESTATE:GetCurrentSong()
			if song and song:HasBanner() then
				self:LoadFromSong(song)
				self:setsize(bannerWidth, bannerHeight)
				self:visible(true)
			else
				self:visible(false)
			end
		end
	}
end

-- the MusicRate Quad and text
t[#t+1] = Def.ActorFrame{
	InitCommand=function(self)
		self:visible( SL.Global.ActiveModifiers.MusicRate ~= 1 ):y(75)
	end,

	--quad behind the music rate text
	Def.Quad{
		InitCommand=function(self) self:diffuse( color("#1E282FCC") ):zoomto(418,14) end
	},

	--the music rate text
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		InitCommand=function(self) self:shadowlength(1):zoom(0.85) end,
		OnCommand=function(self)
			self:settext(("%g"):format(SL.Global.ActiveModifiers.MusicRate) .. "x " .. THEME:GetString("OptionTitles", "MusicRate"))
		end
	}
}

if ThemePrefs.Get("ShowCDTitles") then
	t[#t+1] = Def.Sprite {
		InitCommand=function(self)
			-- Register with pool for tracking
			if Pool then Pool.RegisterBanner("CDTitleSprite", self) end
			self:draworder(101)
		end,
		OnCommand=function(self)
			self:playcommand("SetCD")
		end,
		CurrentSongChangedMessageCommand=function(self) self:playcommand("SetCD") end,
		SwitchFocusToGroupsMessageCommand=function(self) self:GetChild("CdTitle"):visible(false) end,
		SetCDCommand=function(self)
			song = GAMESTATE:GetCurrentSong()
			if song and song:HasCDTitle() then
				self:visible(true)
				self:Load( GAMESTATE:GetCurrentSong():GetCDTitlePath() )
				local dim1, dim2 = math.max(self:GetWidth(), self:GetHeight()), math.min(self:GetWidth(), self:GetHeight())
				local ratio = math.max(dim1 / dim2, 2.5)

				local toScale = self:GetWidth() > self:GetHeight() and self:GetWidth() or self:GetHeight()
				self:xy((bannerWidth - 30) / 2, (bannerHeight - 30)/ 2)
				self:zoom(22 / toScale * ratio)
				self:finishtweening():addrotationy(0):linear(.5):addrotationy(360)
			else
				self:visible(false)
			end
		end
	}
end

return t