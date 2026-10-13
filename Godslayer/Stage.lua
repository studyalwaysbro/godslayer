-- Godslayer stage: everything you see. The announcer decides what happened; this draws it.
--
-- THE BANNER. The words slam in from large, land, and throw light: a streak across, a glow
-- behind, a ring going out. Bigger moments get more of it (rays turning behind the words, claw
-- marks for kills in a row, the edges of the screen flashing the colour of the call), so a
-- tenth kill does not look like a first.
--
-- THE FUSE. While a hunt is on, a thin bar under the banner burns down the time you have left
-- to kill again. It refills on every kill and turns red and beats when it is nearly out.
--
-- THE CARD. When a hunt of any size ends, what it came to, and a grade stamped on it.
--
-- All of it is light drawn by tools/build_art.py: white shapes tinted to the moment and added
-- over the game. Nothing covers the middle of the screen. /godslayer hype fx off goes back to
-- plain words that appear and fade, and anything this client refuses to animate is skipped.

local ADDON, ns = ...

local Stage = {}
ns.Stage = Stage

local ART = "Interface\\AddOns\\Godslayer\\Art\\"
local HOLD = { 2.6, 3.0, 3.4, 4.2, 5.0 } -- seconds the words stay, by size of moment
local FUSE_WIDTH, FUSE_LOW = 250, 10

local banner, pulse, fuse, built, failed
local turn = 0

local function fx() return not (GodslayerDB and GodslayerDB.opts and GodslayerDB.opts.hype and GodslayerDB.opts.hype.fx == false) end

-- One texture of light, added over whatever is behind it.
local function light(parent, file, width, height, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetTexture(ART .. file)
  t:SetBlendMode("ADD")
  t:SetSize(width, height)
  t:SetAlpha(0)
  return t
end

-- An animation group, built from a list of steps. A client that lacks a step leaves it out.
-- step: { kind, order, seconds, delay, from, to, smoothing }; Scale takes from/to as one number or {x, y}
local function animate(region, steps, looping)
  local group = region:CreateAnimationGroup()
  if not group then return nil end
  if looping then pcall(group.SetLooping, group, looping) end
  -- without this a region snaps back to the alpha it had before the animation the moment it ends
  pcall(group.SetToFinalAlpha, group, true)
  for _, s in ipairs(steps) do
    local a = group:CreateAnimation(s[1])
    if a then
      pcall(function()
        a:SetOrder(s[2])
        a:SetDuration(s[3])
        if s[4] and s[4] > 0 then a:SetStartDelay(s[4]) end
        if s[1] == "Alpha" then
          a:SetFromAlpha(s[5]) a:SetToAlpha(s[6])
        elseif s[1] == "Scale" then
          local from, to = s[5], s[6]
          if type(from) == "number" then from = { from, from } end
          if type(to) == "number" then to = { to, to } end
          a:SetScaleFrom(from[1], from[2]) a:SetScaleTo(to[1], to[2])
        elseif s[1] == "Rotation" then
          a:SetDegrees(s[6])
        elseif s[1] == "Translation" then
          a:SetOffset(s[5], s[6])
        end
        if s[7] then a:SetSmoothing(s[7]) end
      end)
    end
  end
  return group
end

local function play(group)
  if not group then return end
  pcall(group.Stop, group)
  pcall(group.Play, group)
end

local function stop(group)
  if group then pcall(group.Stop, group) end
end

local function build()
  local f = CreateFrame("Frame", "GodslayerHypeBanner", UIParent)
  f:SetSize(760, 120)
  f:SetPoint("TOP", UIParent, "TOP", 0, -150)
  f:SetFrameStrata("HIGH")
  local font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

  f.plate = f:CreateTexture(nil, "BACKGROUND")
  f.plate:SetTexture(ART .. "plate")
  f.plate:SetVertexColor(0, 0, 0)
  f.plate:SetSize(820, 150)
  f.plate:SetPoint("CENTER", f, "TOP", 0, -40)
  f.plate:SetAlpha(0)

  f.rays = light(f, "rays", 460, 460, "BORDER")
  f.rays:SetPoint("CENTER", f, "TOP", 0, -24)
  f.glow = light(f, "glow", 640, 210, "BORDER")
  f.glow:SetPoint("CENTER", f, "TOP", 0, -24)
  f.slash = light(f, "slash", 440, 220, "BORDER")
  f.slash:SetPoint("CENTER", f, "TOP", 0, -24)
  f.ring = light(f, "ring", 200, 200, "ARTWORK")
  f.ring:SetPoint("CENTER", f, "TOP", 0, -24)
  f.flare = light(f, "flare", 980, 46, "ARTWORK")
  f.flare:SetPoint("CENTER", f, "TOP", 0, -24)

  -- the words live in a frame of their own, so they can be thrown at the screen
  f.word = CreateFrame("Frame", nil, f)
  f.word:SetSize(760, 50)
  f.word:SetPoint("TOP", f, "TOP", 0, 0)
  f.title = f.word:CreateFontString(nil, "OVERLAY")
  -- the game says whether it took the font; if the heavy outline is refused, the plain one is not
  if f.title:SetFont(font, 44, "THICKOUTLINE") == false then f.title:SetFont(font, 44, "OUTLINE") end
  f.title:SetPoint("CENTER", f.word, "CENTER", 0, 0)
  f.line = f:CreateFontString(nil, "OVERLAY")
  f.line:SetFont(font, 17, "OUTLINE")
  f.line:SetPoint("TOP", f.word, "BOTTOM", 0, -4)
  f.line:SetTextColor(1, 1, 1)
  -- the grade on a hunt card: stamped on a moment after the rest
  f.stamp = CreateFrame("Frame", nil, f)
  f.stamp:SetSize(120, 90)
  f.stamp:SetPoint("LEFT", f.word, "RIGHT", -150, -14)
  f.grade = f.stamp:CreateFontString(nil, "OVERLAY")
  if f.grade:SetFont(font, 66, "THICKOUTLINE") == false then f.grade:SetFont(font, 66, "OUTLINE") end
  f.grade:SetPoint("CENTER", f.stamp, "CENTER", 0, 0)
  f.stamp:Hide()

  f.anim = {
    slam = animate(f.word, { { "Alpha", 1, 0.07, 0, 0, 1 }, { "Scale", 1, 0.13, 0, 1.9, 1, "IN" },
                             { "Scale", 2, 0.07, 0, 1, 1.07, "OUT" }, { "Scale", 3, 0.13, 0, 1.07, 1, "IN" } }),
    line = animate(f.line, { { "Alpha", 1, 0.22, 0.2, 0, 1 } }),
    plate = animate(f.plate, { { "Alpha", 1, 0.15, 0, 0, 0.55 } }),
    flare = animate(f.flare, { { "Alpha", 1, 0.05, 0.11, 0, 1 }, { "Scale", 1, 0.5, 0.11, { 0.25, 1 }, { 1.15, 1 }, "OUT" },
                               { "Alpha", 2, 0.55, 0, 1, 0, "IN" } }),
    glow = animate(f.glow, { { "Alpha", 1, 0.06, 0.1, 0, 0.95 }, { "Alpha", 2, 0.9, 0, 0.95, 0.3, "OUT" } }),
    ring = animate(f.ring, { { "Alpha", 1, 0.04, 0.12, 0, 0.9 }, { "Scale", 1, 0.55, 0.12, 0.4, 2.6, "OUT" }, { "Alpha", 2, 0.4, 0.15, 0.9, 0 } }),
    slash = animate(f.slash, { { "Alpha", 1, 0.05, 0.14, 0, 0.85 }, { "Scale", 1, 0.16, 0.14, { 0.2, 1 }, { 1, 1 }, "OUT" },
                               { "Alpha", 2, 1.2, 0.5, 0.85, 0, "IN" } }),
    raysIn = animate(f.rays, { { "Alpha", 1, 0.25, 0.12, 0, 0.5 } }),
    raysTurn = animate(f.rays, { { "Rotation", 1, 40, 0, 0, 360 } }, "REPEAT"),
    out = animate(f, { { "Alpha", 1, 0.6, 0, 1, 0, "IN" }, { "Translation", 1, 0.6, 0, 0, 10, "IN" } }),
    stamp = animate(f.stamp, { { "Alpha", 1, 0.05, 0, 0, 1 }, { "Scale", 1, 0.12, 0, 2.6, 1, "IN" }, { "Scale", 2, 0.06, 0, 1, 1.1, "OUT" },
                               { "Scale", 3, 0.1, 0, 1.1, 1, "IN" } }),
  }
  -- what an animation leaves behind when it ends is whatever the region was set to before it ran
  if f.anim.out then pcall(f.anim.out.SetScript, f.anim.out, "OnFinished", function() f:Hide() end) end
  f:Hide()

  -- the edges of the screen, for the moments that deserve the whole of it
  local p = CreateFrame("Frame", "GodslayerStagePulse", UIParent)
  p:SetAllPoints(UIParent)
  p:SetFrameStrata("BACKGROUND")
  if p.EnableMouse then p:EnableMouse(false) end
  p.tex = p:CreateTexture(nil, "BACKGROUND")
  p.tex:SetTexture(ART .. "vignette")
  p.tex:SetBlendMode("ADD")
  p.tex:SetAllPoints(p)
  p.tex:SetAlpha(0)
  p.anim = {}
  p:Hide()

  -- the fuse
  local m = CreateFrame("Frame", "GodslayerHuntFuse", UIParent)
  m:SetSize(FUSE_WIDTH, 16)
  m:SetPoint("TOP", UIParent, "TOP", 0, -240)
  m:SetFrameStrata("HIGH")
  m.back = m:CreateTexture(nil, "BACKGROUND")
  m.back:SetTexture(ART .. "bar")
  m.back:SetVertexColor(0, 0, 0)
  m.back:SetAlpha(0.6)
  m.back:SetSize(FUSE_WIDTH + 6, 9)
  m.back:SetPoint("LEFT", m, "LEFT", -3, 0)
  m.fill = m:CreateTexture(nil, "ARTWORK")
  m.fill:SetTexture(ART .. "bar")
  m.fill:SetSize(FUSE_WIDTH, 5)
  m.fill:SetPoint("LEFT", m, "LEFT", 0, 0)
  m.spark = m:CreateTexture(nil, "OVERLAY")
  m.spark:SetTexture(ART .. "spark")
  m.spark:SetBlendMode("ADD")
  m.spark:SetSize(26, 26)
  m.count = m:CreateFontString(nil, "OVERLAY")
  m.count:SetFont(font, 15, "OUTLINE")
  m.count:SetPoint("RIGHT", m, "LEFT", -8, 0)
  m.name = m:CreateFontString(nil, "OVERLAY")
  m.name:SetFont(font, 11, "OUTLINE")
  m.name:SetPoint("LEFT", m, "RIGHT", 8, 0)
  m.name:SetTextColor(0.8, 0.8, 0.8)
  m.anim = { kick = animate(m.spark, { { "Scale", 1, 0.08, 0, 1, 2.4, "OUT" }, { "Scale", 2, 0.25, 0, 2.4, 1, "IN" } }) }
  m:Hide()

  banner, pulse, fuse = f, p, m
end

local function ready()
  if built then return banner ~= nil end
  built = true
  local ok, err = pcall(build)
  if not ok then
    failed = true
    if ns.Log then ns.Log("error", "stage: " .. tostring(err)) end
    -- words and nothing else: the smallest banner there is
    if not banner then
      local okPlain, f = pcall(function()
        local b = CreateFrame("Frame", "GodslayerHypeBanner", UIParent)
        b:SetSize(760, 100)
        b:SetPoint("TOP", UIParent, "TOP", 0, -150)
        b:SetFrameStrata("HIGH")
        local font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
        b.title = b:CreateFontString(nil, "OVERLAY")
        b.title:SetFont(font, 44, "OUTLINE")
        b.title:SetPoint("TOP", 0, 0)
        b.line = b:CreateFontString(nil, "OVERLAY")
        b.line:SetFont(font, 17, "OUTLINE")
        b.line:SetPoint("TOP", b.title, "BOTTOM", 0, -6)
        b:Hide()
        return b
      end)
      banner = okPlain and f or nil
    end
  end
  return banner ~= nil
end

-- The edges of the screen flash a colour and let go. strength 0..1.
function Stage.Pulse(color, strength, seconds)
  if not ready() or failed or not pulse or not fx() then return end
  strength = math.max(0, math.min(1, strength or 0.4))
  local key = math.floor(strength * 10 + 0.5) .. ":" .. (seconds or 0.8)
  -- one group per strength, made the first time it is needed
  local group = pulse.anim[key]
  if not group then
    group = animate(pulse.tex, { { "Alpha", 1, 0.07, 0, 0, strength, "OUT" }, { "Alpha", 2, seconds or 0.8, 0, strength, 0, "IN" } })
    pulse.anim[key] = group
    if group then pcall(group.SetScript, group, "OnFinished", function() pulse:Hide() end) end
  end
  for _, other in pairs(pulse.anim) do stop(other) end
  pulse.tex:SetVertexColor(color[1], color[2], color[3])
  pulse:Show()
  play(group)
  Stage.pulses = (Stage.pulses or 0) + 1
end

-- The words. size 1 (a kill) to 5 (the King is dead); claws = kills in a row to mark behind them.
-- opts: { size, claws, grade, gradeColor, hold }
function Stage.Banner(title, color, line, opts)
  if not ready() then return end
  opts = opts or {}
  local size = math.max(1, math.min(5, opts.size or 1))
  local f = banner
  turn = turn + 1
  local mine = turn
  if not failed then for _, group in pairs(f.anim) do stop(group) end end
  if type(UIFrameFadeRemoveFrame) == "function" then pcall(UIFrameFadeRemoveFrame, f) end
  f.title:SetText(title)
  -- the words are the colour of the moment pushed toward white, so they stand out of their own light
  f.title:SetTextColor(color[1] + (1 - color[1]) * 0.35, color[2] + (1 - color[2]) * 0.35, color[3] + (1 - color[3]) * 0.35)
  f.line:SetText(line or "")
  f:SetAlpha(1)
  f:Show()
  Stage.size, Stage.claws, Stage.grade = size, opts.claws, opts.grade
  local hold = opts.hold or HOLD[size]

  if not failed and fx() then
    for _, name in ipairs({ "glow", "flare", "ring", "slash", "rays" }) do
      f[name]:SetVertexColor(color[1], color[2], color[3])
      f[name]:SetAlpha(0)
    end
    f.line:SetAlpha(0) -- it fades in a beat after the words land
    play(f.anim.slam)
    play(f.anim.line)
    play(f.anim.plate)
    play(f.anim.flare)
    play(f.anim.glow)
    if size >= 2 then play(f.anim.ring) end
    if opts.claws and opts.claws >= 2 then play(f.anim.slash) end
    if size >= 3 then
      play(f.anim.raysIn)
      play(f.anim.raysTurn)
      Stage.Pulse(color, size >= 5 and 0.6 or (size == 4 and 0.45 or 0.3), size >= 4 and 1.1 or 0.7)
    end
    if opts.grade then
      f.grade:SetText(opts.grade)
      local gc = opts.gradeColor or color
      f.grade:SetTextColor(gc[1], gc[2], gc[3])
      f.stamp:Hide()
      C_Timer.After(opts.stampAfter or 0.7, function()
        if mine ~= turn then return end
        f.stamp:Show()
        play(f.anim.stamp)
        if opts.onStamp then pcall(opts.onStamp) end
      end)
    else
      f.stamp:Hide()
    end
    C_Timer.After(hold, function()
      if mine ~= turn then return end
      if f.anim.out then play(f.anim.out) else f:Hide() end
    end)
    return
  end

  -- plain: the words appear, wait and fade
  f.line:SetAlpha(1)
  if f.stamp then
    if opts.grade then f.grade:SetText(opts.grade) f.stamp:Show() else f.stamp:Hide() end
  end
  C_Timer.After(hold + 1, function()
    if mine ~= turn then return end
    if type(UIFrameFadeOut) == "function" and pcall(UIFrameFadeOut, f, 0.8, 1, 0) then
      C_Timer.After(0.85, function() if mine == turn then f:Hide() end end)
    else
      f:Hide()
    end
  end)
end

-- The line under the words, corrected while it is still up: a kill that has just got its name.
function Stage.Reline(find, with)
  if not (banner and banner:IsShown() and banner.line) then return false end
  local text = banner.line:GetText()
  if type(text) ~= "string" then return false end
  local at, to = text:find(find, 1, true)
  if not at then return false end
  banner.line:SetText(text:sub(1, at - 1) .. with .. text:sub(to + 1))
  return true
end

-- THE FUSE -----------------------------------------------------------------------
local fuseState -- { ends, window, color, low }

local function fuseUpdate()
  local s, m = fuseState, fuse
  if not s or not m then return end
  local left = s.ends - GetTime()
  if left <= 0 then
    m:Hide()
    fuseState = nil
    return
  end
  local part = math.max(0.004, math.min(1, left / s.window))
  m.fill:SetWidth(FUSE_WIDTH * part)
  m.spark:SetPoint("CENTER", m, "LEFT", FUSE_WIDTH * part, 0)
  local low = left <= FUSE_LOW
  if low then
    -- a beat a second, faster at the very end
    local beat = 0.55 + 0.45 * math.abs(math.sin(GetTime() * (left < 4 and 7 or 3.6)))
    m.fill:SetVertexColor(1, 0.12, 0.08)
    m.fill:SetAlpha(beat)
    m.spark:SetVertexColor(1, 0.3, 0.2)
  else
    m.fill:SetVertexColor(s.color[1], s.color[2], s.color[3])
    m.fill:SetAlpha(0.95)
    m.spark:SetVertexColor(1, 0.9, 0.6)
  end
  m.spark:SetAlpha(1)
  if low and not s.low then
    s.low = true
    Stage.Pulse({ 1, 0.1, 0.05 }, 0.2, 1.2)
  end
end

-- Lights the fuse, or relights it: seconds to burn, the hunt's count and what it is called.
function Stage.Fuse(seconds, kills, name, color)
  if not ready() or failed or not fuse then return end
  local o = GodslayerDB and GodslayerDB.opts and GodslayerDB.opts.hype
  if not fx() or (o and o.fuse == false) then Stage.FuseOut() return end
  fuseState = { ends = GetTime() + seconds, window = seconds, color = color or { 1, 0.8, 0.2 } }
  fuse.count:SetText("x" .. kills)
  fuse.count:SetTextColor(fuseState.color[1], fuseState.color[2], fuseState.color[3])
  fuse.name:SetText(name or "")
  if not fuse.ticking then
    fuse.ticking = true
    fuse:SetScript("OnUpdate", function() pcall(fuseUpdate) end)
  end
  fuse:Show()
  fuseUpdate()
  play(fuse.anim.kick)
end

function Stage.FuseOut()
  fuseState = nil
  if fuse then fuse:Hide() end
end

function Stage.FuseLeft() return fuseState and math.max(0, fuseState.ends - GetTime()) or nil end
Stage.FuseTick = fuseUpdate -- for the tests, which have no frames per second

function Stage.Ready() return ready() and not failed end
