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
  WARLOCK = {
    -- your imp's: tracked while an imp that knows it is out; the button and Buff binds cast it through the pet
    { key = "fireshield", id = 2947, pet = true, who = "tanks", on = true },
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
---Does your pet know this spell now? By id, then by name through the pet's spellbook (a pet may list only its best rank).
local function petKnows(id, name)
  if M.Plain(UnitExists, "pet") ~= true then return false end
  local SB = rawget(_G, "C_SpellBook")
  local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
  if SB and bank then
    if SB.IsSpellKnown and M.Plain(SB.IsSpellKnown, id, bank) == true then return true end
    local n = SB.HasPetSpells and M.Plain(SB.HasPetSpells)
    if type(n) == "number" and name and SB.GetSpellBookItemName then
      for i = 1, n do
        if M.Plain(SB.GetSpellBookItemName, i, bank) == name then return true end
      end
    end
  end
  local legacy = M.Fn(nil, "IsSpellKnown")
  return legacy and M.Plain(legacy, id, true) == true or false
end

local GROUP_SIZE = 3   -- this many in one party missing it: cast the group version

local function spellInfo(id)
  local info = M.Plain(M.Fn("C_Spell", "GetSpellInfo"), id)
  if type(info) == "table" then return info.name, info.iconID end
end

Buffs.WHO = { { "off", "Off" }, { "all", "Everyone" }, { "mana", "Mana users" }, { "tanks", "Tanks" } }

local function copy(e)
  local t = {}
  for k, v in pairs(e) do t[k] = v end
  return t
end

---Who a default buff is for now: your setting (buffWho), the older on/off (buffTrack), or its own default.
function Buffs:Who(e)
  local who = (M.db.buffWho or {})[e.key]
  if who then return who end
  local on = (M.db.buffTrack or {})[e.key]
  if on == false then return "off" end
  if on == nil and not e.on then return "off" end
  return e.who
end

---Every buff Mercy knows of for you: your class's defaults and the ones you added, each with who it's for (even "off").
---Each entry has key, name, icon, who, known, custom.
function Buffs:All()
  local out = {}
  for _, base in ipairs(self.LIST[M.class or ""] or {}) do
    local e = copy(base)
    local name, icon = spellInfo(e.id)
    local groupName = e.group and spellInfo(e.group)
    local known = (name and M.Knows(name)) or (groupName and M.Knows(groupName))
    if e.pet then known = name and petKnows(e.id, name) end
    if e.blessing then
      known = false
      e.names = {}
      for _, id in ipairs(e.ids) do
        local n = spellInfo(id)
        if n then e.names[#e.names + 1] = n if M.Knows(n) then known = true end end
      end
    end
    if known and name then
      -- groupName is for casting, so only when you know it; partyName is for reading, so someone else's Gift of the Wild
      -- counts as Mark of the Wild even before you've learned Gift yourself
      e.name, e.icon, e.groupName, e.partyName = name, icon, groupName and M.Knows(groupName) and groupName or nil, groupName
      e.who, e.known = self:Who(base), true
      out[#out + 1] = e
    end
  end
  for _, c in ipairs(M.db.customBuffs or {}) do
    if type(c) == "table" and type(c.name) == "string" and c.name ~= "" then
      local info = M.Plain(M.Fn("C_Spell", "GetSpellInfo"), c.name)
      out[#out + 1] = { key = "custom:" .. string.lower(c.name), name = type(info) == "table" and info.name or c.name,
        icon = type(info) == "table" and info.iconID or 134400, who = c.who or "all", custom = true, known = M.Knows(c.name) }
    end
  end
  return out
end

---The buffs being tracked (who isn't "off"). Rebuilt when your spells or the settings change.
function Buffs:Active()
  if self.active then return self.active end
  local out = {}
  for _, e in ipairs(self:All()) do
    if e.who ~= "off" then out[#out + 1] = e end
  end
  self.active = out
  return out
end

---Adds a buff of your own choosing, by name, tracked for everyone until you say otherwise. False if it's already there.
function Buffs:Add(name)
  name = name and strtrim(name) or ""
  if name == "" then return false end
  M.db.customBuffs = M.db.customBuffs or {}
  for _, c in ipairs(M.db.customBuffs) do
    if string.lower(c.name) == string.lower(name) then return false end
  end
  local info = M.Plain(M.Fn("C_Spell", "GetSpellInfo"), name)
  table.insert(M.db.customBuffs, { name = type(info) == "table" and info.name or name, who = "all" })
  self:Reset()
  return true
end

---Who a buff is for ("off", "all", "mana", "tanks"), or "remove" for one you added.
function Buffs:SetWho(e, who)
  if e.custom then
    for i, c in ipairs(M.db.customBuffs or {}) do
      if "custom:" .. string.lower(c.name) == e.key then
        if who == "remove" then table.remove(M.db.customBuffs, i) else c.who = who end
        break
      end
    end
  else
    M.db.buffWho = M.db.buffWho or {}
    M.db.buffWho[e.key] = who
  end
  self:Reset()
end

function Buffs:Reset()
  self.active, self.buffNames = nil, nil
  if M.Binds then M.Binds:ForgetRanks() end
  self:ScanSoon()
end

---Everything someone wears, read once per scan: { [name] = { expires, mine } }, or nil if the client won't say.
---Read by index rather than asked by name: a by-name lookup can miss another caster's version of the buff.
function Buffs:Worn(unit)
  self.wornCache = self.wornCache or {}
  local cached = self.wornCache[unit]
  if cached ~= nil then return cached or nil end
  local get = M.Fn("C_UnitAuras", "GetAuraDataByIndex")
  local out, readable = {}, false
  if get then
    for i = 1, 60 do
      local ok, a = pcall(get, unit, i, "HELPFUL")
      if not ok or a == nil or M.IsSecret(a) or type(a) ~= "table" then break end
      readable = true
      local name = a.name
      if type(name) == "string" and not M.IsSecret(name) then
        local exp, src, dur = a.expirationTime, a.sourceUnit, a.duration
        exp = (type(exp) == "number" and not M.IsSecret(exp)) and exp or 0
        dur = (type(dur) == "number" and not M.IsSecret(dur)) and dur or 0
        local mine = not M.IsSecret(src) and src == "player"
        local old = out[name]
        -- two of the same name (Mark from one druid, Gift from another): keep the longer
        if not old or (old.expires > 0 and (exp == 0 or exp > old.expires)) then out[name] = { expires = exp, duration = dur, mine = mine } end
        if old and (old.mine or mine) then out[name].mine = true end
      end
    end
  end
  self.wornCache[unit] = readable and out or false
  return readable and out or nil
end

---The names that count as having this buff: itself and its group version (Mark of the Wild and Gift of the Wild).
function Buffs:Names(e)
  if e.blessing then return e.names end
  return { e.name, e.partyName }
end

---"has", "expiring" or "missing" for one person and one buff; nil if it isn't theirs to have.
function Buffs:State(b, e)
  local unit = b.unit
  if e.who == "mana" and M.Plain(UnitPowerType, unit) ~= 0 then return nil end
  if e.who == "tanks" and M.UF:Role(b) ~= "TANK" then return nil end
  local soon = (M.db.rebuffMinutes or 5) * 60
  local now = GetTime()
  local worn = self:Worn(unit)
  local best
  for _, name in pairs(self:Names(e)) do
    local expires, duration, found
    local w = worn and worn[name]
    if w then
      found, expires, duration = not e.blessing or w.mine, w.expires, w.duration
    else
      -- the client wouldn't list them, or listed them without this one: ask by name too
      local aura = M.Plain(M.Fn("C_UnitAuras", "GetAuraDataBySpellName"), unit, name, "HELPFUL")
      if type(aura) == "table" then
        found, expires, duration = not e.blessing or aura.sourceUnit == "player", aura.expirationTime, aura.duration
      end
    end
    if found then
      -- "running out" is the last 5 minutes (your setting), or the last quarter of a short buff: Thorns, Fire Shield
      local window = soon
      if type(duration) == "number" and duration > 0 then window = math.min(soon, duration / 4) end
      if type(expires) ~= "number" or expires <= 0 or expires - now > window then return "has" end
      best = "expiring"
    end
  end
  return best or "missing"
end

---/mercy buffs: what Mercy reads on your target (or you) and what it decides, for bug reports.
function Buffs:Report()
  local unit = M.Plain(UnitExists, "target") and "target" or "player"
  self.wornCache = nil
  local worn = self:Worn(unit)
  M:Print(("Buffs on %s (%s):"):format(tostring(M.Plain(UnitName, unit) or unit), unit))
  if not worn then
    M:Print("  the client won't list them (by index)")
  else
    local list = {}
    for name, w in pairs(worn) do
      list[#list + 1] = name .. (w.mine and " (yours)" or "") .. (w.expires > 0 and (" %dm"):format((w.expires - GetTime()) / 60) or "")
    end
    table.sort(list)
    M:Print("  wearing: " .. (#list > 0 and table.concat(list, ", ") or "nothing"))
  end
  local active = self:Active()
  if #active == 0 then M:Print("  no buffs tracked for your class") end
  for _, e in ipairs(active) do
    local names = {}
    for _, n in pairs(self:Names(e)) do names[#names + 1] = n end
    local fake = { unit = unit }
    local ok, state = pcall(self.State, self, fake, e)
    M:Print(("  %s [%s] looks for %s: %s"):format(e.name or e.key, e.who, table.concat(names, " / "),
      ok and tostring(state or "not theirs") or ("error " .. tostring(state))))
  end
  self.wornCache = nil
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
  self.wornCache = {}
  for key, g in pairs(M.Groups.frames) do
    if SCANNED[key] then
      local counts, needers = {}, {}
      for _, e in ipairs(active) do counts[e.key], needers[e.key] = 0, {} end
      local showBuffed = M.db.buffShow == "buffed"
      for _, b in ipairs(g.buttons) do
        local marks, want = {}, nil
        if b.fake then
          local e = active[1]
          if e and (b.fake.needBuff == not showBuffed) then marks[1] = { entry = e, state = showBuffed and "has" or "missing" } end
        elseif eligible(b) then
          for _, e in ipairs(active) do
            local state = self:State(b, e)
            local needs = state == "missing" or state == "expiring"
            if needs and e.known and not want then want = self:SpellFor(e, b) end
            if needs then
              counts[e.key] = counts[e.key] + 1
              table.insert(needers[e.key], b)
            end
            -- "missing": what they need from you; "buffed": what they have (faded when it's running out, either way)
            if state and ((not showBuffed and needs) or (showBuffed and state ~= "missing")) then
              marks[#marks + 1] = { entry = e, state = state }
            end
          end
        end
        self:Mark(b, marks)
        self:SetBuffSpell(b, (not b.fake and eligible(b)) and want or nil)
        if eligible(b) then
          local level = M.Plain(UnitLevel, b.unit)
          if b.lastLevel ~= level then
            local first = b.lastLevel == nil
            b.lastLevel = level
            if not first and M.db.downrank and not M.InCombat() then M.Binds:Apply(b) end
          end
        end
      end
      self.counts[key] = counts
      if key ~= "tanks" then self:SetButton(g, active, counts, needers) end
    end
  end
  if M.Groups.UpdateSummaries then M.Groups:UpdateSummaries() end
end

---The spell that gives this person this buff: the buff itself, or for a paladin Wisdom (mana users) or Might, at a rank that
---lands on their level.
function Buffs:SpellFor(e, b)
  local spell = e.name
  if e.blessing then
    local wisdom, might = spellInfo(e.wisdom), spellInfo(e.might)
    spell = (M.Plain(UnitPowerType, b.unit) == 0 and wisdom and M.Knows(wisdom)) and wisdom or might or wisdom
  end
  return M.Binds:BestRank(spell, M.Plain(UnitLevel, b.unit))
end

---Is this one of the buffs Mercy knows (your class's, their party versions, blessings, the ones you added)? For downranking binds.
function Buffs:IsBuff(spell)
  if not self.buffNames then
    local names = {}
    for _, e in ipairs(self:All()) do
      if e.name then names[e.name] = true end
      if e.groupName then names[e.groupName] = true end
      for _, n in ipairs(e.names or {}) do names[n] = true end
    end
    self.buffNames = names
  end
  return self.buffNames[spell] == true
end

---What a "Buff" click on this frame casts. A change rewrites the frame's click attributes (we're out of combat here).
function Buffs:SetBuffSpell(b, spell)
  if b.buffSpell == spell then return end
  b.buffSpell = spell
  if not M.InCombat() and M.Binds:HasBuffBind() then M.Binds:Apply(b) end
end

function Buffs:ScanSoon()
  Core:NextFrame(function() Buffs:Scan() end, "mercy-buffs")
end

---The small icons on a frame's top right, up to three: the buffs this person needs from you, or (Show: Buffed) the ones they
---have. Faded when a buff is running out.
function Buffs:Mark(b, marks)
  local list = b.buffMarks
  if not list then return end
  for i, t in ipairs(list) do
    local m = marks and marks[i]
    if m then
      t:SetTexture(m.entry.icon)
      t:SetAlpha(m.state == "expiring" and 0.55 or 1)
      t:Show()
    else
      t:Hide()
    end
  end
end

function Buffs:HideAll()
  if not M.Groups then return end
  for _, b in ipairs(M.Groups:Buttons()) do self:Mark(b, nil) end
  for _, g in pairs(M.Groups.frames) do
    local btn = g.rebuff
    if btn and not M.InCombat() then
      -- reminders off or no button wanted: gone. Otherwise (combat is starting): stays, greyed, and does nothing until it ends
      if not (M.db.buffReminders and M.db.rebuffButton) then btn:Hide() else self:Dim(btn, "combat") end
    end
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
    if list and #list > 0 and e.known then   -- a buff you added but can't cast is tracked, not offered
      if e.groupName then
        local bySub = {}
        for _, b in ipairs(list) do
          local s = subgroup(b)
          bySub[s] = bySub[s] or {}
          table.insert(bySub[s], b)
        end
        for _, members in pairs(bySub) do
          if #members >= GROUP_SIZE then
            local low
            for _, b in ipairs(members) do
              local level = M.Plain(UnitLevel, b.unit)
              if type(level) == "number" and level > 0 and (not low or level < low) then low = level end
            end
            local groupSpell = M.Binds:BestRank(e.groupName, low)
            for _, b in ipairs(members) do
              if inRange(e.groupName, b.unit) then return { spell = groupSpell, unit = b.unit, b = b, count = counts[e.key], entry = e, party = true } end
            end
          end
        end
      end
      for _, b in ipairs(list) do
        local spell = self:SpellFor(e, b)
        if spell and inRange(spell:gsub("%(.-%)$", ""), b.unit) then return { spell = spell, unit = b.unit, b = b, count = counts[e.key], entry = e } end
      end
    end
  end
end

function Buffs:Button(g)
  if g.rebuff then return g.rebuff end
  local btn = CreateFrame("Button", "MercyRebuff_" .. g.key, g, "SecureActionButtonTemplate")
  btn:SetSize(16, 16)
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
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if not n then
      GameTooltip:AddLine("Rebuff", 1, 1, 1)
      GameTooltip:AddLine(self.why == "combat" and "Waits for combat to end." or "Everyone has your buffs.", 0.66, 0.63, 0.54)
      GameTooltip:Show()
      return
    end
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

---The button with nothing to do: greyed, "0" (or blank in combat), and a click does nothing. Out of combat only (it's secure).
function Buffs:Dim(btn, why)
  btn.next, btn.why = nil, why
  btn:SetAttribute("type", nil)
  btn:SetAttribute("spell", nil)
  btn:SetAttribute("unit", nil)
  if btn.icon.SetDesaturated then btn.icon:SetDesaturated(true) end
  btn.icon:SetAlpha(0.45)
  btn.count:SetText(why == "combat" and "" or "0")
  btn.count:SetTextColor(0.6, 0.6, 0.6)
end

function Buffs:SetButton(g, active, counts, needers)
  if M.InCombat() then return end
  local btn = self:Button(g)
  -- shown whenever you have a buff to track and want the button; greyed with "0" when nobody needs one
  local mine
  for _, e in ipairs(active) do if e.known then mine = mine or e end end
  if not (M.db.rebuffButton and mine) then btn:Hide() return end
  local n = self:Next(active, counts, needers)
  btn.next = n
  -- in the panel's bottom strip, under the last person shown (secure, so placed out of combat; the panel itself resizes in combat)
  local last
  for _, b in ipairs(g.buttons) do
    if (b:IsShown() or b.fake) and b.row and (not last or b.row > last.row or (b.row == last.row and b.col > last.col)) then last = b end
  end
  btn:ClearAllPoints()
  btn:SetPoint("TOPRIGHT", last or g, "BOTTOMRIGHT", 0, -3)
  if not n then
    btn.icon:SetTexture(mine.icon)
    self:Dim(btn, "none")
    btn:Show()
    return
  end
  btn.why = nil
  btn:SetAttribute("type", "spell")
  btn:SetAttribute("spell", n.spell)
  btn:SetAttribute("unit", n.unit)
  local _, icon = spellInfo(n.entry.id or 0)
  btn.icon:SetTexture(icon or n.entry.icon)
  if btn.icon.SetDesaturated then btn.icon:SetDesaturated(false) end
  btn.icon:SetAlpha(1)
  btn.count:SetText(n.count)
  btn.count:SetTextColor(1, 1, 1)
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
  -- your pet came or went (an imp's Fire Shield): which buffs you can give changed
  Core:On("UNIT_PET", Buffs, function() if M.class == "WARLOCK" then Buffs:Reset() end end)
  Core:On("PET_BAR_UPDATE", Buffs, function() if M.class == "WARLOCK" then Buffs:Reset() end end)
  Core:On("UNIT_LEVEL", Buffs, function() if not M.InCombat() then Buffs:ScanSoon() end end)
  if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(15, function() if not M.InCombat() then Buffs:Scan() end end) end
end)
