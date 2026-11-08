-- Debuffs: the dispel highlight and the debuff icons, in and out of combat (docs/mercy-v1.md section 3).
--
-- Two ways, both from the client's own docs, and the probe (/hprobe) says which works in game:
--   B, ours: C_UnitAuras.GetUnitAuraInstanceIDs(unit, "HARMFUL|RAID") isn't marked secret, so how many debuffs you
--      can remove is a plain count even in combat. GetAuraDispelTypeColor gives the first one's colour, secret in
--      combat, which a texture takes without our reading it. That draws Mercy's highlight.
--   A, Blizzard's: C_UnitAuras.AddPrivateAuraAnchor with isContainer, the call the game's own raid frames make. The
--      secure Blizzard_PrivateAurasUI then draws the debuff icons (and, as a setting, its dispel overlay) on our frame.
-- If B's count turns out secret, the highlight falls back to A's overlay. If A is refused, our own icons stand in.

local Core = NorgannonCore
local M = Mercy
if M.disabled then return end

local Auras = {}
M.Auras = Auras

local FILTER_MINE = "HARMFUL|RAID"                      -- debuffs you can dispel
local FILTER_ANY = "HARMFUL|RAID_PLAYER_DISPELLABLE"    -- debuffs someone in your group can dispel
local CURES = {
  PRIEST = { ["Dispel Magic"] = { "Magic" }, ["Cure Disease"] = { "Disease" }, ["Abolish Disease"] = { "Disease" } },
  PALADIN = { Purify = { "Poison", "Disease" }, Cleanse = { "Poison", "Disease", "Magic" } },
  DRUID = { ["Remove Curse"] = { "Curse" }, ["Cure Poison"] = { "Poison" }, ["Abolish Poison"] = { "Poison" } },
  SHAMAN = { ["Cure Poison"] = { "Poison" }, ["Cure Disease"] = { "Disease" } },
  MAGE = { ["Remove Lesser Curse"] = { "Curse" }, ["Remove Curse"] = { "Curse" } },
}
local ORDER = { "Magic", "Curse", "Disease", "Poison" }

function Auras:Init()
  self:SpellsChanged()
end

---The dispel types your spells remove, for the settings text and /mercy status (the client's RAID filter does the real work).
function Auras:SpellsChanged()
  local set = {}
  for spell, types in pairs(CURES[M.class or ""] or {}) do
    if M.Knows(spell) then for _, t in ipairs(types) do set[t] = true end end
  end
  self.cures = set
end

function Auras:CuresText()
  local out = {}
  for _, t in ipairs(ORDER) do if self.cures and self.cures[t] then out[#out + 1] = t end end
  return #out > 0 and table.concat(out, ", ") or "nothing"
end

function Auras:Filter()
  return M.db.dispelScope == "any" and FILTER_ANY or FILTER_MINE
end

---The highlight in use: Mercy's, unless its count can't be read and Blizzard's drawing works.
function Auras:Effective()
  if M.db.highlight == "mercy" and self.countState == "secret" and self.containerState == "working" then return "blizzard" end
  return M.db.highlight
end

-------------------------------------------------------------------------------------------
-- Reading: instance ids pass a filter; never the aura's contents in combat
-------------------------------------------------------------------------------------------

---The ids of a unit's auras that pass a filter, or nil and why not.
function Auras.Ids(unit, filter, max)
  local fn = M.Fn("C_UnitAuras", "GetUnitAuraInstanceIDs")
  if not fn then return nil, "missing" end
  local ok, ids = pcall(fn, unit, filter, max)
  if not ok then return nil, "error" end
  if M.IsSecret(ids) or type(ids) ~= "table" then return nil, "secret" end
  if ids[1] ~= nil and M.IsSecret(ids[1]) then return nil, "secret" end
  return ids
end

-------------------------------------------------------------------------------------------
-- B: Mercy's highlight
-------------------------------------------------------------------------------------------

function Auras:UpdateHighlight(b)
  local hl = b.highlight
  if not hl then return end
  if b.fake then
    local t = b.fake.dispel
    if t and (M.db.dispelScope == "any" or (self.cures and self.cures[t])) and self:Effective() == "mercy" then
      hl:SetColor(M.Curves.TypeColor(t))
      hl:Show()
    else
      hl:Hide()
    end
    return
  end
  local unit = b.unit
  if M.db.highlight ~= "mercy" or b.dead or not UnitExists(unit) then hl:Hide() return end
  local ids, why = self.Ids(unit, self:Filter(), 1)
  local state = ids and "working" or why
  if state ~= self.countState then
    local was = self:Effective()
    self.countState = state
    if self:Effective() ~= was then self:SettingsChanged() end   -- Blizzard's overlay takes over, or hands back
  end
  if not ids or self:Effective() ~= "mercy" then hl:Hide() return end
  if not ids[1] then hl:Hide() return end
  local fn = M.Fn("C_UnitAuras", "GetAuraDispelTypeColor")
  local ok, color = false, nil
  if fn and M.Curves.dispel then ok, color = pcall(fn, unit, ids[1], M.Curves.dispel) end
  if ok and color and not M.IsSecret(color) and color.GetRGBA then
    hl:SetSecretColor(color)
  else
    hl:SetColor(1, 1, 1)   -- we know there is one, not its colour
  end
  hl:Show()
end

-------------------------------------------------------------------------------------------
-- A: Blizzard's private aura container on our health bar
-------------------------------------------------------------------------------------------

local function enum(group, key, fallback)
  local e = Enum and Enum[group]
  return e and e[key] ~= nil and e[key] or fallback
end

function Auras:ContainerAttributes(b)
  local blizz = self:Effective() == "blizzard"
  local icons = M.db.debuffIcons and (M.db.maxDebuffs or 3) or 0
  -- your buffs: Blizzard's rule (AuraUtil.ShouldDisplayBuff) is buffs you cast that you can put on others, not self-only ones
  local buffs = M.db.myBuffs and (M.db.maxBuffs or 3) or 0
  local size = b.iconSize or 14
  local groups = rawget(_G, "CompactRaidGroupTypeEnum")
  return {
    ["max-buffs"] = buffs, ["max-debuffs"] = icons, ["max-dispel-debuffs"] = blizz and 3 or 0,
    ["aura-organization-type"] = enum("RaidAuraOrganizationType", "BuffsRightDebuffsLeft", 2),
    ["display-only-dispellable-debuffs"] = false,
    ["ignore-buffs"] = buffs == 0, ["ignore-debuffs"] = icons == 0, ["ignore-dispel-debuffs"] = false,
    ["dispel-indicator-option"] = blizz and (M.db.dispelScope == "any" and enum("RaidDispelDisplayType", "DisplayAll", 2)
      or enum("RaidDispelDisplayType", "DispellableByMe", 1)) or enum("RaidDispelDisplayType", "Disabled", 0),
    ["display-larger-role-specific-debuffs"] = true,
    ["dispel-indicator-overlay-type"] = enum("RaidDispelOverlayType", "UseDebuffColor", 1),
    ["dispel-indicator-overlay-animation"] = false, ["dispel-indicator-animated-border"] = false,
    ["show-big-defensive"] = false, ["big-defensive-size"] = size + 4,
    ["debuff-size"] = size, ["buff-size"] = size - 2, ["debuff-border-scale"] = 1, ["buff-border-scale"] = 1,
    ["always-hide-duration"] = true, ["set-aura-size-to-icon-size"] = true,
    ["power-bar-used-height"] = 0, ["group-type"] = groups and groups.Raid or nil,
  }
end

local function writeAttributes(c, attrs)
  for k, v in pairs(attrs) do c:SetAttribute(k, v) end
end

---Asks for Blizzard's container on a button's health area. Out of combat, once per button (its unit never changes).
function Auras:Attach(b)
  if b.anchorID or b.anchorTried or b.fake then return end
  b.anchorTried = true
  local add = M.Fn("C_UnitAuras", "AddPrivateAuraAnchor")
  if not add then self.containerState = "missing" return end
  local c = b.container
  writeAttributes(c, self:ContainerAttributes(b))
  local ok, id = pcall(add, {
    unitToken = b.unit, auraIndex = 1, parent = c,
    showCooldownFrame = true, showCooldownEdge = false, showCountdownNumbers = false, showDispelIcon = false,
    isContainer = true,
    iconInfo = { iconAnchor = { point = "BOTTOMRIGHT", relativeTo = c, relativePoint = "BOTTOMRIGHT", offsetX = 0, offsetY = 0 },
      iconWidth = b.iconSize or 14, iconHeight = b.iconSize or 14, borderScale = 1 },
  })
  if ok and id ~= nil and not M.IsSecret(id) then
    b.anchorID = id
    self.containerState = "working"
  else
    self.containerState = ok and "refused" or "error"
    Core:Debug("mercy", "private aura container refused for %s", tostring(b.unit))
  end
end

---Settings or the effective highlight changed: Blizzard's code reads the attributes again.
function Auras:SettingsChanged()
  if not M.Groups or not M.Groups.built then return end
  for _, b in ipairs(M.Groups:Buttons()) do
    if b.anchorID then
      writeAttributes(b.container, self:ContainerAttributes(b))
      b.container:SetAttribute("update-settings", true)
    end
  end
end

---The roster changed: a unit token may now be someone else, so the container reads its unit again.
function Auras:RosterChanged()
  if not M.Groups or not M.Groups.built then return end
  for _, b in ipairs(M.Groups:Buttons()) do
    if b.anchorID then b.container:SetAttribute("update-settings", true) end
  end
end

-------------------------------------------------------------------------------------------
-- Our own debuff icons: only when Blizzard's container isn't there, or in test mode
-------------------------------------------------------------------------------------------

local function setIcon(icon, unit, id, buff)
  local U = C_UnitAuras
  local okD, data = pcall(U.GetAuraDataByAuraInstanceID, unit, id)
  if not okD or M.IsSecret(data) or type(data) ~= "table" then return false end
  M.Set(icon.texture, "SetTexture", data.icon)
  local okB, color = false, nil
  if buff then
    icon.border:SetVertexColor(0, 0, 0, 1)
  elseif U.GetAuraDispelTypeColor and M.Curves.border then okB, color = pcall(U.GetAuraDispelTypeColor, unit, id, M.Curves.border) end
  if buff then
    -- a black edge, set above
  elseif okB and color and not M.IsSecret(color) and color.GetRGBA then
    M.Set(icon.border, "SetVertexColor", color:GetRGBA())
  else
    icon.border:SetVertexColor(0.8, 0, 0, 1)
  end
  if U.GetAuraApplicationDisplayCount then
    local okC, text = pcall(U.GetAuraApplicationDisplayCount, unit, id, 2)
    if okC then M.Set(icon.count, "SetText", text) else icon.count:SetText("") end
  end
  if U.GetAuraDuration and icon.cooldown.SetCooldownFromDurationObject then
    local okT, dur = pcall(U.GetAuraDuration, unit, id)
    if not (okT and M.Set(icon.cooldown, "SetCooldownFromDurationObject", dur)) then icon.cooldown:Hide() end
  end
  icon.auraID = id
  icon:Show()
  return true
end

function Auras:UpdateIcons(b)
  local icons = b.debuffs
  if not icons then return end
  local n = 0
  local want = M.db.debuffIcons and math.min(M.db.maxDebuffs or 3, #icons) or 0
  if b.fake then
    for _, d in ipairs(b.fake.debuffs or {}) do
      if n >= want then break end
      n = n + 1
      local icon = icons[n]
      icon.texture:SetTexture(d.icon or 136207)
      icon.border:SetVertexColor(M.Curves.TypeColor(d.type))
      icon.count:SetText(d.stacks and d.stacks > 1 and d.stacks or "")
      icon.auraID = nil
      icon:Show()
    end
  elseif want > 0 and not b.anchorID and UnitExists(b.unit) and not b.dead then
    local ids = self.Ids(b.unit, "HARMFUL", want)
    if ids then
      for _, id in ipairs(ids) do
        if n >= want then break end
        if setIcon(icons[n + 1], b.unit, id) then n = n + 1 end
      end
    end
  end
  for i = n + 1, #icons do icons[i]:Hide() end
  self:UpdateBuffIcons(b)
end

---Your buffs on someone, drawn by Mercy only when Blizzard's container isn't there (it draws them otherwise), or in test mode.
---HELPFUL|PLAYER: everything you cast on them, read as instance ids, which stay readable in combat.
function Auras:UpdateBuffIcons(b)
  local icons = b.buffs
  if not icons then return end
  local n = 0
  local want = M.db.myBuffs and math.min(M.db.maxBuffs or 3, #icons) or 0
  if b.fake then
    for _, d in ipairs(b.fake.buffs or {}) do
      if n >= want then break end
      n = n + 1
      local icon = icons[n]
      icon.texture:SetTexture(d.icon)
      icon.border:SetVertexColor(0, 0, 0, 1)
      icon.count:SetText("")
      icon.auraID = nil
      icon:Show()
    end
  elseif want > 0 and not b.anchorID and UnitExists(b.unit) and not b.dead then
    local ids = self.Ids(b.unit, "HELPFUL|PLAYER", want)
    if ids then
      for _, id in ipairs(ids) do
        if n >= want then break end
        if setIcon(icons[n + 1], b.unit, id, true) then n = n + 1 end
      end
    end
  end
  for i = n + 1, #icons do icons[i]:Hide() end
end

function Auras:UpdateUnit(b)
  self:UpdateHighlight(b)
  self:UpdateIcons(b)
end
