-- MemSaver: lazy loading for SMODS atlases and sound effects.
--
-- Stock SMODS decodes every atlas PNG and uploads it to the GPU while the game
-- starts, and reads every sound file into memory. With 50+ content mods that is
-- well over a thousand textures, which does not fit on an 8 GB machine with
-- integrated graphics (textures live in system RAM there).
--
-- Here an atlas only remembers its path and size at inject time. The texture is
-- loaded the first time something reads `atlas.image` (normally the first sprite
-- drawn from it), and pixel data only when something reads `atlas.image_data`.
-- Textures loaded this way are dropped again on the main menu and at run start,
-- so memory tracks what is actually on screen.
--
-- Must load before any mod that wraps SMODS.Atlas.inject (Cryptid, Spectrallib),
-- hence the very low priority.

MEMSAVER = MEMSAVER or {}
local MS = MEMSAVER

MS.STREAM_BYTES = 1024 * 1024 -- sound effects bigger than this are streamed, not decoded whole
MS.size_only = 0
MS.loaded = setmetatable({}, { __mode = 'k' })
MS.pending_sounds = {}
MS.stats = { deferred = 0, loaded = 0, freed = 0, sounds_deferred = 0, sounds_loaded = 0 }

local atlas_table_map = {
    ASSET_ATLAS = "ASSET_ATLAS",
    ANIMATION_ATLAS = "ANIMATION_ATLAS",
    STATE_ATLAS = "ANIMATION_ATLAS",
}

local function log(msg)
    sendInfoMessage(msg, 'MemSaver')
end

local function png_size(path)
    local head = NFS.read(path, 24)
    if type(head) ~= 'string' or #head < 24 or head:sub(2, 4) ~= 'PNG' then return end
    local function u32(i)
        local a, b, c, d = head:byte(i, i + 3)
        return ((a * 256 + b) * 256 + c) * 256 + d
    end
    return u32(17), u32(21)
end

local function localized_path(self)
    return type(self.path) == 'table' and
        ((G.SETTINGS.real_language and self.path[G.SETTINGS.real_language]) or self.path[G.SETTINGS.language] or self.path['default'] or self.path['en-us']) or self.path
end

-------------------------------------------------------------------------------
-- Atlases
-------------------------------------------------------------------------------

local Atlas = SMODS.Atlas
local atlas_inject_ref = Atlas.inject

local function load_image(t)
    local file_data = assert(NFS.newFileData(t.full_path),
        ('MemSaver: failed to read %s for Atlas %s'):format(tostring(t.full_path), tostring(t.key)))
    local image = love.graphics.newImage(file_data, { mipmaps = true, dpiscale = t._ms_scale })
    if t.force_pixel then
        image:setFilter("nearest", "nearest")
    end
    local mipmap_level = SMODS.config.graphics_mipmap_level_options[SMODS.config.graphics_mipmap_level]
    if not t.disable_mipmap and mipmap_level and mipmap_level > 0 then
        image:setMipmapFilter('linear', mipmap_level)
    end
    rawset(t, 'image', image)
    t._ms_image = image
    t._ms_lazy = nil
    MS.loaded[t] = true
    MS.stats.loaded = MS.stats.loaded + 1
end

local function load_image_data(t)
    local file_data = assert(NFS.newFileData(t.full_path),
        ('MemSaver: failed to read %s for Atlas %s'):format(tostring(t.full_path), tostring(t.key)))
    local image_data = love.image.newImageData(file_data)
    rawset(t, 'image_data', image_data)
    t._ms_image_data = image_data
    t._ms_lazy_data = nil
    MS.loaded[t] = true
end

-- Stands in for the texture while code only asks for its size
-- (Game:set_render_settings, Atlas.pre_inject_class), so those loops do not load everything.
local function size_stub(t)
    local w, h = t._ms_w, t._ms_h
    return {
        getWidth = function() return w end,
        getHeight = function() return h end,
        getDimensions = function() return w, h end,
    }
end

-- Instances use the class as their metatable, so missing fields land here.
Atlas.__index = function(t, k)
    if k == 'image' and rawget(t, '_ms_lazy') then
        if MS.size_only > 0 then return size_stub(t) end
        load_image(t)
        return rawget(t, 'image')
    elseif k == 'image_data' and rawget(t, '_ms_lazy_data') then
        load_image_data(t)
        return rawget(t, 'image_data')
    end
    return Atlas[k]
end

local function size_only(func)
    return function(...)
        MS.size_only = MS.size_only + 1
        local ret = { func(...) }
        MS.size_only = MS.size_only - 1
        return unpack(ret)
    end
end

-- Malverk replaces pre_inject_class after we load, so wrap on first injection.
local function install_late_hooks()
    if MS.late_hooks then return end
    MS.late_hooks = true
    if Atlas.pre_inject_class then
        Atlas.pre_inject_class = size_only(Atlas.pre_inject_class)
    end
    Game.set_render_settings = size_only(Game.set_render_settings)
end

-- Same logic as SMODS.Atlas.inject, minus the decoding. Anything unusual
-- (subclasses, non-PNG files, missing scale folder) goes through the original.
function Atlas.inject(self)
    install_late_hooks()
    if getmetatable(self) ~= Atlas then return atlas_inject_ref(self) end

    local file_path = localized_path(self)
    if file_path == 'DEFAULT' then return end
    if self.language and G.SETTINGS.language ~= self.language and G.SETTINGS.real_language ~= self.language then return end
    local texture_scaling = G.SETTINGS.GRAPHICS.texture_scaling
    if self.force_pixel then
        texture_scaling = 1
    end
    if not self.language and (self.obj_table[('%s_%s'):format(self.key, tostring(G.SETTINGS.language))] or self.obj_table[('%s_%s'):format(self.key, tostring(G.SETTINGS.real_language))]) then return end

    local full_path = NFS.getNormalizedPath((self.path_mod or self.mod or SMODS).path ..
        'assets/' .. texture_scaling .. 'x/' .. file_path)
    local w, h = png_size(full_path)
    if not w then
        self._ms_lazy, self._ms_lazy_data = nil, nil
        return atlas_inject_ref(self)
    end

    -- re-inject (texture scaling or language changed): forget the old texture
    if rawget(self, 'image') == self._ms_image then rawset(self, 'image', nil) end
    if rawget(self, 'image_data') == self._ms_image_data then rawset(self, 'image_data', nil) end
    self._ms_image, self._ms_image_data = nil, nil
    MS.loaded[self] = nil

    self.full_path = full_path
    self._ms_scale = texture_scaling
    self._ms_w, self._ms_h = w / texture_scaling, h / texture_scaling
    self._ms_lazy, self._ms_lazy_data = true, true
    self.columns = self._ms_w / self.px
    self.rows = self._ms_h / self.py
    G[atlas_table_map[self.atlas_table]][self.key_noloc or self.key] = self
    MS.stats.deferred = MS.stats.deferred + 1
end

-- Drop every texture we loaded. Sprites look up `atlas.image` on each draw,
-- so whatever is still on screen simply loads again. Textures are not
-- :release()d, in case someone kept a reference; the GC frees them.
function MS.unload_atlases()
    local n = 0
    for t in pairs(MS.loaded) do
        if t._ms_image and rawget(t, 'image') == t._ms_image then
            rawset(t, 'image', nil)
            t._ms_lazy = true
            n = n + 1
        end
        if t._ms_image_data and rawget(t, 'image_data') == t._ms_image_data then
            rawset(t, 'image_data', nil)
            t._ms_lazy_data = true
        end
        t._ms_image, t._ms_image_data = nil, nil
        MS.loaded[t] = nil
    end
    if n > 0 then
        collectgarbage('collect')
        collectgarbage('collect')
        MS.stats.freed = MS.stats.freed + n
        log(('Freed %d atlases'):format(n))
    end
end

local main_menu_ref = Game.main_menu
function Game:main_menu(...)
    MS.unload_atlases()
    return main_menu_ref(self, ...)
end

local start_run_ref = Game.start_run
function Game:start_run(...)
    MS.unload_atlases()
    return start_run_ref(self, ...)
end

-------------------------------------------------------------------------------
-- Sounds
-------------------------------------------------------------------------------

local Sound = SMODS.Sound
local sound_inject_ref = Sound.inject

local function is_music(self)
    return type(self.select_music_track) == 'function' or self.sync
        or string.find(self.key, 'music') or string.find(self.key, 'stream') or string.find(self.key, 'ambient')
end

-- Music is picked inside the sound thread, so it must be there up front;
-- everything else is read from disk the first time play_sound asks for it.
function Sound.inject(self)
    if getmetatable(self) ~= Sound or is_music(self) then return sound_inject_ref(self) end
    local file_path = localized_path(self)
    if file_path == 'DEFAULT' then return end
    local prev_path = self.full_path
    self.full_path = NFS.getNormalizedPath((self.path_mod or self.mod or SMODS).path ..
        'assets/sounds/' .. file_path)
    if prev_path == self.full_path then return end
    if prev_path then G.SOUND_MANAGER.channel:push({ type = 'stop' }) end
    self.data = nil
    MS.pending_sounds[self.sound_code] = self
    MS.stats.sounds_deferred = MS.stats.sounds_deferred + 1
end

local function ensure_sound(sound_code)
    local s = sound_code and MS.pending_sounds[sound_code]
    if not s then return end
    MS.pending_sounds[sound_code] = nil
    local data = NFS.read('data', s.full_path)
    if not data then return end
    s.data = data
    s.should_stream = data:getSize() > MS.STREAM_BYTES or nil
    G.SOUND_MANAGER.channel:push({ type = 'sound_source', sound_code = s.sound_code, data = data, should_stream = s.should_stream, per = s.pitch, vol = s.volume })
    MS.stats.sounds_loaded = MS.stats.sounds_loaded + 1
end

local play_sound_ref = play_sound
function play_sound(sound_code, per, vol)
    ensure_sound(sound_code)
    local replace = Sound.replace_sounds[sound_code]
    if replace and SMODS.Sounds[replace.key] then
        ensure_sound(SMODS.Sounds[replace.key].sound_code)
    end
    return play_sound_ref(sound_code, per, vol)
end

-------------------------------------------------------------------------------

local inject_items_ref = SMODS.injectItems
function SMODS.injectItems(...)
    local ret = { inject_items_ref(...) }
    log(('Atlases deferred: %d, sounds deferred: %d'):format(MS.stats.deferred, MS.stats.sounds_deferred))
    return unpack(ret)
end
