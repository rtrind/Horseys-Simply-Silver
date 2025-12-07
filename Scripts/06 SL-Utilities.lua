------------------------------------------------------------
-- 06 SL-Utilities.lua
-- Utility Functions for Development
--
-- The filename starts with "06" so that it loads before other SL scripts that rely on
-- global functions defined here.  For more information on this numbering system that
-- pretty much no one uses, see: ./Themes/_fallback/Scripts/hierarchy.txt

------------------------------------------------------------
-- define helper functions local to this file first
-- global utility functions (below) will depend on these
------------------------------------------------------------

-- TableToString() function via:
-- http://www.hpelbers.org/lua/print_r
-- Copyright 2009: hans@hpelbers.org
TableToString = function(t, name, indent)
	local tableList = {}
	local table_r

	table_r = function(t, name, indent, full)
		local id = not full and name or type(name)~="number" and tostring(name) or '['..name..']'
		local tag = indent .. id .. ' = '
		local out = {}	-- result

		if type(t) == "table" then
			if tableList[t] ~= nil then
				table.insert(out, tag .. '{} -- ' .. tableList[t] .. ' (self reference)')
			else
				tableList[t]= full and (full .. '.' .. id) or id
				if next(t) then -- Table not empty
					table.insert(out, tag .. '{')
					for key,value in pairs(t) do
						table.insert(out,table_r(value,key,indent .. '|    ',tableList[t]))
					end
					table.insert(out,indent .. '}')
				else
					table.insert(out,tag .. '{}')
				end
			end
		else
			local val = type(t)~="number" and type(t)~="boolean" and '"'..tostring(t)..'"' or tostring(t)
			table.insert(out, tag .. val)
		end

		return table.concat(out, '\n')
	end

	return table_r(t,name or 'Value',indent or '')
end


------------------------------------------------------------
-- GLOBAL UTILITY FUNCTIONS
-- use these to assist in theming/scripting efforts
------------------------------------------------------------

-- SM()
-- Shorthand for SCREENMAN:SystemMessage(), this is useful for rapid iterative
-- testing by allowing us to pretty-print tables and variables to the screen.
--
-- If the first argument is a table, SM() will use TableToString (from above)
-- to display children recursively.  Larger tables will spill offscreen, so
-- rec_print_table() from the _fallback theme is good to know about and use when
-- debugging.  That will recursively pretty-print table structures to ./Logs/Log.txt
--
-- The second arugment is optional and allows you to provide a specific duration,
-- in seconds, for how long you want the text to appear on screen.
-- in Simply Love, the default SystemMessage duration used in ./BGA/ScreenSystemLayer overlay.lua is 3

SM = function( arg, duration )
	local msg

	-- if a table has been passed in, recursively stringify the table's keys and values
	if type( arg ) == "table" then
		msg = TableToString(arg)

	-- otherwise, Lua's standard tostring() should suffice
	else
		msg = tostring(arg)
	end

	-- SCREENMAN:SystemMessage() is effectively a convenience function for broadcasting
	-- "SystemMessage" with certain parameters.  see: ScreenManager.cpp
	-- let's broadcast directly using MESSAGEMAN so that we can also pack in a duration
	-- value (how long to display the SystemMessage for) if so desired
	MESSAGEMAN:Broadcast("SystemMessage", {Message=msg, Duration=duration})
	Trace(msg)
end


------------------------------------------------------------
-- Group Name Utilities
-- For handling folder naming conventions like "O1998a-DDR (J)"
------------------------------------------------------------

-- Strip folder naming prefix (e.g., "O1998a-DDR (J)" -> "DDR (J)")
-- Pattern: letter, 4 digits, optional letter, hyphen
StripGroupPrefix = function(name)
	if not name then return name end
	return name:gsub("^%a%d%d%d%d%a?%-", "")
end

-- Get the pack type from a group name based on first letter
-- O = Original DDR, S = Stamina, X = Gimmick, Y = Couples, Z = Custom
-- Returns: type string or nil if not matching pattern
GetGroupPackType = function(name)
	if not name then return nil end
	local first_letter = name:match("^(%a)%d%d%d%d")
	if not first_letter then return nil end
	
	first_letter = first_letter:upper()
	local pack_types = {
		O = "original",   -- Original DDR songs
		S = "stamina",    -- Stamina packs
		X = "gimmick",    -- Gimmick packs
		Y = "couples",    -- Couples mode
		Z = "custom"      -- Custom packs
	}
	return pack_types[first_letter]
end


-- range() accepts one, two, or three arguments and returns a table
-- Example Usage:

-- range(4)           → {1, 2, 3, 4}
-- range(4, 7)        → {4, 5, 6, 7}
-- range(5, 27, 5)    → {5, 10, 15, 20, 25}

-- either of these are acceptable
-- range(-1,-3, 0.5)  → {-1, -1.5, -2, -2.5, -3 }
-- range(-1,-3, -0.5) → {-1, -1.5, -2, -2.5, -3 }

-- but this just doesn't make sense and will return an empty table
-- range(1, 3, -0.5)  → {}

range = function(start, stop, step)
	if start == nil then return end

	if not stop then
		stop = start
		start = 1
	end

	step = step or 1

	-- if step has been explicitly provided as a positive number
	-- but the start and stop values tell us to decrement
	-- multiply step by -1 to allow decrementing to occur
	if step > 0 and start > stop then
		step = -1 * step
	end

	local t = {}
	for i = start, stop, step do
		t[#t+1] = i
	end
	return t
end

-- stringify() accepts an indexed table, applies tostring() to each element,
-- and returns the results.  sprintf style format can be provided via an
-- optional second argument.  Note that this function will remove key/value pairs
-- if any are passed in via "tbl".
--
-- Example:
-- 		local blah = stringify( {10, true, "hey now", asdf=10} )
-- Result:
-- 		blah == { "10", "true", "hey now" }
--
-- For an example with range()
-- see Mini in ./Scripts/SL-PlayerOptions.lua
function stringify( tbl, form )
	if not tbl then return end

	local t = {}
	for _,value in ipairs(tbl) do
		t[#t+1] = (type(value)=="number" and form and form:format(value) ) or tostring(value)
	end
	return t
end

-- iterates over a numerically-indexed table (haystack) until a desired value (needle) is found
-- if found, return the index (number) of the desired value within the table
-- if not found, return nil
function FindInTable(needle, haystack)
	for i = 1, #haystack do
		if needle == haystack[i] then
			return i
		end
	end
	return nil
end

-- i'm learning haskell okay? map is nice -ian5v
function map(func, array)
	local new_array = {}
	for i,v in ipairs(array) do
		new_array[i] = func(v)
	end
	return new_array
end


-- Create a new table with each unique element from the input present exactly once,
-- e.g. {1, 2, 3, 2, 1} -> {1, 2, 3}
function deduplicate(array)
	local hash = {}
	local res = {}

	for _, v in ipairs(array) do
		if not hash[v] then
			res[#res+1] = v
			hash[v] = true
		end
	end

	return res
end

function GetGroupBanner()
 	local path = '';
 	if ThemePrefs.Get('NoBannerUseGroupBanner') then
 		local current = GAMESTATE:IsCourseMode() and GAMESTATE:GetCurrentCourse() or GAMESTATE:GetCurrentSong();
 		if current then
 			if GAMESTATE:IsCourseMode() then
 				path = SONGMAN:GetCourseGroupBannerPath(current:GetGroupName());
 			else
 				path = SONGMAN:GetSongGroupBannerPath(current:GetGroupName());
 			end
 		end
 	end
 	return path;
 end

 function HasGroupBanner()
 	return GetGroupBanner() ~= '';
 end

--  function used to randomly select one table entry
 function shuffle(tbl)
    for i = #tbl, 2, -1 do
      local j = math.random(i)
      tbl[i], tbl[j] = tbl[j], tbl[i]
    end
    return tbl
  end

  ---------------------------------------------------------------------------
-- helper function used to parse ITG-Mode-DefaultSongs.txt
-- returns the contents of a txt file as an indexed table, split on newline

GetFileContents = function(path)
	local contents = ""

	if FILEMAN:DoesFileExist(path) then
		-- create a generic RageFile that we'll use to read the contents
		local file = RageFileUtil.CreateRageFile()
		-- the second argument here (the 1) signifies
		-- that we are opening the file in read-only mode
		if file:Open(path, 1) then
			contents = file:Read()
		end

		-- destroy the generic RageFile now that we have the contents
		file:destroy()
	end

	-- split the contents of the file on newline
	-- to create a table of lines as strings
	local lines = {}
	for line in contents:gmatch("[^\r\n]+") do
		lines[#lines+1] = line
	end

	return lines
end

-- used to set the preferred song based on a list in ~/Other/ITG-Mode-DefaultSongs.txt
-- the Music Wheel will default to a random song listed in the above file (if found) if no valid player profiles are loaded
-- in the case that player profiles are loaded that have a last song played, the Music Wheel will default to the last played song
function SetPreferredSong()
	if GAMESTATE:GetCurrentStageIndex() == 0 then
		local lastPlayed = false
		for i,pn in ipairs(GAMESTATE:GetHumanPlayers()) do
			local prof = PROFILEMAN:GetProfile(pn)
			song = prof:GetLastPlayedSong()
			if song ~= nil then
					lastPlayed = true
					GAMESTATE:SetPreferredSong( song )
			end
		end
	
		if not lastPlayed then
	
			local path = THEME:GetCurrentThemeDirectory() .. "Other/ITG-Mode-DefaultSongs.txt"
			local song_list = shuffle(GetFileContents(path))
	
			for _, song in ipairs(song_list) do
				local s = SONGMAN:FindSong( song )
				if s ~= nil then
					GAMESTATE:SetPreferredSong( s )
					-- prints the randomly selected song ID; used for debugging
					-- SM(s)
					break;
				end
			end
		end
	end
end

------------------------------------------------------------
-- DEBUG INSTRUMENTATION
-- For diagnosing crashes and performance issues
------------------------------------------------------------

-- Debug configuration
SL_Debug = {
	enabled = true,           -- Master switch for debug logging
	log_memory = true,        -- Log memory usage
	log_screen_changes = true, -- Log screen transitions
	log_interval_seconds = 60, -- How often to log periodic stats (in seconds)
	session_start = nil,       -- Set when theme initializes
	screen_count = 0,          -- Number of screen transitions
	last_screen = nil,         -- Last screen name
	last_periodic_log = 0,     -- Timestamp of last periodic log
}

-- Get current timestamp in seconds since theme loaded
-- Uses GetTimeSinceStart() which is provided by Outfox engine
function SL_Debug.GetUptime()
	if not SL_Debug.session_start then
		SL_Debug.session_start = GetTimeSinceStart and GetTimeSinceStart() or 0
	end
	local now = GetTimeSinceStart and GetTimeSinceStart() or 0
	return now - SL_Debug.session_start
end

-- Format uptime as HH:MM:SS
function SL_Debug.FormatUptime()
	local seconds = SL_Debug.GetUptime()
	local hours = math.floor(seconds / 3600)
	local mins = math.floor((seconds % 3600) / 60)
	local secs = seconds % 60
	return string.format("%02d:%02d:%02d", hours, mins, secs)
end

-- Get Lua memory usage in KB
function SL_Debug.GetMemoryKB()
	return collectgarbage("count")
end

-- Format memory for logging
function SL_Debug.FormatMemory()
	local kb = SL_Debug.GetMemoryKB()
	if kb > 1024 then
		return string.format("%.2f MB", kb / 1024)
	end
	return string.format("%.2f KB", kb)
end

-- Log a debug message with timestamp and uptime
function SL_Debug.Log(category, message)
	if not SL_Debug.enabled then return end
	
	local uptime = SL_Debug.FormatUptime()
	local mem = SL_Debug.FormatMemory()
	local log_msg = string.format("[%s] [%s] [Mem: %s] %s", uptime, category, mem, message)
	
	Trace(log_msg)
end

-- Log screen transition
function SL_Debug.LogScreenChange(screen_name)
	if not SL_Debug.enabled or not SL_Debug.log_screen_changes then return end
	
	SL_Debug.screen_count = SL_Debug.screen_count + 1
	local prev = SL_Debug.last_screen or "none"
	SL_Debug.last_screen = screen_name
	
	SL_Debug.Log("SCREEN", string.format("#%d: %s (from: %s)", 
		SL_Debug.screen_count, screen_name, prev))
end

-- Log periodic status (call from a recurring actor update)
function SL_Debug.LogPeriodicStatus()
	if not SL_Debug.enabled or not SL_Debug.log_memory then return end
	
	local now = GetTimeSinceStart and GetTimeSinceStart() or 0
	if now - SL_Debug.last_periodic_log < SL_Debug.log_interval_seconds then
		return
	end
	SL_Debug.last_periodic_log = now
	
	-- Force garbage collection to get accurate memory reading
	collectgarbage("collect")
	
	local song = GAMESTATE:GetCurrentSong()
	local song_name = song and song:GetDisplayMainTitle() or "none"
	
	SL_Debug.Log("STATUS", string.format(
		"Screens: %d | Current Song: %s | Stage: %d",
		SL_Debug.screen_count,
		song_name,
		GAMESTATE:GetCurrentStageIndex() + 1
	))
	
	-- Log MusicWheel state if available
	if SL and SL.MusicWheel and SL.MusicWheel.State then
		local state = SL.MusicWheel.State
		SL_Debug.Log("WHEEL", string.format(
			"Items: %d | Focus: %d | Sort: %s",
			#state.items,
			state.focus_index,
			state.sort_order
		))
	end
end

-- Log when entering a potentially crash-prone operation
function SL_Debug.LogOperation(operation_name, details)
	if not SL_Debug.enabled then return end
	SL_Debug.Log("OP", string.format("%s: %s", operation_name, details or ""))
end

-- Log error with context
function SL_Debug.LogError(context, error_msg)
	-- Always log errors, even if debug is disabled
	local uptime = SL_Debug.FormatUptime()
	local mem = SL_Debug.FormatMemory()
	local log_msg = string.format("[%s] [ERROR] [Mem: %s] [%s] %s", uptime, mem, context, error_msg)
	Trace(log_msg)
end

-- Wrap a function with error logging
function SL_Debug.SafeCall(context, fn, ...)
	local success, result = pcall(fn, ...)
	if not success then
		SL_Debug.LogError(context, tostring(result))
		return nil
	end
	return result
end

-- Create a timer for profiling operations
-- Uses GetTimeSinceStart() which returns seconds with high precision
function SL_Debug.StartTimer()
	return GetTimeSinceStart and GetTimeSinceStart() or 0
end

function SL_Debug.EndTimer(start_time, operation_name, threshold_ms)
	local now = GetTimeSinceStart and GetTimeSinceStart() or 0
	local elapsed = (now - start_time) * 1000  -- Convert to ms
	threshold_ms = threshold_ms or 100  -- Default 100ms threshold
	
	if elapsed > threshold_ms then
		SL_Debug.Log("PERF", string.format("%s took %.2fms (threshold: %dms)", 
			operation_name, elapsed, threshold_ms))
	end
	
	return elapsed
end

-- Initialize session tracking
SL_Debug.session_start = GetTimeSinceStart and GetTimeSinceStart() or 0
-- Note: Can't call Log here because Trace may not be available during script load