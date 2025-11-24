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
local item_title_x = 78

local song_color = color("#0A141B")
local group_color = color("#4c565d")

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
			end,
			UpdateCommand = function(subself)
				-- Pulsing glow effect for focused song items only
				if self.info and self.info.type == "song" and self.is_focused then
					-- Pulse between song color and group color every second
					subself:stoptweening()
					subself:linear(1)
					subself:diffuse(group_color)
					subself:diffusealpha(0.5)
					subself:linear(1)
					subself:diffuse(song_color)
					subself:diffusealpha(0.5)
					subself:queuecommand("Update")
				end
			end
		},
		
		-- Song title text (no banner - theme has dedicated banner display)
		LoadFont("Common Normal") .. {
			Name = "Title",
			InitCommand = function(subself)
				self.title = subself
				subself:x(-item_width/2 + item_title_x)
				subself:halign(0)
				subself:zoom(0.8)
				subself:maxwidth(item_width - 20)  -- Full width minus margins
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
		self.is_focused = true
		self.container:zoom(1.0)
		self.container:diffusealpha(1.0)
		
		-- Highlight background and start pulsing for songs
		if self.background then
			if self.info and self.info.type == "song" then
				-- Start pulsing for focused songs
				self.background:queuecommand("Update")
			else
				-- Static highlight for groups
				self.background:stoptweening()
				self.background:diffuse(group_color)
				self.background:diffusealpha(0.8)
			end
		end
	else
		self.is_focused = false
		-- No fade effect - keep all items at full opacity
		self.container:zoom(1.0)
		self.container:diffusealpha(1.0)
		
		if self.background then
			-- Stop pulsing and use default color
			self.background:stoptweening()
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
		self.default_color = song_color
		self.background:diffuse(self.default_color)
		self.background:diffusealpha(1)
	end
	
	-- Show song title
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
	-- Hide song title
	if self.title then
		self.title:visible(false)
	end
	
	-- Reset background to default group color (Dark Gray)
	if self.background then
		self.default_color = group_color
		self.background:diffuse(self.default_color)
		self.background:diffusealpha(1)
	end
	
	-- Show group elements
	if self.group_name then
		self.group_name:visible(true)
		self.group_name:settext(info.group_name)
		
		-- Rainbow color on text for Group sort
		if SL.MusicWheel.State.sort_order == "SortOrder_Group" and info.index then
			local hue = ((info.index - 1) * 30 + 30) % 360
			-- Full saturation and brightness for maximum readability
			local rainbow_color = HSV(hue, 0.8, 1.0)
			self.group_name:diffuse(rainbow_color)
		else
			self.group_name:diffuse(Color.White)
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
