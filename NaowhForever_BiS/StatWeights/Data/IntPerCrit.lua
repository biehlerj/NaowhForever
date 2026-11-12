-- IntPerCrit.lua: a healer class's Intellect per 1% spell crit, by level (ns.StatWeightIntPerCrit).
local ns = _G.NaowhForever

ns.StatWeightIntPerCrit = {
    PALADIN = { { 10, 16.3 }, { 30, 31.9 }, { 60, 59.9 } },
    PRIEST = { { 30, 26.9 }, { 60, 59.5 } },
    SHAMAN = { { 28, 26.3 }, { 30, 28.2 }, { 60, 59.2 } },
    DRUID = { { 30, 28.4 }, { 60, 59.9 } },
}
