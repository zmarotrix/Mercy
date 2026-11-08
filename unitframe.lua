-- One unit frame: a secure unit button with a fixed unit token (party2, raid17, target), and everything drawn on it.
-- The token never changes, so neither do its click attributes or its Blizzard aura container. The game shows and
-- hides it by whether the unit exists (RegisterUnitWatch), securely, in combat too.
--
-- Health, power, incoming heals and absorbs are always secret on this client: they go straight into status bars.
-- Text goes through SetFormattedText, colours through curves, range through SetAlphaFromBoolean.

local Core = NorgannonCore
local M = Mercy
if M.disabled then return end
local UI = Core.UI

local UF = {}
M.UF = UF
UF.all = {}
UF.byUnit = {}

UF.LAYOUTS = {
  standard = { w = 120, h = 46, power = 4, font = 12, icon = 14 },
  compact = { w = 96, h = 40, power = 3, font = 11, icon = 12 },
  wide = { w = 170, h = 42, power = 4, font = 13, icon = 16 },
  tiny = { w = 72, h = 26, power = 0, font = 10, icon = 10 },
  classic = { w = 140, h = 40, power = 7, font = 12, icon = 14 },
}
UF.LAYOUT_NAMES = { { "standard", "Standard" }, { "compact", "Compact" }, { "wide", "Wide" }, { "tiny", "Tiny" }, { "classic", "Classic" } }

-- The client's own modern raid frame art (CompactUnitFrame.xml): soft gradient fills, a rounded background, and rounded
-- target and aggro frames. Plain textures stand in if a client lacks an atlas.
local FLAT = "Interface\\Buttons\\WHITE8X8"
local ART = {
  health = "RaidFrame-Hp-Fill", healthBg = "raidframe-hp-bg-white",
  power = "_RaidFrame-Resource-Fill", powerBg = "_RaidFrame-Resource-Background",
  target = "RaidFrame-TargetFrame", aggro = "RaidFrame-AgroFrame",
}
local function hasAtlas(name)
  local info = M.Plain(M.Fn("C_Texture", "GetAtlasInfo"), name)
  return type(info) == "table"
end
---Puts an atlas on a texture, or a flat colour if the client hasn't got it.
local function art(tex, name)
  if hasAtlas(name) and tex.SetAtlas then tex:SetAtlas(name, false) return true end
  tex:SetTexture(FLAT)
  return false
end
UF.POWER_COLORS = { MANA = { 0.3, 0.55, 1 }, RAGE = { 0.9, 0.25, 0.25 }, ENERGY = { 1, 0.85, 0.25 }, FOCUS = { 1, 0.6, 0.25 },
  RUNIC_POWER = { 0, 0.82, 1 } }
-- the client's own small role icons (the ones its raid frames use)
local ROLE_ATLAS = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer", DAMAGER = "roleicon-tiny-dps" }
local HEALER_CLASSES = { PRIEST = true, DRUID = true, PALADIN = true, SHAMAN = true }

-------------------------------------------------------------------------------------------
-- Building
-------------------------------------------------------------------------------------------

local function statusbar(parent, r, g, b, a, atlas)
  local s = CreateFrame("StatusBar", nil, parent)
  if atlas and hasAtlas(atlas) then s:SetStatusBarTexture(atlas) else s:SetStatusBarTexture(FLAT) end
  s:SetStatusBarColor(r, g, b, a or 1)
  s:SetMinMaxValues(0, 1)
  s:SetValue(0)
  return s
end

---The highlight (Mercy's): a 2 px border and an inner glow in the debuff's colour, pulsing gently.
local function makeHighlight(parent)
  local hl = CreateFrame("Frame", nil, parent)
  hl:SetAllPoints()
  hl:SetFrameLevel(parent:GetFrameLevel() + 8)
  local parts = {}
  local function edge(p1, p2, w, h)
    local t = hl:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(1, 1, 1, 1)
    t:SetPoint(p1)
    t:SetPoint(p2)
    if w then t:SetWidth(w) end
    if h then t:SetHeight(h) end
    parts[#parts + 1] = t
  end
  edge("TOPLEFT", "TOPRIGHT", nil, 2)
  edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 2)
  edge("TOPLEFT", "BOTTOMLEFT", 2, nil)
  edge("TOPRIGHT", "BOTTOMRIGHT", 2, nil)
  local glow = hl:CreateTexture(nil, "ARTWORK")
  glow:SetAllPoints()
  glow:SetTexture("Interface\\Buttons\\WHITE8X8")
  if glow.SetGradient and CreateColor then
    glow:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.35))
  else
    glow:SetAlpha(0.2)
  end
  parts[#parts + 1] = glow
  hl.parts = parts
  local ag = hl.CreateAnimationGroup and hl:CreateAnimationGroup()
  if ag then
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    if a then
      a:SetFromAlpha(1) a:SetToAlpha(0.55) a:SetDuration(0.7)
      hl:SetScript("OnShow", function() ag:Play() end)
      hl:SetScript("OnHide", function() ag:Stop() end)
    end
  end
  function hl:SetColor(r, g, b)
    for _, t in ipairs(parts) do t:SetVertexColor(r, g, b, 1) end
  end
  function hl:SetSecretColor(color)
    for _, t in ipairs(parts) do
      if not M.Set(t, "SetVertexColor", color:GetRGBA()) then t:SetVertexColor(1, 1, 1, 1) end
    end
  end
  hl:Hide()
  return hl
end

local function makeDebuffIcon(b, i)
  local f = CreateFrame("Frame", nil, b.content)
  f:SetFrameLevel(b.content:GetFrameLevel() + 6)
  if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end   -- clicks fall through to the unit button
  f:EnableMouse(true)
  f.border = f:CreateTexture(nil, "BACKGROUND")
  f.border:SetAllPoints()
  f.border:SetColorTexture(1, 1, 1, 1)
  f.texture = f:CreateTexture(nil, "ARTWORK")
  f.texture:SetPoint("TOPLEFT", 1, -1)
  f.texture:SetPoint("BOTTOMRIGHT", -1, 1)
  f.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
  f.cooldown:SetAllPoints(f.texture)
  if f.cooldown.SetHideCountdownNumbers then f.cooldown:SetHideCountdownNumbers(true) end
  if f.cooldown.SetDrawEdge then f.cooldown:SetDrawEdge(false) end
  f.count = f:CreateFontString(nil, "OVERLAY")
  f.count:SetFontObject(UI.Font("bold", 9, "OUTLINE"))
  f.count:SetPoint("BOTTOMRIGHT", 2, -1)
  f:SetScript("OnEnter", function(self)
    if not self.auraID then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    if not M.Set(GameTooltip, "SetUnitDebuffByAuraInstanceID", b.unit, self.auraID) then GameTooltip:Hide() return end
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f:Hide()
  return f
end

---Creates the button for one unit token. Out of combat only (it's a protected frame).
function UF:Create(parent, unit, name)
  local b = CreateFrame("Button", name, parent, "SecureUnitButtonTemplate")
  b.unit = unit
  b:SetAttribute("unit", unit)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetSize(120, 44)

  b.content = CreateFrame("Frame", nil, b)
  b.content:SetAllPoints()
  -- the game's soft raid frame background, dark: it's what shows where health is missing
  b.bg = b.content:CreateTexture(nil, "BACKGROUND", nil, -7)
  b.bg:SetAllPoints()
  art(b.bg, ART.healthBg)
  b.bg:SetVertexColor(0.13, 0.13, 0.15, 1)

  -- health, with incoming heals and absorbs drawn after its fill; the clip keeps them inside the bar
  b.clip = CreateFrame("Frame", nil, b.content)
  if b.clip.SetClipsChildren then b.clip:SetClipsChildren(true) end
  b.health = statusbar(b.clip, M.GREEN[1], M.GREEN[2], M.GREEN[3], 1, ART.health)
  b.health:SetAllPoints(b.clip)
  b.incAll = statusbar(b.clip, 0.45, 0.95, 0.5, 0.35, ART.health)
  b.incMine = statusbar(b.clip, 0.65, 1, 0.7, 0.65, ART.health)
  b.absorb = statusbar(b.clip, 0.85, 0.9, 1, 0.55, ART.health)
  local fill = b.health:GetStatusBarTexture() or b.health
  for _, s in ipairs({ b.incAll, b.incMine }) do
    s:SetPoint("TOPLEFT", fill, "TOPRIGHT")
    s:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT")
  end
  local after = b.incAll:GetStatusBarTexture() or b.incAll
  b.absorb:SetPoint("TOPLEFT", after, "TOPRIGHT")
  b.absorb:SetPoint("BOTTOMLEFT", after, "BOTTOMRIGHT")

  b.powerBg = b.content:CreateTexture(nil, "BACKGROUND", nil, -6)
  art(b.powerBg, ART.powerBg)
  b.power = statusbar(b.content, 0.3, 0.55, 1, 1, ART.power)
  b.powerBg:SetAllPoints(b.power)

  -- text in the middle, as HealersMate has it: the name, and missing health under it. A plain soft shadow, no outline.
  local text = CreateFrame("Frame", nil, b.content)
  text:SetAllPoints()
  text:SetFrameLevel(b.content:GetFrameLevel() + 5)
  b.name = text:CreateFontString(nil, "OVERLAY")
  b.name:SetJustifyH("CENTER")
  if b.name.SetWordWrap then b.name:SetWordWrap(false) end
  b.value = text:CreateFontString(nil, "OVERLAY")
  b.value:SetJustifyH("CENTER")
  b.value:SetTextColor(1, 1, 1, 0.9)
  b.status = text:CreateFontString(nil, "OVERLAY")
  b.status:SetJustifyH("CENTER")
  b.status:SetTextColor(0.72, 0.72, 0.74)
  for _, fs in ipairs({ b.name, b.value, b.status }) do
    if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) fs:SetShadowColor(0, 0, 0, 0.9) end
  end
  b.role = text:CreateTexture(nil, "OVERLAY")
  b.role:SetSize(11, 11)
  b.role:SetPoint("TOPLEFT", b.clip, "TOPLEFT", 3, -3)
  b.raidIcon = text:CreateTexture(nil, "OVERLAY")
  b.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
  b.raidIcon:SetSize(12, 12)
  b.raidIcon:SetPoint("TOPRIGHT", b.clip, "TOPRIGHT", -3, -3)
  -- no UI.Glow here: its copies centre on the FontString and ghosted on these

  -- low health: a red wash whose strength comes from a curve, pulsing
  b.flashFrame = CreateFrame("Frame", nil, b.content)
  b.flashFrame:SetAllPoints(b.clip)
  b.flashFrame:SetFrameLevel(b.content:GetFrameLevel() + 3)
  b.flash = b.flashFrame:CreateTexture(nil, "ARTWORK")
  b.flash:SetAllPoints()
  b.flash:SetColorTexture(1, 0.15, 0.1, 0.28)
  b.flash:SetAlpha(0)

  -- borders: your target and aggro, the game's own rounded raid frame art; thin lines if the client lacks it
  local function border(atlas, r, g, bl, level)
    local f = CreateFrame("Frame", nil, b.content)
    f:SetAllPoints()
    f:SetFrameLevel(b.content:GetFrameLevel() + level)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints()
    if hasAtlas(atlas) and t.SetAtlas then
      t:SetAtlas(atlas, false)
      if atlas == ART.aggro then t:SetVertexColor(r, g, bl, 1) end
    else
      t:SetTexture(nil)
      for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1, nil },
        { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
        local e = f:CreateTexture(nil, "OVERLAY")
        e:SetColorTexture(r, g, bl, 1)
        e:SetPoint(p[1]) e:SetPoint(p[2])
        if p[3] then e:SetWidth(p[3]) end
        if p[4] then e:SetHeight(p[4]) end
      end
    end
    f:SetAlpha(0)
    return f
  end
  b.aggro = border(ART.aggro, 0.9, 0.15, 0.1, 6)
  b.targetBorder = border(ART.target, 1, 1, 1, 7)

  b.highlight = makeHighlight(b.content)
  b.container = CreateFrame("Frame", nil, b.content)       -- Blizzard's aura container draws here (A)
  b.container:SetAllPoints(b.clip)
  b.container:SetFrameLevel(b.content:GetFrameLevel() + 4)
  b.debuffs = {}
  for i = 1, 5 do b.debuffs[i] = makeDebuffIcon(b, i) end

  b:SetScript("OnEnter", function(self) if M.Tooltip then M.Tooltip:Show(self) end end)
  b:SetScript("OnLeave", function(self) if M.Tooltip then M.Tooltip:Hide(self) end end)
  b:SetScript("PostClick", function(self, mouse, down) M.Binds:PostClick(self, mouse, down) end)

  local clique = rawget(_G, "ClickCastFrames")
  if type(clique) == "table" then clique[b] = true end

  self.all[#self.all + 1] = b
  self.byUnit[unit] = self.byUnit[unit] or {}
  table.insert(self.byUnit[unit], b)
  return b
end

---Sizes and places the parts for a layout. Children aren't protected, but this runs with the group layout, out of combat.
function UF:ApplyLayout(b, key)
  local L = self.LAYOUTS[key] or self.LAYOUTS.standard
  b.layout = L
  b:SetSize(L.w, L.h)
  b.iconSize = L.icon
  local PAD = 2   -- the bars sit inside the soft background, which shows round them
  local showPower = L.power > 0 and self:WantsPower(b)
  b.clip:ClearAllPoints()
  b.clip:SetPoint("TOPLEFT", b.content, "TOPLEFT", PAD, -PAD)
  b.clip:SetPoint("BOTTOMRIGHT", b.content, "BOTTOMRIGHT", -PAD, showPower and (L.power + PAD + 1) or PAD)
  b.power:ClearAllPoints()
  b.power:SetPoint("BOTTOMLEFT", b.content, "BOTTOMLEFT", PAD, PAD)
  b.power:SetPoint("BOTTOMRIGHT", b.content, "BOTTOMRIGHT", -PAD, PAD)
  b.power:SetHeight(math.max(L.power, 1))
  b.power:SetShown(showPower)
  b.powerBg:SetShown(showPower)
  local barWidth = L.w - PAD * 2
  for _, s in ipairs({ b.incAll, b.incMine, b.absorb }) do s:SetWidth(barWidth) end
  -- the name and, under it, missing health or the status, centred on the bar
  local twoLines = key ~= "tiny"
  b.name:SetFontObject(UI.Font("bold", L.font))
  b.name:SetWidth(L.w - 10)
  b.value:SetFontObject(UI.Font("body", L.font - 1))
  b.status:SetFontObject(UI.Font("body", L.font - 1))
  b.name:ClearAllPoints()
  b.value:ClearAllPoints()
  b.status:ClearAllPoints()
  if twoLines then
    b.name:SetPoint("BOTTOM", b.clip, "CENTER", 0, 0)
    b.value:SetPoint("TOP", b.clip, "CENTER", 0, -1)
    b.status:SetPoint("TOP", b.clip, "CENTER", 0, -1)
  else
    b.name:SetPoint("CENTER", b.clip, "CENTER", 0, 0)
    b.value:SetPoint("RIGHT", b.clip, "RIGHT", -3, 0)
    b.status:SetPoint("RIGHT", b.clip, "RIGHT", -3, 0)
  end
  b.value:SetShown(twoLines)
  for i, icon in ipairs(b.debuffs) do
    icon:SetSize(L.icon, L.icon)
    icon:ClearAllPoints()
    icon:SetPoint("BOTTOMRIGHT", b.clip, "BOTTOMRIGHT", -2 - (i - 1) * (L.icon + 2), 2)
  end
end

-------------------------------------------------------------------------------------------
-- Updating
-------------------------------------------------------------------------------------------

function UF:Role(b)
  if b.fake then return b.fake.role end
  local role = M.Plain(UnitGroupRolesAssigned, b.unit)
  if role and role ~= "NONE" then return role end
  local name = M.Plain(UnitName, b.unit)
  return name and M.Binds:Roles()[name] or nil
end

function UF:Class(b)
  if b.fake then return b.fake.class end
  local _, class = M.Plain(UnitClass, b.unit)
  if class then b.lastClass = class end
  return class or b.lastClass
end

function UF:WantsPower(b)
  local mode = M.db.power
  if mode == "none" then return false end
  if mode == "all" then return true end
  if b.fake then return b.fake.role == "HEALER" end
  local ptype = M.Plain(UnitPowerType, b.unit)
  if ptype ~= nil and ptype ~= 0 then return false end
  local role = self:Role(b)
  if role then return role == "HEALER" end
  return HEALER_CLASSES[self:Class(b) or ""] == true
end

function UF:UpdateName(b)
  local c = M.db.nameColor == "class" and (rawget(_G, "RAID_CLASS_COLORS") or {})[self:Class(b) or ""]
  if c then b.name:SetTextColor(c.r, c.g, c.b) else b.name:SetTextColor(1, 1, 1) end
  if b.fake then b.name:SetText(b.fake.name) return end
  local ok, name = pcall(UnitName, b.unit)
  if ok then M.Set(b.name, "SetText", name) end
end

function UF:UpdateColor(b)
  local mode = M.db.color
  if mode == "gradient" and not b.fake and M.Curves.gradient then
    local ok, color = pcall(UnitHealthPercent, b.unit, true, M.Curves.gradient)
    if ok and color and not M.IsSecret(color) and color.GetRGB and M.Set(b.health, "SetStatusBarColor", color:GetRGB()) then return end
  end
  if mode == "class" or (mode == "gradient" and b.fake) then
    local c = (rawget(_G, "RAID_CLASS_COLORS") or {})[self:Class(b) or ""]
    if c then b.health:SetStatusBarColor(c.r * 0.8, c.g * 0.8, c.b * 0.8) return end
  end
  b.health:SetStatusBarColor(M.GREEN[1], M.GREEN[2], M.GREEN[3])
end

function UF:UpdateHealth(b)
  local unit = b.unit
  if b.fake then
    local f = b.fake
    b.health:SetMinMaxValues(0, 100) b.health:SetValue(f.dead and 0 or f.hp)
    for _, s in ipairs({ b.incAll, b.incMine, b.absorb }) do s:SetMinMaxValues(0, 100) end
    b.incAll:SetValue(f.inc or 0) b.incMine:SetValue(f.incMine or 0) b.absorb:SetValue(f.absorb or 0)
    b.flash:SetAlpha(M.db.lowHealth and not f.dead and f.hp < 25 and 1 or 0)
    if M.db.text == "none" or f.dead or f.hp >= 100 then b.value:SetText("")
    elseif M.db.text == "percent" then b.value:SetFormattedText("%d%%", f.hp)
    else b.value:SetFormattedText("-%d", (100 - f.hp) * 45) end
    b.value:SetAlpha(1)
    self:UpdateColor(b)
    return
  end
  local okH, hp = pcall(UnitHealth, unit)
  local okM, mx = pcall(UnitHealthMax, unit)
  if okH and okM then
    for _, s in ipairs({ b.health, b.incAll, b.incMine, b.absorb }) do M.Set(s, "SetMinMaxValues", 0, mx) end
    M.Set(b.health, "SetValue", hp)
  end
  if b.dead or b.offline then
    b.health:SetValue(0)
    b.value:SetText("")
    b.flash:SetAlpha(0)
  else
    self:UpdateText(b)
    if M.db.lowHealth and M.Curves.lowHealth then
      local ok, a = pcall(UnitHealthPercent, unit, true, M.Curves.lowHealth)
      if not (ok and M.Set(b.flash, "SetAlpha", a)) then b.flash:SetAlpha(0) end
    else
      b.flash:SetAlpha(0)
    end
  end
  self:UpdateColor(b)
end

function UF:UpdateText(b)
  local unit, mode = b.unit, M.db.text
  if mode == "none" then b.value:SetText("") return end
  if mode == "percent" and M.Curves.percent then
    local ok, p = pcall(UnitHealthPercent, unit, true, M.Curves.percent)
    if ok then M.Set(b.value, "SetFormattedText", "%.0f%%", p) end
    b.value:SetAlpha(1)
    return
  end
  local ok, missing = pcall(UnitHealthMissing, unit, true)
  if not ok then b.value:SetText("") return end
  local okA, short = pcall(AbbreviateNumbers, missing)
  M.Set(b.value, "SetFormattedText", "-%s", okA and short or missing)
  if not M.IsSecret(missing) then
    b.value:SetAlpha((missing or 0) > 0 and 1 or 0)
  elseif M.Curves.missingAlpha then
    local okP, a = pcall(UnitHealthPercent, unit, true, M.Curves.missingAlpha)
    if not (okP and M.Set(b.value, "SetAlpha", a)) then b.value:SetAlpha(1) end
  end
end

function UF:UpdatePrediction(b)
  if b.fake then return end
  local unit = b.unit
  local function value(bar, fn, ...)
    local ok, v = pcall(fn, ...)
    if not ok or v == nil then bar:SetValue(0) return end
    if not M.Set(bar, "SetValue", v) then bar:SetValue(0) end
  end
  if b.dead or b.offline then
    b.incAll:SetValue(0) b.incMine:SetValue(0) b.absorb:SetValue(0)
    return
  end
  value(b.incAll, UnitGetIncomingHeals, unit)
  value(b.incMine, UnitGetIncomingHeals, unit, "player")
  value(b.absorb, UnitGetTotalAbsorbs, unit)
end

function UF:UpdatePower(b)
  if not b.power:IsShown() then return end
  if b.fake then b.power:SetMinMaxValues(0, 100) b.power:SetValue(b.fake.mana or 70) return end
  local unit = b.unit
  local okM, mx = pcall(UnitPowerMax, unit)
  local okP, p = pcall(UnitPower, unit)
  if okM and okP then
    M.Set(b.power, "SetMinMaxValues", 0, mx)
    M.Set(b.power, "SetValue", p)
  end
  local _, token = M.Plain(UnitPowerType, unit)
  local c = UF.POWER_COLORS[token or "MANA"] or UF.POWER_COLORS.MANA
  b.power:SetStatusBarColor(c[1], c[2], c[3])
end

function UF:UpdateStatus(b)
  local text
  if b.fake then
    b.dead, b.offline = b.fake.dead, false
    text = b.fake.dead and "Dead" or nil
  else
    local unit = b.unit
    b.offline = M.Plain(UnitIsConnected, unit) == false
    b.dead = M.Plain(UnitIsDeadOrGhost, unit) == true and M.Plain(UnitIsFeignDeath, unit) ~= true
    if b.offline then text = "Offline"
    elseif b.dead then
      text = M.Plain(UnitHasIncomingResurrection, unit) and "Resurrecting" or (M.Plain(UnitIsGhost, unit) and "Ghost" or "Dead")
    end
  end
  b.status:SetText(text or "")
  b.health:SetAlpha(b.offline and 0.4 or 1)
end

function UF:UpdateRole(b)
  local role = self:Role(b)
  local atlas = role and ROLE_ATLAS[role]
  local tiny = b.layout and b.layout.h < 30
  if atlas and not tiny and b.role:SetAtlas(atlas) ~= false then b.role:Show() else b.role:Hide() end
end

function UF:UpdateRaidIcon(b)
  local index = not b.fake and M.Plain(GetRaidTargetIndex, b.unit) or nil
  if index and SetRaidTargetIconTexture then SetRaidTargetIconTexture(b.raidIcon, index) b.raidIcon:Show()
  else b.raidIcon:Hide() end
end

function UF:UpdateTarget(b)
  if b.fake or b.unit == "target" then b.targetBorder:SetAlpha(0) return end
  local ok, same = pcall(UnitIsUnit, b.unit, "target")
  if not ok then b.targetBorder:SetAlpha(0)
  elseif M.IsSecret(same) then
    if not M.Set(b.targetBorder, "SetAlphaFromBoolean", same, 1, 0) then b.targetBorder:SetAlpha(0) end
  else b.targetBorder:SetAlpha(same and 1 or 0) end
end

function UF:UpdateAggro(b)
  if not M.db.aggro or b.fake then b.aggro:SetAlpha(b.fake and b.fake.aggro and M.db.aggro and 1 or 0) return end
  local status = M.Plain(UnitThreatSituation, b.unit)
  b.aggro:SetAlpha(status and status >= 2 and 1 or 0)
end

function UF:UpdateRange(b)
  if not M.db.range or b.fake or b.unit == "player" or b.unit == "target" or b.unit == "focus" then
    b.content:SetAlpha(b.fake and b.fake.far and M.db.range and M.db.rangeAlpha or 1)
    return
  end
  local ok, inRange = pcall(UnitInRange, b.unit)
  if not ok then b.content:SetAlpha(1) return end
  if M.IsSecret(inRange) then
    if not M.Set(b.content, "SetAlphaFromBoolean", inRange, 1, M.db.rangeAlpha) then b.content:SetAlpha(1) end
  else
    b.content:SetAlpha(inRange and 1 or M.db.rangeAlpha)
  end
end

function UF:UpdateAuras(b)
  if b.dead or b.offline then b.highlight:Hide() end
  M.Auras:UpdateUnit(b)
end

---Everything about one frame.
function UF:Update(b)
  if not b:IsShown() and not b.fake then return end
  if not b.fake and not UnitExists(b.unit) then return end
  self:UpdateStatus(b)
  self:UpdateName(b)
  self:UpdateHealth(b)
  self:UpdatePrediction(b)
  self:UpdatePower(b)
  self:UpdateRole(b)
  self:UpdateRaidIcon(b)
  self:UpdateTarget(b)
  self:UpdateAggro(b)
  self:UpdateRange(b)
  self:UpdateAuras(b)
end

-------------------------------------------------------------------------------------------
-- Events: one shared handler, routed by unit token
-------------------------------------------------------------------------------------------

local function each(unit, fn)
  local list = UF.byUnit[unit]
  if not list then return end
  for _, b in ipairs(list) do
    if (b:IsShown() or b.fake) and not b.fake then fn(b) end
  end
end

local UNIT_EVENTS = {
  UNIT_HEALTH = function(b) UF:UpdateHealth(b) end,
  UNIT_MAXHEALTH = function(b) UF:UpdateHealth(b) UF:UpdatePrediction(b) end,
  UNIT_HEAL_PREDICTION = function(b) UF:UpdatePrediction(b) end,
  UNIT_ABSORB_AMOUNT_CHANGED = function(b) UF:UpdatePrediction(b) end,
  UNIT_POWER_UPDATE = function(b) UF:UpdatePower(b) end,
  UNIT_MAXPOWER = function(b) UF:UpdatePower(b) end,
  UNIT_DISPLAYPOWER = function(b) UF:UpdatePower(b) end,
  UNIT_AURA = function(b) UF:UpdateAuras(b) end,
  UNIT_THREAT_SITUATION_UPDATE = function(b) UF:UpdateAggro(b) end,
  UNIT_NAME_UPDATE = function(b) UF:Update(b) end,
  UNIT_CONNECTION = function(b) UF:Update(b) end,
  UNIT_FLAGS = function(b) UF:UpdateStatus(b) UF:UpdateHealth(b) end,
  UNIT_PHASE = function(b) UF:Update(b) end,
  INCOMING_RESURRECT_CHANGED = function(b) UF:UpdateStatus(b) end,
}

function UF:RegisterEvents()
  for event, fn in pairs(UNIT_EVENTS) do
    Core:On(event, UF, function(_, unit) if unit then each(unit, fn) end end)
  end
  Core:On("UNIT_PET", UF, function() UF:UpdateUnitAll("pet") for i = 1, 4 do UF:UpdateUnitAll("partypet" .. i) end end)
  Core:On("PLAYER_TARGET_CHANGED", UF, function()
    UF:UpdateUnitAll("target")
    for _, b in ipairs(UF.all) do if b:IsShown() then UF:UpdateTarget(b) end end
  end)
  Core:On("PLAYER_FOCUS_CHANGED", UF, function() UF:UpdateUnitAll("focus") end)
  Core:On("RAID_TARGET_UPDATE", UF, function() for _, b in ipairs(UF.all) do UF:UpdateRaidIcon(b) end end)
  if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(0.25, function() for _, b in ipairs(UF.all) do if b:IsShown() then UF:UpdateRange(b) end end end)
  end
end

function UF:UpdateUnitAll(unit)
  local list = self.byUnit[unit]
  if not list then return end
  for _, b in ipairs(list) do self:Update(b) end
end
