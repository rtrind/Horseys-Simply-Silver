-- WheelItem.lua
-- Metatable for music wheel items (implements sick_wheel interface)
-- Phase 1: Basic display with song title and banner

local item_mt = {}
item_mt.__index = item_mt

-- ============================================================================
-- Configuration
-- ============================================================================

-- Match original engine wheel dimensions
local item_width = SCREEN_WIDTH / 2.125  -- Same as engine wheel
local item_height = 31
local banner_width = 80  -- Slightly smaller banner
local banner_height = 38  -- Proportional to new item height
local text_x = 90  -- X position for text (after banner)

-- ============================================================================
-- create_actors - Returns Def.ActorFrame with visual elements
-- ============================================================================

function item_mt:create_actors(name)
	self.name = name
	
	return Def.ActorFrame{
		Name = name,
		InitCommand = function(subself)
			self.container = subself
		end,
		
		-- Background quad
		Def.Quad{
			Name = "Background",
			InitCommand = function(subself)
				self.background = subself
				subself:zoomto(item_width, item_height)
				subself:diffuse(0, 0, 0, 0.5)
			end
		},
		
		-- Banner sprite
		Def.Banner{
			Name = "Banner",
			InitCommand = function(subself)
				self.banner = subself
				subself:x(-item_width/2 + banner_width/2 + 5)
				subself:zoomto(banner_width, banner_height)
			end
		},
		
		-- Song title text
		LoadFont("Common Normal") .. {
			Name = "Title",
			InitCommand = function(subself)
				self.title = subself
				subself:x(-item_width/2 + text_x)
				subself:halign(0)
				subself:zoom(0.8)
				subself:maxwidth(item_width - text_x - 10)
				subself:diffuse(Color.White)
			end
		},
		
		-- Group name text (for group headers)
		LoadFont("Common Normal") .. {
			Name = "GroupName",
			InitCommand = function(subself)
				self.group_name = subself
				subself:x(0)
				subself:halign(0.5)
				subself:zoom(0.9)
				subself:maxwidth(item_width - 20)
				subself:diffuse(Color.White)
				subself:visible(false)
			end
		},
		
		-- Song count text (for group headers)
		LoadFont("Common Normal") .. {
			Name = "SongCount",
			InitCommand = function(subself)
				self.song_count = subself
				subself:x(item_width/2 - 18)
				subself:halign(1)
				subself:zoom(0.7)
				subself:diffuse(Color.White)
				subself:visible(false)
			end
		}
	}
end

-- ============================================================================
-- transform - Positions item based on focus
-- ============================================================================

function item_mt:transform(position, num_items, has_focus)
	if not self.container then return end
	
	-- Calculate offset from center
	local focus_pos = math.ceil(num_items / 2)
	local offset = position - focus_pos
	
	-- Vertical spacing (match original engine wheel)
	local y_pos = offset * (item_height + 1)
	
	-- Hide first and last items (offscreen buffers)
	-- Also hide items that are too far from center (beyond visible range)
	if position == 1 or position == num_items or math.abs(offset) > 5 then
		self.container:visible(false)
		self.container:y(y_pos)
		return
	else
		self.container:visible(true)
	end
	
	-- Apply position
	self.container:stoptweening()
	self.container:decelerate(0.15)
	self.container:y(y_pos)
	
	-- Scale and alpha based on focus
	if has_focus then
		self.container:zoom(1.0)
		self.container:diffusealpha(1.0)
		
		-- Highlight background with lighter gray
		if self.background then
			self.background:diffuse(0.7, 0.7, 0.7, 0.3)  -- Light gray,Slightly less transparent than regular
		end
	else
		-- No fade effect - keep all items at full opacity
		self.container:zoom(1.0)
		self.container:diffusealpha(1.0)
		
		if self.background then
			-- Use the stored default color (or fallback to black)
			if self.default_color then
				self.background:diffuse(self.default_color)
				self.background:diffusealpha(0.5)
			else
				self.background:diffuse(0, 0, 0, 0.5)
			end
		end
	end
end

-- ============================================================================
-- set - Updates display with item data
-- ============================================================================

function item_mt:set(info)
	if not info then return end
	
	self.info = info
	
	-- Handle song items
	if info.type == "song" then
		self:set_song(info)
	-- Handle group header items
	elseif info.type == "group_header" then
		self:set_group_header(info)
	end
end

-- Set display for song item
function item_mt:set_song(info)
	local song = info.song
	
	if not song then return end
	
	-- Reset background to default song color (Dark Blue/Black)
	if self.background then
		self.default_color = color("#0A141B")
		self.background:diffuse(self.default_color)
		self.background:diffusealpha(1)
	end
	
	-- Show song elements
	if self.banner then
		self.banner:visible(true)
		self.banner:LoadFromSong(song)
	end
	
	if self.title then
		self.title:visible(true)
		self.title:settext(song:GetDisplayMainTitle())
	end
	
	-- Hide group elements
	if self.group_name then
		self.group_name:visible(false)
	end
	
	if self.song_count then
		self.song_count:visible(false)
	end
end

-- Set display for group header item
function item_mt:set_group_header(info)
	-- Hide song elements
	if self.banner then
		self.banner:visible(false)
	end
	
	if self.title then
		self.title:visible(false)
	end
	
	if self.background then
		self.default_color = color("#4c565d")
		self.background:diffuse(self.default_color)
	end
	
	-- Show group elements
	if self.group_name then
		self.group_name:visible(true)
		self.group_name:settext(info.group_name)
		
		-- Different color for group headers
		if info.is_open then
			self.group_name:diffuse(0.3, 0.8, 1.0, 1)  -- Cyan for open
		else
			self.group_name:diffuse(1.0, 1.0, 0.3, 1)  -- Yellow for closed
		end
	end
	
	if self.song_count then
		self.song_count:visible(true)
		self.song_count:settext(info.song_count)
	end
end

-- ============================================================================
-- Return metatable
-- ============================================================================

return item_mt
