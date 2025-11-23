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
local item_height = 32
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
				subself:x(item_width/2 - 10)
				subself:halign(1)
				subself:zoom(0.6)
				subself:diffuse(0.7, 0.7, 0.7, 1)
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
	local focus_pos = math.floor(num_items / 2) + 1
	local offset = position - focus_pos
	
	-- Vertical spacing (match original engine wheel)
	local y_pos = offset * (item_height + 0.5)
	
	-- Apply position
	self.container:stoptweening()
	self.container:decelerate(0.15)
	self.container:y(y_pos)
	
	-- Scale and alpha based on focus
	if has_focus then
		self.container:zoom(1.0)
		self.container:diffusealpha(1.0)
		
		-- Highlight background
		if self.background then
			self.background:diffuse(0.2, 0.4, 0.6, 0.7)
		end
	else
		-- Fade items further from center
		local distance = math.abs(offset)
		local alpha = 1.0 - (distance * 0.15)
		alpha = math.max(0.3, alpha)
		
		self.container:zoom(1.0)
		self.container:diffusealpha(alpha)
		
		if self.background then
			self.background:diffuse(0, 0, 0, 0.5)
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
		self.song_count:settext("(" .. info.song_count .. ")")
	end
end

-- ============================================================================
-- Return metatable
-- ============================================================================

return item_mt
