-- Run with Lua 5.1 from the repository root: the price chart on The Market's Sell page. It sits under the listings in
-- the full window, where Up Next is a column of its own and there is height for it, and follows the item in front of
-- you; the docked panel has no chart.

local checks = 0
local function Check(label, value) assert(value, label); checks = checks + 1 end

local Page = dofile("Tools/regression/market_sell_page.lua")
local Stack, COMMODITY = Page.Stack, Page.COMMODITY

local ORE, CLOTH = 2770, 2589

local t = Page.Setup({ bags = { [0] = { Stack(ORE, 20), Stack(CLOTH, 10) } },
    status = { [ORE] = COMMODITY, [CLOTH] = COMMODITY }, scan = { [ORE] = 500, [CLOTH] = 100 },
    vendor = { [ORE] = 5, [CLOTH] = 3 } })
local chart = t.charts[1]

local function Resize(width)
    t.pageFrame.width = width
    t.pageFrame.scripts.OnSizeChanged(t.pageFrame)
end

t.page.Show()
Check("Sell builds one chart", #t.charts == 1)
Check("on the docked panel there is no chart", not chart.shown)
Resize(648)
Check("nor on the docked panel made wide", not chart.shown)

t.page.Hide()
t.covering = true
Resize(1120)
t.page.Show()
Check("in the full window the chart shows", chart.shown)
Check("and it draws the item in front of you", chart.item == ORE)
t.skip.click()
Check("skipping draws the next item", chart.shown and chart.item == CLOTH)
Resize(360)
Check("in the full window but without the column, there is no chart", not chart.shown)
Resize(1120)
Check("and with the column again it is back", chart.shown)

t.bags[0] = {}
t.Fire("BAG_UPDATE_DELAYED")
t.RunTimers()
Check("with nothing left to sell the chart goes", not chart.shown)

t.page.Hide()
t.covering = false
Resize(360)
t.page.Show()
Check("back on the docked panel the chart goes", not chart.shown)

print("market sell chart: " .. checks .. " checks passed")
