-- Hunters multi-client network simulator: lua tests/hunters_sim.lua [clients] [seconds] [seed]
-- Exercises the real Hunters module in isolated Lua environments with latency, drops, offline
-- targets, result codes 3/11/12, synchronous offline lines, reloads, combat/instance/lockdown
-- suspension, and working/refused/suspended channel directories.

local CLIENTS, DURATION, SEED = tonumber(arg[1]) or 220, tonumber(arg[2]) or 3200, tonumber(arg[3]) or 7301
assert(CLIENTS >= 200, "the Hunters simulator requires at least 200 clients")
math.randomseed(SEED)

local realPrint, NOW, WALL = print, 0, 1800000000
local failures, events, serial = 0, {}, 0
local stats = { attempts=0, deliveries=0, drops=0, offline=0, throttles=0, lockdown=0, reloads=0, attacks=0,
  crossSpellings={}, crossScopeQueries=0, crossScopeAnswers=0, newsSends=0, legacyPushes=0,
  newsDeliveries=0, liveNewsLatencyMax=0, staleNews=0, maxQueue=0, owed={}, responseLatencyMax=0,
  probes=0, hunts=0 }

local function fail(message)
  failures = failures + 1
  if failures <= 30 then realPrint("FAIL: " .. message) end
end

local function less(a,b) return a.at < b.at or (a.at == b.at and a.serial < b.serial) end
local function schedule(at, fn)
  serial = serial + 1
  local e, i = { at=at, fn=fn, serial=serial }, #events + 1
  events[i] = e
  while i > 1 do
    local p = math.floor(i/2)
    if not less(e, events[p]) then break end
    events[i], events[p], i = events[p], e, p
  end
end
local function pop()
  local first, last = events[1], events[#events]
  events[#events] = nil
  if #events > 0 then
    events[1] = last
    local i = 1
    while true do
      local a,b = i*2, i*2+1
      if a > #events then break end
      local child = b <= #events and less(events[b],events[a]) and b or a
      if not less(events[child],events[i]) then break end
      events[i],events[child],i = events[child],events[i],child
    end
  end
  return first
end

local function alpha(n)
  local out = ""
  repeat local d=n%26; out=string.char(97+d)..out; n=math.floor(n/26) until n==0
  return ("aaaa"..out):sub(-4)
end

local clients, byName = {}, {}
for i=1,CLIENTS do
  local one = i > math.floor(CLIENTS/2)
  local name = one and ("Solo"..alpha(i)) or ("Hunter"..alpha(i).." Clan"..alpha(i%71+1))
  local backend = i%2==0 and "A" or "B"
  local ruleset = i > CLIENTS - 20 and "standard" or "pvp"
  local c = { id=i, name=name, backend=backend, ruleset=ruleset, version=i%3==0 and "3.0.0" or "3.1.0",
    realmLabel=(backend=="A" and "CAMWOWUS1Realm8" or "CAMWOWUS2Realm6")
      .. (ruleset=="pvp" and "PvP" or "Standard"),
    directory=i<=CLIENTS-20 and "working"
    or i<=CLIENTS-10 and "refused" or "suspended", generation=0, outbound={}, received={}, char={
      class=({"DRUID","HUNTER","MAGE","PALADIN","PRIEST","ROGUE","SHAMAN","WARLOCK","WARRIOR"})[(i-1)%9+1], kills=10+i%90, points=10+i%90,
      kb=i%9, orig=i%7, kings=i%13==0 and 1 or 0, wkKills=i%6, wkPoints=i%6,
      weekStart=1799884800, weekComplete=1, hunterGen=WALL+i, hunterSeq=i,
    }, db={ hunters={ version=1, enabled=true, scopes={} } } }
  clients[i], byName[name] = c, c
end

local source = assert(io.open("Godslayer/Hunters.lua")):read("*a")

local function isCombat(c, at) return c.id%15==0 and at>=900 and at<965 end
local function isInstance(c, at) return c.id%20==0 and at>=500 and at<655 end
local function isLockdown(c, at) return c.id%17==0 and at>=1200 and at<1265 end

local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local result = { pcall(fn, ...) }
  if not result[1] then return nil end
  return unpack(result,2)
end

local loadClient
local function route(sender, prefix, payload, channel, target)
  stats.attempts = stats.attempts + 1
  sender.sendSerial = (sender.sendSerial or 0) + 1
  sender.outbound[#sender.outbound+1] = { at=NOW, prefix=prefix, payload=payload, channel=channel, target=target }
  local op, nonce = payload:match("^([A-Z]);1;([^;]+)")
  if op=="N" then
    stats.newsSends=stats.newsSends+1
    local parsed=sender.ns.Hunters.Parse(payload)
    local age=parsed and (WALL+math.floor(NOW)-parsed.made) or math.huge
    if age<=300 then
      if sender.lastKillAt then stats.liveNewsLatencyMax=math.max(stats.liveNewsLatencyMax,NOW-sender.lastKillAt) end
    else stats.staleNews=stats.staleNews+1 end
  elseif op=="R" and nonce=="0" and sender.lastKillAt then
    -- Current verified 3.0 partners receive the legacy board form for a hunt.
    stats.legacyPushes=stats.legacyPushes+1
  end
  local debug=sender.ns and sender.ns.Hunters.Debug()
  if debug then
    local snapshots=0; for _ in pairs(debug.snapshots or {}) do snapshots=snapshots+1 end
    stats.maxQueue=math.max(stats.maxQueue,#debug.queue+snapshots)
  end
  if channel ~= "WHISPER" then fail(sender.name.." sent addon data on "..tostring(channel)) end
  if #payload > 240 then fail(sender.name.." sent oversize payload") end
  local recipient = byName[target]
  if recipient and sender.ruleset ~= recipient.ruleset and payload:match("^Q;1;") then
    stats.crossScopeQueries = stats.crossScopeQueries + 1
  elseif recipient and sender.ruleset ~= recipient.ruleset and payload:match("^R;1;") then
    stats.crossScopeAnswers = stats.crossScopeAnswers + 1
    fail(sender.name.." answered a query across rulesets for "..recipient.name)
  end
  if not recipient or recipient.id > CLIENTS-5 then
    stats.offline = stats.offline + 1
    sender.ns.Hunters.handlers.CHAT_MSG_SYSTEM("No player named '"..target.."' is currently playing.")
    return 12
  end
  if sender.sendSerial % 97 == 0 then stats.throttles=stats.throttles+1; return 3 end
  if sender.sendSerial % 131 == 0 then stats.lockdown=stats.lockdown+1; return 11 end
  if op=="R" and nonce and nonce~="0" then
    local key=nonce.."|"..target.."|"..sender.name
    local obligation=stats.owed[key]
    if obligation then
      local due
      for dedupe,rec in pairs((debug and debug.owedResponses) or {}) do
        if dedupe:sub(-9)==":"..nonce and type(rec)=="table" then due=rec.due; break end
      end
      local delay=due and NOW-due or math.huge
      if delay~=math.huge then stats.responseLatencyMax=math.max(stats.responseLatencyMax,delay) end
      if delay>2.001 then stats.responseStarvation=(stats.responseStarvation or 0)+1 end
      stats.owed[key]=nil
      sender.probeActive=nil
    end
  end
  if sender.sendSerial % 19 == 0 then stats.drops=stats.drops+1; return 0 end
  -- While a measured response is owed, model unrelated inbound Q traffic as one of the simulator's
  -- normal packet drops. That keeps the probe about the reserved send slot rather than a second
  -- response racing it for the same single slot.
  if recipient.probeActive and payload:match("^Q;1;") then stats.drops=stats.drops+1; return 0 end
  local delay = 0.05 + (stats.attempts % 20) * 0.02
  local senderWire = sender.name
  if recipient.backend ~= sender.backend and sender.name:find(" ",1,true) then
    stats.crossSerial = (stats.crossSerial or 0) + 1
    local form = (stats.crossSerial - 1) % 3 + 1
    if form == 2 then senderWire = sender.name .. "-" .. sender.realmLabel
    elseif form == 3 then senderWire = sender.name:gsub(" ", "-", 1) .. "-" .. sender.realmLabel end
    stats.crossSpellings[form] = true
  end
  schedule(NOW+delay, function()
    -- A query already in flight when a measured obligation is accepted is unrelated contention too.
    -- Drop it at delivery just like a later query dropped above, so one probe measures one owed slot.
    if recipient.probeActive and payload:match("^Q;1;") then stats.drops=stats.drops+1; return end
    stats.deliveries = stats.deliveries + 1
    if payload:match("^[RN];1;") then recipient.received[sender.name] = true end
    if payload:match("^N;1;") then stats.newsDeliveries=stats.newsDeliveries+1 end
    recipient.ns.Hunters.handlers.CHAT_MSG_ADDON(prefix,payload,"WHISPER",senderWire)
  end)
  return 0
end

loadClient = function(c, reload)
  c.generation = c.generation + 1
  local generation = c.generation
  if reload then stats.reloads=stats.reloads+1 end
  local env = {}
  setmetatable(env,{__index=_G})
  env._G, env.GodslayerDB = env, c.db
  env.GetTime = function() return NOW end
  env.GetServerTime = function() return WALL+math.floor(NOW) end
  env.time = env.GetServerTime
  env.debugprofilestop = function() return NOW*1000 end
  env.issecretvalue = function() return false end
  env.GetCurrentRegionName = function() return "US" end
  env.GetCurrentRegion = function() return 1 end
  env.GetRealmName = function() return c.realmLabel end
  env.GetNormalizedRealmName = function() return c.realmLabel end
  env.UnitFactionGroup = function() return "Horde" end
  env.InCombatLockdown = function() return isCombat(c,NOW) end
  env.IsInInstance = function() return isInstance(c,NOW) end
  env.Enum = { GameRule={} }
  env.C_GameRules = { IsHardcoreActive=function() return false end, IsGameRuleActive=function() return false end }
  env.C_DateAndTime = { GetSecondsUntilWeeklyReset=function() return 500000-(math.floor(NOW)%100000) end }
  env.C_Timer = {}
  env.C_Timer.After = function(delay,fn)
    schedule(NOW+math.max(0,delay),function() if c.generation==generation then fn() end end)
  end
  env.C_Timer.NewTicker = function(period,fn)
    local ticker={cancelled=false}
    function ticker:Cancel() self.cancelled=true end
    local function tick()
      if ticker.cancelled or c.generation~=generation then return end
      fn()
      schedule(NOW+period,tick)
    end
    schedule(NOW+period,tick)
    return ticker
  end
  env.GetChannelList = function()
    if c.directory=="suspended" then return 9,"GodslayerHunters",true end
    if not c.joined then return end
    return 9,"GodslayerHunters",false
  end
  env.securecall = function(fn,...) return fn(...) end
  env.JoinChannelByName = function(name,password,frameID,hasVoice)
    if c.directory=="refused" then return false end
    if c.directory=="suspended" then return false end
    if frameID~=0 or hasVoice~=0 then fail(c.name.." joined a visible directory channel") end
    c.joined=true
    return name=="GodslayerHunters" and 9 or false
  end
  env.LeaveChannelByName = function(name) if name=="GodslayerHunters" then c.joined=false return true end return false end
  env.GetNumDisplayChannels = function() return c.joined and 2 or 1 end
  env.GetChannelDisplayInfo = function(index)
    if index==1 then return "General",false,false,1,25,true,"CHANNEL_CATEGORY_WORLD","CHANNEL_TYPE_SYSTEM" end
    if index==2 and c.joined then return "GodslayerHunters",false,false,9,CLIENTS,true,"CHANNEL_CATEGORY_CUSTOM","CHANNEL_TYPE_CUSTOM" end
  end
  env.SetSelectedDisplayChannel = function(index) c.selected=index return true end
  env.C_ChatInfo = {
    RegisterAddonMessagePrefix=function() return 0 end,
    InChatMessagingLockdown=function() return isLockdown(c,NOW) end,
    SendAddonMessage=function(prefix,payload,channel,target) return route(c,prefix,payload,channel,target) end,
    GetChannelRosterInfo=function(_,index)
      local row=clients[index]
      return row and row.name or nil,false,false,row and ("Player-"..row.backend.."-"..index) or nil
    end,
  }
  env.ChatFrameUtil = { AddMessageEventFilter=function() end }
  local ns = { plain=function(v)return v end, try=try, char=c.char, myName=c.name, VERSION=c.version, ORIGINAL_POINTS=5,
    Rank={Level=function()return c.id%15 end}, Print=function()end }
  local chunk
  if type(setfenv)=="function" then
    chunk=assert(loadstring(source,"@Godslayer/Hunters.lua")); setfenv(chunk,env)
  else
    chunk=assert(load(source,"@Godslayer/Hunters.lua","t",env))
  end
  chunk("Godslayer",ns)
  c.env,c.ns,c.db=env,ns,env.GodslayerDB
  ns.Hunters.Init()
  if c.id==CLIENTS then ns.Hunters.SetEnabled(false) end
  if c.directory~="working" then
    -- Saved address-book/guild seeds let degraded clients prove they can continue with limited coverage.
    for i=1,12 do if clients[i]~=c then ns.Hunters.NoteCandidate(clients[i].name,"saved") end end
  end
  ns.Hunters.handlers.PLAYER_ENTERING_WORLD()
end

for _,c in ipairs(clients) do loadClient(c,false) end

-- Ten mixed-version live hunts after discovery has converged. Each has five credited kills in ten
-- seconds, so 3.1 targets receive one N while known 3.0 targets receive one nonce-zero R.
schedule(2400,function()
  for i=1,10 do
    local clientIndex, c=i,clients[i]
    stats.hunts=stats.hunts+1
    for kill=1,5 do
      local killIndex=kill
      schedule(NOW+(kill-1)*2,function()
        c.char.kills,c.char.points=c.char.kills+1,c.char.points+1
        c.lastKillAt=NOW
        c.ns.Hunters.Score(1,{name="Victim "..alpha(clientIndex*10+killIndex),class=({"DRUID","HUNTER","MAGE","PALADIN","PRIEST","ROGUE","SHAMAN","WARLOCK","WARRIOR"})[(clientIndex+killIndex-2)%9+1]})
      end)
    end
  end
end)

schedule(2419,function()
  -- The production rule sends nonce-zero R only to current verified 3.0 partners. Discovery's
  -- bounded partner cache is intentionally randomized, so refresh one already authenticated 3.0 row
  -- per hunter just before freeze instead of making legacy coverage depend on table iteration order.
  local legacyReady = 0
  for i=1,10 do
    local scope = clients[i].ns.Hunters.Debug().scope
    for key,row in pairs(scope.rows) do
      if row.version == "3.0.0" then
        scope.partners[key] = { name=row.name, heard=WALL+math.floor(NOW), verified=true }
        legacyReady = legacyReady + 1
        break
      end
    end
  end
  if legacyReady == 0 then fail("mixed-wire fixture found no authenticated 3.0 row to refresh as a partner") end
end)

-- Put one accepted response obligation on each hunting client's outbound path while its news fan-out
-- is active. Retrying the injection when that client's bounded response window is already full avoids
-- counting inbound traffic that the receiver correctly declined to owe.
for i=1,10 do
  local receiver, querySender, nonce=clients[i],clients[11],("z%07d"):format(i)
  local function readyCandidate(candidate)
    if candidate.probeActive then return nil end
    local before=candidate.ns.Hunters.Debug()
    local outstanding=before.responseScheduled or 0
    for _,item in ipairs(before.queue) do if item.kind=="response" then outstanding=outstanding+1 end end
    local burst,nonResponseBurst,minute,oldestNonResponse=0,0,0,math.huge
    local rateAt=WALL+NOW
    for _,at in ipairs(before.sentBurst or {}) do if rateAt-at<10 then burst=burst+1 end end
    for _,at in ipairs(before.nonResponseBurst or {}) do
      if rateAt-at<10 then nonResponseBurst=nonResponseBurst+1; oldestNonResponse=math.min(oldestNonResponse,at) end
    end
    for _,at in ipairs(before.sentMinute or {}) do if rateAt-at<60 then minute=minute+1 end end
    local nextSend=(candidate.sendSerial or 0)+1
    local cleanTransport=nextSend%97~=0 and nextSend%131~=0
    -- Make this a queue-reservation probe, not a server-throttle probe: two non-response attempts occupy the
    -- non-response burst, the reserved third slot is still free, and no unrelated owed response or
    -- active throttle can consume it first. Both attempts must remain in the window through the
    -- randomized response-enqueue delay, so another non-response cannot slip in ahead of the probe.
    local reservedReady=nonResponseBurst>=2 and burst==nonResponseBurst
      and rateAt-oldestNonResponse<=7
    if outstanding>0 or not reservedReady or minute>=10
       or NOW<(before.pauseUntil or 0) or not cleanTransport then return nil end
    return before
  end
  local function probe()
    local before=readyCandidate(receiver)
    if not before then
      for candidateIndex=1,CLIENTS-5 do
        local candidate=clients[candidateIndex]
        before=readyCandidate(candidate)
        if before then receiver=candidate; break end
      end
    end
    if not before then
      if NOW<3100 then schedule(NOW+1,probe) end
      return
    end
    receiver.ns.Hunters.handlers.CHAT_MSG_ADDON("GodslayerG","Q;1;"..nonce..";us/pvp","WHISPER",querySender.name)
    local accepted=false
    for dedupe in pairs(receiver.ns.Hunters.Debug().owedResponses or {}) do
      if dedupe:sub(-9)==":"..nonce then accepted=true; break end
    end
    if accepted then
      stats.probes=stats.probes+1
      stats.owed[nonce.."|"..querySender.name.."|"..receiver.name]={accepted=NOW}
      receiver.probeActive=nonce
    elseif NOW<3000 then schedule(NOW+5,probe) end
  end
  schedule(2422+i*0.1,probe)
end

-- Reload five live clients in place; their SavedVariables and character ordering survive while
-- generation-guarded old timers die exactly as the client destroys old Lua frames.
schedule(1600,function()
  for i=1,5 do
    clients[i].reloadFloor=clients[i].ns.Hunters.Debug().scope.meta.rowCount
    loadClient(clients[i],true)
  end
end)

-- Malformed and hostile traffic enters the real parser. None of these senders receives a query,
-- so none may acquire a row.
schedule(300,function()
  local h=clients[1].ns.Hunters.handlers
  local valid=clients[2].ns.Hunters.OwnMessage("0")
  local attacks={ ("X"):rep(241),"R;1;0","R;2;0;1","Q;1;bad","I;1;abcdefgh;Good Name|junk;R;1",
    valid,valid..";Another Owner" }
  for _,payload in ipairs(attacks) do stats.attacks=stats.attacks+1; h.CHAT_MSG_ADDON("GodslayerG",payload,"WHISPER","Evil Intruder") end
  for i=1,30 do
    stats.attacks=stats.attacks+1
    h.CHAT_MSG_ADDON("GodslayerG",("Q;1;%08d;us/pvp"):format(i),"WHISPER","Flood Sender")
  end
end)

while events[1] and events[1].at<=DURATION do
  local e=pop(); NOW=e.at
  local ok,err=pcall(e.fn)
  if not ok then fail("timer/network error at "..string.format("%.2f",NOW)..": "..tostring(err)) end
end
NOW=DURATION

local bestConfirmed, working, refused, suspended = 0,0,0,0
local sawOne,sawTwo,backendA,backendB=false,false,false,false
for _,c in ipairs(clients) do
  local H,debug=c.ns.Hunters,c.ns.Hunters.Debug()
  local scope=debug.scope
  if c.name:find(" ",1,true) then sawTwo=true else sawOne=true end
  if c.backend=="A" then backendA=true else backendB=true end
  if c.directory=="working" then working=working+1
  elseif c.directory=="refused" then refused=refused+1 else suspended=suspended+1 end
  local status=H.Status()
  if c.id~=CLIENTS then
    if c.directory=="working" and status.directory~="working" then fail(c.name.." did not reach working directory state: "..tostring(status.directory)) end
    if c.directory=="refused" and status.directory~="not joined" then fail(c.name.." did not expose refused directory") end
    if c.directory=="suspended" and status.directory~="suspended" then fail(c.name.." did not expose suspended directory") end
  end
  bestConfirmed=math.max(bestConfirmed,scope.meta.rowCount or 0)
  if (scope.meta.rowCount or 0)>H.LIMITS.rows or (scope.meta.candidateCount or 0)>H.LIMITS.candidates
     or (scope.meta.pendingCount or 0)>H.LIMITS.pending or (scope.meta.completedCount or 0)>H.LIMITS.completed
     or #debug.queue>H.LIMITS.queue+8 then fail(c.name.." exceeded a storage/queue cap") end
  for _,row in pairs(scope.rows) do
    if not c.received[row.name] then fail(c.name.." has a row without a direct R from "..tostring(row.name)) end
    local owner = byName[row.name]
    if owner and owner.ruleset ~= c.ruleset then
      fail(c.name.." retained cross-ruleset row for "..row.name)
    end
  end
  if scope.rows[H.RowKey("Evil Intruder")] then fail(c.name.." accepted forged Evil Intruder row") end
  local nonces={}
  for i,m in ipairs(c.outbound) do
    if m.channel~="WHISPER" then fail(c.name.." used channel transport") end
    if isCombat(c,m.at) or isInstance(c,m.at) or isLockdown(c,m.at) then fail(c.name.." sent during combat/instance/lockdown") end
    if i>1 and m.at-c.outbound[i-1].at<1.999 then fail(c.name.." violated two-second spacing") end
    local nonce=m.payload:match("^Q;1;([0-9a-z]+);[a-z0-9]+/[a-z0-9]+$")
      or m.payload:match("^D;1;([0-9a-z]+)$")
    if nonce then
      -- A result-3 retry is the same issued request and intentionally keeps its nonce.  Reusing
      -- that nonce for another operation or destination is the session-uniqueness violation.
      local signature=m.payload.."\031"..tostring(m.target)
      if nonces[nonce] and nonces[nonce]~=signature then fail(c.name.." reused issued nonce "..nonce) end
      nonces[nonce]=signature
    end
    local minute,burst=0,0
    local nonResponseBurst=0
    for j=i,#c.outbound do
      local gap=c.outbound[j].at-m.at
      if gap<60 then minute=minute+1 end
      if gap<10 then
        burst=burst+1
        local rop,rnonce=c.outbound[j].payload:match("^([A-Z]);1;([^;]+)")
        if not (rop=="R" and rnonce and rnonce~="0") then nonResponseBurst=nonResponseBurst+1 end
      end
    end
    if minute>10 then fail(c.name.." exceeded ten outbound attempts/minute") end
    if burst>3 then fail(c.name.." exceeded three outbound attempts/ten seconds") end
    if nonResponseBurst>2 then fail(c.name.." exceeded two non-response attempts/ten seconds") end
  end
  if c.id==CLIENTS and #c.outbound>0 then fail("opted-out client emitted Hunters traffic") end
  if c.reloadFloor and (scope.meta.rowCount or 0)<c.reloadFloor then fail(c.name.." lost confirmed rows across reload") end
end

if not (sawOne and sawTwo) then fail("simulator did not include both Forever name forms") end
if not (backendA and backendB) then fail("simulator did not include two backends") end
if not (stats.crossSpellings[1] and stats.crossSpellings[2] and stats.crossSpellings[3]) then
  fail("cross-backend delivery did not exercise plain, suffixed, and hyphenated sender spellings")
end
if stats.crossScopeQueries == 0 then fail("second-ruleset clients never whispered the first ruleset") end
if stats.crossScopeAnswers ~= 0 then fail("one or more cross-ruleset Q messages were answered") end
-- Foreign candidates deliberately consume one discovery turn before retirement. Eighty rows keeps
-- the original busy-network convergence check meaningful for the 200-client primary scope without
-- rewarding an implementation that incorrectly merges the second ruleset.
if bestConfirmed<80 then fail("busy network converged to only "..bestConfirmed.." confirmed rows") end
if stats.deliveries==0 or stats.drops==0 or stats.offline==0 or stats.throttles==0 or stats.lockdown==0 then
  fail("one or more transport fault modes were not exercised")
end
if stats.reloads<5 or working==0 or refused==0 or suspended==0 then fail("reload/directory scenario coverage incomplete") end
local starvation=stats.responseStarvation or 0
for _ in pairs(stats.owed) do starvation=starvation+1 end
if stats.newsSends==0 or stats.legacyPushes==0 or stats.newsDeliveries==0 then fail("mixed 3.0/3.1 live-news workload did not deliver both wire forms") end
if stats.probes~=10 then fail("live-news workload accepted only "..stats.probes.." of 10 response probes") end
if starvation~=0 then fail("live-news workload starved "..starvation.." owed responses") end

realPrint(("%d clients, 9 classes, mixed 3.0/3.1, %d working/%d refused/%d suspended directories, %d deliveries, %d news/%d legacy sends over %d hunts, %.1fs max live news latency, %d stale N, %.1f sends/hunt, queue depth %d, %d response probes, max owed-response delay %.1fs, starvation %d, %d failures")
  :format(CLIENTS,working,refused,suspended,stats.deliveries,stats.newsSends,stats.legacyPushes,stats.hunts,
    stats.liveNewsLatencyMax,stats.staleNews,(stats.newsSends+stats.legacyPushes)/math.max(1,stats.hunts),
    stats.maxQueue,stats.probes,stats.responseLatencyMax,starvation,failures))
os.exit(failures==0 and 0 or 1)
