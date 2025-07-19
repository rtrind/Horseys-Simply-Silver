local player = ...
local pn = ToEnumShortString(player)

local mods = SL[pn].ActiveModifiers or {}

if mods.BPMLines ~= "On" then
	return Def.Actor{}
end

local LINE_HEIGHT = 6

-- If a BPM change is less than this ratio, it will not be drawn.
local RATIO_TO_IGNORE = 0.10

-- Vertical offset (in pixels) that positions the horizontal line close to the
-- first upcoming arrow when playing with a normal (non-reverse) scroll
-- direction.  The value is borrowed from Simply Love's other NoteField
-- decorations (e.g. ColumnCues.lua).
local NOTEFIELD_Y_OFFSET = 80

local ps   = GAMESTATE:GetPlayerState(player)
local opts = ps:GetCurrentPlayerOptions()

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

-- Build an ActorFrame that draws and animates a single BPM-indicator line for
-- the given target beat.
local function CreateLineActor(target_beat)
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
				local arrow_half = (32 + LINE_HEIGHT) * (self.zoom_factor or 1)
				self:y( NOTEFIELD_Y_OFFSET + pixels + arrow_half)
			end)
		end,

		Def.Quad{
			InitCommand=function(self)
				local width = GetNotefieldWidth() or 256
				local spacing_str = tostring(mods.Spacing or "0"):gsub("%%", "")
				local spacing = (tonumber(spacing_str) or 0) / 100
				local full_width = width + width * 2 * spacing

				self:zoomto(full_width, LINE_HEIGHT)
				self:diffuse(color("1,0,0,0.6"))
			end
		}
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
						table.insert(beats_to_draw, beat)
					end
                    prev_bpm = bpm
                end
            end
        end
    end
end

if #beats_to_draw == 0 then return Def.Actor{} end

local children = {}
for _, beat in ipairs(beats_to_draw) do
    table.insert(children, CreateLineActor(beat))
end

return Def.ActorFrame(children)