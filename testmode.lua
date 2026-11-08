-- Test mode: invented players with damage, debuffs and roles, to place and style the frames. Out of combat only,
-- because it shows and hides protected frames. /mercy test 5 | 10 | 20 | 40, and /mercy test again to stop.

local Core = NorgannonCore
local M = Mercy
if M.disabled then return end

local Test = {}
M.Test = Test

local NAMES = { "Brunhok", "Thalindra", "Sefira", "Tessarine", "Wynne", "Corwyn", "Hallek", "Vashti", "Merek", "Ylva", "Aldwin",
  "Korrin", "Liora", "Isaura", "Dorrik", "Pellan", "Ostrid", "Maevin", "Garreth", "Rhiannon", "Elowen", "Tobren", "Halvard",
  "Brannoch", "Arhara", "Fennick", "Orla", "Draven", "Sabine", "Quill", "Marrow", "Ebba", "Thorne", "Lysa", "Cadoc", "Neve",
  "Bram", "Ione", "Tavish", "Wren" }
local CLASSES = { "WARRIOR", "PRIEST", "ROGUE", "MAGE", "DRUID", "SHAMAN", "PALADIN", "WARLOCK", "HUNTER" }
local ROLES = { WARRIOR = "TANK", PRIEST = "HEALER", DRUID = "HEALER", SHAMAN = "HEALER", PALADIN = "TANK" }
local DEBUFFS = {
  Magic = { icon = 135848 }, Curse = { icon = 136139 }, Disease = { icon = 136127 }, Poison = { icon = 136016 },
  none = { icon = 132355 },
}

local function fake(i)
  local class = CLASSES[(i - 1) % #CLASSES + 1]
  local f = { name = NAMES[i] or ("Player" .. i), class = class, role = ROLES[class] or "DAMAGER",
    hp = 100 - ((i * 37) % 70), subgroup = math.ceil(i / 5), mana = 40 + (i * 13) % 60 }
  if class == "PALADIN" and i > 7 then f.role = "HEALER" end
  f.inc = i % 3 == 0 and 12 or 0
  f.incMine = i % 4 == 1 and 10 or 0
  f.absorb = i == 1 and 15 or 0
  f.far = i % 7 == 0
  f.dead = i % 11 == 0
  f.aggro = i == 1
  f.needBuff = i % 3 == 0
  -- your HoTs on a few of them
  if i % 2 == 1 then f.buffs = { { icon = 135953 }, i % 4 == 1 and { icon = 135940 } or nil } end
  local types = { "Magic", "Curse", "Disease", "Poison", "none" }
  if i % 3 == 2 then
    local t = types[i % 5 + 1]
    f.debuffs = { { type = t, icon = DEBUFFS[t].icon } }
    if t ~= "none" then f.dispel = t end
    if i % 6 == 5 then f.debuffs[2] = { type = "none", icon = DEBUFFS.none.icon, stacks = 3 } end
  end
  return f
end

function Test:Toggle(n)
  if M.InCombat() then M:Print("Test mode waits for combat to end.") return end
  if self.active and not n then self:Stop() return end
  if self.active then self:Stop() end
  self:Start(n or 5)
end

function Test:Start(n)
  if not M.Groups.built then return end
  n = math.max(1, math.min(40, math.floor(n)))
  local key = n <= 5 and "party" or "raid"
  M:Group(key).on = true
  if not M.Groups.frames[key] then M.Groups:BuildGroup(key) M.Groups:Attach() M.Binds:ApplyAll() end
  self.active, self.key, self.count = true, key, n
  local g = M.Groups.frames[key]
  for i, b in ipairs(g.buttons) do
    UnregisterUnitWatch(b)
    if i <= n then
      b.fake = fake(i)
      b:Show()
    else
      b.fake = nil
      b:Hide()
    end
  end
  M.Groups:Layout()
  M.Groups:UpdateAll()
  M:Print(("Test mode: %d invented players. Drag a group by its label to move it; /mercy test again to stop."):format(n))
end

function Test:Stop()
  if not self.active then return end
  local g = M.Groups.frames[self.key]
  self.active = false
  if g then
    for _, b in ipairs(g.buttons) do
      b.fake = nil
      if not b.slot then RegisterUnitWatch(b) end
    end
  end
  M.Groups:Layout()
  M.Groups:UpdateAll()
  M:Print("Test mode off.")
end

-- combat ends test mode: the frames need to show real people
Core:On("PLAYER_REGEN_DISABLED", Test, function()
  if Test.active then
    Test.active = false
    M:Print("Test mode stops when combat ends.")
    Core:AfterCombat(function()
      Test.active = true
      Test:Stop()
    end, "mercy-test-stop")
  end
end)
