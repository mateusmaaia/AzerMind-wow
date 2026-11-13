-- Optional, local integration with AHledger. No network or persistent price cache.
local function Money(value)
    if type(value) ~= "number" or value < 0 or value ~= value or value == math.huge then return nil end
    value = math.floor(value)
    return string.format("%dg %ds %dc", math.floor(value / 10000), math.floor(value / 100) % 100, value % 100)
end

function AzerMind.AuctionItemDetails(item)
    local api = AHledgerAPI
    if type(api) ~= "table" or type(api.GetPrice) ~= "function" then return nil end
    local ok, price = pcall(api.GetPrice, item)
    if not ok or type(price) ~= "table" then return nil end
    local median, buyout = Money(price.median), Money(price.minBuyout)
    if not median and not buyout then return nil end
    local lines = {"Auction prices (per unit): " .. (buyout and ("minimum " .. buyout) or "minimum unknown") ..
        (median and ("; median " .. median) or "")}
    if type(price.quantity) == "number" then lines[#lines+1] = "Listed quantity: " .. tostring(price.quantity) end
    lines[#lines+1] = "Market: " .. tostring(price.market or "unknown")
    local updated = tonumber(price.updated)
    lines[#lines+1] = "Observed: " .. (updated and updated > 0 and updated < 32503680000 and date("%Y-%m-%d %H:%M", updated) or "unknown") ..
        (price.snapshot and " (bundled snapshot; not live)" or " (latest available scan; not a sale guarantee)")
    lines[#lines+1] = "Prices from AHledger (ahledger.com)"
    return table.concat(lines, "\n")
end
