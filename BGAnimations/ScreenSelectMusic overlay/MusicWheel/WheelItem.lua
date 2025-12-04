-- WheelItem.lua
-- Metatable for music wheel items (implements sick_wheel interface)
-- Phase 1: Basic display with song title and banner

-- Uses global StripGroupPrefix() and GetGroupPackType() from 06 SL-Utilities.lua

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
	
	local af = Def.ActorFrame{
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
				subself:zoom(1)
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
		},
		
		-- Pack type icon (for group headers) - uses sprites from Graphics/PackIcons/
		Def.Sprite{
			Name = "PackIcon",
			InitCommand = function(subself)
				self.pack_icon = subself
				subself:x(-item_width/2 + 20)
				subself:halign(0.5):valign(0.5)
				subself:visible(false)
			end
		}
	}

    -- Add Grade/Lamp indicators for both players
    -- Layout: P1 Grade | P2 Grade (on the left side)
    -- Lamp is a horizontal bar below the grade
    
    -- Load metrics for grade tiers (needed for sprite frame mapping)
    local num_tiers = THEME:GetMetric("PlayerStageStats", "NumGradeTiersUsed")
    local grade_frames = {}
    for i=1,num_tiers do
        grade_frames[ ("Grade_Tier%02d"):format(i) ] = i-1
    end
    grade_frames["Grade_Failed"] = num_tiers

    for player in ivalues(PlayerNumber) do
        local pn = ToEnumShortString(player)
        -- Position P1 at x=20, P2 at x=50 (relative to left edge)
        local x_offset = (player == PLAYER_1) and 20 or 50
        local x_pos = -item_width/2 + x_offset

        local playerFrame = Def.ActorFrame{
            Name = "GradeFrame"..pn,
            InitCommand = function(subself)
                self["gradeFrame"..pn] = subself
                subself:x(x_pos)
                subself:visible(false)
            end
        }

        -- Heart Icon (Favorites)
        -- Placed behind the grade
        playerFrame[#playerFrame+1] = Def.Sprite{
            Name = "HeartIcon"..pn,
            Texture = THEME:GetPathG("", "_VisualStyles/Hearts/SelectColor"),
            InitCommand = function(subself)
                self["heartIcon"..pn] = subself
                subself:zoom(0.035) -- Much smaller to fit behind grade
                subself:diffuse(1, 0, 0, 0.5) -- Red color with 50% transparency
                subself:x(0):y(-1) -- Match grade sprite position
                subself:visible(false)
            end,
            UpdateGradeCommand=function(subself)
                -- Use item's song
                local song = subself:GetParent():GetParent().song
                if not song then song = SL.MusicWheel.State.last_song end
                
                if song then
                    local profile = PROFILEMAN:GetProfile(player)
                    if profile and profile:SongIsFavorite(song) then
                        subself:visible(true)
                    else
                        subself:visible(false)
                    end
                else
                    subself:visible(false)
                end
            end,
            ["CurrentSteps"..pn.."ChangedMessageCommand"]=function(subself) subself:queuecommand("UpdateGrade") end,
            FavoritesChangedMessageCommand=function(subself) subself:queuecommand("UpdateGrade") end
        }

        -- Grade Sprite (replaces Wendy font)
        -- Uses 1x18 sprite sheet from Simply Love
        playerFrame[#playerFrame+1] = Def.Sprite{
            Name = "GradeSprite"..pn,
            Texture = THEME:GetPathG("MusicWheelItem","Grades/grades 1x18.png"),
            InitCommand = function(subself)
                self["gradeSprite"..pn] = subself
                subself:zoom(0.32) -- Slightly smaller, balanced size
                subself:animate(false)
                subself:x(0):y(0) -- Centered in the space above the lamp
                subself:visible(false)
            end,
            UpdateGradeCommand=function(subself)
                -- Use item's song, or fall back to last_song for group headers
                local song = subself:GetParent():GetParent().song
                if not song then song = SL.MusicWheel.State.last_song end
                if not song then subself:visible(false) return end
                
                local best_lamp, tap_count, best_grade = WheelHelpers.GetLamp(song, player)
                
                if best_grade then
                    local grade_str = ToEnumShortString(best_grade)
                    local frame_index = num_tiers
                    
                    if grade_str == "Failed" then
                        frame_index = num_tiers
                    else
                        local tier_num = tonumber(grade_str:match("Tier(%d+)"))
                        if tier_num then frame_index = tier_num - 1 end
                    end
                    subself:setstate(frame_index):visible(true)
                else
                    subself:visible(false)
                end
            end,
            ["CurrentSteps"..pn.."ChangedMessageCommand"]=function(subself) subself:queuecommand("UpdateGrade") end
        }

        -- Count Text (Small text overlay for FC counts)
        -- Use BitmapText with ScreenEval font for better readability
        playerFrame[#playerFrame+1] = Def.BitmapText{
            Font="Wendy/_ScreenEvaluation numbers",
            Name = "Count"..pn,
            Text="5",
            InitCommand = function(subself)
                self["count"..pn] = subself
                subself:zoom(0.12) -- Back to original size
                subself:x(-13):y(12) -- 1px higher, 1px more left
                subself:halign(1):valign(1)
                subself:diffuse(Color.White)
                subself:visible(false)
            end,
            UpdateGradeCommand=function(subself)
                -- Use item's song, or fall back to last_song for group headers
                local song = subself:GetParent():GetParent().song
                if not song then song = SL.MusicWheel.State.last_song end
                if not song then subself:visible(false) return end
                
                local best_lamp, tap_count, best_grade = WheelHelpers.GetLamp(song, player)
                
                if tap_count and tap_count < 10 then
                    subself:settext(tap_count)
                    subself:visible(true)
                else
                    subself:visible(false)
                end
            end,
            ["CurrentSteps"..pn.."ChangedMessageCommand"]=function(subself) subself:queuecommand("UpdateGrade") end
        }

        -- Lamp (Horizontal Bar below grade)
        playerFrame[#playerFrame+1] = Def.Quad{
            Name = "Lamp"..pn,
            InitCommand = function(subself)
                self["lamp"..pn] = subself
                subself:y(13) -- 1px higher than before
                subself:zoomto(24, 4) -- 4px wider (20 -> 24)
                subself:halign(0.5)
            end,
            UpdateGradeCommand=function(subself)
                -- Use item's song, or fall back to last_song for group headers
                local song = subself:GetParent():GetParent().song
                if not song then song = SL.MusicWheel.State.last_song end
                if not song then subself:visible(false) return end
                
                local best_lamp, tap_count, best_grade = WheelHelpers.GetLamp(song, player)
                
                if best_lamp then
                    subself:visible(true)
                    if best_lamp == 0 then
                        local ItlPink = color("1,0.2,0.406,1")
                        subself:diffuse(ItlPink)
                    elseif best_lamp > 50 then
                        local ClearLamp = { color("#0000CC"), color("#990000") }
                        subself:diffuse(ClearLamp[best_lamp - 50])
                    else
                        subself:diffuse(SL.JudgmentColors[SL.Global.GameMode][best_lamp])
                    end
                    
                    -- Update Count color to match
                    local countActor = subself:GetParent():GetChild("Count"..pn)
                    if countActor then countActor:diffuse(subself:GetDiffuse()) end
                else
                    subself:visible(false)
                end
            end,
            ["CurrentSteps"..pn.."ChangedMessageCommand"]=function(subself) subself:queuecommand("UpdateGrade") end
        }
        
        af[#af+1] = playerFrame
    end

    return af
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
    
    -- Store song on container for child actors to access
    if self.container then self.container.song = song end
	
	if not song then 
        if self.title then self.title:settext("") end
        return 
    end
	
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
	
	if self.pack_icon then
		self.pack_icon:visible(false)
	end

    -- Trigger UpdateGrade for both players
    for player in ivalues(PlayerNumber) do
        local pn = ToEnumShortString(player)
        
        if self["gradeFrame"..pn] then
            self["gradeFrame"..pn]:visible(true)
            -- Propagate UpdateGrade to children using playcommand
            if self["gradeSprite"..pn] then self["gradeSprite"..pn]:playcommand("UpdateGrade") end
            if self["lamp"..pn] then self["lamp"..pn]:playcommand("UpdateGrade") end
            if self["count"..pn] then self["count"..pn]:playcommand("UpdateGrade") end
            if self["heartIcon"..pn] then self["heartIcon"..pn]:playcommand("UpdateGrade") end
        end
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
	
	-- Determine pack type and load icon sprite
	local pack_type = GetGroupPackType(info.group_name)
	
	-- Show pack icon if applicable
	if self.pack_icon then
		if pack_type then
			-- Try to find icon file (supports png, svg, jpg, etc.)
			local base_path = THEME:GetCurrentThemeDirectory() .. "Graphics/PackIcons/" .. pack_type
			local icon_path = nil
			
			-- Check common image formats
			for _, ext in ipairs({".png", ".svg", ".jpg", ".jpeg"}) do
				if FILEMAN:DoesFileExist(base_path .. ext) then
					icon_path = base_path .. ext
					break
				end
			end
			
			if icon_path then
				self.pack_icon:visible(true)
				self.pack_icon:Load(icon_path)
				-- Scale to fit in header (max 24px height)
				local h = self.pack_icon:GetHeight()
				if h > 0 then
					self.pack_icon:zoom(math.min(24/h, 1))
				end
			else
				self.pack_icon:visible(false)
			end
		else
			self.pack_icon:visible(false)
		end
	end
	
	-- Show group elements
	if self.group_name then
		self.group_name:visible(true)
		self.group_name:settext(StripGroupPrefix(info.group_name))
		
		-- Shift text right if icon is visible
		if pack_type then
			self.group_name:x(10)  -- Offset to make room for icon
		else
			self.group_name:x(0)   -- Centered
		end
		
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

	-- For group headers, do not show any grade/lamp/count at all.
	-- Grades are specific to song items.
	for player in ivalues(PlayerNumber) do
		local pn = ToEnumShortString(player)
		if self["gradeFrame"..pn] then self["gradeFrame"..pn]:visible(false) end
		if self["gradeSprite"..pn] then self["gradeSprite"..pn]:visible(false) end
		if self["lamp"..pn] then self["lamp"..pn]:visible(false) end
		if self["count"..pn] then self["count"..pn]:visible(false) end
		if self["heartIcon"..pn] then self["heartIcon"..pn]:visible(false) end
	end

    -- Clear item's song reference (group headers don't have songs)
    -- Grade display will fall back to last_song
    if self.container then self.container.song = nil end
end

-- ============================================================================
-- Return metatable
-- ============================================================================

return item_mt
