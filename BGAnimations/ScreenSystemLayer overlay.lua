-- This is mostly copy/pasted directly from SM5's _fallback theme with
-- very minor modifications.

local t = Def.ActorFrame{
	
	-- Debug: Log screen changes
	ScreenChangedMessageCommand=function(self)
		if SL_Debug then
			local screen = SCREENMAN:GetTopScreen()
			if screen then
				SL_Debug.LogScreenChange(screen:GetName())
			end
		end
	end,
}

-- Debug: Periodic status logging actor
t[#t+1] = Def.Actor{
	InitCommand=function(self)
		-- Update every second to check if we need to log periodic status
		self:sleep(1):queuecommand("PeriodicCheck")
	end,
	PeriodicCheckCommand=function(self)
		if SL_Debug then
			SL_Debug.LogPeriodicStatus()
		end
		self:sleep(1):queuecommand("PeriodicCheck")
	end,
}

-- -----------------------------------------------------------------------

local function CreditsText( player )
	return LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal") .. {
		InitCommand=function(self)
			self:visible(false)
			self:name("Credits" .. PlayerNumberToString(player))
			ActorUtil.LoadAllCommandsAndSetXY(self,Var "LoadingScreen")
		end,
		VisualStyleSelectedMessageCommand=function(self) self:playcommand("UpdateVisible") end,
		UpdateTextCommand=function(self)
			-- this feels like a holdover from SM3.9 that just never got updated
			local str = ScreenSystemLayerHelpers.GetCreditsMessage(player)
			self:settext(str)
		end,
		UpdateVisibleCommand=function(self)
			local screen = SCREENMAN:GetTopScreen()
			local bShow = true

			local textColor = Color.White
			local shadowLength = 0

			if screen then
				bShow = THEME:GetMetric( screen:GetName(), "ShowCreditDisplay" )

				local screenName = screen:GetName()
				if screenName == "ScreenTitleMenu" or screenName == "ScreenTitleJoin" or screenName == "ScreenLogo" then
				elseif (screen:GetName() == "ScreenEvaluationNonstop") or (screen:GetName() == "ScreenGameplay") then
					-- ignore ShowCreditDisplay metric for ScreenEval
					-- only show this BitmapText actor on Evaluation if the player is joined
					bShow = GAMESTATE:IsHumanPlayer(player)
					--        I am not human^
					--        today, but there's always hope
					--        I'll see tomorrow

					-- dark text for RainbowMode
					if ThemePrefs.Get("RainbowMode") then
						textColor = Color.Black
					end
				-- 16:9 only: player name not shown on ScreenEvaluation (shown in profile card)
				elseif (screen:GetName() == "ScreenEvaluationStage") or (screen:GetName() == "ScreenSelectMusic") then
					bShow = false
				end
			end

			self:visible( bShow )
			self:diffuse(textColor)
			self:shadowlength(shadowLength)
		end
	}
end

-- -----------------------------------------------------------------------
-- player avatars
-- see: https://youtube.com/watch?v=jVhlJNJopOQ

for player in ivalues(PlayerNumber) do
	t[#t+1] = Def.Sprite{
		ScreenChangedMessageCommand=function(self)   self:queuecommand("Update") end,
		PlayerJoinedMessageCommand=function(self, params)   if params.Player==player then self:queuecommand("Update") end end,
		PlayerUnjoinedMessageCommand=function(self, params) if params.Player==player then self:queuecommand("Update") end end,
		PlayerProfileSetMessageCommand=function(self, params) if params.Player==player then self:queuecommand("Update") end end,

		UpdateCommand=function(self)
			local path = GetPlayerAvatarPath(player)

			if path == nil and self:GetTexture() ~= nil then
				self:Load(nil):diffusealpha(0):visible(false)
				return
			end

			-- only read from disk if not currently set or if the path has changed
			if self:GetTexture() == nil or path ~= self:GetTexture():GetPath() then
				self:Load(path):finishtweening():linear(0.075):diffusealpha(1)

				local dim = 32
				local h   = (player==PLAYER_1 and left or right)
				local x   = (player==PLAYER_1 and    0 or _screen.w)

				self:horizalign(h):vertalign(bottom)
				self:xy(x, _screen.h):setsize(dim,dim)
			end

			local screen = SCREENMAN:GetTopScreen()
			if screen then
				if THEME:HasMetric(screen:GetName(), "ShowPlayerAvatar") then
					-- 16:9 only: avatars not shown on ScreenEvaluation (profile card has space)
					if  screen:GetName() == "ScreenEvaluationStage" then
						self:visible( THEME:GetMetric(screen:GetName(), "ShowCreditDisplay") )
					else
						self:visible( THEME:GetMetric(screen:GetName(), "ShowPlayerAvatar") )
					end
				else
					self:visible( THEME:GetMetric(screen:GetName(), "ShowCreditDisplay") )
				end
			end
		end,
	}
end

-- -----------------------------------------------------------------------

-- what is aux?
t[#t+1] = LoadActor(THEME:GetPathB("ScreenSystemLayer","aux"))

-- Credits
t[#t+1] = Def.ActorFrame {
 	CreditsText( PLAYER_1 ),
	CreditsText( PLAYER_2 )
}

-- "Event Mode" or CreditText at lower-center of screen
t[#t+1] = Def.BitmapText{
	Font="Mega Footer",
	InitCommand=function(self)
		self:xy(_screen.cx, _screen.h-16):zoom(0.5):horizalign(center)
	end,
	OnCommand=function(self) self:playcommand("Refresh") end,
	ScreenChangedMessageCommand=function(self) self:playcommand("Refresh") end,
	CoinModeChangedMessageCommand=function(self) self:playcommand("Refresh") end,
	CoinsChangedMessageCommand=function(self) self:playcommand("Refresh") end,
	VisualStyleSelectedMessageCommand=function(self) self:playcommand("Refresh") end,

	RefreshCommand=function(self)
		local screen = SCREENMAN:GetTopScreen()
		if ThemePrefs.Get("ThemeFont") ~= "Mega" then
			self:visible(false)
		else
			-- if this screen's Metric for ShowCreditDisplay=false, then hide this BitmapText actor
			-- PS: "ShowCreditDisplay" isn't a real Metric as far as the engine is concerned.
			-- I invented it for Simply Love and it has (understandably) confused other themers.
			-- Sorry about this.
			if screen then
				self:visible( THEME:GetMetric( screen:GetName(), "ShowCreditDisplay" ) )
			end

			--we don't want the clock and Event Mode text to overlap
			--it's possible for machine owners to want to set their machine to EVENT MODE but not HOME MODE
			--this is useful for public settings where you want to give free continuous plays but don't want to give access to the full ScreenTitleMenu
			if PREFSMAN:GetPreference("EventMode") and not GAMESTATE:GetCoinMode() == "CoinMode_Home" then
				self:settext( THEME:GetString("ScreenSystemLayer", "EventMode") )

			elseif GAMESTATE:GetCoinMode() == "CoinMode_Pay" then
				local credits = GetCredits()
				local text

				if credits.CoinsPerCredit > 1 then
					text = ("%s     %d     %d/%d"):format(
						THEME:GetString("ScreenSystemLayer", "CreditsCredits"),
						credits.Credits,
						credits.Remainder,
						credits.CoinsPerCredit
					)
				else
					text = ("%s     %d"):format(
						THEME:GetString("ScreenSystemLayer", "CreditsCredits"),
						credits.Credits
					)
				end
			end
		end
	end
}

t[#t+1] = Def.BitmapText{
	Font="Common Footer",
	InitCommand=function(self)
		self:xy(_screen.cx, _screen.h-16):zoom(0.5):horizalign(center)
	end,
	OnCommand=function(self) self:playcommand("Refresh") end,
	ScreenChangedMessageCommand=function(self) self:playcommand("Refresh") end,
	CoinModeChangedMessageCommand=function(self) self:playcommand("Refresh") end,
	CoinsChangedMessageCommand=function(self) self:playcommand("Refresh") end,
	VisualStyleSelectedMessageCommand=function(self) self:playcommand("Refresh") end,

	RefreshCommand=function(self)
		local screen = SCREENMAN:GetTopScreen()
		if ThemePrefs.Get("ThemeFont") ~= "Common" then
			self:visible(false)
		else
			-- if this screen's Metric for ShowCreditDisplay=false, then hide this BitmapText actor
			-- PS: "ShowCreditDisplay" isn't a real Metric as far as the engine is concerned.
			-- I invented it for Simply Love and it has (understandably) confused other themers.
			-- Sorry about this.
			if screen then
				self:visible( THEME:GetMetric( screen:GetName(), "ShowCreditDisplay" ) )
			end

			--we don't want the clock and Event Mode text to overlap
			--it's possible for machine owners to want to set their machine to EVENT MODE but not HOME MODE
			--this is useful for public settings where you want to give free continuous plays but don't want to give access to the full ScreenTitleMenu
			if PREFSMAN:GetPreference("EventMode") and not GAMESTATE:GetCoinMode() == "CoinMode_Home" then
				self:settext( THEME:GetString("ScreenSystemLayer", "EventMode") ):spin()

			elseif GAMESTATE:GetCoinMode() == "CoinMode_Pay" then
				local credits = GetCredits()
				local text

				if credits.CoinsPerCredit > 1 then
					text = ("%s     %d     %d/%d"):format(
						THEME:GetString("ScreenSystemLayer", "CreditsCredits"),
						credits.Credits,
						credits.Remainder,
						credits.CoinsPerCredit
					)
				else
					text = ("%s     %d"):format(
						THEME:GetString("ScreenSystemLayer", "CreditsCredits"),
						credits.Credits
					)
				end
			end
		end
	end
}

-- -----------------------------------------------------------------------
-- Modules

local function LoadModules()
	-- A table that contains a [ScreenName] -> Table of Actors mapping.
	-- Each entry will then be converted to an ActorFrame with the actors as children.
	local modules = {}
	local files = FILEMAN:GetDirListing(THEME:GetCurrentThemeDirectory().."Modules/")
	for file in ivalues(files) do
		-- Get the file extension (everything past the last period).
		local filetype = file:match("[^.]+$"):lower()
		if filetype == "lua" then
			local full_path = THEME:GetCurrentThemeDirectory().."Modules/"..file
			Trace("Loading module: "..full_path)

			-- Load the Lua file as proper lua.
			local loaded_module, error = loadfile(full_path)
			if loaded_module then
				local status, ret = pcall(loaded_module)
				if status then
					if ret ~= nil then
						for screenName, actor in pairs(ret) do
							if modules[screenName] == nil then
								modules[screenName] = {}
							end
							modules[screenName][#modules[screenName]+1] = actor
						end
					end
				else
					lua.ReportScriptError("Error executing module: "..full_path.." with error:\n    "..ret)
				end
			else
				lua.ReportScriptError("Error loading module: "..full_path.." with error:\n    "..error)
			end
		end
	end

	for screenName, table_of_actors in pairs(modules) do
		local module_af = Def.ActorFrame {
			ScreenChangedMessageCommand=function(self)
				local screen = SCREENMAN:GetTopScreen()
				if screen then
					local name = screen:GetName()
					if name == screenName then
						self:visible(true)
						self:queuecommand("Module")
					else
						self:visible(false)
					end
				else
					self:visible(false)
				end
			end,
		}
		for actor in ivalues(table_of_actors) do
			module_af[#module_af+1] = actor
		end
		t[#t+1] = module_af
	end
end

LoadModules()

-- -----------------------------------------------------------------------
-- SystemMessage stuff.
-- Put it on top of everything
-- this is what appears when someone uses SCREENMAN:SystemMessage(text)
-- or MESSAGEMAN:Broadcast("SystemMessage", {text})
-- or SM(text)

local bmt = nil

-- SystemMessage ActorFrame
t[#t+1] = Def.ActorFrame {
	SystemMessageMessageCommand=function(self, params)
		bmt:settext( params.Message )

		self:playcommand( "On" )
		if params.NoAnimate then
			self:finishtweening()
		end
		self:playcommand( "Off", params )
	end,
	HideSystemMessageMessageCommand=function(self) self:finishtweening() end,

	-- background quad behind the SystemMessage
	Def.Quad {
		InitCommand=function(self)
			self:zoomto(_screen.w, 30)
			self:horizalign(left):vertalign(top)
			self:diffuse(0,0,0,0)
		end,
		OnCommand=function(self)
			self:finishtweening():diffusealpha(0.85)
			self:zoomto(_screen.w, (bmt:GetHeight() + 16) * SL_WideScale(0.8, 1) )
		end,
		OffCommand=function(self, params)
			-- use 3.33 seconds as a default duration if none was provided as the second arg in SM()
			self:sleep(type(params.Duration)=="number" and params.Duration or 3.33):linear(0.25):diffusealpha(0)
		end,
	},

	-- BitmapText for the SystemMessage
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="Text",
		InitCommand=function(self)
			bmt = self

			self:maxwidth(_screen.w-20)
			self:horizalign(left):vertalign(top):xy(10, 10)
			self:diffusealpha(0):zoom(SL_WideScale(0.8, 1))
		end,
		OnCommand=function(self)
			self:finishtweening():diffusealpha(1)
		end,
		OffCommand=function(self, params)
			-- use 3 seconds as a default duration if none was provided as the second arg in SM()
			self:sleep(type(params.Duration)=="number" and params.Duration or 3):linear(0.5):diffusealpha(0)
		end,
	}
}
-- -----------------------------------------------------------------------

--Bottom Bar Clock
t[#t+1] = LoadFont("Common Normal")..{
	InitCommand=function(self) self:x(_screen.cx):y(SCREEN_BOTTOM-16):zoom(1):horizalign(center) end,
	OnCommand=function(self) self:playcommand("Refresh") end,
	ScreenChangedMessageCommand=function(self)
		self:playcommand("Refresh");
	end,
	CoinModeChangedMessageCommand=function(self) self:playcommand("Refresh") end,
	CoinsChangedMessageCommand=function(self) self:playcommand("Refresh") end,
	PulseMessageCommand=function(self) self:playcommand("Refresh") end,
	RefreshCommand=function(self)
		local screen = SCREENMAN:GetTopScreen()
		local bShow = true
		if screen then
			local sClass = screen:GetName()
			bShow = THEME:GetMetric( sClass, "ShowCreditDisplay" )
			 -- hide this centered credit text for certain screens,
			-- where it would more likely just be distracting and superfluous
			--I'm leaving out the clock on the player options screens because this screen isn't supposed to be "sat on"
			if sClass == "ScreenPlayerOptions"
				or sClass == "ScreenPrompt" -- this screen is an OutFox specific screen that prompts the user to upgrade to the latest OutFox client
				or sClass == "ScreenTitleMenu"
				or sClass == "ScreenEditMenu"
				or sClass == "ScreenEditOptions"
				or sClass == "ScreenMiniMenuMainMenu"
				or sClass == "ScreenPlayerOptions2"
				or sClass == "ScreenEvaluationStage"
				or sClass == "ScreenEvaluationCourse"
				or sClass == "ScreenEvaluationSummary"
				or sClass == "ScreenNameEntryActual"
				or sClass == "ScreenNameEntryTraditional"
				or sClass == "ScreenGameOver" then
				bShow = false
			end
		end
		 --don't show the clock in Free Play or Coin mode, because these modes should have the free play/coins banner
		if GAMESTATE:GetCoinMode() == "CoinMode_Pay" or GAMESTATE:GetCoinMode() == "CoinMode_Free"
			then self:visible( false )
		end
		 --as long as you are in Home Mode, the clock will be visible on the screens where it's not blacklisted
		if GAMESTATE:GetCoinMode() == "CoinMode_Home" then
			self:settext(string.format('%2i:%02i:%02i  %s %02i, %04i', Hour(), Minute(), Second(), MonthToString(MonthOfYear()), DayOfMonth(), Year()))
			self:visible( bShow )
		end
	end,
}
 --Pulse by second (used by the clock)
t[#t+1] = Def.ActorFrame {
	Def.Quad {
		PulseCommand=function(self) MESSAGEMAN:Broadcast("Pulse"); self:sleep(1); self:queuecommand("Pulse"); end;
		InitCommand=function(self) self:visible(false):playcommand("Pulse") end,
	}
}

return t
