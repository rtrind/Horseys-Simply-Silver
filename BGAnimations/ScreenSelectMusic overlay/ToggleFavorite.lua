local af = Def.ActorFrame{
    CodeMessageCommand=function(self, param)
        if param.Name == "ToggleFavorite" then
            local ssm = SCREENMAN:GetTopScreen()
            ssm:ToggleFavoriteCurrentItem(param.PlayerNumber)
        end
	end
}

return af