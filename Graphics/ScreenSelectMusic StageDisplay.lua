local curScreen = Var "LoadingScreen"
local curStage = GAMESTATE:GetCurrentStage()
local curStageIndex = GAMESTATE:GetCurrentStageIndex()
local t = Def.ActorFrame {}

if not PREFSMAN:GetPreference("EventMode") then
	t[#t+1] = Def.ActorFrame {
		LoadFont(ThemePrefs.Get("ThemeFont") .. " Header")..{
			InitCommand=function(self)
				self:zoom( 0.6 )
				self:y( 9 / self:GetZoom() )
				self:diffusealpha(0):x(_screen.cx)
			end,
			OnCommand=function(self)
				self:sleep(0.1):decelerate(0.33):diffusealpha(1)
			end,
			BeginCommand=function(self)
				local top = SCREENMAN:GetTopScreen()
				if top then
					if not string.find(top:GetName(),"ScreenEvaluation") then
						curStageIndex = curStageIndex + 1
					end
				end
				self:playcommand("Set")
			end,
			SetCommand=function(self)
				local SongCost = (IsMarathon and 3) or (IsLong and 2) or 1
				if GAMESTATE:GetCurrentCourse() then
					self:settext( curStageIndex+1 .. " / " .. GAMESTATE:GetCurrentCourse():GetEstimatedNumStages() )
				else
					self:settextf("%s Stage", ToEnumShortString(curStage))
				end
				-- diffuse red on the final stage, but stay white otherwise
				-- StageToColor() is a function defined in _fallback/Scripts/02 Colors.lua
				if curStage == "Stage_Final" then
					-- FIXME: there's a really hilarious edge case whereby if _header.lua is recolored to red, this will be hard to see
					self:diffuse(StageToColor(curStage))
				else end
			end,
		}
	}
	return t
else end