--[[
Bag Delta Tracker (Retail Only)
Tracks player-specified items and shows current bag counts + delta (current - baseline).
Add items by Shift-clicking from bags into the input, or paste an item link or itemID.
]] BagDeltaTrackerDB = BagDeltaTrackerDB or {
    items = {},
    pos = {
        x = 300,
        y = -200
    },
    scale = 1,
    runCount = 1,
    minimap = {
        hide = false,
    }
}

-- Clean up old string keys in items table
do
    local new = {}
    for k, v in pairs(BagDeltaTrackerDB.items) do
        new[tonumber(k)] = v
    end
    BagDeltaTrackerDB.items = new
end

BagDeltaTrackerDB.runCount = tonumber(BagDeltaTrackerDB.runCount) or 1
BagDeltaTrackerDB.minimap = BagDeltaTrackerDB.minimap or {}
if type(BagDeltaTrackerDB.minimap.hide) ~= "boolean" then
    BagDeltaTrackerDB.minimap.hide = false
end


local ADDON_NAME = "BagDeltaTracker"
local f = CreateFrame("Frame", ADDON_NAME .. "Frame", UIParent, "BackdropTemplate")
f:SetSize(620, 360)
f:SetPoint("CENTER", UIParent, "CENTER", BagDeltaTrackerDB.pos.x or 300, BagDeltaTrackerDB.pos.y or -200)
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local x, y = self:GetLeft(), self:GetTop()
    local ux, uy = UIParent:GetLeft(), UIParent:GetTop()
    BagDeltaTrackerDB.pos.x = x - ux
    BagDeltaTrackerDB.pos.y = y - uy
end)

f:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = {
        left = 3,
        right = 3,
        top = 3,
        bottom = 3
    }
})
f:SetBackdropColor(0, 0, 0, 0.85)
f:Hide()

-- Title
local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
title:SetText("Bag Delta Tracker")

-- Status text
local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
statusText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -14)
statusText:SetText("Idle")

-- Drag handle hint
local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
hint:SetText("Add items by Shift-clicking them from your bags into the box below.")

local elapsed = 0
local running = false
local baseline = nil
local baselineGold = nil

local timerActive = false
local timerStartTime = nil
local timerElapsed = 0
local timerText
local runCountText
local avgFrame
local avgElapsedText
local avgMessage
local avgListFrame
local avgRows = {}
local UpdateAvgFrame

local function ToggleMainFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
    end
end

local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
local minimapDataObject

local function EnsureMinimapIcon()
    if not DBIcon or not LDB then
        return
    end
    if not minimapDataObject then
        minimapDataObject = LDB:NewDataObject(ADDON_NAME, {
            type = "data source",
            text = "Bag Delta Tracker",
            icon = "Interface\\AddOns\\BagDeltaTracker\\media\\BagDeltaTrackerRound",
            OnClick = function(_, button)
                if button == "LeftButton" or button == "RightButton" then
                    ToggleMainFrame()
                end
            end,
            OnTooltipShow = function(tooltip)
                if not tooltip or not tooltip.AddLine then
                    return
                end
                tooltip:AddLine("Bag Delta Tracker")
                tooltip:AddLine("Left-click to toggle window", 0.8, 0.8, 0.8)
            end,
        })
    end
    DBIcon:Register(ADDON_NAME, minimapDataObject, BagDeltaTrackerDB.minimap)
end


local function FormatSeconds(totalSeconds)
    totalSeconds = math.max(0, math.floor(totalSeconds or 0))
    local hours = math.floor(totalSeconds / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    local seconds = totalSeconds % 60
    return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

local function UpdateTimerDisplay()
    if not timerText then
        return
    end
    local total = math.floor(timerElapsed or 0)
    local hours = math.floor(total / 3600)
    local minutes = math.floor((total % 3600) / 60)
    local seconds = total % 60
    timerText:SetText(string.format("Timer: %02d:%02d:%02d", hours, minutes, seconds))
end

local function UpdateRunCountDisplay()
    if not runCountText then
        return
    end
    local count = BagDeltaTrackerDB.runCount or 1
    runCountText:SetText(string.format("Run Count: %d", count))
end

local function StartTimer()
    timerStartTime = GetTime()
    timerElapsed = 0
    timerActive = true
    UpdateTimerDisplay()
    UpdateAvgFrame()
end

local function StopTimer()
    if timerActive and timerStartTime then
        timerElapsed = GetTime() - timerStartTime
    end
    timerActive = false
    timerStartTime = nil
    UpdateTimerDisplay()
    UpdateAvgFrame()
end

local function ResetTimer()
    timerActive = false
    timerStartTime = nil
    timerElapsed = 0
    UpdateTimerDisplay()
    UpdateAvgFrame()
end

local ICON_OFFSET = 2
local ICON_SIZE = 18
local NAME_LEFT = ICON_OFFSET + ICON_SIZE + 6
local NAME_WIDTH = 230
local CURRENT_LEFT = NAME_LEFT + NAME_WIDTH + 12
local CURRENT_WIDTH = 150
local DELTA_LEFT = CURRENT_LEFT + CURRENT_WIDTH + 16
local DELTA_WIDTH = 140

timerText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
timerText:SetPoint("TOPRIGHT", statusText, "BOTTOMRIGHT", 0, -4)
timerText:SetJustifyH("RIGHT")
timerText:SetText("Timer: 00:00:00")

runCountText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
runCountText:SetPoint("TOPRIGHT", timerText, "BOTTOMRIGHT", 0, -4)
runCountText:SetJustifyH("RIGHT")
runCountText:SetText("Run Count: " .. (BagDeltaTrackerDB.runCount or 1))

UpdateTimerDisplay()
UpdateRunCountDisplay()
f:SetScript("OnUpdate", function(self, dt)
    if running then
        elapsed = elapsed + dt
        if elapsed > 1 then
            UpdateList()
            elapsed = 0
        end
    end

    if timerActive and timerStartTime then
        timerElapsed = GetTime() - timerStartTime
        UpdateTimerDisplay()
        if avgFrame and avgFrame:IsShown() then
            UpdateAvgFrame()
        else
            if avgElapsedText then
                avgElapsedText:SetText("Elapsed: " .. FormatSeconds(timerElapsed))
            end
        end
    elseif avgElapsedText then
        avgElapsedText:SetText("Elapsed: " .. FormatSeconds(timerElapsed))
    end
end)

-- Count total of itemID in all player bags (including reagent bag)
local function CountItemInBags(itemID)
    itemID = tonumber(itemID)
    if not itemID then
        return 0
    end

    local count = 0

    if C_Item and C_Item.GetItemCount then
        local ok, result = pcall(C_Item.GetItemCount, itemID, false, false, false, false)
        if ok and type(result) == "number" then
            count = result
        end
    end

    if (not count or count == 0) and GetItemCount then
        local ok, result = pcall(GetItemCount, itemID, false, false, false, false)
        if ok and type(result) == "number" then
            count = math.max(count or 0, result)
        end
    end

    count = count or 0
    return count
end

local function GetPlayerMoney()
    if GetMoney then
        local ok, result = pcall(GetMoney)
        if ok and type(result) == "number" then
            return result
        end
    end
    return 0
end

-- Parse user input into itemID
local pendingAdds = {}
local function ResolveItem(input)
    if not input or input == "" then
        return
    end
    input = input:gsub("^%s+", ""):gsub("%s+$", "")
    -- If it's an item link, extract the ID
    local idFromLink = input:match("item:(%d+)")
    if idFromLink then
        return tonumber(idFromLink)
    end
    -- If it's a number, treat as ID
    local asNum = tonumber(input)
    if asNum then
        return asNum
    end
    -- Try to parse a plain item name (if cached)
    local name = input
    local itemName, _, _, _, _, _, _, _, _, _, itemID = GetItemInfo(name)
    if itemID then
        return itemID
    end
    return nil, "Please Shift-click an item from your bags, paste an item link, or enter a numeric itemID."
end

-- UI: Input + Add button
local edit = CreateFrame("EditBox", ADDON_NAME .. "EditBox", f, "InputBoxTemplate")
edit:SetAutoFocus(false)
edit:SetSize(260, 24)
edit:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
edit:SetText("")
edit:HookScript("OnEscapePressed", function(self)
    self:ClearFocus()
end)
edit:SetMultiLine(false)
function edit:InsertLink(link)
    if type(link) == "string" then
        self:Insert(link)
        return true
    end
end
edit:EnableMouse(true)
edit:SetScript("OnMouseDown", function(self)
    self:SetFocus()
end)
hooksecurefunc("ChatEdit_InsertLink", function(link)
    if edit:IsVisible() and edit:HasFocus() then
        edit:InsertLink(link)
        return true
    end
end)

local addBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
addBtn:SetText("Add Item")
addBtn:SetSize(90, 24)
addBtn:SetPoint("LEFT", edit, "RIGHT", 8, 0)

-- Buttons: Start / End / Reset
local startBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
startBtn:SetText("Start")
startBtn:SetSize(80, 24)
startBtn:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", 0, -10)

local endBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
endBtn:SetText("End")
endBtn:SetSize(80, 24)
endBtn:SetPoint("LEFT", startBtn, "RIGHT", 8, 0)

local resetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
resetBtn:SetText("Reset")
resetBtn:SetSize(80, 24)
resetBtn:SetPoint("LEFT", endBtn, "RIGHT", 8, 0)

local avgBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
avgBtn:SetText("Avg/hr")
avgBtn:SetSize(80, 24)
avgBtn:SetPoint("LEFT", resetBtn, "RIGHT", 8, 0)

-- Headers
local headerContainer = CreateFrame("Frame", nil, f)
headerContainer:SetPoint("TOPLEFT", startBtn, "BOTTOMLEFT", 0, -10)
headerContainer:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, 0)
headerContainer:SetHeight(16)

local headerTracked = headerContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
headerTracked:SetPoint("LEFT", headerContainer, "LEFT", NAME_LEFT, 0)
headerTracked:SetWidth(NAME_WIDTH)
headerTracked:SetJustifyH("LEFT")
headerTracked:SetText("Tracked Gold & Items")

local headerCurrent = headerContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
headerCurrent:SetPoint("LEFT", headerContainer, "LEFT", CURRENT_LEFT, 0)
headerCurrent:SetWidth(CURRENT_WIDTH)
headerCurrent:SetJustifyH("RIGHT")
headerCurrent:SetText("Current")

local headerDelta = headerContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
headerDelta:SetPoint("LEFT", headerContainer, "LEFT", DELTA_LEFT, 0)
headerDelta:SetWidth(DELTA_WIDTH)
headerDelta:SetJustifyH("RIGHT")
headerDelta:SetText("Delta Since Start")
-- List container
local listFrame = CreateFrame("Frame", nil, f)
listFrame:SetPoint("TOPLEFT", headerContainer, "BOTTOMLEFT", 0, -6)
listFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)

-- We'll render rows dynamically (no scroll; practical for ~25 items)
local rows = {}
local function GetRow(i)
    if rows[i] then
        return rows[i]
    end
    local row = CreateFrame("Frame", nil, listFrame)
    row:SetHeight(20)
    if i == 1 then
        row:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, 0)
        row:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", 0, 0)
    else
        row:SetPoint("TOPLEFT", rows[i - 1], "BOTTOMLEFT", 0, -4)
        row:SetPoint("TOPRIGHT", rows[i - 1], "BOTTOMRIGHT", 0, -4)
    end
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", row, "LEFT", ICON_OFFSET, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", row, "LEFT", NAME_LEFT, 0)
    row.name:SetWidth(NAME_WIDTH)
    row.name:SetJustifyH("LEFT")
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.count:SetPoint("LEFT", row, "LEFT", CURRENT_LEFT, 0)
    row.count:SetWidth(CURRENT_WIDTH)
    row.count:SetJustifyH("RIGHT")
    row.delta = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.delta:SetPoint("LEFT", row, "LEFT", DELTA_LEFT, 0)
    row.delta:SetWidth(DELTA_WIDTH)
    row.delta:SetJustifyH("RIGHT")
    row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.remove:SetText("X")
    row.remove:SetSize(22, 18)
    row.remove:SetPoint("LEFT", row.delta, "RIGHT", 12, 0)
    rows[i] = row
    return row
end

avgFrame = CreateFrame("Frame", ADDON_NAME .. "AvgFrame", UIParent, "BackdropTemplate")
avgFrame:SetSize(540, 320)
avgFrame:SetPoint("TOPLEFT", f, "TOPRIGHT", 16, 0)
avgFrame:SetScale(BagDeltaTrackerDB.scale or 1)
avgFrame:SetBackdrop(f:GetBackdrop())
avgFrame:SetBackdropColor(0, 0, 0, 0.85)
avgFrame:SetMovable(true)
avgFrame:EnableMouse(true)
avgFrame:RegisterForDrag("LeftButton")
avgFrame:SetScript("OnDragStart", avgFrame.StartMoving)
avgFrame:SetScript("OnDragStop", avgFrame.StopMovingOrSizing)
avgFrame:Hide()

local avgTitle = avgFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
avgTitle:SetPoint("TOPLEFT", avgFrame, "TOPLEFT", 12, -10)
avgTitle:SetText("Per-Hour Averages")

avgElapsedText = avgFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
avgElapsedText:SetPoint("TOPRIGHT", avgFrame, "TOPRIGHT", -12, -14)
avgElapsedText:SetText("Elapsed: 00:00:00")

avgMessage = avgFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
avgMessage:SetPoint("TOPLEFT", avgTitle, "BOTTOMLEFT", 0, -6)
avgMessage:SetText("Start the timer to compute averages.")

local avgHeader = CreateFrame("Frame", nil, avgFrame)
avgHeader:SetPoint("TOPLEFT", avgMessage, "BOTTOMLEFT", 0, -8)
avgHeader:SetPoint("TOPRIGHT", avgFrame, "TOPRIGHT", -12, 0)
avgHeader:SetHeight(16)

local avgHeaderName = avgHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
avgHeaderName:SetPoint("LEFT", avgHeader, "LEFT", 26, 0)
avgHeaderName:SetWidth(200)
avgHeaderName:SetJustifyH("LEFT")
avgHeaderName:SetText("Name")

local avgHeaderDelta = avgHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
avgHeaderDelta:SetPoint("LEFT", avgHeaderName, "RIGHT", 16, 0)
avgHeaderDelta:SetWidth(120)
avgHeaderDelta:SetJustifyH("RIGHT")
avgHeaderDelta:SetText("Delta")

local avgHeaderPerHour = avgHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
avgHeaderPerHour:SetPoint("LEFT", avgHeaderDelta, "RIGHT", 20, 0)
avgHeaderPerHour:SetWidth(140)
avgHeaderPerHour:SetJustifyH("RIGHT")
avgHeaderPerHour:SetText("Per Hour")

avgListFrame = CreateFrame("Frame", nil, avgFrame)
avgListFrame:SetPoint("TOPLEFT", avgHeader, "BOTTOMLEFT", 0, -6)
avgListFrame:SetPoint("BOTTOMRIGHT", avgFrame, "BOTTOMRIGHT", -12, 12)

local avgClose = CreateFrame("Button", nil, avgFrame, "UIPanelCloseButton")
avgClose:SetPoint("TOPRIGHT", avgFrame, "TOPRIGHT", 4, 4)

local function GetAvgRow(i)
    if avgRows[i] then
        return avgRows[i]
    end
    local row = CreateFrame("Frame", nil, avgListFrame)
    row:SetHeight(20)
    if i == 1 then
        row:SetPoint("TOPLEFT", avgListFrame, "TOPLEFT", 0, 0)
        row:SetPoint("TOPRIGHT", avgListFrame, "TOPRIGHT", 0, 0)
    else
        row:SetPoint("TOPLEFT", avgRows[i - 1], "BOTTOMLEFT", 0, -4)
        row:SetPoint("TOPRIGHT", avgRows[i - 1], "BOTTOMRIGHT", 0, -4)
    end
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE - 2, ICON_SIZE - 2)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetWidth(200)
    row.name:SetJustifyH("LEFT")
    row.delta = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.delta:SetPoint("LEFT", row.name, "RIGHT", 16, 0)
    row.delta:SetWidth(120)
    row.delta:SetJustifyH("RIGHT")
    row.perHour = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.perHour:SetPoint("LEFT", row.delta, "RIGHT", 20, 0)
    row.perHour:SetWidth(140)
    row.perHour:SetJustifyH("RIGHT")
    avgRows[i] = row
    return row
end

avgFrame:SetScript("OnShow", function()
    UpdateAvgFrame()
end)
local function SortedItemIDs()
    local ids = {}
    for id in pairs(BagDeltaTrackerDB.items) do
        ids[#ids + 1] = tonumber(id)
    end
    table.sort(ids, function(a, b)
        local A = BagDeltaTrackerDB.items[a] and BagDeltaTrackerDB.items[a].name or tostring(a)
        local B = BagDeltaTrackerDB.items[b] and BagDeltaTrackerDB.items[b].name or tostring(b)
        return A:lower() < B:lower()
    end)
    return ids
end

local function UpdateStatus()
    if running then
        statusText:SetText("|cff00ff00Running|r")
    elseif baseline then
        statusText:SetText("|cffffff00Ended (baseline kept)|r")
    else
        statusText:SetText("Idle")
    end
end

local GOLD_ICON_TEXTURE = 133784

local function FormatItemDelta(base, delta)
    if not base then
        return "-"
    end
    if delta >= 0 then
        return "|cff00ff00+" .. delta .. "|r"
    else
        return "|cffff2020" .. delta .. "|r"
    end
end

local function FormatGoldAmount(amount)
    amount = amount or 0
    if GetMoneyString then
        return GetMoneyString(amount, true)
    end
    local gold = math.floor(amount / 10000)
    local silver = math.floor((amount % 10000) / 100)
    local copper = amount % 100
    return string.format("%dg %ds %dc", gold, silver, copper)
end

local function FormatGoldDelta(current, baselineValue)
    if not baselineValue then
        return "-"
    end
    local diff = current - baselineValue
    if diff == 0 then
        return "|cffcccccc" .. FormatGoldAmount(0) .. "|r"
    end
    local prefix = diff > 0 and "+" or "-"
    local color = diff > 0 and "|cff00ff00" or "|cffff2020"
    return color .. prefix .. FormatGoldAmount(math.abs(diff)) .. "|r"
end

local function FormatItemPerHour(delta, elapsedSeconds)
    if not delta or not elapsedSeconds or elapsedSeconds <= 0 then
        return "-"
    end
    local perHour = delta * 3600 / elapsedSeconds
    if math.abs(perHour) < 0.005 then
        return "|cffcccccc0/hr|r"
    end
    local color = perHour > 0 and "|cff00ff00" or "|cffff2020"
    return color .. string.format("%+.2f/hr", perHour) .. "|r"
end

local function FormatGoldPerHour(delta, elapsedSeconds)
    if not delta or not elapsedSeconds or elapsedSeconds <= 0 then
        return "-"
    end
    local perHour = delta * 3600 / elapsedSeconds
    if math.abs(perHour) < 0.5 then
        return "|cffcccccc0/hr|r"
    end
    local color = perHour > 0 and "|cff00ff00" or "|cffff2020"
    local sign = perHour > 0 and "+" or "-"
    local amount = FormatGoldAmount(math.floor(math.abs(perHour) + 0.5))
    return color .. sign .. amount .. "/hr|r"
end

UpdateAvgFrame = function()
    if avgElapsedText then
        avgElapsedText:SetText("Elapsed: " .. FormatSeconds(timerElapsed))
    end
    if not avgFrame or not avgFrame:IsShown() then
        return
    end

    local elapsedSeconds = timerElapsed or 0
    if not baseline then
        avgMessage:SetText("Start the timer to compute averages.")
        for _, row in ipairs(avgRows) do
            row:Hide()
        end
        return
    end

    if elapsedSeconds <= 0 then
        avgMessage:SetText("Timer must run before averages appear.")
        for _, row in ipairs(avgRows) do
            row:Hide()
        end
        return
    end

    avgMessage:SetText("")

    local rowIndex = 1
    local currentGold = GetPlayerMoney()
    if baselineGold then
        local goldDelta = currentGold - baselineGold
        local row = GetAvgRow(rowIndex)
        row.icon:SetTexture(GOLD_ICON_TEXTURE)
        row.name:SetText("Gold")
        row.delta:SetText(FormatGoldDelta(currentGold, baselineGold))
        row.perHour:SetText(FormatGoldPerHour(goldDelta, elapsedSeconds))
        row:Show()
        rowIndex = rowIndex + 1
    end

    local ids = SortedItemIDs()
    for _, itemID in ipairs(ids) do
        local base = baseline and baseline[itemID] or nil
        if base then
            local row = GetAvgRow(rowIndex)
            local meta = BagDeltaTrackerDB.items[itemID]
            row.icon:SetTexture((meta and meta.icon) or 134400)
            row.name:SetText(meta and meta.name or ("Item " .. itemID))
            local current = CountItemInBags(itemID)
            local delta = current - base
            row.delta:SetText(FormatItemDelta(base, delta))
            row.perHour:SetText(FormatItemPerHour(delta, elapsedSeconds))
            row:Show()
            rowIndex = rowIndex + 1
        end
    end

    for i = rowIndex, #avgRows do
        avgRows[i]:Hide()
    end
end
function UpdateList()
    local rowIndex = 1
    local currentGold = GetPlayerMoney()
    local goldRow = GetRow(rowIndex)
    goldRow.icon:SetTexture(GOLD_ICON_TEXTURE)
    goldRow.name:SetText("Gold")
    goldRow.count:SetText(FormatGoldAmount(currentGold))
    goldRow.delta:SetText(FormatGoldDelta(currentGold, baselineGold))
    goldRow.remove:SetScript("OnClick", nil)
    goldRow.remove:Hide()
    goldRow.remove:Disable()
    goldRow:Show()
    rowIndex = rowIndex + 1

    local ids = SortedItemIDs()
    for _, itemID in ipairs(ids) do
        local row = GetRow(rowIndex)
        local meta = BagDeltaTrackerDB.items[itemID]
        local name = meta and meta.name or ("Item " .. itemID)
        local icon = meta and meta.icon or 134400
        local current = CountItemInBags(itemID)
        local base = baseline and baseline[itemID] or nil
        local delta = base and (current - base) or 0
        row.icon:SetTexture(icon)
        row.name:SetText(name)
        row.count:SetText(tostring(current))
        row.delta:SetText(FormatItemDelta(base, delta))
        row.remove:SetScript("OnClick", function()
            BagDeltaTrackerDB.items[itemID] = nil
            UpdateList()
        end)
        row.remove:Show()
        row.remove:Enable()
        row:Show()
        rowIndex = rowIndex + 1
    end

    for i = rowIndex, #rows do
        rows[i]:Hide()
    end

    UpdateStatus()
    UpdateAvgFrame()
end
function BagDeltaTracker_IncrementRunCount()
    BagDeltaTrackerDB.runCount = (BagDeltaTrackerDB.runCount or 0) + 1
    UpdateRunCountDisplay()
    UpdateAvgFrame()
end

function BagDeltaTracker_ResetRunCount()
    BagDeltaTrackerDB.runCount = 1
    UpdateRunCountDisplay()
    UpdateAvgFrame()
end

local function EnsureItemMeta(itemID)
    if BagDeltaTrackerDB.items[itemID] and BagDeltaTrackerDB.items[itemID].name then
        return
    end
    local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemID)
    if name then
        BagDeltaTrackerDB.items[itemID] = BagDeltaTrackerDB.items[itemID] or {}
        BagDeltaTrackerDB.items[itemID].name = name
        BagDeltaTrackerDB.items[itemID].icon = icon or 134400
        return true
    else
        pendingAdds[itemID] = true
        return false
    end
end

-- Button handlers
addBtn:SetScript("OnClick", function()
    local txt = edit:GetText()
    local itemID, err = ResolveItem(txt)
    if not itemID then
        UIErrorsFrame:AddMessage(err or "Invalid item.", 1, 0.2, 0.2)
        return
    end
    itemID = tonumber(itemID)
    BagDeltaTrackerDB.items[itemID] = BagDeltaTrackerDB.items[itemID] or {}
    if not EnsureItemMeta(itemID) then
        -- Will resolve on GET_ITEM_INFO_RECEIVED
    end
    edit:SetText("")
    UpdateList()
end)

startBtn:SetScript("OnClick", function()
    baseline = {}
    for itemID in pairs(BagDeltaTrackerDB.items) do
        baseline[itemID] = CountItemInBags(itemID)
    end
    baselineGold = GetPlayerMoney()
    elapsed = 0
    StartTimer()
    running = true
    UpdateList()
end)

endBtn:SetScript("OnClick", function()
    StopTimer()
    running = false
    UpdateList()
end)

resetBtn:SetScript("OnClick", function()
    running = false
    baseline = nil
    baselineGold = nil
    elapsed = 0
    ResetTimer()
    UpdateList()
end)

avgBtn:SetScript("OnClick", function()
    if avgFrame:IsShown() then
        avgFrame:Hide()
    else
        avgFrame:Show()
        UpdateAvgFrame()
    end
end)

-- Slash command for quick toggle
SLASH_BAGDELTATRACKER1 = "/bdt"
SlashCmdList["BAGDELTATRACKER"] = function(msg)
    msg = (msg or ""):lower()
    if msg == "show" or msg == "" then
        f:Show()
    elseif msg == "hide" then
        f:Hide()
    elseif msg == "toggle" then
        ToggleMainFrame()
    elseif msg == "reset" then
        baseline = nil
        baselineGold = nil
        running = false
        elapsed = 0
        ResetTimer()
        UpdateList()
    else
        print("|cff33ff99BagDeltaTracker|r commands /bdt show | hide | toggle | reset")
    end
end

if AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon then
    AddonCompartmentFrame:RegisterAddon({
        text = "Bag Delta Tracker",
        icon = "Interface\\AddOns\\BagDeltaTracker\\media\\BagDeltaTrackerRound",
        notCheckable = true,
        func = function()
            ToggleMainFrame()
        end,
    })
end
-- Event handling
f:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        for itemID in pairs(BagDeltaTrackerDB.items) do
            EnsureItemMeta(itemID)
        end
        UpdateList()
        UpdateTimerDisplay()
        UpdateRunCountDisplay()
        EnsureMinimapIcon()
    elseif event == "BAG_UPDATE_DELAYED" then
        if next(BagDeltaTrackerDB.items) ~= nil then
            UpdateList()
        end
    elseif event == "PLAYER_MONEY" then
        UpdateList()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local itemID, success = ...
        if success and pendingAdds[itemID] then
            pendingAdds[itemID] = nil
            EnsureItemMeta(itemID)
            UpdateList()
        end
    end
end)
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("PLAYER_MONEY")
f:RegisterEvent("GET_ITEM_INFO_RECEIVED")

-- Close button
local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 4, 4)

-- Border line under input area
local line = f:CreateTexture(nil, "BACKGROUND")
line:SetColorTexture(1, 1, 1, 0.08)
line:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", -6, -6)
line:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
line:SetHeight(1)

-- Tooltip on row remove Buttons
local function HookRemoveTooltip(btn)
    btn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Remove", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
end

for _, r in ipairs(rows) do
    if r.remove then
        HookRemoveTooltip(r.remove)
    end
end

UpdateList()
