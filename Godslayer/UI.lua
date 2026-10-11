-- Godslayer window (kill log, dossiers, guilds, leaderboard, hit list, stats), kill toast,
-- brag lines, minimap button, tooltip lines, slash commands.

local _, ns = ...
local plain, try = ns.plain, ns.try

local UI = {}
ns.UI = UI

local ICON = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"
local GOLD, WHITE, GREY, ORANGE = "|cffffd100", "|cffffffff", "|cff9d9d9d", "|cffff7d0a"
local ROWS, ROW_HEIGHT = 13, 18
local SHARE_GAP = 15 -- seconds between guild chat posts

local opts
local main, toast, minimapButton
local currentTab, offset = 1, 0
local dossierId -- the victim whose dossier is open over the kill log, if any
local phraseIndex, phraseZero
local lastShare = -SHARE_GAP

-- ---------------------------------------------------------------------------
-- Text helpers
-- ---------------------------------------------------------------------------

local function classColored(name, class)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c and c.r then
    return ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, name)
  end
  return name
end

local function ago(t)
  if not t then return "" end
  local s = time() - t
  if s < 60 then return "now" end
  if s < 3600 then return math.floor(s / 60) .. "m" end
  if s < 86400 then return math.floor(s / 3600) .. "h" end
  return math.floor(s / 86400) .. "d"
end

local function className(token)
  if type(token) ~= "string" or token == "" then return nil end
  local localized = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]
  if type(localized) == "string" then return localized end
  return token:sub(1, 1) .. token:sub(2):lower()
end

-- Nothing that could be read as an escape code or a phrase token goes to chat.
local function chatSafe(text)
  return (tostring(text):gsub("[|{}%c]", ""))
end

local function hourLabel(hour)
  local h = hour % 12
  if h == 0 then h = 12 end
  return h .. (hour < 12 and " AM" or " PM")
end

local function stamp(t)
  local text = t and try(date, "%b %d, %H:%M", t)
  return type(text) == "string" and text or ""
end

local function plural(n, one, many)
  return n .. " " .. (n == 1 and one or many)
end

-- "Level 34 Dwarf Paladin", from whatever parts are known.
local function describe(v)
  local parts = {}
  if v.level then parts[#parts + 1] = "Level " .. v.level end
  if v.race then parts[#parts + 1] = v.race end
  local class = className(v.class)
  if class then parts[#parts + 1] = class end
  return table.concat(parts, " ")
end

-- The key with the biggest count, and that count. Ties go to the alphabet so the
-- answer does not flicker between refreshes.
local function topKey(counts, skip)
  local best, bestN
  for key, n in pairs(counts) do
    if key ~= skip and (not bestN or n > bestN or (n == bestN and tostring(key) < tostring(best))) then
      best, bestN = key, n
    end
  end
  return best, bestN
end

local function sortedCounts(counts)
  local list = {}
  for key, n in pairs(counts) do list[#list + 1] = { key, n } end
  table.sort(list, function(a, b)
    if a[2] ~= b[2] then return a[2] > b[2] end
    return tostring(a[1]) < tostring(b[1])
  end)
  return list
end

local function guildLabel(guild, tier)
  if tier == "original" then return GOLD .. guild .. " (x" .. ns.ORIGINAL_POINTS .. ")|r" end
  return guild
end

-- The facts the newer brag lines need. Each is nil until the kill records can back it.
local function phraseFacts()
  local a, facts = ns.Aggregates(), {}
  local nemesis = ns.Nemesis()
  if nemesis then facts.nemesis = chatSafe(nemesis.name or "Unknown") .. " (" .. nemesis.kills .. " times)" end
  local zone = topKey(a.zone, ns.ELSEWHERE)
  if zone then facts.zone = chatSafe(zone) end
  local prey = topKey(a.class)
  if prey then facts.prey = prey:sub(1, 1) .. prey:sub(2):lower() .. "s" end
  local today = ns.KillsToday()
  if today >= 2 then facts.today = today .. " Olympus kills today" end
  if a.upset and a.upset.up >= 2 then facts.up = tostring(a.upset.up) end
  return facts
end
local FACT_TOKENS = { "nemesis", "zone", "prey", "today", "up" }

local function renderPhrase(template, facts)
  local c = ns.char
  local n, p, u, o = c.kills, c.points, c.uniques, c.orig
  facts = facts or phraseFacts()
  local words = {
    nemesis = facts.nemesis, zone = facts.zone, prey = facts.prey, today = facts.today, up = facts.up,
    n = n, p = p, u = u, o = o,
    kills = n .. " Olympus " .. (n == 1 and "kill" or "kills"),
    points = p .. " " .. (p == 1 and "point" or "points"),
    uniques = (u == 1) and "1 Olympian" or (u .. " different Olympians"),
    orig = o .. " from the original OLYMPUS guild",
    rank = (ns.RankFor(p)),
    king = ((c.kings or 0) > 1) and ("the King himself " .. c.kings .. " times") or "the King himself",
  }
  return (template:gsub("{(%a+)}", words))
end
UI.RenderPhrase = renderPhrase

local function phraseAllowed(template, facts)
  local c = ns.char
  for _, token in ipairs(FACT_TOKENS) do
    if not facts[token] and template:find("{" .. token .. "}", 1, true) then return false end
  end
  if c.kills < 2 and template:find("{n}", 1, true) then return false end
  if c.orig < 1 and (template:find("{orig}", 1, true) or template:find("{o}", 1, true)) then return false end
  if (c.kings or 0) < 1 and template:find("{king}", 1, true) then return false end
  return true
end

local function rollPhrase()
  local c = ns.char
  if c.kills == 0 then
    phraseZero = (phraseZero or math.random(#ns.PHRASES_ZERO)) % #ns.PHRASES_ZERO + 1
    phraseIndex = nil
    return
  end
  local pool, facts = {}, phraseFacts()
  for i, template in ipairs(ns.PHRASES) do
    if i ~= phraseIndex and phraseAllowed(template, facts) then pool[#pool + 1] = i end
  end
  phraseIndex = pool[math.random(#pool)] or 1
end

local function currentPhrase()
  local c = ns.char
  if c.kills == 0 then
    if not phraseZero then rollPhrase() end
    return ns.PHRASES_ZERO[phraseZero]
  end
  local facts = phraseFacts()
  if not phraseIndex or not phraseAllowed(ns.PHRASES[phraseIndex], facts) then rollPhrase() end
  return renderPhrase(ns.PHRASES[phraseIndex], facts)
end
UI.CurrentPhrase = currentPhrase

-- ---------------------------------------------------------------------------
-- Guild chat (only ever from a button click or a typed command)
-- ---------------------------------------------------------------------------

local function sayGuild(text)
  if not plain(try(IsInGuild)) then
    ns.Print("You are not in a guild, so there is nobody to brag to.")
    return false
  end
  if ns.ChatLockedDown() then
    ns.Print("The game holds addon chat in here (instance or match). Try again outside.")
    return false
  end
  local wait = SHARE_GAP - (GetTime() - lastShare)
  if wait > 0 then
    ns.Print(("Easy. You can post again in %d seconds."):format(math.ceil(wait)))
    return false
  end
  local sendChat = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  if type(sendChat) ~= "function" then return false end
  local ok, err = pcall(sendChat, chatSafe(text):sub(1, 255), "GUILD")
  if not ok then
    ns.Log("chat", err)
    ns.Print("The game refused that message.")
    return false
  end
  lastShare = GetTime()
  return true
end

function UI.Share()
  if sayGuild(currentPhrase()) then
    rollPhrase()
    UI.Refresh()
  end
end

function UI.ShareTop()
  local rows = ns.Comm.Leaderboard()
  local parts = {}
  for i = 1, math.min(3, #rows) do
    local r = rows[i]
    if r.kills > 0 then
      parts[#parts + 1] = ("%d. %s %d pts (%d %s)"):format(i, r.name, r.points, r.kills, r.kills == 1 and "kill" or "kills")
    end
  end
  if #parts == 0 then
    ns.Print("Nobody has an Olympus kill yet.")
    return
  end
  sayGuild("Godslayer top " .. #parts .. " Olympus hunters: " .. table.concat(parts, ", "))
end

-- ---------------------------------------------------------------------------
-- Table data
-- ---------------------------------------------------------------------------

local function victimRows()
  local list = {}
  for id, v in pairs(ns.char.victims) do
    if v.tier then list[#list + 1] = { v, id } end
  end
  table.sort(list, function(a, b)
    a, b = a[1], b[1]
    if a.points ~= b.points then return a.points > b.points end
    if a.kills ~= b.kills then return a.kills > b.kills end
    return (a.last or 0) > (b.last or 0)
  end)
  local rows = {}
  for i, pair in ipairs(list) do
    local v = pair[1]
    rows[i] = { i, classColored(v.name or "Unknown", v.class), v.level or "", guildLabel(v.guild or "", v.tier),
                v.kills, v.kb or 0, v.points, ago(v.last), id = pair[2] }
  end
  return rows
end

-- Everything known about one victim, as label and value lines.
local function dossierLines(id)
  local v = ns.char.victims[id]
  if not v then return {} end
  local L = {}
  local function add(label, value) L[#L + 1] = { GOLD .. label .. "|r", value } end
  local name = classColored(v.name or "Unknown", v.class)
  if v.king then name = name .. GOLD .. "  the King of Olympus|r" end
  add("Target", name)
  local who = describe(v)
  if who ~= "" and v.sex then who = who .. ", " .. (v.sex == 3 and "female" or "male") end
  if who ~= "" then add("Known as", who) end
  if v.title then add("PvP title", v.title) end
  add("Guild", guildLabel(v.guild or "?", v.tier) .. (v.tier and "" or GREY .. "  (not counted right now)|r"))
  if v.rank then
    local others = {}
    for _, pair in ipairs(sortedCounts(v.ranks or {})) do
      if pair[1] ~= v.rank then others[#others + 1] = pair[1] end
    end
    add("Rank in that guild", v.rank .. (#others > 0 and (GREY .. "  (also killed as " .. table.concat(others, ", ") .. ")|r") or ""))
  end
  local label, nextAt = ns.VictimTier(v.kills)
  add("What they are to you", ORANGE .. (label or "") .. "|r" ..
    (nextAt and (GREY .. "  (" .. (nextAt - v.kills) .. " more for the next title)|r") or ""))
  add("Kills", ("%s, %s, %s"):format(plural(v.kills, "kill", "kills"),
    plural(v.kb or 0, "killing blow", "killing blows"), plural(v.points, "point", "points")))
  if v.first then add("First kill", stamp(v.first) .. GREY .. "  " .. ago(v.first) .. " ago|r") end
  if v.last then add("Last kill", stamp(v.last) .. GREY .. "  " .. ago(v.last) .. " ago|r") end
  local records = {}
  if (v.dayBest or 0) > 1 then records[#records + 1] = v.dayBest .. " in one day" end
  if (v.bestRun or 0) > 1 then records[#records + 1] = v.bestRun .. " in a row without you dying" end
  if #records > 0 then add("Your best on them", table.concat(records, ", ")) end
  if v.up then
    add("Level gap", v.up > 0 and (v.up .. " above you at most") or (v.up == 0 and "your level" or ((-v.up) .. " below you at best")))
  end
  local hour, hourKills = topKey(v.hours or {})
  if hour and hourKills >= 2 then add("Usually dies around", hourLabel(hour)) end
  local zones = sortedCounts(v.zones or {})
  if #zones > 0 then
    local parts = {}
    for i = 1, math.min(3, #zones) do parts[i] = zones[i][1] .. " " .. zones[i][2] end
    if #zones > 3 then parts[#parts + 1] = "and " .. (#zones - 3) .. " more" end
    add("Killing grounds", table.concat(parts, ", "))
  end
  local hist = v.hist or {}
  if #hist == 0 then
    add("Kill history", GREY .. "No kill-by-kill details on file: these kills are from before version 1.1, or the feud is very old.|r")
  else
    add("Kill history", GREY .. "the last " .. #hist .. (v.kills > #hist and (" of " .. v.kills) or "") .. ", newest first|r")
    for i = #hist, 1, -1 do
      local h = hist[i]
      local where = h[2] ~= "" and h[2] or "somewhere"
      if h[3] ~= "" and h[3] ~= h[2] then where = where .. ", " .. h[3] end
      local extra = {}
      if h[5] > 0 then extra[#extra + 1] = "level " .. h[5] .. (h[6] > 0 and (" (you " .. h[6] .. ")") or "") end
      if h[4] == 1 then extra[#extra + 1] = "your killing blow" end
      L[#L + 1] = { WHITE .. stamp(h[1]) .. "|r", where .. (#extra > 0 and (GREY .. "   " .. table.concat(extra, ", ") .. "|r") or "") }
    end
  end
  return L
end
UI.DossierLines = dossierLines

local function hitRows()
  local rows = {}
  for i, k in ipairs(ns.HitList()) do
    rows[i] = { i, classColored(k.name, k.class), k.level or "", guildLabel(k.guild, k.tier), k.rank or "", k.zone or "", ago(k.t) }
  end
  return rows
end

local function statsRows()
  local a, rows = ns.Aggregates(), {}
  local function header(text) rows[#rows + 1] = { ORANGE .. text .. "|r", "", "", "" } end
  local function share(n, total) return total > 0 and (math.floor(n * 100 / total + 0.5) .. "%") or "" end
  local function who(v) return classColored(v.name or "Unknown", v.class) end
  header("Records")
  local nemesis = ns.Nemesis()
  rows[#rows + 1] = { "Nemesis", nemesis and who(nemesis) or GREY .. "nobody twice yet|r", nemesis and nemesis.kills or "", "" }
  rows[#rows + 1] = { "Kills today", "", ns.KillsToday(), "" }
  if a.day and a.day.dayBest > 1 then rows[#rows + 1] = { "Most on one player in a day", who(a.day), a.day.dayBest, "" } end
  if a.run and a.run.bestRun > 1 then rows[#rows + 1] = { "Most on one player in one life", who(a.run), a.run.bestRun, "" } end
  if a.highest then rows[#rows + 1] = { "Highest level killed", who(a.highest) .. GREY .. "  level " .. a.highest.level .. "|r", "", "" } end
  if a.upset and a.upset.up > 0 then rows[#rows + 1] = { "Biggest upset", who(a.upset) .. GREY .. "  " .. a.upset.up .. " levels above you|r", "", "" } end
  local sections = {
    { "By class", a.class, a.kills, function(key) return classColored(className(key) or key, key) end },
    { "By zone", a.zone, a.zoned },
    { "By rank inside their guild", a.rank, a.kills },
  }
  for _, section in ipairs(sections) do
    local list = sortedCounts(section[2])
    if #list > 0 then
      header(section[1])
      for i = 1, math.min(12, #list) do
        local key, n = list[i][1], list[i][2]
        rows[#rows + 1] = { "", section[4] and section[4](key) or key, n, share(n, section[3]) }
      end
    end
  end
  if a.timed > 0 then
    header("By hour of the day")
    for hour = 0, 23 do
      local n = a.hour[hour]
      if n then rows[#rows + 1] = { "", hourLabel(hour), n, share(n, a.timed) } end
    end
  end
  return rows
end

local function guildRows()
  local members = {}
  for _, v in pairs(ns.char.victims) do
    if v.tier and v.guild then members[v.guild] = (members[v.guild] or 0) + 1 end
  end
  local list = {}
  for guild, g in pairs(ns.char.guilds) do
    local tier = ns.Classify(guild)
    if tier then list[#list + 1] = { guild = guild, tier = tier, kills = g.kills, points = g.points } end
  end
  table.sort(list, function(a, b)
    if a.points ~= b.points then return a.points > b.points end
    return a.guild < b.guild
  end)
  local rows = {}
  for i, g in ipairs(list) do
    rows[i] = { i, guildLabel(g.guild, g.tier), members[g.guild] or 0, g.kills, g.points }
  end
  return rows
end

local function boardRows()
  local board = ns.Comm.Leaderboard()
  local rows = {}
  for i, r in ipairs(board) do
    local name = classColored(r.name, r.class)
    if (r.kings or 0) > 0 then name = name .. GOLD .. " [Kingslayer]|r" end
    if r.me then name = name .. GREY .. " (you)|r" end
    rows[i] = { i, name, (ns.RankFor(r.points)), r.kills, r.uniques, r.kb, r.orig, r.points }
  end
  return rows
end

local TABS = {
  { label = "Kill Log", rows = victimRows, empty = "No Olympus kills yet. Go find one.",
    cols = { { "#", 26, "RIGHT" }, { "Player", 168, "LEFT" }, { "Lvl", 30, "RIGHT" }, { "Guild", 170, "LEFT" },
             { "Kills", 46, "RIGHT" }, { "KB", 36, "RIGHT" }, { "Points", 54, "RIGHT" }, { "Last", 50, "RIGHT" } } },
  { label = "Guilds", rows = guildRows, empty = "No Olympus guild has paid tribute yet.",
    cols = { { "#", 26, "RIGHT" }, { "Guild", 280, "LEFT" }, { "Members killed", 110, "RIGHT" },
             { "Kills", 70, "RIGHT" }, { "Points", 70, "RIGHT" } } },
  { label = "Leaderboard", rows = boardRows, empty = "",
    cols = { { "#", 26, "RIGHT" }, { "Hunter", 190, "LEFT" }, { "Title", 140, "LEFT" }, { "Kills", 40, "RIGHT" },
             { "Unique", 46, "RIGHT" }, { "KB", 32, "RIGHT" }, { "OLYMPUS", 62, "RIGHT" }, { "Points", 46, "RIGHT" } } },
  { label = "Hit List", rows = hitRows, empty = "No Olympian seen and still breathing. Turn on enemy nameplates.",
    cols = { { "#", 26, "RIGHT" }, { "Player", 140, "LEFT" }, { "Lvl", 30, "RIGHT" }, { "Guild", 150, "LEFT" },
             { "Rank", 90, "LEFT" }, { "Seen in", 100, "LEFT" }, { "Seen", 40, "RIGHT" } } },
  { label = "Stats", rows = statsRows, empty = "",
    cols = { { "", 190, "LEFT" }, { "", 290, "LEFT" }, { "Kills", 60, "RIGHT" }, { "Share", 60, "RIGHT" } } },
}
local DOSSIER_COLS = { { "Dossier", 150, "LEFT" }, { "", 490, "LEFT" } }
local TAB_NOTES = {
  [1] = "Click a player for their dossier",
  [4] = "Olympians you have seen and not killed yet",
}
local MAX_COLS = 8

-- ---------------------------------------------------------------------------
-- Main window
-- ---------------------------------------------------------------------------

local function makeButton(parent, text, width)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetText(text)
  return b
end

local function layoutColumns(cells, cols)
  local x = 0
  for i = 1, MAX_COLS do
    local cell, col = cells[i], cols[i]
    if col then
      cell:ClearAllPoints()
      cell:SetPoint("LEFT", cell:GetParent(), "LEFT", x, 0)
      cell:SetWidth(col[2])
      cell:SetJustifyH(col[3])
      cell:Show()
      x = x + col[2] + 8
    else
      cell:Hide()
    end
  end
end

local function buildMain()
  local ok, f = pcall(CreateFrame, "Frame", "GodslayerFrame", UIParent, "BasicFrameTemplateWithInset")
  if not ok or not f then
    f = CreateFrame("Frame", "GodslayerWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if f.SetBackdrop then
      f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
                      insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    end
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
  end
  f:SetSize(680, 490)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()
  if f:GetName() and UISpecialFrames then table.insert(UISpecialFrames, f:GetName()) end

  local title = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
  if not title then
    title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -6)
  end
  title:SetText("Godslayer  |cff9d9d9dOlympus kill counter|r")

  f.summary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.summary:SetPoint("TOPLEFT", 16, -34)
  f.summary:SetPoint("TOPRIGHT", -16, -34)
  f.summary:SetJustifyH("LEFT")
  f.summary:SetWordWrap(false)
  f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.status:SetPoint("TOPLEFT", 16, -52)
  f.status:SetPoint("TOPRIGHT", -16, -52)
  f.status:SetJustifyH("LEFT")
  f.status:SetWordWrap(false)

  f.tabs = {}
  for i, tab in ipairs(TABS) do
    local b = makeButton(f, tab.label, 104)
    b:SetPoint("TOPLEFT", 14 + (i - 1) * 108, -74)
    b:SetScript("OnClick", function()
      currentTab, offset, dossierId = i, 0, nil
      UI.Refresh()
    end)
    f.tabs[i] = b
  end

  local list = CreateFrame("Frame", nil, f)
  list:SetPoint("TOPLEFT", 16, -104)
  list:SetPoint("TOPRIGHT", -16, -104)
  list:SetHeight((ROWS + 1) * ROW_HEIGHT + 4)
  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", function(_, delta)
    offset = offset - delta * 3
    UI.Refresh()
  end)
  f.list = list

  -- under the list, on the left: what the open tab is showing
  f.guildNote = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.guildNote:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -2)

  local function wheel(_, delta)
    offset = offset - delta * 3
    UI.Refresh()
  end

  local header = CreateFrame("Frame", nil, list)
  header:SetPoint("TOPLEFT")
  header:SetPoint("TOPRIGHT")
  header:SetHeight(ROW_HEIGHT)
  header.cells = {}
  for i = 1, MAX_COLS do
    header.cells[i] = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  end
  f.header = header

  f.rows = {}
  for r = 1, ROWS do
    local row = CreateFrame("Frame", nil, list)
    row:SetPoint("TOPLEFT", 0, -r * ROW_HEIGHT - 2)
    row:SetPoint("TOPRIGHT", 0, -r * ROW_HEIGHT - 2)
    row:SetHeight(ROW_HEIGHT)
    if r % 2 == 0 then
      local stripe = row:CreateTexture(nil, "BACKGROUND")
      stripe:SetAllPoints()
      stripe:SetColorTexture(1, 1, 1, 0.04)
    end
    row.cells = {}
    for i = 1, MAX_COLS do
      local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      cell:SetWordWrap(false)
      row.cells[i] = cell
    end
    -- a kill log row opens that player's dossier
    local glow = row:CreateTexture(nil, "BACKGROUND")
    glow:SetAllPoints()
    glow:SetColorTexture(1, 0.49, 0.04, 0.18)
    glow:Hide()
    row:EnableMouse(true)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", wheel)
    row:SetScript("OnEnter", function(self) if self.id then glow:Show() end end)
    row:SetScript("OnLeave", function() glow:Hide() end)
    row:SetScript("OnMouseUp", function(self)
      if self.id then UI.OpenDossier(self.id) end
    end)
    f.rows[r] = row
  end

  f.empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  f.empty:SetPoint("CENTER", 0, 0)

  f.count = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.count:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", 0, -2)

  -- brag line
  local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("BOTTOMLEFT", 16, 86)
  label:SetText("Guild chat brag line")
  f.phrase = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.phrase:SetPoint("BOTTOMLEFT", 16, 44)
  f.phrase:SetPoint("BOTTOMRIGHT", -16, 44)
  f.phrase:SetHeight(38)
  f.phrase:SetJustifyH("LEFT")
  f.phrase:SetJustifyV("TOP")
  f.phrase:SetWordWrap(true)

  local reroll = makeButton(f, "Another line", 120)
  reroll:SetPoint("BOTTOMLEFT", 14, 14)
  reroll:SetScript("OnClick", function() rollPhrase(); UI.Refresh() end)

  local share = makeButton(f, "Share to guild", 140)
  share:SetPoint("LEFT", reroll, "RIGHT", 6, 0)
  share:SetScript("OnClick", UI.Share)

  local top = makeButton(f, "Post top 3 to guild", 160)
  top:SetPoint("LEFT", share, "RIGHT", 6, 0)
  top:SetScript("OnClick", UI.ShareTop)

  local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMRIGHT", -16, 20)
  hint:SetText("/godslayer help")
  f.hint = hint

  -- only while a dossier is open
  f.back = makeButton(f, "Back", 56)
  f.back:SetPoint("LEFT", top, "RIGHT", 6, 0)
  f.back:SetScript("OnClick", function() dossierId, offset = nil, 0; UI.Refresh() end)
  f.bragVictim = makeButton(f, "Brag about them", 140)
  f.bragVictim:SetPoint("LEFT", f.back, "RIGHT", 6, 0)
  f.bragVictim:SetScript("OnClick", function() if dossierId then UI.ShareVictim(dossierId) end end)

  f:SetScript("OnShow", UI.Refresh)
  return f
end

function UI.Refresh()
  if not main or not main:IsShown() then return end
  local c, s = ns.char, ns.session
  local line = ("%sKills|r %s%d|r    %sPoints|r %s%d|r    %sUnique|r %s%d|r    %sKilling blows|r %s%d|r    %sOLYMPUS|r %s%d|r")
    :format(GOLD, WHITE, c.kills, GOLD, WHITE, c.points, GOLD, WHITE, c.uniques, GOLD, WHITE, c.kb, GOLD, WHITE, c.orig)
  if s.kills > 0 then
    line = line .. ("    %sthis session +%d / +%d pts|r"):format(GREY, s.kills, s.points)
  end
  main.summary:SetText(line)

  local rank, _, nextAt, nextName = ns.RankFor(c.points)
  local status = ("%sTitle|r %s%s|r"):format(GOLD, ORANGE, rank)
  if nextAt then status = status .. ("%s  (%d more for %s)|r"):format(GREY, nextAt - c.points, nextName) end
  if s.streak > 1 or (c.bestStreak or 0) > 1 then
    status = status .. ("    %sStreak|r %s%d|r %s(best %d)|r"):format(GOLD, WHITE, s.streak, GREY, c.bestStreak or 0)
  end
  if (c.kings or 0) > 0 then status = status .. ("    %sRegicides|r %s%d|r"):format(GOLD, WHITE, c.kings) end
  local favorite
  for _, v in pairs(c.victims) do
    if v.tier and v.kills > 1 and (not favorite or v.kills > favorite.kills) then favorite = v end
  end
  if favorite then
    status = status .. ("    %sFavorite customer|r %s x%d"):format(GOLD, classColored(favorite.name or "Unknown", favorite.class), favorite.kills)
  end
  main.status:SetText(status)

  local tab = TABS[currentTab]
  for i, b in ipairs(main.tabs) do
    if i == currentTab then b:LockHighlight() else b:UnlockHighlight() end
  end
  -- a dossier covers the kill log until Back, another tab, or the victim's record going away
  if dossierId and not (currentTab == 1 and c.victims[dossierId]) then dossierId = nil end
  local cols, rows = tab.cols, nil
  if dossierId then
    cols, rows = DOSSIER_COLS, dossierLines(dossierId)
    main.back:Show(); main.bragVictim:Show(); main.hint:Hide()
  else
    rows = tab.rows()
    main.back:Hide(); main.bragVictim:Hide(); main.hint:Show()
  end
  for i = 1, MAX_COLS do
    main.header.cells[i]:SetText(cols[i] and cols[i][1] or "")
  end
  layoutColumns(main.header.cells, cols)

  offset = math.max(0, math.min(offset, math.max(0, #rows - ROWS)))
  for r = 1, ROWS do
    local row, data = main.rows[r], rows[r + offset]
    if data then
      layoutColumns(row.cells, cols)
      for i = 1, MAX_COLS do
        row.cells[i]:SetText(data[i] ~= nil and tostring(data[i]) or "")
      end
      row.id = data.id
      row:Show()
    else
      row.id = nil
      row:Hide()
    end
  end
  main.empty:SetText(#rows == 0 and tab.empty or "")
  if #rows > ROWS then
    main.count:SetText(("%d-%d of %d  (mouse wheel to scroll)"):format(offset + 1, math.min(offset + ROWS, #rows), #rows))
  else
    main.count:SetText("")
  end

  if dossierId then
    main.guildNote:SetText("")
  elseif currentTab == 3 then
    local guild = ns.MyGuild()
    main.guildNote:SetText(guild and ("<" .. guild .. "> members running Godslayer") or "Join a guild to see a leaderboard")
  else
    main.guildNote:SetText(#rows > 0 and TAB_NOTES[currentTab] or "")
  end
  main.phrase:SetText(currentPhrase())
end

function UI.OpenDossier(id)
  if not ns.char.victims[id] then return false end
  if not main then UI.Toggle() elseif not main:IsShown() then main:Show() end
  if not main then return false end
  currentTab, offset, dossierId = 1, 0, id
  UI.Refresh()
  return true
end

-- One victim's record as a guild chat line. Click or typed command only, like every brag.
function UI.ShareVictim(id)
  local v = ns.char.victims[id]
  if not v or not v.tier then return false end
  local who = describe(v)
  local text = ("Dossier: %s <%s>%s. Killed %s%s. Status: %s."):format(v.name or "Unknown", v.guild or "?",
    who ~= "" and (", " .. who) or "", plural(v.kills, "time", "times"),
    (v.kb or 0) > 0 and (", " .. v.kb .. " by my own hand") or "", (ns.VictimTier(v.kills)) or "Unknown")
  return sayGuild(text)
end

function UI.Toggle()
  if not main then
    local ok, result = pcall(buildMain)
    if not ok then
      ns.Log("error", "window: " .. tostring(result))
      ns.Print("Could not build the window. /godslayer stats still works. (" .. tostring(result) .. ")")
      return
    end
    main = result
  end
  if main:IsShown() then main:Hide() else main:Show() end
end

-- ---------------------------------------------------------------------------
-- Kill toast
-- ---------------------------------------------------------------------------

local function showToast(headline, detail, extra, facts)
  if not toast then
    toast = CreateFrame("Frame", nil, UIParent)
    toast:SetSize(700, 100)
    toast:SetPoint("TOP", 0, -170)
    toast:SetFrameStrata("HIGH")
    toast.head = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    toast.head:SetPoint("TOP")
    toast.detail = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    toast.detail:SetPoint("TOP", toast.head, "BOTTOM", 0, -4)
    toast.facts = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    toast.facts:SetPoint("TOP", toast.detail, "BOTTOM", 0, -3)
    toast.extra = toast:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    toast.extra:SetPoint("TOP", toast.facts, "BOTTOM", 0, -4)
    toast:SetScript("OnUpdate", function(self, elapsed)
      self.age = self.age + elapsed
      if self.age > 3.5 then
        self:Hide()
      elseif self.age > 2.5 then
        self:SetAlpha(3.5 - self.age)
      end
    end)
  end
  toast.head:SetText(headline)
  toast.detail:SetText(detail)
  toast.facts:SetText(facts or "")
  toast.extra:SetText(extra or "")
  toast.age = 0
  toast:SetAlpha(1)
  toast:Show()
end

local function streakName(streak)
  local best
  for at, label in pairs(ns.STREAKS) do
    if streak >= at and (not best or at > best) then best = at end
  end
  return best and ns.STREAKS[best]
end

-- The best facts about a fresh kill, most interesting first.
local function killFacts(v, info)
  local facts = {}
  local who = describe(v)
  if v.rank then who = (who ~= "" and (who .. ", ") or "") .. v.rank end
  if who ~= "" then facts[#facts + 1] = who end
  if info.zone then facts[#facts + 1] = info.zone end
  if info.first then
    facts[#facts + 1] = "First blood on this one"
  else
    local today = v.today or 0
    if today == 2 then facts[#facts + 1] = "Second time today"
    elseif today == 3 then facts[#facts + 1] = "Third time today"
    elseif today > 3 then facts[#facts + 1] = today .. " times today"
    else facts[#facts + 1] = "Kill number " .. v.kills .. " on them" end
    local label = ns.VictimTier(v.kills)
    if label then facts[#facts + 1] = label end
  end
  return facts
end
UI.KillFacts = killFacts

local function killFeedback(name, class, guild, tier, pts, info, v)
  local c = ns.char
  local who = classColored(name, class)
  local facts = v and killFacts(v, info) or {}
  if opts.chat then
    ns.Print(("%s <%s> down. +%d  (%d kills, %d points)"):format(who, guild, pts, c.kills, c.points))
    if #facts > 0 then print("  " .. GREY .. table.concat(facts, ". ") .. ".|r") end
    if info.king then ns.Print(GOLD .. "REGICIDE.|r You killed the King of Olympus. Tell everyone.") end
    if info.rankUp then ns.Print("New title: " .. ORANGE .. info.rankUp .. "|r") end
  end
  if opts.toast then
    local headline = ORANGE .. "Olympian down|r"
    if info.king then
      headline = GOLD .. "REGICIDE: THE KING IS DEAD|r"
    elseif tier == "original" then
      headline = GOLD .. "OLYMPUS DOWN|r"
    end
    local extras = {}
    local streak = info.streak and info.streak > 1 and streakName(info.streak)
    if streak then extras[#extras + 1] = streak .. " (x" .. info.streak .. ")" end
    if info.rankUp then extras[#extras + 1] = "New title: " .. info.rankUp end
    showToast(headline, ("%s  <%s>  %s+%d|r"):format(who, guild, GOLD, pts), table.concat(extras, "   "),
      table.concat(facts, "    "))
  end
  -- the announcer has this one: a system chime under a shouted line is only noise
  if opts.sound and SOUNDKIT and not info.announced then
    local loud = tier == "original" or info.rankUp
    local id = loud and SOUNDKIT.RAID_WARNING or (SOUNDKIT.UI_PVP_HONOR_PRESTIGE_RANK_UP or SOUNDKIT.RAID_WARNING)
    if id then pcall(PlaySound, id) end -- this client's second argument is not the old channel name
  end
end

ns.OnScore = function(v, guild, tier, pts, info)
  killFeedback(v.name or "Unknown", v.class, guild, tier, pts, info or {}, v)
  ns.Comm.MarkDirty()
  UI.Refresh()
end

ns.OnChanged = function() UI.Refresh() end

-- ---------------------------------------------------------------------------
-- Minimap button and addon compartment entry
-- ---------------------------------------------------------------------------

local function placeMinimapButton()
  local angle = math.rad(opts.minimapAngle or 215)
  local radius = (Minimap:GetWidth() / 2) + 6
  minimapButton:ClearAllPoints()
  minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function tooltipSummary(tt)
  local c = ns.char
  tt:AddLine("Godslayer")
  tt:AddLine((ns.RankFor(c.points)), 1, 0.49, 0.04)
  tt:AddLine(("%d Olympus kills, %d points, %d unique"):format(c.kills, c.points, c.uniques), 1, 1, 1)
  tt:AddLine("Click to open. Drag to move.", 0.6, 0.6, 0.6)
end

local function buildMinimapButton()
  if not Minimap then return end
  local b = CreateFrame("Button", "GodslayerMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("AnyUp")
  b:RegisterForDrag("LeftButton")
  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", 7, -5)
  icon:SetTexture(ICON)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  b:SetScript("OnClick", UI.Toggle)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    tooltipSummary(GameTooltip)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      opts.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
      placeMinimapButton()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  minimapButton = b
  placeMinimapButton()
  if not opts.minimap then b:Hide() end
end

function Godslayer_OnCompartmentClick() UI.Toggle() end

function Godslayer_OnCompartmentEnter(_, button)
  if not (GameTooltip and button and ns.char) then return end
  GameTooltip:SetOwner(button, "ANCHOR_LEFT")
  tooltipSummary(GameTooltip)
  GameTooltip:Show()
end

function Godslayer_OnCompartmentLeave()
  if GameTooltip then GameTooltip:Hide() end
end

-- ---------------------------------------------------------------------------
-- Tooltip line on Olympus players
-- ---------------------------------------------------------------------------

local function onUnitTooltip(tt)
  if not opts.tooltip or tt ~= GameTooltip or type(tt.GetUnit) ~= "function" then return end
  local _, unit = tt:GetUnit()
  unit = plain(unit)
  if type(unit) ~= "string" then return end
  local tier, _, id = ns.UnitTier(unit)
  if not tier then return end
  local pts = ns.PointsFor(tier)
  tt:AddLine(("Godslayer: %s, %d %s"):format(tier == "original" and "OLYMPUS" or "Olympus network",
    pts, pts == 1 and "point" or "points"), 1, 0.49, 0.04)
  local v = ns.char.victims[id]
  if v and v.tier then
    tt:AddLine(("You have killed them %d %s"):format(v.kills, v.kills == 1 and "time" or "times"), 1, 0.82, 0)
    local label = ns.VictimTier(v.kills)
    local zone = v.hist and v.hist[#v.hist] and v.hist[#v.hist][2]
    tt:AddLine((label or "") .. ". Last: " .. ago(v.last) .. " ago" .. ((zone and zone ~= "") and (" in " .. zone) or ""), 0.8, 0.8, 0.8)
  else
    tt:AddLine("On your hit list. Not killed yet.", 0.8, 0.8, 0.8)
  end
end

local function hookTooltip()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
      pcall(onUnitTooltip, tt)
    end)
  elseif GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tt) pcall(onUnitTooltip, tt) end)
  end
end

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------

local TOGGLES = { sound = "Kill sound", toast = "Kill banner", chat = "Kill line in chat",
                  tooltip = "Tooltip line", minimap = "Minimap button" }

local function printStats()
  local c = ns.char
  ns.Print(("%s: %d Olympus kills, %d points, %d unique players, %d killing blows, %d from the original OLYMPUS.")
    :format((ns.RankFor(c.points)), c.kills, c.points, c.uniques, c.kb, c.orig))
end

local function printHelp()
  ns.Print("commands (also /slay):")
  print("  /godslayer            open or close the window")
  print("  /godslayer stats      your totals in chat (only you see it)")
  print("  /godslayer dossier <name>   everything on someone you killed (only you see it)")
  print("  /godslayer nemesis    who you have killed most   /godslayer hitlist   Olympians seen, not killed yet")
  print("  /godslayer hype       your kill song and the announcer: test, on, off, window <seconds>")
  print("  /godslayer share      post a brag line to guild chat")
  print("  /godslayer top        post the top 3 to guild chat")
  print("  /godslayer add <guild name>       count a guild that has no 'olympus' in its name")
  print("  /godslayer ignore <guild name>    stop counting a guild   (unignore to undo)")
  print("  /godslayer guilds     show the guilds you added or ignored")
  print("  /godslayer sound | toast | chat | tooltip | minimap     turn each on or off")
  print("  /godslayer demo       preview the kill banner without recording anything")
  print("  /godslayer log        last debug lines   /godslayer reset confirm   wipe this character")
end

local function slash(input)
  input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, rest = input:match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()

  if cmd == "" then
    UI.Toggle()
  elseif cmd == "help" or cmd == "?" then
    printHelp()
  elseif cmd == "stats" then
    printStats()
  elseif cmd == "dossier" or cmd == "who" or cmd == "nemesis" then
    local v, id
    if cmd == "nemesis" then v, id = ns.Nemesis() else v, id = ns.FindVictim(rest) end
    if not v then
      ns.Print(cmd == "nemesis" and "Nobody has died to you twice yet." or
        (rest == "" and "Give a name, for example: /godslayer dossier Bob" or ("No kill on record for '" .. rest .. "'.")))
      return
    end
    ns.Print("dossier:")
    for _, line in ipairs(dossierLines(id)) do print("  " .. line[1] .. "  " .. line[2]) end
  elseif cmd == "hype" then
    if ns.Hype then ns.Hype.Command(rest) else ns.Print("The hype part of the addon did not load. Quit the game fully and start it again.") end
  elseif cmd == "hitlist" then
    local list = ns.HitList()
    ns.Print(#list == 0 and "No Olympian seen and still unkilled." or (#list .. " seen and not killed yet. The most recent:"))
    for i = 1, math.min(10, #list) do
      local k = list[i]
      print(("  %s <%s>%s  %s ago"):format(classColored(k.name, k.class), k.guild,
        k.level and (" level " .. k.level) or "", ago(k.t)))
    end
  elseif cmd == "share" then
    UI.Share()
  elseif cmd == "top" then
    UI.ShareTop()
  elseif TOGGLES[cmd] then
    opts[cmd] = not opts[cmd]
    ns.Print(TOGGLES[cmd] .. (opts[cmd] and " on." or " off."))
    if cmd == "minimap" and minimapButton then
      if opts.minimap then minimapButton:Show() else minimapButton:Hide() end
    end
  elseif cmd == "add" or cmd == "ignore" or cmd == "unignore" or cmd == "remove" then
    if rest == "" then
      ns.Print("Give a guild name, for example: /godslayer " .. cmd .. " The Enclave")
      return
    end
    local norm = ns.NormGuild(rest)
    if norm == "" then return end
    local db = GodslayerDB
    if cmd == "add" then
      db.custom[norm], db.ignore[norm] = rest, nil
      ns.Print("Now counting <" .. rest .. ">.")
    elseif cmd == "ignore" then
      db.ignore[norm], db.custom[norm] = rest, nil
      ns.Print("No longer counting <" .. rest .. ">.")
    else
      db.ignore[norm], db.custom[norm] = nil, nil
      ns.Print("<" .. rest .. "> is back to the default rules.")
    end
    ns.Recount()
    ns.Comm.MarkDirty()
    UI.Refresh()
  elseif cmd == "guilds" then
    local db = GodslayerDB
    local added, ignored = {}, {}
    for _, name in pairs(db.custom) do added[#added + 1] = tostring(name) end
    for _, name in pairs(db.ignore) do ignored[#ignored + 1] = tostring(name) end
    ns.Print("Counts any guild with 'olympus' in the name, plus a built-in list of affiliates.")
    print("  added: " .. (#added > 0 and table.concat(added, ", ") or "none"))
    print("  ignored: " .. (#ignored > 0 and table.concat(ignored, ", ") or "none"))
  elseif cmd == "demo" then
    showToast(GOLD .. "REGICIDE: THE KING IS DEAD|r", ("%s  <OLYMPUS>  %s+%d|r"):format(ns.KING, GOLD, ns.ORIGINAL_POINTS),
      "Triple Heresy (x3)   New title: Thief of Fire", "Level 60 Human Warrior, Guild Master    Stranglethorn Vale    Third time today")
    ns.Print("That was a preview. Nothing was recorded.")
  elseif cmd == "log" then
    local log = GodslayerDB.log
    ns.Print("last debug lines:")
    for i = math.max(1, #log - 19), #log do print("  " .. log[i]) end
  elseif cmd == "reset" then
    if rest == "confirm" then
      ns.ResetCharacter()
      ns.Comm.MarkDirty()
      UI.Refresh()
      ns.Print("This character's kills are wiped.")
    elseif rest == "roster" then
      ns.Comm.ForgetRoster()
      UI.Refresh()
      ns.Print("Leaderboard cleared. It refills as guildmates log in.")
    else
      ns.Print("Type /godslayer reset confirm to wipe this character's kills, or /godslayer reset roster to clear the leaderboard.")
    end
  else
    printHelp()
  end
end

function UI.Init()
  opts = GodslayerDB.opts
  SLASH_GODSLAYER1, SLASH_GODSLAYER2, SLASH_GODSLAYER3 = "/godslayer", "/slay", "/gsl"
  SlashCmdList["GODSLAYER"] = function(input)
    local ok, err = pcall(slash, input)
    if not ok then ns.Log("error", "slash: " .. tostring(err)); ns.Print("That command failed: " .. tostring(err)) end
  end
  local ok, err = pcall(buildMinimapButton)
  if not ok then ns.Log("error", "minimap: " .. tostring(err)) end
  ok, err = pcall(hookTooltip)
  if not ok then ns.Log("error", "tooltip: " .. tostring(err)) end
end
