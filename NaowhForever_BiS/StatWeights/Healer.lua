-- Healer.lua: Healer Mana, a healer's Intellect and Spirit worked out from your own mana (SW.Healer).
local ns = _G.NaowhForever

local SW = ns.StatWeights
local S = SW.Settings

local PER_FIVE = 5
local REGEN_KNEE, REGEN_LOW, REGEN_HIGH = 50, 0.25, 0.125
local DERIVED = { int = true, spi = true }
local EVENTS = { "PLAYER_LEVEL_UP", "PLAYER_EQUIPMENT_CHANGED", "TRAIT_CONFIG_UPDATED" }
local SETTINGS = { healerMana = true, fightLength = true }

local derived = {}
local spiritMp5, critPerInt
local read = false
local events

local function IntPerCrit(class, level)
    local steps = ns.StatWeightIntPerCrit[class]
    if not steps then return nil end
    local below, above
    for _, step in ipairs(steps) do
        if step[1] <= level then below = step end
        if step[1] >= level and not above then above = step end
    end
    if not below then return above[2] end
    if not above or above == below then return below[2] end
    return below[2] + (above[2] - below[2]) * (level - below[1]) / (above[1] - below[1])
end

local function Read()
    if C_Secrets.ShouldUnitStatsBeSecret() then return end
    local _, spirit = UnitStat("player", LE_UNIT_STAT_SPIRIT)
    local base, casting = GetManaRegenFromSpirit()
    local share = base > 0 and casting / base or 0
    spiritMp5 = PER_FIVE * (spirit < REGEN_KNEE and REGEN_LOW or REGEN_HIGH) * share
    local perCrit = IntPerCrit(select(2, UnitClass("player")), UnitLevel("player"))
    critPerInt = perCrit and 1 / perCrit or 0
    read = true
end

local function Stale()
    read = false
    wipe(derived)
    SW.Notify()
end

local function Forget()
    wipe(derived)
end

local function Apply()
    local on = S.Get("healerMana") == true
    if on and not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", Stale)
    end
    if not events then return end
    if on then
        events:RegisterUnitEvent("UNIT_STATS", "player")
        for _, event in ipairs(EVENTS) do events:RegisterEvent(event) end
    else
        events:UnregisterAllEvents()
    end
end

local function OnSetting(key)
    if not SETTINGS[key] then return end
    Apply()
    Stale()
end

function SW.Healer(key, weights)
    local mine = derived[key]
    if mine then return mine end
    if not read then Read() end
    if not spiritMp5 then return weights end
    mine = {}
    for stat, worth in pairs(weights) do mine[stat] = worth end
    local mp5 = weights.mp5 or 0
    if not SW.Changed(key, "int") then
        mine.int = mp5 * PER_FIVE * MANA_PER_INTELLECT / S.Get("fightLength") + (weights.scrit or 0) * critPerInt
    end
    if not SW.Changed(key, "spi") then mine.spi = mp5 * spiritMp5 end
    derived[key] = mine
    return mine
end

function SW.Derived(key, stat)
    return DERIVED[stat] == true and SW.HealerOn(key) and not SW.Changed(key, stat)
end

SW.OnChange(Forget)
S.OnChange(OnSetting)
hooksecurefunc(ns, "Apply", Apply)
