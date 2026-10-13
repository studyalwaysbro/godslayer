-- The clip mark, for players who record. An addon cannot write a file or talk to another
-- program, but it can take a screenshot. So when a hunt ends, a small block of black and white
-- squares is drawn in the top left corner for a moment and the screenshot is taken with it in
-- view. A recorder watching the Screenshots folder reads the squares and knows a hunt just
-- ended, how long it ran, how many died and where its best moment was. clipper/ in the
-- repository is one such recorder. Off unless asked: /godslayer hype clip on.
local ADDON, ns = ...
local Clip = {}
ns.Clip = Clip

-- 16 bytes, most significant bit first, 32 squares to a row, inside a border one square wide:
--   1 0xAC   2 version * 16 + kind   3 kills   4-5 seconds since the first kill
--   6-7 seconds since the last kill   8 rung reached (its place on the ladder)   9 best run
--   10 grade (0 none, 1 C, 2 B, 3 A, 4 S, 5 S+)   11 Olympus points   12 flags
--   13-14 seconds since the best moment   15 a count that changes with every mark   16 CRC-8
local COLS, ROWS, CELL = 32, 4, 8 -- a square is 8 screen pixels
local MAGIC, VERSION = 0xAC, 1
local SHOWN = 1.5
Clip.KIND = { quiet = 1, died = 2, manual = 3 }
Clip.FLAG = { pretend = 1, record = 2, king = 4, flawless = 8 }
Clip.COLS, Clip.ROWS, Clip.CELL = COLS, ROWS, CELL

local function bxor(a, b)
  local r, p = 0, 1
  for _ = 1, 8 do
    local x, y = a % 2, b % 2
    if x ~= y then r = r + p end
    a, b, p = (a - x) / 2, (b - y) / 2, p * 2
  end
  return r
end

local function crc8(bytes)
  local crc = 0
  for i = 1, #bytes do
    crc = bxor(crc, bytes[i])
    for _ = 1, 8 do
      crc = crc >= 128 and bxor((crc * 2) % 256, 0x07) or (crc * 2) % 256
    end
  end
  return crc
end
Clip.Crc = crc8

local function clamp(v, top) return math.max(0, math.min(top, math.floor(tonumber(v) or 0))) end

local strip, cells, serial, turn = nil, nil, 0, 0

local function build()
  if strip then return strip end
  local _, height = GetPhysicalScreenSize()
  if not height or height <= 0 then return nil end
  -- a frame with no parent is measured against a screen 768 high, whatever the interface scale
  local px = 768 / height * CELL
  local f = CreateFrame("Frame")
  f:SetFrameStrata("TOOLTIP")
  f:SetSize((COLS + 2) * px, (ROWS + 2) * px)
  f:SetPoint("TOPLEFT", WorldFrame, "TOPLEFT", 0, 0)
  local back = f:CreateTexture(nil, "BACKGROUND")
  back:SetAllPoints(f)
  back:SetColorTexture(0, 0, 0, 1)
  cells = {}
  for i = 0, COLS * ROWS - 1 do
    local t = f:CreateTexture(nil, "ARTWORK")
    t:SetSize(px, px)
    t:SetPoint("TOPLEFT", f, "TOPLEFT", (i % COLS + 1) * px, -(math.floor(i / COLS) + 1) * px)
    t:SetColorTexture(1, 1, 1, 1)
    cells[i] = t
  end
  f:Hide()
  f:SetScript("OnEvent", function(self) self:Hide() end)
  pcall(f.RegisterEvent, f, "SCREENSHOT_SUCCEEDED")
  pcall(f.RegisterEvent, f, "SCREENSHOT_FAILED")
  strip = f
  return f
end

local function paint(bytes)
  for i = 0, COLS * ROWS - 1 do
    local byte, bit = bytes[math.floor(i / 8) + 1], 7 - i % 8
    cells[i]:SetShown(math.floor(byte / 2 ^ bit) % 2 == 1)
  end
end

-- kind: one of Clip.KIND. f: kills, seconds, since, rung, run, grade, points, peak, flags.
-- True when the mark was drawn and the screenshot asked for.
function Clip.Mark(kind, f)
  f = f or {}
  if type(Screenshot) ~= "function" then return false end
  local ok, s = pcall(build)
  if not ok or not s then return false end
  serial = (serial + 1) % 256
  local seconds, since, peak = clamp(f.seconds, 65535), clamp(f.since, 65535), clamp(f.peak, 65535)
  local b = {
    MAGIC, VERSION * 16 + clamp(kind, 15), clamp(f.kills, 255),
    math.floor(seconds / 256), seconds % 256, math.floor(since / 256), since % 256,
    clamp(f.rung, 255), clamp(f.run, 255), clamp(f.grade, 5), clamp(f.points, 255), clamp(f.flags, 255),
    math.floor(peak / 256), peak % 256, serial,
  }
  b[16] = crc8(b)
  Clip.last = b
  paint(b)
  s:Show()
  turn = turn + 1
  local mine = turn
  C_Timer.After(0.1, function() pcall(Screenshot) end)
  C_Timer.After(SHOWN, function() if turn == mine then s:Hide() end end)
  return true
end

function Clip.Showing() return strip ~= nil and strip:IsShown() end

-- /godslayer clip: keep what just happened, hunt or no hunt
function Clip.Command()
  if Clip.Mark(Clip.KIND.manual) then
    ns.Print("Clip marked. A recorder watching your Screenshots folder keeps the last minute.")
  else
    ns.Print("This client would not take the screenshot the clip mark rides on.")
  end
end
