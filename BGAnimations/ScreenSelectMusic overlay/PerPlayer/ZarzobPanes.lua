local player = ...
local pn = ToEnumShortString(player)

-- ZarzobPanes contains FolderStats and ScoreBox (pattern info)
-- Visible when showPatternInfo is true, hidden when false
local showPatternInfo = false

local t = Def.ActorFrame{
    Name="GroupPanes"..pn,
    InitCommand=function(self)
        self:visible(showPatternInfo)
        Trace("ZarzobPanes["..pn.."] InitCommand: visible="..tostring(showPatternInfo))
    end,

    TogglePatternInfoMessageCommand=function(self, params)
        Trace("ZarzobPanes["..pn.."] received TogglePatternInfoMessage, params.PlayerNumber="..tostring(params.PlayerNumber)..", player="..tostring(player))
        if params.PlayerNumber == player then
            showPatternInfo = not showPatternInfo
            self:visible(showPatternInfo)
            Trace("ZarzobPanes["..pn.."] toggled: visible="..tostring(showPatternInfo))
        end
    end,
}

t[#t+1] = LoadActor("./FolderStats.lua", player)
t[#t+1] = LoadActor("./ScoreBox.lua", player)

return t