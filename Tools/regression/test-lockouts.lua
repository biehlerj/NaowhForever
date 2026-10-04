local function Read(path)
    local f = assert(io.open(path, "rb"))
    local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return source
end
local function Slice(source, a, b)
    local first = assert(source:find(a, 1, true), a)
    return source:sub(first, assert(source:find(b, first + #a, true), b) - 1)
end

local tracker = Read(arg[1] or "InstanceTracker/NaowhForever_InstanceTracker.lua")
local top = Read(arg[2] or "TopBar/NaowhForever_TopBar.lua")

-- The countdown lives in the tracker. The clock only names and sorts what that read returns.
local preamble = "local function Secret(v)\n    return issecretvalue and issecretvalue(v)\nend\n"
local code = preamble
    .. Slice(tracker, "local function FormatRemaining(resetAt)", "\nlocal function PlainCoins(")
    .. "\nns.InstanceTracker = { Remaining = FormatRemaining }\n"
    .. Slice(tracker, "local savedReadAt, savedRaw", "\nlocal function ReadLockouts")
    .. "\n" .. Slice(top, "local function Lockouts()", "\nfunction ns.LockoutsCommand")
    .. "\nreturn Lockouts\n"

-- Saved instances as GetSavedInstanceInfo returns them: name, reset, locked, extended, total, done.
local function Fixture(saved, now, updatedAt)
    local clock = updatedAt
    local env = {
        ns = { Shared = { Parts = { Fraction = function(part, whole)
            return part .. "/" .. whole
        end } } },
        GetTime = function() return clock end,
        time = function() return 0 end,
        GetNumSavedInstances = function() return #saved end,
        GetSavedInstanceInfo = function(i)
            local s = saved[i]
            return s[1], 1, s[2], 1, s[3], s[4], 0, false, 5, "Normal", s[5], s[6]
        end,
    }
    setmetatable(env, { __index = _G })
    local chunk = assert(loadstring(code)); setfenv(chunk, env)
    local Lockouts = chunk()
    env.ns.RefreshSavedInstances()
    clock = now
    return Lockouts()
end
local function Lines(list)
    local out = {}
    for _, l in ipairs(list) do out[#out + 1] = l.name .. " in " .. l.reset end
    return table.concat(out, "; ")
end
local count = 0
local function Case(name, fn) fn(); count = count + 1; print("PASS " .. name) end

Case("soonest reset first, with boss progress", function()
    local list = Fixture({
        { "Molten Core", 5 * 86400 + 3 * 3600, true, false, 10, 4 },
        { "Zul'Gurub", 2 * 3600 + 30 * 60, true, false, 10, 10 },
    }, 100, 100)
    assert(Lines(list) == "Zul'Gurub 10/10 in 2h 30m; Molten Core 4/10 in 5d 3h", Lines(list))
end)
Case("the reset counts down from the last update", function()
    local list = Fixture({ { "Onyxia's Lair", 3 * 3600, true, false, 1, 1 } }, 100 + 3600, 100)
    assert(Lines(list) == "Onyxia's Lair 1/1 in 2h 0m", Lines(list))
end)
Case("expired and unlocked instances are left out; extended ones stay", function()
    local list = Fixture({
        { "Old", 60, true, false, 0, 0 },
        { "Released", 86400, false, false, 0, 0 },
        { "Extended", 86400, false, true, 0, 0 },
    }, 500, 0)
    assert(Lines(list) == "Extended in 23h 51m", Lines(list))
end)
Case("an instance without boss counts shows just its name", function()
    local list = Fixture({ { "Dire Maul", 600, true, false, 0, 0 } }, 0, 0)
    assert(Lines(list) == "Dire Maul in 10m", Lines(list))
end)
print(count .. " lockout regressions passed")
