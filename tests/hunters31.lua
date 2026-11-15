-- Godslayer 3.1 focused regressions: Slayers discovery, live news, fan-out, and queue isolation.
package.path = "tests/?.lua;" .. package.path
local M = require("mock")
local passed, failed = 0, 0
local function check(value, label)
  if value then passed = passed + 1 else failed = failed + 1; M.realPrint("FAIL: " .. label) end
end
local function eq(got, want, label)
  check(got == want, label .. " (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
end

local function alpha(n)
  local out = ""
  repeat local d = n % 26; out = string.char(97 + d) .. out; n = math.floor(n / 26) until n == 0
  return ("aaaa" .. out):sub(-4)
end

local ME = "Player-1-0000AAAA"
local FILES = { "Data.lua", "Pvp.lua", "Core.lua", "Voice.lua", "Sound.lua", "Stage.lua", "Clip.lua", "Hype.lua",
  "Fight.lua", "Aura.lua", "Ledger.lua", "Rank.lua", "Recap.lua", "Field.lua", "Flag.lua", "Control.lua",
  "Death.lua", "Threat.lua", "Comm.lua", "Hunters.lua", "Rival.lua", "Wheel.lua", "UI.lua" }

local function fresh(saved, playerName)
  M.now, M.wall, M.timers, M.units, M.guids, M.group = 1000, 1791400000, {}, {}, {}, {}
  M.frames, M.sentAddon, M.sentChat, M.printed = { UIParent, Minimap, GameTooltip }, {}, {}, {}
  M.settings, M.prefixes, M.chatFilters = { categories={}, controls={} }, {}, {}
  M.inGuild, M.lockdown, M.inCombat, M.inInstance, M.groupSize = true, false, false, false, 0
  M.addonResult, M.syncOffline, M.addonRouter = 0, {}, nil
  M.region, M.realmName, M.hardcore, M.weekUntil = "US", "Classic Beta PvP", false, nil
  M.channelJoined, M.channelSuspended, M.channelRefused = false, false, false
  M.channelRoster, M.channelRosterCount, M.selectedDisplay, M.selectedDisplays = {}, 0, nil, {}
  M.channelDisplayCalls = 0
  M.joinCalls, M.leaveCalls, M.joinArgs, M.secureCalls = 0, 0, nil, 0
  M.audio.cvars = { Sound_EnableAllSound="1", Sound_EnableMusic="1", Sound_EnableDialog="1", Sound_EnableAmbience="1",
    Sound_DialogVolume="0.8", Sound_AmbienceVolume="0.7", Sound_MusicVolume="0.8" }
  M.audio.cvarWrites, M.audio.files, M.audio.lengths, M.audio.played, M.audio.stopped, M.audio.kits = {}, {}, {}, {}, {}, {}
  GodslayerDB = saved
  GodslayerFrame, GodslayerWindow, GodslayerMinimapButton, GodslayerHypeBanner = nil, nil, nil, nil
  M.addUnit("player", { name=playerName or "Vesh Torchman", guid=ME, guild="The True Torchmen", class="MAGE",
    race="Scourge", sex=2, faction="Horde", isMe=true })
  local ns = M.load("Godslayer", FILES)
  M.fire("ADDON_LOADED", "Godslayer"); M.fire("PLAYER_LOGIN")
  return ns, ns.Hunters
end

local function wire(ns, nonce, values)
  values = values or {}
  local b, c = ns.Hunters.Base36, ns.char
  return table.concat({ "R", "1", nonce, b(values.gen or 100), b(values.seq or 1),
    b(values.made or GetServerTime()), b(values.week or c.weekStart or 0), b(values.complete == nil and 1 or values.complete),
    values.class or "WARRIOR", b(values.kills or 5), b(values.points or 5), b(values.kb or 0),
    b(values.orig or 0), b(values.kings or 0), b(values.rung or 0), b(values.wkKills or 0),
    b(values.wkPoints or 0), values.version or "3.1.0", values.scope or "us/pvp" }, ";")
end

local function news(ns, values)
  values = values or {}
  local b, c = ns.Hunters.Base36, ns.char
  local victimName = values.victimName; if victimName == nil then victimName = "Bob Smith" end
  local victimClass = values.victimClass; if victimClass == nil then victimClass = "PALADIN" end
  return table.concat({ "N", "1", b(values.gen or 100), b(values.seq or 2), b(values.made or GetServerTime()),
    b(values.week or c.weekStart or 0), b(values.complete == nil and 1 or values.complete), values.class or "WARRIOR",
    b(values.kills or 6), b(values.points or 6), b(values.kb or 0), b(values.orig or 0), b(values.kings or 0),
    b(values.rung or 0), b(values.wkKills or 0), b(values.wkPoints or 0), values.version or "3.1.0",
    values.scope or "us/pvp", values.faction or "Horde", b(values.batchKills or 1), b(values.batchPoints or 1),
    victimName, victimClass }, ";")
end

local function addRow(ns, H, name, values)
  local parsed = assert(H.Parse(wire(ns, "0", values)))
  check(H.MergeRow(H.RowKey(name), name, parsed), "setup: confirmed row " .. name)
  return H.Debug().scope.rows[H.RowKey(name)]
end

local function startWorld(H)
  M.fire("PLAYER_ENTERING_WORLD")
  H.Debug().sendAfter = 0
end

local function countSent(op, target)
  local n = 0
  for _, row in ipairs(M.sentAddon) do
    if (not op or row[2]:match("^" .. op .. ";")) and (not target or row[5] == target) then n = n + 1 end
  end
  return n
end

local function snapshotFor(H, name)
  local key = H.RowKey(name)
  for _, item in pairs(H.Debug().snapshots) do if item.key == key then return item end end
end

local function snapshotCount(H)
  local count = 0
  for _ in pairs(H.Debug().snapshots) do count = count + 1 end
  return count
end

-- Ruleset suffixes normalize known labels and preserve an unknown suffix.
do
  local ns, H = fresh()
  local cases = { PvP="pvp", PvE="standard", Normal="standard", RPPvP="rppvp", RP="rp", HC="hardcore", [""]="standard" }
  for suffix, expected in pairs(cases) do
    M.realmName = "CAMWOWUS1Realm8" .. suffix
    eq(H.DetectScope(), "us/horde/" .. expected, "ruleset suffix " .. (suffix == "" and "empty" or suffix))
  end
  M.realmName = "CAMWOWUS1Realm8Mythic"
  eq(H.DetectScope(), "us/horde/mythic", "ruleset unknown suffix remains isolated")
end

-- Positive stale rosters hydrate at 3/8 seconds; self-only is healthy; own selection events do not loop.
do
  local ns, H = fresh()
  eq(H.Status().directory, "starting", "directory begins in a truthful starting state")
  M.channelJoined, M.channelRosterCount = true, 2
  local realSelect = SetSelectedDisplayChannel
  SetSelectedDisplayChannel = function(index)
    local result = realSelect(index)
    M.fire("CHANNEL_UI_UPDATE") -- the real client fires this synchronously for our own selection
    if index == 2 then M.channelRoster = { {name="Vesh Torchman", guid=ME}, {name="Hydrated Peer", guid="Player-9-1"} } end
    return result
  end
  startWorld(H); M.advance(11); H.RefreshDirectory(); M.advance(4)
  eq(H.Status().directory, "working", "directory positive stale count hydrates and rereads")
  check(#M.selectedDisplays >= 2, "directory hydration selects other then ours")
  local refreshes = H.Debug().refreshRuns or 0
  local displayCalls = M.channelDisplayCalls
  for _ = 1, 100 do M.fire("CHANNEL_COUNT_UPDATE", 1, 20) end
  check(H.Debug().refreshRuns == refreshes and not H.Debug().directoryWakePending,
    "one hundred Trade count updates cause zero directory rescans")
  eq(M.channelDisplayCalls, displayCalls,
    "one hundred Trade count updates perform no display-channel reads after the cache refresh")
  M.fire("CHANNEL_UI_UPDATE"); M.advance(6)
  eq(H.Debug().refreshRuns, refreshes, "directory own selection event is ignored for ten seconds")
  M.advance(5); M.fire("CHANNEL_ROSTER_UPDATE", 2, 2); M.advance(6)
  check(H.Debug().refreshRuns > refreshes, "directory later roster event wakes a debounced refresh")
  SetSelectedDisplayChannel = realSelect

  ns, H = fresh(); M.channelJoined, M.channelRosterCount = true, 1
  M.channelRoster = { {name="Vesh Torchman", guid=ME} }
  startWorld(H); M.advance(11); H.RefreshDirectory(); M.advance(0)
  eq(H.Status().directory, "only you", "directory readable self-only roster is healthy")
  eq(H.Status().rejected.self, 1, "directory status records self rejection")
end

-- A successful join that is not visible in the display list yet waits and retries soon. Only a
-- refused join (and sharing off) use the not-joined state.
do
  local ns, H = fresh(); startWorld(H); M.advance(11)
  M.channelJoined, M.channelRosterCount = true, 1
  M.channelRoster = { {name="Vesh Torchman", guid=ME} }
  local realDisplay = GetChannelDisplayInfo
  GetChannelDisplayInfo = function(index)
    M.channelDisplayCalls = (M.channelDisplayCalls or 0) + 1
    if index == 1 then return realDisplay(index) end
  end
  local refreshes = H.Debug().refreshRuns or 0
  H.RefreshDirectory()
  eq(H.Status().directory, "waiting for roster", "directory missing display row waits instead of claiming join failure")
  GetChannelDisplayInfo = realDisplay
  M.advance(16)
  check(H.Debug().refreshRuns > refreshes and H.Status().directory == "only you",
    "directory missing display row gets one short retry before the normal cycle")

  ns, H = fresh(); H.SetEnabled(false); startWorld(H)
  M.channelRefused = true; H.SetEnabled(true); M.advance(0)
  eq(H.Status().directory, "not joined", "directory refused join keeps the not-joined state")
  M.advance(11)
  M.channelRefused, M.channelJoined, M.channelRosterCount = false, true, 1
  M.channelRoster = { {name="Vesh Torchman", guid=ME} }
  realDisplay = GetChannelDisplayInfo
  GetChannelDisplayInfo = function(index)
    M.channelDisplayCalls = (M.channelDisplayCalls or 0) + 1
    if index == 1 then return realDisplay(index) end
  end
  refreshes = H.Debug().refreshRuns or 0
  H.RefreshDirectory()
  eq(H.Status().directory, "waiting for roster",
    "directory manual membership overrides an earlier refused-join state while its row is hidden")
  GetChannelDisplayInfo = realDisplay
  M.advance(16)
  check(H.Debug().refreshRuns > refreshes and H.Status().directory == "only you",
    "directory manual join with a hidden row gets the single short retry")

  ns, H = fresh(); H.SetEnabled(false); startWorld(H); M.advance(11)
  M.channelRefused = true; H.SetEnabled(true); M.advance(0)
  eq(H.Status().directory, "not joined", "directory combat refusal: refused join starts as not joined")
  M.inCombat = true; H.RefreshDirectory()
  eq(H.Status().directory, "waiting for roster", "directory combat refusal: combat defers the refresh")
  M.inCombat = false; H.RefreshDirectory()
  eq(H.Status().directory, "not joined",
    "directory combat refusal: post-combat refresh enforces the current refusal")

  ns, H = fresh(); H.SetEnabled(false); startWorld(H); M.advance(11)
  M.channelRefused = true; H.SetEnabled(true); M.advance(0)
  M.channelRefused, M.channelJoined, M.channelRosterCount = false, true, 1
  M.channelRoster = { {name="Vesh Torchman", guid=ME} }
  H.RefreshDirectory()
  check(H.Status().directory == "only you" and H.Debug().joinFailedGeneration == nil,
    "directory visible manual join clears the refused generation during its scan")
  M.channelJoined = false
  H.RefreshDirectory()
  check(H.Status().directory == "waiting for roster" and H.Debug().joinFailedGeneration == nil,
    "directory leave after a visible manual join does not reuse the old refusal")
end

-- A combat-aborted slice and an inbound Q both resume discovery promptly.
do
  local ns, H = fresh(); M.channelJoined, M.channelRosterCount = true, 80
  for i = 1, 80 do M.channelRoster[i] = { name="Peer " .. alpha(i), guid="Player-9-" .. i } end
  startWorld(H); M.advance(11); H.RefreshDirectory()
  M.inCombat = true; M.runNextTimer()
  eq(H.Status().directory, "waiting for roster", "directory combat interruption is visible")
  M.inCombat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(6)
  eq(H.Status().directory, "working", "directory resumes after combat")
  M.inInstance = true; H.RefreshDirectory()
  eq(H.Status().directory, "waiting for roster", "directory instance interruption is visible")
  M.inInstance = false; M.fire("PLAYER_ENTERING_WORLD"); M.advance(6)
  eq(H.Status().directory, "working", "directory resumes after leaving an instance")
  local refreshes = H.Debug().refreshRuns
  M.fire("PLAYER_ENTERING_WORLD"); M.advance(6)
  eq(H.Debug().refreshRuns, refreshes,
    "ordinary entering-world inside sixty seconds does not bypass the directory limit")

  local before = #M.sentAddon
  M.fire("CHAT_MSG_ADDON", "GodslayerG", "Q;1;inbound1;us/pvp", "WHISPER", "Inbound Peer")
  local candidate = H.Debug().scope.candidates[H.RowKey("Inbound Peer")]
  check(candidate and candidate.source == "inbound", "inbound Q seeds a candidate")
  M.advance(8)
  check(countSent("Q", "Inbound Peer") >= 1, "inbound Q schedules a reciprocal Q")
  check(#M.sentAddon > before, "inbound Q also receives its owed response")
end

-- Unreadable positive counts persist diagnostics, YOU_JOINED wakes, and expired blocked Q is neutral.
do
  local ns, H = fresh(); M.channelJoined, M.channelRosterCount = true, 2
  startWorld(H); M.advance(11); H.RefreshDirectory(); M.advance(9)
  eq(H.Status().directory, "unreadable", "directory positive count with no readable names becomes unreadable")
  local scan = H.Debug().scope.meta.lastScan
  check(scan and scan.reported == 2 and scan.namesRead == 0 and scan.rejected.secret == 2,
    "directory last scan summary is persisted in scope meta")
  H.Command("status")
  local status = M.printed[#M.printed]
  check(status:find("channel", 1, true) and status:find("rejected secret/nil", 1, true)
    and status:find("lockdown", 1, true) and status:find("version 3.1.0", 1, true),
    "Slayers status prints compact multi-line diagnostics")
  check(status:find("s ago", 1, true) and not status:find(tostring(scan.at), 1, true),
    "Slayers status reports last scan as an age instead of a server timestamp")

  local refreshes = H.Debug().refreshRuns
  M.fire("CHAT_MSG_CHANNEL_NOTICE", "YOU_JOINED", nil, nil, nil, nil, "GodslayerHunters")
  M.advance(6)
  check(H.Debug().refreshRuns > refreshes, "YOU_JOINED notice wakes directory refresh")

  H.NoteCandidate("Blocked Query", "test")
  local key, runtime = H.RowKey("Blocked Query"), H.Debug()
  runtime.scope.pending.expireq = {kind="Q", target="Blocked Query", key=key, at=GetServerTime()}
  runtime.scope.meta.pendingCount = runtime.scope.meta.pendingCount + 1
  runtime.queue[#runtime.queue + 1] = {p=3, target="Blocked Query", payload="Q;1;expireq1;us/pvp",
    kind="Q", nonce="expireq", created=GetTime()-61, ttl=60, due=GetTime()-61}
  M.inCombat = true; H.SendTick(); M.inCombat = false; H.SendTick()
  eq(runtime.scope.candidates[key].fail or 0, 0, "Q expiry after combat does not count as candidate failure")
end

-- Offline correlation is kind-aware and exact-name-only. Result 12, a line inside the API call, a
-- line after it, and result 12 plus a later line each apply exactly one candidate failure.
do
  local ns, H = fresh(); startWorld(H)
  H.NoteCandidate("Repeat Name", "test")
  local c = H.Debug().scope.candidates[H.RowKey("Repeat Name")]
  c.nextTry = GetServerTime() + 3600 -- isolate the owed response from the reciprocal-Q path
  M.fire("CHAT_MSG_ADDON", "GodslayerG", "Q;1;reply001;us/pvp", "WHISPER", "Repeat Name")
  M.syncOffline["Repeat Name"] = true; M.advance(4)
  eq(c.fail or 0, 0, "offline after a response does not penalize candidate discovery")
  eq(M.applyChatFilters("CHAT_MSG_SYSTEM", "No player named 'Repeat Name-Classic Beta PvP' is currently playing.", 1), 1,
    "offline exact full-name-realm line is correlated")
  eq(M.applyChatFilters("CHAT_MSG_SYSTEM", "No player named 'Repeat' is currently playing.", 1), 0,
    "offline first-name-only line is not correlated")

  local function queuedQuery(H, name, nonce)
    H.NoteCandidate(name, "test")
    local key, runtime = H.RowKey(name), H.Debug()
    runtime.scope.pending[nonce] = {kind="Q", target=name, key=key, at=GetServerTime()}
    runtime.scope.meta.pendingCount = runtime.scope.meta.pendingCount + 1
    runtime.queue[#runtime.queue + 1] = {p=3, target=name, payload="Q;1;" .. nonce .. ";us/pvp",
      kind="Q", nonce=nonce, created=GetTime(), ttl=60, due=GetTime()}
    runtime.lastSend = -1e9
    runtime.sentMinute, runtime.sentBurst, runtime.nonResponseBurst = {}, {}, {}
    runtime.nonResponseMinute = {}
    return runtime.scope.candidates[key]
  end

  local cases = {
    { "result 12 alone", function(name, H) M.addonResult = 12; H.SendTick() end },
    { "offline line inside send", function(name, H) M.syncOffline[name] = true; H.SendTick() end },
    { "offline line after send", function(name, H)
        H.SendTick(); M.fire("CHAT_MSG_SYSTEM", "No player named '" .. name .. "' is currently playing.")
      end },
    { "result 12 plus later line", function(name, H)
        M.addonResult = 12; H.SendTick()
        M.fire("CHAT_MSG_SYSTEM", "No player named '" .. name .. "' is currently playing.")
      end },
  }
  for i, case in ipairs(cases) do
    ns, H = fresh(); startWorld(H)
    local name = "Order " .. alpha(i)
    local candidate = queuedQuery(H, name, "order00" .. i)
    case[2](name, H)
    check(candidate.fail == 1 and not candidate.retired, case[1] .. " applies one candidate failure")
  end

  ns, H = fresh(); startWorld(H)
  local name, candidate = "Four Offlines", nil
  for i = 1, 4 do
    candidate = queuedQuery(H, name, "four000" .. i)
    M.addonResult = 12; H.SendTick()
    check(candidate.fail == i and ((i == 4 and candidate.retired) or (i < 4 and not candidate.retired)),
      "candidate retires only on distinct offline number " .. i)
  end
end

-- Inbound Q dedupe is committed only after an accepted response send. Expiry and local API throws
-- clear their obligations, and a later copy can recover without penalizing discovery.
do
  local ns, H = fresh(); startWorld(H)
  M.fire("CHAT_MSG_ADDON", "GodslayerG", "Q;1;retryq01;us/pvp", "WHISPER", "Retry Asker")
  local response
  for _ = 1, 30 do
    for _, item in ipairs(H.Debug().queue) do if item.responseKey then response = item end end
    if response then break end
    M.runNextTimer()
  end
  local dedupe = "in:" .. H.RowKey("Retry Asker") .. ":retryq01"
  check(response and not H.Debug().scope.completedNonces[dedupe],
    "response dedupe: queued response is not complete before accepted send")
  response.created, response.ttl = GetTime() - 61, 60
  H.SendTick()
  check(not H.Debug().scope.completedNonces[dedupe] and not H.Debug().owedResponses[dedupe],
    "response dedupe: expiry clears the owed record without completing it")
  M.fire("CHAT_MSG_ADDON", "GodslayerG", "Q;1;retryq01;us/pvp", "WHISPER", "Retry Asker")
  check(H.Debug().owedResponses[dedupe] ~= nil, "response dedupe: repeated Q is answerable after expiry")

  H.NoteCandidate("Throw Query", "test")
  local key, runtime = H.RowKey("Throw Query"), H.Debug()
  runtime.scope.pending.throwq01 = {kind="Q", target="Throw Query", key=key, at=GetServerTime()}
  runtime.scope.meta.pendingCount = runtime.scope.meta.pendingCount + 1
  runtime.queue[#runtime.queue + 1] = {p=3, target="Throw Query", payload="Q;1;throwq01;us/pvp",
    kind="Q", nonce="throwq01", created=GetTime(), ttl=60, due=GetTime()}
  local realSend = C_ChatInfo.SendAddonMessage
  C_ChatInfo.SendAddonMessage = function() error("local send failure") end
  runtime.lastSend = -1e9; runtime.sentMinute, runtime.sentBurst, runtime.nonResponseBurst = {}, {}, {}
  H.SendTick(); C_ChatInfo.SendAddonMessage = realSend
  check((runtime.scope.candidates[key].fail or 0) == 0 and not runtime.scope.pending.throwq01,
    "send throw: local API exception clears pending work without candidate failure")

  ns, H = fresh(); startWorld(H)
  local repeated = "in:" .. H.RowKey("Disable Asker") .. ":disable1"
  M.fire("CHAT_MSG_ADDON", "GodslayerG", "Q;1;disable1;us/pvp", "WHISPER", "Disable Asker")
  check(H.Debug().owedResponses[repeated] ~= nil, "disable response: inbound Q creates an owed response")
  H.SetEnabled(false)
  check(not next(H.Debug().owedResponses) and #H.Debug().queue == 0,
    "disable response: dropping the queue clears all owed records")
  H.SetEnabled(true)
  M.fire("CHAT_MSG_ADDON", "GodslayerG", "Q;1;disable1;us/pvp", "WHISPER", "Disable Asker")
  check(H.Debug().owedResponses[repeated] ~= nil,
    "disable response: repeated Q is answerable after sharing is re-enabled")
  M.advance(3)
  local responses = 0
  for _, item in ipairs(H.Debug().queue) do if item.responseKey == repeated then responses = responses + 1 end end
  for _, sent in ipairs(M.sentAddon) do
    if sent[5] == "Disable Asker" and sent[2]:match("^R;1;disable1;") then responses = responses + 1 end
  end
  eq(responses, 1, "disable response: canceled timer cannot duplicate the replacement response")
end

-- A Q offline record cannot consume a later news offline result for the same exact name.
do
  local ns, H = fresh(); startWorld(H)
  addRow(ns, H, "Dual Offline", {version="3.1.0"}); H.Debug().directoryNames["dual offline"] = true
  local key, runtime = H.RowKey("Dual Offline"), H.Debug()
  runtime.scope.pending.dualq001 = {kind="Q", target="Dual Offline", key=key, at=GetServerTime()}
  runtime.scope.meta.pendingCount = runtime.scope.meta.pendingCount + 1
  runtime.queue[#runtime.queue + 1] = {p=3, target="Dual Offline", payload="Q;1;dualq001;us/pvp",
    kind="Q", nonce="dualq001", created=GetTime(), ttl=60, due=GetTime()}
  M.addonResult = 12; H.SendTick()
  check(not runtime.newsOffline or not runtime.newsOffline[key], "offline correlation: Q result does not arm news cooldown")
  ns.char.kills, ns.char.points = 1, 1
  H.Score(1, {name="Offline News", class="MAGE"}); M.advance(14)
  check(runtime.newsOffline and runtime.newsOffline[key] and runtime.newsOffline[key] > GetServerTime(),
    "offline correlation: later news result arms its own cooldown")
end

-- Session-only feed and offline maps prune expired entries and never grow past their hard caps.
do
  local ns, H = fresh(); startWorld(H)
  local runtime = H.Debug()
  runtime.feedLast = { expired=GetTime() - 31 }
  for i = 1, 70 do runtime.feedLast["feed " .. i] = GetTime() - i / 100 end
  addRow(ns, H, "Bound Feed", {gen=310, seq=1, kills=5, points=5})
  M.fire("CHAT_MSG_ADDON", "GodslayerG", news(ns, {gen=310, seq=2, kills=6, points=6}), "WHISPER", "Bound Feed")
  local feedCount = 0; for _ in pairs(runtime.feedLast) do feedCount = feedCount + 1 end
  check(not runtime.feedLast.expired and feedCount <= 64,
    "session maps: feed presentation prunes expired entries and remains bounded")
end

do
  local ns, H = fresh(); startWorld(H)
  local runtime = H.Debug()
  runtime.newsOffline = { expired=GetServerTime() - 1 }
  for i = 1, 300 do runtime.newsOffline["offline " .. i] = GetServerTime() + 1800 + i end
  addRow(ns, H, "Bound Offline", {gen=320, seq=1, kills=0, points=0, version="3.1.0"})
  runtime.directoryNames["bound offline"] = true
  M.addonResult = 12
  ns.char.kills, ns.char.points = 1, 1
  H.Score(1, {name="Bound Victim", class="MAGE"}); M.advance(14)
  local offlineCount = 0; for _ in pairs(runtime.newsOffline) do offlineCount = offlineCount + 1 end
  check(not runtime.newsOffline.expired and runtime.newsOffline[H.RowKey("Bound Offline")] and offlineCount <= 300,
    "session maps: news offline use prunes expired entries and remains bounded")
end

-- Fifty rapid kills cannot fill or evict the protocol queue, and news uses at most six sends/minute.
do
  local ns, H = fresh(); startWorld(H)
  for i = 1, 20 do
    local name = "Busy " .. alpha(i)
    addRow(ns, H, name, {gen=600+i, version="3.1.0"}); H.Debug().directoryNames[name:lower()] = true
  end
  for i = 1, 50 do
    ns.char.kills, ns.char.points = i, i
    H.Score(1, {name="Rapid " .. alpha(i), class="MAGE"}); M.advance(0.5)
  end
  -- Let six news sends load the two-per-burst and six-per-minute windows, then inject the Q without
  -- resetting lastSend. Its accepted response must use the next spacing slot.
  M.advance(28)
  check(#H.Debug().snapshotMinute >= 6, "fifty-kill hunt loads the news minute window")
  M.fire("CHAT_MSG_ADDON", "GodslayerG", "Q;1;busyresp;us/pvp", "WHISPER", "Busy Asker")
  local due
  for _ = 1, 30 do
    local owed = H.Debug().owedResponses or {}
    for key, rec in pairs(owed) do if key:find("busyresp", 1, true) and rec.due then due = rec.due end end
    if due then break end
    M.runNextTimer()
  end
  check(due ~= nil, "fifty-kill hunt turns the accepted Q into an owed response")
  M.advance(2.1)
  local sentAt
  for _, row in ipairs(M.sentAddon) do
    if row[5] == "Busy Asker" and row[2]:match("^R;1;busyresp;") then sentAt = row[4]; break end
  end
  check(sentAt and due and sentAt - due <= 2.001,
    "fifty-kill hunt sends the owed response within one spacing slot")
  check(#H.Debug().snapshotMinute <= 6, "fifty-kill hunt holds news to six sends per minute")
  check(#H.Debug().nonResponseMinute <= 8, "fifty-kill hunt preserves two minute slots for responses")
  local retired = false
  for _, c in pairs(H.Debug().scope.candidates) do if c.retired then retired = true end end
  check(not retired, "fifty-kill hunt never retires a discovery candidate")
end

-- Latest snapshot survives zero targets, uses N for 3.1 and R for 3.0, and coalesces five kills.
do
  local ns, H = fresh(); startWorld(H)
  ns.char.kills, ns.char.points = 1, 1; H.Score(1, {name="First Victim", class="MAGE"}); M.advance(13)
  eq(countSent("N"), 0, "snapshot with zero targets is retained without a fake delivery")
  addRow(ns, H, "Late Peer", {version="3.1.0", kills=2, points=2})
  H.Debug().directoryNames["late peer"] = true
  -- Any newly confirmed peer wakes the retained latest snapshot.
  H.MergeRow(H.RowKey("Late Peer"), "Late Peer", assert(H.Parse(wire(ns, "0", {version="3.1.0", kills=2, points=2}))))
  M.advance(3)
  check(countSent("N", "Late Peer") >= 1, "late peer receives the latest undelivered kill snapshot")

  ns, H = fresh(); startWorld(H)
  addRow(ns, H, "Modern Peer", {version="3.1.0"}); H.Debug().directoryNames["modern peer"] = true
  addRow(ns, H, "Legacy Peer", {version="3.0.0"}); H.Debug().directoryNames["legacy peer"] = true
  H.Debug().scope.partners[H.RowKey("Legacy Peer")] = {name="Legacy Peer", heard=GetServerTime(), verified=true}
  addRow(ns, H, "Legacy Stranger", {version="3.0.0"}); H.Debug().directoryNames["legacy stranger"] = true
  M.inCombat = true
  for i = 1, 5 do
    ns.char.kills, ns.char.points = i, i
    H.Score(1, {name="Victim " .. i, class="PALADIN"}); M.advance(1)
  end
  M.advance(12); M.inCombat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(8)
  eq(countSent("N", "Modern Peer"), 1, "five kills inside quiet window produce one N")
  eq(countSent("R", "Modern Peer"), 0, "3.1 peer receives N only")
  eq(countSent("R", "Legacy Peer"), 1, "3.0 peer receives one legacy R")
  eq(countSent("N", "Legacy Peer"), 0, "3.0 peer never receives N")
  eq(countSent(nil, "Legacy Stranger"), 0, "3.0 non-partner consumes no fan-out slot")
  local parsed
  for _, row in ipairs(M.sentAddon) do if row[5] == "Modern Peer" then parsed = H.Parse(row[2]) end end
  check(parsed and parsed.batchKills == 5 and parsed.batchPoints == 5,
    "coalesced N carries batch totals (kills=" .. tostring(parsed and parsed.batchKills)
      .. ", points=" .. tostring(parsed and parsed.batchPoints) .. ")")

  ns.char.kills, ns.char.points = 6, 6
  H.Score(1, {name="Unknown victim"}); M.advance(16)
  local unknown
  for i = #M.sentAddon, 1, -1 do
    if M.sentAddon[i][2]:match("^N;") then unknown = H.Parse(M.sentAddon[i][2]); break end
  end
  check(unknown and unknown.victimName == nil and unknown.victimClass == nil,
    "unknown or secret victim identity is omitted from N")

  M.sentAddon = {}; H.LocalChanged(); H.AdjustWeekly(1, 0); H.AfterReset(ns.char.hunterGen); M.advance(35)
  eq(countSent("N"), 0, "recount, reset, and LocalChanged never generate N")

  ns, H = fresh(); startWorld(H)
  addRow(ns, H, "Push Stranger", {version="3.1.0"}); H.Debug().directoryNames["push stranger"] = true
  H.LocalChanged(); M.advance(14)
  eq(countSent(nil, "Push Stranger"), 0, "LocalChanged sends no row push to a 3.1 non-partner")

  ns, H = fresh(); startWorld(H)
  addRow(ns, H, "Lapsed Partner", {version="3.1.0"})
  local lapsedKey, lapsedRuntime = H.RowKey("Lapsed Partner"), H.Debug()
  lapsedRuntime.scope.partners[lapsedKey] = {
    name="Lapsed Partner", heard=GetServerTime(), verified=true,
  }
  M.inCombat = true; H.LocalChanged(); M.advance(13)
  eq(snapshotCount(H), 1, "row push send gate: current partner is selected while combat holds delivery")
  lapsedRuntime.scope.partners[lapsedKey].heard = GetServerTime() - 1801
  M.inCombat = false
  local lastSend, attempts = lapsedRuntime.lastSend, #lapsedRuntime.sentMinute
  H.SendTick()
  check(snapshotCount(H) == 0 and countSent(nil, "Lapsed Partner") == 0
    and lapsedRuntime.lastSend == lastSend and #lapsedRuntime.sentMinute == attempts,
    "row push send gate: expired partner is dropped without an API attempt or budget charge")
end

-- A newer finalized batch supersedes pending older items, folds their totals, and carries their
-- targets. A target that already received A still gets B's frozen row; a target that missed A gets
-- one folded N with B's victim. Non-kill deadlines and in-window upgrades remain unchanged.
do
  local ns, H = fresh(); startWorld(H)
  local peers = { "Frozen Alpha", "Frozen Beta" }
  for _, name in ipairs(peers) do
    addRow(ns, H, name, {version="3.1.0"}); H.Debug().directoryNames[name:lower()] = true
  end
  M.inCombat = true
  ns.char.kills, ns.char.points = 1, 1
  H.Score(1, {name="Batch A", class="MAGE"}); M.advance(13)
  M.inCombat = false
  H.Debug().lastSend = -1e9
  H.SendTick()
  local gotA = M.sentAddon[#M.sentAddon] and M.sentAddon[#M.sentAddon][5]
  local missedA = gotA == peers[1] and peers[2] or peers[1]
  check(gotA ~= nil and countSent("N", gotA) == 1, "batch carry: A reaches exactly one peer before B")
  M.inCombat = true
  ns.char.kills, ns.char.points = 2, 2
  H.Score(1, {name="Batch B", class="MAGE"}); M.advance(13)
  local queued, onlyLatest = 0, true
  for _, item in pairs(H.Debug().snapshots) do
    queued = queued + 1
    onlyLatest = onlyLatest and item.batch == H.Debug().latestSnapshot
  end
  check(queued == 2 and onlyLatest and H.Debug().latestSnapshot.kills == 2,
    "batch carry: snapshot queue contains only B and its folded A totals")
  M.inCombat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(15)
  local received = { [gotA]={}, [missedA]={} }
  for _, sent in ipairs(M.sentAddon) do
    if received[sent[5]] and sent[2]:match("^N;") then
      received[sent[5]][#received[sent[5]] + 1] = H.Parse(sent[2])
    end
  end
  local missed = received[missedA][1]
  check(#received[missedA] == 1 and missed and missed.kills == 2 and missed.batchKills == 2
    and missed.victimName == "Batch B",
    "batch carry: peer that missed A receives one folded N with B's frozen row")
  local first, second = received[gotA][1], received[gotA][2]
  check(#received[gotA] == 2 and first and second and first.kills == 1 and first.batchKills == 1
    and first.victimName == "Batch A" and second.kills == 2 and second.batchKills == 2
    and second.victimName == "Batch B",
    "batch carry: peer that received A also receives B's frozen folded payload")

  ns, H = fresh(); startWorld(H)
  addRow(ns, H, "Deadline Reset", {version="3.1.0"}); H.Debug().directoryNames["deadline reset"] = true
  H.LocalChanged(); M.advance(10); H.AdjustWeekly(0, 0); M.advance(10); H.LocalChanged(); M.advance(9)
  ns.char.kills, ns.char.points = 1, 1
  H.Score(1, {name="Late First Kill", class="ROGUE"}); M.advance(2)
  eq(countSent("N", "Deadline Reset"), 0, "batch deadline: non-kill opener does not expire one second after first kill")
  M.advance(11)
  eq(countSent("N", "Deadline Reset"), 1, "batch deadline: first kill receives its own quiet window")

  ns, H = fresh(); startWorld(H)
  addRow(ns, H, "Upgrade Peer", {version="3.1.0"}); H.Debug().directoryNames["upgrade peer"] = true
  ns.char.kills, ns.char.points = 1, 1
  H.Score(1, {name="Upgraded Victim", class="WARRIOR"}); M.advance(5)
  ns.char.points = 5; H.AdjustWeekly(4, 0); M.advance(13)
  local upgraded
  for _, sent in ipairs(M.sentAddon) do if sent[5] == "Upgrade Peer" and sent[2]:match("^N;") then upgraded = H.Parse(sent[2]) end end
  check(upgraded and upgraded.batchKills == 1 and upgraded.batchPoints == 5,
    "batch points: a late Olympus upgrade inside the window counts in the frozen batch")
end

-- A reset row supersedes an older generation without folding its pending news. Its row-only batch
-- goes only to a current partner, whose real receive path accepts and merges the new generation.
do
  local ns, H = fresh(); startWorld(H)
  local stranger, partner = "Reset Stranger", "Reset Partner"
  local peers = { stranger, partner }
  for _, name in ipairs(peers) do
    addRow(ns, H, name, {version="3.1.0"}); H.Debug().directoryNames[name:lower()] = true
  end
  H.Debug().scope.partners[H.RowKey(partner)] = {name=partner, heard=GetServerTime(), verified=true}
  M.inCombat = true
  ns.char.kills, ns.char.points = 1, 1
  H.Score(1, {name="Before Reset", class="MAGE"}); M.advance(13)
  eq(snapshotCount(H), 2,
    "generation reset: pre-reset news is queued for both peers")
  local oldGeneration = ns.char.hunterGen
  ns.ResetCharacter()
  check(ns.char.hunterGen > oldGeneration, "generation reset: ResetCharacter advances the hunter generation")
  M.advance(12)
  local resetBatch = H.Debug().latestSnapshot
  check(resetBatch and resetBatch.fields[1] == H.Base36(ns.char.hunterGen)
    and resetBatch.kills == 0 and resetBatch.newsPayload == nil,
    "generation reset: frozen reset row does not fold old-generation news")
  M.inCombat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(6)
  local resetWire
  for _, sent in ipairs(M.sentAddon) do
    if sent[5] == partner and sent[2]:match("^R;") then resetWire = sent[2] end
  end
  eq(countSent(nil, stranger), 0, "generation reset: carried 3.1 non-partner receives no row push")
  check(countSent("R", partner) == 1 and resetWire ~= nil,
    "generation reset: current 3.1 partner receives one frozen row push")
  eq(countSent("N"), 0, "generation reset: reset delivery has no news payload")

  local resetGeneration = ns.char.hunterGen
  ns.char.kills, ns.char.points = 1, 1
  H.Score(1, {name="After Reset", class="MAGE"}); M.advance(16)
  for _, name in ipairs(peers) do
    local later
    for _, sent in ipairs(M.sentAddon) do
      if sent[5] == name and sent[2]:match("^N;") then later = H.Parse(sent[2]) end
    end
    check(later and later.gen == ns.char.hunterGen and later.kills == 1 and later.batchKills == 1,
      "generation reset: " .. name .. " receives normal news for the later kill")
  end

  local receiverNS, receiverH = fresh(nil, "Reset Receiver"); startWorld(receiverH)
  addRow(receiverNS, receiverH, "Vesh Torchman",
    {gen=oldGeneration, seq=5, kills=5, points=5, version="3.1.0"})
  local senderKey = receiverH.RowKey("Vesh Torchman")
  receiverH.Debug().scope.partners[senderKey] = {
    name="Vesh Torchman", heard=GetServerTime(), verified=true,
  }
  M.fire("CHAT_MSG_ADDON", "GodslayerG", resetWire, "WHISPER", "Vesh Torchman")
  local received = receiverH.Debug().scope.rows[senderKey]
  check(received and received.gen == resetGeneration and received.kills == 0,
    "generation reset: partner's real receive path merges the new-generation row")
end

-- A temporary inability to freeze B leaves A intact and keeps exactly one retrying coalescer. Once
-- the class returns, B freezes and folds A normally.
do
  local ns, H = fresh(); startWorld(H)
  for _, name in ipairs({ "Freeze Alpha", "Freeze Beta" }) do
    addRow(ns, H, name, {version="3.1.0"}); H.Debug().directoryNames[name:lower()] = true
  end
  M.inCombat = true
  ns.char.kills, ns.char.points = 1, 1
  H.Score(1, {name="Freeze A", class="MAGE"}); M.advance(13)
  local older, oldBatch = {}, H.Debug().latestSnapshot
  for id, item in pairs(H.Debug().snapshots) do older[id] = item end
  ns.char.kills, ns.char.points = 2, 2
  H.Score(1, {name="Freeze B", class="MAGE"})
  ns.char.class = nil
  M.advance(13)
  local intact, count = H.Debug().coalesce ~= nil, 0
  for id, item in pairs(older) do intact = intact and H.Debug().snapshots[id] == item; count = count + 1 end
  check(intact and H.Debug().latestSnapshot == oldBatch,
    "freeze retry: nil own fields leave every older snapshot and the new coalescer intact")
  eq(count, 2, "freeze retry: setup retained both older targets")
  ns.char.class = "MAGE"
  H.LocalChanged()
  M.advance(11)
  check(H.Debug().latestSnapshot == oldBatch,
    "freeze retry: an older retry does not shorten a newer quiet window")
  M.advance(1)
  local replacement = H.Debug().latestSnapshot
  local pending, onlyReplacement = 0, true
  for _, item in pairs(H.Debug().snapshots) do
    pending = pending + 1; onlyReplacement = onlyReplacement and item.batch == replacement
  end
  check(replacement ~= oldBatch and replacement.kills == 2 and replacement.newsPayload
    and pending == 2 and onlyReplacement,
    "freeze retry: restored class freezes B, folds A, and replaces the old queue")
end

-- The hard deadline emits during a continuous hunt, and longest valid victim names stay in budget.
do
  local ns, H = fresh(); startWorld(H)
  addRow(ns, H, "Deadline Peer", {version="3.1.0"}); H.Debug().directoryNames["deadline peer"] = true
  for i = 1, 4 do
    ns.char.kills, ns.char.points = i, i; H.Score(1, {name="Long Fight", class="ROGUE"}); M.advance(10)
  end
  check(countSent("N", "Deadline Peer") >= 1, "thirty-second hard deadline emits during continuous kills")

  local longest = string.rep("A", 24) .. " " .. string.rep("B", 24)
  ns.char.kills, ns.char.points = 1, 1
  local payload = H.NewsMessage({kills=1, points=5, victimName=longest, victimClass="WARRIOR"})
  check(payload and #payload <= H.LIMITS.payload and H.Parse(payload),
    "longest canonical victim name keeps N at or below 240 bytes (bytes=" .. tostring(payload and #payload)
      .. ", parsed=" .. tostring(payload and H.Parse(payload) ~= nil) .. ")")
end

-- Row refreshes never consume live news this client has not announced. A full R tuple before N still
-- shows the full batch once, and a mid-batch R leaves the full three-kill batch to announce.
do
  local ns, H = fresh(); startWorld(H)
  addRow(ns, H, "Full First", {gen=910, seq=1, kills=0, points=0, version="3.1.0"})
  local fullKey = H.RowKey("Full First")
  H.Debug().scope.partners[fullKey] = {name="Full First", heard=GetServerTime(), verified=true}
  M.fire("CHAT_MSG_ADDON", "GodslayerG", wire(ns, "0", {gen=910, seq=4, kills=3, points=3,
    version="3.1.0"}), "WHISPER", "Full First")
  M.fire("CHAT_MSG_ADDON", "GodslayerG", news(ns, {gen=910, seq=4, kills=3, points=3,
    batchKills=3, batchPoints=3}), "WHISPER", "Full First")
  check(M.printed[#M.printed]:find("took down 3 players, +3", 1, true),
    "news base: full R tuple before N still announces the full batch once")

  addRow(ns, H, "Delta Peer", {gen=920, seq=1, kills=0, points=0, version="3.1.0"})
  local deltaKey = H.RowKey("Delta Peer")
  H.Debug().scope.partners[deltaKey] = {name="Delta Peer", heard=GetServerTime(), verified=true}
  M.fire("CHAT_MSG_ADDON", "GodslayerG", wire(ns, "0", {gen=920, seq=2, kills=1, points=1,
    version="3.1.0"}), "WHISPER", "Delta Peer")
  local deltaPrinted = #M.printed
  M.fire("CHAT_MSG_ADDON", "GodslayerG", news(ns, {gen=920, seq=4, kills=3, points=3,
    batchKills=3, batchPoints=3}), "WHISPER", "Delta Peer")
  local row = H.Debug().scope.rows[deltaKey]
  check(row.kills == 3 and #M.printed == deltaPrinted + 1
    and M.printed[#M.printed]:find("Delta Peer", 1, true)
    and M.printed[#M.printed]:find("took down 3 players, +3", 1, true),
    "news base: mid-batch R leaves all three kills to announce")
  M.fire("CHAT_MSG_ADDON", "GodslayerG", news(ns, {gen=920, seq=6, kills=5, points=5,
    batchKills=2, batchPoints=2}), "WHISPER", "Delta Peer")
  eq(row.kills, 5, "combat-delayed batch B advances after batch A")
  M.advance(31)
  check(M.printed[#M.printed]:find("5 kills", 1, true), "combat-delayed batch B is eventually shown")

  addRow(ns, H, "No Victim", {gen=930, seq=1, kills=46, points=46, version="3.1.0"})
  M.fire("CHAT_MSG_ADDON", "GodslayerG", news(ns, {gen=930, seq=2, kills=47, points=47,
    victimName="", victimClass=""}), "WHISPER", "No Victim")
  check(M.printed[#M.printed]:find("No Victim (Warrior) scored a kill, +1. 47 kills", 1, true),
    "feed wording: one kill without a victim says scored a kill")

  local createdKey = H.RowKey("Created Row")
  H.Debug().scope.partners[createdKey] = {name="Created Row", heard=GetServerTime(), verified=true}
  M.fire("CHAT_MSG_ADDON", "GodslayerG", wire(ns, "0", {gen=935, seq=4, kills=4, points=4,
    version="3.1.0"}), "WHISPER", "Created Row")
  local createdBase = H.Debug().newsBase[createdKey]
  check(H.Debug().scope.rows[createdKey] and createdBase and createdBase.gen == 935
    and createdBase.kills == 0 and createdBase.points == 0,
    "news base: an R-created row starts from nothing announced")
  local createdPrinted = #M.printed
  local createdNews = news(ns, {gen=935, seq=4, kills=4, points=4,
    batchKills=4, batchPoints=4, victimName="", victimClass=""})
  M.fire("CHAT_MSG_ADDON", "GodslayerG", createdNews, "WHISPER", "Created Row")
  check(#M.printed == createdPrinted + 1 and M.printed[#M.printed]:find("Created Row", 1, true)
    and M.printed[#M.printed]:find("took down 4 players, +4", 1, true),
    "news base: N after a row-creating R announces all four kills once")
  M.fire("CHAT_MSG_ADDON", "GodslayerG", createdNews, "WHISPER", "Created Row")
  eq(#M.printed, createdPrinted + 1, "news base: replay after a row-creating R is silent")
end

-- A folded replacement announces both kills to a peer that missed A, but only B to a peer whose
-- client already announced A.
do
  local ns, H = fresh(); startWorld(H)
  addRow(ns, H, "Saw A", {gen=940, seq=1, kills=0, points=0, version="3.1.0"})
  M.fire("CHAT_MSG_ADDON", "GodslayerG", news(ns, {gen=940, seq=2, kills=1, points=1,
    batchKills=1, batchPoints=1, victimName="Batch A", victimClass="MAGE"}), "WHISPER", "Saw A")
  M.fire("CHAT_MSG_ADDON", "GodslayerG", news(ns, {gen=940, seq=3, kills=2, points=2,
    batchKills=2, batchPoints=2, victimName="Batch B", victimClass="MAGE"}), "WHISPER", "Saw A")
  local pending = H.Debug().feedPending[H.RowKey("Saw A")]
  check(pending and pending.kills == 1 and pending.points == 1 and pending.victimName == "Batch B",
    "folded news: peer that announced A presents only B from the replacement")

  addRow(ns, H, "Missed A", {gen=950, seq=1, kills=0, points=0, version="3.1.0"})
  M.fire("CHAT_MSG_ADDON", "GodslayerG", news(ns, {gen=950, seq=3, kills=2, points=2,
    batchKills=2, batchPoints=2, victimName="Batch B", victimClass="MAGE"}), "WHISPER", "Missed A")
  check(M.printed[#M.printed]:find("Missed A", 1, true)
    and M.printed[#M.printed]:find("took down 2 players, +2", 1, true),
    "folded news: peer that missed A presents both kills from the replacement")
end

-- Receiver binds identity to CHAT_MSG_ADDON sender, validates scope/order, and dedupes replay.
do
  local ns, H = fresh(); startWorld(H)
  addRow(ns, H, "Zed Slayer", {gen=100, seq=1, kills=5, points=5, version="3.1.0"})
  local beforePrint = #M.printed
  M.fire("CHAT_MSG_ADDON", "GodslayerG", news(ns, {seq=2, kills=6, points=6}), "WHISPER", "Unknown Sender")
  check(H.Debug().scope.rows[H.RowKey("Unknown Sender")] == nil
    and H.Debug().scope.candidates[H.RowKey("Unknown Sender")], "unknown N seeds candidate but no row")
  eq(#M.printed, beforePrint, "unknown N produces no notification")

  local good = news(ns, {seq=2, kills=6, points=6, victimName="Bob Smith", victimClass="PALADIN"})
  M.fire("CHAT_MSG_ADDON", "GodslayerG", good, "WHISPER", "Zed Slayer")
  local row = H.Debug().scope.rows[H.RowKey("Zed Slayer")]
  check(row and row.name == "Zed Slayer" and row.kills == 6, "N owner is authenticated sender only")
  check(M.printed[#M.printed]:find("Zed Slayer (Warrior) took down Bob Smith (Paladin)", 1, true),
    "valid N prints the live Slayers line")
  local shown = #M.printed
  M.fire("CHAT_MSG_ADDON", "GodslayerG", good, "WHISPER", "Zed Slayer")
  eq(#M.printed, shown, "N replay is deduped")
  local replayKey = "news:" .. H.RowKey("Zed Slayer") .. ":100:2"
  if H.Debug().scope.completedNonces[replayKey] then
    H.Debug().scope.completedNonces[replayKey] = nil
    H.Debug().scope.meta.completedCount = H.Debug().scope.meta.completedCount - 1
  end
  M.fire("CHAT_MSG_ADDON", "GodslayerG", good, "WHISPER", "Zed Slayer")
  check(#M.printed == shown and not H.Debug().feedPending[H.RowKey("Zed Slayer")],
    "news base makes the same N silent after completed-nonce eviction")
  if H.Debug().scope.completedNonces[replayKey] then
    H.Debug().scope.completedNonces[replayKey] = nil
    H.Debug().scope.meta.completedCount = H.Debug().scope.meta.completedCount - 1
  end
  H.Debug().newsBase[H.RowKey("Zed Slayer")] = {gen=100, kills=5, points=5}
  M.fire("CHAT_MSG_ADDON", "GodslayerG", good, "WHISPER", "Zed Slayer")
  check(#M.printed == shown and not H.Debug().feedPending[H.RowKey("Zed Slayer")],
    "per-row replay guard is reached and survives completed-nonce eviction")

  addRow(ns, H, "Same Tuple", {gen=150, seq=1, kills=5, points=5, version="3.1.0"})
  local sameKey = H.RowKey("Same Tuple")
  H.Debug().scope.partners[sameKey] = {name="Same Tuple", heard=GetServerTime(), verified=true}
  M.fire("CHAT_MSG_ADDON", "GodslayerG", wire(ns, "0", {gen=150, seq=2, kills=6, points=6,
    version="3.1.0"}), "WHISPER", "Same Tuple")
  local sameBefore = #M.printed
  M.fire("CHAT_MSG_ADDON", "GodslayerG", news(ns, {gen=150, seq=2, kills=6, points=6}), "WHISPER", "Same Tuple")
  check(#M.printed == sameBefore + 1 and M.printed[#M.printed]:find("Same Tuple", 1, true),
    "equal N tuple still announces when an R carried it before any live line")
  check(H.Parse(good .. ";Forged Owner") == nil, "forged owner field is rejected rather than trusted")
  M.fire("CHAT_MSG_ADDON", "GodslayerG", news(ns, {seq=3, kills=7, points=7, scope="us/standard"}), "WHISPER", "Zed Slayer")
  eq(row.kills, 6, "foreign wire scope N is rejected")
  M.fire("CHAT_MSG_ADDON", "GodslayerG", news(ns, {seq=3, kills=7, points=7, faction="Alliance"}), "WHISPER", "Zed Slayer")
  eq(row.kills, 6, "foreign faction N is rejected")
  M.fire("CHAT_MSG_ADDON", "GodslayerG", news(ns, {seq=1, kills=4, points=4}), "WHISPER", "Zed Slayer")
  eq(row.kills, 6, "non-monotone N is rejected")
end

-- Sender lockdown keeps only the newest frozen batch, which carries pending kills. A stale 3.1
-- batch still uses N so the receiver can merge it without printing a live line.
do
  local ns, H = fresh(); startWorld(H)
  addRow(ns, H, "Lock Peer", {version="3.1.0"}); H.Debug().directoryNames["lock peer"] = true
  M.lockdown = true
  ns.char.kills, ns.char.points = 1, 1; H.Score(1, {name="Old Victim", class="MAGE"}); M.advance(13)
  ns.char.kills, ns.char.points = 2, 2; H.Score(1, {name="New Victim", class="MAGE"}); M.advance(13)
  eq(countSent(), 0, "lockdown sends nothing")
  M.lockdown = false; M.advance(5)
  eq(countSent("N", "Lock Peer"), 1, "lockdown exit sends one folded fresh batch")
  local folded
  for _, sent in ipairs(M.sentAddon) do
    if sent[5] == "Lock Peer" and sent[2]:match("^N;") then folded = H.Parse(sent[2]) end
  end
  check(folded and folded.kills == 2 and folded.batchKills == 2 and folded.victimName == "New Victim",
    "lockdown replacement carries both kills with the newest frozen row")

  M.sentAddon = {}; M.lockdown = true
  ns.char.kills, ns.char.points = 3, 3; H.Score(1, {name="Stale Victim", class="MAGE"}); M.advance(314)
  M.lockdown = false; M.advance(5)
  eq(countSent("N", "Lock Peer"), 1, "stale lockdown snapshot remains an N for a 3.1 peer")
  eq(countSent("R", "Lock Peer"), 0, "stale lockdown snapshot does not become a nonce-zero R")

  ns, H = fresh(); startWorld(H)
  addRow(ns, H, "Stale Peer", {gen=960, seq=1, kills=0, points=0, version="3.1.0"})
  local before = #M.printed
  M.fire("CHAT_MSG_ADDON", "GodslayerG", news(ns, {gen=960, seq=2, kills=1, points=1,
    made=GetServerTime()-301}), "WHISPER", "Stale Peer")
  check(H.Debug().scope.rows[H.RowKey("Stale Peer")].kills == 1 and #M.printed == before,
    "stale N merges the row without printing a live line")
end

-- Result 3/11 retain snapshots, result 12 drops with cooldown, and responses preempt news.
do
  local ns, H = fresh(); startWorld(H)
  addRow(ns, H, "Fault Peer", {version="3.1.0"}); H.Debug().directoryNames["fault peer"] = true
  M.addonResult = 3
  ns.char.kills, ns.char.points = 1, 1; H.Score(1, {name="Fault Victim", class="MAGE"}); M.advance(14)
  check(H.Debug().pauseUntil > M.now and snapshotFor(H, "Fault Peer"), "result 3 backs off and retains news")
  M.addonResult = 0; M.advance(H.Debug().pauseUntil - M.now + 1)

  M.addonResult = 11
  ns.char.kills, ns.char.points = 2, 2; H.Score(1, {name="Lock Victim", class="MAGE"}); M.advance(14)
  check(snapshotFor(H, "Fault Peer"), "result 11 retains latest news slot")
  M.addonResult = 0; M.advance(3)

  M.addonResult = 12
  ns.char.kills, ns.char.points = 3, 3; H.Score(1, {name="Offline Victim", class="MAGE"}); M.advance(14)
  check(not snapshotFor(H, "Fault Peer")
    and H.Debug().newsOffline[H.RowKey("Fault Peer")] - GetServerTime() >= 1790,
    "result 12 drops event and applies thirty-minute news cooldown")

  M.addonResult, H.Debug().newsOffline[H.RowKey("Fault Peer")] = 0, nil
  ns.char.kills, ns.char.points = 4, 4; H.Score(1, {name="Priority Victim", class="MAGE"}); M.advance(12)
  M.sentAddon = {}
  M.fire("CHAT_MSG_ADDON", "GodslayerG", "Q;1;priority;us/pvp", "WHISPER", "Owed Peer")
  M.advance(4)
  check(M.sentAddon[1] and M.sentAddon[1][2]:match("^R;1;priority;"),
    "owed Q response preempts news by no more than one send slot")
end

-- Fan-out thresholds are bounded and deterministic rotation changes the large-network slice.
local function fanoutCase(size, wantMax)
  local ns, H = fresh(); startWorld(H)
  local template = H.Parse(wire(ns, "0", {version="3.1.0"}))
  for i = 1, size do
    local name = "Fan " .. alpha(i)
    local row = {}; for k, v in pairs(template) do row[k] = v end
    row.gen, row.seq, row.version = 100 + i, 1, "3.1.0"
    H.MergeRow(H.RowKey(name), name, row); H.Debug().directoryNames[name:lower()] = true
  end
  M.inCombat = true; ns.char.kills, ns.char.points = 1, 1
  H.Score(1, {name="Fan Victim", class="MAGE"}); M.advance(13)
  local first, keys = 0, {}
  for key in pairs(H.Debug().latestSnapshot.selected) do first=first+1; keys[key]=true end
  check(first <= wantMax and (size > 20 or first == size), "fan-out " .. size .. " targets is bounded")
  if size > 20 then
    ns.char.kills, ns.char.points = 2, 2; H.Score(1, {name="Fan Victim Two", class="MAGE"}); M.advance(13)
    local changed = false; for key in pairs(H.Debug().latestSnapshot.selected) do if not keys[key] then changed=true end end
    check(changed, "fan-out " .. size .. " rotates fairly")
  end
end
fanoutCase(20, 20); fanoutCase(200, 10); fanoutCase(2000, 10)

-- Carried targets have first claim on the replacement batch. New partners cannot displace them,
-- because every carried item replaces one pending item removed from A.
do
  local ns, H = fresh(); startWorld(H)
  for i = 1, 30 do
    local name = "Carry " .. alpha(i)
    addRow(ns, H, name, {gen=1100+i, version="3.1.0"})
    H.Debug().directoryNames[name:lower()] = true
  end
  M.inCombat = true
  ns.char.kills, ns.char.points = 1, 1
  H.Score(1, {name="Carry A", class="MAGE"}); M.advance(13)
  local carried, carriedCount = {}, 0
  for key in pairs(H.Debug().latestSnapshot.selected) do carried[key], carriedCount = true, carriedCount + 1 end
  eq(carriedCount, 12, "carried priority: A leaves twelve pending targets")
  local partners = 0
  for key, row in pairs(H.Debug().scope.rows) do
    if not carried[key] and partners < 6 then
      H.Debug().scope.partners[key] = {name=row.name, heard=GetServerTime(), verified=true}
      partners = partners + 1
    end
  end
  eq(partners, 6, "carried priority: six new verified partners are outside A")
  ns.char.kills, ns.char.points = 2, 2
  H.Score(1, {name="Carry B", class="MAGE"}); M.advance(13)
  local replacement, pending, allCarried = H.Debug().latestSnapshot, 0, true
  for key in pairs(carried) do allCarried = allCarried and replacement.selected[key] == true end
  for _, item in pairs(H.Debug().snapshots) do
    pending = pending + 1
    allCarried = allCarried and item.batch == replacement
  end
  check(allCarried and pending == 12 and pending <= 20,
    "carried priority: all twelve carried targets get B and the pending queue stays bounded")
end

-- Carried exemptions exist only during replacement finalization. If twelve carried 3.0 partners
-- expire, twelve rotating 3.1 rows take B; restoring those partners cannot grow B past its limit.
do
  local ns, H = fresh(); startWorld(H)
  local legacyKeys = {}
  for i = 1, 12 do
    local name = "RatchetL " .. alpha(i)
    addRow(ns, H, name, {gen=1300+i, version="3.0.0"})
    local key = H.RowKey(name); legacyKeys[#legacyKeys + 1] = key
    H.Debug().directoryNames[name:lower()] = true
    H.Debug().scope.partners[key] = {name=name, heard=GetServerTime(), verified=true}
  end
  for i = 1, 30 do
    local name = "RatchetM " .. alpha(i)
    addRow(ns, H, name, {gen=1400+i, version="3.1.0"})
    H.Debug().directoryNames[name:lower()] = true
  end
  M.inCombat = true
  ns.char.kills, ns.char.points = 1, 1
  H.Score(1, {name="Ratchet A", class="MAGE"}); M.advance(13)
  local onlyLegacy = snapshotCount(H) == 12
  for _, key in ipairs(legacyKeys) do onlyLegacy = onlyLegacy and H.Debug().latestSnapshot.selected[key] == true end
  check(onlyLegacy, "carried ratchet: A leaves twelve current 3.0 partners pending")

  for _, key in ipairs(legacyKeys) do H.Debug().scope.partners[key].heard = GetServerTime() - 1801 end
  ns.char.kills, ns.char.points = 2, 2
  H.Score(1, {name="Ratchet B", class="MAGE"}); M.advance(13)
  check(snapshotCount(H) == 12 and H.Debug().latestSnapshot.carriedTargets == nil,
    "carried ratchet: expired carries are replaced by twelve rotating targets and exemption state is cleared")

  for _, key in ipairs(legacyKeys) do
    local row = H.Debug().scope.rows[key]
    H.Debug().scope.partners[key] = {name=row.name, heard=GetServerTime(), verified=true}
  end
  M.fire("PLAYER_REGEN_ENABLED")
  eq(snapshotCount(H), 12, "carried ratchet: returning partners cannot refill a frozen full batch")

  ns.char.kills, ns.char.points = 3, 3
  H.Score(1, {name="Ratchet C", class="MAGE"}); M.advance(13)
  check(snapshotCount(H) == 12 and snapshotCount(H) <= 20,
    "carried ratchet: the following kill remains bounded after partner return")
end

-- Repeated partner churn across replacement batches never breaks the absolute twenty-snapshot cap.
do
  local ns, H = fresh(); startWorld(H)
  local churn = {}
  for i = 1, 24 do
    local name = "ChurnL " .. alpha(i)
    addRow(ns, H, name, {gen=1500+i, version="3.0.0"})
    local key = H.RowKey(name); churn[#churn + 1] = key
    H.Debug().directoryNames[name:lower()] = true
  end
  for i = 1, 30 do
    local name = "ChurnM " .. alpha(i)
    addRow(ns, H, name, {gen=1600+i, version="3.1.0"})
    H.Debug().directoryNames[name:lower()] = true
  end
  M.inCombat = true
  for batch = 1, 24 do
    for i, key in ipairs(churn) do
      local row = H.Debug().scope.rows[key]
      H.Debug().scope.partners[key] = {
        name=row.name, heard=GetServerTime() - (((i + batch) % 2 == 0) and 0 or 1801), verified=true,
      }
    end
    ns.char.kills, ns.char.points = batch, batch
    H.Score(1, {name="Churn " .. alpha(batch), class="MAGE"}); M.advance(13)
    check(snapshotCount(H) <= 20, "snapshot cap under churn after finalize " .. batch)
    for i, key in ipairs(churn) do
      local row = H.Debug().scope.rows[key]
      H.Debug().scope.partners[key] = {
        name=row.name, heard=GetServerTime() - (((i + batch) % 2 == 1) and 0 or 1801), verified=true,
      }
    end
    M.fire("PLAYER_REGEN_ENABLED")
    check(snapshotCount(H) <= 20, "snapshot cap under churn after eligibility flip " .. batch)
  end
end

-- Above 100 eligible rows, every batch gets exactly the four-target cursor window. Interleaved row,
-- regen, and zone wakes neither add front-of-list fillers nor move the cursor. Full rotation covers
-- all 200 rows.
do
  local ns, H = fresh(); startWorld(H)
  local template = H.Parse(wire(ns, "0", {version="3.1.0"}))
  local names, keys = {}, {}
  for i = 1, 200 do
    local name = "Cover " .. alpha(i); names[i] = name
    local row = {}; for k, v in pairs(template) do row[k] = v end
    row.gen, row.seq = 1200 + i, 1
    local key = H.RowKey(name); keys[#keys + 1] = key
    H.MergeRow(key, name, row); H.Debug().directoryNames[name:lower()] = true
  end
  table.sort(keys)
  local covered, cursor = {}, 0
  for batch = 1, math.ceil(#keys / 4) + 1 do
    ns.char.kills, ns.char.points = batch, batch
    H.Score(1, {name="Coverage " .. batch, class="MAGE"}); M.advance(13)
    local selected, count = H.Debug().latestSnapshot.selected, 0
    for key in pairs(selected) do covered[key], count = true, count + 1 end
    local exact = count == 4
    for i = 1, 4 do exact = exact and selected[keys[(cursor + i - 1) % #keys + 1]] == true end
    cursor = (cursor + 4) % #keys
    check(exact and H.Debug().scope.meta.fanoutCursor == cursor,
      "fan-out cursor batch " .. batch .. " is exactly its four-target window")
    for i = 1, 3 do
      local name = names[(batch * 7 + i - 1) % #names + 1]
      local old = H.Debug().scope.rows[H.RowKey(name)]
      local copy = {}; for k, v in pairs(old) do copy[k] = v end
      copy.seq = old.seq + 1
      H.MergeRow(H.RowKey(name), name, copy)
    end
    M.fire("PLAYER_REGEN_ENABLED")
    M.fire("ZONE_CHANGED_NEW_AREA")
    local after, unchanged = 0, H.Debug().scope.meta.fanoutCursor == cursor
    for key in pairs(H.Debug().latestSnapshot.selected) do
      after = after + 1
      unchanged = unchanged and selected[key] == true
    end
    check(after == 4 and unchanged,
      "fan-out wakes batch " .. batch .. " do not fill or burn cursor positions")
    M.advance(70) -- drain this window so the next batch has no carried targets
  end
  local count = 0; for _ in pairs(covered) do count = count + 1 end
  eq(count, 200, "fan-out coverage: every rotating target is selected despite interleaved wakes")
end

-- Sustained kills and a long battleground lockdown retain only one bounded batch. Every target
-- selected by the newest frozen row receives it within the six-per-minute budget plus thirty seconds
-- measured from that row's finalization.
local function backlogCase(label, targets, kills, gap, lockdown)
  local ns, H = fresh(); startWorld(H)
  for i = 1, targets do
    local name = "Backlog " .. alpha(i)
    addRow(ns, H, name, {gen=2000+i, seq=1, kills=0, points=0, version="3.1.0"})
    H.Debug().directoryNames[name:lower()] = true
  end
  M.lockdown = lockdown
  local peak, oneBatch = 0, true
  local function sample()
    local count, batch = 0, nil
    for _, item in pairs(H.Debug().snapshots) do
      count = count + 1
      if batch and batch ~= item.batch then oneBatch = false else batch = item.batch end
    end
    peak = math.max(peak, count)
  end
  for k = 1, kills do
    ns.char.kills, ns.char.points = k, k
    H.Score(1, {name="Backlog Victim " .. alpha(k), class="MAGE"})
    for _ = 1, gap do M.advance(1); sample() end
  end
  local latest = H.Debug().latestSnapshot
  local selected, wanted = {}, 0
  for key in pairs(latest.selected) do
    local row = H.Debug().scope.rows[key]
    selected[row.name], wanted = true, wanted + 1
  end
  M.lockdown = false
  local received = {}
  local function collect()
    for _, sent in ipairs(M.sentAddon) do
      if selected[sent[5]] and not received[sent[5]] then
        local parsed = H.Parse(sent[2])
        if parsed and parsed.op == "N" and parsed.seq == ns.char.hunterSeq then received[sent[5]] = true end
      end
    end
  end
  collect()
  local deadline = latest.made + wanted / 6 * 60 + 30
  while GetServerTime() <= deadline do
    local have = 0; for _ in pairs(received) do have = have + 1 end
    if have == wanted then break end
    M.advance(1); sample(); collect()
  end
  local have = 0; for _ in pairs(received) do have = have + 1 end
  check(oneBatch and peak <= 20, label .. " keeps one batch and at most twenty queued targets")
  check(wanted > 0 and have == wanted and GetServerTime() <= deadline,
    label .. " delivers the newest frozen row to every selected peer within budget")
end
backlogCase("backlog world 30", 30, 30, 40, false)
backlogCase("backlog world 15", 15, 30, 40, false)
backlogCase("backlog lockdown 30", 30, 15, 60, true)
backlogCase("backlog lockdown 15", 15, 15, 60, true)

-- Feed modes, guild duplicate, sender/global caps, and the summary line.
do
  local ns, H = fresh(); startWorld(H)
  addRow(ns, H, "Feed Peer", {gen=100, seq=1, kills=5, points=5})
  H.Command("feed off")
  local before = #M.printed
  M.fire("CHAT_MSG_ADDON", "GodslayerG", news(ns, {seq=2, kills=6, points=6}), "WHISPER", "Feed Peer")
  eq(#M.printed, before, "feed off suppresses chat")
  check(not H.GuildDuplicate("Feed Peer", 6), "feed off does not mark an unpresented kill as a duplicate")
  local presented = ns.Hype.Ally("Feed Peer", 1)
  if presented then H.MarkPresented("Feed Peer", 6, "guild") end
  check(presented and #M.printed == before + 1,
    "feed-off news leaves the guild presentation path available")

  H.Command("feed everyone")
  addRow(ns, H, "Guild Peer", {gen=200, seq=1, kills=5, points=5})
  check(not H.GuildDuplicate("Guild Peer", 6), "guild duplicate check is initially clear")
  H.MarkPresented("Guild Peer", 6, "guild")
  before = #M.printed
  M.fire("CHAT_MSG_ADDON", "GodslayerG", news(ns, {gen=200, seq=2, kills=6, points=6}), "WHISPER", "Guild Peer")
  eq(#M.printed, before, "guild plus news duplicate is shown once")

  addRow(ns, H, "Cooldown Peer", {gen=300, seq=1, kills=5, points=5})
  M.fire("CHAT_MSG_ADDON", "GodslayerG", news(ns, {gen=300, seq=2, kills=6, points=6}), "WHISPER", "Cooldown Peer")
  local first = #M.printed
  M.fire("CHAT_MSG_ADDON", "GodslayerG", news(ns, {gen=300, seq=3, kills=7, points=7}), "WHISPER", "Cooldown Peer")
  eq(#M.printed, first, "per-sender thirty-second cooldown folds later news")
  M.advance(31)
  check(#M.printed > first and M.printed[#M.printed]:find("7 kills", 1, true),
    "per-sender folded news appears on next line")

  local base = #M.printed
  for i = 1, 7 do
    local name = "Cap " .. alpha(i)
    addRow(ns, H, name, {gen=400+i, seq=1, kills=5, points=5})
    M.fire("CHAT_MSG_ADDON", "GodslayerG", news(ns, {gen=400+i, seq=2, kills=6, points=6}), "WHISPER", name)
  end
  check(#M.printed - base <= 6, "global feed cap permits at most six immediate lines per minute")
  M.advance(61)
  check(M.printed[#M.printed]:find("more Slayers scored in the last minute", 1, true),
    "global feed cap emits one summary line")
end

-- A guild presentation that lands while a news line is waiting on the thirty-second sender cooldown
-- suppresses that delayed news line too.
do
  local ns, H = fresh(); startWorld(H)
  addRow(ns, H, "Race Peer", {gen=610, seq=1, kills=5, points=5})
  M.fire("CHAT_MSG_ADDON", "GodslayerG", news(ns, {gen=610, seq=2, kills=6, points=6}), "WHISPER", "Race Peer")
  M.fire("CHAT_MSG_ADDON", "GodslayerG", news(ns, {gen=610, seq=3, kills=7, points=7}), "WHISPER", "Race Peer")
  check(H.Debug().feedPending[H.RowKey("Race Peer")] ~= nil,
    "guild-news race: second line waits on the sender cooldown")
  H.MarkPresented("Race Peer", 7, "guild")
  local before = #M.printed
  M.advance(31)
  check(#M.printed == before and not H.Debug().feedPending[H.RowKey("Race Peer")],
    "guild-news race: delayed line rechecks and skips an intervening guild presentation")
end

-- Top-10 mode filters a low row, while opt-in banner and voice trigger only on a top entry.
do
  local ns, H = fresh(); startWorld(H)
  for i = 1, 11 do addRow(ns, H, "High " .. alpha(i), {gen=700+i, seq=1, kills=20+i, points=20+i}) end
  addRow(ns, H, "Low Slayer", {gen=800, seq=1, kills=1, points=1})
  H.Command("feed top10")
  local before = #M.printed
  M.fire("CHAT_MSG_ADDON", "GodslayerG", news(ns, {gen=800, seq=2, kills=2, points=2}), "WHISPER", "Low Slayer")
  eq(#M.printed, before, "feed top10 suppresses a row below tenth")

  local banners, voices = 0, 0
  ns.Stage.Banner = function() banners = banners + 1 end
  ns.Hype.SlayerVoice = function() voices = voices + 1 return true end
  H.Command("feed everyone"); H.Command("feed banner on"); H.Command("feed voice on")
  M.advance(31)
  M.fire("CHAT_MSG_ADDON", "GodslayerG", news(ns, {gen=800, seq=3, kills=100, points=100,
    batchKills=98, batchPoints=98}), "WHISPER", "Low Slayer")
  check(banners == 1 and voices == 1, "opt-in banner and voice fire when a Slayer enters number one")
end

M.realPrint(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
