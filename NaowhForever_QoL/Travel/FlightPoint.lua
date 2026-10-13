-- FlightPoint.lua: the QoL reminder to learn a town's flight point.
local ns = _G.NaowhForever

local issecretvalue = issecretvalue

local S = ns.QoLSettings
local T = ns.THEME
local Parts, St = ns.Shared.Parts, ns.Shared.Style

local GOLD = { r = 1, g = 0.82, b = 0 }
local WIDTH, ROOM = 300, 10
local FONT_SIZE = 22
local STACK_ORDER = 6
local TOWN_RANGE = 400
local ZONE = Enum.UIMapType.Zone
local NEUTRAL = Enum.FlightPathFaction.Neutral
local HORDE = Enum.FlightPathFaction.Horde
local ALLIANCE = Enum.FlightPathFaction.Alliance
local PAGE = "QoL/Travel"
local PLAYER = "player"
local TEXT_ALERT = "Flight Point"
local SAMPLE_PLACE = "Ratchet"
local TEXT_RANGE = { 10, 48, 1 }

local TEXT = ns.L("Learn the %s flight point")

local EVENTS = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD",
    "PLAYER_STOPPED_MOVING", "TAXIMAP_CLOSED", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
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

local function Nearest()
    if inCombat or UnitOnTaxi(PLAYER) then return nil end
    local map = ZoneMap()
    if not map then return nil end
    local here = C_Map.GetBestMapForUnit(PLAYER)
    local player, secret = WorldOf(here, here and C_Map.GetPlayerMapPosition(here, PLAYER))
    if secret then return nil end
    local capital = ns.TownCapitals[map]
    local bestName, bestDist
    for _, node in ipairs(C_TaxiMap.GetTaxiNodesForMap(map)) do
        local name = node.isUndiscovered and Ours(node.faction) and node.name
        if name then
            local world, blocked = WorldOf(map, node.position)
            if blocked then return nil end
            local dist = player and world and Yards(player, world)
            if capital or (dist and dist <= TOWN_RANGE) then
                local rank = dist or math.huge
                if not bestName or rank < bestDist then
                    bestName, bestDist = PlaceName(name), rank
                end
            end
        end
    end
    return bestName
end

local function Show(place)
    frame.text:SetText(TEXT:format(place))
    frame:SetWidth(frame.mode == "none" and WIDTH or frame.text:GetStringWidth() + 2 * St.CARD_PAD)
    frame:Show()
end

local function Update()
    if unlocked then
        Show(SAMPLE_PLACE)
        return
    end
    local place = Nearest()
    if place then Show(place) else frame:Hide() end
end

local function OnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    end
    Update()
end

local function Build()
    frame = CreateFrame("Frame", "NaowhForeverFlightPoint", UIParent)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame.text = ns.Font(frame, FONT_SIZE, "OUTLINE")
    frame.text:SetPoint("CENTER")
    frame.backdrop = Parts.HudBackdrop(frame, { mode = "none" })
    ns.AlertStack(frame, STACK_ORDER, TEXT_ALERT, PAGE, PAGE .. ":flightPoint")
end

local function Restyle()
    local size = S.Get("flightPointFontSize")
    frame.mode = frame.backdrop:SetMode(S.Get("flightPointBackground"))
    Parts.HudFont(frame.text, S.Get("flightPointFont"), size, S.Get("flightPointOutline"), frame.mode)
    local c = S.Get("flightPointTheme") and T.accent or GOLD
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
        .. "or your faction's. Hidden in combat. Move it in the HUD Editor.",
    rows = {
        Settings.Look("flightPoint", { text = true, size = TEXT_RANGE, background = "card" }),
        Settings.Group("Colors"),
        { key = "flightPointTheme", label = "Apply Theme to Text Color", toggle = true,
          help = "The text in the theme's accent color instead of gold." },
    },
})
