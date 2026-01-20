local ADDON, ns = ...

local PREFIX = "|cff00ccff[FDT]|r "
local function Print(msg)
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg or ""))
  end
end

local function Clamp(n, minV, maxV)
  if n == nil then
    if minV ~= nil then return minV end
    return nil
  end
  if n < minV then return minV end
  if n > maxV then return maxV end
  return n
end

---@param n number|nil
---@param minV number
---@param maxV number
---@return number
local function ClampNum(n, minV, maxV)
  if n == nil then return minV end
  if n < minV then return minV end
  if n > maxV then return maxV end
  return n
end

local DEFAULTS = {
  enabled = true,
  locked = false,
  use24h = false,
  showSeconds = false,
  scale = 1.0,
  alpha = 1.0,
  tooltipSide = "RIGHT", -- RIGHT or LEFT
  tooltipOffset = 0, -- horizontal offset from the widget edge
  tooltipYOffset = 0,
  tooltipWidth = 200,
  tooltipOrder = { "realm", "day", "date", "daily", "weekly", "extra1", "extra2", "extra3", "lockouts" },
  fontPreset = "bazooka",
  fontPath = "",
  optionsX = 0,
  optionsY = 0,
  dateLayout = "UK", -- UK: 18 JANUARY 2026 | US: JANUARY 18 2026
  showDay = true,
  showDate = true,
  monthAbbrev = false,
  layoutMode = "STACKED", -- STACKED or INLINE
  textAlign = "CENTER", -- LEFT | CENTER | RIGHT
  gapDayDate = 0,
  gapDateTime = 0,
  timeXOffset = -2,
  timeYOffset = 0,
  ampmGapX = 8,
  ampmYOffset = 0,
  colonUseClass = true,
  colonColor = { 1, 1, 1, 1 },
  colorMode = "someclass", -- solid | someclass | allclass | custom
  customColors = {
    day = { 1, 1, 1, 1 },
    date = { 1, 1, 1, 1 },
    time = { 1, 1, 1, 1 },
    ampm = { 1, 1, 1, 1 },
  },
  showLockouts = false,
  extraClocks = {}, -- { { name = "Home", offsetHours = 0, enabled = true } }
  alarms = {}, -- account-wide alarms
  alarmClickToStop = true,
  labels = {
    realm = "Realm",
    daily = "Daily",
    weekly = "Weekly",
  },
  textColor = { 1, 1, 1, 1 },
  daySize = 13,
  dateSize = 13,
  timeSize = 32,
  ampmSize = 32,
  point = "CENTER",
  relPoint = "CENTER",
  x = 0,
  y = 0,
}

fr0z3nUI_DateTimeDB = fr0z3nUI_DateTimeDB or nil
fr0z3nUI_DateTimeCharDB = fr0z3nUI_DateTimeCharDB or nil
local DB
local CharDB

local clockFrame
local ticker
local optionsFrame

local ResetDefaults
local ApplyState

local ALARM_SOUND_PRESETS = {
  { key = "raidwarning", name = "Raid Warning", kit = function() return SOUNDKIT and SOUNDKIT.RAID_WARNING end },
  { key = "readycheck", name = "Ready Check", kit = function() return SOUNDKIT and SOUNDKIT.READY_CHECK end },
  { key = "igmainmenuopen", name = "UI: Open", kit = function() return SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN end },
  { key = "none", name = "None", kit = function() return nil end },
}

local activeAlarmState = nil
local lastAlarmTickSecond = nil

local function GetLibSharedMedia()
  local ls = _G and rawget(_G, "LibStub")
  if type(ls) ~= "function" then return nil end
  local ok, lib = pcall(ls, "LibSharedMedia-3.0", true)
  if ok and type(lib) == "table" then
    return lib
  end
  return nil
end

local function GetLSMFontNames()
  local lsm = GetLibSharedMedia()
  if not lsm then return nil end

  local names = {}
  if type(lsm.List) == "function" then
    local ok, list = pcall(lsm.List, lsm, "font")
    if ok and type(list) == "table" then
      for _, n in ipairs(list) do
        if type(n) == "string" and n ~= "" then
          names[#names + 1] = n
        end
      end
    end
  end

  if #names == 0 and type(lsm.HashTable) == "function" then
    local ok, ht = pcall(lsm.HashTable, lsm, "font")
    if ok and type(ht) == "table" then
      for n in pairs(ht) do
        if type(n) == "string" and n ~= "" then
          names[#names + 1] = n
        end
      end
    end
  end

  if #names == 0 then return nil end
  table.sort(names, function(a, b)
    return tostring(a):lower() < tostring(b):lower()
  end)
  return names
end

local function ResolveLSMFontPath(name)
  if type(name) ~= "string" or name == "" then return nil end
  local lsm = GetLibSharedMedia()
  if not lsm then return nil end

  local fetch = lsm.Fetch or lsm.fetch
  if type(fetch) == "function" then
    local ok, path = pcall(fetch, lsm, "font", name)
    if ok and type(path) == "string" and path ~= "" then
      return path
    end
  end

  if type(lsm.HashTable) == "function" then
    local ok, ht = pcall(lsm.HashTable, lsm, "font")
    if ok and type(ht) == "table" then
      local p = ht[name]
      if type(p) == "string" and p ~= "" then
        return p
      end
    end
  end
  return nil
end

local FONT_PRESETS = {
  { key = "default", name = "Default (UI)", path = nil },
  { key = "friz", name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
  { key = "arialn", name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
  { key = "morpheus", name = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
  { key = "skurri", name = "Skurri", path = "Fonts\\SKURRI.TTF" },
  { key = "bazooka", name = "Bazooka (addon)", path = "Interface\\AddOns\\fr0z3nUI_DateTime\\media\\Bazooka.ttf" },
  { key = "custom", name = "Custom path", path = "" },
}

local function CopyDefaults(dst, src)
  if type(dst) ~= "table" then dst = {} end
  for k, v in pairs(src) do
    if dst[k] == nil then
      if type(v) == "table" then
        dst[k] = CopyDefaults({}, v)
      else
        dst[k] = v
      end
    elseif type(v) == "table" and type(dst[k]) == "table" then
      dst[k] = CopyDefaults(dst[k], v)
    end
  end
  return dst
end

local function EnsureDB()
  if type(fr0z3nUI_DateTimeDB) ~= "table" then fr0z3nUI_DateTimeDB = {} end
  DB = CopyDefaults(fr0z3nUI_DateTimeDB, DEFAULTS)

  -- Back-compat: remove deprecated LibSharedMedia preset if a user had it saved.
  if tostring(DB.fontPreset or "") == "lsm" then
    DB.fontPreset = "bazooka"
  end

  -- Ensure tooltip order is valid.
  if type(DB.tooltipOrder) ~= "table" then
    DB.tooltipOrder = { "realm", "day", "date", "daily", "weekly", "extra1", "extra2", "extra3", "lockouts" }
  end
end

local TOOLTIP_SECTIONS = {
  { key = "realm", name = "Realm time" },
  { key = "day", name = "Day (when hidden)" },
  { key = "date", name = "Date (when hidden)" },
  { key = "daily", name = "Daily reset" },
  { key = "weekly", name = "Weekly reset" },
  { key = "extra1", name = "Extra clock 1" },
  { key = "extra2", name = "Extra clock 2" },
  { key = "extra3", name = "Extra clock 3" },
  { key = "lockouts", name = "Saved instances" },
}

local function GetDefaultTooltipOrder()
  return { "realm", "day", "date", "daily", "weekly", "extra1", "extra2", "extra3", "lockouts" }
end

local function NormalizeTooltipOrder()
  if not DB then return GetDefaultTooltipOrder() end
  local order = DB.tooltipOrder
  if type(order) ~= "table" then
    DB.tooltipOrder = GetDefaultTooltipOrder()
    return DB.tooltipOrder
  end

  local allowed = {}
  for _, s in ipairs(TOOLTIP_SECTIONS) do
    allowed[s.key] = true
  end

  local out = {}
  local seen = {}
  for _, k in ipairs(order) do
    k = tostring(k or "")
    -- Back-compat: older versions used a single "extra" entry; expand it.
    if k == "extra" then
      local expanded = { "extra1", "extra2", "extra3" }
      for _, ek in ipairs(expanded) do
        if allowed[ek] and not seen[ek] then
          out[#out + 1] = ek
          seen[ek] = true
        end
      end
    elseif allowed[k] and not seen[k] then
      out[#out + 1] = k
      seen[k] = true
    end
  end
  for _, s in ipairs(TOOLTIP_SECTIONS) do
    if not seen[s.key] then
      out[#out + 1] = s.key
      seen[s.key] = true
    end
  end

  DB.tooltipOrder = out
  return out
end

local function FindTooltipOrderIndex(key)
  local order = NormalizeTooltipOrder()
  key = tostring(key or "")
  for i, k in ipairs(order) do
    if k == key then return i, order end
  end
  return nil, order
end

local function MoveTooltipSection(key, dir)
  local idx, order = FindTooltipOrderIndex(key)
  if not idx then return end
  dir = tonumber(dir) or 0
  if dir == 0 then return end
  local j = idx + dir
  if j < 1 then j = 1 end
  if j > #order then j = #order end
  if j == idx then return end
  order[idx], order[j] = order[j], order[idx]
  DB.tooltipOrder = order
end

local function MoveTooltipSectionTo(key, targetIndex)
  local idx, order = FindTooltipOrderIndex(key)
  if not idx then return end
  targetIndex = tonumber(targetIndex) or idx
  if targetIndex < 1 then targetIndex = 1 end
  if targetIndex > #order then targetIndex = #order end
  if targetIndex == idx then return end
  local v = table.remove(order, idx)
  table.insert(order, targetIndex, v)
  DB.tooltipOrder = order
end

local function EnsureCharDB()
  if type(fr0z3nUI_DateTimeCharDB) ~= "table" then fr0z3nUI_DateTimeCharDB = {} end
  if type(fr0z3nUI_DateTimeCharDB.alarms) ~= "table" then fr0z3nUI_DateTimeCharDB.alarms = {} end
  CharDB = fr0z3nUI_DateTimeCharDB
end

local function GetAccountAlarms()
  if not DB then return {} end
  if type(DB.alarms) ~= "table" then DB.alarms = {} end
  return DB.alarms
end

local function GetCharAlarms()
  EnsureCharDB()
  return (CharDB and CharDB.alarms) or {}
end

local function GetAllAlarms()
  local out = {}
  for _, a in ipairs(GetAccountAlarms()) do out[#out + 1] = a end
  for _, a in ipairs(GetCharAlarms()) do out[#out + 1] = a end
  return out
end

local function ApplyPosition()
  if not clockFrame then return end
  clockFrame:ClearAllPoints()
  clockFrame:SetPoint(DB.point or "TOP", UIParent, DB.relPoint or "TOP", tonumber(DB.x) or 0, tonumber(DB.y) or 0)
end

local function SavePosition()
  if not clockFrame or not clockFrame.GetPoint then return end
  local point, relTo, relPoint, x, y = clockFrame:GetPoint(1)
  if relTo ~= UIParent then
    relTo = UIParent
  end
  DB.point = tostring(point or "TOP")
  DB.relPoint = tostring(relPoint or "TOP")
  DB.x = math.floor((tonumber(x) or 0) + 0.5)
  DB.y = math.floor((tonumber(y) or 0) + 0.5)
end

local function GetTextRGBA()
  local c = (type(DB) == "table" and type(DB.textColor) == "table") and DB.textColor or nil
  local r = (c and tonumber(c[1])) or 1
  local g = (c and tonumber(c[2])) or 1
  local b = (c and tonumber(c[3])) or 1
  local a = (c and tonumber(c[4])) or 1
  return ClampNum(r, 0, 1), ClampNum(g, 0, 1), ClampNum(b, 0, 1), ClampNum(a, 0, 1)
end

local function GetPlayerClassRGB()
  local colors = _G and rawget(_G, "RAID_CLASS_COLORS")
  if not (UnitClass and colors) then return 1, 1, 1 end
  local _, classToken = UnitClass("player")
  if not classToken then return 1, 1, 1 end
  local c = colors[classToken]
  if not c then return 1, 1, 1 end
  return tonumber(c.r) or 1, tonumber(c.g) or 1, tonumber(c.b) or 1
end

local function EnsureCustomColors()
  if not DB then return end
  if type(DB.customColors) ~= "table" then DB.customColors = {} end
  local function EnsureKey(k)
    if type(DB.customColors[k]) ~= "table" then
      DB.customColors[k] = { 1, 1, 1, 1 }
    end
  end
  EnsureKey("day")
  EnsureKey("date")
  EnsureKey("time")
  EnsureKey("ampm")
end

local function GetElementRGBA(element)
  element = tostring(element or "")
  local baseA = select(4, GetTextRGBA())
  local mode = tostring((DB and DB.colorMode) or "someclass"):lower()
  local cr, cg, cb = GetPlayerClassRGB()

  if mode == "solid" then
    local r, g, b, a = GetTextRGBA()
    return r, g, b, a
  end

  if mode == "allclass" then
    return cr, cg, cb, baseA
  end

  if mode == "custom" then
    EnsureCustomColors()
    local c = DB and DB.customColors and DB.customColors[element] or nil
    if type(c) == "table" then
      local r = ClampNum(tonumber(c[1]), 0, 1)
      local g = ClampNum(tonumber(c[2]), 0, 1)
      local b = ClampNum(tonumber(c[3]), 0, 1)
      local a = ClampNum(tonumber(c[4]), 0, 1)
      return r, g, b, a
    end
    local r, g, b, a = GetTextRGBA()
    return r, g, b, a
  end

  -- someclass: Day + AM/PM class colored, Date + time digits white.
  if element == "day" or element == "ampm" then
    return cr, cg, cb, baseA
  end
  return 1, 1, 1, baseA
end

local function GetLabel(key, fallback)
  local t = (type(DB) == "table" and type(DB.labels) == "table") and DB.labels or nil
  local v = t and t[key] or nil
  v = tostring(v or "")
  v = v:gsub("^%s+", ""):gsub("%s+$", "")
  if v == "" then v = tostring(fallback or key or "") end
  return v
end

local function GetBaseTimeSeconds()
  -- Use realm/server time when possible; it matches "Realm" expectations.
  local gst = _G and rawget(_G, "GetServerTime")
  if type(gst) == "function" then
    local ok, v = pcall(gst)
    if ok and type(v) == "number" then return v end
  end
  return time()
end

local function FormatClockTimeAt(seconds)
  if type(seconds) ~= "number" then seconds = GetBaseTimeSeconds() end
  if DB.use24h then
    local fmt = DB.showSeconds and "%H:%M:%S" or "%H:%M"
    return tostring(date(fmt, seconds) or ""), ""
  end
  local fmt = DB.showSeconds and "%I:%M:%S %p" or "%I:%M %p"
  local s = tostring(date(fmt, seconds) or "")
  s = s:gsub("^0", "")
  local t, ap = s:match("^(.-)%s+([AP]M)$")
  if not t then
    t, ap = s, ""
  end
  return t, ap
end

local function FormatDayAndDateAt(seconds)
  if type(seconds) ~= "number" then seconds = GetBaseTimeSeconds() end
  local day = tostring(date("%A", seconds) or "")
  day = day:upper()

  local dayNum = tonumber(date("%d", seconds)) or 0
  local monthFmt = (DB and DB.monthAbbrev) and "%b" or "%B"
  local month = tostring(date(monthFmt, seconds) or "")
  local year = tostring(date("%Y", seconds) or "")

  local layout = tostring(DB.dateLayout or "UK"):upper()
  if layout == "US" then
    return day, string.format("%s %d %s", month:upper(), dayNum, year)
  end
  return day, string.format("%d %s %s", dayNum, month:upper(), year)
end

local function ApplyLayout()
  if not clockFrame then return end
  if not (clockFrame.day and clockFrame.date and clockFrame.time and clockFrame.timeGroup) then return end

  local align = tostring((DB and DB.textAlign) or "LEFT"):upper()
  if align ~= "CENTER" and align ~= "RIGHT" then align = "LEFT" end

  if clockFrame.day.SetJustifyH then clockFrame.day:SetJustifyH(align) end
  if clockFrame.date.SetJustifyH then clockFrame.date:SetJustifyH(align) end

  local width = math.max(1, tonumber(clockFrame.GetWidth and clockFrame:GetWidth() or 220) or 220)
  if clockFrame.day.SetWidth then clockFrame.day:SetWidth(width) end
  if clockFrame.date.SetWidth then clockFrame.date:SetWidth(width) end

  local dayAnchor = "TOPLEFT"
  local dateAnchor = "TOPLEFT"
  local timeAnchor = "TOPLEFT"
  if align == "CENTER" then
    dayAnchor, dateAnchor, timeAnchor = "TOP", "TOP", "TOP"
  elseif align == "RIGHT" then
    dayAnchor, dateAnchor, timeAnchor = "TOPRIGHT", "TOPRIGHT", "TOPRIGHT"
  end

  local showDay = (DB and DB.showDay ~= false) and true or false
  local showDate = (DB and DB.showDate ~= false) and true or false
  local mode = tostring((DB and DB.layoutMode) or "STACKED"):upper()
  if not showDay then mode = "STACKED" end

  local gapDayDate = ClampNum(tonumber(DB.gapDayDate), 0, 30)
  local gapDateTime = ClampNum(tonumber(DB.gapDateTime), 0, 60)
  local timeX = ClampNum(tonumber(DB.timeXOffset), -80, 80)
  local timeY = ClampNum(tonumber(DB.timeYOffset), -80, 80)

  clockFrame.day:ClearAllPoints()
  clockFrame.date:ClearAllPoints()
  clockFrame.timeGroup:ClearAllPoints()

  clockFrame.day:SetPoint(dayAnchor, 0, 0)

  if showDay then
    clockFrame.day:Show()
  else
    clockFrame.day:Hide()
  end

  local inline = (showDay and mode == "INLINE") and true or false
  local showDateLine = (showDate and not inline) and true or false

  if showDateLine then
    if showDay then
      clockFrame.date:SetPoint(dateAnchor, clockFrame.day, dateAnchor == "TOP" and "BOTTOM" or (dateAnchor == "TOPRIGHT" and "BOTTOMRIGHT" or "BOTTOMLEFT"), 0, -(gapDayDate))
    else
      clockFrame.date:SetPoint(dateAnchor, 0, 0)
    end
    clockFrame.date:Show()
  else
    clockFrame.date:Hide()
  end

  if showDateLine then
    clockFrame.timeGroup:SetPoint(timeAnchor, clockFrame.date, timeAnchor == "TOP" and "BOTTOM" or (timeAnchor == "TOPRIGHT" and "BOTTOMRIGHT" or "BOTTOMLEFT"), timeX, -(gapDateTime) + timeY)
  elseif showDay then
    clockFrame.timeGroup:SetPoint(timeAnchor, clockFrame.day, timeAnchor == "TOP" and "BOTTOM" or (timeAnchor == "TOPRIGHT" and "BOTTOMRIGHT" or "BOTTOMLEFT"), timeX, -(gapDateTime) + timeY)
  else
    clockFrame.timeGroup:SetPoint(timeAnchor, 0, 0, timeX, timeY)
  end

  if clockFrame.ampm and clockFrame.time then
    local ax = ClampNum(tonumber(DB.ampmGapX), -80, 80)
    local ay = ClampNum(tonumber(DB.ampmYOffset), -80, 80)
    clockFrame.ampm:ClearAllPoints()
    clockFrame.ampm:SetPoint("BOTTOMLEFT", clockFrame.time, "BOTTOMRIGHT", ax, ay)
  end
end

local function UpdateTimeGroupSize()
  if not clockFrame or not clockFrame.timeGroup or not clockFrame.time then return end
  if not (clockFrame.time.GetStringWidth and clockFrame.timeGroup.SetWidth) then return end

  local tw = tonumber(clockFrame.time:GetStringWidth()) or 0
  local aw = 0
  local ax = ClampNum(tonumber(DB and DB.ampmGapX), -80, 80)
  if clockFrame.ampm and clockFrame.ampm.IsShown and clockFrame.ampm:IsShown() and clockFrame.ampm.GetStringWidth then
    aw = tonumber(clockFrame.ampm:GetStringWidth()) or 0
    if aw > 0 then aw = aw + math.max(0, ax) end
  end

  clockFrame.timeGroup:SetWidth(math.max(1, tw + aw))
  clockFrame.timeGroup:SetHeight(math.max(1, tonumber(DB.timeSize) or 32))
end

local function AutoSizeClockFrameWidth()
  if not clockFrame then return end
  if not (clockFrame.SetWidth and clockFrame.GetWidth) then return end

  local function isShown(f)
    return f and f.IsShown and f:IsShown()
  end

  local function stringWidth(fs)
    if not fs or not fs.GetStringWidth or not isShown(fs) then return 0 end
    local w = tonumber(fs:GetStringWidth()) or 0
    if w < 0 then w = 0 end
    return w
  end

  local dayW = stringWidth(clockFrame.day)
  local dateW = stringWidth(clockFrame.date)
  local timeW = 0
  if clockFrame.timeGroup and clockFrame.timeGroup.GetWidth and isShown(clockFrame.timeGroup) then
    timeW = tonumber(clockFrame.timeGroup:GetWidth()) or 0
  end

  local maxW = math.max(dayW, dateW, timeW)

  -- Account for offsets that may push the time group left/right a bit.
  local timeX = ClampNum(tonumber(DB and DB.timeXOffset), -80, 80)
  local extra = math.abs(tonumber(timeX) or 0)

  -- Padding keeps the hitbox comfortable but tight.
  local padL, padR = 6, 6
  local targetW = math.floor((maxW + padL + padR + extra) + 0.5)
  targetW = ClampNum(targetW, 24, 520)

  -- Keep width at least wide enough for alignment math.
  clockFrame:SetWidth(targetW)
  if clockFrame.day and clockFrame.day.SetWidth then clockFrame.day:SetWidth(targetW) end
  if clockFrame.date and clockFrame.date.SetWidth then clockFrame.date:SetWidth(targetW) end
end

local function ColorCodeRGB(r, g, b)
  r = ClampNum(tonumber(r), 0, 1)
  g = ClampNum(tonumber(g), 0, 1)
  b = ClampNum(tonumber(b), 0, 1)
  return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function GetColonRGB()
  if DB and DB.colonUseClass then
    return GetPlayerClassRGB()
  end
  local c = (DB and type(DB.colonColor) == "table") and DB.colonColor or nil
  return ClampNum(c and tonumber(c[1]) or 1, 0, 1), ClampNum(c and tonumber(c[2]) or 1, 0, 1), ClampNum(c and tonumber(c[3]) or 1, 0, 1)
end

local function ColorizeColons(text)
  text = tostring(text or "")
  local r, g, b = GetColonRGB()
  local code = ColorCodeRGB(r, g, b)
  return text:gsub(":", code .. ":|r")
end

local function FormatDuration(secs)
  secs = tonumber(secs) or 0
  if secs < 0 then secs = 0 end
  local d = math.floor(secs / 86400)
  secs = secs - d * 86400
  local h = math.floor(secs / 3600)
  secs = secs - h * 3600
  local m = math.floor(secs / 60)
  if d > 0 then
    return string.format("%dd %dh %dm", d, h, m)
  elseif h > 0 then
    return string.format("%dh %dm", h, m)
  else
    return string.format("%dm", m)
  end
end

local function NormalizeAlarmTime(text)
  text = tostring(text or "")
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  local h, m = text:match("^(%d?%d)%s*:%s*(%d%d)$")
  if not h then
    h, m = text:match("^(%d%d)(%d%d)$")
  end
  h = tonumber(h)
  m = tonumber(m)
  if not h or not m then return nil end
  if h < 0 or h > 23 then return nil end
  if m < 0 or m > 59 then return nil end
  return string.format("%02d:%02d", h, m)
end

local function NormalizeAlarmDate(text)
  text = tostring(text or "")
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  local y, m, d = text:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if not y or not m or not d then return nil end
  if y < 2000 or y > 2100 then return nil end
  if m < 1 or m > 12 then return nil end
  if d < 1 or d > 31 then return nil end
  return string.format("%04d-%02d-%02d", y, m, d)
end

local function Time24From12(hh12, mm, ampm)
  hh12 = tonumber(hh12)
  mm = tonumber(mm)
  if not hh12 or hh12 < 1 or hh12 > 12 then return nil end
  if not mm or mm < 0 or mm > 59 then return nil end
  ampm = tostring(ampm or "AM"):upper()
  local h = hh12 % 12
  if ampm == "PM" then h = h + 12 end
  return string.format("%02d:%02d", h, mm)
end

local function Time12From24(timeText)
  local t = NormalizeAlarmTime(timeText)
  if not t then return "", "", "AM" end
  local hh, mm = t:match("^(%d%d):(%d%d)$")
  hh, mm = tonumber(hh), tonumber(mm)
  if not hh or not mm then return "", "", "AM" end
  local ap = (hh >= 12) and "PM" or "AM"
  local h12 = hh % 12
  if h12 == 0 then h12 = 12 end
  return string.format("%02d", h12), string.format("%02d", mm), ap
end

local function GetAlarmTimeEpochForToday(alarm, now)
  if type(alarm) ~= "table" then return nil end
  local t = NormalizeAlarmTime(alarm.time)
  if not t then return nil end
  local hh, mm = t:match("^(%d%d):(%d%d)$")
  hh = tonumber(hh)
  mm = tonumber(mm)
  if not hh or not mm then return nil end

  local dt = date("*t", now)
  if type(dt) ~= "table" then return nil end
  dt.hour = hh
  dt.min = mm
  dt.sec = 0
  local ok, when = pcall(time, dt)
  if ok and type(when) == "number" then return when end
  return nil
end

local function DayKey(now)
  return tostring(date("%Y-%m-%d", now) or "")
end

local function GetAlarmSoundKit(key)
  key = tostring(key or "")
  for _, s in ipairs(ALARM_SOUND_PRESETS) do
    if s.key == key then
      local ok, v = pcall(s.kit)
      if ok then return v end
      return nil
    end
  end
  return nil
end

local function PlayAlarmSound(key)
  local kit = GetAlarmSoundKit(key)
  if not kit then return end
  local ps = _G and rawget(_G, "PlaySound")
  if type(ps) == "function" then
    pcall(ps, kit, "Master")
  end
end

local function IsAlarmActive()
  return activeAlarmState ~= nil
end

local function ApplyInteractivity()
  if not clockFrame then return end
  clockFrame:EnableMouse(true)

  local clickable = (DB and DB.locked) and false or true
  if IsAlarmActive() and DB and DB.alarmClickToStop then
    clickable = true
  end

  if clockFrame.SetMouseClickEnabled then
    -- API signature varies by client; be defensive.
    local ok = pcall(clockFrame.SetMouseClickEnabled, clockFrame, clickable)
    if not ok then
      pcall(clockFrame.SetMouseClickEnabled, clockFrame, "LeftButton", clickable)
      pcall(clockFrame.SetMouseClickEnabled, clockFrame, "RightButton", clickable)
    end
  elseif clockFrame.SetPropagateMouseClicks then
    pcall(clockFrame.SetPropagateMouseClicks, clockFrame, not clickable)
  else
    -- Fallback: disables hover tooltip too on older clients.
    clockFrame:EnableMouse(clickable)
  end

  if DB and DB.locked then
    clockFrame:SetMovable(false)
    clockFrame:RegisterForDrag()
  else
    clockFrame:SetMovable(true)
    clockFrame:RegisterForDrag("LeftButton")
  end
end

local function StopActiveAlarm()
  activeAlarmState = nil
  if clockFrame and clockFrame._alarmFlashTicker and clockFrame._alarmFlashTicker.Cancel then
    clockFrame._alarmFlashTicker:Cancel()
  end
  if clockFrame then
    clockFrame._alarmFlashTicker = nil
  end
  ApplyState()
end

local function StartAlarm(alarm, now)
  if IsAlarmActive() then
    -- Keep it simple: only one active alarm at a time.
    return
  end

  now = tonumber(now) or GetBaseTimeSeconds()

  local soundKey = tostring(alarm.sound or "raidwarning")
  local flash = alarm.flash and true or false
  local untilClick = alarm.untilClick and true or false
  local repeatEvery = tonumber(alarm.repeatEvery) or 10
  if repeatEvery < 1 then repeatEvery = 1 end
  if repeatEvery > 300 then repeatEvery = 300 end

  local repeatFor = tonumber(alarm.repeatFor) or 60
  if repeatFor < 1 then repeatFor = 1 end
  if repeatFor > 3600 then repeatFor = 3600 end

  local allowClickStop = (DB and DB.alarmClickToStop) and true or false
  activeAlarmState = {
    alarm = alarm,
    startedAt = now,
    nextSoundAt = now,
    soundKey = soundKey,
    flash = flash,
    untilClick = untilClick,
    repeatEvery = repeatEvery,
    endAt = (untilClick and allowClickStop) and nil or (now + repeatFor),
  }

  Print("Alarm: " .. tostring(alarm.name or NormalizeAlarmTime(alarm.time) or "(unnamed)"))
  PlayAlarmSound(soundKey)

  -- Flash color is applied smoothly in UpdateAlarmState (no hard toggle ticker).

  ApplyInteractivity()
end

local function CheckAlarms(now)
  now = tonumber(now) or GetBaseTimeSeconds()
  local sec = tonumber(date("%S", now))
  if sec ~= nil then
    if lastAlarmTickSecond == sec then return end
    lastAlarmTickSecond = sec
  end

  if IsAlarmActive() then return end

  local today = DayKey(now)
  for _, alarm in ipairs(GetAllAlarms()) do
    if type(alarm) == "table" and alarm.enabled ~= false then
      local eligible = true
      local schedule = tostring(alarm.schedule or "daily"):lower()
      if schedule ~= "daily" and schedule ~= "today" and schedule ~= "date" then
        schedule = "daily"
        alarm.schedule = schedule
      end

      if schedule == "today" then
        local onceDay = tostring(alarm.onceDay or "")
        if onceDay == "" then
          alarm.onceDay = today
          onceDay = today
        end
        if onceDay ~= today then
          -- One-shot is for a different day; keep disabled so it doesn't surprise later.
          alarm.enabled = false
          eligible = false
        end
      elseif schedule == "date" then
        local dt = NormalizeAlarmDate(alarm.date)
        if not dt then
          -- Invalid date => treat as disabled until fixed.
          alarm.enabled = false
          eligible = false
        elseif dt ~= today then
          -- Not the target day.
          eligible = false
        end
      end

      if eligible then
        local when = GetAlarmTimeEpochForToday(alarm, now)
        if when and now >= when and now < (when + 60) then
          if schedule == "daily" then
            if tostring(alarm.lastFiredDay or "") ~= today then
              alarm.lastFiredDay = today
              StartAlarm(alarm, now)
              return
            end
          else
            -- today/date: one-shot
            StartAlarm(alarm, now)
            alarm.enabled = false
            return
          end
        end
      end
    end
  end
end

local function UpdateAlarmState(now)
  if not activeAlarmState then return end
  now = tonumber(now) or GetBaseTimeSeconds()

  if DB and DB.alarmClickToStop and activeAlarmState.untilClick then
    -- waits for click
  elseif activeAlarmState.endAt and now >= activeAlarmState.endAt then
    StopActiveAlarm()
    return
  end

  if activeAlarmState.nextSoundAt and now >= activeAlarmState.nextSoundAt then
    PlayAlarmSound(activeAlarmState.soundKey)
    activeAlarmState.nextSoundAt = now + (activeAlarmState.repeatEvery or 10)
  end

  if activeAlarmState.flash and clockFrame then
    local function ApplyFlash(element, fs)
      if not fs then return end
      local r, g, b, a = GetElementRGBA(element)
      -- Smooth pulse towards red.
      local t = (math.sin((now - (activeAlarmState.startedAt or now)) * math.pi) + 1) * 0.5 -- ~2s period
      local rr, rg, rb = 1, 0.2, 0.2
      r = r + (rr - r) * t
      g = g + (rg - g) * t
      b = b + (rb - b) * t
      fs:SetTextColor(r, g, b, a)
    end
    ApplyFlash("day", clockFrame.day)
    ApplyFlash("date", clockFrame.date)
    ApplyFlash("time", clockFrame.time)
    ApplyFlash("ampm", clockFrame.ampm)
  end
end

local function UpdateClockText()
  if not clockFrame then return end
  local now = GetBaseTimeSeconds()
  local day, dateStr = FormatDayAndDateAt(now)
  local timeStr, ampm = FormatClockTimeAt(now)
  local showDay = (DB and DB.showDay ~= false) and true or false
  local showDate = (DB and DB.showDate ~= false) and true or false
  local mode = tostring((DB and DB.layoutMode) or "STACKED"):upper()
  if not showDay then mode = "STACKED" end

  if showDay and mode == "INLINE" then
    if clockFrame.day then
      if showDate then
        clockFrame.day:SetText(string.format("%s  %s", day, dateStr))
      else
        clockFrame.day:SetText(day)
      end
    end
    if clockFrame.date then clockFrame.date:SetText("") end
  else
    if clockFrame.day then clockFrame.day:SetText(showDay and day or "") end
    if clockFrame.date then clockFrame.date:SetText(showDate and dateStr or "") end
  end
  if DB and tostring(DB.colorMode or "someclass"):lower() == "someclass" then
    timeStr = ColorizeColons(timeStr)
  end
  if clockFrame.time then clockFrame.time:SetText(timeStr) end
  if clockFrame.ampm then
    clockFrame.ampm:SetText(ampm)
    if ampm == "" then
      if clockFrame.ampm.Hide then clockFrame.ampm:Hide() end
    else
      if clockFrame.ampm.Show then clockFrame.ampm:Show() end
    end
  end
  UpdateTimeGroupSize()
  AutoSizeClockFrameWidth()
end

local function StopTicker()
  if ticker and ticker.Cancel then
    ticker:Cancel()
  end
  ticker = nil
end

local function StartTicker()
  StopTicker()
  local interval = DB.showSeconds and 0.25 or 1.0
  local function Tick()
    local now = GetBaseTimeSeconds()

    local function AddHiddenDay()
      if DB and DB.showDay ~= false then return false end
      local day = FormatDayAndDateAt(now)
      if type(day) == "string" and day ~= "" then
        GameTooltip:AddDoubleLine("Day", day, 0.8, 0.8, 0.8, 1, 1, 1)
        return true
      end
      return false
    end

    local function AddHiddenDate()
      if DB and DB.showDate ~= false then return false end
      local _, dateStr = FormatDayAndDateAt(now)
      if type(dateStr) == "string" and dateStr ~= "" then
        GameTooltip:AddDoubleLine("Date", dateStr, 0.8, 0.8, 0.8, 1, 1, 1)
        return true
      end
      return false
    end
    UpdateClockText()
    CheckAlarms(now)
    UpdateAlarmState(now)
  end
  if C_Timer and C_Timer.NewTicker then
    ticker = C_Timer.NewTicker(interval, Tick)
  else
    -- Fallback: OnUpdate
    clockFrame._elapsed = 0
    clockFrame:SetScript("OnUpdate", function(self, elapsed)
      self._elapsed = (self._elapsed or 0) + (elapsed or 0)
      if self._elapsed >= interval then
        self._elapsed = 0
        Tick()
      end
    end)
  end
end

ApplyState = function()
  if not clockFrame then return end

  ApplyLayout()

  clockFrame:SetScale(ClampNum(tonumber(DB.scale), 0.5, 2.0))
  clockFrame:SetAlpha(ClampNum(tonumber(DB.alpha), 0, 1))

  do
    local r, g, b, a = GetElementRGBA("day")
    if clockFrame.day then clockFrame.day:SetTextColor(r, g, b, a) end
    r, g, b, a = GetElementRGBA("date")
    if clockFrame.date then clockFrame.date:SetTextColor(r, g, b, a) end
    r, g, b, a = GetElementRGBA("time")
    if clockFrame.time then clockFrame.time:SetTextColor(r, g, b, a) end
    r, g, b, a = GetElementRGBA("ampm")
    if clockFrame.ampm then clockFrame.ampm:SetTextColor(r, g, b, a) end
  end

  -- No backdrop by default (per design). Keep frame fully transparent.

  if DB.enabled then
    clockFrame:Show()
  else
    clockFrame:Hide()
  end

  ApplyInteractivity()

  clockFrame:SetScript("OnDragStart", function(self)
    if DB.locked then return end
    if self.StartMoving then self:StartMoving() end
  end)

  clockFrame:SetScript("OnDragStop", function(self)
    if self.StopMovingOrSizing then self:StopMovingOrSizing() end
    SavePosition()
  end)

  clockFrame:SetScript("OnMouseUp", function(_, btn)
    if btn == "LeftButton" then
      if DB and DB.alarmClickToStop and IsAlarmActive() then
        StopActiveAlarm()
        return
      end
      return
    end

    if btn ~= "RightButton" then return end
    if DB and DB.locked then return end
    if optionsFrame and optionsFrame:IsShown() then
      optionsFrame:Hide()
    else
      if ns and ns.ShowOptions then
        ns.ShowOptions()
      end
    end
  end)

  UpdateClockText()
  StartTicker()
end

local function ApplyFonts()
  if not clockFrame then return end
  local font = nil
  local presetKey = tostring(DB.fontPreset or "default")
  if presetKey == "lsm" then
    presetKey = "bazooka"
    DB.fontPreset = "bazooka"
  end

  local lsmName = presetKey:match("^lsm:(.+)$")

  local function ResolveFirstWorkingFont(candidates)
    if type(candidates) ~= "table" then return nil end
    if not clockFrame.CreateFontString then return nil end
    clockFrame._fontProbeFS = clockFrame._fontProbeFS or clockFrame:CreateFontString(nil, "OVERLAY")
    local fs = clockFrame._fontProbeFS
    if fs and fs.Hide then fs:Hide() end

    for _, candidate in ipairs(candidates) do
      if type(candidate) == "string" and candidate ~= "" and fs and fs.SetFont then
        local ok, res = pcall(fs.SetFont, fs, candidate, 12, "OUTLINE")
        if ok and (res == nil or res == true) then
          if fs.GetFont then
            local after = fs:GetFont()
            if type(after) == "string" and after ~= "" then
              return candidate
            end
          else
            return candidate
          end
        end
      end
    end
    return nil
  end

  if presetKey == "bazooka" then
    local candidates = {}
    local function LooksLikeBazookaPath(v)
      if type(v) ~= "string" or v == "" then return false end
      return v:gsub("/", "\\"):lower():find("bazooka", 1, true) ~= nil
    end
    local function AddCandidate(v)
      if type(v) == "string" and v ~= "" then
        candidates[#candidates + 1] = v
      end
    end
    local function AddCandidateLSM(v)
      -- LSM can be mis-registered (e.g., name 'Bazooka' mapped to a different font file).
      if LooksLikeBazookaPath(v) then
        AddCandidate(v)
      end
    end

    -- Bazooka preset: addon-local font only (stable; no SharedMedia/ElvUI/LSM fallback).
    AddCandidate("Interface\\AddOns\\fr0z3nUI_DateTime\\media\\Bazooka.ttf")
    AddCandidate("Interface\\AddOns\\fr0z3nUI_DateTime\\media\\bazooka.ttf")

    font = ResolveFirstWorkingFont(candidates)
  elseif presetKey == "custom" then
    local p = tostring(DB.fontPath or "")
    if p ~= "" then
      font = ResolveFirstWorkingFont({ p }) or p
    end
  elseif lsmName then
    local p = ResolveLSMFontPath(lsmName)
    if type(p) == "string" and p ~= "" then
      font = ResolveFirstWorkingFont({ p }) or p
    end
  else
    for _, p in ipairs(FONT_PRESETS) do
      if p.key == presetKey then
        font = ResolveFirstWorkingFont({ p.path }) or p.path
        break
      end
    end
  end

  if type(font) ~= "string" or font == "" then
    font = _G and rawget(_G, "STANDARD_TEXT_FONT")
  end
  if type(font) ~= "string" or font == "" then
    font = "Fonts\\FRIZQT__.TTF"
  end

  if presetKey == "bazooka" and clockFrame then
    if clockFrame._lastBazookaResolved ~= font then
      clockFrame._lastBazookaResolved = font
      Print("Bazooka resolved to: " .. tostring(font))
    end
  end

  local function SetFS(fs, size, outline)
    if not fs then return end
    local flags = outline and tostring(outline) or "OUTLINE"
    local ok = false
    if fs.SetFont then
      local ok2, res = pcall(fs.SetFont, fs, font, tonumber(size) or 12, flags)
      ok = ok2 and (res == nil or res == true)
    end
    if not ok and fs.SetFontObject then
      fs:SetFontObject("GameFontNormal")
    end
    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0.9) end
    if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
  end

  SetFS(clockFrame.day, DB.daySize, "OUTLINE")
  SetFS(clockFrame.date, DB.dateSize, "OUTLINE")
  SetFS(clockFrame.time, DB.timeSize, "OUTLINE")
  SetFS(clockFrame.ampm, DB.ampmSize, "OUTLINE")
end

local function EnsureClockFrame()
  if clockFrame then return clockFrame end

  local f = CreateFrame("Frame", "fr0z3nUI_DateTimeFrame", UIParent)
  f:SetSize(220, 70)
  f:SetFrameStrata("HIGH")
  f:EnableMouse(true)

  f.day = f:CreateFontString(nil, "OVERLAY")
  f.day:SetPoint("TOPLEFT", 0, 0)
  if f.day.SetJustifyH then f.day:SetJustifyH("LEFT") end

  f.date = f:CreateFontString(nil, "OVERLAY")
  f.date:SetPoint("TOPLEFT", f.day, "BOTTOMLEFT", 0, -2)
  if f.date.SetJustifyH then f.date:SetJustifyH("LEFT") end

  f.timeGroup = CreateFrame("Frame", nil, f)
  f.timeGroup:SetSize(1, 1)
  f.timeGroup:SetPoint("TOPLEFT", f.date, "BOTTOMLEFT", -2, -8)

  f.time = f.timeGroup:CreateFontString(nil, "OVERLAY")
  f.time:SetPoint("BOTTOMLEFT", 0, 0)
  if f.time.SetJustifyH then f.time:SetJustifyH("LEFT") end

  f.ampm = f.timeGroup:CreateFontString(nil, "OVERLAY")
  f.ampm:SetPoint("BOTTOMLEFT", f.time, "BOTTOMRIGHT", 8, 6)
  if f.ampm.SetJustifyH then f.ampm:SetJustifyH("LEFT") end

  f:SetClampedToScreen(true)

  local function ApplyTooltipBorderless(enable)
    if not GameTooltip then return end

    local getBorder = rawget(GameTooltip, "GetBackdropBorderColor")
    local setBorder = rawget(GameTooltip, "SetBackdropBorderColor")

    -- Prefer making only the border transparent (keeps tooltip background).
    if enable then
      if not f._tooltipPrevBorder then
        if type(getBorder) == "function" then
          local ok, r, g, b, a = pcall(getBorder, GameTooltip)
          if ok then
            f._tooltipPrevBorder = { r, g, b, a }
          end
        end
      end
      if type(setBorder) == "function" then
        pcall(setBorder, GameTooltip, 0, 0, 0, 0)
      end
    else
      if f._tooltipPrevBorder and type(setBorder) == "function" then
        local c = f._tooltipPrevBorder
        pcall(setBorder, GameTooltip, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
      end
      f._tooltipPrevBorder = nil
    end
  end

  f:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:Hide()
    ApplyTooltipBorderless(true)
    GameTooltip:SetOwner(self, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()

    do
      local w = ClampNum(tonumber((DB and DB.tooltipWidth) or 260), 160, 520)
      if GameTooltip.SetMinimumWidth then
        pcall(GameTooltip.SetMinimumWidth, GameTooltip, w)
      end
    end
    local side = tostring((DB and DB.tooltipSide) or "RIGHT"):upper()
    local xoff = tonumber((DB and DB.tooltipOffset) or 18) or 18
    local yoff = tonumber((DB and DB.tooltipYOffset) or 6) or 6
    if xoff < 0 then xoff = 0 end
    if xoff > 80 then xoff = 80 end
    if yoff < 0 then yoff = 0 end
    if yoff > 30 then yoff = 30 end
    if side == "LEFT" then
      -- Align tooltip bottom-right with addon bottom-left
      GameTooltip:SetPoint("BOTTOMRIGHT", self, "BOTTOMLEFT", -xoff, yoff)
    else
      -- Align tooltip bottom-left with addon bottom-right
      GameTooltip:SetPoint("BOTTOMLEFT", self, "BOTTOMRIGHT", xoff, yoff)
    end

    local now = GetBaseTimeSeconds()

    local function AddRealmTime()
      local tt, aap = FormatClockTimeAt(now)
      if type(tt) == "string" and tt ~= "" then
        GameTooltip:AddDoubleLine(GetLabel("realm", "Realm"), tt .. ((aap ~= "") and (" " .. aap) or ""), 0.8, 0.8, 0.8, 1, 1, 1)
        return true
      end
      return false
    end

    local function AddHiddenDay()
      if DB and DB.showDay ~= false then return false end
      local day = select(1, FormatDayAndDateAt(now))
      if type(day) == "string" and day ~= "" then
        GameTooltip:AddDoubleLine("Day", day, 0.8, 0.8, 0.8, 1, 1, 1)
        return true
      end
      return false
    end

    local function AddHiddenDate()
      if DB and DB.showDate ~= false then return false end
      local dateStr = select(2, FormatDayAndDateAt(now))
      if type(dateStr) == "string" and dateStr ~= "" then
        GameTooltip:AddDoubleLine("Date", dateStr, 0.8, 0.8, 0.8, 1, 1, 1)
        return true
      end
      return false
    end

    local function AddDailyReset()
      if C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset then
        local ok2, s = pcall(C_DateAndTime.GetSecondsUntilDailyReset)
        if ok2 and type(s) == "number" then
          GameTooltip:AddDoubleLine(GetLabel("daily", "Daily"), FormatDuration(s), 0.8, 0.8, 0.8, 1, 1, 1)
          return true
        end
      end
      return false
    end

    local function AddWeeklyReset()
      if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
        local ok3, s = pcall(C_DateAndTime.GetSecondsUntilWeeklyReset)
        if ok3 and type(s) == "number" then
          GameTooltip:AddDoubleLine(GetLabel("weekly", "Weekly"), FormatDuration(s), 0.8, 0.8, 0.8, 1, 1, 1)
          return true
        end
      end
      return false
    end

    local function AddExtraClock(i)
      if type(DB.extraClocks) ~= "table" then return false end
      local ec = DB.extraClocks[i]
      if type(ec) ~= "table" or ec.enabled == false then return false end

      local name = tostring(ec.name or "Clock")
      name = name:gsub("^%s+", ""):gsub("%s+$", "")
      if name == "" then name = "Clock" end

      local off = tonumber(ec.offsetHours) or 0
      if off > 24 then off = 24 end
      if off < -24 then off = -24 end

      local seconds = now + (off * 3600)
      local tt, aap = FormatClockTimeAt(seconds)
      local suffix = (off == 0) and "" or string.format(" (%+dh)", off)
      GameTooltip:AddDoubleLine(name .. suffix, tt .. ((aap ~= "") and (" " .. aap) or ""), 0.8, 0.95, 0.8, 1, 1, 1)
      return true
    end

    local function AddExtraClock1() return AddExtraClock(1) end
    local function AddExtraClock2() return AddExtraClock(2) end
    local function AddExtraClock3() return AddExtraClock(3) end

    local function AddSavedInstances()
      if not DB.showLockouts then return false end
      local gns = _G and rawget(_G, "GetNumSavedInstances")
      local gsi = _G and rawget(_G, "GetSavedInstanceInfo")
      if type(gns) ~= "function" or type(gsi) ~= "function" then return false end

      local n = 0
      local total = 0
      local num = 0
      local ok, v = pcall(gns)
      if ok and type(v) == "number" then num = v end

      local entries = {}
      for i = 1, num do
        local name, _, reset, difficulty, locked, extended = gsi(i)
        if (locked or extended) and type(name) == "string" and name ~= "" then
          total = total + 1
          entries[#entries + 1] = {
            name = name,
            reset = tonumber(reset) or 0,
            diff = tostring(difficulty or ""),
          }
        end
      end

      if total <= 0 then return false end

      table.sort(entries, function(a, b)
        if a.reset == b.reset then return tostring(a.name) < tostring(b.name) end
        return a.reset < b.reset
      end)

      GameTooltip:AddLine(GetLabel("lockouts", "Saved Instances"), 1, 0.82, 0)
      for _, e in ipairs(entries) do
        local left = e.name
        if e.diff ~= "" then left = left .. " (" .. e.diff .. ")" end
        GameTooltip:AddDoubleLine(left, FormatDuration(e.reset), 1, 1, 1, 0.9, 0.9, 0.9)
        n = n + 1
        if n >= 12 then break end
      end
      return true
    end

    local sectionAdders = {
      realm = { fn = AddRealmTime, gap = false },
      day = { fn = AddHiddenDay, gap = false },
      date = { fn = AddHiddenDate, gap = false },
      daily = { fn = AddDailyReset, gap = false },
      weekly = { fn = AddWeeklyReset, gap = false },
      extra1 = { fn = AddExtraClock1, gap = false },
      extra2 = { fn = AddExtraClock2, gap = false },
      extra3 = { fn = AddExtraClock3, gap = false },
      lockouts = { fn = AddSavedInstances, gap = true },
    }

    local anyShown = false
    local order = NormalizeTooltipOrder()
    for _, key in ipairs(order) do
      local e = sectionAdders[key]
      if e and type(e.fn) == "function" then
        if e.gap and anyShown then
          GameTooltip:AddLine(" ")
        end
        local okShow = false
        local okCall, shown = pcall(e.fn)
        if okCall and shown then okShow = true end
        if okShow then
          anyShown = true
        end
      end
    end
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
    ApplyTooltipBorderless(false)
  end)

  clockFrame = f
  ApplyFonts()
  ApplyPosition()
  ApplyLayout()
  ApplyState()

  return f
end

local function EnsureOptionsFrame()
  if optionsFrame then return optionsFrame end

  local f = CreateFrame("Frame", "fr0z3nUI_DateTimeOptions", UIParent, "BasicFrameTemplateWithInset")

  -- Allow closing with Escape.
  if type(UISpecialFrames) == "table" then
    local name = "fr0z3nUI_DateTimeOptions"
    local exists = false
    for i = 1, #UISpecialFrames do
      if UISpecialFrames[i] == name then exists = true break end
    end
    if not exists and tinsert then tinsert(UISpecialFrames, name) end
  end

  -- Slightly taller so bottom controls don't overlap the last section.
  f:SetSize(330, 820)
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", tonumber(DB and DB.optionsX) or 0, tonumber(DB and DB.optionsY) or 0)
  f:SetFrameStrata("DIALOG")
  f:Hide()

  -- Make the options window draggable (independent of the clock lock).
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self)
    if self.StartMoving then self:StartMoving() end
  end)
  f:SetScript("OnDragStop", function(self)
    if self.StopMovingOrSizing then self:StopMovingOrSizing() end
    if DB and self.GetPoint then
      local _, relTo, _, x, y = self:GetPoint(1)
      if relTo == UIParent then
        DB.optionsX = math.floor((tonumber(x) or 0) + 0.5)
        DB.optionsY = math.floor((tonumber(y) or 0) + 0.5)
      end
    end
  end)

  f.panelGeneral = CreateFrame("Frame", nil, f)
  f.panelGeneral:SetAllPoints()
  f.panelStyle = CreateFrame("Frame", nil, f)
  f.panelStyle:SetAllPoints()
  f.panelStyle:Hide()
  f.panelAlarms = CreateFrame("Frame", nil, f)
  f.panelAlarms:SetAllPoints()
  f.panelAlarms:Hide()

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.title:SetPoint("TOPLEFT", 12, -10)
  f.title:SetText("fr0z3nUI DateTime")

  local function SelectTab(which)
    which = tostring(which or "general"):lower()
    f._activeTab = which
    if which == "style" then
      f.panelGeneral:Hide()
      f.panelAlarms:Hide()
      f.panelStyle:Show()
    elseif which == "alarms" then
      f.panelGeneral:Hide()
      f.panelStyle:Hide()
      f.panelAlarms:Show()
      if f.RefreshAlarms then f:RefreshAlarms() end
    else
      f.panelAlarms:Hide()
      f.panelStyle:Hide()
      f.panelGeneral:Show()
    end
    if f.tabGeneral then f.tabGeneral:SetEnabled(which ~= "general") end
    if f.tabStyle then f.tabStyle:SetEnabled(which ~= "style") end
    if f.tabAlarms then f.tabAlarms:SetEnabled(which ~= "alarms") end
  end

  f.tabGeneral = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.tabGeneral:SetSize(70, 20)
  f.tabGeneral:SetPoint("TOPRIGHT", -154, -6)
  f.tabGeneral:SetText("General")
  f.tabGeneral:SetScript("OnClick", function() SelectTab("general") end)

  f.tabStyle = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.tabStyle:SetSize(70, 20)
  f.tabStyle:SetPoint("LEFT", f.tabGeneral, "RIGHT", 6, 0)
  f.tabStyle:SetText("Style")
  f.tabStyle:SetScript("OnClick", function() SelectTab("style") end)

  f.tabAlarms = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.tabAlarms:SetSize(70, 20)
  f.tabAlarms:SetPoint("LEFT", f.tabStyle, "RIGHT", 6, 0)
  f.tabAlarms:SetText("Alarms")
  f.tabAlarms:SetScript("OnClick", function() SelectTab("alarms") end)

  local sliderIndex = 0

  local function CreateCheck(label, x, y, onClick)
    local cb = CreateFrame("CheckButton", nil, f.panelGeneral, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb.text:SetText(label)
    cb:SetScript("OnClick", function(self)
      if type(onClick) == "function" then onClick(self) end
    end)
    return cb
  end

  local function CreateSlider(label, x, y, minV, maxV, step, onValue)
    sliderIndex = sliderIndex + 1
    local sliderName = "fr0z3nUI_DateTimeSlider" .. sliderIndex
    local s = CreateFrame("Slider", sliderName, f.panelGeneral, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", x, y)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step or 1)
    s:SetObeyStepOnDrag(true)

    local function FormatValue(v)
      local st = tonumber(step) or 1
      if st < 1 then
        if st <= 0.05 then
          return string.format("%.2f", tonumber(v) or 0)
        end
        return string.format("%.1f", tonumber(v) or 0)
      end
      return tostring(math.floor((tonumber(v) or 0) + 0.5))
    end

    local txt = _G[sliderName .. "Text"]
    if txt and txt.SetText then txt:SetText(tostring(label or "")) end

    s._valueText = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    s._valueText:SetPoint("LEFT", txt or s, "RIGHT", 8, 0)
    s._valueText:SetText("")

    local low = _G[sliderName .. "Low"]
    if low and low.SetText then low:SetText(tostring(minV)) end
    local high = _G[sliderName .. "High"]
    if high and high.SetText then high:SetText(tostring(maxV)) end

    s:SetScript("OnValueChanged", function(self, v)
      if self._valueText and self._valueText.SetText then
        self._valueText:SetText(FormatValue(v))
      end
      if type(onValue) == "function" then onValue(self, v) end
    end)

    if s._valueText and s.GetValue then
      s._valueText:SetText(FormatValue(s:GetValue()))
    end
    return s
  end

  f.enable = CreateCheck("Enabled", 16, -36, function(self)
    DB.enabled = self:GetChecked() and true or false
    ApplyState()
  end)

  f.locked = CreateCheck("Locked (disable dragging)", 16, -62, function(self)
    DB.locked = self:GetChecked() and true or false
    ApplyState()
  end)

  f.use24h = CreateCheck("24-hour clock", 16, -88, function(self)
    DB.use24h = self:GetChecked() and true or false
    ApplyState()
  end)

  f.seconds = CreateCheck("Show seconds", 16, -114, function(self)
    DB.showSeconds = self:GetChecked() and true or false
    ApplyState()
  end)

  f.scale = CreateSlider("Scale", 18, -146, 0.5, 2.0, 0.05, function(_, v)
    DB.scale = ClampNum(v, 0.5, 2.0)
    ApplyState()
  end)
  f.scale:SetWidth(280)

  f.alpha = CreateSlider("Alpha", 18, -188, 0.0, 1.0, 0.05, function(_, v)
    DB.alpha = ClampNum(v, 0, 1)
    ApplyState()
  end)
  f.alpha:SetWidth(280)

  local dateLabel = f.panelGeneral:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  dateLabel:SetPoint("TOPLEFT", 16, -226)
  dateLabel:SetText("Date layout")

  f.dateUK = CreateCheck("UK (18 JANUARY 2026)", 16, -242, function(self)
    if self:GetChecked() then
      DB.dateLayout = "UK"
      if f.dateUS then f.dateUS:SetChecked(false) end
      ApplyState()
    else
      if f.dateUS and not f.dateUS:GetChecked() then self:SetChecked(true) end
    end
  end)
  f.dateUK:SetHitRectInsets(0, -160, 0, 0)
  f.dateUS = CreateCheck("US (JANUARY 18 2026)", 170, -242, function(self)
    if self:GetChecked() then
      DB.dateLayout = "US"
      if f.dateUK then f.dateUK:SetChecked(false) end
      ApplyState()
    else
      if f.dateUK and not f.dateUK:GetChecked() then self:SetChecked(true) end
    end
  end)
  f.dateUS:SetHitRectInsets(0, -160, 0, 0)

  f.lockouts = CreateCheck("Show instance lockouts in tooltip", 16, -268, function(self)
    DB.showLockouts = self:GetChecked() and true or false
  end)

  local tipPosLabel = f.panelGeneral:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  tipPosLabel:SetPoint("TOPLEFT", 16, -292)
  tipPosLabel:SetText("Tooltip")

  f.tipOrder = CreateFrame("Button", nil, f.panelGeneral, "UIPanelButtonTemplate")
  f.tipOrder:SetSize(70, 18)
  f.tipOrder:SetPoint("TOPLEFT", 242, -290)
  f.tipOrder:SetText("Order...")

  do
    local menu
    local function GetSectionName(key)
      key = tostring(key or "")

      local n = key:match("^extra([123])$")
      if n then
        local idx = tonumber(n)
        local ec = (DB and type(DB.extraClocks) == "table") and DB.extraClocks[idx] or nil
        local name = ec and tostring(ec.name or "") or ""
        name = name:gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then
          name = "Clock " .. tostring(idx)
        end
        return "Extra: " .. name
      end

      for _, s in ipairs(TOOLTIP_SECTIONS) do
        if s.key == key then return s.name end
      end
      return key
    end

    f.tipOrder:SetScript("OnClick", function(btn)
      if not (UIDropDownMenu_CreateInfo and ToggleDropDownMenu) then
        Print("Dropdown menu unavailable.")
        return
      end
      if not menu then
        menu = CreateFrame("Frame", "fr0z3nUI_DateTimeTooltipOrderMenu", f, "UIDropDownMenuTemplate")
      end
      UIDropDownMenu_Initialize(menu, function(_, level)
        if level == 1 then
          local order = NormalizeTooltipOrder()

          local title = UIDropDownMenu_CreateInfo()
          title.text = "Tooltip order"
          title.isTitle = true
          title.notCheckable = true
          UIDropDownMenu_AddButton(title, level)

          for i, key in ipairs(order) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = string.format("%d. %s", i, GetSectionName(key))
            info.notCheckable = true
            info.hasArrow = true
            info.value = key
            UIDropDownMenu_AddButton(info, level)
          end

          local spacer = UIDropDownMenu_CreateInfo()
          spacer.disabled = true
          spacer.notCheckable = true
          spacer.text = " "
          UIDropDownMenu_AddButton(spacer, level)

          local reset = UIDropDownMenu_CreateInfo()
          reset.text = "Reset to default"
          reset.notCheckable = true
          reset.func = function()
            DB.tooltipOrder = GetDefaultTooltipOrder()
            NormalizeTooltipOrder()
            if CloseDropDownMenus then CloseDropDownMenus() end
          end
          UIDropDownMenu_AddButton(reset, level)
          return
        end

        if level == 2 then
          local key = _G and rawget(_G, "UIDROPDOWNMENU_MENU_VALUE")
          if type(key) ~= "string" or key == "" then return end
          local idx, order = FindTooltipOrderIndex(key)
          if not idx then return end

          local up = UIDropDownMenu_CreateInfo()
          up.text = "Move up"
          up.notCheckable = true
          up.disabled = (idx <= 1)
          up.func = function()
            MoveTooltipSection(key, -1)
            if f.Refresh then f:Refresh() end
            if CloseDropDownMenus then CloseDropDownMenus() end
          end
          UIDropDownMenu_AddButton(up, level)

          local down = UIDropDownMenu_CreateInfo()
          down.text = "Move down"
          down.notCheckable = true
          down.disabled = (idx >= #order)
          down.func = function()
            MoveTooltipSection(key, 1)
            if f.Refresh then f:Refresh() end
            if CloseDropDownMenus then CloseDropDownMenus() end
          end
          UIDropDownMenu_AddButton(down, level)

          local top = UIDropDownMenu_CreateInfo()
          top.text = "Move to top"
          top.notCheckable = true
          top.disabled = (idx <= 1)
          top.func = function()
            MoveTooltipSectionTo(key, 1)
            if f.Refresh then f:Refresh() end
            if CloseDropDownMenus then CloseDropDownMenus() end
          end
          UIDropDownMenu_AddButton(top, level)

          local bottom = UIDropDownMenu_CreateInfo()
          bottom.text = "Move to bottom"
          bottom.notCheckable = true
          bottom.disabled = (idx >= #order)
          bottom.func = function()
            MoveTooltipSectionTo(key, #order)
            if f.Refresh then f:Refresh() end
            if CloseDropDownMenus then CloseDropDownMenus() end
          end
          UIDropDownMenu_AddButton(bottom, level)

          return
        end
      end, "MENU")
      ToggleDropDownMenu(1, nil, menu, btn, 0, 0)
    end)
  end

  f.tipRight = CreateCheck("Right", 16, -308, function(self)
    if self:GetChecked() then
      DB.tooltipSide = "RIGHT"
      if f.tipLeft then f.tipLeft:SetChecked(false) end
    else
      if f.tipLeft and not f.tipLeft:GetChecked() then self:SetChecked(true) end
    end
  end)
  f.tipLeft = CreateCheck("Left", 90, -308, function(self)
    if self:GetChecked() then
      DB.tooltipSide = "LEFT"
      if f.tipRight then f.tipRight:SetChecked(false) end
    else
      if f.tipRight and not f.tipRight:GetChecked() then self:SetChecked(true) end
    end
  end)

  f.tipOffset = CreateSlider("Tooltip X offset", 18, -342, 0, 80, 1, function(_, v)
    DB.tooltipOffset = math.floor(ClampNum(v, 0, 80) + 0.5)
  end)
  f.tipOffset:SetWidth(280)

  f.tipWidth = CreateSlider("Tooltip width", 18, -384, 160, 420, 5, function(_, v)
    DB.tooltipWidth = math.floor(ClampNum(v, 160, 420) + 0.5)
  end)
  f.tipWidth:SetWidth(280)

  local fontLabel = f.panelGeneral:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fontLabel:SetPoint("TOPLEFT", 16, -434)
  fontLabel:SetText("Font")

  local AceGUI
  do
    local ls = _G and rawget(_G, "LibStub")
    if type(ls) == "function" then
      AceGUI = ls("AceGUI-3.0", true)
    end
  end

  f.fontPreset = CreateFrame("Button", nil, f.panelGeneral, "UIPanelButtonTemplate")
  f.fontPreset:SetSize(160, 20)
  f.fontPreset:SetPoint("TOPLEFT", 16, -450)
  f.fontPreset:SetText("Choose preset")

  local function GetFontPresetEntries()
    local out = {}
    for _, p in ipairs(FONT_PRESETS) do
      out[#out + 1] = { key = p.key, name = p.name, lsm = false }
    end
    local lsmFonts = GetLSMFontNames()
    if type(lsmFonts) == "table" then
      for _, n in ipairs(lsmFonts) do
        out[#out + 1] = { key = "lsm:" .. n, name = n, lsm = true }
      end
    end
    return out
  end

  if AceGUI and type(AceGUI.Create) == "function" then
    local ok, widget = pcall(AceGUI.Create, AceGUI, "Dropdown")
    ---@type any
    local w = widget
    if ok and w and w.frame then
      f._aceFontPreset = w
      w.frame:SetParent(f.panelGeneral)
      w.frame:ClearAllPoints()
      w.frame:SetPoint("TOPLEFT", 16, -450)
      if w.frame.SetFrameLevel and f.fontPreset.GetFrameLevel then
        w.frame:SetFrameLevel((f.fontPreset:GetFrameLevel() or 1) + 1)
      end

      if w.SetLabel then w:SetLabel("") end
      if w.label and w.label.Hide then w.label:Hide() end

      if w.dropdown and w.dropdown.ClearAllPoints and w.dropdown.SetPoint then
        w.dropdown:ClearAllPoints()
        w.dropdown:SetPoint("TOPLEFT", w.frame, "TOPLEFT", 0, 0)
        w.dropdown:SetPoint("TOPRIGHT", w.frame, "TOPRIGHT", 0, 0)
      end
      if w.dropdown and w.dropdown.SetHeight then w.dropdown:SetHeight(20) end
      if w.frame.SetHeight then w.frame:SetHeight(20) end
      if w.SetWidth then w:SetWidth(160) end

      do
        local list = {}
        for _, e in ipairs(GetFontPresetEntries()) do
          list[e.key] = e.lsm and ("LSM: " .. e.name) or e.name
        end
        if w.SetList then w:SetList(list) end
      end

      if w.SetValue then
        w:SetValue(tostring(DB.fontPreset or "default"))
      end

      if w.SetCallback then
        w:SetCallback("OnValueChanged", function(_, _, key)
          key = tostring(key or "default")
          DB.fontPreset = key
          if key ~= "custom" then
            DB.fontPath = ""
            if f.fontPath then f.fontPath:SetText("") end
          end
          if f._UpdateFontPathUI then f:_UpdateFontPathUI() end
          ApplyFonts()
          ApplyState()
          if f.Refresh then f:Refresh() end
        end)
      end

      if f.fontPreset.Hide then f.fontPreset:Hide() end
      if f.fontPreset.Disable then f.fontPreset:Disable() end
    end
  end

  f.fontPath = CreateFrame("EditBox", nil, f.panelGeneral, "InputBoxTemplate")
  f.fontPath:SetSize(240, 20)
  f.fontPath:SetPoint("TOPLEFT", 16, -474)
  f.fontPath:SetAutoFocus(false)
  local function CommitCustomFontPath(self)
    if tostring(DB.fontPreset or "") ~= "custom" then
      return
    end
    DB.fontPreset = "custom"
    DB.fontPath = tostring(self:GetText() or "")
    ApplyFonts()
    ApplyState()
  end

  f.fontPath:SetScript("OnEnterPressed", function(self)
    CommitCustomFontPath(self)
    self:ClearFocus()
  end)
  f.fontPath:SetScript("OnEditFocusLost", function(self)
    CommitCustomFontPath(self)
  end)
  f.fontPath:SetScript("OnEscapePressed", function(self)
    if tostring(DB.fontPreset or "") == "custom" then
      self:SetText(tostring(DB.fontPath or ""))
    else
      self:SetText("")
    end
    self:ClearFocus()
  end)

  f.fontHint = f.panelGeneral:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.fontHint:SetPoint("TOPLEFT", 16, -494)
  f.fontHint:SetText("Custom: set a path like Fonts\\FRIZQT__.TTF (Enter or click-away)")

  function f:_UpdateFontPathUI()
    local isCustom = (tostring(DB.fontPreset or "") == "custom")
    if isCustom then
      if f.fontPath.EnableMouse then f.fontPath:EnableMouse(true) end
      if f.fontPath.SetTextColor then f.fontPath:SetTextColor(1, 1, 1, 1) end
      if f.fontHint and f.fontHint.SetText then
        f.fontHint:SetText("Custom: set a path like Fonts\\FRIZQT__.TTF (Enter or click-away)")
      end
    else
      if f.fontPath.EnableMouse then f.fontPath:EnableMouse(false) end
      if f.fontPath.ClearFocus then f.fontPath:ClearFocus() end
      if f.fontPath.SetTextColor then f.fontPath:SetTextColor(0.6, 0.6, 0.6, 1) end
      if f.fontPath.SetText then f.fontPath:SetText("") end
      if f.fontHint and f.fontHint.SetText then
        f.fontHint:SetText("Custom path disabled (choose 'Custom path' preset)")
      end
    end
  end

  if not f._aceFontPreset then
    do
      local menu
      f.fontPreset:SetScript("OnClick", function(self)
        local function ApplyFontPreset(presetKey)
          presetKey = tostring(presetKey or "default")
          DB.fontPreset = presetKey
          if presetKey ~= "custom" then
            DB.fontPath = ""
            if f.fontPath then f.fontPath:SetText("") end
          end
          if f._UpdateFontPathUI then f:_UpdateFontPathUI() end
          ApplyFonts()
          ApplyState()
          if f.Refresh then f:Refresh() end
        end

        do
          local mu = _G and rawget(_G, "MenuUtil")
          if type(mu) == "table" and type(mu.CreateContextMenu) == "function" then
            mu.CreateContextMenu(self, function(_, root)
              if root and root.CreateTitle then
                root:CreateTitle("Font preset")
              end

              local entries = GetFontPresetEntries()
              for _, e in ipairs(entries) do
                local function IsSelected()
                  return tostring(DB.fontPreset or "default") == e.key
                end
                local function SetSelected()
                  ApplyFontPreset(e.key)
                end
                local label = e.lsm and ("LSM: " .. e.name) or e.name

                if root and root.CreateRadio then
                  root:CreateRadio(label, IsSelected, SetSelected)
                elseif root and root.CreateButton then
                  root:CreateButton(label, SetSelected)
                end
              end
            end)
            return
          end
        end

        if not (UIDropDownMenu_CreateInfo and ToggleDropDownMenu) then
          Print("Dropdown menu unavailable.")
          return
        end
        if not menu then
          menu = CreateFrame("Frame", "fr0z3nUI_DateTimeFontMenu", f, "UIDropDownMenuTemplate")
        end
        UIDropDownMenu_Initialize(menu, function(_, level)
          if level == 1 then
            local info = UIDropDownMenu_CreateInfo()
            for _, e in ipairs(GetFontPresetEntries()) do
              info.text = e.lsm and ("LSM: " .. e.name) or e.name
              info.checked = (tostring(DB.fontPreset or "default") == e.key)
              info.hasArrow = nil
              info.value = nil
              info.func = function()
                ApplyFontPreset(e.key)
                if CloseDropDownMenus then CloseDropDownMenus() end
              end
              UIDropDownMenu_AddButton(info, level)
            end
            return
          end
        end)
        ToggleDropDownMenu(1, nil, menu, self, 0, 0)
      end)
    end
  end

  f.timeSize = CreateSlider("Time size", 18, -518, 10, 72, 1, function(_, v)
    DB.timeSize = math.floor(ClampNum(v, 16, 72) + 0.5)
    ApplyFonts()
    ApplyState()
  end)
  f.timeSize:SetWidth(280)

  f.smallSize = CreateSlider("Day & Date size", 18, -560, 8, 24, 1, function(_, v)
    local sz = math.floor(ClampNum(v, 8, 24) + 0.5)
    DB.daySize = sz
    DB.dateSize = sz
    ApplyFonts()
    ApplyState()
  end)
  f.smallSize:SetWidth(280)

  f.ampmSize = CreateSlider("AM/PM size", 18, -602, 8, 36, 1, function(_, v)
    DB.ampmSize = math.floor(ClampNum(v, 8, 36) + 0.5)
    ApplyFonts()
    ApplyState()
  end)
  f.ampmSize:SetWidth(280)

  local labels = f.panelGeneral:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  labels:SetPoint("TOPLEFT", 16, -644)
  labels:SetText("Tooltip labels")

  local function LabelBox(title, x, y, key)
    local t = f.panelGeneral:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    t:SetPoint("TOPLEFT", x, y)
    t:SetText(title)

    local eb = CreateFrame("EditBox", nil, f.panelGeneral, "InputBoxTemplate")
    eb:SetSize(90, 20)
    eb:SetPoint("TOPLEFT", x, y - 14)
    eb:SetAutoFocus(false)
    local function CommitLabel(self)
      DB.labels = DB.labels or {}
      DB.labels[key] = tostring(self:GetText() or "")
    end
    eb:SetScript("OnEnterPressed", function(self)
      CommitLabel(self)
      self:ClearFocus()
    end)
    eb:SetScript("OnEditFocusLost", function(self)
      CommitLabel(self)
    end)
    eb:SetScript("OnEscapePressed", function(self)
      self:SetText(GetLabel(key, title))
      self:ClearFocus()
    end)
    return eb
  end

  f.labelRealm = LabelBox("Realm", 16, -660, "realm")
  f.labelDaily = LabelBox("Daily", 120, -660, "daily")
  f.labelWeekly = LabelBox("Weekly", 224, -660, "weekly")

  local extraTitle = f.panelGeneral:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  extraTitle:SetPoint("TOPLEFT", 16, -696)
  extraTitle:SetText("Extra clocks (tooltip)")

  f.extraRows = {}
  local function EnsureExtraClockTable()
    if type(DB.extraClocks) ~= "table" then DB.extraClocks = {} end
  end

  local function RefreshExtraRows()
    EnsureExtraClockTable()
    for i = 1, 3 do
      local row = f.extraRows[i]
      if not row then
        row = CreateFrame("Frame", nil, f.panelGeneral)
        row:SetSize(300, 20)
        row:SetPoint("TOPLEFT", 16, -712 - (i - 1) * 22)

        row.enable = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.enable:SetPoint("LEFT", 0, 0)
        row.enable:SetSize(18, 18)

        row.name = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        row.name:SetSize(130, 20)
        row.name:SetPoint("LEFT", row.enable, "RIGHT", 4, 0)
        row.name:SetAutoFocus(false)

        row.offset = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        row.offset:SetSize(46, 20)
        row.offset:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
        row.offset:SetAutoFocus(false)

        row.offsetLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.offsetLabel:SetPoint("LEFT", row.offset, "RIGHT", 6, 0)
        row.offsetLabel:SetText("hrs (-24..+24)")

        f.extraRows[i] = row
      end

      local ec = DB.extraClocks[i]
      if type(ec) ~= "table" then
        ec = { name = "", offsetHours = 0, enabled = false }
        DB.extraClocks[i] = ec
      end

      row.enable:SetChecked(ec.enabled and true or false)
      row.enable:SetScript("OnClick", function(self)
        EnsureExtraClockTable()
        DB.extraClocks[i] = DB.extraClocks[i] or {}
        DB.extraClocks[i].enabled = self:GetChecked() and true or false
      end)

      row.name:SetText(tostring(ec.name or ""))
      local function CommitExtraName(self)
        EnsureExtraClockTable()
        DB.extraClocks[i] = DB.extraClocks[i] or {}
        DB.extraClocks[i].name = tostring(self:GetText() or "")
      end
      row.name:SetScript("OnEnterPressed", function(self)
        CommitExtraName(self)
        self:ClearFocus()
      end)
      row.name:SetScript("OnEditFocusLost", function(self)
        CommitExtraName(self)
      end)
      row.name:SetScript("OnEscapePressed", function(self)
        local cur = (DB.extraClocks and DB.extraClocks[i]) or {}
        self:SetText(tostring(cur.name or ""))
        self:ClearFocus()
      end)

      row.offset:SetText(tostring(tonumber(ec.offsetHours) or 0))
      local function CommitExtraOffset(self)
        EnsureExtraClockTable()
        DB.extraClocks[i] = DB.extraClocks[i] or {}
        local v = tonumber(self:GetText() or "") or 0
        if v > 24 then v = 24 end
        if v < -24 then v = -24 end
        DB.extraClocks[i].offsetHours = v
        self:SetText(tostring(v))
      end
      row.offset:SetScript("OnEnterPressed", function(self)
        CommitExtraOffset(self)
        self:ClearFocus()
      end)
      row.offset:SetScript("OnEditFocusLost", function(self)
        CommitExtraOffset(self)
      end)
      row.offset:SetScript("OnEscapePressed", function(self)
        local cur = (DB.extraClocks and DB.extraClocks[i]) or {}
        self:SetText(tostring(tonumber(cur.offsetHours) or 0))
        self:ClearFocus()
      end)
    end
  end

  local reset = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  reset:SetSize(90, 22)
  reset:SetPoint("BOTTOMLEFT", 12, 12)
  reset:SetText("Reset")
  reset:SetScript("OnClick", function() if ResetDefaults then ResetDefaults() end end)

  local centerWin = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  centerWin:SetSize(90, 22)
  centerWin:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
  centerWin:SetText("Center")
  centerWin:SetScript("OnClick", function()
    if not DB then return end
    DB.optionsX, DB.optionsY = 0, 0
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end)

  local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  close:SetSize(90, 22)
  close:SetPoint("BOTTOMRIGHT", -12, 12)
  close:SetText("Close")
  close:SetScript("OnClick", function() f:Hide() end)

  -- Style tab
  do
    local p = f.panelStyle

    local function CreateCheckOn(parent, label, x, y, onClick)
      local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
      cb:SetPoint("TOPLEFT", x, y)
      cb.text:SetText(label)
      cb:SetScript("OnClick", function(self)
        if type(onClick) == "function" then onClick(self) end
      end)
      return cb
    end

    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 16, -36)
    title:SetText("Display")

    f.showDay = CreateCheckOn(p, "Show day", 16, -56, function(self)
      DB.showDay = self:GetChecked() and true or false
      ApplyLayout()
      ApplyState()
    end)

    f.showDate = CreateCheckOn(p, "Show date", 16, -80, function(self)
      DB.showDate = self:GetChecked() and true or false
      ApplyLayout()
      ApplyState()
    end)

    f.monthAbbrev = CreateCheckOn(p, "Abbreviate month (JAN)", 16, -104, function(self)
      DB.monthAbbrev = self:GetChecked() and true or false
      ApplyState()
    end)

    local layoutLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    layoutLabel:SetPoint("TOPLEFT", 16, -112)
    layoutLabel:SetText("Layout")

    local alignLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    alignLabel:SetPoint("TOPLEFT", 16, -148)
    alignLabel:SetText("Alignment")

    f.textAlign = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    f.textAlign:SetSize(220, 20)
    f.textAlign:SetPoint("TOPLEFT", 16, -164)
    f.textAlign:SetText("Align: Left")

    do
      local menu
      f.textAlign:SetScript("OnClick", function(btn)
        if not (UIDropDownMenu_CreateInfo and ToggleDropDownMenu) then
          Print("Dropdown menu unavailable.")
          return
        end
        if not menu then
          menu = CreateFrame("Frame", "fr0z3nUI_DateTimeAlignMenu", f, "UIDropDownMenuTemplate")
        end
        UIDropDownMenu_Initialize(menu, function(_, level)
          local info = UIDropDownMenu_CreateInfo()
          local entries = {
            { key = "LEFT", text = "Left" },
            { key = "CENTER", text = "Center" },
            { key = "RIGHT", text = "Right" },
          }
          for _, e in ipairs(entries) do
            info.text = e.text
            info.checked = (tostring(DB.textAlign or "LEFT"):upper() == e.key)
            info.func = function()
              DB.textAlign = e.key
              ApplyLayout()
              ApplyState()
              if f.Refresh then f:Refresh() end
            end
            UIDropDownMenu_AddButton(info, level)
          end
        end)
        ToggleDropDownMenu(1, nil, menu, btn, 0, 0)
      end)
    end

    local function CreateStyleSlider(label, x, y, minV, maxV, step, onValue)
      sliderIndex = sliderIndex + 1
      local sliderName = "fr0z3nUI_DateTimeStyleSlider" .. sliderIndex
      local s = CreateFrame("Slider", sliderName, p, "OptionsSliderTemplate")
      s:SetPoint("TOPLEFT", x, y)
      s:SetMinMaxValues(minV, maxV)
      s:SetValueStep(step or 1)
      s:SetObeyStepOnDrag(true)

      local function FormatValue(v)
        local st = tonumber(step) or 1
        if st < 1 then
          if st <= 0.05 then
            return string.format("%.2f", tonumber(v) or 0)
          end
          return string.format("%.1f", tonumber(v) or 0)
        end
        return tostring(math.floor((tonumber(v) or 0) + 0.5))
      end

      local txt = _G[sliderName .. "Text"]
      if txt and txt.SetText then txt:SetText(tostring(label or "")) end

      s._valueText = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      s._valueText:SetPoint("LEFT", txt or s, "RIGHT", 8, 0)
      s._valueText:SetText("")

      local low = _G[sliderName .. "Low"]
      if low and low.SetText then low:SetText(tostring(minV)) end
      local high = _G[sliderName .. "High"]
      if high and high.SetText then high:SetText(tostring(maxV)) end

      s:SetScript("OnValueChanged", function(self, v)
        if self._valueText and self._valueText.SetText then
          self._valueText:SetText(FormatValue(v))
        end
        if type(onValue) == "function" then onValue(self, v) end
      end)

      if s._valueText and s.GetValue then
        s._valueText:SetText(FormatValue(s:GetValue()))
      end
      return s
    end

    local spacingTitle = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spacingTitle:SetPoint("TOPLEFT", 16, -196)
    spacingTitle:SetText("Spacing")

    f.gapDayDate = CreateStyleSlider("Gap: Day ↔ Date", 18, -212, 0, 20, 1, function(_, v)
      DB.gapDayDate = math.floor(ClampNum(v, 0, 20) + 0.5)
      ApplyLayout()
      ApplyState()
    end)
    f.gapDayDate:SetWidth(280)

    f.gapDateTime = CreateStyleSlider("Gap: Date ↔ Time", 18, -254, 0, 40, 1, function(_, v)
      DB.gapDateTime = math.floor(ClampNum(v, 0, 40) + 0.5)
      ApplyLayout()
      ApplyState()
    end)
    f.gapDateTime:SetWidth(280)

    local offsetsTitle = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    offsetsTitle:SetPoint("TOPLEFT", 16, -296)
    offsetsTitle:SetText("Offsets")

    f.timeXOffset = CreateStyleSlider("Time X offset", 18, -312, -30, 30, 1, function(_, v)
      DB.timeXOffset = math.floor(ClampNum(v, -30, 30) + 0.5)
      ApplyLayout()
      ApplyState()
    end)
    f.timeXOffset:SetWidth(280)

    f.timeYOffset = CreateStyleSlider("Time Y offset", 18, -354, -30, 30, 1, function(_, v)
      DB.timeYOffset = math.floor(ClampNum(v, -30, 30) + 0.5)
      ApplyLayout()
      ApplyState()
    end)
    f.timeYOffset:SetWidth(280)

    f.ampmGapX = CreateStyleSlider("AM/PM X gap", 18, -396, -20, 40, 1, function(_, v)
      DB.ampmGapX = math.floor(ClampNum(v, -20, 40) + 0.5)
      ApplyLayout()
      UpdateTimeGroupSize()
      ApplyState()
    end)
    f.ampmGapX:SetWidth(280)

    f.ampmYOffset = CreateStyleSlider("AM/PM Y offset", 18, -438, -20, 40, 1, function(_, v)
      DB.ampmYOffset = math.floor(ClampNum(v, -20, 40) + 0.5)
      ApplyLayout()
      ApplyState()
    end)
    f.ampmYOffset:SetWidth(280)

    f.layoutMode = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    f.layoutMode:SetSize(220, 20)
    f.layoutMode:SetPoint("TOPLEFT", 16, -128)
    f.layoutMode:SetText("Layout: Stacked")

    do
      local menu
      f.layoutMode:SetScript("OnClick", function(btn)
        if not (UIDropDownMenu_CreateInfo and ToggleDropDownMenu) then
          Print("Dropdown menu unavailable.")
          return
        end
        if not menu then
          menu = CreateFrame("Frame", "fr0z3nUI_DateTimeLayoutMenu", f, "UIDropDownMenuTemplate")
        end
        UIDropDownMenu_Initialize(menu, function(_, level)
          local info = UIDropDownMenu_CreateInfo()
          local entries = {
            { key = "STACKED", text = "Stacked (day on top, date below)" },
            { key = "INLINE", text = "Inline (day + date on one line)" },
          }
          for _, e in ipairs(entries) do
            info.text = e.text
            info.checked = (tostring(DB.layoutMode or "STACKED"):upper() == e.key)
            info.func = function()
              DB.layoutMode = e.key
              ApplyLayout()
              ApplyState()
              if f.Refresh then f:Refresh() end
            end
            UIDropDownMenu_AddButton(info, level)
          end
        end)
        ToggleDropDownMenu(1, nil, menu, btn, 0, 0)
      end)
    end

    local colorsTitle = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colorsTitle:SetPoint("TOPLEFT", 16, -482)
    colorsTitle:SetText("Colors")

    f.colorMode = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    f.colorMode:SetSize(220, 20)
    f.colorMode:SetPoint("TOPLEFT", 16, -498)
    f.colorMode:SetText("Color: Default")

    local function SetSwatch(btn, r, g, b, a)
      btn._swatch = btn._swatch or btn:CreateTexture(nil, "OVERLAY")
      btn._swatch:SetSize(14, 14)
      btn._swatch:SetPoint("LEFT", btn, "LEFT", 6, 0)
      btn._swatch:SetColorTexture(ClampNum(r, 0, 1), ClampNum(g, 0, 1), ClampNum(b, 0, 1), ClampNum(a, 0, 1))
    end

    local function OpenColorPicker(r, g, b, a, onChange)
      if not ColorPickerFrame then
        Print("Color picker unavailable.")
        return
      end
      local op = _G and rawget(_G, "OpacitySliderFrame")
      r, g, b, a = ClampNum(r, 0, 1), ClampNum(g, 0, 1), ClampNum(b, 0, 1), ClampNum(a, 0, 1)

      local function Apply()
        local nr, ng, nb
        if ColorPickerFrame.GetColorRGB then
          nr, ng, nb = ColorPickerFrame:GetColorRGB()
        elseif ColorPickerFrame.Content and ColorPickerFrame.Content.ColorPicker then
          nr, ng, nb = ColorPickerFrame.Content.ColorPicker:GetColorRGB()
        end

        local na = a
        if ColorPickerFrame.HasOpacity and ColorPickerFrame:HasOpacity() and ColorPickerFrame.GetColorAlpha then
          na = ColorPickerFrame:GetColorAlpha()
        elseif op and op.GetValue then
          na = 1 - (op:GetValue() or 0)
        end

        if type(onChange) == "function" then
          onChange(ClampNum(nr, 0, 1), ClampNum(ng, 0, 1), ClampNum(nb, 0, 1), ClampNum(na, 0, 1))
        end
      end

      if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
          r = r, g = g, b = b,
          opacity = 1 - a,
          hasOpacity = true,
          swatchFunc = Apply,
          opacityFunc = Apply,
          cancelFunc = function(prev)
            if type(onChange) == "function" then
              onChange(prev.r, prev.g, prev.b, 1 - (prev.opacity or 0))
            end
          end,
        })
      else
        ColorPickerFrame.func = Apply
        ColorPickerFrame.opacityFunc = Apply
        ColorPickerFrame.cancelFunc = function(prev)
          if type(onChange) == "function" and type(prev) == "table" then
            onChange(prev.r, prev.g, prev.b, 1 - (prev.opacity or 0))
          end
        end
        ColorPickerFrame.hasOpacity = true
        ColorPickerFrame.opacity = 1 - a
        ColorPickerFrame.previousValues = { r = r, g = g, b = b, opacity = 1 - a }
        if ColorPickerFrame.SetColorRGB then
          ColorPickerFrame:SetColorRGB(r, g, b)
        end
        if op and op.SetValue then
          op:SetValue(1 - a)
        end
        ColorPickerFrame:Show()
      end
    end

    local function UpdateStyleUI()
      local cm = tostring(DB.colorMode or "someclass"):lower()
      local label = (cm == "solid") and "Solid (Custom)"
        or (cm == "allclass") and "All Class"
        or (cm == "custom") and "Custom"
        or "Default (Some Class)"
      f.colorMode:SetText("Color: " .. label)

      if f.textAlign then
        local a = tostring(DB.textAlign or "LEFT"):upper()
        local an = (a == "CENTER") and "Center" or (a == "RIGHT") and "Right" or "Left"
        f.textAlign:SetText("Align: " .. an)
      end

      local lm = tostring(DB.layoutMode or "STACKED"):upper()
      f.layoutMode:SetText("Layout: " .. ((lm == "INLINE") and "Inline" or "Stacked"))

      EnsureCustomColors()
      local enableCustom = (cm == "custom")
      local buttons = { f.colorDay, f.colorDate, f.colorTime, f.colorAMPM, f.colorAllParts }
      for _, b in ipairs(buttons) do
        if b then
          if enableCustom then b:Enable() else b:Disable() end
        end
      end
      if f.colorDay then SetSwatch(f.colorDay, DB.customColors.day[1], DB.customColors.day[2], DB.customColors.day[3], DB.customColors.day[4]) end
      if f.colorDate then SetSwatch(f.colorDate, DB.customColors.date[1], DB.customColors.date[2], DB.customColors.date[3], DB.customColors.date[4]) end
      if f.colorTime then SetSwatch(f.colorTime, DB.customColors.time[1], DB.customColors.time[2], DB.customColors.time[3], DB.customColors.time[4]) end
      if f.colorAMPM then SetSwatch(f.colorAMPM, DB.customColors.ampm[1], DB.customColors.ampm[2], DB.customColors.ampm[3], DB.customColors.ampm[4]) end
      if f.colorWhole then
        local r, g, b, a = GetTextRGBA()
        SetSwatch(f.colorWhole, r, g, b, a)
      end

      if f.colonUseClass then
        f.colonUseClass:SetChecked(DB.colonUseClass and true or false)
      end
      if f.colorColon then
        local c = (DB and type(DB.colonColor) == "table") and DB.colonColor or { 1, 1, 1, 1 }
        SetSwatch(f.colorColon, c[1], c[2], c[3], c[4])
        if DB and DB.colonUseClass then
          f.colorColon:Disable()
        else
          f.colorColon:Enable()
        end
      end
    end
    f._UpdateStyleUI = UpdateStyleUI

    do
      local menu
      f.colorMode:SetScript("OnClick", function(btn)
        if not (UIDropDownMenu_CreateInfo and ToggleDropDownMenu) then
          Print("Dropdown menu unavailable.")
          return
        end
        if not menu then
          menu = CreateFrame("Frame", "fr0z3nUI_DateTimeColorMenu", f, "UIDropDownMenuTemplate")
        end
        UIDropDownMenu_Initialize(menu, function(_, level)
          local info = UIDropDownMenu_CreateInfo()
          local entries = {
            { key = "solid", text = "Solid (one custom color for all)" },
            { key = "someclass", text = "Default (Some Class: time + AM/PM)" },
            { key = "allclass", text = "All Class" },
            { key = "custom", text = "Custom" },
          }
          for _, e in ipairs(entries) do
            info.text = e.text
            info.checked = (tostring(DB.colorMode or "someclass"):lower() == e.key)
            info.func = function()
              DB.colorMode = e.key
              ApplyState()
              UpdateStyleUI()
            end
            UIDropDownMenu_AddButton(info, level)
          end
        end)
        ToggleDropDownMenu(1, nil, menu, btn, 0, 0)
      end)
    end

    local function MakeColorButton(text, x, y, key)
      local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
      b:SetSize(140, 20)
      b:SetPoint("TOPLEFT", x, y)
      b:SetText("   " .. text)
      b:SetScript("OnClick", function()
        EnsureCustomColors()
        local c = DB.customColors[key]
        OpenColorPicker(c[1], c[2], c[3], c[4], function(r, g, b2, a)
          EnsureCustomColors()
          DB.customColors[key] = { r, g, b2, a }
          ApplyState()
          UpdateStyleUI()
        end)
      end)
      return b
    end

    local function MakeWholeColorButton(text, x, y)
      local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
      b:SetSize(300, 20)
      b:SetPoint("TOPLEFT", x, y)
      b:SetText("   " .. text)
      b:SetScript("OnClick", function()
        local r, g, b2, a = GetTextRGBA()
        OpenColorPicker(r, g, b2, a, function(nr, ng, nb, na)
          DB.textColor = { nr, ng, nb, na }
          DB.colorMode = "solid"
          ApplyState()
          UpdateStyleUI()
        end)
      end)
      return b
    end

    local function MakeAllPartsButton(text, x, y)
      local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
      b:SetSize(300, 20)
      b:SetPoint("TOPLEFT", x, y)
      b:SetText("   " .. text)
      b:SetScript("OnClick", function()
        EnsureCustomColors()
        local c = DB.customColors.time
        OpenColorPicker(c[1], c[2], c[3], c[4], function(r, g, b2, a)
          EnsureCustomColors()
          DB.customColors.day = { r, g, b2, a }
          DB.customColors.date = { r, g, b2, a }
          DB.customColors.time = { r, g, b2, a }
          DB.customColors.ampm = { r, g, b2, a }
          DB.colorMode = "custom"
          ApplyState()
          UpdateStyleUI()
        end)
      end)
      return b
    end

    f.colorWhole = MakeWholeColorButton("Whole color (sets Solid mode)", 16, -532)
    f.colorAllParts = MakeAllPartsButton("Custom: apply one color to all parts", 16, -558)

    f.colonUseClass = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    f.colonUseClass:SetPoint("TOPLEFT", 16, -584)
    f.colonUseClass.text:SetText("Colon uses class color")
    f.colonUseClass:SetScript("OnClick", function(self)
      DB.colonUseClass = self:GetChecked() and true or false
      ApplyState()
      if f._UpdateStyleUI then f._UpdateStyleUI() end
    end)

    f.colorColon = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    f.colorColon:SetSize(300, 20)
    f.colorColon:SetPoint("TOPLEFT", 16, -610)
    f.colorColon:SetText("   Colon color (when not using class)")
    f.colorColon:SetScript("OnClick", function()
      local c = (DB and type(DB.colonColor) == "table") and DB.colonColor or { 1, 1, 1, 1 }
      OpenColorPicker(c[1], c[2], c[3], c[4], function(r, g, b2, a)
        DB.colonColor = { r, g, b2, a }
        DB.colonUseClass = false
        ApplyState()
        if f._UpdateStyleUI then f._UpdateStyleUI() end
      end)
    end)

    f.colorDay = MakeColorButton("Day", 16, -640, "day")
    f.colorDate = MakeColorButton("Date", 176, -640, "date")
    f.colorTime = MakeColorButton("Time", 16, -666, "time")
    f.colorAMPM = MakeColorButton("AM/PM", 176, -666, "ampm")

    UpdateStyleUI()
  end

  -- Alarms tab
  do
    local p = f.panelAlarms

    local help = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 16, -36)
    help:SetText("Alarms use realm time. Format: HH:MM")

    f.alarmClickToStop = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    f.alarmClickToStop:SetPoint("TOPLEFT", 16, -58)
    f.alarmClickToStop.text:SetText("Click clock to stop active alarms")
    f.alarmClickToStop:SetScript("OnClick", function(self)
      DB.alarmClickToStop = self:GetChecked() and true or false
    end)

    local scroll = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -86)
    scroll:SetPoint("BOTTOMRIGHT", -30, 44)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    f._alarmScroll = scroll
    f._alarmContent = content
    f._alarmRows = {}

    local add = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    add:SetSize(120, 22)
    add:SetPoint("BOTTOMLEFT", 16, 12)
    add:SetText("Add alarm")
    add:SetScript("OnClick", function()
      EnsureCharDB()
      if type(DB.alarms) ~= "table" then DB.alarms = {} end
      local now = GetBaseTimeSeconds()
      local t = date("%H:%M", now)
      DB.alarms[#DB.alarms + 1] = {
        enabled = true,
        time = t,
        name = "",
        schedule = "daily",
        sound = "raidwarning",
        flash = true,
        repeatEvery = 10,
        repeatFor = 60,
        untilClick = true,
      }
      if f.RefreshAlarms then f:RefreshAlarms() end
    end)

    local function BuildAlarmView()
      local v = {}
      for i, a in ipairs(GetAccountAlarms()) do v[#v + 1] = { scope = "account", index = i, alarm = a } end
      for i, a in ipairs(GetCharAlarms()) do v[#v + 1] = { scope = "char", index = i, alarm = a } end
      return v
    end

    local function CreateSoundButton(parent)
      local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
      b:SetSize(90, 18)
      b:SetText("Sound")
      return b
    end

    function f:RefreshAlarms()
      if not optionsFrame then return end
      EnsureCharDB()
      local view = BuildAlarmView()

      content:SetHeight(math.max(1, #view * 60))

      for i = 1, #view do
        local row = f._alarmRows[i]
        if not row then
          row = CreateFrame("Frame", nil, content)
          row:SetSize(280, 60)

          row.enable = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
          row.enable:SetPoint("TOPLEFT", 0, 0)
          row.enable:SetSize(18, 18)

          row.hh = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
          row.hh:SetSize(26, 18)
          row.hh:SetPoint("TOPLEFT", 22, -1)
          row.hh:SetAutoFocus(false)

          row.colon = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
          row.colon:SetPoint("LEFT", row.hh, "RIGHT", 2, 0)
          row.colon:SetText(":")

          row.mm = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
          row.mm:SetSize(26, 18)
          row.mm:SetPoint("LEFT", row.colon, "RIGHT", 2, 0)
          row.mm:SetAutoFocus(false)

          row.ampm = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
          row.ampm:SetSize(34, 18)
          row.ampm:SetPoint("LEFT", row.mm, "RIGHT", 4, 0)
          row.ampm:SetText("AM")

          row.name = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
          row.name:SetSize(98, 18)
          row.name:SetPoint("TOPLEFT", 98, -1)
          row.name:SetAutoFocus(false)

          row.del = CreateFrame("Button", nil, row, "UIPanelCloseButton")
          row.del:SetSize(18, 18)
          row.del:SetPoint("TOPRIGHT", 6, 0)

          row.sound = CreateSoundButton(row)
          row.sound:SetPoint("TOPLEFT", 0, -22)

          row.flash = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
          row.flash:SetPoint("LEFT", row.sound, "RIGHT", 6, 0)
          row.flash:SetSize(18, 18)
          row.flash.text:SetText("Flash")

          row.schedule = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
          row.schedule:SetSize(70, 18)
          row.schedule:SetPoint("LEFT", row.flash.text, "RIGHT", 8, 0)
          row.schedule:SetText("Daily")

          row.date = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
          row.date:SetSize(76, 18)
          row.date:SetPoint("LEFT", row.schedule, "RIGHT", 6, 0)
          row.date:SetAutoFocus(false)

          row.repeatEvery = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
          row.repeatEvery:SetSize(40, 18)
          row.repeatEvery:SetPoint("LEFT", row.date, "RIGHT", 6, 0)
          row.repeatEvery:SetAutoFocus(false)

          row.repeatLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
          row.repeatLabel:SetPoint("LEFT", row.repeatEvery, "RIGHT", 6, 0)
          row.repeatLabel:SetText("every")

          row.duration = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
          row.duration:SetSize(40, 18)
          row.duration:SetPoint("LEFT", row.repeatLabel, "RIGHT", 6, 0)
          row.duration:SetAutoFocus(false)

          row.durationLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
          row.durationLabel:SetPoint("LEFT", row.duration, "RIGHT", 6, 0)
          row.durationLabel:SetText("for")

          row.untilClick = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
          row.untilClick:SetPoint("LEFT", row.durationLabel, "RIGHT", 10, 0)
          row.untilClick:SetSize(18, 18)
          row.untilClick.text:SetText("Until click")

          row.isChar = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
          row.isChar:SetPoint("TOPLEFT", 204, -1)
          row.isChar:SetSize(18, 18)
          row.isChar.text:SetText("Char")

          f._alarmRows[i] = row
        end

        row:SetPoint("TOPLEFT", 0, -(i - 1) * 60)
        row:SetPoint("TOPRIGHT", 0, -(i - 1) * 60)

        local entry = view[i]
        local alarm = entry.alarm
        row.enable:SetChecked(alarm.enabled ~= false)
        row.enable:SetScript("OnClick", function(self)
          alarm.enabled = self:GetChecked() and true or false
        end)

        do
          local hh, mm, ap = Time12From24(alarm.time)
          row.hh:SetText(hh)
          row.mm:SetText(mm)
          row.ampm:SetText(ap)

          local function CommitTime()
            local h = tostring(row.hh:GetText() or ""):gsub("%s+", "")
            local m = tostring(row.mm:GetText() or ""):gsub("%s+", "")
            local ampm = tostring(row.ampm:GetText() or "AM"):upper()
            local hN = tonumber(h)
            local mN = tonumber(m)
            local t24 = Time24From12(hN, mN, ampm)
            if not t24 then
              Print("Invalid time. Use HH MM + AM/PM")
              local rh, rm, rap = Time12From24(alarm.time)
              row.hh:SetText(rh)
              row.mm:SetText(rm)
              row.ampm:SetText(rap)
              return
            end
            alarm.time = t24
            local rh, rm, rap = Time12From24(alarm.time)
            row.hh:SetText(rh)
            row.mm:SetText(rm)
            row.ampm:SetText(rap)
          end

          row.hh:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            CommitTime()
          end)
          row.mm:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            CommitTime()
          end)
          row.ampm:SetScript("OnClick", function()
            local cur = tostring(row.ampm:GetText() or "AM"):upper()
            row.ampm:SetText((cur == "PM") and "AM" or "PM")
            CommitTime()
          end)
        end

        row.name:SetText(tostring(alarm.name or ""))
        row.name:SetScript("OnEnterPressed", function(self)
          self:ClearFocus()
          alarm.name = tostring(self:GetText() or "")
        end)

        row.flash:SetChecked(alarm.flash and true or false)
        row.flash:SetScript("OnClick", function(self)
          alarm.flash = self:GetChecked() and true or false
        end)

        do
          local function UpdateScheduleUI()
            local s = tostring(alarm.schedule or "daily"):lower()
            if s ~= "daily" and s ~= "today" and s ~= "date" then s = "daily" end
            alarm.schedule = s

            local label = (s == "today") and "Today" or (s == "date") and "Date" or "Daily"
            row.schedule:SetText(label)

            if s == "date" then
              row.date:Enable()
            else
              row.date:Disable()
            end
          end

          row.date:SetText(tostring(alarm.date or ""))
          row.date:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            local d = NormalizeAlarmDate(self:GetText())
            if not d then
              Print("Invalid date. Use YYYY-MM-DD")
              self:SetText(tostring(alarm.date or ""))
              return
            end
            alarm.date = d
            self:SetText(d)
          end)

          row.schedule:SetScript("OnClick", function(btn)
            if not (UIDropDownMenu_CreateInfo and ToggleDropDownMenu) then
              -- Fallback: cycle
              local cur = tostring(alarm.schedule or "daily"):lower()
              local next = (cur == "daily") and "today" or (cur == "today") and "date" or "daily"
              alarm.schedule = next
              if next == "today" then
                alarm.onceDay = DayKey(GetBaseTimeSeconds())
              end
              UpdateScheduleUI()
              return
            end

            if not f._alarmScheduleMenu then
              f._alarmScheduleMenu = CreateFrame("Frame", "fr0z3nUI_DateTimeAlarmScheduleMenu", f, "UIDropDownMenuTemplate")
            end
            UIDropDownMenu_Initialize(f._alarmScheduleMenu, function(_, level)
              local info = UIDropDownMenu_CreateInfo()
              local entries = {
                { key = "today", text = "Today (one-shot)" },
                { key = "daily", text = "Daily" },
                { key = "date", text = "Specific date" },
              }
              for _, e in ipairs(entries) do
                info.text = e.text
                info.checked = (tostring(alarm.schedule or "daily"):lower() == e.key)
                info.func = function()
                  alarm.schedule = e.key
                  if e.key == "today" then
                    alarm.onceDay = DayKey(GetBaseTimeSeconds())
                  end
                  UpdateScheduleUI()
                end
                UIDropDownMenu_AddButton(info, level)
              end
            end)
            ToggleDropDownMenu(1, nil, f._alarmScheduleMenu, btn, 0, 0)
          end)

          UpdateScheduleUI()
        end

        row.repeatEvery:SetText(tostring(tonumber(alarm.repeatEvery) or 10))
        row.repeatEvery:SetScript("OnEnterPressed", function(self)
          self:ClearFocus()
          local v = tonumber(self:GetText() or "") or 10
          if v < 1 then v = 1 end
          if v > 300 then v = 300 end
          alarm.repeatEvery = v
          self:SetText(tostring(v))
        end)

        row.duration:SetText(tostring(tonumber(alarm.repeatFor) or 60))
        row.duration:SetScript("OnEnterPressed", function(self)
          self:ClearFocus()
          local v = tonumber(self:GetText() or "") or 60
          if v < 1 then v = 1 end
          if v > 3600 then v = 3600 end
          alarm.repeatFor = v
          self:SetText(tostring(v))
        end)

        row.untilClick:SetChecked(alarm.untilClick and true or false)
        row.untilClick:SetScript("OnClick", function(self)
          alarm.untilClick = self:GetChecked() and true or false
        end)

        row.isChar:SetChecked(entry.scope == "char")
        row.isChar:SetScript("OnClick", function(self)
          local wantChar = self:GetChecked() and true or false
          if wantChar and entry.scope ~= "char" then
            local aList = GetAccountAlarms()
            local cList = GetCharAlarms()
            local moved = table.remove(aList, entry.index)
            cList[#cList + 1] = moved
          elseif (not wantChar) and entry.scope ~= "account" then
            local cList = GetCharAlarms()
            local aList = GetAccountAlarms()
            local moved = table.remove(cList, entry.index)
            aList[#aList + 1] = moved
          end
          f:RefreshAlarms()
        end)

        row.sound:SetText("Sound")
        row.sound:SetScript("OnClick", function(btn)
          if not (UIDropDownMenu_CreateInfo and ToggleDropDownMenu) then
            Print("Dropdown menu unavailable.")
            return
          end
          if not f._alarmSoundMenu then
            f._alarmSoundMenu = CreateFrame("Frame", "fr0z3nUI_DateTimeAlarmSoundMenu", f, "UIDropDownMenuTemplate")
          end
          UIDropDownMenu_Initialize(f._alarmSoundMenu, function(_, level)
            local info = UIDropDownMenu_CreateInfo()
            for _, s in ipairs(ALARM_SOUND_PRESETS) do
              info.text = s.name
              info.checked = (tostring(alarm.sound or "raidwarning") == s.key)
              info.func = function()
                alarm.sound = s.key
                PlayAlarmSound(alarm.sound)
              end
              UIDropDownMenu_AddButton(info, level)
            end
          end)
          ToggleDropDownMenu(1, nil, f._alarmSoundMenu, btn, 0, 0)
        end)

        row.del:SetScript("OnClick", function()
          if entry.scope == "char" then
            table.remove(GetCharAlarms(), entry.index)
          else
            table.remove(GetAccountAlarms(), entry.index)
          end
          f:RefreshAlarms()
        end)

        row:Show()
      end
      for i = #view + 1, #f._alarmRows do
        if f._alarmRows[i] then f._alarmRows[i]:Hide() end
      end
    end
  end

  function f:Refresh()
    f.enable:SetChecked(DB.enabled and true or false)
    f.locked:SetChecked(DB.locked and true or false)
    f.use24h:SetChecked(DB.use24h and true or false)
    f.seconds:SetChecked(DB.showSeconds and true or false)
    f.scale:SetValue(ClampNum(tonumber(DB.scale), 0.5, 2.0))
    f.alpha:SetValue(ClampNum(tonumber(DB.alpha), 0, 1))
    f.dateUK:SetChecked(tostring(DB.dateLayout or "UK"):upper() ~= "US")
    f.dateUS:SetChecked(tostring(DB.dateLayout or "UK"):upper() == "US")
    f.lockouts:SetChecked(DB.showLockouts and true or false)
    f.tipRight:SetChecked(tostring(DB.tooltipSide or "RIGHT"):upper() ~= "LEFT")
    f.tipLeft:SetChecked(tostring(DB.tooltipSide or "RIGHT"):upper() == "LEFT")
    f.tipOffset:SetValue(ClampNum(tonumber(DB.tooltipOffset), 0, 80))
    if f.tipWidth then f.tipWidth:SetValue(ClampNum(tonumber(DB.tooltipWidth), 160, 420)) end
    do
      local key = tostring(DB.fontPreset or "default")
      if key == "lsm" then key = "bazooka" end
      local disp = key
      local lsmName = key:match("^lsm:(.+)$")
      if lsmName then
        disp = "LSM: " .. lsmName
      end
      ---@type any
      local w = f._aceFontPreset
      if w and w.SetValue then
        w:SetValue(key)
      end
      if f.fontPreset and f.fontPreset.SetText then
        f.fontPreset:SetText("Preset: " .. disp)
      end
    end
    if f._UpdateFontPathUI then f:_UpdateFontPathUI() end
    if tostring(DB.fontPreset or "") == "custom" then
      f.fontPath:SetText(tostring(DB.fontPath or ""))
    end
    f.timeSize:SetValue(ClampNum(tonumber(DB.timeSize), 16, 72))
    f.smallSize:SetValue(ClampNum(tonumber(DB.daySize), 8, 24))
    if f.ampmSize then f.ampmSize:SetValue(ClampNum(tonumber(DB.ampmSize), 8, 36)) end
    if f.labelRealm then f.labelRealm:SetText(GetLabel("realm", "Realm")) end
    if f.labelDaily then f.labelDaily:SetText(GetLabel("daily", "Daily")) end
    if f.labelWeekly then f.labelWeekly:SetText(GetLabel("weekly", "Weekly")) end
    RefreshExtraRows()
    if f.alarmClickToStop then f.alarmClickToStop:SetChecked(DB.alarmClickToStop and true or false) end
    if f.showDay then f.showDay:SetChecked(DB.showDay ~= false) end
    if f.showDate then f.showDate:SetChecked(DB.showDate ~= false) end
    if f.monthAbbrev then f.monthAbbrev:SetChecked(DB.monthAbbrev and true or false) end
    if f.gapDayDate then f.gapDayDate:SetValue(ClampNum(tonumber(DB.gapDayDate), 0, 20)) end
    if f.gapDateTime then f.gapDateTime:SetValue(ClampNum(tonumber(DB.gapDateTime), 0, 40)) end
    if f.timeXOffset then f.timeXOffset:SetValue(ClampNum(tonumber(DB.timeXOffset), -30, 30)) end
    if f.timeYOffset then f.timeYOffset:SetValue(ClampNum(tonumber(DB.timeYOffset), -30, 30)) end
    if f.ampmGapX then f.ampmGapX:SetValue(ClampNum(tonumber(DB.ampmGapX), -20, 40)) end
    if f.ampmYOffset then f.ampmYOffset:SetValue(ClampNum(tonumber(DB.ampmYOffset), -20, 40)) end
    if f._UpdateStyleUI then f._UpdateStyleUI() end
    SelectTab(f._activeTab or "general")
  end

  optionsFrame = f
  if f._UpdateFontPathUI then f:_UpdateFontPathUI() end
  SelectTab("general")
  return f
end

ResetDefaults = function()
  if type(fr0z3nUI_DateTimeDB) ~= "table" then fr0z3nUI_DateTimeDB = {} end
  for k in pairs(fr0z3nUI_DateTimeDB) do
    fr0z3nUI_DateTimeDB[k] = nil
  end
  EnsureDB()
  ApplyFonts()
  ApplyPosition()
  ApplyState()
  if optionsFrame and optionsFrame.Refresh then
    optionsFrame:Refresh()
  end
  Print("Reset to defaults.")
end

local function HandleSlash(msg)
  msg = tostring(msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

  if msg == "" or msg == "help" or msg == "options" then
    local f = EnsureOptionsFrame()
    f:Refresh()
    f:Show()
    return
  end

  if msg == "toggle" then
    DB.enabled = not DB.enabled
    ApplyState()
    Print(DB.enabled and "Enabled." or "Disabled.")
    return
  end

  if msg == "lock" then
    DB.locked = true
    ApplyState()
    Print("Locked.")
    return
  end

  if msg == "unlock" then
    DB.locked = false
    ApplyState()
    Print("Unlocked (drag to move).")
    return
  end

  if msg == "24" then
    DB.use24h = true
    ApplyState()
    Print("24-hour time.")
    return
  end

  if msg == "12" then
    DB.use24h = false
    ApplyState()
    Print("12-hour time.")
    return
  end

  if msg == "seconds" then
    DB.showSeconds = not DB.showSeconds
    ApplyState()
    Print(DB.showSeconds and "Seconds: on." or "Seconds: off.")
    return
  end

  do
    local s = msg:match("^scale%s+([%d%.]+)$")
    if s then
      local v = tonumber(s)
      if not v then
        Print("Scale must be a number.")
        return
      end
      v = Clamp(v, 0.5, 2.0)
      DB.scale = v
      ApplyState()
      Print("Scale set to " .. tostring(v) .. ".")
      return
    end
  end

  if msg == "reset" then
    ResetDefaults()
    return
  end

  Print("Unknown command. Type /fdt help")
end

function ns.ShowOptions()
  local f = EnsureOptionsFrame()
  f:Refresh()
  f:Show()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(_, event)
  if event ~= "PLAYER_LOGIN" then return end

  EnsureDB()
  EnsureClockFrame()

  SLASH_FR0Z3NUIDATETIME1 = "/fdt"
  SlashCmdList.FR0Z3NUIDATETIME = HandleSlash

  if DB.enabled then
    Print("Loaded. /fdt")
  end
end)
