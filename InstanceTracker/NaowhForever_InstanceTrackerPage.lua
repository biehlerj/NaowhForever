-------------------------------------------------------------------------------
--  NaowhForever_InstanceTrackerPage.lua -- the lockouts and history lists, and the
--  settings cards. The lists are drawn in the module's own window. Opening one only
--  reads what the tracker has already stored.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI
local T = ns.THEME
local S = ns.InstanceTrackerSettings

-- Lockouts and History rows. Sizes are pixels at the addon's UI scale.
local LINE_H = 20          -- one visit line, and the shortest a wrapped line may be
local LINE_FONT = 12       -- the row's text; also the shortest a wrapped string may measure
local LINE_INSET = 4       -- text from a row's edges
local COUNT_GAP = 12       -- between the visit facts and the group count on the right
local HOVER = 0.08         -- the visit under the cursor, so the names belong to it
local FALLBACK_W = 960     -- used when the page has no width yet
local GROUP_GAP = 6        -- under a character, an hour list, or an in-progress visit

-- Cap and warn colors live on the tracker. Secondary text uses the theme's muted
-- color, read when the line is built.
local function HourPaint(left, text)
    local colors = ns.InstanceTracker
    return ns.Color(left <= 0 and colors.CapRGB or colors.WarnRGB, text)
end

local function Line(parent, y, text)
    -- Search runs the builder on a stub parent. These rows are stored visits, not settings.
    if UI.searchScan then return y - LINE_H end
    local row = UI.Keep(parent, "line", function(p)
        local f = CreateFrame("Frame", nil, p)
        f:SetHeight(LINE_H)
        f.text = ns.Font(f, LINE_FONT, nil, T.fg)
        f.text:SetPoint("LEFT", LINE_INSET, 0)
        f.text:SetPoint("RIGHT", -LINE_INSET, 0)
        f.text:SetJustifyH("LEFT")
        f.text:SetWordWrap(false)
        return f
    end)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.CONTENT_PAD, y)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -UI.CONTENT_PAD, y)
    row:SetHeight(LINE_H)
    row.text:SetFont(UI.FontPath(""), LINE_FONT, "")
    row.text:SetTextColor(T.fg.r, T.fg.g, T.fg.b, 1)
    row.text:SetText(text)
    return y - LINE_H
end

-- A second line under a visit. One line stays the same height as the rows above it;
-- a long one wraps instead of running off the page. Padding is the inset on both sides.
local function WrapLine(parent, y, text)
    if UI.searchScan then return y - LINE_H end
    local row = UI.Keep(parent, "wrap", function(p)
        local f = CreateFrame("Frame", nil, p)
        f.text = ns.Font(f, LINE_FONT, nil, T.fg)
        f.text:SetJustifyH("LEFT")
        f.text:SetWordWrap(true)
        return f
    end)
    local width = parent:GetWidth() or 0
    if width <= 0 then width = FALLBACK_W end
    width = width - UI.CONTENT_PAD * 2
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.CONTENT_PAD, y)
    row:SetWidth(width)
    row.text:SetFont(UI.FontPath(""), LINE_FONT, "")
    row.text:SetTextColor(T.fg.r, T.fg.g, T.fg.b, 1)
    row.text:ClearAllPoints()
    row.text:SetPoint("TOPLEFT", LINE_INSET, -LINE_INSET)
    row.text:SetWidth(math.max(1, width - LINE_INSET * 2))
    row.text:SetText(text)
    local textH = math.ceil(row.text:GetStringHeight())
    if textH < LINE_FONT then textH = LINE_FONT end
    local h = textH + LINE_INSET * 2
    if h < LINE_H then h = LINE_H end
    row:SetHeight(h)
    return y - h
end

local function OffText()
    if ns.InstanceTracker.Enabled() then return "" end
    return "Instance Tracker is off, so nothing new is recorded. "
end

local function LockLine(lock)
    local parts = { lock.name or "" }
    if type(lock.difficulty) == "string" and lock.difficulty ~= "" then
        parts[#parts + 1] = lock.difficulty
    end
    if (lock.maxPlayers or 0) > 0 then
        parts[#parts + 1] = lock.maxPlayers .. "-player"
    end
    if (lock.encounters or 0) > 0 then
        parts[#parts + 1] = ns.Shared.Parts.Fraction(lock.progress or 0, lock.encounters)
    end
    if (lock.id or 0) > 0 then
        parts[#parts + 1] = "ID " .. lock.id
    end
    if lock.extended then parts[#parts + 1] = "extended" end
    parts[#parts + 1] = "resets in " .. ns.InstanceTracker.Remaining(lock.resetAt)
    return ns.Color("muted", table.concat(parts, "  -  "))
end

local function CharLine(char)
    local who = ns.ClassColoredName(char.name, char.class)
    local extra = (char.level or "?") .. "   " .. (char.realm or "")
    if char.mine then
        extra = extra .. "   (you)"
    elseif type(char.seen) == "number" then
        extra = extra .. "   " .. date("%m/%d %H:%M", char.seen)
    end
    return who .. "   " .. ns.Color("muted", extra)
end

local function JoinMuted(parts)
    if #parts == 0 then return end
    return "    " .. ns.Color("muted", table.concat(parts, "   "))
end

local function SheetLine(char)
    local parts = {}
    if type(char.durability) == "number" then
        parts[#parts + 1] = char.durability .. "% durability"
    end
    return JoinMuted(parts)
end

local function RestLine(char)
    local parts = {}
    if type(char.xpMax) == "number" and char.xpMax > 0 and type(char.xp) == "number" then
        parts[#parts + 1] = BreakUpLargeNumbers(char.xp) .. "/"
            .. BreakUpLargeNumbers(char.xpMax) .. " XP"
    end
    if type(char.rested) == "number" and char.rested > 0 then
        parts[#parts + 1] = "rested " .. BreakUpLargeNumbers(char.rested)
    end
    return JoinMuted(parts)
end

local function AltHourLine(char)
    local IT = ns.InstanceTracker
    local count = char.hour or 0
    local text = string.format("This hour: %d of %d", count, IT.HOURLY_CAP)
    if count > 0 then
        text = text .. "   next frees in " .. IT.Duration(char.hourFrees or 0)
    end
    local left = IT.HOURLY_CAP - count
    if count > 0 and left <= IT.WarnDistance() then
        text = HourPaint(left, text)
    else
        text = ns.Color("muted", text)
    end
    return "    " .. text
end

local function RunLine(run)
    local IT = ns.InstanceTracker
    local span = IT.Duration((run.left or run.entered or 0) - (run.entered or 0))
    local when = date("%m/%d %H:%M", run.entered or time())
    local who = ns.ClassColoredName(run.name or "?", run.class)
    local text = string.format("%s   %s   %s   %s   %s   %s XP", when, who,
        IT.PlaceName(run.instance, run.difficulty), span, IT.Coins(run.loot),
        BreakUpLargeNumbers(run.xp or 0))
    if (run.deaths or 0) > 0 then
        local word = run.deaths == 1 and "death" or "deaths"
        text = text .. "   " .. ns.Color("muted", run.deaths .. " " .. word)
    end
    return text
end

-- Reputation gained during the visit. The words come from the tracker; this only
-- indents them as a second line. Left out when none was gained.
local function RepText(rep)
    local text = ns.InstanceTracker.Reputation(rep)
    if not text then return end
    return "    " .. ns.Color("muted", text)
end

local function RepLine(parent, y, rep)
    local text = RepText(rep)
    if not text then return y end
    return WrapLine(parent, y, text)
end

-- Other people kept on the visit. This character is already named on the line.
local function GroupCount(group)
    if type(group) ~= "table" then return 0 end
    local n = 0
    for i = 1, #group do
        local member = group[i]
        if type(member) == "table" and type(member.name) == "string" and member.name ~= "" then
            n = n + 1
        end
    end
    return n
end

-- One name a line, in class color. A paragraph of names is what made the page tall.
local function GroupTip(group)
    if type(group) ~= "table" then return end
    local lines = {}
    for i = 1, #group do
        local member = group[i]
        if type(member) == "table" and type(member.name) == "string" and member.name ~= "" then
            lines[#lines + 1] = ns.ClassColoredName(member.name, member.class)
        end
    end
    if #lines == 0 then return end
    return table.concat(lines, "\n")
end

local function ShowGroup(row)
    local text = GroupTip(row.group)
    if not text then return end
    UI.ShowWidgetTooltip(row, text, { anchor = "cursor", justify = "LEFT" })
end

-- A visit. The facts stay on the left. How many other people were there sits on the right,
-- and pointing at the row lists them. A visit with no one else is an ordinary line.
local function VisitLine(parent, y, text, group)
    if UI.searchScan then return y - LINE_H end
    local row = UI.Keep(parent, "visit", function(p)
        local f = CreateFrame("Frame", nil, p)
        f:SetHeight(LINE_H)
        f.text = ns.Font(f, LINE_FONT, nil, T.fg)
        f.text:SetJustifyH("LEFT")
        f.text:SetWordWrap(false)
        f.count = ns.Font(f, LINE_FONT, nil, T.muted)
        f.count:SetPoint("RIGHT", -LINE_INSET, 0)
        f.count:SetJustifyH("RIGHT")
        f.hover = ns.Solid(f, "BACKGROUND", T.fg, HOVER)
        f.hover:SetAllPoints()
        f.hover:Hide()
        f:SetScript("OnEnter", function(self)
            self.hover:Show()
            ShowGroup(self)
        end)
        f:SetScript("OnLeave", function(self)
            self.hover:Hide()
            UI.HideWidgetTooltip()
        end)
        return f
    end)
    local n = GroupCount(group)
    row.group = n > 0 and group or nil
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.CONTENT_PAD, y)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -UI.CONTENT_PAD, y)
    row:SetHeight(LINE_H)
    row.text:SetFont(UI.FontPath(""), LINE_FONT, "")
    row.text:SetTextColor(T.fg.r, T.fg.g, T.fg.b, 1)
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", LINE_INSET, 0)
    row.text:SetText(text)
    row.count:SetFont(UI.FontPath(""), LINE_FONT, "")
    row.count:SetTextColor(T.muted.r, T.muted.g, T.muted.b, 1)
    if n > 0 then
        row.count:SetText("with " .. n)
        row.count:Show()
        row.text:SetPoint("RIGHT", row.count, "LEFT", -COUNT_GAP, 0)
        row:EnableMouse(true)
        if row:IsMouseOver() then
            row.hover:Show()
            ShowGroup(row)
        else
            row.hover:Hide()
        end
    else
        row.count:Hide()
        row.text:SetPoint("RIGHT", -LINE_INSET, 0)
        row:EnableMouse(false)
        row.hover:Hide()
        if row:IsMouseOver() then UI.HideWidgetTooltip() end
    end
    return y - LINE_H
end

function ns.BuildInstanceLockoutsPage(parent, y)
    local W, IT = UI.Widgets, ns.InstanceTracker
    local _, h
    _, h = W:Note(parent, OffText()
        .. "Saved lockouts come from the game's instance list. New dungeon and raid instances "
        .. "on this character count toward a 10-per-hour cap. Another character has their own 10. "
        .. "Walking back into one you have not reset does not count. The chat warning is set "
        .. "under Instance Tracker settings.", y); y = y - h
    _, h = W:SectionHeader(parent, "THIS HOUR", y); y = y - h

    local count, cap, frees = IT.Hour()
    local summary = string.format("Instances this hour: %d of %d", count, cap)
    if count > 0 then summary = summary .. "   next frees in " .. IT.Duration(frees) end
    local left = cap - count
    if count > 0 and left <= IT.WarnDistance() then
        summary = HourPaint(left, summary)
    end
    y = Line(parent, y, summary)
    local hourRows = IT.HourEntries()
    if #hourRows == 0 then
        _, h = W:Note(parent, "No new instances this hour.", y); y = y - h
    else
        for i = 1, #hourRows do
            local row = hourRows[i]
            y = Line(parent, y, string.format("%s   frees in %s", row.name or "",
                IT.Duration(IT.EntryLeft(row))))
        end
        y = y - GROUP_GAP
    end
    local chars = ns.InstanceTracker.Characters()
    local listed = {}
    for i = 1, #chars do
        if chars[i].guid then listed[chars[i].guid] = true end
    end
    local others = IT.HourOthers()
    local stray = {}
    for i = 1, #others do
        local row = others[i]
        if not listed[row.guid] then stray[#stray + 1] = row end
    end
    if #stray > 0 then
        _, h = W:Note(parent, "Other characters, each with their own 10 this hour. "
            .. "Turn on Track Alts to see their saved instances and character sheet.", y); y = y - h
        for i = 1, #stray do
            local row = stray[i]
            local who = row.who ~= "" and row.who or "?"
            if type(row.realm) == "string" and row.realm ~= "" then
                who = who .. "   " .. ns.Color("muted", row.realm)
            end
            local countText = string.format("%d of %d   next frees in %s",
                row.count, cap, IT.Duration(IT.EntryLeft(row)))
            local leftOthers = cap - row.count
            if row.count > 0 and leftOthers <= IT.WarnDistance() then
                countText = HourPaint(leftOthers, countText)
            end
            y = Line(parent, y, who .. "   " .. countText)
        end
        y = y - GROUP_GAP
    end

    _, h = W:SectionHeader(parent, "CHARACTERS", y); y = y - h
    _, h = W:Note(parent, "A character shows up here after you log into it with Instance Tracker on. "
        .. "Track Alts shows the others: rested experience, durability and saved "
        .. "instances, from the last time that character was logged in. "
        .. "Reset times are from when this page was opened.", y); y = y - h

    if #chars == 0 then
        _, h = W:Note(parent, "No characters recorded yet.", y); y = y - h
        return y
    end
    for i = 1, #chars do
        local char = chars[i]
        y = Line(parent, y, CharLine(char))
        local sheet = SheetLine(char)
        if sheet then y = Line(parent, y, sheet) end
        local rest = RestLine(char)
        if rest then y = Line(parent, y, rest) end
        if not char.mine then y = Line(parent, y, AltHourLine(char)) end
        for n = 1, #char.lockouts do
            y = Line(parent, y, "    " .. LockLine(char.lockouts[n]))
        end
        y = y - GROUP_GAP
    end
    return y
end

function ns.BuildInstanceHistoryPage(parent, y)
    local W, IT = UI.Widgets, ns.InstanceTracker
    local _, h
    _, h = W:Note(parent, OffText()
        .. "Each dungeon or raid visit while Instance Tracker is on: how long you were "
        .. "inside, the coins you looted and the experience you gained. Reputation gained "
        .. "is listed under the visit. Who else was in the group is a count on the right; "
        .. "point at the line for the names. Coming back to the same group within "
        .. "the hour, before you reset it, continues that visit, and the time outside "
        .. "is not counted. Other characters stay saved, and show here when Track Alts is on. "
        .. "Repairs and vendor sales are not counted. "
        .. "Older visits drop off the end of the list.", y); y = y - h
    _, h = W:Button(parent, "Clear History", y, function()
        ns.Confirm(ns.L("Clear instance history? Lockouts are kept."), function()
            IT.ClearHistory()
            UI:RefreshPage(true)
        end)
    end); y = y - h
    _, h = W:SectionHeader(parent, "VISITS", y); y = y - h

    local open = IT.Open()
    if open and open.instance then
        local elapsed = IT.Duration(IT.Elapsed(open))
        y = VisitLine(parent, y, "In progress   " .. ns.ClassColoredName(open.name or "?", open.class)
            .. "   " .. IT.PlaceName(open.instance, open.difficulty) .. "   " .. elapsed
            .. "   " .. IT.Coins(open.loot) .. "   " .. BreakUpLargeNumbers(open.xp or 0) .. " XP",
            open.group)
        y = RepLine(parent, y, open.rep)
        y = y - GROUP_GAP
    end

    local runs = IT.Runs()
    if #runs == 0 and not open then
        _, h = W:Note(parent, "No visits recorded yet.", y); y = y - h
        return y
    end
    local shown = math.min(#runs, IT.PAGE_RUNS)
    for i = 1, shown do
        y = VisitLine(parent, y, RunLine(runs[i]), runs[i].group)
        y = RepLine(parent, y, runs[i].rep)
    end
    if #runs > shown then
        _, h = W:Note(parent, "Showing the latest " .. shown .. " of " .. #runs .. ".", y)
        y = y - h
    end
    return y
end

-------------------------------------------------------------------------------
--  Settings. One page in the options window. The lists live in the module window.
-------------------------------------------------------------------------------
local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end

local OFF = "Turn on Instance Tracker"
local WHERE = { { self = "Your Chat", group = "Group" }, { "self", "group" } }
local RAID_WHY = "Choose Group above"

local function Enabled()
    return S.Get("enabled") == true
end

local function Row(key, label, help)
    return { key = key, label = label, toggle = true, needs = Enabled, why = OFF, help = help }
end

-- needs updates why before the row reads it: the module, then Group.
local raid = Row("leavePrintRaid", "Send to Raid Chat", "Sends the summary to raid chat.")
raid.needs = function()
    if not Enabled() then
        raid.why = OFF
        return false
    end
    raid.why = RAID_WHY
    return S.Get("leaveWhere") == "group"
end

local function Headline()
    local IT = ns.InstanceTracker
    if not IT.Enabled() then return "Instance Tracker is off" end
    local open = IT.Open()
    if open and open.instance then return "In " .. IT.PlaceName(open.instance, open.difficulty) end
    local count, cap = IT.Hour()
    return string.format("%d of %d instances this hour", count, cap)
end

local function Detail()
    local IT = ns.InstanceTracker
    if not IT.Enabled() then return "Turn it on to record lockouts and visits." end
    local open = IT.Open()
    if open and open.instance then return IT.Duration(IT.Elapsed(open)) .. " in this visit." end
    local count, _, frees = IT.Hour()
    if count > 0 then return "The next one frees in " .. IT.Duration(frees) .. "." end
    return "No new instances this hour."
end

local function LeaveSummary(store)
    return store.Get("leaveWhere") == "group" and "Sent to the group" or "Your chat only"
end

local function WindowSummary(store)
    return ("%d%% opacity"):format(math.floor((store.Get("windowAlpha") or 1) * 100 + 0.5))
end

local page = Settings.Page("Instance Tracker/Settings", S)

page:Window({
    text = "Open Instance Tracker",
    open = function() ns.OpenInstanceTrackerWindow() end,
    headline = Headline,
    detail = Detail,
})

page:Card({
    id = "hour", name = "This Hour", order = 10,
    help = "Warns in chat as you near the hourly instance cap.",
    rows = {
        { key = "hourlyWarn", label = "Warn when this many are left", slider = { 1, 5, 1 },
          needs = Enabled, why = OFF, help = "How close to the cap before chat warns you." },
    },
})

page:Card({
    id = "timer", name = "Run Timer", order = 20, switch = "showFrame",
    help = "Time, coins and experience while you are inside.",
    summary = function() return "Inside a dungeon or raid" end,
})

page:Card({
    id = "enter", name = "Chat on Enter", order = 30, switch = "enterChat",
    help = "Prints in your chat when you enter an instance.",
    summary = function() return "Your chat only" end,
})

page:Card({
    id = "alts", name = "Track Alts", order = 40, switch = "trackAlts",
    help = "Shows your other characters' lockouts and visits.",
    summary = function() return "Other characters stay listed" end,
})

page:Card({
    id = "leave", name = "When You Leave", order = 50, switch = "leaveChat",
    help = "Prints a summary when you leave a dungeon.",
    summary = LeaveSummary,
    rows = {
        Settings.Group("Where"),
        { key = "leaveWhere", label = "Send It To", choice = WHERE, needs = Enabled, why = OFF,
          help = "Your chat, or the group when you are in one." },
        raid,
        Settings.Group("Included"),
        Row("leaveTime", "Show Time", "How long the visit lasted."),
        Row("leaveXP", "Show Experience", "Experience gained during the visit."),
        Row("leaveXPHour", "Show XP/Hour", "Experience per hour for this visit."),
        Row("leaveGold", "Show Coins Looted", "Coins looted during the visit."),
        Row("leaveDeaths", "Show Deaths", "How many times you died."),
        Row("leaveRep", "Show Reputation", "Reputation gained while inside."),
        Row("leaveAverage", "Show Average Experience", "Average experience from visits to this instance."),
        Row("leaveRunsLevel", "Show Runs This Level", "Visits recorded at your current level."),
        Row("leaveRunsToLevel", "Show Runs to Next Level", "A rough count of visits until you level."),
        Row("leaveActivity", "Skip If Nothing Happened", "Skips the summary when the visit gained nothing."),
        Row("leaveRaids", "Include Raids", "Also prints the summary when you leave a raid."),
    },
})

page:Card({
    id = "reset", name = "When You Reset", order = 60, switch = "resetChat",
    help = "As group leader, posts the reset in group chat.",
    summary = function() return "Posted in group chat" end,
})

page:Card({
    id = "window", name = "Window", order = 90,
    help = "The lockouts and visit list, in their own window.",
    summary = WindowSummary,
    rows = {
        { key = "windowAlpha", label = "Window Opacity", slider = { ns.Shared.Style.OPACITY_MIN, 100, 5 },
          unit = "%", scale = 0.01, help = "How solid the window is, in percent." },
    },
})
