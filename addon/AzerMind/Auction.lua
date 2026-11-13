-- Optional, local integration with AHledger. No network or persistent price cache.
local function Money(value, compact)
    if type(value) ~= "number" or value < 0 or value ~= value or value == math.huge then return nil end
    value = math.floor(value)
    if compact then
        local gold, silver, copper = math.floor(value / 10000), math.floor(value / 100) % 100, value % 100
        local parts = {}
        if gold > 0 then parts[#parts+1] = gold .. "g" end
        if silver > 0 then parts[#parts+1] = silver .. "s" end
        if copper > 0 or #parts == 0 then parts[#parts+1] = copper .. "c" end
        return table.concat(parts, " ")
    end
    return string.format("%dg %ds %dc", math.floor(value / 10000), math.floor(value / 100) % 100, value % 100)
end

function AzerMind.AuctionItemDetails(item, compact)
    local api = AHledgerAPI
    if type(api) ~= "table" or type(api.GetPrice) ~= "function" then return nil end
    local ok, price = pcall(api.GetPrice, item)
    if not ok or type(price) ~= "table" then return nil end
    local median, buyout = Money(price.median, compact), Money(price.minBuyout, compact)
    if not median and not buyout then return nil end
    local updated = tonumber(price.updated)
    local observed = updated and updated > 0 and updated < 32503680000 and date("%Y-%m-%d %H:%M", updated) or "unknown"
    if compact then
        local prices = {}
        if buyout then prices[#prices+1] = "Min " .. buyout end
        if median then prices[#prices+1] = "Median " .. median end
        return table.concat({"Auction / unit: " .. table.concat(prices, " · "),
            (price.snapshot and "Bundled snapshot · " or "Last scan · ") .. observed,
            "Prices from AHledger (ahledger.com)", "Hold Shift for details"}, "\n")
    end
    local lines = {"Auction prices (per unit): " .. (buyout and ("minimum " .. buyout) or "minimum unknown") ..
        (median and ("; median " .. median) or "")}
    if type(price.quantity) == "number" then lines[#lines+1] = "Listed quantity: " .. tostring(price.quantity) end
    lines[#lines+1] = "Market: " .. tostring(price.market or "unknown")
    lines[#lines+1] = "Observed: " .. observed ..
        (price.snapshot and " (bundled snapshot; not live)" or " (latest available scan; not a sale guarantee)")
    lines[#lines+1] = "Prices from AHledger (ahledger.com)"
    return table.concat(lines, "\n")
end
