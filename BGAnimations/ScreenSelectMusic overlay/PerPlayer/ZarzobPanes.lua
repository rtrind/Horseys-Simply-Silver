local player = ...
local pn = ToEnumShortString(player)


local showPatternInfo = true

local t = Def.ActorFrame{
    Name="GroupPanes"..pn,
    InitCommand=function(self)
        self:visible(not showPatternInfo)
    end,

    CodeMessageCommand=function(self, params)
        -- on ScreenSelectMusicWide, this screen code is reused to instead toggle player profile views
        if params.Name == "TogglePatternInfo" and params.PlayerNumber == player then
            if (ThemePrefs.Get("FolderStats")) or not (ThemePrefs.Get("MusicWheelGS") ~= "Scorebox") then
                showPatternInfo = not showPatternInfo
                self:queuecommand("TogglePatternInfo")
            end
        end
    end,

    TogglePatternInfoCommand=function(self)
        self:visible(showPatternInfo)
    end,
}

t[#t+1] = LoadActor("./FolderStats.lua", player)
t[#t+1] = LoadActor("./ScoreBox.lua", player)

return t