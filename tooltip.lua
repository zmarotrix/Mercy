-- The spells tooltip: hovering a frame lists your binds for it, with how many casts your mana allows.
-- With "unit tooltip" on, the game's own unit tooltip comes first (which also sets @mouseover for your macros).

local Core = NorgannonCore
local M = Mercy
if M.disabled then return end

local Tooltip = {}
M.Tooltip = Tooltip

local LOW = 3   -- this many casts or fewer shows in orange

---Mana a spell costs, or nil (unknown, or not mana).
local function manaCost(spell)
  local fn = M.Fn("C_Spell", "GetSpellPowerCost")
  if not fn then return nil end
  local costs = M.Plain(fn, (spell:gsub("%s*%(.-%)%s*$", "")))
  if type(costs) ~= "table" then return nil end
  for _, c in ipairs(costs) do
    if type(c) == "table" and (c.type == 0 or c.name == "MANA") and type(c.cost) == "number" and not M.IsSecret(c.cost) then
      return c.cost
    end
  end
end

function Tooltip:Show(b)
  if not (M.db.spellsTooltip or M.db.unitTooltip) then return end
  local tt = GameTooltip
  tt:SetOwner(b, "ANCHOR_RIGHT")
  local hostile = false
  if b.fake then
    tt:AddLine(b.fake.name, 1, 1, 1)
    tt:AddLine("Test frame", 0.66, 0.63, 0.54)
  else
    if not (M.db.unitTooltip and M.Set(tt, "SetUnit", b.unit)) then
      local ok, name = pcall(UnitName, b.unit)
      if ok and name ~= nil then M.Set(tt, "AddLine", name, 1, 1, 1) end
    end
    hostile = M.Plain(UnitCanAttack, "player", b.unit) == true
  end
  if M.db.spellsTooltip then
    local mana = M.Plain(UnitPower, "player", 0)
    tt:AddLine(hostile and "Your hostile binds" or "Your binds", M.ACCENT[1], M.ACCENT[2], M.ACCENT[3])
    local list = M.Binds:List(hostile and "hostile" or "friendly")
    if #list == 0 then tt:AddLine("None yet: /mercy binds", 0.66, 0.63, 0.54) end
    for _, row in ipairs(list) do
      local right = row.text
      local cost = row.action.isSpell and manaCost(row.action.spell)
      if cost and cost > 0 and mana then
        local casts = math.floor(mana / cost)
        right = right .. (casts <= LOW and "  |cffff9a6a" or "  |cffa8a08a") .. casts .. "|r"
      end
      tt:AddDoubleLine(row.key, right, 1, 0.82, 0, 1, 1, 1)
    end
  end
  tt:Show()
end

function Tooltip:Hide()
  GameTooltip:Hide()
end
