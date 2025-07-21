local player = ...
local pn = ToEnumShortString(player)

local mods = SL[pn].ActiveModifiers or {}

-- Skip drawing if option disabled or player is using CMod (constant speed)
if mods.BPMLines == "Off" or (mods.SpeedModType and mods.SpeedModType:upper() == "C") then
    return
end

local LINE_HEIGHT = 6

-- If a BPM change is less than this ratio, it will not be drawn. DeltaMax was the song used to calibrate this value and not show any lines, since they are gradual.
local RATIO_TO_IGNORE = 0.0741

-- Vertical offset (in pixels) that positions the horizontal line close to the
-- first upcoming arrow when playing with a normal (non-reverse) scroll
-- direction.  The value is borrowed from Simply Love's other NoteField
-- decorations (e.g. ColumnCues.lua).
local NOTEFIELD_Y_OFFSET = 80

local ps   = GAMESTATE:GetPlayerState(player)
local opts = ps:GetCurrentPlayerOptions()
local reverseOffset = THEME:GetMetric("Player", "ReceptorArrowsYReverse")
local receptorStandard = THEME:GetMetric("Player", "ReceptorArrowsYStandard")

-- Helper: convert an absolute beat value into Y-pixels on the NoteField.
-- Uses ArrowEffects functions to properly calculate Y positions based on
-- the player's current timing data, speed mods, and other effects.
local function BeatToPixels(beat)

	local yOffset = ArrowEffects.GetYOffset(ps, 1, beat)
	
	-- Pass 0 for fYReverseOffsetPixels to avoid adding any extra offset that
	-- would shift the line relative to the receptor.
	local yPos = ArrowEffects.GetYPos(ps, 1, yOffset, 0)
	
	return yPos
end

local show_number = (mods.BPMLines == "Number")
local show_colored_lines = (mods.BPMLines == "ColoredLines")

-- Build an ActorFrame that draws and animates a single BPM-indicator line for
-- the given BPM-change entry (beat + info).
local function CreateLineActor(entry)
    local target_beat = entry.beat
    local is_up       = entry.is_up
    local new_bpm     = entry.bpm
	
	return Def.ActorFrame{
		InitCommand=function(self)
			self:x( GetNotefieldX(player) )

			local zoom_factor = 1 - scale( mods.Mini:gsub("%%","")/100, 0, 2, 0, 1)
			self.zoom_factor = zoom_factor
			self:zoomx( zoom_factor )

			self.target_beat = target_beat
			self:queuecommand("SetUpdate")
		end,

		SetUpdateCommand=function(self)
			self:SetUpdateFunction(function(self, _)
				local pixels = BeatToPixels(self.target_beat)

				-- The BeatToPixels function already handles reverse mods and positioning
				local arrow_half = (32 + (LINE_HEIGHT / 2)) * (self.zoom_factor or 1)
				local extra_reverse_offset = (opts:Reverse() == 1) and (math.abs(receptorStandard) + reverseOffset) or 0
				self:y( pixels + NOTEFIELD_Y_OFFSET + extra_reverse_offset + arrow_half )

			end)
		end,

		Def.Quad{
			InitCommand=function(self)
				local width = GetNotefieldWidth() or 256
				local spacing_str = tostring(mods.Spacing or "0"):gsub("%%", "")
				local spacing = (tonumber(spacing_str) or 0) / 100
				local full_width = width + width * 2 * spacing

				self:zoomto(full_width, LINE_HEIGHT)

				if show_colored_lines or show_number then
					if is_up then
						self:diffuse(0,1,0,0.6) -- green
					else
						self:diffuse(1,0,0,0.6) -- red
					end
				else -- show_lines
					self:diffuse(1,1,0,0.6) -- yellow
				end
			end
		},

		-- Optional bpm number display
		(show_number and Def.BitmapText{
			Font="Wendy/_wendy small",
			InitCommand=function(self)
				self:x(-145)

				new_bpm = math.round(new_bpm)
				self:zoom(0.25):shadowlength(1):y(0)
				self:settext(new_bpm)

				if is_up then
					self:diffuse(0,1,0,0.9) -- green
				else
					self:diffuse(1,0,0,0.9) -- red
				end
			end
		}) or nil,
	}
end

-- Examine the song's timing data and build a list of beats where the BPM
-- changes by ≥ RATIO_TO_IGNORE% (ignoring beat 0).
local beats_to_draw = {}
local song = GAMESTATE:GetCurrentSong()
if song and song:GetTimingData() and song:GetTimingData().GetBPMsAndTimes then
    local bpm_table = song:GetTimingData():GetBPMsAndTimes()
    if bpm_table and #bpm_table > 0 then
        local prev_bpm = nil
        for _,entry in ipairs(bpm_table) do
            -- OutFox returns strings like "36.000000=196.007004"
            local beat_str, bpm_str = tostring(entry):match("([^=]+)=([^=]+)")
            local beat = tonumber(beat_str)
            local bpm  = tonumber(bpm_str)
            if beat and bpm then
                if not prev_bpm then
                    -- Initialize previous bpm using first entry (usually beat 0).
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

if #beats_to_draw == 0 then return Def.Actor{} end

local children = {}
for _, entry in ipairs(beats_to_draw) do
    table.insert(children, CreateLineActor(entry))
end

return Def.ActorFrame(children)