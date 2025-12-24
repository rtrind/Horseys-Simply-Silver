local player = ...
local pn = ToEnumShortString(player)

local mods = SL[pn].ActiveModifiers or {}

-- Skip drawing if option disabled or player is using CMod (constant speed)
if mods.BPMLines == "Off" or (mods.SpeedModType and mods.SpeedModType:upper() == "C") then
    return Def.Actor{}
end

local LINE_HEIGHT = 6

-- Maximum number of BPM lines to support (pool size)
-- Most songs have < 20 BPM changes, but some complex charts may have more
local MAX_POOL_SIZE = 50

-- If a BPM change is less than this ratio, it will not be drawn
local RATIO_TO_IGNORE = 0.0741

-- Vertical offset for positioning
local NOTEFIELD_Y_OFFSET = 80

local ps   = GAMESTATE:GetPlayerState(player)
local opts = ps:GetCurrentPlayerOptions()
local reverseOffset = THEME:GetMetric("Player", "ReceptorArrowsYReverse")
local receptorStandard = THEME:GetMetric("Player", "ReceptorArrowsYStandard")

local show_number = (mods.BPMLines == "Number")
local show_colored_lines = (mods.BPMLines == "ColoredLines")

-- Pre-calculate these once
local zoom_factor = 1 - scale( mods.Mini:gsub("%%","")/100, 0, 2, 0, 1)
local nf_width = GetNotefieldWidth() or 256
local spacing_str = tostring(mods.Spacing or "0"):gsub("%%", "")
local spacing = (tonumber(spacing_str) or 0) / 100
local full_width = nf_width + nf_width * 2 * spacing
local nf_x = GetNotefieldX(player)

-- Helper: convert beat to Y-pixels
local function BeatToPixels(beat)
	local yOffset = ArrowEffects.GetYOffset(ps, 1, beat)
	local yPos = ArrowEffects.GetYPos(ps, 1, yOffset, 0)
	return yPos
end

-- Gather BPM change data
local beats_to_draw = {}
local song = GAMESTATE:GetCurrentSong()
if song and song:GetTimingData() and song:GetTimingData().GetBPMsAndTimes then
    local bpm_table = song:GetTimingData():GetBPMsAndTimes()
	local prev_bpm = nil
	if bpm_table and #bpm_table > 1 then
		for _,entry in ipairs(bpm_table) do
			-- OutFox returns strings like "36.000000=196.007004"
			local beat_str, bpm_str = tostring(entry):match("([^=]+)=([^=]+)")
			local beat = tonumber(beat_str)
			local bpm  = tonumber(bpm_str)
			if beat and bpm then
				if not prev_bpm then
					prev_bpm = bpm
				else
					local ratio = math.abs(bpm - prev_bpm) / prev_bpm
					if ratio >= RATIO_TO_IGNORE then
						table.insert(beats_to_draw, {beat=beat, is_up=(bpm>prev_bpm), bpm=bpm})
					end
					prev_bpm = bpm
				end
			end
		end
	end
end

-- Also gather scroll changes
if song and song:GetTimingData() and song:GetTimingData().GetScrolls then
	local scroll_table = song:GetTimingData():GetScrolls()
	if scroll_table and #scroll_table >= 1 then
		local steps = GAMESTATE:GetCurrentSteps(pn)
		if steps and steps:GetTimingData() then
			scroll_table = steps:GetTimingData():GetScrolls()
		end
	end

	if scroll_table and #scroll_table > 1 then
		local prev_scroll = nil
		for _,entry in ipairs(scroll_table) do
			local beat_str, scroll_str = tostring(entry):match("([^=]+)=([^=]+)")
			local beat = tonumber(beat_str)
			local scroll_value = tonumber(scroll_str)
			if beat and scroll_value then
				if not prev_scroll then
					prev_scroll = scroll_value
				else
					local ratio = math.abs(scroll_value - prev_scroll)
					if ratio >= RATIO_TO_IGNORE then
						table.insert(beats_to_draw, {beat=beat, is_up=(scroll_value>prev_scroll), bpm=(song:GetTimingData():GetBPMAtBeat(beat) * scroll_value)})
					end
					prev_scroll = scroll_value
				end
			end
		end
	end
end

-- If no BPM changes, return empty actor
if #beats_to_draw == 0 then return Def.Actor{} end

-- Limit to pool size
local num_lines = math.min(#beats_to_draw, MAX_POOL_SIZE)

-- Create pooled line actors (pre-allocated, reusable)
local function CreatePooledLineActor(index)
	return Def.ActorFrame{
		Name="BPMLine_"..index,
		InitCommand=function(self)
			self:x(nf_x)
			self:zoomx(zoom_factor)
			self.zoom_factor = zoom_factor
			self:visible(false) -- Start hidden, will be configured later
		end,
		
		-- Configure this line for a specific beat/bpm entry
		ConfigureCommand=function(self, params)
			if not params or not params.beat then
				self:visible(false)
				self:SetUpdateFunction(nil) -- Clear update function to save CPU
				return
			end
			
			local target_beat = params.beat
			local is_up = params.is_up
			local new_bpm = params.bpm
			
			self.target_beat = target_beat
			self:visible(true)
			
			-- Configure the quad child
			local quad = self:GetChild("LineQuad")
			if quad then
				if show_colored_lines or show_number then
					if is_up then
						quad:diffuse(0,1,0,0.6)
					else
						quad:diffuse(1,0,0,0.6)
					end
				else
					quad:diffuse(1,1,0,0.6)
				end
			end
			
			-- Configure the text child (if exists)
			local text = self:GetChild("BPMText")
			if text and show_number then
				text:visible(true)
				text:settext(math.round(new_bpm))
				if is_up then
					text:diffuse(0,1,0,0.9)
				else
					text:diffuse(1,0,0,0.9)
				end
			elseif text then
				text:visible(false)
			end
			
			-- Set up the update function for this line
			self:SetUpdateFunction(function(af, _)
				local pixels = BeatToPixels(af.target_beat)
				local arrow_half = (32 + (LINE_HEIGHT / 2)) * (af.zoom_factor or 1)
				local extra_reverse_offset = (opts:Reverse() == 1) and (math.abs(receptorStandard) + reverseOffset) or 0
				af:y(pixels + NOTEFIELD_Y_OFFSET + extra_reverse_offset + arrow_half)
			end)
		end,
		
		-- Cleanup when leaving screen
		OffCommand=function(self)
			self:SetUpdateFunction(nil) -- Clear update function to free closure
			self:visible(false)
		end,

		Def.Quad{
			Name="LineQuad",
			InitCommand=function(self)
				self:zoomto(full_width, LINE_HEIGHT)
			end
		},

		-- Always create BitmapText but control visibility
		Def.BitmapText{
			Name="BPMText",
			Font="Wendy/_wendy small",
			InitCommand=function(self)
				self:x(-145)
				self:zoom(0.25):shadowlength(1):y(0)
				self:visible(show_number)
			end
		},
	}
end

-- Build the pool of line actors
local children = {}
for i = 1, num_lines do
	children[#children+1] = CreatePooledLineActor(i)
end

-- Main ActorFrame that manages the pool
local af = Def.ActorFrame{
	Name="BPMLinesContainer_"..pn,
	
	-- Configure all pooled lines when screen loads
	OnCommand=function(self)
		for i = 1, num_lines do
			local line = self:GetChild("BPMLine_"..i)
			if line and beats_to_draw[i] then
				line:playcommand("Configure", beats_to_draw[i])
			end
		end
	end,
	
	-- Clean up on screen exit
	OffCommand=function(self)
		-- Clear references to help GC
		beats_to_draw = nil
	end,
}

-- Add pooled children to the container
for _, child in ipairs(children) do
	af[#af+1] = child
end

return af