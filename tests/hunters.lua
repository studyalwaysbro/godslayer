-- Focused phase-2 rules for the first-hand Hunters board.
return function(M, check, eq, ME)
  local FILES = { "Data.lua", "Pvp.lua", "Core.lua", "Voice.lua", "Sound.lua", "Stage.lua", "Clip.lua", "Hype.lua",
    "Fight.lua", "Aura.lua", "Ledger.lua", "Rank.lua", "Recap.lua", "Field.lua", "Flag.lua", "Control.lua",
    "Death.lua", "Threat.lua", "Comm.lua", "Hunters.lua", "Rival.lua", "Wheel.lua", "UI.lua" }

  local function alpha(n)
    local out = ""
    repeat
      local d = n % 26
      out = string.char(97 + d) .. out
      n = math.floor(n / 26)
    until n == 0
    return ("aaaa" .. out):sub(-4)
  end

  local function fresh(saved, config)
    config = config or {}
    M.now, M.wall, M.timers, M.units, M.guids, M.group = 1000, 1791400000, {}, {}, {}, {}
    M.frames, M.sentAddon, M.sentChat, M.printed = { UIParent, Minimap, GameTooltip }, {}, {}, {}
    M.settings, M.prefixes = { categories = {}, controls = {} }, {}
    M.inGuild, M.lockdown, M.inCombat, M.inInstance, M.groupSize, M.hk, M.dk = true, false, false, false, 0, 0, 0
    M.addonResult, M.syncOffline, M.addonRouter = 0, {}, nil
    M.region, M.ruleset, M.realmName, M.hardcore = config.region or "US", "pvp",
      config.realmName or "Classic Beta PvP", false
    M.channelJoined, M.channelSuspended, M.channelRefused = false, false, false
    M.channelRoster, M.channelRosterCount, M.selectedDisplay, M.selectedDisplays = {}, 0, nil, {}
    M.joinCalls, M.leaveCalls, M.joinArgs, M.secureCalls, M.chatFilters = 0, 0, nil, 0, {}
    M.weekUntil = nil
    GodslayerDB = saved
    GodslayerFrame, GodslayerWindow, GodslayerMinimapButton, GodslayerHypeBanner = nil, nil, nil, nil
    M.failTemplate = nil
    M.addUnit("player", { name = "Vesh Torchman", guid = ME, guild = "The True Torchmen", class = "MAGE",
      race = "Scourge", sex = 2, faction = "Horde", isMe = true })
    local ns = M.load("Godslayer", FILES)
    M.fire("ADDON_LOADED", "Godslayer")
    M.fire("PLAYER_LOGIN")
    return ns
  end

  local function wire(ns, nonce, values)
    values = values or {}
    local c, b = ns.char, ns.Hunters.Base36
    local fields = { "R", "1", nonce, b(values.gen or 100), b(values.seq or 1), b(values.made or GetServerTime()),
      b(values.week or c.weekStart or 0), b(values.complete == nil and 1 or values.complete), values.class or "WARRIOR",
      b(values.kills or 5), b(values.points or 9), b(values.kb or 2), b(values.orig or 1), b(values.kings or 0),
      b(values.rung or 4), b(values.wkKills or 2), b(values.wkPoints or 3), values.version or ns.VERSION }
    -- Keeping the harness able to finish on snap_r3 makes every new assertion report its own
    -- pre-fix failure instead of aborting at the first widened response.
    local own = ns.Hunters.Parse(ns.Hunters.OwnMessage("0") or "")
    if own and own.scope then fields[#fields + 1] = values.scope or "us/pvp" end
    return table.concat(fields, ";")
  end

  local function globalMessages()
    local rows = {}
    for _, m in ipairs(M.sentAddon) do if m[1] == "GodslayerG" then rows[#rows + 1] = m end end
    return rows
  end

  local function waitForQuery(target, limit)
    limit = limit or 180
    for _ = 1, limit do
      M.advance(1)
      for i = #M.sentAddon, 1, -1 do
        local m = M.sentAddon[i]
        if m[1] == "GodslayerG" and m[3] == "WHISPER" and m[5] == target and m[2]:match("^Q;1;") then return m end
      end
    end
  end

  local ns = fresh()
  local H = ns.Hunters
  check(GodslayerDB.hunters.enabled == true, "hunters: sharing defaults on")
  check(table.concat(M.printed, "\n"):find("name, class, kill counts, Olympus kills, rung", 1, true),
    "hunters: first-run chat notice names every shared field")
  check(table.concat(M.printed, "\n"):find("cannot erase copies already received", 1, true),
    "hunters: first-run notice states remote retention honestly")
  eq(H.DetectScope(), "us/horde/pvp", "hunters: scope is region/faction/ruleset")
  eq(H.CanonicalName("Solo"), "Solo", "hunters: one-segment name accepted")
  eq(H.CanonicalName("First-Surname"), "First Surname", "hunters: Forever hyphen form canonicalised")
  eq(H.CanonicalName("First Surname-ClassicBetaPvP"), "First Surname", "hunters: recognised realm suffix removed")
  eq(H.CanonicalName("First Last-CAMWOWUS2Realm6PvP"), "First Last",
    "hunters regression B2: spaced cross-backend sender suffix is removed")
  eq(H.CanonicalName("First-Last-CAMWOWUS2Realm6PvP"), "First Last",
    "hunters regression B2: hyphenated cross-backend sender suffix is removed")
  eq(H.CanonicalName("Solo-CAMWOWUS2Realm6PvP"), "Solo",
    "hunters regression B2: one-part name keeps no live backend suffix")
  check(H.CanonicalName("Latin \208\144lpha") == nil, "hunters: mixed-script lookalike rejected")
  check(H.CanonicalName("\240\159\152\128") == nil, "hunters: non-letter Unicode is rejected")
  eq(H.RowKey("\208\144\208\176\208\176\208\176"), H.RowKey("\208\176\208\176\208\176\208\176"),
    "hunters: Unicode uppercase and lowercase share one identity key")
  check(H.CanonicalName("Bad|Name") == nil and H.CanonicalName("Bad;Name") == nil, "hunters: wire delimiters rejected in names")
  check(H.CanonicalName(("A"):rep(50)) == nil, "hunters: names are byte bounded")

  M.realmName = "CAMWOWUS1Realm8PvP"
  eq(H.DetectScope(), "us/horde/pvp", "hunters regression B8: live PvP suffix determines ruleset")
  M.realmName = "CAMWOWUS1Realm8Mythic"
  eq(H.DetectScope(), "us/horde/mythic", "hunters regression B8: unknown live suffix remains an isolated ruleset")
  M.realmName = "CAMWOWUS1Realm8"
  eq(H.DetectScope(), "us/horde/standard", "hunters regression B8: empty live suffix is standard")
  M.hardcore, M.realmName = true, "CAMWOWUS1Realm8PvP"
  eq(H.DetectScope(), "us/horde/hardcore", "hunters regression B8: hardcore API takes precedence over label")
  M.hardcore, M.realmName = false, "Classic Beta PvP"

  -- Round-3 wire scope is explicit even though the game already isolates factions. Both request
  -- and response parsers reject a different ruleset, and the maximum accepted response remains
  -- below the add-on-message budget.
  do
    local scopeNS = fresh(nil, { region="abcdefghijk", realmName="CAMWOWUS1Realm8lmnopqrstuvw" })
    local scopeH, c = scopeNS.Hunters, scopeNS.char
    scopeNS.VERSION = "123456789012"
    M.wall, M.weekUntil = 999999999960, 604800 -- divisible by 60, so reset rounding stays in range
    scopeH.LocalChanged() -- advance the cached reset to the maximum wire timestamp first
    c.hunterGen, c.hunterSeq = 1000000000000, 1000000000000
    c.class, c.hunterClass = "WARRIOR", "WARRIOR"
    c.kills, c.points, c.kb, c.orig, c.kings = 10000000, 10000000, 10000000, 10000000, 10000000
    c.wkKills, c.wkPoints = 10000000, 10000000
    scopeNS.Rank.Level = function() return 14 end
    local longest = scopeH.OwnMessage("abcdefgh")
    local parsed = longest and scopeH.Parse(longest)
    check(longest and #longest <= scopeH.LIMITS.payload and parsed
      and parsed.scope == "abcdefghijk/lmnopqrstuvw",
      "hunters R2: nineteen-field R with longest accepted values stays within 240 bytes"
        .. " (bytes=" .. tostring(longest and #longest) .. ", parsed=" .. tostring(parsed ~= nil) .. ")")
    if longest then
      local fields = {}; for value in (longest .. ";"):gmatch("(.-);") do fields[#fields + 1] = value end
      eq(#fields, 19, "hunters R2: R appends scope as field nineteen")
    end

    M.fire("CHAT_MSG_ADDON", "GodslayerG", "Q;1;foreign1;abcdefghijk/standard", "WHISPER", "Foreign Asker")
    M.advance(3)
    eq(scopeH.Debug().responseScheduled, 0, "hunters R2: foreign-scope Q gets no answer")
    M.fire("CHAT_MSG_ADDON", "GodslayerG", "Q;1;matching;abcdefghijk/lmnopqrstuvw", "WHISPER", "Matching Asker")
    check(scopeH.Debug().responseScheduled == 1,
      "hunters R2: matching-scope Q is eligible for an answer")
  end

  do
    local foreignNS = fresh()
    local foreignH, foreignScope = foreignNS.Hunters, foreignNS.Hunters.Debug().scope
    foreignH.NoteCandidate("Foreign Hunter", "test")
    M.fire("PLAYER_ENTERING_WORLD")
    local query = waitForQuery("Foreign Hunter")
    local nonce = query and (query[2]:match("^Q;1;([0-9a-z]+);us/pvp$")
      or query[2]:match("^Q;1;([0-9a-z]+)$"))
    check(nonce ~= nil, "hunters R2: Q carries nonce and region/ruleset scope")
    if nonce then
      M.fire("CHAT_MSG_ADDON", "GodslayerG", wire(foreignNS, nonce, { scope="us/standard" }),
        "WHISPER", "Foreign Hunter")
    end
    local key, candidate = foreignH.RowKey("Foreign Hunter"), foreignScope.candidates[foreignH.RowKey("Foreign Hunter")]
    check(candidate and candidate.retired == true and candidate.foreign == true,
      "hunters R2: foreign R retires the pending candidate instead of backing off")
    check(key and foreignScope.rows[key] == nil and foreignScope.meta.pendingCount == 0,
      "hunters R2: foreign R is never merged and closes its pending Q")
  end

  do
    local expiryNS = fresh()
    local expiryH, expiryScope = expiryNS.Hunters, expiryNS.Hunters.Debug().scope
    expiryH.NoteCandidate("Expiry Hunter", "test")
    M.fire("PLAYER_ENTERING_WORLD")
    local query = waitForQuery("Expiry Hunter")
    local nonce = query and (query[2]:match("^Q;1;([0-9a-z]+);us/pvp$")
      or query[2]:match("^Q;1;([0-9a-z]+)$"))
    if nonce then M.fire("CHAT_MSG_ADDON", "GodslayerG", wire(expiryNS, nonce), "WHISPER", "Expiry Hunter") end
    local key = expiryH.RowKey("Expiry Hunter")
    check(key and expiryScope.partners[key] and expiryScope.partners[key].name == "Expiry Hunter",
      "hunters R3 setup: an exchange records a partner")
    M.now, M.wall = M.now + 1861, M.wall + 1861
    expiryH.Maintenance()
    check(key and expiryScope.partners[key] == nil,
      "hunters R3: a partner name expires after 31 minutes of silence")

    M.now, M.wall = M.now + 8 * 86400, M.wall + 8 * 86400
    expiryH.Maintenance()
    local function containsName(value, wanted, seen)
      if type(value) == "string" then return value:lower():find(wanted, 1, true) ~= nil end
      if type(value) ~= "table" then return false end
      seen = seen or {}; if seen[value] then return false end; seen[value] = true
      for k, v in pairs(value) do
        if containsName(k, wanted, seen) or containsName(v, wanted, seen) then return true end
      end
      return false
    end
    check(not containsName(GodslayerDB.hunters, "expiry hunter"),
      "hunters R3: no saved Hunters structure retains a name after seven-day expiry")
  end

  do
    local boundNS = fresh()
    local boundH = boundNS.Hunters
    local peak = 0
    for round = 1, 40 do
      for i = 1, 60 do
        local sender = "Long" .. alpha((round - 1) * 60 + i)
        boundH.handlers.CHAT_MSG_ADDON("GodslayerG", ("D;1;%08d"):format(i), "WHISPER", sender)
      end
      local count = 0; for _ in pairs(boundH.Debug().inboundBySender) do count = count + 1 end
      peak = math.max(peak, count)
      M.now = M.now + 61
      boundH.Maintenance()
    end
    local remaining = 0; for _ in pairs(boundH.Debug().inboundBySender) do remaining = remaining + 1 end
    check(peak <= 60 and remaining == 0,
      "hunters R8: long-session inbound sender windows are pruned once idle")
    check(boundH.Debug().issued == nil,
      "hunters R8: persistent serial issuance needs no unbounded session nonce set")
  end

  -- Repeated directory refreshes touch the same candidates. Runtime heaps stay bounded and no
  -- implementation heap is serialized into SavedVariables.
  do
    local oldScope = { expiry={{}}, rowExpiry={{}}, candidateExpiry={{}}, routeExpiry={{}},
      routes={ old={ name="Legacy Route" } }, meta={ routeCount=1 } }
    local heapNS = fresh({ hunters={ enabled=true, scopes={ ["eu/horde/standard"]=oldScope } } })
    local heapH, heapScope = heapNS.Hunters, heapNS.Hunters.Debug().scope
    for _ = 1, 24 do
      for i = 1, 250 do heapH.NoteCandidate("Heap " .. alpha(i), "directory") end
    end
    local heaps = heapH.Debug().heaps
    check(type(heaps) == "table", "hunters regression B3: expiry heaps are runtime-only")
    if heaps then
      local live = heapScope.meta.rowCount + heapScope.meta.candidateCount
        + heapScope.meta.pendingCount + heapScope.meta.completedCount
      check(#heaps.expiry <= 2 * live + 64 and #heaps.rowExpiry <= 2 * heapScope.meta.rowCount + 64
        and #heaps.candidateExpiry <= 2 * heapScope.meta.candidateCount + 64,
        "hunters regression B3: 24 refreshes keep every heap within two-times-live plus 64")
    end
    check(heapScope.expiry == nil and heapScope.rowExpiry == nil and heapScope.candidateExpiry == nil
      and heapScope.routeExpiry == nil, "hunters regression B3: SavedVariables contain no heap arrays")
    check(oldScope.expiry == nil and oldScope.rowExpiry == nil and oldScope.candidateExpiry == nil
      and oldScope.routeExpiry == nil, "hunters regression B3: login removes legacy heaps from inactive scopes")
    check(oldScope.routes == nil and oldScope.meta.routeCount == nil,
      "hunters R3: login removes write-only routes from every saved scope")
  end

  -- A recount may leave historical and weekly counters above newly lowered lifetime totals. Both
  -- direct Hunters R and guild schema-3 exports must clamp to a row peers accept.
  do
    local recountNS = fresh()
    local c, recountH = recountNS.char, recountNS.Hunters
    c.kills, c.points, c.uniques, c.kb, c.orig, c.kings = 2, 50, 2, 5, 4, 9
    c.wkKills, c.wkPoints = 7, 60
    local parsed = recountH.Parse(recountH.OwnMessage("abcdefgh"))
    check(parsed and parsed.kills == 2 and parsed.points == 10 and parsed.kb == 2 and parsed.orig == 2
      and parsed.kings == 2 and parsed.wkKills == 2 and parsed.wkPoints == 10,
      "hunters regression B4: recounted direct row is clamped to peer invariants")
    recountNS.Comm.MarkDirty()
    M.advance(6)
    local guildMessage
    for i = #M.sentAddon, 1, -1 do
      if M.sentAddon[i][1] == "Godslayer" and M.sentAddon[i][2]:match("^S;") then guildMessage = M.sentAddon[i][2] break end
    end
    if guildMessage then
      local fields = {}
      for value in (guildMessage .. ";"):gmatch("(.-);") do fields[#fields + 1] = value end
      fields[11] = "peer99"
      guildMessage = table.concat(fields, ";")
      M.fire("CHAT_MSG_ADDON", "Godslayer", guildMessage, "GUILD", "Recount Hunter")
    end
    local roster = GodslayerDB.roster["The True Torchmen"]
    local row = roster and roster["Recount Hunter"]
    check(row and row.kills == 2 and row.points == 10 and row.kings == 2 and row.wkKills == 2 and row.wkPoints == 10,
      "hunters regression B4: recounted guild schema-3 row is accepted by a peer")
  end

  ns = fresh(); H = ns.Hunters

  do
    local offNS = fresh({ hunters = { enabled = false, scopes = {} } })
    local offH = offNS.Hunters
    offH.NoteCandidate("Restart One", "saved")
    offH.NoteCandidate("Restart Two", "saved")
    offH.NoteCandidate("Restart Three", "saved")
    M.fire("PLAYER_ENTERING_WORLD")
    M.advance(500)
    eq(M.joinCalls, 0, "hunters regression B7: off-at-login starts no directory chain")
    offH.SetEnabled(true)
    M.advance(0)
    check(M.joinCalls == 1 and M.channelJoined,
      "hunters regression B7: enabling later starts the directory join chain")
    check(M.joinArgs and M.joinArgs[1] == "GodslayerHunters" and M.joinArgs[3] == 0 and M.joinArgs[4] == 0
      and M.secureCalls >= 1, "hunters regression S2: directory join is secure and hidden from chat windows")
    M.advance(721)
    check((offH.Debug().introductionRuns or 0) >= 1,
      "hunters regression B7: enabling later restarts introductions")
    offH.SetEnabled(false)
    check(M.leaveCalls == 1 and not M.channelJoined and M.secureCalls >= 2,
      "hunters regression S2: opt-out securely leaves the directory channel")
  end

  do
    local toggleNS = fresh({ hunters = { enabled = false, scopes = {} } })
    local toggleH = toggleNS.Hunters
    toggleH.NoteCandidate("Toggle One", "saved")
    toggleH.NoteCandidate("Toggle Two", "saved")
    toggleH.NoteCandidate("Toggle Three", "saved")
    M.fire("PLAYER_ENTERING_WORLD")
    toggleH.SetEnabled(true); toggleH.SetEnabled(false); toggleH.SetEnabled(true)
    M.advance(0)
    eq(toggleH.Debug().scope.meta.pendingCount, 1,
      "hunters regression B7: fast off-on-off-on leaves one discovery chain")
  end

  do
    -- Review follow-ups (Claude, 11-14): leave only when listed, leave at login after opting out
    -- elsewhere, a remembered notice dismissal, the options scope label and the startup footer.
    local leaveNS = fresh({ hunters = { enabled = true, scopes = {} } })
    M.leaveCalls = 0
    leaveNS.Hunters.SetEnabled(false)
    eq(M.leaveCalls, 0, "hunters review: opting out when not in the directory sends no leave")

    local loginNS = fresh({ hunters = { enabled = false, scopes = {} } })
    M.channelJoined, M.leaveCalls = true, 0 -- the game re-joined the saved channel for this character
    M.fire("PLAYER_ENTERING_WORLD")
    M.advance(59)
    check(M.channelJoined, "hunters review: no leave before the game has re-joined saved channels")
    M.advance(2)
    check(not M.channelJoined and M.leaveCalls == 1,
      "hunters review: a character still listed after opting out elsewhere leaves at login")
    check(loginNS.Hunters.Status().enabled == false, "hunters review: the login leave keeps sharing off")

    local noticeNS = fresh({ hunters = { enabled = true, scopes = {} } })
    local noticeH = noticeNS.Hunters
    check(noticeH.Status().notice == true, "hunters review: board notice shows until dismissed")
    noticeH.AcknowledgeBoardNotice()
    local kept = GodslayerDB
    noticeNS = fresh(kept); noticeH = noticeNS.Hunters
    check(noticeH.Status().notice == false, "hunters review: a dismissed board notice stays dismissed after reload")
    noticeH.SetEnabled(false); noticeH.SetEnabled(true)
    check(noticeH.Status().notice == true, "hunters review: opting back in shows the board notice once more")
    eq(noticeH.ScopeLabel("us/horde/pvp"), "US, Horde, PvP", "hunters review: options label reads the scope plainly")
    eq(noticeH.ScopeLabel("us/alliance/rppvp"), "US, Alliance, RP-PvP", "hunters review: options label names RP-PvP")
    eq(noticeH.ScopeLabel(nil), "starting", "hunters review: options label before the scope is known")

    noticeH.AcknowledgeBoardNotice()
    noticeNS.UI.Toggle()
    GodslayerFrame.tabs[3].__scripts.OnClick()
    GodslayerFrame.boardButtons[2].__scripts.OnClick()
    M.advance(0)
    check(GodslayerFrame.guildNote.__text:find("looking for Slayers", 1, true)
      and not GodslayerFrame.guildNote.__text:find("unavailable", 1, true),
      "hunters review: footer says the directory is starting, not unavailable, right after login")
    noticeNS.UI.Toggle()
  end

  do
    local groupNS = fresh()
    local groupH, groupScope = groupNS.Hunters, groupNS.Hunters.Debug().scope
    M.groupSize = 2
    M.addUnit("party1", { name="Private Groupmate", guid="Player-9-00000101", class="MAGE", faction="Horde" })
    M.inInstance = true
    M.fire("GROUP_ROSTER_UPDATE")
    check(groupScope.candidates[groupH.RowKey("Private Groupmate")] == nil,
      "hunters regression S5: group scans skip instances")
    M.inInstance = false
    M.fire("GROUP_ROSTER_UPDATE")
    check(groupScope.candidates[groupH.RowKey("Private Groupmate")] ~= nil,
      "hunters regression S5: an out-of-instance group scan still records a candidate")
    M.addUnit("party1", { name="Rapid Replacement", guid="Player-9-00000102", class="MAGE", faction="Horde" })
    M.fire("GROUP_ROSTER_UPDATE")
    check(groupScope.candidates[groupH.RowKey("Rapid Replacement")] == nil,
      "hunters regression S5: rapid group updates are throttled")
    M.advance(11); M.fire("GROUP_ROSTER_UPDATE")
    check(groupScope.candidates[groupH.RowKey("Rapid Replacement")] ~= nil,
      "hunters regression S5: throttled group scan resumes after its interval")
  end

  ns = fresh(); H = ns.Hunters

  eq(ns.char.weekComplete, 0, "hunters weekly: upgrade week starts partial")
  local week, sequence = ns.char.weekStart, ns.char.hunterSeq
  ns.char.kills, ns.char.points = 1, 1
  H.Score(1)
  eq(ns.char.wkKills, 1, "hunters weekly: Score advances weekly kills")
  eq(ns.char.wkPoints, 1, "hunters weekly: Score advances weekly points")
  check(ns.char.hunterSeq > sequence, "hunters ordering: score increments persistent sequence")
  M.weekUntil = 100001
  H.LocalChanged()
  eq(ns.char.weekStart, week, "hunters weekly: one-second reset jitter does not move cached week")
  M.wall = week + 604810
  M.weekUntil = 604790
  H.LocalChanged()
  check(ns.char.weekStart > week and ns.char.weekComplete == 1, "hunters weekly: first observed reset starts a complete week")
  eq(ns.char.wkKills, 0, "hunters weekly: reset clears kills")
  eq(ns.char.wkPoints, 0, "hunters weekly: reset clears points")

  do
    local recountNS = fresh()
    local function kill(guid, name, guild)
      M.addUnit("target", { name=name, guid=guid, guild=guild, class="WARRIOR", faction="Alliance" })
      M.fire("PLAYER_TARGET_CHANGED")
      M.fire("PARTY_KILL", ME, guid)
      M.advance(20)
    end
    for i = 1, 3 do kill("Player-9-WEEKX00" .. i, "Weekly X" .. i, "OLYMPUS") end
    for i = 1, 2 do kill("Player-9-WEEKO00" .. i, "Weekly Other" .. i, "Method") end
    eq(recountNS.char.wkKills, 5, "hunters R5 setup: five current-week kills are recorded")
    eq(recountNS.char.wkPoints, 17, "hunters R5 setup: current-week points use each guild's rate")
    SlashCmdList.GODSLAYER("ignore OLYMPUS")
    eq(recountNS.char.wkKills, 2, "hunters R5: ignoring guild X removes its three weekly kills")
    eq(recountNS.char.wkPoints, 2, "hunters R5: ignoring guild X leaves the two other weekly points")
    SlashCmdList.GODSLAYER("unignore OLYMPUS")
    eq(recountNS.char.wkKills, 5, "hunters R5: unignoring guild X restores all five weekly kills")
    eq(recountNS.char.wkPoints, 17, "hunters R5: unignoring guild X restores exact weekly points")

    recountNS = fresh()
    local repeatID = "Player-9-REPEAT15"
    for _ = 1, 15 do kill(repeatID, "Weekly Repeat", "Method") end
    local repeatVictim = recountNS.char.victims[repeatID]
    check(repeatVictim and repeatVictim.wk and repeatVictim.wk.kills == 15 and #repeatVictim.hist == 12,
      "hunters R5: per-victim week count remains exact beyond twelve retained kill details")
    SlashCmdList.GODSLAYER("ignore Method")
    eq(recountNS.char.wkKills, 0, "hunters R5: recount removes all fifteen same-victim weekly kills")
    SlashCmdList.GODSLAYER("unignore Method")
    eq(recountNS.char.wkKills, 15, "hunters R5: recount restores all fifteen same-victim weekly kills")

    recountNS = fresh()
    local c = recountNS.char
    c.victims["Player-9-LASTWEEK"] = { name="Old Week", guild="Old Week Guild", tier="any",
      kills=1, points=1, kb=0, first=M.wall - 604800, last=M.wall - 604800,
      wk={ start=c.weekStart - 604800, kills=1 } }
    recountNS.Recount()
    c.wkKills, c.wkPoints = 2, 2
    local partial = c.weekComplete
    SlashCmdList.GODSLAYER("ignore Old Week Guild")
    check(c.wkKills == 2 and c.wkPoints == 2,
      "hunters R5: a last-week victim does not move current-week counters")
    eq(c.weekComplete, partial, "hunters R5: recount preserves a partial week's completeness")
  end

  ns = fresh(); H = ns.Hunters

  M.fire("CHAT_MSG_ADDON", "GodslayerG", "Q;1;preworld;us/pvp", "WHISPER", "Early Hunter")
  M.advance(3)
  eq(#globalMessages(), 0, "hunters pacing: no global traffic leaves before entering the world")
  H.SetEnabled(false); H.SetEnabled(true) -- discard the deliberately pre-world response

  -- Directory discovery and direct owner authentication.
  M.channelRoster = { { name = "Peer Hunter", guid = "Player-9-00000001" } }
  M.channelRosterCount = 1
  H.NoteCandidate("Peer Hunter", "test")
  M.fire("PLAYER_ENTERING_WORLD")
  local query = waitForQuery("Peer Hunter")
  check(query ~= nil, "hunters discovery: candidate is queried by whisper")
  check(M.joinCalls == 1 and M.channelJoined, "hunters directory: one fixed-channel join chain begins")
  local scopedNonce = query and query[2]:match("^Q;1;([0-9a-z]+);us/pvp$")
  local nonce = scopedNonce or (query and query[2]:match("^Q;1;([0-9a-z]+)$"))
  check(scopedNonce and #scopedNonce == 8, "hunters protocol: Q carries an eight-character nonce and scope")

  local scope = H.Debug().scope
  local peerKey = H.RowKey("Peer Hunter")
  M.fire("CHAT_MSG_ADDON", "GodslayerG", wire(ns, "zzzzzzzz"), "WHISPER", "Peer Hunter")
  check(scope.rows[peerKey] == nil, "hunters trust: bad nonce cannot create a row")
  M.fire("CHAT_MSG_ADDON", "GodslayerG", wire(ns, "0"), "WHISPER", "Stranger One")
  check(scope.rows[H.RowKey("Stranger One")] == nil, "hunters trust: unsolicited R from a non-peer is rejected")
  M.fire("CHAT_MSG_ADDON", "GodslayerG", wire(ns, nonce) .. ";Other Owner", "WHISPER", "Peer Hunter")
  check(scope.rows[peerKey] == nil, "hunters trust: sender cannot append another row owner")
  M.fire("CHAT_MSG_ADDON", "GodslayerG", wire(ns, nonce), "WHISPER", "Peer Hunter")
  local peer = scope.rows[peerKey]
  check(peer and peer.name == "Peer Hunter" and peer.points == 9, "hunters trust: direct nonce-matched R creates only its sender's row")
  local confirmed = peer and peer.confirmed
  M.advance(2)
  M.fire("CHAT_MSG_ADDON", "GodslayerG", wire(ns, nonce), "WHISPER", "Peer Hunter")
  eq(scope.rows[peerKey].confirmed, confirmed, "hunters nonce: replayed completed nonce is rejected")

  H.NoteCandidate("Private Groupmate", "group", "Player-9-00000099")
  M.fire("CHAT_MSG_ADDON", "GodslayerG", "D;1;intro001", "WHISPER", "Peer Hunter")
  local introduction
  for _, item in ipairs(H.Debug().queue) do
    if type(item.payload) == "string" and item.payload:match("^I;1;intro001;") then introduction = item.payload break end
  end
  check(introduction and not introduction:find("Private Groupmate", 1, true),
    "hunters regression S6: introductions exclude unverified group candidates")
  for i = #H.Debug().queue, 1, -1 do
    if type(H.Debug().queue[i].payload) == "string" and H.Debug().queue[i].payload:match("^I;1;intro001;") then
      table.remove(H.Debug().queue, i)
    end
  end

  M.fire("CHAT_MSG_ADDON", "GodslayerG", wire(ns, "0", { gen=100, seq=1, points=10 }), "WHISPER", "Peer Hunter")
  eq(scope.rows[peerKey].points, 9, "hunters ordering: equal tuple with different statistics is rejected")
  M.fire("CHAT_MSG_ADDON", "GodslayerG", wire(ns, "0", { gen=100, seq=2, kills=4, points=8 }), "WHISPER", "Peer Hunter")
  eq(scope.rows[peerKey].points, 9, "hunters ordering: same-generation lifetime regression is rejected")
  M.fire("CHAT_MSG_ADDON", "GodslayerG", wire(ns, "0", { gen=101, seq=0, kills=1, points=1, kb=0, orig=0, wkKills=0, wkPoints=0 }), "WHISPER", "Peer Hunter")
  eq(scope.rows[peerKey].points, 1, "hunters ordering: higher generation permits explicit reset")
  H.NoteCandidate("Peer Hunter", "directory", "Player-9-00000001")
  H.NoteCandidate("Peer Hunter", "directory", "Player-9-00000002")
  check(scope.rows[peerKey] == nil, "hunters identity: changed server-observed GUID discards the stale row")
  M.fire("CHAT_MSG_ADDON", "GodslayerG", wire(ns, "0", { gen=102, seq=0 }), "WHISPER", "Peer Hunter")
  check(scope.rows[peerKey] == nil, "hunters identity: GUID change requires a fresh nonce-matched response")

  local beforeRows = scope.meta.rowCount
  local attacks = {
    ("X"):rep(241), "R;1;0", "R;2;0;1;1", wire(ns, "BADNONCE"),
    "I;1;abcdefgh;Good Name|junk;R;1", "I;1;abcdefgh;" .. table.concat({"A A","B B","C C","D D","E E","F F","G G","H H","I I"}, "|"),
  }
  for _, text in ipairs(attacks) do M.fire("CHAT_MSG_ADDON", "GodslayerG", text, "WHISPER", "Attack Sender") end
  eq(scope.meta.rowCount, beforeRows, "hunters parser: oversize, bad-count, bad-version, bad-nonce and stuffed-introduction attacks create no row")

  M.groupSize = 2
  M.addUnit("party1", { name="Group Hunter", guid="Player-9-00000003", class="MAGE", faction="Horde" })
  M.fire("GROUP_ROSTER_UPDATE")
  local grouped = scope.candidates[H.RowKey("Group Hunter")]
  check(grouped and grouped.source == "group" and grouped.guid == "Player-9-00000003",
    "hunters discovery: a locally observed group member becomes a GUID-attributed candidate")
  M.groupSize, M.units.party1 = 0, nil

  -- Inbound response floods are bounded, and the one global sender observes every pacing rule.
  M.sentAddon = {}
  for i = 1, 12 do M.fire("CHAT_MSG_ADDON", "GodslayerG", ("Q;1;%08d;us/pvp"):format(i), "WHISPER", "Asker " .. alpha(i)) end
  M.advance(70)
  local sent = globalMessages()
  local responseTimes = {}
  for _, m in ipairs(sent) do
    check(m[3] == "WHISPER", "hunters transport: addon data is never sent on a channel")
    if m[2]:match("^R;1;") then responseTimes[#responseTimes + 1] = m[4] end
  end
  for i, at in ipairs(responseTimes) do
    local responses = 0
    for j = i, #responseTimes do if responseTimes[j] - at < 60 then responses = responses + 1 end end
    check(responses <= 10, "hunters pacing: owed query responses use the hard ten-per-minute ceiling")
  end
  for i = 2, #sent do check(sent[i][4] - sent[i-1][4] >= 1.999, "hunters pacing: global minimum spacing is two seconds") end
  for i = 1, #sent do
    local minute, burst = 0, 0
    for j = i, #sent do
      if sent[j][4] - sent[i][4] < 60 then minute = minute + 1 end
      if sent[j][4] - sent[i][4] < 10 then burst = burst + 1 end
    end
    check(minute <= 10, "hunters pacing: hard ten-per-minute ceiling")
    check(burst <= 3, "hunters pacing: three-per-ten-second burst ceiling")
  end
  check(H.Debug().responseScheduled <= 8, "hunters inbound: response queue cap holds")

  -- Result 3 pauses exponentially; result 11 retains only reply/push work; the synchronous
  -- Forever offline line is correlated while SendAddonMessage is still on its call stack.
  H.NoteCandidate("Offline Hunter", "test")
  M.syncOffline["Offline Hunter"] = true
  local offlineQ = waitForQuery("Offline Hunter", 1900)
  check(offlineQ ~= nil, "hunters result 12: offline candidate was attempted")
  local offline = scope.candidates[H.RowKey("Offline Hunter")]
  check(offline and (offline.fail or 0) >= 1, "hunters result 12: synchronous offline line applies target backoff")
  M.syncOffline["Offline Hunter"] = nil

  H.NoteCandidate("Delayed Hunter", "test")
  local delayedQ = waitForQuery("Delayed Hunter", 1900)
  check(delayedQ ~= nil, "hunters regression B1 setup: delayed-offline candidate was whispered")
  if delayedQ then
    local untilHundred = 100 - (M.now - delayedQ[4])
    if untilHundred > 0 then M.advance(untilHundred) end
  end
  local delayed = scope.candidates[H.RowKey("Delayed Hunter")]
  local failsBeforeFilter = delayed and delayed.fail or 0
  eq(M.applyChatFilters("CHAT_MSG_SYSTEM", "No player named 'Delayed-Hunter' is currently playing.", 2), 2,
    "hunters regression B1: remembered alias offline line is hidden in every chat frame")
  eq(delayed and delayed.fail or 0, failsBeforeFilter + 1,
    "hunters regression B1: two chat frames apply asynchronous backoff once")
  eq(M.applyChatFilters("CHAT_MSG_SYSTEM", "No player named 'Personal Whisper' is currently playing.", 1), 0,
    "hunters regression B1: unrelated player whisper error remains visible")
  M.inInstance = true
  eq(M.applyChatFilters("CHAT_MSG_SYSTEM", "No player named 'Delayed' is currently playing.", 1), 0,
    "hunters regression B1: offline filters leave instance chat alone")
  M.inInstance = false
  local secretOK, secretHidden = pcall(M.applyChatFilters, "CHAT_MSG_SYSTEM", M.secret(), 1)
  check(secretOK and secretHidden == 0, "hunters regression B1: offline filter never reads a secret line")
  if delayedQ then
    local untilExpired = 121 - (M.now - delayedQ[4])
    if untilExpired > 0 then M.advance(untilExpired) end
  end
  eq(M.applyChatFilters("CHAT_MSG_SYSTEM", "No player named 'Delayed Hunter' is currently playing.", 1), 0,
    "hunters regression B1: remembered offline target expires after 120 seconds")

  eq(M.applyChatFilters("CHAT_MSG_CHANNEL_NOTICE", "YOU_JOINED", 1, nil, nil, nil, "GodslayerHunters"), 1,
    "hunters regression S3: own directory channel notice is hidden")
  eq(M.applyChatFilters("CHAT_MSG_CHANNEL_NOTICE_USER", "SOMEONE_JOINED", 1, nil, nil, nil, "GodslayerHunters"), 1,
    "hunters regression S3: own directory user notice is hidden")
  eq(M.applyChatFilters("CHAT_MSG_CHANNEL_NOTICE", "YOU_JOINED", 1, nil, nil, nil, "General"), 0,
    "hunters regression S3: unrelated channel notice remains visible")

  M.addonResult = 3
  M.fire("CHAT_MSG_ADDON", "GodslayerG", "Q;1;throttle;us/pvp", "WHISPER", "Throttle Peer")
  M.advance(4)
  check(H.Debug().pauseUntil > M.now, "hunters result 3: whole queue pauses after throttling")
  M.addonResult = 0
  local pause = H.Debug().pauseUntil - M.now
  if pause > 0 then M.advance(pause + 1) end
  M.addonResult = 11
  M.fire("CHAT_MSG_ADDON", "GodslayerG", "Q;1;lockdown;us/pvp", "WHISPER", "Lockdown Peer")
  M.advance(4)
  local retainedDiscovery = false
  for _, item in ipairs(H.Debug().queue) do if item.kind == "Q" or item.kind == "D" then retainedDiscovery = true end end
  check(retainedDiscovery, "hunters result 11: discovery work is retained without candidate failure")
  M.addonResult = 0

  -- Caps are exercised through the same insertion paths used by directory and direct replies.
  for i = 1, 360 do H.NoteCandidate("Candidate " .. alpha(i), "cap") end
  eq(scope.meta.candidateCount, H.LIMITS.candidates, "hunters storage: candidate table cap holds")
  local template = H.Parse(wire(ns, "0", { gen=300, seq=1 }))
  for i = 1, H.LIMITS.rows + 80 do
    local name = "Hunter " .. alpha(i)
    local row = {}; for k,v in pairs(template) do row[k] = v end
    row.gen, row.seq, row.kills, row.points = 300 + i, 0, i % 20, i % 20
    row.kb, row.orig, row.kings, row.wkKills, row.wkPoints = 0, 0, 0, 0, 0
    H.MergeRow(H.RowKey(name), name, row)
  end
  eq(scope.meta.rowCount, H.LIMITS.rows, "hunters storage: confirmed-row cap holds")
  check(scope.meta.pendingCount <= H.LIMITS.pending and scope.meta.completedCount <= H.LIMITS.completed,
    "hunters storage: pending and completed-nonce caps hold")

  local savedRows = scope.rows
  scope.rows = {}
  for i = 1, 201 do
    scope.rows["old" .. i] = { name="Old " .. alpha(i), confirmed=GetServerTime(), week=ns.char.weekStart,
      complete=1, class="WARRIOR", kills=1, points=1, kb=0, orig=0, kings=0, rung=0, wkKills=1, wkPoints=1 }
  end
  H.Board("week")
  M.runNextTimer()
  local mutationBuild = H.Debug().board.week
  local removedKey, removedRow = mutationBuild and mutationBuild.cursor, nil
  if removedKey then removedRow, scope.rows[removedKey] = scope.rows[removedKey], nil end
  for i = 1, 700 do
    scope.rows["new" .. i] = { name="Mutation " .. alpha(i), confirmed=GetServerTime(), week=ns.char.weekStart,
      complete=1, class="WARRIOR", kills=1, points=1, kb=0, orig=0, kings=0, rung=0, wkKills=1, wkPoints=1 }
  end
  local mutationOK = pcall(M.advance, 0)
  check(mutationOK and mutationBuild and mutationBuild.building == false,
    "hunters regression S1: removed cursor plus 700 inserted keys cannot freeze board collection")
  scope.rows = savedRows

  local snapshot, building = H.Board("lifetime")
  check(snapshot == nil and building, "hunters board: first open reports a cooperative build")
  M.advance(0)
  snapshot, building = H.Board("lifetime")
  check(snapshot and not building and #snapshot > 100, "hunters board: cooperative merge publishes a large snapshot")
  check((H.Debug().maxSortComparisons or 0) <= 500, "hunters board: no frame exceeds 500 sort comparisons")
  check((H.Debug().maxSortWork or 0) <= 500, "hunters board: collection, merge and publish work is sliced per frame")
  local oldSnapshot = snapshot
  local changed = {}; for k,v in pairs(template) do changed[k] = v end
  changed.gen, changed.kills, changed.points = 999999, 2, 2
  H.MergeRow(H.RowKey("Newest Hunter"), "Newest Hunter", changed)
  local visible, rebuilding = H.Board("lifetime")
  check(visible == oldSnapshot and rebuilding, "hunters board: previous snapshot remains visible during rebuild")
  M.advance(0)
  check(H.Board("lifetime") ~= oldSnapshot, "hunters board: rebuild publishes after journal replay")

  local rowsBeforeExpiry = scope.meta.rowCount
  M.wall = M.wall + 8 * 86400
  H.Maintenance()
  check(H.Debug().lastMaintenanceCount <= 50 and scope.meta.rowCount >= rowsBeforeExpiry - 50,
    "hunters expiry: maintenance is capped at fifty heap entries")

  -- Guild schema 3 ordering does not sacrifice the legacy lifetime board.
  local b, made, weekNow = H.Base36, H.Base36(GetServerTime()), H.Base36(ns.char.weekStart or 0)
  local function guild(gen, seq, kills, points)
    return table.concat({ "S","1",kills,points,kills,0,0,"WARRIOR",ns.VERSION,0,"peer01",4,
      "3",b(gen),b(seq),made,weekNow,"1",b(1),b(1) }, ";")
  end
  M.fire("CHAT_MSG_ADDON", "Godslayer", guild(10, 2, 5, 5), "GUILD", "Schema Hunter")
  M.fire("CHAT_MSG_ADDON", "Godslayer", guild(10, 1, 9, 9), "GUILD", "Schema Hunter")
  local roster = GodslayerDB.roster["The True Torchmen"]["Schema Hunter"]
  check(roster and roster.kills == 5 and roster.seq == 2, "hunters guild: stale schema-3 laptop overwrite is rejected")
  M.fire("CHAT_MSG_ADDON", "Godslayer", "S;1;12;12;12;0;0;WARRIOR;1.0.0;0;old001;4", "GUILD", "Schema Hunter")
  eq(roster.kills, 5, "hunters guild: legacy row cannot overwrite an ordered schema-3 row")
  M.fire("CHAT_MSG_ADDON", "Godslayer", "S;1;3;3;3;0;0;MAGE;1.0.0;0;old002;2", "GUILD", "Legacy Hunter")
  local legacySeen
  for _, row in ipairs(ns.Comm.Leaderboard()) do if row.name == "Legacy Hunter" then legacySeen = true end end
  check(legacySeen, "hunters guild: twelve-field legacy row still ranks")
  local future = table.concat({ "S","1",7,7,7,0,0,"PRIEST",ns.VERSION,0,"peer02",4,
    "4",b(30),b(3),made,weekNow,"1",b(2),b(2),"x" }, ";")
  M.fire("CHAT_MSG_ADDON", "Godslayer", future, "GUILD", "Future Hunter")
  local futureRow = GodslayerDB.roster["The True Torchmen"]["Future Hunter"]
  check(futureRow and futureRow.kills == 7 and futureRow.gen == 30 and futureRow.seq == 3,
    "hunters review: a later schema that only appends still updates the guild board")
  M.fire("CHAT_MSG_ADDON", "Godslayer", table.concat({ "S","1",8,8,8,0,0,"PRIEST",ns.VERSION,0,"peer02",4,
    "3",b(30),b(4),made,weekNow,"1" }, ";"), "GUILD", "Future Hunter")
  eq(GodslayerDB.roster["The True Torchmen"]["Future Hunter"].kills, 7,
    "hunters review: a cut-short schema tail is still refused")

  -- UI switch, exact disclosure/footer, options checkbox and slash opt-out.
  ns.UI.Toggle()
  GodslayerFrame.tabs[3].__scripts.OnClick()
  GodslayerFrame.boardButtons[2].__scripts.OnClick()
  M.advance(0)
  local boardNotice = GodslayerFrame.boardNotice
  check(boardNotice and boardNotice:IsShown() and boardNotice.__text == H.NOTICE and boardNotice.__wordWrap == true,
    "hunters regression B5: full first-run notice stays wrapped on the board")
  ns.UI.Refresh()
  check(boardNotice and boardNotice:IsShown(),
    "hunters regression B5: refresh does not acknowledge the first-run notice")
  if GodslayerFrame.dismissBoardNotice and GodslayerFrame.dismissBoardNotice.__scripts.OnClick then
    GodslayerFrame.dismissBoardNotice.__scripts.OnClick()
  end
  check(GodslayerFrame.empty.__text ~= "Building list...", "hunters UI: cooperative build refreshes the open board when it publishes")
  ns.UI.Refresh()
  local shownRows = 0
  for _, row in ipairs(GodslayerFrame.rows) do if row:IsShown() then shownRows = shownRows + 1 end end
  eq(shownRows, 11, "hunters regression B5: leaderboard tab shows eleven rows")
  eq(GodslayerFrame.list.__height, 220, "hunters regression B5: leaderboard list ends at the safe geometry")
  check(GodslayerFrame.guildNote.__width and GodslayerFrame.guildNote.__width <= 380
    and GodslayerFrame.guildNote.__wordWrap == false,
    "hunters regression B5: one-line footer is width-bounded left of the count")
  check(GodslayerFrame.boardHeader.__text:find("confirmed by your client. Scores are self-reported.", 1, true),
    "hunters UI: header is explicit about local confirmation and self-reporting")
  check(GodslayerFrame.guildNote.__text:find("candidates", 1, true), "hunters UI: footer reports discovery coverage")
  local category = M.settings.categories[#M.settings.categories]
  local share
  for _, setting in ipairs(category.settings or {}) do if setting.variable == "GODSLAYER_HUNTERS_SHARE" then share = setting end end
  check(share ~= nil, "hunters options: share checkbox registered")
  check(category.layout and category.layout.initializers[1]
    and category.layout.initializers[1].text == "Slayers board: US, Horde, PvP",
    "hunters options: header names the scope plainly and leaves on/off to the checkbox")
  local hunterSource = assert(io.open("Godslayer/Hunters.lua")):read("*a")
  check(not hunterSource:find("\226\128\148", 1, true) and not hunterSource:find("\226\128\147", 1, true),
    "hunters regression B6: player-facing Hunters copy contains no em or en dash")
  share.set(false)
  check(GodslayerDB.hunters.enabled == false and #H.Debug().queue == 0 and not M.channelJoined,
    "hunters opt-out: checkbox stops traffic and leaves the directory immediately")
  local sentAtOff = #globalMessages()
  M.fire("CHAT_MSG_ADDON", "GodslayerG", "Q;1;afteroff;us/pvp", "WHISPER", "After Off")
  M.advance(70)
  eq(#globalMessages(), sentAtOff, "hunters opt-out: inbound traffic is ignored after opt-out")
  SlashCmdList.GODSLAYER("hunters on")
  M.advance(0)
  check(GodslayerDB.hunters.enabled == true, "hunters slash: on restores sharing")
  check(M.channelJoined, "hunters regression S2: opt-in rejoins the directory channel")
  SlashCmdList.GODSLAYER("hunters status")
  check(M.printed[#M.printed]:find("Slayers on", 1, true), "hunters slash alias: status reports live state")

  -- Saved rows and local ordering survive reload, while session-bound pending nonces do not.
  local saved, generation, seq = GodslayerDB, ns.char.hunterGen, ns.char.hunterSeq
  local nonceSerial = H.Debug().scope.meta.nonceSerial
  ns = fresh(saved); H = ns.Hunters; scope = H.Debug().scope
  eq(ns.char.hunterGen, generation, "hunters reload: generation survives SavedVariables restore")
  eq(ns.char.hunterSeq, seq, "hunters reload: sequence survives SavedVariables restore")
  eq(scope.meta.nonceSerial, nonceSerial, "hunters reload: nonce issuance never rewinds")
  eq(scope.meta.pendingCount, 0, "hunters reload: session pending requests are discarded")
  check(scope.meta.rowCount <= H.LIMITS.rows and scope.meta.candidateCount <= H.LIMITS.candidates,
    "hunters reload: saved table caps still hold")

  -- Refused and suspended channel states are visible and never provoke channel churn.
  ns = fresh(); H = ns.Hunters
  M.channelRefused = true
  M.fire("PLAYER_ENTERING_WORLD")
  M.advance(130)
  check(H.Status().directory == "not joined", "hunters directory: refused channel is visibly not joined")
  check(M.joinCalls <= 2, "hunters directory: refusal follows the bounded join schedule")

  ns = fresh(); H = ns.Hunters
  M.channelJoined, M.channelSuspended = true, true
  M.fire("PLAYER_ENTERING_WORLD")
  M.advance(130)
  check(H.Status().directory == "suspended", "hunters directory: suspended channel is visibly degraded")

  ns = fresh(); H = ns.Hunters
  M.channelJoined, M.channelRosterCount = true, 0
  M.fire("PLAYER_ENTERING_WORLD")
  M.advance(150)
  check(#M.selectedDisplays <= 4 and H.Status().directory == "waiting for roster",
    "hunters regression S4: empty directory fetch stops after the 3- and 8-second polls")

  ns = fresh(); H = ns.Hunters
  M.channelJoined, M.channelRosterCount = true, 0
  M.fire("PLAYER_ENTERING_WORLD")
  H.RefreshDirectory()
  M.advance(9)
  eq(#M.selectedDisplays, 0, "hunters regression S4: directory fetch waits ten seconds after entering world")
  M.advance(2)
  check(#M.selectedDisplays > 0, "hunters regression S4: deferred directory fetch resumes after zone guard")

  ns = fresh(); H = ns.Hunters
  M.channelJoined, M.channelRosterCount = true, 0
  ChannelFrame = M.newFrame("Frame", "ChannelFrame"); ChannelFrame:Show()
  M.selectedDisplay = nil
  M.advance(11)
  H.RefreshDirectory()
  eq(M.selectedDisplay, nil, "hunters directory: open channel window prevents display-channel selection")
  ChannelFrame = nil
end
