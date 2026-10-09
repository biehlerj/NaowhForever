-- When a live copy still blocks the hourly count, and when a group is a new visit.
-- From the repo root:
--   lua5.1 Tools/regression/test-instance-tracker-copies.lua
local function Read(path)
    local f = assert(io.open(path, "rb"))
    local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return source
end
local function Slice(source, a, b)
    local first = assert(source:find(a, 1, true), a)
    return source:sub(first, assert(source:find(b, first + #a, true), b) - 1)
end

local tracker = Read("NaowhForever_InstanceTracker/NaowhForever_InstanceTracker.lua")
local code = Slice(tracker, "local function CopyFresh(stored, now, hour)", "\n-- end copy memory")
    .. "\nreturn { Fresh = CopyFresh, Counts = CountsEntry, Differ = GroupsDiffer, Resume = CanResume }\n"
local chunk = assert(loadstring(code))
setfenv(chunk, setmetatable({}, { __index = _G }))
local Copy = chunk()

local count = 0
local function Case(name, fn)
    fn()
    count = count + 1
    print("PASS " .. name)
end

local HOUR = 3600
local NOW = 100000

local function Member(name)
    return { name = name, class = "MAGE" }
end

local groupA = { Member("Alice"), Member("Bob") }
local groupB = { Member("Cara"), Member("Dan") }

Case("a stamp inside the hour is the same copy", function()
    local stored = { name = "Deadmines", at = NOW - (HOUR - 1) }
    assert(Copy.Fresh(stored, NOW, HOUR))
    assert(not Copy.Counts(stored, NOW, HOUR, true))
    assert(Copy.Fresh({ name = "Deadmines", at = NOW }, NOW, HOUR))
end)

Case("an hour-old stamp counts again", function()
    local stored = { name = "Deadmines", at = NOW - HOUR }
    assert(not Copy.Fresh(stored, NOW, HOUR))
    assert(Copy.Counts(stored, NOW, HOUR, true))
    stored.at = NOW - 86400
    assert(Copy.Counts(stored, NOW, HOUR, true))
end)

Case("a login or reload does not count", function()
    local old = { name = "Deadmines", at = NOW - 86400 }
    local fresh = { name = "Deadmines", at = NOW - 10 }
    assert(not Copy.Counts(old, NOW, HOUR, false))
    assert(not Copy.Counts(fresh, NOW, HOUR, false))
    assert(not Copy.Counts(nil, NOW, HOUR, false))
end)

Case("a clock that moved backwards does not stick", function()
    local stored = { name = "Deadmines", at = NOW + HOUR }
    assert(not Copy.Fresh(stored, NOW, HOUR))
    assert(Copy.Counts(stored, NOW, HOUR, true))
end)

Case("one shared name keeps the visit", function()
    assert(not Copy.Differ(groupA, { Member("Bob"), Member("Eve") }, true))
    assert(not Copy.Differ(groupA, { Member("Alice") }, true))
end)

Case("two empty groups are the same solo copy", function()
    assert(not Copy.Differ(nil, {}, false))
    assert(not Copy.Differ({}, {}, false))
    assert(not Copy.Differ(nil, nil, false))
    assert(not Copy.Differ({ { name = "" } }, {}, false))
end)

Case("an empty roster while grouped does not split the visit", function()
    assert(not Copy.Differ(groupA, {}, true))
    assert(not Copy.Differ(groupA, nil, true))
end)

Case("a different group is a new visit", function()
    assert(Copy.Differ(groupA, groupB, true))
    assert(Copy.Differ(groupA, {}, false))
    assert(Copy.Differ({}, { Member("Cara") }, true))
    assert(Copy.Differ(nil, { Member("Cara") }, false))
end)

Case("a stamp and a leave inside the hour can resume", function()
    local stored = { name = "Deadmines", at = NOW - (HOUR - 1) }
    assert(Copy.Resume(stored, NOW - 60, NOW, HOUR))
    assert(not Copy.Counts(stored, NOW, HOUR, true))
end)

Case("an hour-old stamp or leave does not resume", function()
    local oldStamp = { name = "Deadmines", at = NOW - HOUR }
    assert(not Copy.Resume(oldStamp, NOW - 60, NOW, HOUR))
    assert(Copy.Counts(oldStamp, NOW, HOUR, true))
    local oldLeave = { name = "Deadmines", at = NOW - (HOUR + 60) }
    assert(not Copy.Resume(oldLeave, NOW - HOUR, NOW, HOUR))
    assert(Copy.Counts(oldLeave, NOW, HOUR, true))
end)

print(count .. " instance tracker copy regressions passed")
