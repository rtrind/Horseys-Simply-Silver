-- SL-ActorPool.lua
-- Global actor pooling and memory management system
-- Prevents memory leaks by reusing actors instead of creating/destroying them

-- Initialize the global pool in SL table (SL is defined in SL_Init.lua)
if not SL then SL = {} end

SL.ActorPool = {
	-- Stored actor references (populated at runtime by actual actors)
	Actors = {
		NotefieldPreview = {}, -- [player] = actor reference
		BannerSprite = nil,    -- Single banner sprite for SSM
		GroupBannerSprite = nil,
		CDTitleSprite = nil,
	},
	
	-- Pool of reusable Quads for BPMLines (created lazily)
	QuadPool = {},
	QuadPoolSize = 0,
	QuadPoolUsed = 0,
	
	-- Pool of reusable BitmapText for BPMLines
	TextPool = {},
	TextPoolSize = 0,
	TextPoolUsed = 0,
	
	-- Memory tracking
	LastGCTime = 0,
	GCInterval = 30, -- Force GC every 30 seconds during gameplay
	
	-- Debug/monitoring
	DebugMode = false,
	MemoryLog = {},
}

local Pool = SL.ActorPool

-- Get or create a Quad from the pool
-- Returns nil during actor tree construction (must be called from commands)
function Pool.GetQuad()
	Pool.QuadPoolUsed = Pool.QuadPoolUsed + 1
	if Pool.QuadPoolUsed <= Pool.QuadPoolSize then
		local quad = Pool.QuadPool[Pool.QuadPoolUsed]
		quad:visible(true)
		return quad
	end
	return nil -- Pool exhausted, caller should handle
end

-- Return a Quad to the pool (hide it)
function Pool.ReturnQuad(quad)
	if quad then
		quad:visible(false):diffusealpha(0)
	end
end

-- Reset pool usage counters (call at start of screen)
function Pool.ResetPools()
	-- Hide all pooled quads
	for i = 1, Pool.QuadPoolSize do
		if Pool.QuadPool[i] then
			Pool.QuadPool[i]:visible(false)
		end
	end
	Pool.QuadPoolUsed = 0
	
	-- Hide all pooled text
	for i = 1, Pool.TextPoolSize do
		if Pool.TextPool[i] then
			Pool.TextPool[i]:visible(false)
		end
	end
	Pool.TextPoolUsed = 0
end

-- Force garbage collection and log memory
function Pool.ForceGC(context)
	local before = collectgarbage("count")
	collectgarbage("collect")
	collectgarbage("collect") -- Second pass for weak references
	local after = collectgarbage("count")
	local freed = before - after
	
	Pool.LastGCTime = os.time()
	
	if Pool.DebugMode or freed > 100 then -- Log if freed more than 100KB
		Trace(string.format("SL.ActorPool GC [%s]: %.1f KB -> %.1f KB (freed %.1f KB)", 
			context or "unknown", before, after, freed))
	end
	
	return freed
end

-- Register a NoteField preview actor for reuse
function Pool.RegisterNotefieldPreview(player, actor)
	local pn = tonumber(player) or (player == PLAYER_1 and 0 or 1)
	Pool.Actors.NotefieldPreview[pn] = actor
	if Pool.DebugMode then
		Trace("SL.ActorPool: Registered NotefieldPreview for player " .. pn)
	end
end

-- Get the registered NoteField preview for a player
function Pool.GetNotefieldPreview(player)
	local pn = tonumber(player) or (player == PLAYER_1 and 0 or 1)
	return Pool.Actors.NotefieldPreview[pn]
end

-- Register banner sprite for reuse
function Pool.RegisterBanner(name, actor)
	Pool.Actors[name] = actor
	if Pool.DebugMode then
		Trace("SL.ActorPool: Registered banner " .. name)
	end
end

-- Unload all registered textures (call on screen exit)
function Pool.UnloadTextures()
	if Pool.Actors.BannerSprite and Pool.Actors.BannerSprite.unloadtexture then
		Pool.Actors.BannerSprite:unloadtexture()
	end
	if Pool.Actors.GroupBannerSprite and Pool.Actors.GroupBannerSprite.unloadtexture then
		Pool.Actors.GroupBannerSprite:unloadtexture()
	end
	if Pool.Actors.CDTitleSprite and Pool.Actors.CDTitleSprite.unloadtexture then
		Pool.Actors.CDTitleSprite:unloadtexture()
	end
end

-- Memory monitoring function (can be called periodically)
function Pool.LogMemory(context)
	local lua_mem = collectgarbage("count")
	local entry = {
		time = os.time(),
		context = context or "unknown",
		lua_kb = lua_mem
	}
	table.insert(Pool.MemoryLog, entry)
	
	-- Keep only last 100 entries
	if #Pool.MemoryLog > 100 then
		table.remove(Pool.MemoryLog, 1)
	end
	
	if Pool.DebugMode then
		Trace(string.format("SL.ActorPool Memory [%s]: Lua=%.1f KB", context, lua_mem))
	end
	
	return lua_mem
end

-- Check if GC should run based on interval
function Pool.ShouldRunGC()
	return (os.time() - Pool.LastGCTime) >= Pool.GCInterval
end

-- Screen transition helper - call when entering a new screen
function Pool.OnScreenEnter(screen_name)
	Pool.ResetPools()
	Pool.ForceGC("Enter " .. (screen_name or "unknown"))
	Pool.LogMemory("Enter " .. (screen_name or "unknown"))
end

-- Screen transition helper - call when leaving a screen
function Pool.OnScreenExit(screen_name)
	Pool.UnloadTextures()
	Pool.ForceGC("Exit " .. (screen_name or "unknown"))
end

-- Enable debug logging
function Pool.EnableDebug()
	Pool.DebugMode = true
	Trace("SL.ActorPool: Debug mode enabled")
end

-- Disable debug logging
function Pool.DisableDebug()
	Pool.DebugMode = false
end

-- Get memory statistics
function Pool.GetStats()
	return {
		lua_memory_kb = collectgarbage("count"),
		quad_pool_size = Pool.QuadPoolSize,
		quad_pool_used = Pool.QuadPoolUsed,
		text_pool_size = Pool.TextPoolSize,
		text_pool_used = Pool.TextPoolUsed,
		last_gc_time = Pool.LastGCTime,
		memory_log_entries = #Pool.MemoryLog,
	}
end

Trace("SL.ActorPool: Loaded actor pooling and memory management system")
