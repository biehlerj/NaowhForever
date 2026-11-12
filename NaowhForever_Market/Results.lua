-- Results.lua: what the auction house's last browse search found, however it was sent, and more of it as you scroll (Market.Results).
local ns = _G.NaowhForever

local Market = ns.Market

local EVENTS = { "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
    "AUCTION_HOUSE_BROWSE_FAILURE" }

local list = {}
local events, moreAsked

local Results = { list = list }
Market.Results = Results

local function OnEvent(_, event, added)
    if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
        wipe(list)
        for i, result in ipairs(C_AuctionHouse.GetBrowseResults()) do list[i] = result end
        Results.searching, Results.searched, moreAsked = false, true, false
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        for _, result in ipairs(added) do list[#list + 1] = result end
        moreAsked = false
    else
        Results.searching, moreAsked = false, false
    end
    if Results.onChange then Results.onChange() end
end

function Results.Sent()
    wipe(list)
    Results.searching, moreAsked = true, false
end

function Results.More()
    if moreAsked or Results.searching or not Results.searched or C_AuctionHouse.HasFullBrowseResults() then return end
    moreAsked = true
    C_AuctionHouse.RequestMoreBrowseResults()
end

function Results.Start()
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    for _, event in ipairs(EVENTS) do events:RegisterEvent(event) end
end

function Results.Stop()
    if events then events:UnregisterAllEvents() end
    moreAsked = false
end
