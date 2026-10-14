-- Run with Lua 5.1 from the repository root: the Tracking Reminder module tests.
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return s
end

local function Short(text)
    return type(text) == "string" and #text < 100 and not text:find("%. ")
end

local function Has(list, spell)
    for i = 1, #list do
        if list[i] == spell then return true end
    end
    return false
end

local BEASTS, HUMANOIDS, UNDEAD, HIDDEN = 1494, 19883, 19884, 19885
local SENSE_UNDEAD, FIND_TREASURE = 5502, 2481

local function Load(opts)
    opts = opts or {}
    local store, listeners, frames = {}, {}, {}
    local card
    local who = { race = opts.race or "Human", class = opts.class or "HUNTER" }
    local known, active = opts.known or {}, opts.active or {}
    local S = {}
    function S.Get(k) return store[k] end
    function S.Set(k, v)
        store[k] = v
        for i = 1, #listeners do listeners[i](k, v) end
    end
    function S.OnChange(fn) listeners[#listeners + 1] = fn end
    local ns = {
        L = dofile("Tools/regression/locale_stub.lua").L,
        Upper = string.upper, Lower = string.lower,
        THEME = { accentSoft = {} },
        Border = function() end,
        Font = function() return { SetPoint = function() end, SetText = function() end } end,
        Apply = function() end, ShowUnlockMode = function() end, HideUnlockMode = function() end,
        UI = {
            ModuleSettings = function(_, defaults)
                for k, v in pairs(defaults) do
                    if store[k] == nil then store[k] = v end
                end
                return S
            end,
            AttachMover = function() return { SetShown = function() end } end,
        },
        Shared = {
            Style = { BORDER_RGB = {}, ICON_CROP = 0.08, HUD_TEXT_RANGE = { 8, 24, 1 } },
            Parts = { HudFont = function() end },
            Settings = {
                Group = function(title) return { group = title } end,
                Look = function() return {} end,
                Page = function()
                    local page = {}
                    function page:Card(spec) card = spec; return spec end
                    return page
                end,
            },
        },
    }
    local function Frame()
        local f = { scripts = {}, events = {}, attrs = {} }
        function f:SetScript(k, fn) self.scripts[k] = fn end
        function f:RegisterEvent(e) self.events[e] = true end
        function f:UnregisterAllEvents() self.events = {} end
        function f:CreateTexture()
            return setmetatable({}, { __index = function(_, key)
                if type(key) == "string" and key:find("^%u") then return function() end end
            end })
        end
        function f:SetAttribute(k, v) self.attrs[k] = v end
        return setmetatable(f, { __index = function(_, key)
            if type(key) == "string" and key:find("^%u") then return function() end end
        end })
    end
    local env = setmetatable({
        NaowhForever = ns, UIParent = {},
        CreateFrame = function(_, name, _, template)
            local f = Frame()
            f.name, f.template = name, template
            frames[#frames + 1] = f
            return f
        end,
        hooksecurefunc = function(tbl, name, fn)
            local prev = tbl[name]
            tbl[name] = function(...)
                if prev then prev(...) end
                return fn(...)
            end
        end,
        wipe = function(t)
            for k in pairs(t) do t[k] = nil end
            return t
        end,
        InCombatLockdown = function() return false end,
        UnitIsDeadOrGhost = function() return false end,
        UnitOnTaxi = function() return false end,
        IsInInstance = function() return false end,
        UnitRace = function() return who.race, who.race end,
        UnitClass = function() return who.class, who.class end,
        GameTooltip = { SetOwner = function() end, SetSpellByID = function() end, Show = function() end },
        GameTooltip_Hide = function() end,
        C_Spell = { GetSpellTexture = function(id) return id end },
        C_SpellBook = { IsSpellKnown = function(id) return known[id] == true end },
        C_Minimap = {
            GetNumTrackingTypes = function() return #active end,
            GetTrackingInfo = function(i)
                local id = active[i]
                if opts.tuple then return "name", "tex", true, "spell", "spell", id end
                return { spellID = id, active = true }
            end,
        },
    }, { __index = _G })
    env._G = env
    for _, file in ipairs({
        "Core/Features.lua",
        "NaowhForever_TrackingReminder/TrackingReminder.lua",
        "NaowhForever_TrackingReminder/Data/Spells.lua",
        "NaowhForever_TrackingReminder/UI/Reminder.lua",
        "NaowhForever_TrackingReminder/UI/SettingsPage.lua",
    }) do
        local chunk = assert(loadstring(Read(file), file))
        setfenv(chunk, env)
        chunk()
    end
    if opts.settings then
        for k, v in pairs(opts.settings) do S.Set(k, v) end
    end
    for _, f in ipairs(frames) do
        if f.scripts.OnEvent and f.events.PLAYER_LOGIN then f.scripts.OnEvent(f, "PLAYER_LOGIN") end
    end
    return { ns = ns, S = S, frames = frames, card = card, who = who }
end

local function Armed(world)
    local spells = {}
    for _, f in ipairs(world.frames) do
        if f.template == "SecureActionButtonTemplate" and f.attrs.spell1 then
            spells[#spells + 1] = f.attrs.spell1
        end
    end
    return spells
end

local function TrackingOn(world)
    for _, f in ipairs(world.frames) do
        if f.events.MINIMAP_UPDATE_TRACKING then return true end
    end
    return false
end

local function Named(world, name)
    for _, f in ipairs(world.frames) do
        if f.name == name then return f end
    end
end

do
    local ns = {
        L = dofile("Tools/regression/locale_stub.lua").L,
        Upper = string.upper, Lower = string.lower,
    }
    _G.NaowhForever = ns
    assert(loadstring(Read("Core/Features.lua"), "Features"))()
    check("trackingReminder feature switches exist", ns.FEATURES.trackingReminder ~= nil)
    check("trackingReminder is off by default", ns.FEATURES.trackingReminder.enabled == false)
    check("trackRacial is off by default", ns.FEATURES.trackingReminder.trackRacial == false)
    check("trackClass is off by default", ns.FEATURES.trackingReminder.trackClass == false)
end

do
    local world = Load()
    local TR = world.ns.TrackingReminder
    check("TrackingReminder module table exists", TR ~= nil)
    check("TrackingReminder.Enabled() is false", TR.Enabled() == false)
    check("TrackingReminder.On() is false", TR.On() == false)
    check("Find Treasure ID is 2481", TR.Data.FIND_TREASURE == FIND_TREASURE)
    check("RACIAL contains Dwarf Find Treasure", #TR.Data.RACIAL == 1 and TR.Data.RACIAL[1].spell == FIND_TREASURE
        and TR.Data.RACIAL[1].race == "Dwarf")
    local hunterSpells, paladinSpells, warlockSpells = 0, 0, 0
    for _, t in ipairs(TR.Data.CLASS) do
        if t.class == "HUNTER" then hunterSpells = hunterSpells + 1 end
        if t.class == "PALADIN" then paladinSpells = paladinSpells + 1 end
        if t.class == "WARLOCK" then warlockSpells = warlockSpells + 1 end
    end
    check("Hunter has 8 tracking spells", hunterSpells == 8)
    check("Paladin has Sense Undead", paladinSpells == 1)
    check("Warlock has Sense Demons", warlockSpells == 1)
    check("off: no tracking events", not TrackingOn(world))
    check("off: no reminder row", Named(world, "NaowhForeverTrackingReminder") == nil)
    check("off: no secure buttons", #Armed(world) == 0)
    check("card help is one short sentence", Short(world.card.help))
    local rows = world.card.rows()
    for i = 1, #rows do
        if rows[i].help then
            check("help is one short sentence: " .. tostring(rows[i].label), Short(rows[i].help))
        end
    end
    local hunterFields = {}
    for i = 1, #rows do
        if rows[i].field then hunterFields[rows[i].field] = true end
    end
    check("a human hunter sees beast tracking", hunterFields.beasts == true)
    check("a human hunter does not see Find Treasure", hunterFields.treasure ~= true)
    check("a human hunter does not see Sense Undead", hunterFields.senseUndead ~= true)
    world.who.race, world.who.class = "Dwarf", "PALADIN"
    local paladinFields = {}
    rows = world.card.rows()
    for i = 1, #rows do
        if rows[i].field then paladinFields[rows[i].field] = true end
    end
    check("a dwarf paladin sees Find Treasure", paladinFields.treasure == true)
    check("a dwarf paladin sees Sense Undead", paladinFields.senseUndead == true)
    check("a dwarf paladin does not see beast tracking", paladinFields.beasts ~= true)
    world.who.race, world.who.class = "Human", "MAGE"
    rows = world.card.rows()
    local mageTracking = false
    for i = 1, #rows do
        if rows[i].key == "trackRacial" or rows[i].key == "trackClass" or rows[i].field then mageTracking = true end
    end
    check("a mage has no racial or class rows", not mageTracking)
end

do
    local world = Load({
        known = { [BEASTS] = true, [HUMANOIDS] = true, [UNDEAD] = true, [HIDDEN] = true },
        settings = { enabled = true, trackClass = true, trackRacial = true },
    })
    local spells = Armed(world)
    check("four missing hunter tracks get four icons", #spells == 4)
    check("the four icons are those tracks", Has(spells, BEASTS) and Has(spells, HUMANOIDS)
        and Has(spells, UNDEAD) and Has(spells, HIDDEN))
    check("on: tracking events are registered", TrackingOn(world))
    world.S.Set("classPicks", { beasts = false })
    spells = Armed(world)
    check("turning a pick off drops that icon", #spells == 3 and not Has(spells, BEASTS)
        and Has(spells, HUMANOIDS) and Has(spells, UNDEAD) and Has(spells, HIDDEN))
end

do
    local world = Load({
        tuple = true,
        known = {
            [BEASTS] = true, [HUMANOIDS] = true, [UNDEAD] = true, [HIDDEN] = true,
            [SENSE_UNDEAD] = true, [FIND_TREASURE] = true,
        },
        active = { BEASTS },
        settings = {
            enabled = true, trackClass = true, trackRacial = true,
            classPicks = { hidden = false },
        },
    })
    local spells = Armed(world)
    check("an active track, a turned-off pick, and other classes are omitted", #spells == 2
        and Has(spells, HUMANOIDS) and Has(spells, UNDEAD) and not Has(spells, BEASTS)
        and not Has(spells, HIDDEN) and not Has(spells, SENSE_UNDEAD) and not Has(spells, FIND_TREASURE))
end

print(("test-tracking-reminder: %d checks passed"):format(checks))
