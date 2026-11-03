#!/bin/sh
# Everything that has to be true before Godslayer is packaged.
#
#   sh tools/check.sh
#
# Three kinds of check, cheapest failure first:
#
#   1. every Lua file parses
#   2. the generated files still match the client they were generated from
#   3. every suite passes, and then the soak
#
# LuaTeX seeds math.random from the clock and WoW's Lua 5.1 does not, so each suite runs under a
# pinned seed. Without that the same code reports anywhere from 0 to 11 failures. luatex will not
# take a script on stdin either, so each step that needs Lua gets a real file.
set -e
cd "$(dirname "$0")/.."

SEED=${GS_SEED:-4}
RUNNER=$(mktemp)
SYNTAX=$(mktemp)
trap 'rm -f "$RUNNER" "$SYNTAX"' EXIT

cat > "$RUNNER" <<'LUA'
math.randomseed(tonumber(os.getenv("GS_SEED")) or 4)
assert(loadfile(os.getenv("GS_SUITE")))()
LUA

cat > "$SYNTAX" <<'LUA'
-- There is no luac on this machine, so loadfile is the compiler: it reports a syntax error
-- without running anything.
local function sh(cmd)
  local p = assert(io.popen(cmd))
  local s = p:read("*a")
  p:close()
  return s
end
local bad, n = 0, 0
for path in sh("ls Godslayer/*.lua tests/*.lua tools/*.lua 2>/dev/null"):gmatch("[^\n]+") do
  n = n + 1
  local fn, err = loadfile(path)
  if not fn then
    bad = bad + 1
    io.stderr:write(path .. ": " .. tostring(err) .. "\n")
  end
end
print(n .. " files parse" .. (bad > 0 and (", " .. bad .. " do not") or ""))
if bad > 0 then os.exit(1) end
LUA

echo "== syntax =="
luatex --luaonly "$SYNTAX"

echo
echo "== generated against the client =="
node tools/build_pvp_data.mjs --check
luatex --luaonly tools/build_secrecy_map.lua --check

echo
echo "== suites =="
total=0
for s in run v2 v22 aura rival ledger rank recap field flag control death threat perf; do
  out=$(GS_SEED="$SEED" GS_SUITE="tests/$s.lua" luatex --luaonly "$RUNNER" 2>&1 | tail -1)
  printf '%-10s %s\n' "$s" "$out"
  case "$out" in
    *"0 failed") ;;
    *) echo "FAILED: $s"; exit 1 ;;
  esac
  n=$(printf '%s' "$out" | sed -n 's/^\([0-9]*\) passed.*/\1/p')
  total=$((total + n))
done
echo "total $total assertions"

echo
echo "== soak =="
GS_SEED="$SEED" GS_SUITE=tests/fuzz.lua luatex --luaonly "$RUNNER" | tail -1

echo
echo "== cost =="
luatex --luaonly tools/profile.lua --check | tail -4
