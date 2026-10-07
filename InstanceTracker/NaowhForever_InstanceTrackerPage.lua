-------------------------------------------------------------------------------
--  NaowhForever_InstanceTrackerPage.lua -- Lockouts, History and Display pages.
--  The rows are reused with the rest of the options window; opening a page only reads
--  what the tracker has already stored.
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
        .. "on the Display tab.", y); y = y - h
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

function ns.BuildInstanceTrackerPage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, "Turn Instance Tracker on with the switch at the top of this page. While it is on, lockouts and visits "
        .. "are recorded, and each new dungeon or raid instance on this character counts toward 10 per hour. "
        .. "Show Run Timer and Chat on Enter stay off until you turn them on. "
        .. "Chat on Leave is under When You Leave, and each of its lines starts off. "
        .. "Chat on Reset is under When You Reset, and it starts off. "
        .. "Move the timer in Unlock Mode; it shows only inside a dungeon or raid.",
        y); y = y - h
    _, h = W:SectionHeader(parent, "THIS HOUR", y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("hourlyWarn", "Warn when this many are left", 1, 5, 1,
            "Prints in your chat when this many new instances are left before this character's "
            .. "10-per-hour cap. 1 warns at 9 of 10. 5 warns at 5 of 10.",
            "enabled"),
        { type = "label", text = "The cap is 10 for this character" }
    ); y = y - h
    _, h = W:SectionHeader(parent, "ON SCREEN", y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("showFrame", "Show Run Timer",
            "Time, coins looted, experience, experience per hour, "
            .. "and instances entered this hour, while you are inside. Move it in Unlock Mode.",
            "enabled"),
        S.Toggle("enterChat", "Chat on Enter",
            "Prints in your chat when you enter: the instance, your last visit, and whether you are already saved. "
            .. "Coming back to one you have not reset says you resumed it. This is never sent to the group.",
            "enabled")
    ); y = y - h
    _, h = W:SectionHeader(parent, "ALTS", y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("trackAlts", "Track Alts",
            "Keep every character you log into on this account: saved instances, visits, "
            .. "rested experience and durability. Log each one once with the tracker on. "
            .. "Off hides the others until you turn this back on. "
            .. "Each character still has their own 10 per hour, and that count is kept either way.",
            "enabled"),
        { type = "label", text = "Off hides other characters" }
    ); y = y - h
    _, h = W:SectionHeader(parent, "WHEN YOU LEAVE", y); y = y - h
    _, h = W:Note(parent, "Choose what to say when you leave a dungeon. Nothing is sent until Chat on Leave "
        .. "is on, and each detail stays off until you check it. Your Chat prints it only for you. "
        .. "Group sends it to party chat, and to raid chat only when Send to Raid Chat is on. "
        .. "A raid is left out until Include Raids is on. Kill counts are not available, "
        .. "because the combat log is closed.",
        y); y = y - h

    local function Leave(key, text, tip)
        local cfg = S.Toggle(key, text, tip)
        cfg.disabled = function()
            return not S.Get("enabled") or not S.Get("leaveChat")
        end
        return cfg
    end

    local where = S.Dropdown("leaveWhere", "Send It To",
        { self = "Your Chat", group = "Group" },
        { "self", "group" },
        "Your Chat prints the summary only for you. Group sends it to party chat. "
        .. "In a raid it is printed to you unless Send to Raid Chat is on. Alone, it is printed to you.")
    where.setValue = function(v)
        S.Set("leaveWhere", v)
        UI:RefreshPage(true)
    end
    where.disabled = function()
        return not S.Get("enabled") or not S.Get("leaveChat")
    end
    local raidChat = S.Toggle("leavePrintRaid", "Send to Raid Chat",
        "With Group selected, send the summary to raid chat. Otherwise it is printed to you "
        .. "while you are in a raid.")
    raidChat.disabled = function()
        return not S.Get("enabled") or not S.Get("leaveChat") or S.Get("leaveWhere") ~= "group"
    end

    _, h = W:DualRow(parent, y,
        S.Toggle("leaveChat", "Chat on Leave",
            "Print a summary when you leave. Nothing is included until you check it below.",
            "enabled"),
        where
    ); y = y - h
    _, h = W:DualRow(parent, y,
        Leave("leaveTime", "Show Time", "How long the visit lasted."),
        Leave("leaveXP", "Show Experience", "Experience gained during the visit.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        Leave("leaveXPHour", "Show XP/Hour",
            "Experience per hour for this visit. The first minute counts as a full minute."),
        Leave("leaveGold", "Show Coins Looted",
            "Coins looted during the visit. Repairs and vendor sales are not counted.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        Leave("leaveDeaths", "Show Deaths", "How many times you died during the visit."),
        Leave("leaveRep", "Show Reputation",
            "Reputation gained while inside, from the faction lines in chat.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        Leave("leaveAverage", "Show Average Experience",
            "Average experience from this character's recorded visits to this same instance, including this one."),
        Leave("leaveRunsLevel", "Show Runs This Level",
            "How many visits this character has recorded at the current level, including this one.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        Leave("leaveRunsToLevel", "Show Runs to Next Level",
            "A rough count from the experience this visit gained and what you still need. "
            .. "Left out at max level, or when this visit gained none."),
        Leave("leaveActivity", "Skip If Nothing Happened",
            "Skip the summary when the visit gained no experience, coins, reputation or deaths.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        Leave("leaveRaids", "Include Raids",
            "Also print the summary when you leave a raid. Off means dungeons only."),
        raidChat
    ); y = y - h

    _, h = W:SectionHeader(parent, "WHEN YOU RESET", y); y = y - h
    _, h = W:Note(parent, "As group leader, a reset can be announced in party, raid, or instance chat. "
        .. "Nothing is typed there until Chat on Reset is on. "
        .. "Nova Instance Tracker users in the group still hear about the reset. "
        .. "If you also have Nova Instance Tracker loaded, it announces, and this line is left out "
        .. "so the group does not see it twice.",
        y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("resetChat", "Chat on Reset",
            "As group leader, post the reset in party, raid, or instance chat. "
            .. "Off still tells Nova Instance Tracker users in the group. "
            .. "Left out when Nova Instance Tracker is loaded, so the line is not posted twice.",
            "enabled"),
        { type = "label", text = "Off until you turn it on" }
    ); y = y - h
    return y
end
