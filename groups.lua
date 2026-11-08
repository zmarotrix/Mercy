-- The groups: party, raid, tanks, pets, target and focus. Each is a secure frame holding fixed unit buttons.
--
-- Which group shows is a state driver ([group:raid] show; hide), which the game runs securely, in combat too.
-- Which button sits where (sorting, raid groups, tanks) is decided out of combat; a roster change in combat is
-- placed properly when it ends. Someone joining mid-fight still appears, because their button's unit watch shows it.

local Core = NorgannonCore
local M = Mercy
if M.disabled then return end
local UI = Core.UI

local Groups = {}
M.Groups = Groups
Groups.frames = {}
Groups.buttons = {}

local GAP = 3
local MAX_TANKS = 4

local function range(prefix, from, to)
  local t = {}
  for i = from, to do t[#t + 1] = prefix .. i end
  return t
end

Groups.DEFS = {
  party = { label = "Party", units = { "player", "party1", "party2", "party3", "party4" } },
  raid = { label = "Raid", units = range("raid", 1, 40), raid = true },
  tanks = { label = "Tanks", units = {}, slots = MAX_TANKS, raid = true },
  pets = { label = "Pets", units = { "pet", "partypet1", "partypet2", "partypet3", "partypet4" } },
  target = { label = "Target", units = { "target" } },
  focus = { label = "Focus", units = { "focus" } },
}
Groups.ORDER = { "party", "raid", "tanks", "pets", "target", "focus" }

function Groups:Driver(key)
  if key == "raid" or key == "tanks" then return "[group:raid] show; hide" end
  if key == "party" then return M.db.soloParty and "[group:raid] hide; show" or "[group:raid] hide; [group:party] show; hide" end
  if key == "pets" then return "[group:raid] hide; [group:party] show; hide" end
  return "show"
end

function Groups:Buttons()
  return self.buttons
end

-------------------------------------------------------------------------------------------
-- Building (out of combat)
-------------------------------------------------------------------------------------------

local function makeLabel(g, key)
  local label = CreateFrame("Button", nil, g)
  label:SetHeight(16)
  label:SetPoint("BOTTOMLEFT", g, "TOPLEFT", 0, 3)
  label:SetPoint("BOTTOMRIGHT", g, "TOPRIGHT", 0, 3)
  label.text = label:CreateFontString(nil, "OVERLAY")
  label.text:SetFontObject(UI.Font("title", 13))
  label.text:SetPoint("CENTER", 0, 0)
  local c = UI.C.goldSoft
  label.text:SetTextColor(c[1], c[2], c[3])
  label.text:SetText(Groups.DEFS[key].label)
  label:RegisterForDrag("LeftButton")
  label:SetScript("OnDragStart", function()
    if M.InCombat() or M.db.locked then return end
    g:StartMoving()
  end)
  label:SetScript("OnDragStop", function()
    g:StopMovingOrSizing()
    local point, _, _, x, y = g:GetPoint()
    local saved = M:Group(key)
    saved.point, saved.x, saved.y = point or "CENTER", x or 0, y or 0
  end)
  label:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(Groups.DEFS[key].label, 1, 1, 1)
    GameTooltip:AddLine("Drag to move. /mercy lock when you're done.", 0.66, 0.63, 0.54)
    GameTooltip:Show()
  end)
  label:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return label
end

function Groups:BuildGroup(key)
  if self.frames[key] then return self.frames[key] end
  local def = self.DEFS[key]
  local g = CreateFrame("Frame", "MercyGroup_" .. key, UIParent, "SecureHandlerStateTemplate")
  g.key = key
  g:SetMovable(true)
  g:SetClampedToScreen(true)
  g:SetSize(10, 10)
  -- a soft rounded panel behind the group, with its label inside the top, like HealersMate's
  g.panel = CreateFrame("Frame", nil, g)
  g.panel:SetPoint("TOPLEFT", g, "TOPLEFT", -6, 22)
  g.panel:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", 6, -6)
  g.panel:SetFrameLevel(math.max(g:GetFrameLevel() - 1, 0))
  g.panel.fill = UI.Round(g.panel, "BACKGROUND", -8, 8)
  g.panel.fill:SetColor(UI.C.stone, 0.88)
  g.panel.line = UI.Round(g.panel, "BORDER", 0, 8, "line")
  g.panel.line:SetColor(UI.C.lineStrong, 0.9)
  g.label = makeLabel(g, key)
  g.buttons = {}
  local units = def.units
  if def.slots then units = {} for i = 1, def.slots do units[i] = "raid" .. i end end
  for i, unit in ipairs(units) do
    local b = M.UF:Create(g, unit, "MercyUnit_" .. key .. i)
    b.group = key
    g.buttons[i] = b
    self.buttons[#self.buttons + 1] = b
    if def.slots then
      -- a tank slot has no unit until AssignTanks gives it one
      b.slot = true
      local list = M.UF.byUnit[unit]
      for j = #list, 1, -1 do if list[j] == b then table.remove(list, j) end end
      b:SetAttribute("unit", nil)
      b.unit = "none"
      b:Hide()
    else
      RegisterUnitWatch(b)
    end
  end
  self.frames[key] = g
  return g
end

function Groups:Build()
  if self.built or M.InCombat() then return end
  M.UF:RegisterEvents()
  for _, key in ipairs(self.ORDER) do
    if M:Group(key).on then self:BuildGroup(key) end
  end
  self.built = true
  self:Attach()
  Core:On("GROUP_ROSTER_UPDATE", Groups, function() Groups:RosterChanged() end)
  Core:On("PLAYER_ROLES_ASSIGNED", Groups, function() Groups:RosterChanged() end)
  Core:On("PLAYER_ENTERING_WORLD", Groups, function() Groups:RosterChanged() end)
  Core:On("PLAYER_REGEN_ENABLED", Groups, function() Groups:UpdateAll() end)
end

---Blizzard's aura container for each button with a fixed unit (tank slots get theirs when they're assigned).
function Groups:Attach()
  for _, b in ipairs(self.buttons) do
    if not b.slot then M.Auras:Attach(b) end
  end
end

-------------------------------------------------------------------------------------------
-- Layout (out of combat)
-------------------------------------------------------------------------------------------

local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3 }

local function sortKey(b)
  local mode = M.db.partySort
  if mode == "none" then return "" end
  if mode == "class" then return (M.UF:Class(b) or "~") .. (M.Plain(UnitName, b.unit) or "") end
  if mode == "name" then return M.Plain(UnitName, b.unit) or "~" end
  return tostring(ROLE_ORDER[M.UF:Role(b) or ""] or 4) .. (M.Plain(UnitName, b.unit) or "")
end

---The order buttons stand in: existing units first, sorted; the rest after (their unit watch hides them).
function Groups:Ordered(g)
  local list, keys, present = {}, {}, {}
  for i, b in ipairs(g.buttons) do
    list[i] = b
    present[b] = b.fake ~= nil or (b.unit ~= "none" and M.Plain(UnitExists, b.unit) == true)
    keys[b] = present[b] and sortKey(b) or "~"
  end
  if g.key ~= "party" and g.key ~= "pets" then
    table.sort(list, function(a, c)
      if present[a] ~= present[c] then return present[a] end
      return false
    end)
    return list
  end
  table.sort(list, function(a, c)
    if present[a] ~= present[c] then return present[a] end
    if a.unit == "player" and M.db.partySort == "none" then return true end
    return keys[a] < keys[c]
  end)
  return list
end

local function place(g, b, col, row, L)
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", g, "TOPLEFT", col * (L.w + GAP), -row * (L.h + GAP))
end

function Groups:LayoutGroup(g)
  local key = g.key
  local layoutKey = (key == "raid" or key == "tanks") and M.db.raidLayout or M.db.layout
  for _, b in ipairs(g.buttons) do M.UF:ApplyLayout(b, layoutKey) end
  local L = M.UF.LAYOUTS[layoutKey] or M.UF.LAYOUTS.standard
  local cols, rows = 1, #g.buttons
  if key == "raid" then
    local columns, counts = {}, {}
    local byGroup = M.db.raidBy == "group"
    for i, b in ipairs(g.buttons) do
      local sub = 1
      if b.fake then sub = b.fake.subgroup or math.ceil(i / 5)
      elseif byGroup then
        local _, _, s = M.Plain(GetRaidRosterInfo, i)
        sub = s or math.ceil(i / 5)
      else
        sub = math.ceil(i / 5)
      end
      counts[sub] = (counts[sub] or 0) + 1
      columns[b] = { sub - 1, counts[sub] - 1 }
    end
    cols, rows = 1, 1
    for _, pos in pairs(columns) do
      cols = math.max(cols, pos[1] + 1)
      rows = math.max(rows, pos[2] + 1)
    end
    for b, pos in pairs(columns) do place(g, b, pos[1], pos[2], L) end
  else
    for i, b in ipairs(self:Ordered(g)) do place(g, b, 0, i - 1, L) end
    rows = (key == "target" or key == "focus") and 1 or #g.buttons
  end
  g:SetSize(math.max(cols * (L.w + GAP) - GAP, 10), math.max(rows * (L.h + GAP) - GAP, 10))
end

---Who the tanks are: the game's tank role, your own role marks, then main tanks.
function Groups:TankUnits()
  local out = {}
  if not IsInRaid or not IsInRaid() then return out end
  for i = 1, 40 do
    local unit = "raid" .. i
    if M.Plain(UnitExists, unit) then
      local role = M.Plain(UnitGroupRolesAssigned, unit)
      local name = M.Plain(UnitName, unit)
      local _, _, _, _, _, _, _, _, _, raidRole = M.Plain(GetRaidRosterInfo, i)
      if role == "TANK" or (name and M.Binds:Roles()[name] == "TANK") or raidRole == "MAINTANK" then
        out[#out + 1] = unit
        if #out >= MAX_TANKS then break end
      end
    end
  end
  return out
end

function Groups:AssignTanks(g)
  local units = self:TankUnits()
  for i, b in ipairs(g.buttons) do
    if b.fake then break end
    local unit = units[i]
    if unit ~= (b.unit ~= "none" and b.unit or nil) then
      if b.anchorID then
        pcall(C_UnitAuras.RemovePrivateAuraAnchor, b.anchorID)
        b.anchorID, b.anchorTried = nil, nil
      end
      local old = M.UF.byUnit[b.unit]
      if old then for j = #old, 1, -1 do if old[j] == b then table.remove(old, j) end end end
      if unit then
        b.unit = unit
        b:SetAttribute("unit", unit)
        M.UF.byUnit[unit] = M.UF.byUnit[unit] or {}
        table.insert(M.UF.byUnit[unit], b)
        RegisterUnitWatch(b)
        M.Binds:Apply(b)
        M.Auras:Attach(b)
      else
        UnregisterUnitWatch(b)
        b.unit = "none"
        b:SetAttribute("unit", nil)
        b:Hide()
      end
    end
  end
end

function Groups:Layout()
  Core:AfterCombat(function()
    if not self.built then return end
    for _, key in ipairs(self.ORDER) do
      local on = M:Group(key).on
      if on and not self.frames[key] then
        self:BuildGroup(key)
        self:Attach()
        M.Binds:ApplyAll()
      end
      local g = self.frames[key]
      if g then
        if key == "tanks" and not (M.Test and M.Test.active) then self:AssignTanks(g) end
        self:LayoutGroup(g)
        local saved = M:Group(key)
        g:ClearAllPoints()
        g:SetPoint(saved.point or "CENTER", UIParent, saved.point or "CENTER", saved.x or 0, saved.y or 0)
        UnregisterStateDriver(g, "visibility")
        if not on then
          g:Hide()
        elseif M.Test and M.Test.active then
          g:Show()
        else
          RegisterStateDriver(g, "visibility", self:Driver(key))
        end
      end
    end
    self:UpdateMovers()
  end, "mercy-layout")
end

function Groups:RosterChanged()
  if not self.built then return end
  M.Auras:RosterChanged()
  self:Layout()
  Core:NextFrame(function() self:UpdateAll() end, "mercy-update-all")
end

function Groups:UpdateAll()
  for _, b in ipairs(self.buttons) do
    if b.fake or b:IsShown() then M.UF:Update(b) end
  end
end

function Groups:UpdateMovers()
  local moving = not M.db.locked or (M.Test and M.Test.active)
  for _, g in pairs(self.frames) do
    g.panel:SetShown(M.db.panels and true or false)
    g.label:SetShown((M.db.panels or moving) and true or false)
    g.label:EnableMouse(moving and true or false)
  end
end

function Groups:ResetPositions()
  for key, d in pairs(M.GROUP_DEFAULTS) do
    local g = M:Group(key)
    g.point, g.x, g.y = d.point, d.x, d.y
  end
  self:Layout()
  M:Print(M.InCombat() and "Positions reset when combat ends." or "Positions reset.")
end

-------------------------------------------------------------------------------------------
-- Blizzard's party and raid frames
-------------------------------------------------------------------------------------------

local hidden
function Groups:HideBlizzard(on)
  if not on then return end
  Core:AfterCombat(function()
    hidden = hidden or CreateFrame("Frame")
    hidden:Hide()
    for _, name in ipairs({ "PartyFrame", "CompactPartyFrame", "CompactRaidFrameManager", "CompactRaidFrameContainer" }) do
      local f = rawget(_G, name)
      if type(f) == "table" and f.SetParent and not (f.IsForbidden and f:IsForbidden()) then
        pcall(f.SetParent, f, hidden)   -- reparented, not unregistered: their own code keeps running untouched
      end
    end
  end, "mercy-hide-blizzard")
end
