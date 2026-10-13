-- Run with Lua 5.1 from the repository root: the flight point reminder. An undiscovered neutral or
-- own-faction node in range names the place; a learned node, an enemy node, and a friendly node
-- past 400 yards stay quiet. A capital shows with no distance check. Combat and a taxi hide it.
-- The switch off registers nothing.

local Load = dofile("Tools/regression/load_files.lua")

local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local NEUTRAL, HORDE, ALLIANCE = 0, 1, 2
local BARRENS, STORMWIND, UNDERCITY, CAVES = 1413, 1453, 1458, 9001
local SECRET = "secret"

local state = { map = BARRENS, pos = { x = 0, y = 0 }, faction = "Alliance", taxi = false,
    combat = false, secret = false, nodes = {}, asked = nil }
local frames, named = {}, {}

local function NewFrame(name)
    local f = { events = {} }
    function f:SetScript(script, fn) self[script] = fn end
    function f:RegisterEvent(event) self.events[event] = true end
    function f:UnregisterAllEvents()
        for event in pairs(self.events) do self.events[event] = nil end
    end
    function f:SetMovable() end
    function f:SetClampedToScreen() end
    function f:SetPoint() end
    function f:SetSize() end
    function f:SetWidth() end
    function f:SetText(text) self.value = text end
    function f:GetStringWidth() return 10 end
    function f:SetTextColor() end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    frames[#frames + 1] = f
    if name then named[name] = f end
    return f
end

local function Listening(event)
    for i = 1, #frames do
        if frames[i].events[event] then return true end
    end
end

local function Fire(event)
    for i = 1, #frames do
        local f = frames[i]
        if f.events[event] and f.OnEvent then f:OnEvent(event) end
    end
end

local function Text()
    local f = named.NaowhForeverFlightPoint
    if not f or not f.shown then return nil end
    return f.text.value
end

local function Node(name, faction, x, learned)
    return { name = name, faction = faction, isUndiscovered = not learned, position = { x = x, y = 0 } }
end

local function At(map, list)
    state.map, state.nodes = map, list
    Fire("ZONE_CHANGED")
    return Text()
end

local values, defaults = {}, {
    enabled = true, flightPoint = false, flightPointFont = "", flightPointFontSize = 22,
    flightPointOutline = "OUTLINE", flightPointBackground = "none", flightPointTheme = false,
}
local S = { Get = function(k)
    local v = values[k]
    if v == nil then return defaults[k] end
    return v
end }
function S.Set(k, v) values[k] = v end

local ns = { L = dofile("Tools/regression/locale_stub.lua").L, QoLSettings = S,
    TownCapitals = { [STORMWIND] = true, [UNDERCITY] = true },
    THEME = { accent = { r = 0, g = 0.5, b = 0.9 } },
    Font = function(parent)
        parent.text = NewFrame()
        return parent.text
    end,
    AlertStack = function() end,
    Apply = function() end, ShowUnlockMode = function() end, HideUnlockMode = function() end,
    Shared = {
        Parts = { HudBackdrop = function()
            return { SetMode = function(_, mode) return mode end }
        end, HudFont = function() end },
        Style = { CARD_PAD = 12 },
        Settings = { Page = function() return { Card = function() end } end,
            Look = function() return {} end, Group = function() return {} end },
    },
}

local env = {
    NaowhForever = ns,
    Enum = { UIMapType = { Zone = 3 }, FlightPathFaction = { Neutral = NEUTRAL, Horde = HORDE, Alliance = ALLIANCE } },
    CreateFrame = function(_, name) return NewFrame(name) end,
    hooksecurefunc = function(t, key, callback)
        local orig = t[key]
        t[key] = function(...) orig(...); callback(...) end
    end,
    UIParent = {},
    UnitFactionGroup = function() return state.faction end,
    UnitOnTaxi = function() return state.taxi end,
    UnitAffectingCombat = function() return state.combat end,
    issecretvalue = function(v) return state.secret and v == SECRET end,
    C_Map = {
        GetBestMapForUnit = function() return state.map end,
        GetMapInfo = function(id)
            if id == CAVES then return { mapID = CAVES, mapType = 4, parentMapID = UNDERCITY } end
            return { mapID = id, mapType = 3, parentMapID = 0 }
        end,
        GetPlayerMapPosition = function() return state.pos end,
        GetWorldPosFromMapPos = function(_, pos) return 0, pos end,
    },
    C_TaxiMap = { GetTaxiNodesForMap = function(map)
        state.asked = map
        return state.nodes[map] or state.nodes
    end },
}
env._G = env
setmetatable(env, { __index = _G })
Load({ "NaowhForever_QoL/Travel/FlightPoint.lua" }, env)

Fire("PLAYER_LOGIN")
check("the switch off registers nothing", not Listening("ZONE_CHANGED") and not Listening("PLAYER_STOPPED_MOVING")
    and not Listening("TAXIMAP_CLOSED") and not Listening("PLAYER_REGEN_DISABLED")
    and not Listening("PLAYER_CONTROL_LOST") and state.asked == nil and named.NaowhForeverFlightPoint == nil)

S.Set("flightPoint", true)
check("turning it on listens for a zone change", Listening("ZONE_CHANGED") and Listening("TAXIMAP_CLOSED")
    and Listening("PLAYER_STOPPED_MOVING") and Listening("PLAYER_CONTROL_LOST"))

check("an undiscovered neutral node in range names the place",
    At(BARRENS, { Node("Ratchet, The Barrens", NEUTRAL, 100) }) == "Learn the Ratchet flight point")
check("an undiscovered flight point of your own faction names the place",
    At(BARRENS, { Node("Sentinel Hill, Westfall", ALLIANCE, 80) }) == "Learn the Sentinel Hill flight point")
check("a name with no comma is the whole name",
    At(BARRENS, { Node("Moonglade", ALLIANCE, 10) }) == "Learn the Moonglade flight point")
check("the nearer of two unlearned flight points wins",
    At(BARRENS, { Node("Far Town, The Barrens", NEUTRAL, 200), Node("Near Town, The Barrens", NEUTRAL, 50) })
    == "Learn the Near Town flight point")
check("400 yards is still the town",
    At(BARRENS, { Node("Ratchet, The Barrens", NEUTRAL, 400) }) == "Learn the Ratchet flight point")

check("a learned flight point stays hidden",
    At(BARRENS, { Node("Ratchet, The Barrens", NEUTRAL, 100, true) }) == nil)
check("a friendly flight point past 400 yards stays hidden",
    At(BARRENS, { Node("Ratchet, The Barrens", NEUTRAL, 401) }) == nil)
check("a learned node nearby does not stand in for one past 400 yards",
    At(BARRENS, { Node("Ratchet, The Barrens", NEUTRAL, 50, true), Node("Camp Taurajo, The Barrens", NEUTRAL, 500) })
    == nil)
check("the other faction's flight point stays hidden",
    At(BARRENS, { Node("Crossroads, The Barrens", HORDE, 20) }) == nil)

state.faction = "Horde"
check("a Horde character is reminded of a Horde flight point",
    At(BARRENS, { Node("Crossroads, The Barrens", HORDE, 20) }) == "Learn the Crossroads flight point")
state.faction = "Alliance"

check("Alliance in Undercity sees nothing",
    At(UNDERCITY, { Node("Undercity, Tirisfal", HORDE, 0) }) == nil and state.asked == UNDERCITY)
check("Alliance in a cave under Undercity still sees nothing",
    At(CAVES, { [UNDERCITY] = { Node("Undercity, Tirisfal", HORDE, 0) } }) == nil and state.asked == UNDERCITY)

check("a capital shows the flight point with no distance check",
    At(STORMWIND, { Node("Stormwind, Elwynn", ALLIANCE, 2000) }) == "Learn the Stormwind flight point")
check("on a capital the nearer flight point still wins",
    At(STORMWIND, { Node("Far Gate, Elwynn", ALLIANCE, 3000), Node("Trade District, Elwynn", ALLIANCE, 2000) })
    == "Learn the Trade District flight point")

state.secret, state.pos = true, { x = SECRET, y = 0 }
check("a secret coordinate hides the reminder", At(STORMWIND, { Node("Stormwind, Elwynn", ALLIANCE, 10) }) == nil)
state.secret, state.pos = false, { x = 0, y = 0 }

At(BARRENS, { Node("Ratchet, The Barrens", NEUTRAL, 100) })
Fire("PLAYER_REGEN_DISABLED")
check("combat hides it", Text() == nil)
Fire("PLAYER_REGEN_ENABLED")
check("leaving combat shows it again", Text() == "Learn the Ratchet flight point")

state.taxi = true
Fire("PLAYER_CONTROL_LOST")
check("a taxi hides it", Text() == nil)
state.taxi = false
Fire("PLAYER_CONTROL_GAINED")
check("landing shows it again", Text() == "Learn the Ratchet flight point")

state.nodes = {}
ns.ShowUnlockMode()
check("Unlock Mode shows the sample line", Text() == "Learn the Ratchet flight point")
ns.HideUnlockMode()
check("leaving Unlock Mode hides it when no flight point is nearby", Text() == nil)

S.Set("flightPoint", false)
check("turning it off drops the events and hides the line", not Listening("ZONE_CHANGED")
    and not Listening("PLAYER_CONTROL_LOST") and Text() == nil)

print(checks .. " flight point checks passed")
