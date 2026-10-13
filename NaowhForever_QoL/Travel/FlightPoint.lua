-- FlightPoint.lua: the QoL reminder to learn a town's flight point.
local ns = _G.NaowhForever

local issecretvalue = issecretvalue

local S = ns.QoLSettings
local T = ns.THEME
local Parts, St = ns.Shared.Parts, ns.Shared.Style

local WIDTH, ROOM = 300, 10
local STACK_ORDER = 6
local TOWN_RANGE = 400
local ZONE = Enum.UIMapType.Zone
local CONTINENT = Enum.UIMapType.Continent
local NEUTRAL = Enum.FlightPathFaction.Neutral
local HORDE = Enum.FlightPathFaction.Horde
local ALLIANCE = Enum.FlightPathFaction.Alliance
local UNREACHABLE = Enum.FlightPathState.Unreachable
local PAGE = "QoL/Travel"
local PLAYER = "player"
local STORE = "flightPoints"
local LEARN, ASK = "learn", "ask"
local TEXT_ALERT = "Flight Point"
local SAMPLE_PLACE = "Ratchet"

local TEXT = ns.L("Learn the %s flight point")
local OPEN = ns.L("Open a flight master's map to save the points you know")

local EVENTS = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD",
    "PLAYER_STOPPED_MOVING", "TAXIMAP_OPENED", "TAXIMAP_CLOSED", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }

local frame, unlocked, inCombat
local events = CreateFrame("Frame")

local function On()
    return S.Get("enabled") and S.Get("flightPoint")
end

local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

local function PlaceName(name)
    local comma = name:find(",", 1, true)
    if not comma then return name end
    return name:sub(1, comma - 1)
end

local function Ours(faction)
    if faction == NEUTRAL then return true end
    local side = UnitFactionGroup(PLAYER)
    if side == "Horde" then return faction == HORDE end
    if side == "Alliance" then return faction == ALLIANCE end
    return false
end

local function PlayerGUID()
    local guid = UnitGUID(PLAYER)
    if Secret(guid) or type(guid) ~= "string" or guid == "" then return nil end
    return guid
end

local function Mine(create)
    if not PlayerGUID() then return end
    return ns.Shared.CharacterData(STORE, create)
end

local function Kind(node, mine)
    if not (Ours(node.faction) and node.name) then return nil end
    if node.isUndiscovered then return LEARN end
    if mine and mine.seen then
        if mine[node.nodeID] ~= true then return LEARN end
        return nil
    end
    return ASK
end

local function Learn()
    local mine = Mine(true)
    local taxi = mine and GetTaxiMapID()
    if not taxi then return end
    mine.seen = true
    for _, node in ipairs(C_TaxiMap.GetAllTaxiNodes(taxi)) do
        if node.nodeID then mine[node.nodeID] = node.state ~= UNREACHABLE end
    end
end

local function Subzone()
    local text = GetSubZoneText()
    if not text or Secret(text) then return "" end
    return text
end

local function ZoneMap()
    local id = C_Map.GetBestMapForUnit(PLAYER)
    local info = id and C_Map.GetMapInfo(id)
    while info and info.mapType > ZONE and info.parentMapID and info.parentMapID > 0 do
        info = C_Map.GetMapInfo(info.parentMapID)
    end
    if info and info.mapType == ZONE then return info.mapID end
end

local function WorldOf(map, pos)
    if not map or not pos then return nil, false end
    if Secret(pos.x) or Secret(pos.y) then return nil, true end
    local _, world = C_Map.GetWorldPosFromMapPos(map, pos)
    if not world then return nil, false end
    if Secret(world.x) or Secret(world.y) then return nil, true end
    return world, false
end

local function Yards(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local function Candidate(node, map, zone, player, subzone, mine)
    local kind = Kind(node, mine)
    if not kind then return nil end
    local world, blocked = WorldOf(map, node.position)
    if blocked then return nil, true end
    local dist = player and world and Yards(player, world)
    local place = PlaceName(node.name)
    local capital = ns.TownCapitals[zone] and map == zone
    local named = subzone ~= "" and subzone == place
    if not (capital or named or (dist and dist <= TOWN_RANGE)) then return nil end
    return kind, place, dist or math.huge
end

local function Scan(map, zone, player, subzone, mine)
    local bestName, bestDist, ask
    for _, node in ipairs(C_TaxiMap.GetTaxiNodesForMap(map)) do
        local kind, place, rank = Candidate(node, map, zone, player, subzone, mine)
        if place == true then return nil, true end
        if kind == LEARN and (not bestName or rank < bestDist) then bestName, bestDist = place, rank end
        if kind == ASK then ask = true end
    end
    return bestName, nil, ask
end

local function Nearest()
    if inCombat or UnitOnTaxi(PLAYER) then return nil end
    local zone = ZoneMap()
    if not zone then return nil end
    local here = C_Map.GetBestMapForUnit(PLAYER)
    local player, secret = WorldOf(here, here and C_Map.GetPlayerMapPosition(here, PLAYER))
    if secret then return nil end
    local subzone, mine = Subzone(), Mine()
    local nodes = C_TaxiMap.GetTaxiNodesForMap(zone)
    local best, blocked, ask
    if nodes[1] then
        best, blocked, ask = Scan(zone, zone, player, subzone, mine)
    else
        local info = C_Map.GetMapInfo(zone)
        while info and info.parentMapID and info.parentMapID > 0 do
            local parent = info.parentMapID
            info = C_Map.GetMapInfo(parent)
            nodes = C_TaxiMap.GetTaxiNodesForMap(parent)
            if nodes[1] then
                best, blocked, ask = Scan(parent, zone, player, subzone, mine)
                break
            end
            if not info or info.mapType <= CONTINENT then break end
        end
    end
    if blocked or best then return best end
    return nil, ask
end

local function Show(place)
    frame.text:SetText(place and TEXT:format(place) or OPEN)
    frame:SetWidth(frame.mode == "none" and WIDTH or frame.text:GetStringWidth() + 2 * St.CARD_PAD)
    frame:Show()
end

local function Update()
    if unlocked then
        Show(SAMPLE_PLACE)
        return
    end
    local place, ask = Nearest()
    if place or ask then Show(place) else frame:Hide() end
end

local function OnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    elseif event == "TAXIMAP_OPENED" then
        Learn()
    end
    Update()
end

local function Build()
    frame = CreateFrame("Frame", "NaowhForeverFlightPoint", UIParent)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame.text = ns.Font(frame, St.TEXT_SIZE, "OUTLINE")
    frame.text:SetPoint("CENTER")
    frame.backdrop = Parts.HudBackdrop(frame, { mode = "none" })
    ns.AlertStack(frame, STACK_ORDER, TEXT_ALERT, PAGE, PAGE .. ":flightPoint")
end

local function Restyle()
    local size = S.Get("flightPointFontSize")
    frame.mode = frame.backdrop:SetMode(S.Get("flightPointBackground"))
    Parts.HudFont(frame.text, S.Get("flightPointFont"), size, S.Get("flightPointOutline"), frame.mode)
    local c = S.Get("flightPointCustom") and S.Get("flightPointColor") or T.accent
    frame.text:SetTextColor(c.r, c.g, c.b, 1)
    frame:SetSize(WIDTH, size + ROOM)
end

local function Apply()
    events:UnregisterAllEvents()
    if not On() then
        if frame then frame:Hide() end
        return
    end
    if not frame then Build() end
    Restyle()
    inCombat = UnitAffectingCombat(PLAYER)
    for _, event in ipairs(EVENTS) do events:RegisterEvent(event) end
    Update()
end

events:SetScript("OnEvent", OnEvent)

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key:find("^flightPoint") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowUnlockMode", function()
    unlocked = S.Get("enabled") == true
    Apply()
end)
hooksecurefunc(ns, "HideUnlockMode", function()
    unlocked = false
    Apply()
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

local Settings = ns.Shared.Settings

Settings.Page(PAGE, S):Card({
    id = "flightPoint", name = "Flight Point", order = 12, switch = "flightPoint",
    help = "Text on screen in a town whose flight point you have not learned, when it is neutral "
        .. "or your faction's. Until this character opens a flight master's map, it asks you to "
        .. "open one to save the points you know. Hidden in combat. Move it in the HUD Editor.",
    rows = {
        Settings.Look("flightPoint", { text = true, size = St.HUD_TEXT_RANGE, background = "card" }),
        Settings.Group("Colors"),
        { key = "flightPointCustom", label = "Custom Color", toggle = true,
          help = "Your own text color instead of the theme's accent." },
        { key = "flightPointColor", label = "Text Color", colour = true, needs = "flightPointCustom" },
    },
})
