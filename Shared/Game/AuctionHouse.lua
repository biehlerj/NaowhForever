-- AuctionHouse.lua: whether Blizzard's auction house window is open and on screen (ns.AuctionHouseShown), and a call when an addon's own auction window moves it away or brings it back (ns.OnAuctionHouseMoved).
local ns = _G.NaowhForever

local AH_ADDON = "Blizzard_AuctionHouseUI"
local AWAY_SCALE = 0.01

local hooked, away = false, false
local watchers = {}
local events

local function Away(ah)
    return ah:GetScale() < AWAY_SCALE
end

local function OnScale(ah)
    local now = Away(ah)
    if now == away then return end
    away = now
    for _, fn in ipairs(watchers) do fn() end
end

local function Hook()
    local ah = _G.AuctionHouseFrame
    if hooked or not ah then return end
    hooked = true
    hooksecurefunc(ah, "SetScale", OnScale)
end

local function OnEvent(_, _, name)
    if name ~= AH_ADDON then return end
    events:UnregisterEvent("ADDON_LOADED")
    Hook()
end

function ns.AuctionHouseShown()
    local ah = _G.AuctionHouseFrame
    return ah ~= nil and ah:IsShown() and not Away(ah)
end

function ns.OnAuctionHouseMoved(fn)
    watchers[#watchers + 1] = fn
    Hook()
    if hooked or events then return end
    events = CreateFrame("Frame")
    events:SetScript("OnEvent", OnEvent)
    events:RegisterEvent("ADDON_LOADED")
end
