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
local LINE_HEIGHT = 2

-- Size (pixels) of the square we will draw.
-- This y-offset puts the square near the first upcoming arrow when playing
-- with standard (non-reverse) orientation.  It is based on the value used by
-- Simply Love for other NoteField decorations (see ColumnCues.lua etc.).
local NOTEFIELD_Y_OFFSET = 80

-- Cache some engine objects we will need every update.
local ps   = GAMESTATE:GetPlayerState(player)
local opts = ps:GetCurrentPlayerOptions()

-- Helper: convert a fractional beat offset into pixels on the notefield.  We
-- benefit from a Lua binding added to OutFox: NoteField:GetYPosForBeat(beat).
-- If it is not available (older SM/ITG engine) we fall back to a reasonable
-- approximation that uses a fixed pixel-per-beat scale (48px).
local function BeatToPixels(notefield, beat)
	if notefield and notefield.GetYPosForBeat then
		return notefield:GetYPosForBeat(beat)
	else
		-- Fallback: assume 48px per beat at 1x scroll speed, then scale by the
		-- player 0s actual scroll speed.
		local speed = tonumber(mods.SpeedMod) or 1
		return beat * 48 * speed
	end
end

-- We draw everything inside an ActorFrame so that we can apply an UpdateFunction
-- to the whole frame (making the maths a bit easier to reason about).
return Def.ActorFrame{
	InitCommand=function(self)
		-- Position ourselves at the notefield's X coordinate so we stay centred
		-- horizontally.  Respect Mini by shrinking horizontally just like other
		-- notefield decorations.
		self:x( GetNotefieldX(player) )

		local zoom_factor = 1 - scale( mods.Mini:gsub("%%","")/100, 0, 2, 0, 1)
		self:zoomx( zoom_factor )

		-- The UpdateFunction will be set once the screen has fully initialised and
		-- the NoteField actor exists.
		self:queuecommand("SetUpdate")
	end,

	SetUpdateCommand=function(self)
		self:SetUpdateFunction(function(self, _)
			-- Grab the NoteField actor every update in case it wasn 0t available at
			-- Init.  Once retrieved successfully we can cache it for the remainder of
			-- the song.
			if not self.notefield then
				local plr_af = SCREENMAN:GetTopScreen():GetChild("Player"..pn)
				if plr_af then self.notefield = plr_af:GetChild("NoteField") end
			end

			-- Calculate the Y position so that the square appears "with" beat 0 (the
			-- next upcoming arrow).  The magic numbers below mirror how Simply Love
			-- positions other overlay actors (MeasureCounter, ColumnCues, etc.)
			local curBeat = ps:GetSongPosition():GetSongBeatVisible()
			local pixels  = BeatToPixels(self.notefield, -curBeat)

			-- Adjust for reverse scroll directions.
			local sign = (opts:Reverse() == 1) and -1 or 1

			self:y( NOTEFIELD_Y_OFFSET + sign * pixels )
		end)
	end,

	-- The red horizontal line itself.
	Def.Quad{
		InitCommand=function(self)
			local width = GetNotefieldWidth() or 256
			-- mods.Spacing is a string like "20%".  Remove the % and convert to number safely.
			local spacing_str = tostring(mods.Spacing or "0"):gsub("%%", "")
			local spacing = (tonumber(spacing_str) or 0) / 100
			-- account for any spacing modifier widening the columns
			local full_width = width + width * 2 * spacing

			self:zoomto(full_width, LINE_HEIGHT)
			self:diffuse(color("1,0,0,1"))
		end
	}
} 