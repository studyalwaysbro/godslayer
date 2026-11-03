-- Build docs/SECRECY.md from the WoW: Forever client's own generated API documentation.
--
--   luatex --luaonly tools/build_secrecy_map.lua [--check]
--
-- Why this exists. Nearly every mistake made writing a PvP addon for this client is a mistake
-- about secrecy: a function that hands back a secret value in the one situation you care about, a
-- field that survives when the rest of its structure does not, or a call that is in the generated
-- documentation and is not loaded in this game at all. All three are written down by the client,
-- and the file that writes down the rules is SecretPredicatesDocumentation.lua, which nobody
-- reads because it has no functions in it.
--
-- The documentation files are Lua, and each one ends in a call to APIDocumentation. So they are
-- not parsed: they are loaded, with that one call stubbed, which makes this exact rather than
-- approximate. The .toc files are read as text, because they are not Lua.
--
-- --check writes nothing and exits non-zero if the file on disk would differ.

local KNOWLEDGE = "/home/yeeterson/projects/wow-forever-guild/site/scripts/knowledge"
local UI = KNOWLEDGE .. "/cache/ui-source/Interface"
local DOCS = UI .. "/AddOns/Blizzard_APIDocumentationGenerated"
local OUT = "docs/SECRECY.md"
local GAME_TYPE = "camelot"

local function sh(cmd)
  local p = assert(io.popen(cmd))
  local s = p:read("*a")
  p:close()
  return s
end

local function lines(s)
  local out = {}
  for line in s:gmatch("[^\n]+") do out[#out + 1] = line end
  return out
end

--------------------------------------------------------------------------------
-- Load every documentation table
--------------------------------------------------------------------------------

-- The stub goes in the real global table rather than a sandbox: setfenv is gone from the Lua
-- this script runs under, and a sandbox the chunk cannot see is a sandbox that does nothing.
local systems = {}
APIDocumentation = {
  AddDocumentationTable = function(_, t) systems[#systems + 1] = t end,
}

-- Some of these files compute a default or a max from `Enum` or `Constants` at load time, which
-- in game are already there. Without them a quarter of the files throw on the way in, and the
-- ones that throw include several that carry never-secret fields. The values do not matter here,
-- only that indexing anything works, so both are tables that answer every question with 0.
local anything = {}
anything.__index = function(t, k) local v = setmetatable({}, anything) rawset(t, k, v) return v end
anything.__add = function() return 0 end
anything.__sub = function() return 0 end
anything.__mul = function() return 0 end
anything.__div = function() return 0 end
anything.__unm = function() return 0 end
anything.__concat = function(a, b) return tostring(type(a) == "string" and a or "") .. tostring(type(b) == "string" and b or "") end
anything.__len = function() return 0 end
anything.__tostring = function() return "0" end
anything.__call = function() return 0 end
Enum = setmetatable({}, anything)
Constants = setmetatable({}, anything)

local files = lines(sh(("ls %q/*.lua 2>/dev/null"):format(DOCS)))
if #files == 0 then
  io.stderr:write("no documentation files under " .. DOCS .. "\n")
  os.exit(1)
end

local loaded, skipped = 0, {}
for _, path in ipairs(files) do
  local chunk, err = loadfile(path)
  if not chunk then
    skipped[#skipped + 1] = { path:match("([^/]+)$"), tostring(err) }
  else
    local ok, e = pcall(chunk)
    if ok then loaded = loaded + 1 else skipped[#skipped + 1] = { path:match("([^/]+)$"), tostring(e) } end
  end
end

--------------------------------------------------------------------------------
-- The rules, from the file that states them
--------------------------------------------------------------------------------

local rules = {}       -- name -> { kind, rule, failure }
for _, sys in ipairs(systems) do
  for _, p in ipairs(sys.Predicates or {}) do
    if type(p) == "table" and p.Name then
      local doc = p.Documentation
      rules[p.Name] = {
        kind = p.Type or "",
        rule = (type(doc) == "table" and doc[1]) or nil,
        failure = p.FailureMode,
      }
    end
  end
end

--------------------------------------------------------------------------------
-- Who carries which rule, and which fields escape it
--------------------------------------------------------------------------------

local KNOWN_KEYS = {}  -- every Secret*/Requires* key seen on a function
local carriers = {}    -- rule -> { "C_Thing.Call", ... }
local never = {}       -- structure -> { field, ... }
local namespaces = {}  -- namespace -> { system = name, environment = ... }

local function noteCarrier(rule, who)
  carriers[rule] = carriers[rule] or {}
  local t = carriers[rule]
  t[#t + 1] = who
end

for _, sys in ipairs(systems) do
  local ns = sys.Namespace
  local sysName = sys.Name or "(unnamed)"
  if ns then namespaces[ns] = { system = sysName, environment = sys.Environment } end
  local prefix = ns and (ns .. ".") or ""

  for _, f in ipairs(sys.Functions or {}) do
    if type(f) == "table" and f.Name then
      local who = prefix .. f.Name
      for key, value in pairs(f) do
        local isRule = key:match("^Secret") or key:match("^Requires")
        -- SecretArguments governs what may be passed IN and is on nearly every call, so it is
        -- counted but never treated as a restriction on what comes back.
        if isRule and key ~= "SecretArguments" and key ~= "SecretArgumentsAddAspect" then
          KNOWN_KEYS[key] = true
          if value ~= false then noteCarrier(key, who) end
        end
      end
      -- A precondition can also be listed rather than flagged.
      for _, p in ipairs(f.Preconditions or {}) do
        if type(p) == "string" then KNOWN_KEYS[p] = true noteCarrier(p, who) end
      end
    end
  end

  for _, e in ipairs(sys.Events or {}) do
    if type(e) == "table" and e.Name then
      local who = (e.LiteralName or e.Name) .. " (event)"
      for key, value in pairs(e) do
        local isRule = key:match("^Secret") or key:match("^Requires")
        if isRule and key ~= "SecretArguments" and key ~= "SecretArgumentsAddAspect" then
          KNOWN_KEYS[key] = true
          if value ~= false then noteCarrier(key, who) end
        end
      end
    end
  end

  for _, t in ipairs(sys.Tables or {}) do
    if type(t) == "table" and t.Name and t.Fields then
      for _, field in ipairs(t.Fields) do
        if type(field) == "table" and field.NeverSecret and field.Name then
          never[t.Name] = never[t.Name] or {}
          local b = never[t.Name]
          b[#b + 1] = field.Name
        end
      end
    end
  end
end

--------------------------------------------------------------------------------
-- What actually loads in this game
--------------------------------------------------------------------------------

-- A call in the generated documentation is not a call this client runs. Blizzard ships one
-- interface for every game type and gates the files, so a .toc is the difference between a
-- function existing and existing here.
local gated = {}      -- { addon, file, loadsOn } for files NOT loaded on this game type
local addonGated = {} -- { addon, loadsOn } for addons whose whole toc leaves this game type out

-- `AllowLoadGameType` does not take game types only. It also takes the name of a FAMILY, and
-- camelot is a member of the `mainline` family. That one fact decides whether a Blizzard frame
-- exists on this realm, so it is written down here with its evidence rather than assumed:
--
--   * Six addons are gated `AllowLoadGameType: mainline` at the top of the toc and then name
--     camelot-only files inside themselves -- the auction house, professions, achievements, the
--     collections journal, the friends list and the personal resource display. A camelot file
--     inside an addon that camelot never loads is dead code, and Blizzard does not ship six of
--     those. `assertFamilyEvidence` below re-checks this every run.
--   * `Blizzard_Collections` writes `[Family]\Blizzard_ToyBoxProgressTracker.xml
--     [AllowLoadGameType mainline] [ExcludeLoadGameType camelot]`. Excluding camelot from a line
--     already gated to mainline is only meaningful if mainline would otherwise admit it.
--   * `Blizzard_WorldMap` carries `RequiredDep: Blizzard_SharedMapDataProviders`, whose own toc
--     reads `AllowLoadGameType: mainline`, and then overrides the world map for camelot. A
--     required dependency that could not load would leave this realm with no world map at all.
--
-- `standard` is a sibling of camelot and not a parent: eleven addons write `standard, camelot`,
-- which would be redundant if standard contained it, and not one addon gated to `standard` names
-- a camelot-only file.
--
-- `ExcludeLoadGameType` is the other half and the client never writes a family name in one -- it
-- names concrete game types -- so an exclusion is matched on the game type alone. It also wins:
-- a `[Family]` line admitted by the family and then excluded by game type does not load.
local ADMITS = { [GAME_TYPE] = true, mainline = true }

local function admitted(words)
  for word in words:gmatch("[%w_]+") do if ADMITS[word] then return true end end
  return false
end

local function barred(words)
  for word in words:gmatch("[%w_]+") do if word == GAME_TYPE then return true end end
  return false
end

-- Reasons a family word may not be read as a game type, counted so the summary can show that the
-- distinction is load-bearing rather than theoretical.
local familyEvidence = 0

local tocs = lines(sh(("find %q/AddOns -maxdepth 2 -name '*.toc' 2>/dev/null | sort"):format(UI)))
for _, tocPath in ipairs(tocs) do
  local addon = tocPath:match("([^/]+)%.toc$")
  local fh = io.open(tocPath)
  if fh then
    local body = fh:read("*a") fh:close()

    local allow = body:match("##%s*AllowLoadGameType:%s*([^\r\n]+)")
    local deny = body:match("##%s*ExcludeLoadGameType:%s*([^\r\n]+)")
    local loads = not allow or admitted(allow)
    if loads and deny and barred(deny) then loads = false end
    if not loads then
      local why = allow and (allow:gsub("%s+$", "")) or "all"
      if deny then why = why .. ", not " .. (deny:gsub("%s+$", "")) end
      addonGated[#addonGated + 1] = { addon, why }
    end

    -- A toc gated to a family that then names a file for this game type is the evidence above.
    if allow and not barred(allow) and admitted(allow) and body:find("%[AllowLoadGameType%s+[^%]]*" .. GAME_TYPE) then
      familyEvidence = familyEvidence + 1
    end

    if loads then
      for line in body:gmatch("[^\r\n]+") do
        if not line:match("^%s*##") then
          local types = line:match("%[AllowLoadGameType%s+([^%]]+)%]")
          local nope = line:match("%[ExcludeLoadGameType%s+([^%]]+)%]")
          if types or nope then
            local file = line:match("^(.-)%s*%[") or ""
            file = file:gsub("%s+$", "")
            local ok = (not types) or admitted(types)
            if ok and nope and barred(nope) then ok = false end
            if file ~= "" and not ok then
              local why = types and (types:gsub("%s+$", "")) or "all"
              if nope then why = why .. ", not " .. (nope:gsub("%s+$", "")) end
              gated[#gated + 1] = { addon, file, why }
            end
          end
        end
      end
    end
  end
end

-- If Blizzard ever stops shipping camelot files inside family-gated addons, the reading above is
-- no longer supported by the source and this file would start inventing frames that do not exist.
-- Six is what the interface at the top of this file carries; one is enough to keep the claim, and
-- none means stop and read the tocs again.
assert(familyEvidence > 0, ([[
no toc gated to a family names a %s file any more, so the family reading in this script is no
longer backed by the interface source. Re-derive it before trusting docs/SECRECY.md.]]):format(GAME_TYPE))

--------------------------------------------------------------------------------
-- Emit
--------------------------------------------------------------------------------

local o = {}
local function w(s) o[#o + 1] = s or "" end

local build = (sh(("ls %q/cache/db2 2>/dev/null | sort -V | tail -1"):format(KNOWLEDGE)):gsub("%s+$", ""))
local uiBuild = (sh(("git -C %q/cache/ui-source log --oneline -1 2>/dev/null"):format(KNOWLEDGE)):gsub("%s+$", ""))

w("# What WoW: Forever will and will not tell an addon")
w()
w("Written by `tools/build_secrecy_map.lua` from the client's own generated API documentation.")
w("Do not edit by hand.")
w()
w(("Interface source: `%s`. Newest client data in the cache: `%s`."):format(uiBuild ~= "" and uiBuild or "unknown", build ~= "" and build or "unknown"))
w(("%d documentation tables loaded from %d files."):format(#systems, loaded))
if #skipped > 0 then
  w()
  w(("%d file(s) could not be loaded and are not represented here:"):format(#skipped))
  for _, s in ipairs(skipped) do w(("- `%s`: %s"):format(s[1], s[2])) end
end
w()
w("The interface source lags the installed client. A function added since the commit above will")
w("not appear here, and the way to find out is to call it and check the result rather than to")
w("trust this file's silence.")
w()
w("## Why this file exists")
w()
w("Nearly every mistake in writing an addon for this client is a mistake about secrecy. A call")
w("returns a number out of combat and a secret value in it. A structure goes secret except for the")
w("four fields that do not. A function is in the documentation and is not loaded in this game at")
w("all. Each of those has a different cause and they are easy to confuse for one another, because")
w("all three look like \"it stopped working\".")
w()
w("The rules themselves are written down by the client, in a file with no functions in it that")
w("therefore nobody opens: `SecretPredicatesDocumentation.lua`. What follows is that file's rules")
w("joined to every call and event that carries them.")
w()
w("A secret value cannot be added, compared or concatenated. It is not nil and it is not zero, and")
w("treating it as either is the bug. `ns.plain(v)` in this addon returns nil for one, which makes")
w("\"we were not told\" a different answer from \"it was nothing\".")
w()

-- the rules
w("## The rules")
w()
w("`Secret*` rules hand back secret values. `Requires*` preconditions fail instead, and the")
w("failure mode says how: `Error` throws, `ReturnWithError` returns nothing and logs, and")
w("`ReturnNothing` returns nothing quietly. Anything behind an `Error` needs a `pcall`.")
w()
local names = {}
for name in pairs(KNOWN_KEYS) do names[#names + 1] = name end
table.sort(names, function(a, b)
  local na, nb = #(carriers[a] or {}), #(carriers[b] or {})
  if na ~= nb then return na > nb end
  return a < b
end)
w("| rule | carriers | kind | fails by | what the client says it means |")
w("|---|---|---|---|---|")
for _, name in ipairs(names) do
  local r = rules[name] or {}
  local rule = r.rule or "_not documented in SecretPredicatesDocumentation.lua_"
  rule = rule:gsub("|", "\\|")
  w(("| `%s` | %d | %s | %s | %s |"):format(name, #(carriers[name] or {}),
    r.kind ~= "" and (r.kind or "-") or "-", r.failure or "-", rule))
end
w()
w("Three of the names above are flags rather than predicates and so have no entry in the client's")
w("own rules file. Reading them from how they are used:")
w()
w("- `SecretReturns = true` with no conditional rule beside it means the returns are secret")
w("  always, not under a condition. `UnitCastingDuration` carries it bare, while `UnitCastingInfo`")
w("  next to it carries `SecretWhenUnitSpellCastRestricted` instead -- so the pair is the same")
w("  subject with an unconditional rule and a conditional one, which is what fixes the reading.")
w("- `SecretArguments` is excluded from this file entirely. It governs what may be passed **in**")
w("  (`AllowedWhenTainted`, `AllowedWhenUntainted`) and sits on nearly four thousand calls, so it")
w("  says nothing about whether an answer comes back usable.")
w("- A `Requires*` precondition with no entry is almost always about state rather than secrecy")
w("  (`RequiresClubsInitialized`, `RequiresFriendList`): the call needs something loaded, and an")
w("  addon handles it by checking, not by unwrapping.")
w()
local orphan = {}
for name in pairs(rules) do if not KNOWN_KEYS[name] then orphan[#orphan + 1] = name end end
table.sort(orphan)
if #orphan > 0 then
  w(("Rules the client documents but nothing in this interface source carries (%d): %s."):format(
    #orphan, "`" .. table.concat(orphan, "`, `") .. "`"))
  w()
end

-- who carries what
w("## What each rule gates")
w()
for _, name in ipairs(names) do
  local who = carriers[name] or {}
  table.sort(who)
  w(("### `%s` — %d"):format(name, #who))
  w()
  local r = rules[name]
  if r and r.rule then w("> " .. r.rule) w() end
  if #who <= 60 then
    for _, c in ipairs(who) do w("- `" .. c .. "`") end
  else
    for i = 1, 40 do w("- `" .. who[i] .. "`") end
    w(("- _and %d more_"):format(#who - 40))
  end
  w()
end

-- the escape hatches
w("## Fields that are never secret")
w()
w("`NeverSecret = true` on a field is a deliberate hole in a restriction: the structure goes")
w("secret and these do not. They are where an addon on this client is still allowed to work, and")
w("they are the most useful list in this file.")
w()
local structs = {}
for s in pairs(never) do structs[#structs + 1] = s end
table.sort(structs)
w("| structure | fields that survive |")
w("|---|---|")
for _, s in ipairs(structs) do
  local f = never[s]
  table.sort(f)
  w(("| `%s` | %s |"):format(s, "`" .. table.concat(f, "`, `") .. "`"))
end
w()

-- what loads here
w(("## What is not loaded on `%s`"):format(GAME_TYPE))
w()
w("Blizzard ships one interface for every game type and gates the files in each `.toc`. A function")
w("defined in a gated-out file does not exist in this game, whatever the documentation says and")
w("whatever CVar the file checks on its first line. This is the trap that catches every addon")
w("ported from Classic or retail, and it is silent: the global is simply nil.")
w()
if #addonGated > 0 then
  table.sort(addonGated, function(a, b) return a[1] < b[1] end)
  w(("Whole addons excluded (%d):"):format(#addonGated))
  w()
  w("| addon | loads on |")
  w("|---|---|")
  for _, row in ipairs(addonGated) do w(("| `%s` | %s |"):format(row[1], row[2])) end
  w()
end
table.sort(gated, function(a, b)
  if a[1] ~= b[1] then return a[1] < b[1] end
  return a[2] < b[2]
end)
w(("Individual files excluded (%d):"):format(#gated))
w()
w("| addon | file | loads on |")
w("|---|---|---|")
for _, row in ipairs(gated) do w(("| `%s` | `%s` | %s |"):format(row[1], row[2], row[3])) end
w()

-- the conclusions, each one pointing at a row above it
w("## What this means for an addon on this realm")
w()
w("Every claim here is a reading of a row in this file. The rows are generated; the readings are")
w("not, and they are marked as readings.")
w()
w("**The combat log is shut, and two replacements for it are open.** `C_DamageMeter` carries")
w("`SecretWhenInCombat`, so its numbers arrive once the fight is over. `C_DeathRecap` carries")
w("**nothing at all** -- four functions, no annotation on any of them -- and hands back")
w("combat-log-shaped rows for the last seconds of your life.")
w()
w("**`mainline` in a `.toc` is a family, and camelot is inside it.** This is the most expensive")
w("mistake available in this file and it is not a secrecy rule at all. Reading `AllowLoadGameType:")
w("mainline` as a game type rather than a family hides twenty-eight addons that do load here --")
w("the mail frame, the friends list, the auction house, professions, achievements, the collections")
w("journal -- and it invents gaps in the interface that are not there. The giveaway is in the")
w("tocs themselves: six addons gated to `mainline` go on to name camelot-only files inside")
w("themselves, and `Blizzard_Collections` writes `[AllowLoadGameType mainline]` and")
w("`[ExcludeLoadGameType camelot]` on the same line, which is only meaningful if mainline would")
w("otherwise admit camelot. `standard` is the sibling, not the parent: eleven addons write")
w("`standard, camelot` and none gated to `standard` alone names a camelot file.")
w()
w("**The two open namespaces have frames here after all, and the frames answer narrower")
w("questions than the calls do.** `C_LossOfControl` and `C_DeathRecap` carry no secrecy")
w("annotation whatever, and both of their frames load on this game type through the family above.")
w("What is still missing is not the data and not a window -- it is the reading.")
w()
w("| namespace | its frame | loads here | what the frame shows |")
w("|---|---|---|---|")
w("| `C_LossOfControl` | `Blizzard_FrameXML/LossOfControlFrame.lua` | yes, mists + mainline | one effect at a time, highest priority then longest remaining, behind the `lossOfControl` CVar |")
w("| `C_DeathRecap` | `Blizzard_DeathRecap/Mainline/Blizzard_DeathRecap.lua` | yes, mainline | the rows, in a window you open afterwards from the damage meter, the death dialog or a chat link |")
w()
w("**An enemy cast bar cannot be built.** `SecretWhenUnitSpellCastRestricted` is documented as")
w("secret \"if the unit being queried for cast information is not the player or their pet\", and")
w("`UnitCastingDuration` beside it carries a bare `SecretReturns`. There is no condition to wait")
w("out and no window where it opens.")
w()
w("**Enemy names survive in PvP, deliberately.** `SecretWhenUnitNameIdentityRestricted` is")
w("documented as the ordinary identity rules \"except in PvP when the queried unit is a player\".")
w("That carve-out is what lets a kill tracker, a dossier and a battleground roster work at all.")
w()
w("**A battleground scoreboard is names and ranks until the match ends.** `SecretInActivePvPMatch`")
w("seals `C_PvP.GetScoreInfo` for the whole match, and `PVPScoreInfo` leaves seven fields open --")
w("including `honorLevel`, which on this game type is the PvP rank.")
w()
w("**Whether a cooldown is running is always knowable; how long is not.** `SpellCooldownInfo`")
w("leaves `isActive`, `isEnabled` and `isOnGCD` never-secret while the call around it carries")
w("`SecretWhenCooldownsRestricted`. An addon can say \"that is on cooldown\" under restriction and")
w("cannot say for how long.")
w()
w("**`pcall` is not optional.** `RequiresUnitAuraAccess` fails by `Error`, which throws rather")
w("than returning nothing. Anything reading auras needs the call wrapped.")
w()
w("**A secret is not a nil and not a zero.** Three different failures look identical from the")
w("outside -- a secret value, a precondition that returned nothing, and a function that was never")
w("loaded on this game type -- and each wants different code. The first needs unwrapping, the")
w("second needs checking, and the third needs a different function.")
w()

-- namespaces and their environments
w("## Namespaces, and where they are allowed to run")
w()
w("`Environment` is the client's own note about where a namespace exists. `All` is every")
w("environment; anything else is worth reading before building on it.")
w()
local nsNames = {}
for n in pairs(namespaces) do nsNames[#nsNames + 1] = n end
table.sort(nsNames)
local byEnv = {}
for _, n in ipairs(nsNames) do
  local e = namespaces[n].environment or "(unstated)"
  byEnv[e] = byEnv[e] or {}
  local b = byEnv[e]
  b[#b + 1] = n
end
local envs = {}
for e in pairs(byEnv) do envs[#envs + 1] = e end
table.sort(envs)
w("| environment | namespaces |")
w("|---|---|")
for _, e in ipairs(envs) do
  local list = byEnv[e]
  w(("| %s | %d |"):format(e, #list))
end
w()
for _, e in ipairs(envs) do
  if e ~= "(unstated)" and #byEnv[e] <= 40 then
    w(("**%s** (%d): %s"):format(e, #byEnv[e], "`" .. table.concat(byEnv[e], "`, `") .. "`"))
    w()
  end
end

local text = table.concat(o, "\n") .. "\n"

local check = false
for i = 1, #(arg or {}) do if arg[i] == "--check" then check = true end end

local have = ""
local fh = io.open(OUT)
if fh then have = fh:read("*a") fh:close() end

if check then
  if have ~= text then
    io.stderr:write(OUT .. " is out of date; run luatex --luaonly tools/build_secrecy_map.lua\n")
    os.exit(1)
  end
  print(OUT .. " matches the interface source")
  os.exit(0)
end

local out = assert(io.open(OUT, "w"))
out:write(text) out:close()
print(("wrote %s (%d rules, %d structures with never-secret fields, %d gated files)"):format(
  OUT, #names, #structs, #gated))
