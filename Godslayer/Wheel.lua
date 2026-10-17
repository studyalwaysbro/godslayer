-- Godslayer chat wheel: Dota's, with lines of our own.
--
-- Hold the key you bound to it (Key Bindings, AddOns, Godslayer), point toward a line and let
-- go: it is said out loud. Or /godslayer wheel and click one. The first ring is for showing off,
-- the second for calling the fight; right-click or the mouse wheel turns between them.
--
-- You always hear it. The people in your party or raid who run Godslayer hear it too, in the
-- same voice, with your name and the words in their chat. Nothing is written in any chat
-- channel, and nobody outside your group hears a thing. Each sender is rationed, so a friend
-- holding the key down is one line and not a song. /godslayer hype wheel off and you hear only
-- your own.

local _, ns = ...
local plain, try = ns.plain, ns.try

local Wheel = {}
ns.Wheel = Wheel

local SOUNDS = "Interface\\AddOns\\Godslayer\\Sounds\\wheel\\"
local ART = "Interface\\AddOns\\Godslayer\\Art\\"
local PAGE, RADIUS, DEAD_ZONE = 8, 112, 34
local OWN_GAP = 3                         -- your own lines, at most this often
local HEARD_GAP, HEARD_PER_MINUTE = 3, 8  -- and each groupmate's
local ALL_PER_MINUTE = 10                 -- and a whole raid's together, one finished before the next
local PAGES = { "Banter", "Callouts" }

local function count() local n = 0 while ns.WHEEL and ns.WHEEL.clips["wheel_" .. (n + 1)] do n = n + 1 end return n end
Wheel.Count = count

local function opts() return ns.Hype and ns.Hype.Opts() or {} end

local function text(n) return ns.WHEEL and ns.WHEEL.text and ns.WHEEL.text["wheel_" .. n] end
local function label(n) return ns.WHEEL and ns.WHEEL.label and ns.WHEEL.label["wheel_" .. n] or text(n) end

local heardHandle -- a groupmate's line in the air, which your own kill call may cut short
local function play(n)
  if not (ns.WHEEL and ns.WHEEL.clips["wheel_" .. n]) then return false end
  if plain(try(GetCVar, "Sound_EnableAllSound")) == "0" then return false end
  local ok, handle = try(PlaySoundFile, SOUNDS .. "wheel_" .. n .. ".ogg", opts().channel or "Master")
  return plain(ok) and true or false, plain(handle)
end

function Wheel.Hush()
  if heardHandle then try(StopSound, heardHandle, 150) end
  heardHandle = nil
end

-- A line of yours. Heard by you, and sent to your group.
local lastOwn, ownLog = -1000, {}
function Wheel.Say(n)
  n = tonumber(n)
  if not n or not text(n) then return false end
  local now = GetTime()
  while ownLog[1] and now - ownLog[1] > 60 do table.remove(ownLog, 1) end
  -- the same rationing your groupmates' addons hold you to, so nothing you send is thrown away
  if now - lastOwn < OWN_GAP or #ownLog >= HEARD_PER_MINUTE then return false end
  lastOwn, ownLog[#ownLog + 1] = now, now
  play(n)
  print(("|cffff7d0a[Wheel]|r |cffffd100%s|r: %s"):format(ns.myName or "You", text(n)))
  if ns.Comm and ns.Comm.Wheel then pcall(ns.Comm.Wheel, n) end
  return true
end

-- A groupmate's line arrived.
local heard, everyone, heardBusy = {}, {}, -1000
function Wheel.Heard(who, n)
  n = tonumber(n)
  if type(who) ~= "string" or not n or n ~= math.floor(n) or not text(n) then return false end
  local o = opts()
  if o.on == false or o.wheel == false then return false end
  local now, log = GetTime(), heard[who]
  if not log then log = {} heard[who] = log end
  while log[1] and now - log[1] > 60 do table.remove(log, 1) end
  if #log >= HEARD_PER_MINUTE or (log[#log] and now - log[#log] < HEARD_GAP) then return false end
  while everyone[1] and now - everyone[1] > 60 do table.remove(everyone, 1) end
  if #everyone >= ALL_PER_MINUTE or now < heardBusy then return false end
  -- your own announcer comes first: a groupmate's line never talks over a kill being called
  if ns.Hype and ns.Hype.Busy and ns.Hype.Busy() then return false end
  log[#log + 1], everyone[#everyone + 1] = now, now
  heardBusy = now + (ns.WHEEL.clips["wheel_" .. n] or 1.5) + 0.5
  local _, handle = play(n)
  heardHandle = handle
  print(("|cffff7d0a[Wheel]|r |cffffd100%s|r: %s"):format(who, text(n)))
  return true
end

-- THE RING --------------------------------------------------------------------
local frame, buttons, page, holding, hot = nil, {}, 1, false, nil

local function slot(i) return (page - 1) * PAGE + i end

local function paint()
  if not frame then return end
  frame.title:SetText(PAGES[page] or "")
  for i, b in ipairs(buttons) do
    local n = slot(i)
    local words = label(n)
    b:SetShown(words ~= nil)
    if words then b.text:SetText(words) end
    local on = hot == i
    b.text:SetTextColor(on and 1 or 0.92, on and 0.82 or 0.9, on and 0.2 or 0.86)
    if b.glow then b.glow:SetAlpha(on and 0.9 or 0) end
  end
end

-- which slice the cursor is pointing at, from the middle of the ring: 1 at the top, going round clockwise
local function pointed()
  local cx, cy = frame:GetCenter()
  local x, y = GetCursorPosition()
  local scale = frame:GetEffectiveScale()
  if not (cx and x and scale and scale > 0) then return nil end
  local dx, dy = x / scale - cx, y / scale - cy
  if dx * dx + dy * dy < DEAD_ZONE * DEAD_ZONE then return nil end
  local angle = math.deg(math.atan2(dx, dy)) % 360 -- 0 is straight up
  return math.floor((angle + 180 / PAGE) / (360 / PAGE)) % PAGE + 1
end

local function turnPage(step)
  local pages = math.max(1, math.ceil(count() / PAGE))
  page = (page - 1 + step) % pages + 1
  paint()
end

local function build()
  if frame then return frame end
  frame = CreateFrame("Frame", "GodslayerWheel", UIParent)
  frame:SetSize(340, 340)
  frame:SetFrameStrata("DIALOG")
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:EnableMouseWheel(true)
  frame:Hide()
  local ring = frame:CreateTexture(nil, "BACKGROUND")
  ring:SetTexture(ART .. "ring")
  ring:SetBlendMode("ADD")
  ring:SetAllPoints()
  ring:SetVertexColor(1, 0.5, 0.1)
  ring:SetAlpha(0.35)
  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.title:SetPoint("CENTER")
  local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  hint:SetPoint("TOP", frame.title, "BOTTOM", 0, -4)
  hint:SetText("right-click: more")
  for i = 1, PAGE do
    local b = CreateFrame("Button", nil, frame)
    b:SetSize(132, 34)
    local angle = math.rad((i - 1) * 360 / PAGE)
    b:SetPoint("CENTER", frame, "CENTER", math.sin(angle) * RADIUS, math.cos(angle) * RADIUS)
    local glow = b:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture(ART .. "glow")
    glow:SetBlendMode("ADD")
    glow:SetAllPoints()
    glow:SetVertexColor(1, 0.55, 0.1)
    glow:SetAlpha(0)
    b.glow = glow
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.text:SetPoint("CENTER")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnEnter", function() hot = i paint() end)
    b:SetScript("OnClick", function(_, mouse)
      if mouse == "RightButton" then turnPage(1) return end
      Wheel.Say(slot(i))
      Wheel.Close()
    end)
    buttons[i] = b
  end
  frame:SetScript("OnMouseUp", function(_, mouse) if mouse == "RightButton" then turnPage(1) end end)
  frame:SetScript("OnMouseWheel", function(_, delta) turnPage(delta > 0 and -1 or 1) end)
  frame:SetScript("OnUpdate", function()
    if not holding then return end
    local p = pointed()
    if p ~= hot then hot = p paint() end
  end)
  if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "GodslayerWheel" end -- Escape closes it
  return frame
end

-- atCursor: opened by the key, centred where you are looking
function Wheel.Open(atCursor)
  if count() == 0 then ns.Print("The chat wheel has no lines in this build.") return false end
  build()
  frame:ClearAllPoints()
  local x, y = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale()
  if atCursor and x and scale and scale > 0 then
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
  else
    frame:SetPoint("CENTER")
  end
  hot = nil
  paint()
  frame:Show()
  return true
end

function Wheel.Close()
  holding, hot = false, nil
  if frame then frame:Hide() end
end

function Wheel.Shown() return frame ~= nil and frame:IsShown() end

-- The key binding: held down, the ring; let go, the line you were pointing at.
function Godslayer_Wheel(keystate)
  if keystate == "down" then
    holding = Wheel.Open(true) and true or false
  else
    -- let go in the middle and nothing is said, as in Dota
    local chosen = holding and frame and frame:IsShown() and pointed()
    Wheel.Close()
    if chosen then Wheel.Say(slot(chosen)) end
  end
end

BINDING_HEADER_GODSLAYER = "Godslayer"
BINDING_NAME_GODSLAYER_WHEEL = "Chat wheel (hold, point, let go)"

function Wheel.Command(rest)
  local n = tonumber(rest)
  if n then
    if not Wheel.Say(n) then ns.Print("No line " .. n .. ", or too soon after the last one.") end
    return
  end
  if rest == "list" then
    ns.Print("Chat wheel lines (/godslayer wheel <number> says one):")
    for i = 1, count() do print(("  |cffffd100%d|r  %s"):format(i, text(i))) end
    return
  end
  if Wheel.Shown() then Wheel.Close() else Wheel.Open(false) end
end
