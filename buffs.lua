-- Buff reminders: who needs your buffs, and a button that casts the next one.
--
-- Out of combat every aura can be read by name (GetAuraDataBySpellName), which is when buffing happens. In combat names are
-- secret, so the markers and the button step aside and come back when it ends. Your buffs that are on people show on their
-- frames all the time (auras.lua). Each click on the button is one cast, made by you: Mercy picks the target, never casts.

local Core = NorgannonCore
local M = Mercy
if M.disabled then return end
local UI = Core.UI

local Buffs = {}
M.Buffs = Buffs
Buffs.counts = {}

-- Rank 1 spell ids. Names come from the client, so they're in its language and match every rank.
-- who: "all" players, "mana" users, "tanks". group: the party-wide version, cast when 3 or more in one party need it.
Buffs.LIST = {
  PRIEST = {
    { key = "fortitude", id = 1243, group = 21562, who = "all", on = true },
    { key = "spirit", id = 14752, group = 27681, who = "mana", on = true },
    { key = "shadow", id = 976, group = 27683, who = "all", on = false },
  },
  DRUID = {
    { key = "wild", id = 1126, group = 21849, who = "all", on = true },
    { key = "thorns", id = 467, who = "tanks", on = true },
  },
  MAGE = {
    { key = "intellect", id = 1459, group = 23028, who = "mana", on = true },
  },
  PALADIN = {
    -- any blessing of yours counts; the button casts Wisdom on mana users and Might on everyone else
    { key = "blessing", id = 19742, blessing = true, wisdom = 19742, might = 19740, who = "all", on = true,
      ids = { 19740, 19742, 20217, 1038, 19977, 20911, 25782, 25894, 25898, 25895, 25890, 25899 } },
  },
}
local GROUP_SIZE = 3   -- this many in one party missing it: cast the group version

local function spellInfo(id)
  local info = M.Plain(M.Fn("C_Spell", "GetSpellInfo"), id)
  if type(info) == "table" then return info.name, info.iconID end
end

---The buffs you can give and have on, with their names resolved. Rebuilt when your spells or the settings change.
function Buffs:Active()
  if self.active then return self.active end
  local out = {}
  local track = M.db.buffTrack or {}
  for _, e in ipairs(self.LIST[M.class or ""] or {}) do
    local on = track[e.key]
    if on == nil then on = e.on end
    local name, icon = spellInfo(e.id)
    local groupName = e.group and spellInfo(e.group)
    local known = (name and M.Knows(name)) or (groupName and M.Knows(groupName))
    if e.blessing then
      known = false
      e.names = {}
      for _, id in ipairs(e.ids) do
        local n = spellInfo(id)
        if n then e.names[#e.names + 1] = n if M.Knows(n) then known = true end end
      end
    end
    if on and known and name then
      e.name, e.icon, e.groupName = name, icon, groupName and M.Knows(groupName) and groupName or nil
      out[#out + 1] = e
    end
  end
  self.active = out
  return out
end

function Buffs:Reset()
  self.active = nil
  self:ScanSoon()
end

---"has", "expiring" or "missing" for one person and one buff; nil if it isn't theirs to have.
function Buffs:State(b, e)
  local unit = b.unit
  if e.who == "mana" and M.Plain(UnitPowerType, unit) ~= 0 then return nil end
  if e.who == "tanks" and M.UF:Role(b) ~= "TANK" then return nil end
  local names = e.blessing and e.names or { e.name, e.groupName }
  local soon = (M.db.rebuffMinutes or 5) * 60
  local now = GetTime()
  local best
  for _, name in pairs(names) do
    local aura = M.Plain(M.Fn("C_UnitAuras", "GetAuraDataBySpellName"), unit, name, "HELPFUL")
    if type(aura) == "table" and (not e.blessing or aura.sourceUnit == "player") then
      local expires = aura.expirationTime
      if type(expires) ~= "number" or expires <= 0 or expires - now > soon then return "has" end
      best = "expiring"
    end
  end
  return best or "missing"
end

-------------------------------------------------------------------------------------------
-- Scanning, out of combat
-------------------------------------------------------------------------------------------

local SCANNED = { party = true, raid = true, tanks = true }

local function eligible(b)
  if b.fake then return false end
  if not (b:IsShown() and b.unit ~= "none") then return false end
  if M.Plain(UnitIsPlayer, b.unit) == false then return false end
  return M.Plain(UnitExists, b.unit) == true and not b.dead and not b.offline
end

function Buffs:Scan()
  if not (M.db and M.Groups and M.Groups.built) then return end
  if M.InCombat() or not M.db.buffReminders then self:HideAll() return end
  local active = self:Active()
  for key, g in pairs(M.Groups.frames) do
    if SCANNED[key] then
      local counts, needers = {}, {}
      for _, e in ipairs(active) do counts[e.key], needers[e.key] = 0, {} end
      for _, b in ipairs(g.buttons) do
        local need
        if b.fake then
          need = b.fake.needBuff and active[1] and { entry = active[1], state = "missing" } or nil
        elseif eligible(b) then
          for _, e in ipairs(active) do
            local state = self:State(b, e)
            if state == "missing" or state == "expiring" then
              counts[e.key] = counts[e.key] + 1
              table.insert(needers[e.key], b)
              need = need or { entry = e, state = state }
            end
          end
        end
        self:Mark(b, need)
      end
      self.counts[key] = counts
      if key ~= "tanks" then self:SetButton(g, active, counts, needers) end
    end
  end
  if M.Groups.UpdateSummaries then M.Groups:UpdateSummaries() end
end

function Buffs:ScanSoon()
  Core:NextFrame(function() Buffs:Scan() end, "mercy-buffs")
end

---The small icon on a frame: the buff this person needs. Faded when it's only running out.
function Buffs:Mark(b, need)
  local t = b.needBuff
  if not t then return end
  if not need then t:Hide() return end
  t:SetTexture(need.entry.icon)
  t:SetAlpha(need.state == "expiring" and 0.55 or 1)
  t:Show()
end

function Buffs:HideAll()
  if not M.Groups then return end
  for _, b in ipairs(M.Groups:Buttons()) do if b.needBuff then b.needBuff:Hide() end end
  for _, g in pairs(M.Groups.frames) do
    if g.rebuff and not M.InCombat() then g.rebuff:Hide() end
  end
  self.counts = {}
  if M.Groups.UpdateSummaries then M.Groups:UpdateSummaries() end
end

-------------------------------------------------------------------------------------------
-- The rebuff button: a secure spell button whose target and spell are set out of combat
-------------------------------------------------------------------------------------------

local function subgroup(b)
  if b.group ~= "raid" then return 1 end
  local index = tonumber((b.unit or ""):match("^raid(%d+)$"))
  local _, _, sub = M.Plain(GetRaidRosterInfo, index or 0)
  return sub or 1
end

local function inRange(spell, unit)
  return M.Plain(M.Fn("C_Spell", "IsSpellInRange"), spell, unit) ~= false
end

---What the next click casts: { spell, unit, b, count, entry }.
function Buffs:Next(active, counts, needers)
  for _, e in ipairs(active) do
    local list = needers[e.key]
    if list and #list > 0 then
      if e.groupName then
        local bySub = {}
        for _, b in ipairs(list) do
          local s = subgroup(b)
          bySub[s] = bySub[s] or {}
          table.insert(bySub[s], b)
        end
        for _, members in pairs(bySub) do
          if #members >= GROUP_SIZE then
            for _, b in ipairs(members) do
              if inRange(e.groupName, b.unit) then return { spell = e.groupName, unit = b.unit, b = b, count = counts[e.key], entry = e, party = true } end
            end
          end
        end
      end
      for _, b in ipairs(list) do
        local spell = e.name
        if e.blessing then
          local wisdom, might = spellInfo(e.wisdom), spellInfo(e.might)
          spell = (M.Plain(UnitPowerType, b.unit) == 0 and wisdom and M.Knows(wisdom)) and wisdom or might or wisdom
        end
        if spell and inRange(spell, b.unit) then return { spell = spell, unit = b.unit, b = b, count = counts[e.key], entry = e } end
      end
    end
  end
end

function Buffs:Button(g)
  if g.rebuff then return g.rebuff end
  local btn = CreateFrame("Button", "MercyRebuff_" .. g.key, g, "SecureActionButtonTemplate")
  btn:SetSize(18, 18)
  btn:SetPoint("BOTTOMRIGHT", g, "TOPRIGHT", 0, 3)
  btn:RegisterForClicks("AnyUp", "AnyDown")
  btn:SetAttribute("type", "spell")
  btn.icon = btn:CreateTexture(nil, "ARTWORK")
  btn.icon:SetAllPoints()
  btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  btn.count = btn:CreateFontString(nil, "OVERLAY")
  btn.count:SetFontObject(UI.Font("bold", 11, "OUTLINE"))
  btn.count:SetPoint("BOTTOMRIGHT", 3, -2)
  btn:SetScript("OnEnter", function(self)
    local n = self.next
    if not n then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(n.spell, 1, 1, 1)
    local who = M.Plain(UnitName, n.unit) or n.unit
    GameTooltip:AddLine(n.party and ("Click: on " .. who .. "'s party") or ("Click: on " .. who), M.ACCENT[1], M.ACCENT[2], M.ACCENT[3])
    for _, e in ipairs(Buffs:Active()) do
      local c = (Buffs.counts[g.key] or {})[e.key] or 0
      if c > 0 then GameTooltip:AddDoubleLine(e.name, c .. (c == 1 and " needs it" or " need it"), 0.9, 0.9, 0.9, 1, 0.82, 0) end
    end
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  btn:Hide()
  g.rebuff = btn
  return btn
end

function Buffs:SetButton(g, active, counts, needers)
  if M.InCombat() then return end
  local btn = self:Button(g)
  local n = M.db.rebuffButton and self:Next(active, counts, needers) or nil
  btn.next = n
  if not n then btn:Hide() return end
  btn:SetAttribute("spell", n.spell)
  btn:SetAttribute("unit", n.unit)
  local _, icon = spellInfo(n.entry.id)
  btn.icon:SetTexture(icon or n.entry.icon)
  btn.count:SetText(n.count > 1 and n.count or "")
  btn:Show()
end

-------------------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------------------

Core:OnLogin(function()
  if not M.db then return end
  Core:On("UNIT_AURA", Buffs, function() if not M.InCombat() then Buffs:ScanSoon() end end)
  Core:On("GROUP_ROSTER_UPDATE", Buffs, function() Buffs:ScanSoon() end)
  Core:On("PLAYER_REGEN_ENABLED", Buffs, function() Buffs:ScanSoon() end)
  Core:On("PLAYER_REGEN_DISABLED", Buffs, function() Buffs:HideAll() end)   -- still allowed to hide here: lockdown starts after
  Core:On("LEARNED_SPELL_IN_TAB", Buffs, function() Buffs:Reset() end)
  if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(15, function() if not M.InCombat() then Buffs:Scan() end end) end
end)
