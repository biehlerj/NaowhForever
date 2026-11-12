-- Defaults.lua: each spec's default stat weights (ns.StatWeightDefaults), from MythicSim's Forever sims.
local ns = _G.NaowhForever

local NONE = {}
local MELEE = { sta = 0.1, armor = 0.005 }
local CASTER = { spell = 1, sta = 0.05, armor = 0.005 }
local HEALER = { heal = 1, sta = 0.05, armor = 0.005 }
local TANK = { sta = 1, def = 1.5, armor = 0.06, dodge = 10, threat = 6 }

local function Spec(class, key, name, role, own)
    local weights = {}
    for stat, worth in pairs(role) do weights[stat] = worth end
    for stat, worth in pairs(own or NONE) do weights[stat] = worth end
    return { class = class, key = key, name = name, weights = weights, healer = role == HEALER }
end

ns.StatWeightDefaultsUpdated = "12 Nov 2026"

ns.StatWeightDefaults = {
    Spec("DRUID", "balance-druid", "Balance", CASTER, { int = 0.28, nature = 0.36, arcane = 0.64, mp5 = 0.14,
        shit = 11.2, scrit = 9.4, haste = 8.4 }),
    Spec("DRUID", "feral-dps-druid", "Feral DPS", MELEE, { str = 0.89, agi = 1, ap = 0.36, dps = 8.6, hit = 6.9,
        crit = 10.9, haste = 5.5, exp = 6.7, arp = 0.12 }),
    Spec("DRUID", "feral-tank-druid", "Feral Tank", TANK, { str = 1.08, agi = 0.7, ap = 0.49, dps = 10.2, hit = 18.4,
        crit = 12.5, haste = 4.8, exp = 36.9, arp = 0.2, def = 1.2, dodge = 12, armor = 0.12, threat = 5 }),
    Spec("DRUID", "restoration-druid", "Restoration", HEALER, { int = 0.45, spi = 0.5, mp5 = 1.8, scrit = 3,
        haste = 6 }),
    Spec("HUNTER", "beast-mastery-hunter", "Beast Mastery", MELEE, { str = 0.1, agi = 1, int = 0.59, spi = 0.05,
        ap = 0.09, rap = 0.29, dps = 3.1, mp5 = 0.26, hit = 14.1, crit = 12.7, haste = 4, exp = 7.3, arp = 0.13 }),
    Spec("HUNTER", "marksmanship-hunter", "Marksmanship", MELEE, { str = 0.11, agi = 1, int = 0.58, spi = 0.05,
        ap = 0.1, rap = 0.3, dps = 3.6, mp5 = 0.21, hit = 11.1, crit = 11.8, haste = 3.8, exp = 3.1, arp = 0.13 }),
    Spec("HUNTER", "survival-hunter", "Survival", MELEE, { str = 0.17, agi = 1, int = 0.67, ap = 0.16, rap = 0.2,
        dps = 3.2, mp5 = 0.39, hit = 10.5, crit = 10.8, haste = 4.1, exp = 6.2, arp = 0.13 }),
    Spec("MAGE", "arcane-mage", "Arcane", CASTER, { int = 0.99, spi = 0.27, fire = 0.44, arcane = 0.56, mp5 = 0.43,
        shit = 17.9, scrit = 11.2, haste = 6.6 }),
    Spec("MAGE", "fire-mage", "Fire", CASTER, { int = 0.47, spi = 0.11, fire = 0.88, arcane = 0.12, mp5 = 0.25,
        shit = 15.3, scrit = 10.6 }),
    Spec("MAGE", "frost-mage", "Frost", CASTER, { int = 0.18, spi = 0.01, frost = 0.85, arcane = 0.15, mp5 = 0.02,
        shit = 16.4, scrit = 9.1, haste = 10.9 }),
    Spec("PALADIN", "holy-paladin", "Holy", HEALER, { int = 0.6, spi = 0.1, mp5 = 2, scrit = 6, haste = 5 }),
    Spec("PALADIN", "protection-paladin", "Protection", TANK, { str = 0.45, agi = 0.51, int = 0.03, ap = 0.19,
        dps = 3, spell = 1.13, holy = 0.45, mp5 = 0.6, hit = 3, shit = 5.9, crit = 10.3, scrit = 1.1, haste = 4.6,
        exp = 25.5, arp = 0.04, block = 6 }),
    Spec("PALADIN", "retribution-paladin", "Retribution", MELEE, { str = 1, agi = 1.36, int = 1.6, ap = 0.41, dps = 8,
        spell = 2.11, holy = 0.25, mp5 = 0.3, hit = 12, shit = 2, crit = 24.2, haste = 14.8, exp = 28.6, arp = 0.1 }),
    Spec("PRIEST", "discipline-priest", "Discipline", HEALER, { spell = 0.15, int = 0.55, spi = 0.4, mp5 = 2,
        scrit = 4, haste = 5 }),
    Spec("PRIEST", "holy-priest", "Holy", HEALER, { int = 0.5, spi = 0.55, mp5 = 2, scrit = 4, haste = 5 }),
    Spec("PRIEST", "shadow-priest", "Shadow", CASTER, { int = 0.26, shadow = 1, shit = 11.9, scrit = 12.7,
        haste = 6.5 }),
    Spec("ROGUE", "assassination-rogue", "Assassination", MELEE, { str = 0.54, agi = 1, ap = 0.49, dps = 7.5,
        hit = 9.3, crit = 12.5, haste = 6.6, exp = 14.6, arp = 0.2 }),
    Spec("ROGUE", "combat-rogue", "Combat", MELEE, { str = 0.61, agi = 1, ap = 0.55, dps = 7.2, hit = 12.6,
        crit = 10.4, haste = 8.8, exp = 15.5, arp = 0.19 }),
    Spec("ROGUE", "subtlety-rogue", "Subtlety", MELEE, { str = 0.57, agi = 1, ap = 0.52, dps = 5.3, hit = 11.1,
        crit = 11.2, haste = 8, exp = 13.3, arp = 0.13 }),
    Spec("SHAMAN", "elemental-shaman", "Elemental", CASTER, { int = 0.19, spi = 0.1, fire = 0.25, frost = 0.1,
        nature = 0.88, shit = 13.2, scrit = 9.7, haste = 9.6 }),
    Spec("SHAMAN", "enhancement-shaman", "Enhancement", MELEE, { str = 1, agi = 0.65, int = 0.89, ap = 0.45, dps = 8,
        spell = 0.62, nature = 0.29, mp5 = 0.3, hit = 13, shit = 9.5, crit = 11.7, scrit = 5.2, haste = 9.8,
        exp = 18.5, arp = 0.16 }),
    Spec("SHAMAN", "restoration-shaman", "Restoration", HEALER, { int = 0.55, spi = 0.25, mp5 = 2.2, scrit = 4,
        haste = 5 }),
    Spec("WARLOCK", "affliction-warlock", "Affliction", CASTER, { sta = 0.1, int = 0.17, spi = 0.3, shadow = 1,
        shit = 5.2, scrit = 9.7, haste = 2.2 }),
    Spec("WARLOCK", "demonology-warlock", "Demonology", CASTER, { sta = 0.1, int = 0.45, spi = 0.3, shadow = 0.79,
        fire = 0.18, mp5 = 0.28, shit = 12.9, scrit = 10.8, haste = 8.7 }),
    Spec("WARLOCK", "destruction-warlock", "Destruction", CASTER, { sta = 0.1, int = 0.5, spi = 0.3, shadow = 0.77,
        fire = 0.21, mp5 = 0.3, shit = 11.4, scrit = 11.8, haste = 7.9 }),
    Spec("WARRIOR", "arms-warrior", "Arms", MELEE, { str = 1, agi = 0.84, ap = 0.45, dps = 8, hit = 11.2, crit = 15.1,
        haste = 8.3, exp = 10.4, arp = 0.2 }),
    Spec("WARRIOR", "fury-warrior", "Fury", MELEE, { str = 1, agi = 0.8, ap = 0.45, dps = 7.5, hit = 13.3,
        crit = 14.3, haste = 8.7, exp = 15.3, arp = 0.19 }),
    Spec("WARRIOR", "protection-warrior", "Protection", TANK, { str = 0.65, agi = 0.34, ap = 0.29, dps = 4, hit = 8,
        crit = 7, haste = 4.2, exp = 27.2, arp = 0.12, bv = 0.36, block = 4 }),
}
