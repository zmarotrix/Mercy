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
  -- a healer's target and focus frames are for people you heal: shown only for friendly units (the game decides, in combat too)
  if M.db.friendlyOnly and (key == "target" or key == "focus") then return "[@" .. key .. ",help] show; hide" end
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
  label.text:SetPoint("LEFT", 2, 0)
  local c = UI.C.goldSoft
  label.text:SetTextColor(c[1], c[2], c[3])
  label.text:SetText(Groups.DEFS[key].label)
  label:RegisterForDrag("LeftButton")
  label:SetScript("OnDragStart", function()
    if M.InCombat() or not Groups:CanDrag() then return end
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
  g.panel:SetSize(10, 10)   -- Groups:FitPanel sizes it to the frames showing
  g.panel:SetFrameLevel(math.max(g:GetFrameLevel() - 1, 0))
  g.panel.fill = UI.Round(g.panel, "BACKGROUND", -8, 8)
  g.panel.fill:SetColor(UI.C.stone, 0.88)
  g.panel.line = UI.Round(g.panel, "BORDER", 0, 8, "line")
  g.panel.line:SetColor(UI.C.lineStrong, 0.9)
  g.label = makeLabel(g, key)
  -- how many need a dispel (in combat too) and your buffs (out of combat), on the label's right
  -- in a strip along the panel's bottom, so the group's name has the top to itself
  g.summary = g.panel:CreateFontString(nil, "OVERLAY")
  g.summary:SetFontObject(UI.Font("body", 11))
  g.summary:SetPoint("BOTTOMLEFT", g.panel, "BOTTOMLEFT", 8, 6)
  g.summary:SetPoint("BOTTOMRIGHT", g.panel, "BOTTOMRIGHT", -26, 6)
  g.summary:SetJustifyH("LEFT")
  if g.summary.SetWordWrap then g.summary:SetWordWrap(false) end
  g.buttons = {}
  local units = def.units
  if def.slots then units = {} for i = 1, def.slots do units[i] = "raid" .. i end end
  for i, unit in ipairs(units) do
    local b = M.UF:Create(g, unit, "MercyUnit_" .. key .. i)
    b.group = key
    -- the panel follows who's there: it isn't protected, so it can resize in combat when the game shows or hides a frame
    -- the game shows a frame when its unit appears, which can be after our last full redraw (at login most of all): draw it then
    b:HookScript("OnShow", function(self)
      Groups:FitPanelSoon(g)
      Core:NextFrame(function() if self:IsShown() then M.UF:Update(self) end end, "mercy-show-" .. (self:GetName() or tostring(i)))
    end)
    b:HookScript("OnHide", function() Groups:FitPanelSoon(g) end)
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
  if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(0.5, function() Groups:UpdateSummaries() end) end
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
  b.col, b.row = col, row
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
  g.cell = L
  self:FitPanel(g)
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

---Sizes a group's panel to the frames showing now: as many rows (and, in a raid, columns) as there are people.
function Groups:FitPanel(g)
  local L = g.cell
  if not (g.panel and L) then return end
  local cols, rows = 0, 0
  for _, b in ipairs(g.buttons) do
    if b.col and (b:IsShown() or b.fake) then
      cols = math.max(cols, b.col + 1)
      rows = math.max(rows, b.row + 1)
    end
  end
  local empty = rows == 0
  cols, rows = math.max(cols, 1), math.max(rows, 1)
  local strip = (g.key == "party" or g.key == "raid") and 20 or 0   -- the bottom strip: dispels, buffs, the rebuff button
  g.panel:SetSize(cols * (L.w + GAP) - GAP + 12, rows * (L.h + GAP) - GAP + 28 + strip)
  -- the panel and its name: only when someone's in it (unless you're moving the frames), at this group's opacity
  -- an empty group (no target, no focus) shows nothing, unless /mercy unlock asked to see every group to move it
  local showAll = M.showAll
  local showPanel = M.db.panels and (showAll or not empty or not M.db.hideEmpty)
  local alpha = M:Group(g.key).alpha or 0.88
  g.panel.fill:SetColor(UI.C.stone, alpha)
  g.panel.line:SetColor(UI.C.lineStrong, math.min(0.9, alpha * 1.1))
  g.panel:SetShown(showPanel and true or false)
  -- the name: on its panel, or as the handle to drag the group by while the frames are unlocked; never for an empty group
  local showLabel = showAll or showPanel or (not empty and Groups:CanDrag())
  g.label:SetShown(showLabel and true or false)
end

---"Dispel 2  ·  Power Word: Fortitude 3": who needs you, counted per group.
function Groups:UpdateSummaries()
  for key, g in pairs(self.frames) do
    if g.summary then
      local parts = {}
      local dispel = 0
      for _, b in ipairs(g.buttons) do
        if b.fake then
          local t = b.fake.dispel
          if t and (M.db.dispelScope == "any" or (M.Auras.cures and M.Auras.cures[t])) then dispel = dispel + 1 end
        elseif b:IsShown() and b.unit ~= "none" and not b.dead then
          local ids = M.Auras.Ids(b.unit, M.Auras:Filter(), 1)
          if ids and ids[1] then dispel = dispel + 1 end
        end
      end
      if dispel > 0 then parts[#parts + 1] = "|cffd9a8ffDispel " .. dispel .. "|r" end
      local counts = M.Buffs and M.Buffs.counts[key]
      if counts and not M.InCombat() then
        for _, e in ipairs(M.Buffs:Active()) do
          local c = counts[e.key] or 0
          if c > 0 then parts[#parts + 1] = "|cffffeea0" .. e.name .. " " .. c .. "|r" end
        end
      end
      g.summary:SetText(table.concat(parts, "  "))
    end
  end
end

function Groups:FitPanelSoon(g)
  Core:NextFrame(function() self:FitPanel(g) end, "mercy-fit-" .. g.key)
end

---Can groups be dragged by their names now? When unlocked, and always in test mode, which is for placing the frames.
function Groups:CanDrag()
  return not M.db.locked or (M.Test and M.Test.active) or false
end

function Groups:UpdateMovers()
  for _, g in pairs(self.frames) do
    g.label:EnableMouse(Groups:CanDrag())   -- drag a group by its name, unless the frames are locked
    self:FitPanel(g)
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
