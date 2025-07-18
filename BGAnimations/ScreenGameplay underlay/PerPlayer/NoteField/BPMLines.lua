local player = ...
local pn = ToEnumShortString(player)

-- Access the player's active modifiers table to see if the option is enabled.
local mods = SL[pn].ActiveModifiers or {}

-- If the option is Off (default) simply return an empty Actor to avoid any
-- overhead.
if mods.BPMLines ~= "On" then
	return Def.Actor{}
end

------------------------------------------------------------
-- Basic constants
------------------------------------------------------------

-- Thickness (pixels) of the horizontal line we will draw.
local LINE_HEIGHT = 6

-- Ratio to consider the change so small that it's not worth drawing a line for.
local RATIO_TO_IGNORE = 0.10

-- Vertical offset (in pixels) that positions the horizontal line close to the
-- first upcoming arrow when playing with a normal (non-reverse) scroll
-- direction.  The value is borrowed from Simply Love's other NoteField
-- decorations (e.g. ColumnCues.lua).
local NOTEFIELD_Y_OFFSET = 80

-- Cache some engine objects we will need every update.
local ps   = GAMESTATE:GetPlayerState(player)
local opts = ps:GetCurrentPlayerOptions()

-- Helper: convert a fractional beat offset into Y-pixels on the NoteField.
-- We first try the OutFox-specific binding NoteField:GetYPosForBeat(beat).
-- On engines that lack this helper we fall back to a simple approximation
-- that assumes 64 px per beat at 1× scroll speed.
local function BeatToPixels(notefield, beat)
	if notefield and notefield.GetYPosForBeat then
		return notefield:GetYPosForBeat(beat)
	else
		-- Fallback: assume 64 px per beat at 1× scroll speed and scale by the
		-- player's actual SpeedMod.
		local speed = tonumber(mods.SpeedMod) or 1
		return beat * 64 * speed
	end
end

-- Build an ActorFrame that draws and animates a single BPM-indicator line for
-- the given target beat.
local function CreateLineActor(target_beat)
	return Def.ActorFrame{
		InitCommand=function(self)
			-- Position at the notefield's X so the line is centred.
			self:x( GetNotefieldX(player) )

			-- Respect Mini just like other notefield decorations.
			local zoom_factor = 1 - scale( mods.Mini:gsub("%%","")/100, 0, 2, 0, 1)
			self.zoom_factor = zoom_factor
			self:zoomx( zoom_factor )

			self.target_beat = target_beat
			self:queuecommand("SetUpdate")
		end,

		SetUpdateCommand=function(self)
			self:SetUpdateFunction(function(self, _)
				-- Cache the NoteField once it exists.
				if not self.notefield then
					local plr_af = SCREENMAN:GetTopScreen():GetChild("Player"..pn)
					if plr_af then self.notefield = plr_af:GetChild("NoteField") end
				end

				-- Compute vertical position so the line follows the specified beat.
				local curBeatVis = ps:GetSongPosition():GetSongBeatVisible()
				local diffBeat   = self.target_beat - curBeatVis
				local pixels     = BeatToPixels(self.notefield, diffBeat)

				-- Account for Reverse scroll.
				local sign = (opts:Reverse() == 1) and -1 or 1

				local arrow_half = (32 + (LINE_HEIGHT / 2)) * (self.zoom_factor or 1)

				self:y( NOTEFIELD_Y_OFFSET + sign * (pixels + arrow_half) )
			end)
		end,

		-- The horizontal line graphic.
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

-- Remove earlier single-line child creation; replace with multi-line implementation
-- Examine the song's timing data and build a list of beats where the BPM
-- changes by ≥3 % (ignoring beat 0).
local beats_to_draw = {}
local song = GAMESTATE:GetCurrentSong()
if song and song:GetTimingData() and song:GetTimingData().GetBPMsAndTimes then
    local bpm_table = song:GetTimingData():GetBPMsAndTimes()
    if bpm_table and #bpm_table > 0 then
        local prev_bpm = nil
        for _,entry in ipairs(bpm_table) do
            -- OutFox returns strings like "36.000000=196.007004"; parse them.
            local beat_str, bpm_str = tostring(entry):match("([^=]+)=([^=]+)")
            local beat = tonumber(beat_str)
            local bpm  = tonumber(bpm_str)
            if beat and bpm then
                if not prev_bpm then
                    -- Initialize previous bpm using first entry (usually beat 0).
                    prev_bpm = bpm
                else
                    -- Skip very early beats (beat 0) and tiny changes < RATIO_TO_IGNORE%.
                    if beat > 0 then
                        local ratio = math.abs(bpm - prev_bpm) / prev_bpm
                        if ratio >= RATIO_TO_IGNORE then
                            table.insert(beats_to_draw, beat)
                        end
                    end
                    prev_bpm = bpm
                end
            end
        end
    end
end

-- If no qualifying BPM changes, exit early
if #beats_to_draw == 0 then return Def.Actor{} end
SM("beats_to_draw: " .. #beats_to_draw)

-- Build one line per qualifying BPM-change beat detected earlier.
local children = {}
for _, beat in ipairs(beats_to_draw) do
    table.insert(children, CreateLineActor(beat))
end

return Def.ActorFrame(children)