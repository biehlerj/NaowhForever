-- Reminder.lua: the Tracking Reminder row, one secure icon per missing racial or class tracking.
local ns = _G.NaowhForever

local GetNumTrackingTypes = C_Minimap.GetNumTrackingTypes
local GetTrackingInfo = C_Minimap.GetTrackingInfo
local IsSpellKnown = C_SpellBook.IsSpellKnown
local GetSpellTexture = C_Spell.GetSpellTexture

local T = ns.THEME
local UI = ns.UI
local Parts = ns.Shared.Parts
local St = ns.Shared.Style

local TR = ns.TrackingReminder
local S = TR.Settings
local D = TR.Data

local CROP = St.ICON_CROP
local LABEL_SIZE = 13
local LABEL_GAP = 4
local ICON_GAP = 4
local HIGHLIGHT_ALPHA = 0.15
local HOME_X, HOME_Y = 260, 170
local FRAME_NAME = "NaowhForeverTrackingReminder"
local MOVER_LABEL = "Tracking Reminder"
local CARD = TR.PAGE .. ":tracking"
local EVENTS = { "MINIMAP_UPDATE_TRACKING", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB",
    "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD",
    "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED" }
local REFRESH = {
    enabled = true, trackRacial = true, trackClass = true, racialPicks = true, classPicks = true,
    inInstances = true, iconSize = true, trackingFont = true, trackingFontSize = true, trackingOutline = true,
}

local row, unlocked, pending
local buttons = {}
local shown = {}
local events = CreateFrame("Frame")

local Look = {}
TR.Look = Look

local function Tracking(spellID)
    for i = 1, GetNumTrackingTypes() do
        local info, _, active, _, _, id = GetTrackingInfo(i)
        if type(info) == "table" then
            if info.spellID == spellID then return info.active == true end
        elseif id == spellID then
            return active == true
        end
    end
    return false
end

local function AddKnown(list, picks, token, field, includeActive)
    for i = 1, #list do
        local t = list[i]
        if t[field] == token and picks[t.key] ~= false and IsSpellKnown(t.spell) then
            if includeActive or not Tracking(t.spell) then
                shown[#shown + 1] = t
            end
        end
    end
end

local function Collect(includeActive)
    wipe(shown)
    local _, race = UnitRace("player")
    local _, class = UnitClass("player")
    if S.Get("trackRacial") then AddKnown(D.RACIAL, S.Get("racialPicks"), race, "race", includeActive) end
    if S.Get("trackClass") then AddKnown(D.CLASS, S.Get("classPicks"), class, "class", includeActive) end
    return shown
end

local function Suppressed()
    if UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then return true end
    return IsInInstance() and not S.Get("inInstances")
end

local function OnEnter(self)
    local spell = self.spell
    if not spell then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetSpellByID(spell)
    GameTooltip:Show()
end

function Look.New(frame)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints()
    frame.icon:SetTexCoord(CROP, 1 - CROP, CROP, 1 - CROP)
    ns.Border(frame, St.BORDER_RGB)
    frame.label = ns.Font(frame, LABEL_SIZE, "OUTLINE", T.accentSoft)
    frame.label:SetPoint("TOP", frame, "BOTTOM", 0, -LABEL_GAP)
end

function Look.Fill(frame, size, texture, text)
    frame:SetSize(size, size)
    frame.icon:SetTexture(texture)
    Parts.HudFont(frame.label, S.Get("trackingFont"), S.Get("trackingFontSize"), S.Get("trackingOutline"))
    frame.label:SetText(text)
end

local function GetButton(i)
    local button = buttons[i]
    if button then return button end
    button = CreateFrame("Button", nil, row, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyUp")
    Look.New(button)
    button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.highlight:SetAllPoints()
    button.highlight:SetColorTexture(1, 1, 1, HIGHLIGHT_ALPHA)
    button:SetScript("OnEnter", OnEnter)
    button:SetScript("OnLeave", GameTooltip_Hide)
    buttons[i] = button
    return button
end

local function SavePosition(pos)
    S.Set("trackingPos", pos)
end

local function Build()
    row = CreateFrame("Frame", FRAME_NAME, UIParent)
    row:SetMovable(true)
    row:SetClampedToScreen(true)
    row.mover = UI.AttachMover(row, MOVER_LABEL, SavePosition, TR.PAGE, CARD)
    row:Hide()
end

local function Place()
    local pos = S.Get("trackingPos")
    row:ClearAllPoints()
    if pos then
        row:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        row:SetPoint("CENTER", UIParent, "CENTER", HOME_X, HOME_Y)
    end
end

local function ShowRow(list)
    local size = S.Get("iconSize")
    local n = #list
    for i = 1, n do
        local t = list[i]
        local button = GetButton(i)
        button.spell = t.spell
        button:SetAttribute("type1", "spell")
        button:SetAttribute("spell1", t.spell)
        Look.Fill(button, size, GetSpellTexture(t.spell), t.label)
        button:ClearAllPoints()
        button:SetPoint("LEFT", row, "LEFT", (i - 1) * (size + ICON_GAP), 0)
        button:Show()
    end
    for i = n + 1, #buttons do
        local button = buttons[i]
        button.spell = nil
        button:SetAttribute("spell1", nil)
        button:Hide()
    end
    row:SetSize(n > 0 and n * size + (n - 1) * ICON_GAP or size, size)
    row:Show()
end

local function Update(event)
    if not row then return end
    if event == "PLAYER_REGEN_DISABLED" then
        row:Hide()
        return
    end
    if InCombatLockdown() then return end
    local list = Collect(unlocked)
    if unlocked or (TR.On() and #list > 0 and not Suppressed()) then
        ShowRow(list)
    else
        row:Hide()
    end
end

local function Apply()
    if InCombatLockdown() then
        pending = true
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    events:UnregisterAllEvents()
    if not (TR.On() or unlocked) then
        if row then row:Hide() end
        return
    end
    if not row then Build() end
    Place()
    row.mover:SetShown(unlocked == true)
    for i = 1, #EVENTS do events:RegisterEvent(EVENTS[i]) end
    Update()
end

local function OnEvent(_, event)
    if event == "PLAYER_REGEN_ENABLED" and pending then
        pending = nil
        return Apply()
    end
    Update(event)
end

local function OnSettingChanged(key)
    if REFRESH[key] then Apply() end
end

local function OnUnlock()
    unlocked = TR.On() == true
    Apply()
end

local function OnLock()
    unlocked = false
    Apply()
end

events:SetScript("OnEvent", OnEvent)
S.OnChange(OnSettingChanged)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowUnlockMode", OnUnlock)
hooksecurefunc(ns, "HideUnlockMode", OnLock)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

boot:SetScript("OnEvent", Apply)
