-- The run timer, the settings and the lists sit on the shared surfaces.
-- From the repo root:
--   lua5.1 Tools/regression/test-instance-tracker-ui.lua
local function Read(path)
    local f = assert(io.open(path, "rb"))
    local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return source
end

local cases = 0
local function Check(ok, why)
    assert(ok, why)
    cases = cases + 1
end

local toc = Read("NaowhForever.toc")
local moduleToc = Read("NaowhForever_InstanceTracker/NaowhForever_InstanceTracker.toc")
local window = Read("Core/NaowhForever_Window.lua")
local tracker = Read("NaowhForever_InstanceTracker/NaowhForever_InstanceTracker.lua")
local page = Read("NaowhForever_InstanceTracker/NaowhForever_InstanceTrackerPage.lua")
local lists = Read("NaowhForever_InstanceTracker/NaowhForever_InstanceTrackerWindow.lua")

Check(toc:find("NaowhForever_InstanceTracker.lua", 1, true) == nil,
    "the core toc does not load the tracker")
Check(moduleToc:match("## Interface:[^%c]*") == toc:match("## Interface:[^%c]*")
    and moduleToc:match("## Version:[^%c]*") == toc:match("## Version:[^%c]*"),
    "its TOC matches the core Interface and Version")
Check(moduleToc:find("## Dependencies: NaowhForever", 1, true) ~= nil
    and moduleToc:find("## Group: NaowhForever", 1, true) ~= nil,
    "the module depends on NaowhForever and is grouped with it")
local tocAt = moduleToc:find("NaowhForever_InstanceTracker.lua", 1, true)
local pageAt = moduleToc:find("NaowhForever_InstanceTrackerPage.lua", 1, true)
local windowAt = moduleToc:find("NaowhForever_InstanceTrackerWindow.lua", 1, true)
Check(tocAt and pageAt and windowAt and tocAt < pageAt and pageAt < windowAt,
    "tracker, then its page, then its window")

Check(tracker:find("Parts.TrackerPanel(", 1, true) ~= nil, "the timer is a tracker panel")
Check(tracker:find('page = SETTINGS_PAGE, card = TIMER_CARD', 1, true) ~= nil,
    "the cog opens the Run Timer card")
Check(tracker:find('SETTINGS_PAGE = "Instance Tracker/Settings"', 1, true) ~= nil,
    "the mover opens the settings page")
Check(tracker:find("CreateFrame(\"Frame\", \"NaowhForeverInstanceTracker\"", 1, true) == nil,
    "the hand-built timer frame is gone")

Check(page:find('Settings.Page("Instance Tracker/Settings"', 1, true) ~= nil,
    "settings are a shared settings page")
Check(page:find('id = "timer"', 1, true) and page:find('switch = "showFrame"', 1, true),
    "Run Timer is the showFrame card")
Check(page:find("function ns.BuildInstanceTrackerPage", 1, true) == nil,
    "the hand-built Display page is gone")
Check(page:find("function ns.BuildInstanceHourPage", 1, true) ~= nil
    and page:find("function ns.BuildInstanceHistoryPage", 1, true) ~= nil,
    "the list builders stay for the module window")

local helps = 0
local function Help(help)
    helps = helps + 1
    Check(#help < 100, "help under 100 characters: " .. help)
    Check(help:find("%.%s") == nil, "help is one sentence: " .. help)
end
for help in page:gmatch('help = "([^"]*)"') do Help(help) end
for help in page:gmatch('Row%b()') do
    local text = help:match(', "([^"]+)"%s*%)$')
    if text then Help(text) end
end
Check(helps >= 20, "the settings cards carry help")

Check(lists:find("Parts.Window(", 1, true) ~= nil, "the lists sit in a module window")
Check(lists:find("BuildInstanceHourPage", 1, true) ~= nil
    and lists:find("BuildInstanceHistoryPage", 1, true) ~= nil,
    "This Hour and History are the window's tabs")
Check(lists:find("function ns.ToggleInstanceTrackerWindow", 1, true) ~= nil,
    "the slash command can open the window")

Check(window:find('addon = "NaowhForever_InstanceTracker"', 1, true) ~= nil,
    "the module is its own addon")
Check(Read(".pkgmeta"):find("NaowhForever/NaowhForever_InstanceTracker: NaowhForever_InstanceTracker", 1, true) ~= nil,
    "packaged beside the core")
Check(window:find('name = "Instance Tracker"[^}]-open = "ToggleInstanceTrackerWindow"', 1) ~= nil,
    "the module opens its own window")
Check(window:find('open = "ToggleInstanceTrackerWindow"[^}]-name = "Settings"', 1) ~= nil,
    "options keeps a settings tab")
Check(window:find("BuildInstanceHourPage", 1, true) == nil
    and window:find("BuildInstanceHistoryPage", 1, true) == nil
    and window:find("BuildInstanceTrackerPage", 1, true) == nil,
    "the lists are not options tabs")

print("OK " .. cases .. " instance tracker UI checks")
