local player = ...
local pn = ToEnumShortString(player)

-- ZarzobPanes contains FolderStats (pattern info)
-- Visible when showPatternInfo is true, hidden when false
local showPatternInfo = false

local t = Def.ActorFrame{
    Name="GroupPanes"..pn,
    InitCommand=function(self)
        self:visible(showPatternInfo)
    end,

    TogglePatternInfoMessageCommand=function(self, params)
        if params.PlayerNumber == player then
            showPatternInfo = not showPatternInfo
            self:visible(showPatternInfo)
        end
    end,
}

t[#t+1] = LoadActor("./FolderStats.lua", player)

return t