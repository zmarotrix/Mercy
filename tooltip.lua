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

---The binds for the modifier you're holding: every button, "Unbound" where there's nothing, redrawn as soon as you press or
---let go of Shift, Ctrl or Alt (as HealersMate's tooltip does).
function Tooltip:Show(b)
  if not (M.db.spellsTooltip or M.db.unitTooltip) then return end
  self.owner = b
  local tt = GameTooltip
  tt:SetOwner(b, "ANCHOR_RIGHT")
  tt:ClearLines()
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
    local set = hostile and "hostile" or "friendly"
    local mod = M.Binds.ModKey()
    local label = "No modifier"
    for _, m in ipairs(M.Binds.MODS) do if m.key == mod then label = m.label end end
    tt:AddDoubleLine(hostile and "Hostile binds" or "Binds", label, M.ACCENT[1], M.ACCENT[2], M.ACCENT[3], 0.66, 0.63, 0.54)
    local mana = M.Plain(UnitPower, "player", 0)
    for _, button in ipairs(M.Binds.BUTTONS) do
      local text = M.Binds:Get(set, mod, button.key)
      local action = M.Binds.Parse(text)
      if action then
        local right = text
        local cost = action.isSpell and manaCost(action.spell)
        if cost and cost > 0 and mana then
          local casts = math.floor(mana / cost)
          right = right .. (casts <= LOW and "  |cffff9a6a" or "  |cffa8a08a") .. casts .. "|r"
        end
        tt:AddDoubleLine(button.label, right, 1, 0.82, 0, 1, 1, 1)
      else
        tt:AddDoubleLine(button.label, "Unbound", 1, 0.82, 0, 0.43, 0.4, 0.32)
      end
    end
    if mod == "none" then tt:AddLine("Hold Shift, Ctrl or Alt for more", 0.43, 0.4, 0.32) end
  end
  tt:Show()
end

function Tooltip:Hide()
  self.owner = nil
  GameTooltip:Hide()
end

Core:On("MODIFIER_STATE_CHANGED", Tooltip, function()
  local b = Tooltip.owner
  if b and GameTooltip:IsShown() and GameTooltip:GetOwner() == b then Tooltip:Show(b) end
end)
