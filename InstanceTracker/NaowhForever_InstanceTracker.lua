-------------------------------------------------------------------------------
--  NaowhForever_InstanceTracker.lua -- saved lockouts for each character on this
--  account, a record of each dungeon or raid visit, and how many new instances this
--  character has entered in the last hour. Coming back to the same group in a copy
--  this character has not reset continues that visit, and the time outside is not
--  counted. A different group starts a new visit. Who else was in the group is kept
--  on that visit. With Track Alts on, every character you log
--  into keeps that hour, its saved instances, and a snapshot of rest and durability.
--
--  Off until the module is enabled. The display frame is built the first time the run
--  timer is allowed on screen. Coin amounts come from loot messages (the client's own
--  GOLD_AMOUNT phrases), not from a combat log, which Forever does not give to addons.
--  Lockouts and visits are account data, so a profile switch does not wipe them.
--  A character is stored under the full name, first and surname. UnitName is only the
--  first name on Forever, so two alts who share it would otherwise be one record.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI
local T = ns.THEME

local S = UI.ModuleSettings("instanceTracker", {
    enabled = false,
    showFrame = false,
    enterChat = false,
    leaveChat = false,
    leaveWhere = "self",
    leaveTime = false,
    leaveXP = false,
    leaveXPHour = false,
    leaveGold = false,
    leaveDeaths = false,
    leaveRep = false,
    leaveAverage = false,
    leaveRunsLevel = false,
    leaveRunsToLevel = false,
    -- Skip the leave summary when the visit gained nothing.
    leaveActivity = false,
    -- Dungeons only until this is on. Raid chat is a separate choice.
    leaveRaids = false,
    leavePrintRaid = false,
    -- Other characters' lockouts, visits and the snapshot. Each has their own 10 per hour.
    trackAlts = false,
    -- How many entries short of this character's 10-per-hour cap to warn. 1 warns at 9 of 10.
    hourlyWarn = 1,
})
ns.InstanceTrackerSettings = S

local MAX_RUNS = 80
local AWAY_CAP = 86400 * 14
local HOUR = 3600
local HOURLY_CAP = 10

-- Run timer. Sizes are pixels at the addon's UI scale.
local FRAME_W, FRAME_H = 280, 100
local PAD_X = 10             -- text from the left and right edges
local TITLE_TOP = 8          -- title below the frame's top
local TIME_GAP = 2           -- between the title and the clock
local LINE_GAP = 1           -- between the clock, loot, xp and hour lines
local TITLE_SIZE = 13
local TIME_SIZE = 16
local BODY_SIZE = 12         -- the loot, xp and hour lines
local DEFAULT_Y = -180       -- where the frame first sits, under the top of the screen
local COIN_ICON = 12         -- the coin textures beside a loot amount
local FRAME_ALPHA = 0.9

-- At the hourly cap the line is red; inside the warn distance it is amber.
-- Not theme tokens (same hues as LIMITED and NOT POSSIBLE YET). The lockouts page
-- reads these same tables from ns.InstanceTracker.
local CAP_RGB = { r = 1, g = 0x60 / 255, b = 0x60 / 255 }
local WARN_RGB = { r = 1, g = 0xa3 / 255, b = 0 }

local frame, clock, unlocked
local goldPattern, silverPattern, copperPattern, repPattern
local events

local UpdateFrame, CloseRun, BeginRun, PruneAlts

local function On()
    return S.Get("enabled")
end

local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

local function RawStore()
    local store = ns.AccountSettings().instanceTracker
    if type(store) ~= "table" then return nil end
    return store
end

local function EnsureStore()
    local account = ns.AccountSettings()
    local store = account.instanceTracker
    if type(store) ~= "table" then
        store = { chars = {}, runs = {} }
        account.instanceTracker = store
    end
    if type(store.chars) ~= "table" then store.chars = {} end
    if type(store.runs) ~= "table" then store.runs = {} end
    return store
end

local function OpenRun()
    local store = RawStore()
    local open = store and store.open
    if type(open) ~= "table" then return nil end
    return open
end

local function RealmKey()
    local realm = GetRealmName()
    if not realm or Secret(realm) then realm = "" end
    local faction = UnitFactionGroup("player")
    if not faction or Secret(faction) then faction = "" end
    return realm .. "-" .. faction
end

-- UnitName, and a "Name-Realm" glued into one string, both stop at the hyphen.
local function BareName(name)
    if Secret(name) or type(name) ~= "string" or name == "" or name == UNKNOWNOBJECT then
        return ""
    end
    return name:match("^[^-]+") or name
end

-- UnitName is the first name ("Glyadin"). Older rows were filed under that.
local function FirstName()
    return BareName(UnitName("player"))
end

-- UnitFullName is the whole name ("Glyadin Skywolf"). A realm glued on the end is stripped.
local function FullName()
    return BareName(UnitFullName("player"))
end

local function PlayerClass()
    local _, class = UnitClass("player")
    if Secret(class) or type(class) ~= "string" or class == "" then return nil end
    return class
end

local function RealmAgrees(stored, realm)
    if type(stored) ~= "string" or stored == "" then return true end
    return stored == realm
end

-- A row with no class stored can be this character. A row with a class needs a match,
-- and a class the game will not show yet is left for a later login read.
local function ClassAgrees(stored, class)
    if type(stored) ~= "string" or stored == "" then return true end
    if not class then return false end
    return stored == class
end

local function HasClass(stored)
    return type(stored) == "string" and stored ~= ""
end

-- Move this character's first-name rows onto the full name. Another alt who only
-- shares the first name keeps a row whose class is not this one. True when the
-- move is finished; false when a class still has to be read before it is safe.
local function ClaimFirstName(store, full, first)
    if first == "" or first == full then return true end
    local realm, class = RealmKey(), PlayerClass()
    local group = type(store.chars) == "table" and store.chars[realm] or nil
    local old = type(group) == "table" and group[first] or nil
    local open = store.open
    -- A classed row cannot be told from the other alt's until this class is known.
    if not class then
        if type(old) == "table" and HasClass(old.class) then return false end
        if type(store.runs) == "table" then
            for i = 1, #store.runs do
                local row = store.runs[i]
                if type(row) == "table" and row.char == first and RealmAgrees(row.realm, realm)
                    and HasClass(row.class) then
                    return false
                end
            end
        end
        if type(open) == "table" and open.char == first and RealmAgrees(open.realm, realm)
            and HasClass(open.class) then
            return false
        end
    end

    local sheetAgrees = type(old) ~= "table" or ClassAgrees(old.class, class)
    if type(old) == "table" and sheetAgrees and type(group[full]) ~= "table" then
        group[full] = old
        group[first] = nil
    end

    local function Take(row, field)
        if type(row) ~= "table" or row[field] ~= first or not RealmAgrees(row.realm, realm) then
            return
        end
        local stored = row.class
        local hasClass = type(stored) == "string" and stored ~= ""
        if hasClass then
            if stored ~= class then return end
        elseif not sheetAgrees then
            return
        end
        row[field] = full
        if type(row.realm) ~= "string" or row.realm == "" then row.realm = realm end
    end
    if type(store.runs) == "table" then
        for i = 1, #store.runs do Take(store.runs[i], "char") end
    end
    Take(open, "char")

    if sheetAgrees then
        if type(store.hour) == "table" then
            for i = 1, #store.hour do
                local row = store.hour[i]
                if type(row) == "table" and row.who == first and RealmAgrees(row.realm, realm) then
                    row.who = full
                    if type(row.realm) ~= "string" or row.realm == "" then row.realm = realm end
                end
            end
        end
        local live = type(store.live) == "table" and store.live[realm] or nil
        if type(live) == "table" and type(live[first]) == "table" and type(live[full]) ~= "table" then
            live[full] = live[first]
            live[first] = nil
        end
        local noted = store.hourNoted
        if type(noted) == "table" then
            local oldKey, newKey = realm .. "\031" .. first, realm .. "\031" .. full
            if noted[oldKey] ~= nil and noted[newKey] == nil then
                noted[newKey] = noted[oldKey]
                noted[oldKey] = nil
            end
        end
    end
    return true
end

-- Forever names carry a surname: UnitName is "Glyadin", UnitFullName is "Glyadin Skywolf".
-- Until the old first-name rows have been moved, this stays the first name, so a new
-- row is not opened beside them.
local namedFull
local function CharName()
    local full, first = FullName(), FirstName()
    if full == "" then return first end
    if not namedFull then
        local store = RawStore()
        if not store or ClaimFirstName(store, full, first) then namedFull = true end
    end
    if not namedFull then return first end
    return full
end

local function WholeNumber(v)
    if Secret(v) or type(v) ~= "number" then return nil end
    return v
end

-- Equipped pieces that have durability, as one percentage. A secret read keeps the old one.
local function DurabilityPct()
    if not GetInventoryItemDurability then return nil end
    local first = INVSLOT_FIRST_EQUIPPED or 1
    local last = INVSLOT_LAST_EQUIPPED or 19
    local current, full = 0, 0
    for slot = first, last do
        local cur, max = GetInventoryItemDurability(slot)
        if Secret(cur) or Secret(max) then return nil end
        if type(cur) == "number" and type(max) == "number" and max > 0 then
            current, full = current + cur, full + max
        end
    end
    if full <= 0 then return nil end
    return math.floor(current / full * 100 + 0.5)
end

-- Rest and durability from this login. A failed read leaves the previous number in
-- place, so a secret combat value does not wipe the sheet. Gold stays with Mail & Alts.
local function SnapshotChar(row)
    local level = WholeNumber(UnitLevel("player"))
    if level then row.level = level end
    local _, class = UnitClass("player")
    if not Secret(class) and type(class) == "string" then row.class = class end
    local xp = WholeNumber(UnitXP("player"))
    if xp then row.xp = xp end
    local xpMax = WholeNumber(UnitXPMax("player"))
    if xpMax then row.xpMax = xpMax end
    if GetXPExhaustion then
        local rested = GetXPExhaustion()
        if not Secret(rested) then
            row.rested = type(rested) == "number" and rested or 0
        end
    end
    local durability = DurabilityPct()
    if durability ~= nil then row.durability = durability end
    row.seen = time()
end

-- The character row lockouts and the sheet hang off.
local function TouchChar()
    local name = CharName()
    if name == "" then return end
    local store = EnsureStore()
    local realm = RealmKey()
    store.chars[realm] = store.chars[realm] or {}
    local row = store.chars[realm][name]
    if not row then
        row = { lockouts = {} }
        store.chars[realm][name] = row
    end
    SnapshotChar(row)
    PruneAlts()
    return row, realm, name
end

-- Off keeps the character you are playing. The hourly list is left alone: each
-- character's 10 is their own, and it still has to be there the next time you log them in.
-- This login cannot gain another character's rows while Track Alts stays off, so a
-- finished prune for this realm and name is not repeated on experience or durability.
local prunedRealm, prunedName
PruneAlts = function()
    if S.Get("trackAlts") then
        prunedRealm, prunedName = nil, nil
        return
    end
    local store = RawStore()
    if not store then return end
    local realm, name = RealmKey(), CharName()
    if name == "" then return end
    if prunedRealm == realm and prunedName == name then return end
    if type(store.chars) == "table" then
        for key, group in pairs(store.chars) do
            if key ~= realm then
                store.chars[key] = nil
            elseif type(group) == "table" then
                for char in pairs(group) do
                    if char ~= name then group[char] = nil end
                end
            end
        end
    end
    local runs = store.runs
    if type(runs) == "table" then
        local foreign
        for i = 1, #runs do
            local run = runs[i]
            if run.realm ~= realm or run.char ~= name then
                foreign = true
                break
            end
        end
        if foreign then
            local write = 1
            for i = 1, #runs do
                local run = runs[i]
                if run.realm == realm and run.char == name then
                    runs[write] = run
                    write = write + 1
                end
            end
            for i = #runs, write, -1 do runs[i] = nil end
        end
    end
    prunedRealm, prunedName = realm, name
end

local function FormatDuration(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    if seconds < 0 then seconds = 0 end
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor(seconds % 3600 / 60)
    local secs = seconds % 60
    if hours > 0 then return string.format("%d:%02d:%02d", hours, minutes, secs) end
    return string.format("%d:%02d", minutes, secs)
end

-- Time inside the visit. skipped is the gap while logged out, reloading, or outside
-- this copy, so a resumed visit does not count the time spent away.
local function Elapsed(open, now)
    now = now or time()
    local elapsed = now - (tonumber(open.entered) or now) - (tonumber(open.skipped) or 0)
    if elapsed < 0 then return 0 end
    return elapsed
end

local function FormatRemaining(resetAt)
    local seconds = math.floor((tonumber(resetAt) or 0) - time())
    if seconds <= 0 then return "expired" end
    local days = math.floor(seconds / 86400)
    local hours = math.floor(seconds % 86400 / 3600)
    local minutes = math.floor(seconds % 3600 / 60)
    if days > 0 then return string.format("%dd %dh", days, hours) end
    if hours > 0 then return string.format("%dh %dm", hours, minutes) end
    return string.format("%dm", math.max(1, minutes))
end

-- Plain coins for a line sent to the group. Textures from the coin API are for this client.
local function PlainCoins(copper)
    copper = math.floor(tonumber(copper) or 0)
    if copper < 0 then copper = 0 end
    return string.format("%dg %ds %dc", math.floor(copper / 10000),
        math.floor(copper / 100) % 100, copper % 100)
end

local function Coins(copper)
    copper = math.floor(tonumber(copper) or 0)
    if copper < 0 then copper = 0 end
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        return C_CurrencyInfo.GetCoinTextureString(copper, COIN_ICON)
    end
    return PlainCoins(copper)
end

-- "%d Gold" and the silver and copper phrases, so a loot line can be summed in any locale.
local function CoinPattern(phrase)
    return phrase:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%d", "(%%d+)")
end

local function LootedCopper(text)
    if type(text) ~= "string" or Secret(text) then return 0 end
    if not goldPattern then
        if type(GOLD_AMOUNT) ~= "string" or type(SILVER_AMOUNT) ~= "string"
            or type(COPPER_AMOUNT) ~= "string" then
            return 0
        end
        goldPattern = CoinPattern(GOLD_AMOUNT)
        silverPattern = CoinPattern(SILVER_AMOUNT)
        copperPattern = CoinPattern(COPPER_AMOUNT)
    end
    return (tonumber(text:match(goldPattern)) or 0) * 10000
        + (tonumber(text:match(silverPattern)) or 0) * 100
        + (tonumber(text:match(copperPattern)) or 0)
end

local function CurrentInstance()
    local inInstance, kind = IsInInstance()
    if Secret(inInstance) or Secret(kind) then return nil, "secret" end
    if not inInstance or (kind ~= "party" and kind ~= "raid") then return nil, "out" end
    local name, _, _, difficultyName, _, _, _, mapID = GetInstanceInfo()
    if Secret(name) or Secret(difficultyName) or Secret(mapID) then return nil, "secret" end
    if type(name) ~= "string" or name == "" then return nil, "out" end
    if type(difficultyName) ~= "string" then difficultyName = "" end
    if type(mapID) ~= "number" then mapID = 0 end
    return name, "in", kind, difficultyName, mapID
end

local function SamePlace(open, name, mapID, difficulty)
    if open.char ~= CharName() or open.realm ~= RealmKey() then return false end
    if open.instance ~= name or (open.difficulty or "") ~= difficulty then return false end
    local saved = open.mapID or 0
    return saved == 0 or mapID == 0 or saved == mapID
end

local function LastRun(realm, char, instance)
    local store = RawStore()
    if not store or type(store.runs) ~= "table" then return end
    for i = 1, #store.runs do
        local run = store.runs[i]
        if run.realm == realm and run.char == char and run.instance == instance then
            return run
        end
    end
end

local function MatchingLockout(instance)
    local store = RawStore()
    local group = store and store.chars and store.chars[RealmKey()]
    local row = group and group[CharName()]
    if not row or type(row.lockouts) ~= "table" then return end
    local now = time()
    for i = 1, #row.lockouts do
        local lock = row.lockouts[i]
        if lock.name == instance and lock.resetAt and lock.resetAt > now then
            return lock
        end
    end
end

-- The client's reset is a countdown from the last time this was read, not from now.
-- The clock tooltip and this module both read the list from here.
local savedReadAt, savedRaw

function ns.RefreshSavedInstances()
    savedReadAt = GetTime()
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

function ns.SavedInstances()
    if savedReadAt == nil then ns.RefreshSavedInstances() end
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

local function ReadLockouts()
    ns.RefreshSavedInstances()
    local list = {}
    for _, lock in ipairs(ns.SavedInstances()) do
        if lock.locked then
            lock.reset, lock.left = nil, nil
            list[#list + 1] = lock
        end
    end
    return list
end

local function SaveLockouts()
    if not On() then return end
    local row = TouchChar()
    if not row then return end
    row.lockouts = ReadLockouts()
    row.updated = time()
    local open = OpenRun()
    if open and open.wantSave and not open.toldSave and S.Get("enterChat") then
        local lock = MatchingLockout(open.instance)
        if lock then
            open.toldSave = true
            ns.Print(ns.L("Saved to %s. Resets in %s.", open.instance, FormatRemaining(lock.resetAt)))
        end
    end
    UI:RefreshPage(true)
end

-- Experience and level stay registered while the module is on, so the alt sheet
-- keeps up outside a dungeon. These only matter during a visit.
local RUN_EVENTS = {
    "CHAT_MSG_MONEY", "CHAT_MSG_COMBAT_FACTION_CHANGE", "PLAYER_DEAD",
    "GROUP_ROSTER_UPDATE",
}

local function SetRunEvents(active)
    for i = 1, #RUN_EVENTS do
        if active then events:RegisterEvent(RUN_EVENTS[i])
        else events:UnregisterEvent(RUN_EVENTS[i]) end
    end
end

-- Baseline on enter; later calls add the gain, including the bar that a level-up clears.
local function NoteXP(baseline)
    local open = OpenRun()
    if not open then return end
    local xp, maxXP = UnitXP("player"), UnitXPMax("player")
    if Secret(xp) or Secret(maxXP) or type(xp) ~= "number" then return end
    if type(maxXP) ~= "number" then maxXP = 0 end
    if baseline or not open.lastXP then
        open.lastXP, open.lastMax = xp, maxXP
        return
    end
    if xp >= open.lastXP then
        open.xp = (open.xp or 0) + (xp - open.lastXP)
    else
        local span = (open.lastMax or 0) - open.lastXP
        if span < 0 then span = 0 end
        open.xp = (open.xp or 0) + span + xp
    end
    open.lastXP, open.lastMax = xp, maxXP
end

local function AddLoot(text)
    local open = OpenRun()
    if not open then return end
    local copper = LootedCopper(text)
    if copper <= 0 then return end
    open.loot = (open.loot or 0) + copper
    UpdateFrame()
end

-- "Reputation with %s increased by %d." Recorded while a visit is open; printed only
-- when that line is turned on.
local function NoteRep(text)
    local open = OpenRun()
    if not open or type(text) ~= "string" or Secret(text) then return end
    if not repPattern then
        if type(FACTION_STANDING_INCREASED) ~= "string" then return end
        repPattern = "^" .. FACTION_STANDING_INCREASED:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
            :gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)") .. "$"
    end
    local faction, amount = text:match(repPattern)
    amount = tonumber(amount)
    if not faction or not amount or amount <= 0 then return end
    if type(open.rep) ~= "table" then open.rep = {} end
    open.rep[faction] = (open.rep[faction] or 0) + amount
end

local function Where(open)
    local name = open.instance or ""
    if open.difficulty and open.difficulty ~= "" then
        return name .. " (" .. open.difficulty .. ")"
    end
    return name
end

local function AnnounceResume(open)
    if not S.Get("enterChat") or not open.instance then return end
    ns.Print(ns.L("Resumed %s.", Where(open)))
end

local function AnnounceEnter(open)
    if not S.Get("enterChat") or not open.instance then return end
    ns.Print(ns.L("Entered %s.", Where(open)))
    local last = LastRun(open.realm, open.char, open.instance)
    if last and last.left and last.entered then
        ns.Print(ns.L("Last visit: %s, looted %s.",
            FormatDuration(last.left - last.entered), Coins(last.loot)))
    end
    local lock = MatchingLockout(open.instance)
    if lock then
        open.toldSave = true
        ns.Print(ns.L("Saved to %s. Resets in %s.", open.instance, FormatRemaining(lock.resetAt)))
    end
end

local function VisitActive(open)
    if (open.xp or 0) > 0 or (open.loot or 0) > 0 or (open.deaths or 0) > 0 then
        return true
    end
    if type(open.rep) ~= "table" then return false end
    for _, amount in pairs(open.rep) do
        if (amount or 0) > 0 then return true end
    end
    return false
end

local function RepText(open)
    if type(open.rep) ~= "table" then return end
    local parts = {}
    for faction, amount in pairs(open.rep) do
        if type(faction) == "string" and (amount or 0) > 0 then
            parts[#parts + 1] = faction .. " +" .. BreakUpLargeNumbers(amount)
        end
    end
    if #parts == 0 then return end
    table.sort(parts)
    return table.concat(parts, ", ")
end

local function RunsFor(open, instanceOnly)
    local store = RawStore()
    local list = {}
    if not store or type(store.runs) ~= "table" then return list end
    for i = 1, #store.runs do
        local run = store.runs[i]
        if run.realm == open.realm and run.char == open.char then
            if not instanceOnly or run.instance == open.instance then
                list[#list + 1] = run
            end
        end
    end
    return list
end

local function GroupChannel()
    if IsInRaid then
        local raid = IsInRaid()
        if not Secret(raid) and raid then
            if S.Get("leavePrintRaid") then return "RAID" end
            return nil
        end
    end
    if IsInGroup then
        local group = IsInGroup()
        if not Secret(group) and group then return "PARTY" end
    end
end

-- One chat message. Longer summaries become a second complete message, split between
-- facts, rather than cut in the middle of one.
local CHAT_LIMIT = 255

local function LeaveFacts(open, span, plain)
    local facts = {}
    local function add(text) facts[#facts + 1] = text end
    if S.Get("leaveTime") then add(FormatDuration(span)) end
    if S.Get("leaveXP") then
        add(ns.L("%s XP", BreakUpLargeNumbers(open.xp or 0)))
    end
    if S.Get("leaveXPHour") then
        local elapsed = span or 0
        if elapsed < 0 then elapsed = 0 end
        local rate = (open.xp or 0) / (math.max(elapsed, 60) / 3600)
        add(ns.L("%s XP/hr", BreakUpLargeNumbers(math.floor(rate + 0.5))))
    end
    if S.Get("leaveGold") then
        add(plain and PlainCoins(open.loot) or Coins(open.loot))
    end
    if S.Get("leaveDeaths") then
        local n = open.deaths or 0
        add(n == 1 and ns.L("1 death") or ns.L("%d deaths", n))
    end
    if S.Get("leaveRep") then
        local rep = RepText(open)
        if rep then add(ns.L("%s reputation", rep)) end
    end
    if S.Get("leaveAverage") then
        local runs = RunsFor(open, true)
        local total, n = 0, 0
        for i = 1, #runs do
            if (runs[i].xp or 0) > 0 then
                total = total + runs[i].xp
                n = n + 1
            end
        end
        if n > 0 then
            add(ns.L("%s XP on average", BreakUpLargeNumbers(math.floor(total / n + 0.5))))
        end
    end
    if S.Get("leaveRunsLevel") and open.level then
        local runs = RunsFor(open, false)
        local n = 0
        for i = 1, #runs do
            if runs[i].level == open.level then n = n + 1 end
        end
        add(ns.L("%d runs this level", n))
    end
    if S.Get("leaveRunsToLevel") and (open.xp or 0) > 0
        and (open.lastMax or 0) > (open.lastXP or 0) then
        local more = math.ceil((open.lastMax - open.lastXP) / open.xp)
        if more > 0 then add(ns.L("about %d more to the next level", more)) end
    end
    return facts
end

local function Sentence(place, facts)
    if #facts == 0 then return end
    return place .. " " .. table.concat(facts, ", ") .. "."
end

local function SendLine(text, channel)
    return pcall(C_ChatInfo.SendChatMessage, text, channel)
end

-- Complete facts, joined by commas, with a period on each message.
local function SendFacts(channel, facts, fallback)
    local chunk = ""
    local function flush()
        if chunk == "" then return true end
        local line = chunk .. "."
        chunk = ""
        if SendLine(line, channel) then return true end
        ns.Print(fallback)
        return false
    end
    for i = 1, #facts do
        local joined = chunk == "" and facts[i] or (chunk .. ", " .. facts[i])
        if #joined + 1 > CHAT_LIMIT and chunk ~= "" then
            if not flush() then return end
            joined = facts[i]
        end
        chunk = joined
    end
    flush()
end

local function Deliver(shown, place, facts)
    if S.Get("leaveWhere") ~= "group" then
        ns.Print(shown)
        return
    end
    local channel = GroupChannel()
    local locked = C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
    if not channel or locked then
        ns.Print(shown)
        return
    end
    local body = table.concat(facts, ", ") .. "."
    local group = place .. " " .. body
    if #group <= CHAT_LIMIT then
        if not SendLine(group, channel) then ns.Print(shown) end
        return
    end
    if not SendLine(place, channel) then
        ns.Print(shown)
        return
    end
    SendFacts(channel, facts, shown)
end

local function AnnounceLeave(open, span)
    if not S.Get("leaveChat") or not open.instance then return end
    if open.kind == "raid" and not S.Get("leaveRaids") then return end
    if S.Get("leaveActivity") and not VisitActive(open) then return end
    local place = ns.L("Left %s.", Where(open))
    local shown = Sentence(place, LeaveFacts(open, span, false))
    if not shown then return end
    Deliver(shown, place, LeaveFacts(open, span, true))
end

-- A group member, as a short name, or Name-Realm when they are from somewhere else.
-- Forever has been seen to hand back "Name-Realm" in the first return.
local function MemberName(unit)
    local name, realm = UnitFullName(unit)
    if Secret(name) or Secret(realm) or type(name) ~= "string" then return end
    name = name:match("^[^-]+") or name
    if name == "" or name == UNKNOWNOBJECT then return end
    local mine = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName()
    if Secret(mine) then mine = nil end
    if type(realm) == "string" and realm ~= "" and realm ~= mine then
        name = name .. "-" .. realm
    end
    return name
end

-- Everyone else currently in the group. The visit already names this character.
local function CurrentGroup()
    local list = {}
    if not IsInGroup then return list end
    local grouped = IsInGroup()
    if Secret(grouped) or not grouped then return list end
    local raid = false
    if IsInRaid then
        local inRaid = IsInRaid()
        if not Secret(inRaid) and inRaid then raid = true end
    end
    local count = raid and GetNumGroupMembers() or GetNumSubgroupMembers()
    if Secret(count) or type(count) ~= "number" or count < 1 then return list end
    local prefix = raid and "raid" or "party"
    for i = 1, count do
        local unit = prefix .. i
        local mine = UnitIsUnit(unit, "player")
        if not Secret(mine) and not mine then
            local name = MemberName(unit)
            if name then
                local _, class = UnitClass(unit)
                if Secret(class) or type(class) ~= "string" or class == "" then class = nil end
                list[#list + 1] = { name = name, class = class }
            end
        end
    end
    return list
end

-- Write the group onto the visit. Someone who leaves before the end stays, so the
-- history shows who was there. A name that has not loaded yet is filled in later.
local function NoteGroup(open)
    if type(open) ~= "table" then return false end
    local members = CurrentGroup()
    if #members == 0 then return false end
    local group = type(open.group) == "table" and open.group or nil
    local known = {}
    if group then
        for i = 1, #group do
            local row = group[i]
            if type(row) == "table" and type(row.name) == "string" then
                known[row.name] = row
            end
        end
    end
    local changed = false
    for i = 1, #members do
        local member = members[i]
        if member.name ~= open.char then
            local row = known[member.name]
            if not row then
                if not group then
                    group = {}
                    open.group = group
                end
                row = { name = member.name, class = member.class }
                group[#group + 1] = row
                known[member.name] = row
                changed = true
            elseif member.class and row.class ~= member.class then
                row.class = member.class
                changed = true
            end
        end
    end
    return changed
end

-- at is a logout stamp, used when the leave itself was not seen live. quiet skips the
-- display refresh when the caller is about to start another visit immediately.
CloseRun = function(announce, at, quiet)
    local store = RawStore()
    local open = store and store.open
    if type(open) ~= "table" then
        SetRunEvents(false)
        return
    end
    store.open = nil
    SetRunEvents(false)
    if type(store.runs) ~= "table" then store.runs = {} end
    local left = at or time()
    if left < (open.entered or left) then left = time() end
    local span = Elapsed(open, left)
    local start = open.entered or left
    local repGain = false
    if type(open.rep) == "table" then
        for _, amount in pairs(open.rep) do
            if (amount or 0) > 0 then repGain = true end
        end
    end
    NoteGroup(open)
    local group = open.group
    if type(group) ~= "table" or #group == 0 then group = nil end
    local worth = span >= 1 or (open.loot or 0) > 0 or (open.xp or 0) > 0
        or (open.deaths or 0) > 0 or repGain
    if worth then
        local runs = store.runs
        table.insert(runs, 1, {
            realm = open.realm, char = open.char, class = open.class,
            instance = open.instance, mapID = open.mapID, kind = open.kind,
            difficulty = open.difficulty or "",
            entered = start, left = start + span, level = open.level,
            loot = open.loot or 0, xp = open.xp or 0, deaths = open.deaths or 0,
            rep = open.rep, toldSave = open.toldSave and true or nil,
            group = group,
        })
        while #runs > MAX_RUNS do runs[#runs] = nil end
        if announce then AnnounceLeave(open, span) end
    end
    if quiet then return end
    UpdateFrame()
    UI:RefreshPage(true)
end

-------------------------------------------------------------------------------
--  Hourly instance entries. A new dungeon or raid instance counts. Walking back into
--  one this character has not reset does not, for the hour after that entry. A later
--  zone-in counts again. A name saved before those stamps does not hold the count.
--  The client's own reset line clears that memory, and so does a reset a Nova
--  Instance Tracker group leader announces. The same group continues the visit. A
--  different group is a new one, so the earlier loot and group stay on that record.
--  The cap is 10 new instances in a rolling hour, for this character. Another
--  character on the account has their own 10.
-------------------------------------------------------------------------------
local expiryGen = 0

local function CopyKey(mapID, difficulty, name)
    if type(mapID) ~= "number" or mapID == 0 then
        return "name:" .. (name or "") .. ":" .. (difficulty or "")
    end
    return tostring(mapID) .. ":" .. (difficulty or "")
end

local function CharLives(store, create)
    local name = CharName()
    if name == "" then return end
    if type(store.live) ~= "table" then
        if not create then return end
        store.live = {}
    end
    local realm = RealmKey()
    local byRealm = store.live[realm]
    if type(byRealm) ~= "table" then
        if not create then return end
        byRealm = {}
        store.live[realm] = byRealm
    end
    local mine = byRealm[name]
    if type(mine) ~= "table" then
        if not create then return end
        mine = {}
        byRealm[name] = mine
    end
    return mine
end

local function ByAt(a, b)
    return a.at < b.at
end

local function PruneHour(store)
    local list = store.hour
    if type(list) ~= "table" then
        list = {}
        store.hour = list
        return list
    end
    local now = time()
    local n, w, ordered, prev = #list, 1, true, nil
    for i = 1, n do
        local row = list[i]
        if type(row) == "table" and type(row.at) == "number" and now - row.at < HOUR then
            if prev and prev.at > row.at then ordered = false end
            prev = row
            if w ~= i then list[w] = row end
            w = w + 1
        end
    end
    for i = n, w, -1 do list[i] = nil end
    if not ordered then table.sort(list, ByAt) end
    return list
end

local function WarnDistance()
    local n = math.floor(tonumber(S.Get("hourlyWarn")) or 1)
    if n < 1 then return 1 end
    if n > 5 then return 5 end
    return n
end

local function SameChar(row, realm, name)
    if type(row) ~= "table" or name == "" or row.who ~= name then return false end
    if type(row.realm) ~= "string" or row.realm == "" then return true end
    return row.realm == realm
end

local function HourFor(list, realm, name)
    local count, oldest = 0, nil
    for i = 1, #list do
        local row = list[i]
        if SameChar(row, realm, name) then
            count = count + 1
            if not oldest or row.at < oldest then oldest = row.at end
        end
    end
    local frees = 0
    if oldest then
        frees = oldest + HOUR - time()
        if frees < 0 then frees = 0 end
    end
    return count, frees
end

-- Oldest first, this character only. PruneHour has already ordered the full list.
-- Only the page path copies this character's rows.
local function CharacterHour(store, realm, name)
    local list = PruneHour(store)
    local mine = {}
    for i = 1, #list do
        if SameChar(list[i], realm, name) then
            mine[#mine + 1] = list[i]
        end
    end
    return mine
end

local function HourSnapshot(store)
    if not store then return 0, HOURLY_CAP, 0 end
    local count, frees = HourFor(PruneHour(store), RealmKey(), CharName())
    return count, HOURLY_CAP, frees
end

-- One note per character, so an alt already warned does not swallow this character's.
local function NotedMap(store)
    if type(store.hourNoted) ~= "table" then store.hourNoted = {} end
    return store.hourNoted
end

local function WarnHour()
    if not On() then return end
    local store = RawStore()
    if not store then return end
    local name = CharName()
    if name == "" then return end
    local count, cap, frees = HourSnapshot(store)
    local noted = NotedMap(store)
    local key = RealmKey() .. "\031" .. name
    local left = cap - count
    if left < 0 then left = 0 end
    if count <= 0 or left > WarnDistance() then
        noted[key] = nil
        return
    end
    local state = left <= 0 and "cap" or "close"
    if noted[key] == state then return end
    noted[key] = state
    local when = FormatDuration(frees)
    if left <= 0 then
        ns.Print(ns.L("%s has used %d of %d instances this hour. A new instance will not let you in. The next one frees in %s.",
            name, count, cap, when))
    else
        ns.Print(ns.L("%s has used %d of %d instances this hour. %d left before a new instance will not let you in. The next one frees in %s.",
            name, count, cap, left, when))
    end
end

local function StopExpiry()
    expiryGen = expiryGen + 1
end

local function ScheduleExpiry()
    StopExpiry()
    if not On() then return end
    local store = RawStore()
    if not store then return end
    local list = PruneHour(store)
    if #list == 0 then return end
    local delay = list[1].at + HOUR - time()
    if delay < 1 then delay = 1 end
    local gen = expiryGen
    C_Timer.After(delay, function()
        if gen ~= expiryGen then return end
        local current = RawStore()
        if current then PruneHour(current) end
        WarnHour()
        UpdateFrame()
        UI:RefreshPage(true)
        ScheduleExpiry()
    end)
end

-- A stamp inside the hour is still this copy. An older stamp, or a name saved
-- before stamps existed, is not. A login does not count. The block through
-- GroupsDiffer is loaded by the regression.
local function CopyFresh(stored, now, hour)
    if type(stored) ~= "table" or type(stored.at) ~= "number" then return false end
    if type(now) ~= "number" or type(hour) ~= "number" then return false end
    local age = now - stored.at
    return age >= 0 and age < hour
end

-- True when this zone-in adds an hourly entry. A login or reload does not.
local function CountsEntry(stored, now, hour, countIt)
    if not countIt then return false end
    return not CopyFresh(stored, now, hour)
end

-- True when the people zoning in are not the visit's group. One shared name keeps
-- the visit. Two empty groups are the same solo copy. An empty roster while still
-- grouped has not loaded, so it does not split the visit.
local function GroupsDiffer(saved, current, inGroup)
    local function names(group)
        local set, n = {}, 0
        if type(group) ~= "table" then return set, 0 end
        for i = 1, #group do
            local row = group[i]
            local who = type(row) == "table" and row.name or nil
            if type(who) == "string" and who ~= "" and not set[who] then
                set[who] = true
                n = n + 1
            end
        end
        return set, n
    end
    local savedSet, savedN = names(saved)
    local hereSet, hereN = names(current)
    for who in pairs(savedSet) do
        if hereSet[who] then return false end
    end
    if savedN == 0 and hereN == 0 then return false end
    if hereN == 0 and inGroup then return false end
    return true
end

-- countIt is false for a login or reload: that copy already existed. An existing
-- stamp stays put on that path, so a resume does not push the hour forward.
local function NoteInstanceEntry(name, mapID, difficulty, countIt)
    local store = EnsureStore()
    local lives = CharLives(store, true)
    if not lives then return end
    local key = CopyKey(mapID, difficulty, name)
    local now = time()
    if not CountsEntry(lives[key], now, HOUR, countIt) then
        if lives[key] == nil then
            lives[key] = { name = name or "", at = now }
        end
        return
    end
    lives[key] = { name = name or "", at = now }
    if type(store.hour) ~= "table" then store.hour = {} end
    store.hour[#store.hour + 1] = {
        at = now, name = name or "", map = mapID, who = CharName(), realm = RealmKey(),
    }
    PruneHour(store)
    WarnHour()
    ScheduleExpiry()
end

-------------------------------------------------------------------------------
--  Nova Instance Tracker, prefix "NIT". A reset is the text
--  "<command> <version> <instance>" (the name keeps its spaces), then LibSerialize,
--  LibDeflate at level 9, and the addon-channel encoding. Version 1 is the oldest
--  Nova still reads, and it is not newer than a current copy, so Nova does not tell
--  that player to update.
--
--  instanceReset rides with a "[NIT] " line in party or raid chat. Nova's handler for
--  that command does nothing, because the chat line is what the group sees.
--  instanceResetNoMsg is the same reset with the chat line left out, and Nova prints
--  it. instanceResetOther is that print from Nova World Buffs, on this same prefix.
--  Nova reset wire format. The block through ClearNamedCopy is loaded by the regression.
-------------------------------------------------------------------------------
local NIT_PREFIX = "NIT"
local NIT_VERSION = "1"
local NIT_STILL_INSIDE = "has been reset (Players still inside old instance can zone out and enter new)."
local NIT_RESET = {
    instanceReset = true,
    instanceResetNoMsg = true,
    instanceResetOther = true,
}
local NIT_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }

local function NitCodec()
    local LS = LibStub and LibStub("LibSerialize", true)
    local LD = LibStub and LibStub("LibDeflate", true)
    if not LS or not LD then return end
    return LS, LD
end

-- One addon message. AceComm treats a leading control byte as its own framing, so a
-- reset that starts with one is sent with the escape byte in front.
local function NitEncode(plain)
    if type(plain) ~= "string" or plain == "" then return end
    local LS, LD = NitCodec()
    if not LS then return end
    local serialized = LS:Serialize(plain)
    if type(serialized) ~= "string" then return end
    local compressed = LD:CompressDeflate(serialized, { level = 9 })
    if type(compressed) ~= "string" then return end
    local encoded = LD:EncodeForWoWAddonChannel(compressed)
    if type(encoded) ~= "string" or encoded == "" or #encoded > 255 then return end
    return encoded
end

local function NitWire(plain)
    local encoded = NitEncode(plain)
    if not encoded then return end
    local lead = encoded:byte(1)
    if lead >= 1 and lead <= 9 then
        if #encoded >= 255 then return end
        return "\004" .. encoded
    end
    return encoded
end

local function NitDecode(payload)
    if type(payload) ~= "string" or payload == "" then return end
    local lead = payload:byte(1)
    if lead == 4 then
        payload = payload:sub(2)
        if payload == "" then return end
    elseif lead == 1 or lead == 2 or lead == 3 then
        return
    end
    local LS, LD = NitCodec()
    if not LS then return end
    local decoded = LD:DecodeForWoWAddonChannel(payload)
    if type(decoded) ~= "string" then return end
    local compressed = LD:DecompressDeflate(decoded)
    if type(compressed) ~= "string" then return end
    local ok, value = LS:Deserialize(compressed)
    if not ok or type(value) ~= "string" then return end
    return value
end

-- The first two words are the command and the version. The instance keeps its spaces.
local function NitFields(text)
    if type(text) ~= "string" then return end
    local cmd, version, rest = text:match("^(%S+)%s+(%S+)%s*(.*)$")
    if not cmd then return end
    if rest == "" then rest = nil end
    return cmd, version, rest
end

local function NitVersionOk(version)
    local n = tonumber(version)
    return n ~= nil and n >= 1
end

-- The name Nova prints: the sender, without a realm glued on the end.
local function NitWho(sender)
    if type(sender) ~= "string" or sender == "" then return end
    local name = sender:match("^([^%-]+)")
    if not name or name == "" then return end
    return name
end

-- A realm that is not ours is ignored. A roster match who is not the leader is
-- ignored. A name that matches no unit is still taken: Forever's addon sender is
-- often a full name no unit API returns, and Nova only sends this as the leader.
local function NitSenderOk(sender, realm, normalized, roster)
    if type(sender) ~= "string" or sender == "" then return false end
    local _, theirs = sender:match("^([^%-]+)%-(.+)$")
    if theirs and theirs ~= realm and theirs ~= normalized then return false end
    if type(roster) ~= "table" then return true end
    local who = NitWho(sender)
    local saw, leads = false, false
    for name, leader in pairs(roster) do
        if name == sender or name == who then
            saw = true
            if leader then leads = true end
        end
    end
    if saw then return leads end
    return true
end

-- The instance to forget, and a line to print when Nova sent no chat line.
local function NitIncoming(text, sender, realm, normalized, roster)
    local cmd, version, instance = NitFields(text)
    if not NIT_RESET[cmd] or not NitVersionOk(version) then return end
    if not NitSenderOk(sender, realm, normalized, roster) then return end
    if type(instance) ~= "string" or instance == "" then return end
    local line
    if cmd ~= "instanceReset" then
        line = instance .. " has been reset by the group leader (" .. (NitWho(sender) or sender) .. ")."
    end
    return instance, line
end

-- kind is "success", "inside", "zoning" or "offline". chatOk is whether the group
-- line can go out. A failed chat send of a real reset uses instanceResetNoMsg, so
-- Nova still prints it. Zoning and offline are the chat line only.
local function NitOutbound(kind, instance, systemText, chatOk)
    if type(instance) ~= "string" or instance == "" then return end
    local body
    if kind == "inside" then
        body = instance .. " " .. NIT_STILL_INSIDE
    elseif kind == "success" or kind == "zoning" or kind == "offline" then
        body = systemText
    else
        return
    end
    if type(body) ~= "string" or body == "" then return end
    local chat = chatOk and ("[NIT] " .. body) or nil
    if kind ~= "success" and kind ~= "inside" then return chat end
    local cmd = chat and "instanceReset" or "instanceResetNoMsg"
    return chat, cmd .. " " .. NIT_VERSION .. " " .. instance
end

-- Drops every live copy stored under this instance name. The hour list is left as
-- it is: a reset does not give an entry back.
local function ClearNamedCopy(lives, name)
    if type(lives) ~= "table" or type(name) ~= "string" or name == "" then return false end
    local cleared = false
    for key, stored in pairs(lives) do
        local storedName = stored
        if type(stored) == "table" then storedName = stored.name end
        if storedName == name then
            lives[key] = nil
            cleared = true
        end
    end
    return cleared
end
-- end Nova reset wire format

local function ForgetCopy(name)
    local store = RawStore()
    if not store then return end
    local mine = CharLives(store, false)
    if not mine then return end
    if name then
        ClearNamedCopy(mine, name)
    else
        for key in pairs(mine) do mine[key] = nil end
    end
end

local function ResetPattern(global)
    if type(global) ~= "string" or not global:find("%s", 1, true) then return end
    local pattern = global:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    return "^" .. pattern:gsub("%%%%s", "(.+)") .. "$"
end

local resetPatterns
local function ClassifyReset(text)
    if type(text) ~= "string" or Secret(text) then return end
    if not resetPatterns then
        resetPatterns = {
            zoning = ResetPattern(INSTANCE_RESET_FAILED_ZONING),
            offline = ResetPattern(INSTANCE_RESET_FAILED_OFFLINE),
            inside = ResetPattern(INSTANCE_RESET_FAILED),
            success = ResetPattern(INSTANCE_RESET_SUCCESS),
        }
    end
    local order = { "zoning", "offline", "inside", "success" }
    for i = 1, #order do
        local kind = order[i]
        local pattern = resetPatterns[kind]
        if pattern then
            local name = text:match(pattern)
            if name then return kind, name end
        elseif kind == "success" and type(INSTANCE_RESET_SUCCESS) == "string"
            and text == INSTANCE_RESET_SUCCESS then
            return "success"
        end
    end
end

-- Raid, else the instance group, else the party. Alone, nothing is sent. A raid is
-- included here even when the leave summary is not sent to raid chat.
local function ResetChannel()
    if IsInRaid then
        local raid = IsInRaid()
        if not Secret(raid) and raid then return "RAID" end
    end
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup then
        local instance = IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
        if not Secret(instance) and instance then return "INSTANCE_CHAT" end
    end
    if IsInGroup then
        local group = IsInGroup()
        if not Secret(group) and group then return "PARTY" end
    end
end

local function WeAreLeader()
    if not UnitIsGroupLeader then return false end
    local leader = UnitIsGroupLeader("player")
    if Secret(leader) or not leader then return false end
    return true
end

local function ChatWent(ok, result)
    if not ok then return false end
    if result == nil or result == true then return true end
    local success = Enum and Enum.SendChatMessageResult and Enum.SendChatMessageResult.Success
    return result == success
end

local function AddonWent(ok, result)
    if not ok then return false end
    if result == nil or result == true then return true end
    local success = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success
    return result == success
end

local function SendResetChat(text, channel)
    if type(text) ~= "string" or #text > CHAT_LIMIT or #text == 0 then return false end
    return ChatWent(pcall(C_ChatInfo.SendChatMessage, text, channel))
end

local function SendResetAddon(plain, channel)
    local encoded = NitWire(plain)
    if not encoded then return false end
    return AddonWent(pcall(C_ChatInfo.SendAddonMessage, NIT_PREFIX, encoded, channel))
end

local function AnnounceReset(kind, name, text)
    if not WeAreLeader() then return end
    local channel = ResetChannel()
    if not channel then return end
    local locked = C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
    if Secret(locked) then locked = true end
    local chat, plain = NitOutbound(kind, name or "", text, not locked)
    if chat and not SendResetChat(chat, channel) then
        plain = select(2, NitOutbound(kind, name or "", text, false))
    end
    if plain then SendResetAddon(plain, channel) end
end

local function OnResetMessage(text)
    local kind, name = ClassifyReset(text)
    if not kind then return end
    if kind == "success" or kind == "inside" then ForgetCopy(name) end
    AnnounceReset(kind, name, text)
end

local function OurRealm()
    local realm = GetRealmName()
    if Secret(realm) or type(realm) ~= "string" then realm = "" end
    local normalized = (GetNormalizedRealmName and GetNormalizedRealmName()) or realm
    if Secret(normalized) or type(normalized) ~= "string" then normalized = realm end
    return realm, normalized
end

local function IsOwnSender(sender)
    if type(sender) ~= "string" or sender == "" then return true end
    local full, first = FullName(), FirstName()
    local realm, normalized = OurRealm()
    if sender == full or sender == first then return true end
    if full ~= "" and (sender == full .. "-" .. realm or sender == full .. "-" .. normalized) then
        return true
    end
    if first ~= "" and (sender == first .. "-" .. realm or sender == first .. "-" .. normalized) then
        return true
    end
    return false
end

-- Names that match a group unit, and whether that unit leads. No match is absent,
-- which the incoming check treats as still worth taking.
local function LeaderRoster()
    local roster = {}
    if not IsInGroup then return roster end
    local grouped = IsInGroup()
    if Secret(grouped) or not grouped then return roster end
    local raid = false
    if IsInRaid then
        local inRaid = IsInRaid()
        if not Secret(inRaid) and inRaid then raid = true end
    end
    local count = raid and GetNumGroupMembers() or GetNumSubgroupMembers()
    if Secret(count) or type(count) ~= "number" then return roster end
    local prefix = raid and "raid" or "party"
    local function note(unit)
        local leader = UnitIsGroupLeader and UnitIsGroupLeader(unit)
        if Secret(leader) then leader = false end
        leader = leader and true or false
        local name = MemberName(unit)
        if name then roster[name] = leader end
        local full = UnitFullName(unit)
        if not Secret(full) and type(full) == "string" and full ~= "" then roster[full] = leader end
    end
    note("player")
    for i = 1, count do
        local unit = prefix .. i
        local mine = UnitIsUnit(unit, "player")
        if Secret(mine) or not mine then note(unit) end
    end
    return roster
end

local function OnNovaReset(prefix, payload, channel, sender)
    if Secret(prefix) or prefix ~= NIT_PREFIX then return end
    if Secret(payload) or Secret(channel) or Secret(sender) then return end
    if not NIT_CHANNELS[channel] or IsOwnSender(sender) then return end
    local text = NitDecode(payload)
    if not text then return end
    local realm, normalized = OurRealm()
    local instance, line = NitIncoming(text, sender, realm, normalized, LeaderRoster())
    if not instance then return end
    ForgetCopy(instance)
    if line then ns.Print(line) end
end

local function TakeSameCopy(name, mapID, difficulty)
    local store = RawStore()
    if not store or type(store.runs) ~= "table" then return end
    local mine = CharLives(store, false)
    if not mine or not mine[CopyKey(mapID, difficulty, name)] then return end
    local now = time()
    local grouped = false
    if IsInGroup then
        local inGroup = IsInGroup()
        if not Secret(inGroup) and inGroup then grouped = true end
    end
    local current = CurrentGroup()
    for i = 1, #store.runs do
        local run = store.runs[i]
        if type(run) == "table" and SamePlace(run, name, mapID, difficulty) then
            local away = now - (tonumber(run.left) or 0)
            if away < 0 or away >= AWAY_CAP then return end
            -- A different group is a new copy. The old visit stays in the history.
            if GroupsDiffer(run.group, current, grouped) then return end
            table.remove(store.runs, i)
            return run
        end
    end
end

BeginRun = function(name, kind, difficulty, mapID, announce)
    local row, realm, char = TouchChar()
    if not row then return end
    local store = EnsureStore()
    local open = store.open
    if type(open) == "table" and SamePlace(open, name, mapID, difficulty) then
        -- Drop the time passed while logged out or reloading, then keep counting.
        if open.seen then
            local away = time() - open.seen
            if away > 0 and away < AWAY_CAP then
                open.skipped = (open.skipped or 0) + away
            end
            open.seen = nil
        end
        open.wantSave = nil
        NoteInstanceEntry(name, mapID, difficulty, false)
        if NoteGroup(open) then UI:RefreshPage(true) end
        SetRunEvents(true)
        UpdateFrame()
        return
    end
    if type(open) == "table" then
        CloseRun(announce, (not announce) and open.seen or nil, true)
    end
    local prior = TakeSameCopy(name, mapID, difficulty)
    if prior then
        local now = time()
        local skipped = now - (tonumber(prior.left) or now)
        if skipped < 0 then skipped = 0 end
        store.open = {
            realm = prior.realm or realm, char = prior.char or char,
            class = prior.class or row.class, level = prior.level or row.level,
            instance = name, mapID = mapID ~= 0 and mapID or prior.mapID,
            kind = kind, difficulty = difficulty,
            entered = prior.entered or now, skipped = skipped,
            loot = prior.loot or 0, xp = prior.xp or 0, deaths = prior.deaths or 0,
            rep = prior.rep, toldSave = prior.toldSave and true or nil,
            wantSave = (announce and not prior.toldSave) and true or nil,
            group = prior.group,
        }
        NoteGroup(store.open)
        NoteInstanceEntry(name, mapID, difficulty, false)
        NoteXP(true)
        SetRunEvents(true)
        if announce then AnnounceResume(store.open) end
        UpdateFrame()
        UI:RefreshPage(true)
        return
    end
    store.open = {
        realm = realm, char = char, class = row.class, level = row.level,
        instance = name, mapID = mapID, kind = kind, difficulty = difficulty,
        entered = time(), loot = 0, xp = 0, deaths = 0,
        wantSave = announce and true or false,
    }
    NoteGroup(store.open)
    NoteInstanceEntry(name, mapID, difficulty, announce and true or false)
    NoteXP(true)
    SetRunEvents(true)
    if announce then AnnounceEnter(store.open) end
    UpdateFrame()
    UI:RefreshPage(true)
end

local function SyncZone(announce)
    if not On() then return end
    local name, state, kind, difficulty, mapID = CurrentInstance()
    if state == "secret" then return end
    if state ~= "in" then
        local open = OpenRun()
        if open then CloseRun(announce, (not announce) and open.seen or nil)
        else UpdateFrame() end
        return
    end
    BeginRun(name, kind, difficulty, mapID, announce)
end

-------------------------------------------------------------------------------
--  Run timer. Built the first time it is allowed on screen, and ticked only while a
--  visit is actually in progress.
-------------------------------------------------------------------------------
local function FrameWanted()
    if not On() or not S.Get("showFrame") then return false end
    if unlocked then return true end
    return OpenRun() ~= nil
end

local function StopClock()
    if clock then clock:Cancel(); clock = nil end
end

local function Place()
    local pos = S.Get("pos")
    frame:ClearAllPoints()
    if type(pos) == "table" and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, DEFAULT_Y)
    end
end

local function XPPerHour(open)
    return (open.xp or 0) / (math.max(Elapsed(open), 60) / 3600)
end

local function XPLine(open)
    local rate = open and math.floor(XPPerHour(open) + 0.5) or 0
    return "XP/hr " .. BreakUpLargeNumbers(rate)
end

local function HourLine()
    local count, cap, frees = HourSnapshot(RawStore())
    local text = string.format("Instances this hour: %d of %d", count, cap)
    if count > 0 then text = text .. "   " .. FormatDuration(frees) end
    local left = cap - count
    if count > 0 and left <= WarnDistance() then
        return ns.Color(left <= 0 and CAP_RGB or WARN_RGB, text)
    end
    return text
end

local function Paint()
    local open = OpenRun()
    if open then
        frame.title:SetText(Where(open))
        frame.time:SetText(FormatDuration(Elapsed(open)))
        frame.stats:SetText(Coins(open.loot) .. "   " .. BreakUpLargeNumbers(open.xp or 0) .. " XP")
    else
        frame.title:SetText("Instance")
        frame.time:SetText("0:00")
        frame.stats:SetText(Coins(0) .. "   0 XP")
    end
    frame.xp:SetText(XPLine(open))
    frame.hour:SetText(HourLine())
end

local function Build()
    frame = CreateFrame("Frame", "NaowhForeverInstanceTracker", UIParent)
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    frame.bg = ns.Solid(frame, "BACKGROUND", T.bg, FRAME_ALPHA)
    frame.bg:SetAllPoints()
    ns.Border(frame, ns.Shared.Style.BORDER_RGB)
    frame.title = ns.Font(frame, TITLE_SIZE, "OUTLINE", T.accent)
    frame.title:SetPoint("TOPLEFT", PAD_X, -TITLE_TOP)
    frame.title:SetPoint("TOPRIGHT", -PAD_X, -TITLE_TOP)
    frame.title:SetJustifyH("LEFT")
    frame.title:SetWordWrap(false)
    frame.time = ns.Font(frame, TIME_SIZE, "OUTLINE", T.fg)
    frame.time:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -TIME_GAP)
    frame.time:SetJustifyH("LEFT")
    frame.stats = ns.Font(frame, BODY_SIZE, "OUTLINE", T.fg)
    frame.stats:SetPoint("TOPLEFT", frame.time, "BOTTOMLEFT", 0, -LINE_GAP)
    frame.stats:SetPoint("RIGHT", frame, "RIGHT", -PAD_X, 0)
    frame.stats:SetJustifyH("LEFT")
    frame.stats:SetWordWrap(false)
    frame.xp = ns.Font(frame, BODY_SIZE, "OUTLINE", T.fg)
    frame.xp:SetPoint("TOPLEFT", frame.stats, "BOTTOMLEFT", 0, -LINE_GAP)
    frame.xp:SetPoint("RIGHT", frame, "RIGHT", -PAD_X, 0)
    frame.xp:SetJustifyH("LEFT")
    frame.xp:SetWordWrap(false)
    frame.hour = ns.Font(frame, BODY_SIZE, "OUTLINE", T.fg)
    frame.hour:SetPoint("TOPLEFT", frame.xp, "BOTTOMLEFT", 0, -LINE_GAP)
    frame.hour:SetPoint("RIGHT", frame, "RIGHT", -PAD_X, 0)
    frame.hour:SetJustifyH("LEFT")
    frame.hour:SetWordWrap(false)
    frame.mover = UI.AttachMover(frame, "Instance Tracker", function(pos) S.Set("pos", pos) end,
        "Instance Tracker/Display")
    frame:Hide()
end

UpdateFrame = function()
    if not FrameWanted() then
        StopClock()
        if frame then frame:Hide() end
        return
    end
    if not frame then Build() end
    if not frame.placed then Place(); frame.placed = true end
    Paint()
    frame.mover:SetShown(unlocked == true)
    frame:Show()
    if OpenRun() then
        if not clock then clock = C_Timer.NewTicker(1, UpdateFrame) end
    else
        StopClock()
    end
end

local function CopyLocks(locks)
    local now, copy = time(), {}
    for i = 1, #locks do
        local lock = locks[i]
        if type(lock) == "table" and lock.resetAt and lock.resetAt > now then
            copy[#copy + 1] = lock
        end
    end
    table.sort(copy, function(a, b)
        if a.isRaid ~= b.isRaid then return a.isRaid and not b.isRaid end
        if a.name ~= b.name then return tostring(a.name) < tostring(b.name) end
        return (a.resetAt or 0) < (b.resetAt or 0)
    end)
    return copy
end

ns.InstanceTracker = {
    MAX_RUNS = MAX_RUNS,
    PAGE_RUNS = 40,
    HOURLY_CAP = HOURLY_CAP,
    Enabled = On,
    Open = OpenRun,
    Duration = FormatDuration,
    Elapsed = Elapsed,
    Remaining = FormatRemaining,
    Coins = Coins,
    WarnDistance = WarnDistance,
    CapRGB = CAP_RGB,
    WarnRGB = WARN_RGB,
}

function ns.InstanceTracker.Characters()
    local list, store = {}, RawStore()
    if not store or type(store.chars) ~= "table" then return list end
    local myRealm, myName = RealmKey(), CharName()
    local track = S.Get("trackAlts")
    local hour = PruneHour(store)
    for realm, group in pairs(store.chars) do
        if type(group) == "table" then
            for name, row in pairs(group) do
                local mine = realm == myRealm and name == myName
                if type(row) == "table" and (track or mine) then
                    local count, frees = HourFor(hour, realm, name)
                    list[#list + 1] = {
                        realm = realm, name = name, class = row.class,
                        level = row.level or 0, mine = mine,
                        xp = row.xp, xpMax = row.xpMax, rested = row.rested,
                        durability = row.durability, seen = row.seen,
                        hour = count, hourFrees = frees,
                        lockouts = CopyLocks(type(row.lockouts) == "table" and row.lockouts or {}),
                    }
                end
            end
        end
    end
    table.sort(list, function(a, b)
        local aHome, bHome = a.realm == myRealm, b.realm == myRealm
        if aHome ~= bHome then return aHome end
        if a.realm ~= b.realm then return a.realm < b.realm end
        if a.mine ~= b.mine then return a.mine end
        if a.level ~= b.level then return a.level > b.level end
        return a.name < b.name
    end)
    return list
end

function ns.InstanceTracker.Runs()
    local store = RawStore()
    if not store or type(store.runs) ~= "table" then return {} end
    if S.Get("trackAlts") then return store.runs end
    local realm, name = RealmKey(), CharName()
    local list = {}
    for i = 1, #store.runs do
        local run = store.runs[i]
        if run.realm == realm and run.char == name then
            list[#list + 1] = run
        end
    end
    return list
end

function ns.InstanceTracker.ClearHistory()
    local store = RawStore()
    if store then store.runs = {} end
end

function ns.InstanceTracker.Hour()
    return HourSnapshot(RawStore())
end

function ns.InstanceTracker.HourEntries()
    local store = RawStore()
    if not store then return {} end
    local mine = CharacterHour(store, RealmKey(), CharName())
    local rows = {}
    for i = #mine, 1, -1 do rows[#rows + 1] = mine[i] end
    return rows
end

-- Other characters who still have entries inside the hour, fullest first.
function ns.InstanceTracker.HourOthers()
    local store = RawStore()
    if not store then return {} end
    local list = PruneHour(store)
    local realm, name = RealmKey(), CharName()
    local grouped, order = {}, {}
    for i = 1, #list do
        local row = list[i]
        if not SameChar(row, realm, name) then
            local key = (row.realm or "") .. "\031" .. (row.who or "")
            local bucket = grouped[key]
            if not bucket then
                bucket = { who = row.who or "", realm = row.realm, count = 0, at = row.at }
                grouped[key] = bucket
                order[#order + 1] = bucket
            end
            bucket.count = bucket.count + 1
            if type(row.at) == "number" and row.at < (bucket.at or row.at) then
                bucket.at = row.at
            end
        end
    end
    table.sort(order, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return (a.who or "") < (b.who or "")
    end)
    return order
end

function ns.InstanceTracker.EntryLeft(row)
    if type(row) ~= "table" or type(row.at) ~= "number" then return 0 end
    local left = row.at + HOUR - time()
    if left < 0 then return 0 end
    return left
end

-------------------------------------------------------------------------------
--  Events. Registered only while the module is on. Loot, reputation and deaths only
--  while a visit is open. Rest and durability update the whole time, so an alt's
--  sheet is current the next time you log over.
-------------------------------------------------------------------------------
-- The sheet is written immediately. The open page follows a moment later, so a bag
-- update does not rebuild it on every slot.
local sheetQueued
local function QueueSheet()
    TouchChar()
    if sheetQueued then return end
    sheetQueued = true
    C_Timer.After(1, function()
        sheetQueued = nil
        if On() then UI:RefreshPage(true) end
    end)
end

events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        local login, reload = ...
        SyncZone(not login and not reload)
        QueueSheet()
    elseif event == "UPDATE_INSTANCE_INFO" then
        SaveLockouts()
    elseif event == "PLAYER_LOGOUT" then
        TouchChar()
        local open = OpenRun()
        if open then
            NoteGroup(open)
            open.seen = time()
        end
    elseif event == "CHAT_MSG_SYSTEM" then
        OnResetMessage(...)
    elseif event == "CHAT_MSG_ADDON" then
        OnNovaReset(...)
    elseif event == "CHAT_MSG_MONEY" then
        AddLoot(...)
    elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
        NoteRep(...)
    elseif event == "PLAYER_DEAD" then
        local open = OpenRun()
        if open then open.deaths = (open.deaths or 0) + 1 end
    elseif event == "GROUP_ROSTER_UPDATE" then
        local open = OpenRun()
        if open and NoteGroup(open) then UI:RefreshPage(true) end
    elseif event == "UPDATE_INVENTORY_DURABILITY" then
        QueueSheet()
    elseif event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" then
        if event == "PLAYER_LEVEL_UP" then
            local newLevel = ...
            local open = OpenRun()
            if open and not Secret(newLevel) and type(newLevel) == "number" then
                open.level = newLevel
            end
        end
        NoteXP(false)
        QueueSheet()
        UpdateFrame()
    end
end)

local function Apply()
    events:UnregisterAllEvents()
    StopClock()
    StopExpiry()
    if not On() then
        if OpenRun() then CloseRun(false) end
        if frame then frame:Hide(); frame.placed = nil end
        return
    end
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("UPDATE_INSTANCE_INFO")
    events:RegisterEvent("PLAYER_LOGOUT")
    events:RegisterEvent("CHAT_MSG_SYSTEM")
    events:RegisterEvent("CHAT_MSG_ADDON")
    if C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(NIT_PREFIX)
    end
    events:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    events:RegisterEvent("PLAYER_XP_UPDATE")
    events:RegisterEvent("PLAYER_LEVEL_UP")
    -- The Top Bar asks the server for saved instances on each zone. Read whatever
    -- the client already has, so enabling the tracker does not request them again.
    SaveLockouts()
    PruneAlts()
    TouchChar()
    if frame then frame.placed = nil end
    SyncZone(false)
    ScheduleExpiry()
    WarnHour()
end

S.OnChange(function(key)
    if key == "pos" then return end
    if key == "enabled" then Apply()
    elseif key == "showFrame" then UpdateFrame()
    elseif key == "hourlyWarn" then WarnHour()
    elseif key == "trackAlts" and not S.Get("trackAlts") then PruneAlts() end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = On() and S.Get("showFrame") and true or false
    UpdateFrame()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlocked = false
    UpdateFrame()
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Apply()
end)
