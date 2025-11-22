local row_height = 30
local row_width  = 456

return Def.Quad {
	InitCommand=function(self)
		self:zoomto(row_width, row_height)
		self:x( 30 ):horizalign(left)
	end
}
