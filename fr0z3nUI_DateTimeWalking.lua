local ADDON, ns = ...

-- Standalone Timewalking module for fr0z3nUI_DateTime.
ns = ns or {}
ns.Timewalking = ns.Timewalking or {}
local TW = ns.Timewalking

local PREFIX = "|cff00ccff[FDT]|r "
local function Print(msg)
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg or ""))
  end
end

local UIParentLoadAddOn = _G and rawget(_G, "UIParentLoadAddOn")
local PVEFrame_ToggleFrame = _G and rawget(_G, "PVEFrame_ToggleFrame")
local LFG_JoinDungeon = _G and rawget(_G, "LFG_JoinDungeon")
local LE_LFG_CATEGORY_LFD = _G and rawget(_G, "LE_LFG_CATEGORY_LFD")
local IsLFGDungeonJoinable = _G and rawget(_G, "IsLFGDungeonJoinable")

local function IsDungeonJoinable(dungeonID)
  if not dungeonID or type(IsLFGDungeonJoinable) ~= "function" then
    return nil
  end
  local ok, joinable = pcall(IsLFGDungeonJoinable, dungeonID)
  if not ok then
    return nil
  end
  return joinable and true or false
end

TW.LABELS = TW.LABELS or {
  classic = "Classic",
  tbc = "TBC",
  wrath = "Wrath",
  cata = "Cata",
  mop = "MoP",
  wod = "WoD",
  legion = "Legion",
  bfa = "BFA",
  shadowlands = "SL",
}

-- Stable IDs (from EventQ); Shadowlands intentionally omitted until confirmed.
TW.LFG_IDS = TW.LFG_IDS or {
  tbc = 744,
  wrath = 995,
  cata = 1146,
  mop = 1453,
  wod = 1971,
  legion = 2274,
  classic = 2634,
  bfa = 2874,
  shadowlands = 3076,
}

function TW.GetLabel(key)
  key = tostring(key or ""):lower()
  return TW.LABELS[key]
end

local function ResolveTimewalkingKeyByDungeonID(dungeonID)
  if not dungeonID then return nil end
  for key, id in pairs(TW.LFG_IDS) do
    if id == dungeonID then return key end
  end
  return nil
end

-- Calendar helpers
local _calendarOpened = false
local function EnsureCalendarOpened()
  if _calendarOpened then return end
  if C_Calendar and C_Calendar.OpenCalendar then
    pcall(C_Calendar.OpenCalendar)
    _calendarOpened = true
  end
end

local function GetCurrentCalendarDay()
  if C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then
    local ok, t = pcall(C_DateAndTime.GetCurrentCalendarTime)
    if ok and type(t) == "table" and tonumber(t.monthDay) then
      return tonumber(t.monthDay)
    end
  end
  if C_Calendar and C_Calendar.GetDate then
    local ok, t = pcall(C_Calendar.GetDate)
    if ok and type(t) == "table" and tonumber(t.monthDay) then
      return tonumber(t.monthDay)
    end
  end
  return nil
end

local function GetCurrentMonthNumDays()
  if C_Calendar and C_Calendar.GetMonthInfo then
    local ok, info = pcall(C_Calendar.GetMonthInfo, 0)
    if ok and type(info) == "table" and tonumber(info.numDays) then
      local n = tonumber(info.numDays)
      if n and n > 0 then return n end
    end
  end
  return 31
end

local function GetCalendarEventText(monthOffset, day, index)
  if not (C_Calendar and C_Calendar.GetDayEvent) then return nil end
  local ok, ev = pcall(C_Calendar.GetDayEvent, monthOffset, day, index)
  if not ok or type(ev) ~= "table" then return nil end
  local title = rawget(ev, "title")
  if title then return tostring(title) end
  return nil
end

local function IsHolidayDayEvent(monthOffset, day, index)
  if not (C_Calendar and C_Calendar.GetDayEvent) then return false end
  local ok, ev = pcall(C_Calendar.GetDayEvent, monthOffset, day, index)
  if not ok or type(ev) ~= "table" then return false end

  local eventType = rawget(ev, "eventType")
  do
    local et = Enum and Enum.CalendarEventType
    local holidayEnum = et and (rawget(et, "Holiday") or rawget(et, "HOLIDAY"))
    if holidayEnum ~= nil and eventType == holidayEnum then
      return true
    end
  end
  if type(eventType) == "string" and tostring(eventType):lower() == "holiday" then
    return true
  end

  local calendarType = rawget(ev, "calendarType")
  if type(calendarType) == "string" and tostring(calendarType):lower() == "holiday" then
    return true
  end

  return false
end

local function GetCalendarHolidayText(monthOffset, day, index)
  if not (C_Calendar and C_Calendar.GetHolidayInfo) then return nil end
  if not IsHolidayDayEvent(monthOffset, day, index) then
    return nil
  end
  local ok, info = pcall(C_Calendar.GetHolidayInfo, monthOffset, day, index)
  if not ok or type(info) ~= "table" then return nil end
  local name = rawget(info, "name")
  local desc = rawget(info, "description")
  local out = ""
  if name then out = out .. tostring(name) end
  if desc then out = out .. "\n" .. tostring(desc) end
  if out == "" then return nil end
  return out
end

local function DetermineActiveKeyFromCalendar()
  EnsureCalendarOpened()
  if not (C_Calendar and C_Calendar.GetNumDayEvents) then
    return nil
  end

  local today = GetCurrentCalendarDay()
  if not today then
    return nil
  end

  local numDays = GetCurrentMonthNumDays()
  local function ClampDay(d)
    d = tonumber(d)
    if not d then return nil end
    if d < 1 then d = 1 end
    if d > numDays then d = numDays end
    return d
  end

  local timewalkingLabel = _G and _G["PLAYER_DIFFICULTY_TIMEWALKER"] or "Timewalking"
  local keywordMap = {
    classic = { "classic" },
    tbc = { "outland", "burning crusade", "tbc" },
    wrath = { "northrend", "lich king", "wrath", "wotlk" },
    cata = { "cataclysm", "cata" },
    mop = { "pandaria", "mists" },
    wod = { "draenor", "warlords" },
    legion = { "legion" },
    bfa = { "azeroth", "battle for azeroth", "bfa" },
    shadowlands = { "shadowlands" },
  }

  local function ScanDays(startDay, endDay)
    startDay = ClampDay(startDay)
    endDay = ClampDay(endDay)
    if not startDay or not endDay then
      return nil
    end
    if endDay < startDay then
      return nil
    end

    for day = startDay, endDay do
      local okNum, n = pcall(C_Calendar.GetNumDayEvents, 0, day)
      n = okNum and tonumber(n) or 0
      for i = 1, n do
        local title = GetCalendarEventText(0, day, i) or ""
        local holidayText = GetCalendarHolidayText(0, day, i) or ""
        local hay = (title .. "\n" .. holidayText):lower()

        if hay:find("turbulent timeways", 1, true)
          or hay:find("timewalking", 1, true)
          or (type(timewalkingLabel) == "string" and timewalkingLabel ~= "" and (title:find(timewalkingLabel, 1, true) or holidayText:find(timewalkingLabel, 1, true)))
        then
          for key, kws in pairs(keywordMap) do
            for _, kw in ipairs(kws) do
              if kw ~= "" and hay:find(kw, 1, true) then
                return key
              end
            end
          end
        end
      end
    end
    return nil
  end

  -- Prefer an event that is active today; only look ahead if nothing is active right now.
  return ScanDays(today, today) or ScanDays(today + 1, today + 7)

end

local function DetermineActiveKeyFromLFGList()
  if type(GetNumRandomDungeons) ~= "function" or type(GetLFGRandomDungeonInfo) ~= "function" then
    return nil
  end

  local firstKey = nil
  local twCount = 0
  for i = 1, (GetNumRandomDungeons() or 0) do
    local dungeonID, name = GetLFGRandomDungeonInfo(i)
    if dungeonID and type(name) == "string" and name:lower():find("timewalking", 1, true) then
      twCount = twCount + 1
      local key = ResolveTimewalkingKeyByDungeonID(dungeonID)
      if key and not firstKey then
        firstKey = key
      end
      -- Prefer the actually-joinable (active) Timewalking queue.
      if key and IsDungeonJoinable(dungeonID) then
        return key
      end
    end
  end

  -- If the LFG list only contains a single TW entry, it's safe to use it.
  if twCount == 1 then
    return firstKey
  end
  -- Multiple TW entries but none clearly joinable yet => don't guess.
  return nil
end

local function FindJoinableTimewalkingDungeonID()
  if type(GetNumRandomDungeons) ~= "function" or type(GetLFGRandomDungeonInfo) ~= "function" then
    return nil
  end

  local twCount = 0
  local firstTW = nil
  for i = 1, (GetNumRandomDungeons() or 0) do
    local dungeonID, name = GetLFGRandomDungeonInfo(i)
    if dungeonID and type(name) == "string" and name:lower():find("timewalking", 1, true) then
      twCount = twCount + 1
      local key = ResolveTimewalkingKeyByDungeonID(dungeonID)
      if not firstTW then
        firstTW = { id = dungeonID, key = key }
      end

      if IsDungeonJoinable(dungeonID) then
        return dungeonID, key
      end
    end
  end

  if firstTW and twCount == 1 then
    return firstTW.id, firstTW.key
  end
  return nil
end

local _twCache = { checkedAt = 0, key = nil }
function TW.GetActiveKey(now)
  now = tonumber(now) or time()
  if (now - (_twCache.checkedAt or 0)) < 60 then
    return _twCache.key
  end
  local key = DetermineActiveKeyFromCalendar() or DetermineActiveKeyFromLFGList()
  _twCache.checkedAt = now
  _twCache.key = key
  return key
end

local function FindTimewalkingRandomDungeonID(prefer)
  if type(GetNumRandomDungeons) ~= "function" or type(GetLFGRandomDungeonInfo) ~= "function" then
    return nil
  end
  local preferLower = type(prefer) == "string" and prefer:lower() or nil

  local bestId, bestName
  local fallbackId, fallbackName
  for i = 1, (GetNumRandomDungeons() or 0) do
    local dungeonID, name = GetLFGRandomDungeonInfo(i)
    if dungeonID and type(name) == "string" and name ~= "" then
      local n = name:lower()
      local isTW = n:find("timewalking", 1, true) ~= nil
      if isTW then
        if not fallbackId then
          fallbackId, fallbackName = dungeonID, name
        end
        if preferLower then
          if n:find(preferLower, 1, true) then
            bestId, bestName = dungeonID, name
            break
          end
          if preferLower == "wrath" or preferLower == "wotlk" then
            if n:find("lich king", 1, true) or n:find("wotlk", 1, true) then
              bestId, bestName = dungeonID, name
              break
            end
          end
        end
      end
    end
  end

  if bestId then return bestId, bestName end
  return fallbackId, fallbackName
end

local function FindTimewalkingRandomDungeonIDByTokens(tokens)
  if type(tokens) ~= "table" then
    return FindTimewalkingRandomDungeonID(tokens)
  end
  for _, token in ipairs(tokens) do
    local id, name = FindTimewalkingRandomDungeonID(token)
    if id then
      return id, name
    end
  end
  return nil
end

local function ResolveTimewalkingDungeonID(key)
  key = tostring(key or ""):lower()
  if key == "" then return nil end

  local preferredID = TW.LFG_IDS[key]
  if preferredID and type(GetNumRandomDungeons) == "function" and type(GetLFGRandomDungeonInfo) == "function" then
    for i = 1, (GetNumRandomDungeons() or 0) do
      local dungeonID, name = GetLFGRandomDungeonInfo(i)
      if dungeonID == preferredID then
        return dungeonID, name
      end
    end
  end

  local tokenMap = {
    tbc = { "burning crusade", "tbc", "outland" },
    wrath = { "wrath", "lich king", "wotlk" },
    cata = { "cataclysm", "cata" },
    mop = { "pandaria", "mists" },
    wod = { "draenor", "warlords" },
    legion = { "legion" },
    classic = { "classic" },
    bfa = { "azeroth", "bfa" },
    shadowlands = { "shadowlands" },
  }

  local scannedID, scannedName = FindTimewalkingRandomDungeonIDByTokens(tokenMap[key] or key)
  if scannedID then
    return scannedID, scannedName
  end

  if preferredID then
    return preferredID, nil
  end
  return nil
end

local function EnsureGroupFinderLoaded()
  if _G and _G["PVEFrame"] then
    return true
  end
  if type(UIParentLoadAddOn) ~= "function" then
    return false
  end
  pcall(UIParentLoadAddOn, "Blizzard_PVEFrame")
  pcall(UIParentLoadAddOn, "Blizzard_GroupFinder")
  pcall(UIParentLoadAddOn, "Blizzard_LookingForGroup")
  return (_G and _G["PVEFrame"]) and true or false
end

local function PrimeGroupFinderUI()
  local pveLoad = _G and _G["PVEFrame_LoadUI"]
  if type(pveLoad) == "function" then
    pcall(pveLoad)
  end
  local gfLoad = _G and _G["GroupFinderFrame_LoadUI"]
  if type(gfLoad) == "function" then
    pcall(gfLoad)
  end
end

local function SelectLfdDungeon(dungeonID)
  if not dungeonID then
    return false
  end
  if type(ClearAllLFGDungeons) == "function" then
    pcall(ClearAllLFGDungeons)
    if LE_LFG_CATEGORY_LFD then
      pcall(ClearAllLFGDungeons, LE_LFG_CATEGORY_LFD)
    end
  end
  if type(SetLFGDungeon) == "function" then
    return pcall(SetLFGDungeon, dungeonID)
  end
  return false
end

local function TryQueueLFD(dungeonID)
  if not dungeonID then
    return false
  end
  if type(LFG_JoinDungeon) ~= "function" or not LE_LFG_CATEGORY_LFD then
    return false
  end
  if InCombatLockdown and InCombatLockdown() then
    return false
  end
  local lfdList = _G and _G["LFDDungeonList"] or nil
  local hiddenByCollapse = _G and _G["LFDHiddenByCollapseList"] or nil
  local ok = pcall(LFG_JoinDungeon, LE_LFG_CATEGORY_LFD, dungeonID, lfdList, hiddenByCollapse)
  return ok and true or false
end

function TW.TryQueueActive(openUIOnFail)
  if InCombatLockdown and InCombatLockdown() then
    Print("Can't queue in combat.")
    return false
  end

  if not EnsureGroupFinderLoaded() then
    Print("Couldn't load Blizzard Group Finder.")
    return false
  end
  PrimeGroupFinderUI()

  local now = time()
  local key = TW.GetActiveKey(now)
  local dungeonID

  if key then
    dungeonID = ResolveTimewalkingDungeonID(key)
  end

  -- If key detection is ambiguous (or LFG joinability isn't ready), prefer the joinable TW queue.
  if not dungeonID or IsDungeonJoinable(dungeonID) == false then
    local id2, key2 = FindJoinableTimewalkingDungeonID()
    if id2 then
      dungeonID = id2
      key = key2 or key
    end
  end

  if not dungeonID then
    Print("No Timewalking random dungeon found (event not active?).")
    return false
  end

  SelectLfdDungeon(dungeonID)
  local ok = TryQueueLFD(dungeonID)
  if ok then
    local label = (key and (TW.GetLabel(key) or key)) or nil
    if label then
      Print("Queued: Timewalking " .. tostring(label))
    else
      Print("Queued: Timewalking")
    end
    return true
  end

  Print("Queue attempt blocked; open LFD UI and click Find Group.")
  if openUIOnFail and type(PVEFrame_ToggleFrame) == "function" then
    pcall(PVEFrame_ToggleFrame, "GroupFinderFrame")
  end
  return false
end

function TW.AddEventsToTooltip(tooltip, now)
  if not tooltip then return false end

  local lines = {}

  local key = TW.GetActiveKey(now)
  if key then
    local label = TW.GetLabel(key) or key
    lines[#lines + 1] = "Timewalking: " .. tostring(label)
  end

  EnsureCalendarOpened()
  if C_Calendar and C_Calendar.GetNumDayEvents then
    local today = GetCurrentCalendarDay()
    if today then
      local numDays = GetCurrentMonthNumDays()
      local startDay = today
      local endDay = today + 7
      if startDay < 1 then startDay = 1 end
      if endDay > numDays then endDay = numDays end

      local seen = {}
      for day = startDay, endDay do
        local okNum, n = pcall(C_Calendar.GetNumDayEvents, 0, day)
        n = okNum and tonumber(n) or 0
        for i = 1, n do
          local title = GetCalendarEventText(0, day, i) or ""
          local holidayText = GetCalendarHolidayText(0, day, i) or ""
          local hay = (title .. "\n" .. holidayText):lower()

          local isRelevant = false
          if hay:find("turbulent timeways", 1, true) or hay:find("timewalking", 1, true) then
            isRelevant = true
          elseif holidayText ~= "" then
            isRelevant = true
          end

          if isRelevant then
            local line = title
            if line == "" and holidayText ~= "" then
              line = tostring(holidayText):match("^([^\n]+)") or ""
            end
            line = tostring(line or "")
            line = line:gsub("^%s+", ""):gsub("%s+$", "")
            if line ~= "" and not seen[line] then
              seen[line] = true
              lines[#lines + 1] = line
            end
          end
        end
      end
    end
  end

  if #lines <= 0 then
    return false
  end

  tooltip:AddLine("Events", 1, 0.82, 0)
  local shown = 0
  for _, line in ipairs(lines) do
    shown = shown + 1
    tooltip:AddLine(line, 1, 1, 1, true)
    if shown >= 8 then break end
  end
  return true
end

function TW.PrintTimewalkingDungeonList()
  if type(GetNumRandomDungeons) ~= "function" or type(GetLFGRandomDungeonInfo) ~= "function" then
    Print("Random dungeon APIs not available.")
    return
  end

  local rows = {}
  for i = 1, (GetNumRandomDungeons() or 0) do
    local dungeonID, name = GetLFGRandomDungeonInfo(i)
    if dungeonID and type(name) == "string" then
      if name:lower():find("timewalking", 1, true) then
        rows[#rows + 1] = { id = dungeonID, name = name }
      end
    end
  end

  if #rows == 0 then
    Print("No Timewalking random dungeons found (not active?).")
    return
  end

  table.sort(rows, function(a, b)
    return tostring(a.name):lower() < tostring(b.name):lower()
  end)

  Print("Timewalking queues (name -> dungeonID):")
  for i = 1, #rows do
    Print("- " .. tostring(rows[i].name) .. " -> " .. tostring(rows[i].id))
  end
end

function TW.PrintShadowlandsTimewalkingHint()
  if type(GetNumRandomDungeons) ~= "function" or type(GetLFGRandomDungeonInfo) ~= "function" then
    Print("Random dungeon APIs not available.")
    return
  end

  local found = nil
  for i = 1, (GetNumRandomDungeons() or 0) do
    local dungeonID, name = GetLFGRandomDungeonInfo(i)
    if dungeonID and type(name) == "string" and name:lower():find("timewalking", 1, true) then
      if name:lower():find("shadowlands", 1, true) then
        found = { id = dungeonID, name = name }
        break
      end
    end
  end

  if found then
    Print("Found Shadowlands Timewalking: " .. tostring(found.name) .. " -> " .. tostring(found.id))
  else
    Print("No Shadowlands Timewalking entry found right now.")
    local known = TW.LFG_IDS and TW.LFG_IDS.shadowlands
    if known then
      Print("Known Shadowlands Timewalking dungeonID: " .. tostring(known))
    end
    Print("Tip: run /fdt twlist during a Shadowlands TW week.")
  end
end
