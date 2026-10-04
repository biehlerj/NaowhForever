-------------------------------------------------------------------------------
--  NaowhForever_SavedInstances.lua -- the saved-instance countdown, read once.
--  GetSavedInstanceInfo counts down from the last UPDATE_INSTANCE_INFO, not from now.
--  This file is the only listener. The Top Bar and Instance Tracker read the list.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever

local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

-- "2h 30m", "5d 3h", "10m", or "expired". Shared so the clock tooltip does not
-- depend on Instance Tracker being loaded.
function ns.FormatRemaining(resetAt)
    local seconds = math.floor((tonumber(resetAt) or 0) - time())
    if seconds <= 0 then return "expired" end
    local days = math.floor(seconds / 86400)
    local hours = math.floor(seconds % 86400 / 3600)
    local minutes = math.floor(seconds % 3600 / 60)
    if days > 0 then return string.format("%dd %dh", days, hours) end
    if hours > 0 then return string.format("%dh %dm", hours, minutes) end
    return string.format("%dm", math.max(1, minutes))
end

-- The client's reset is a countdown from the last UPDATE_INSTANCE_INFO, not from now.
-- Only that event stamps the clock. A later refresh does not move it.
local savedReadAt, savedRaw

function ns.RefreshSavedInstances()
    savedRaw = {}
    if not GetNumSavedInstances or not GetSavedInstanceInfo then return end
    local count = GetNumSavedInstances()
    if Secret(count) or type(count) ~= "number" or count < 1 then return end
    for i = 1, count do
        local name, id, reset, _, locked, extended, _, isRaid, maxPlayers,
            difficultyName, encounters, progress = GetSavedInstanceInfo(i)
        if not Secret(name) and not Secret(reset) and not Secret(locked) and not Secret(extended)
            and type(name) == "string" and type(reset) == "number" and reset > 0
            and (locked or extended) then
            local lock = {
                name = name,
                reset = reset,
                locked = locked and true or false,
                extended = extended and true or false,
                isRaid = (not Secret(isRaid)) and isRaid and true or false,
                difficulty = (not Secret(difficultyName) and type(difficultyName) == "string")
                    and difficultyName or "",
            }
            if not Secret(id) and type(id) == "number" and id > 0 then lock.id = id end
            if not Secret(maxPlayers) and type(maxPlayers) == "number" then
                lock.maxPlayers = maxPlayers
            end
            if not Secret(encounters) and type(encounters) == "number" then
                lock.encounters = encounters
            end
            if not Secret(progress) and type(progress) == "number" then
                lock.progress = progress
            end
            savedRaw[#savedRaw + 1] = lock
        end
    end
end

-- Stamp the countdown only when the client has just refreshed instance info.
function ns.NoteInstanceInfo()
    savedReadAt = GetTime()
    ns.RefreshSavedInstances()
end

-- False until UPDATE_INSTANCE_INFO. Storing lockouts before that would replace a
-- saved countdown with an empty list.
function ns.SavedInstancesReady()
    return savedReadAt ~= nil
end

function ns.SavedInstances()
    if savedReadAt == nil or savedRaw == nil then return {} end
    local elapsed = GetTime() - savedReadAt
    local now, list = time(), {}
    for i = 1, #savedRaw do
        local src = savedRaw[i]
        local left = src.reset - elapsed
        if left > 0 then
            local lock = {}
            for key, value in pairs(src) do lock[key] = value end
            lock.left = left
            lock.resetAt = now + left
            list[#list + 1] = lock
        end
    end
    return list
end

local watch = CreateFrame("Frame")
watch:RegisterEvent("UPDATE_INSTANCE_INFO")
watch:SetScript("OnEvent", function()
    ns.NoteInstanceInfo()
end)
