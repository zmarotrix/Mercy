-- Click-casting: what each mouse button and modifier does on a frame, as secure attributes.
--
-- Friendly binds use the plain suffix ("shift-type1"). Clicking an enemy remaps the button through "*harmbutton1" to
-- "hostile1", so hostile binds live under "-hostile1" (SecureTemplates.lua, GetConvertedButtonUnitAndActionType).
-- Attributes can only change out of combat, so ApplyAll waits for it to end.

local Core = NorgannonCore
local M = Mercy
if M.disabled then return end

local Binds = {}
M.Binds = Binds

Binds.MODS = {
  { key = "none", prefix = "", label = "No modifier" },
  { key = "shift", prefix = "shift-", label = "Shift" },
  { key = "ctrl", prefix = "ctrl-", label = "Ctrl" },
  { key = "alt", prefix = "alt-", label = "Alt" },
  { key = "ctrl-shift", prefix = "ctrl-shift-", label = "Ctrl+Shift" },
  { key = "alt-shift", prefix = "alt-shift-", label = "Alt+Shift" },
  { key = "alt-ctrl", prefix = "alt-ctrl-", label = "Alt+Ctrl" },
  { key = "alt-ctrl-shift", prefix = "alt-ctrl-shift-", label = "Alt+Ctrl+Shift" },
}
Binds.BUTTONS = {
  { key = "Left", suffix = "1", click = "LeftButton", label = "Left" },
  { key = "Right", suffix = "2", click = "RightButton", label = "Right" },
  { key = "Middle", suffix = "3", click = "MiddleButton", label = "Middle" },
  { key = "Button4", suffix = "4", click = "Button4", label = "Back" },        -- the side buttons, as most mice name them
  { key = "Button5", suffix = "5", click = "Button5", label = "Forward" },
}
Binds.SETS = { "friendly", "hostile" }
Binds.SPECIAL = { "Target", "Assist", "Focus", "Context", "Follow", "Role", "Role: Tank", "Role: Healer", "Role: Damage", "Role: None" }

Binds.RES = { PRIEST = "Resurrection", PALADIN = "Redemption", SHAMAN = "Ancestral Spirit", DRUID = "Rebirth" }

local DEFAULTS = {
  PRIEST = { none = { Left = "Flash Heal", Right = "Renew", Middle = "Dispel Magic" },
    shift = { Left = "Greater Heal", Right = "Power Word: Shield", Middle = "Cure Disease" }, ctrl = { Left = "Target", Right = "Context" } },
  DRUID = { none = { Left = "Healing Touch", Right = "Rejuvenation", Middle = "Remove Curse" },
    shift = { Left = "Regrowth", Middle = "Abolish Poison" }, ctrl = { Left = "Target", Right = "Context" } },
  PALADIN = { none = { Left = "Flash of Light", Right = "Holy Light", Middle = "Cleanse" },
    shift = { Right = "Blessing of Protection" }, ctrl = { Left = "Target", Right = "Context" } },
  SHAMAN = { none = { Left = "Lesser Healing Wave", Right = "Healing Wave", Middle = "Cure Poison" },
    shift = { Left = "Chain Heal", Middle = "Cure Disease" }, ctrl = { Left = "Target", Right = "Context" } },
}

local function emptySet()
  local t = {}
  for _, mod in ipairs(Binds.MODS) do t[mod.key] = {} end
  return t
end

function Binds:Empty()
  return { friendly = emptySet(), hostile = emptySet() }
end

function Binds:Defaults(class)
  local b = self:Empty()
  local d = DEFAULTS[class]
  if d then
    for mod, buttons in pairs(d) do
      for btn, text in pairs(buttons) do b.friendly[mod][btn] = text end
    end
  else
    b.friendly.none.Left, b.friendly.none.Right = "Target", "Context"
  end
  b.hostile.none.Left, b.hostile.none.Right = "Target", "Context"
  return b
end

function Binds:InitChar()
  local c = M.char
  if type(c.binds) ~= "table" then
    c.binds = self:Defaults(M.PlayerClass())
    c.freshBinds = true
  end
  for _, set in ipairs(self.SETS) do
    c.binds[set] = c.binds[set] or {}
    for _, mod in ipairs(self.MODS) do c.binds[set][mod.key] = c.binds[set][mod.key] or {} end
  end
end

function Binds:Get(set, mod, btn)
  local b = M.char.binds[set]
  return b and b[mod] and b[mod][btn]
end

function Binds:Set(set, mod, btn, text)
  text = text and strtrim(text) or nil
  if text == "" then text = nil end
  M.char.binds[set][mod][btn] = text
  M.char.freshBinds = nil
  self:ApplyAll()
end

-------------------------------------------------------------------------------------------
-- What a bind means
-------------------------------------------------------------------------------------------

local ROLE = { tank = "TANK", healer = "HEALER", damage = "DAMAGER", dps = "DAMAGER", none = "NONE" }

---A bind's text as an action: { type, spell | item | macro | macrotext } for secure actions, or { role = ... } for
---the role binds, which run as ordinary code after the click.
function Binds.Parse(text)
  if type(text) ~= "string" then return nil end
  text = strtrim(text)
  if text == "" then return nil end
  local lower = string.lower(text)
  if lower == "target" then return { type = "target", label = "Target" } end
  if lower == "assist" then return { type = "assist", label = "Assist" } end
  if lower == "focus" then return { type = "focus", label = "Focus" } end
  if lower == "context" or lower == "menu" then return { type = "togglemenu", label = "Menu" } end
  if lower == "follow" then return { type = "macro", follow = true, label = "Follow" } end
  if lower == "role" or lower == "set role" then return { role = "menu", label = "Role" } end
  local role = lower:match("^role:%s*(%a+)$")
  if role and ROLE[role] then return { role = ROLE[role], label = text } end
  local item = text:match("^[Ii][Tt][Ee][Mm]:%s*(.+)$")
  if item then return { type = "item", item = item, label = item } end
  local macro = text:match("^[Mm][Aa][Cc][Rr][Oo]:%s*(.+)$")
  if macro then return { type = "macro", macro = macro, label = macro } end
  return { type = "spell", spell = text, label = text, isSpell = true }
end

---What a bind's text looks like: its icon (nil if none), and whether it matches something you have.
---Spells come from your spellbook, items by name, macros from your macro list; Target, Context and the like have no icon.
function Binds.Icon(text)
  local a = Binds.Parse(text)
  if not a then return nil, true end
  if a.isSpell then
    local info = M.Plain(M.Fn("C_Spell", "GetSpellInfo"), (a.spell:gsub("%s*%(.-%)%s*$", "")))
    if type(info) == "table" then return info.iconID or info.originalIconID, true end
    return nil, false
  end
  if a.item then
    local id, _, _, _, icon = M.Plain(M.Fn("C_Item", "GetItemInfoInstant"), a.item)
    return icon, id ~= nil
  end
  if a.macro then
    local name, icon = M.Plain(M.Fn(nil, "GetMacroInfo"), a.macro)
    return icon, name ~= nil
  end
  return nil, true
end

---The resurrection spell you know, or nil.
function Binds:ResSpell()
  local spell = self.RES[M.class or M.PlayerClass() or ""]
  if spell and M.Knows(spell) then return spell end
end

---A spell turned into a macro when it should also resurrect the dead or target the unit.
local function spellMacro(spell, unit, res, target)
  local lines = {}
  if res then
    lines[#lines + 1] = ("/cast [@%s,dead] %s; [@%s] %s"):format(unit, res, unit, spell)
  else
    lines[#lines + 1] = ("/cast [@%s] %s"):format(unit, spell)
  end
  if target then lines[#lines + 1] = "/target " .. unit end
  return table.concat(lines, "\n")
end

---The attributes for one button, as a table (also what the harness checks).
function Binds:Attributes(unit)
  local attrs = {
    ["*type1"] = "target", ["*type2"] = "togglemenu",                    -- an unbound click still does something sensible
    ["*type-hostile1"] = "target", ["*type-hostile2"] = "togglemenu",
    useOnKeyDown = M.db.castOn == "down",
  }
  for _, b in ipairs(self.BUTTONS) do attrs["*harmbutton" .. b.suffix] = "hostile" .. b.suffix end
  local res = M.db.autoRes and self:ResSpell() or nil
  for _, set in ipairs(self.SETS) do
    for _, mod in ipairs(self.MODS) do
      for _, b in ipairs(self.BUTTONS) do
        local a = self.Parse(self:Get(set, mod.key, b.key))
        if a and a.type then
          local suffix = set == "friendly" and b.suffix or ("-hostile" .. b.suffix)
          local p = mod.prefix
          if a.isSpell and set == "friendly" and (res or M.db.autoTarget) then
            attrs[p .. "type" .. suffix] = "macro"
            attrs[p .. "macrotext" .. suffix] = spellMacro(a.spell, unit, res, M.db.autoTarget)
          elseif a.follow then
            attrs[p .. "type" .. suffix] = "macro"
            attrs[p .. "macrotext" .. suffix] = "/follow " .. unit
          else
            attrs[p .. "type" .. suffix] = a.type
            if a.spell then attrs[p .. "spell" .. suffix] = a.spell end
            if a.item then attrs[p .. "item" .. suffix] = a.item end
            if a.macro then attrs[p .. "macro" .. suffix] = a.macro end
          end
        elseif a and a.role then
          -- role binds run in PostClick; the click itself does nothing secure
          attrs[mod.prefix .. "type" .. (set == "friendly" and b.suffix or ("-hostile" .. b.suffix))] = "noop"
        end
      end
    end
  end
  return attrs
end

---Writes a button's attributes. Out of combat only.
function Binds:Apply(button)
  if M.InCombat() then return false end
  local unit = button:GetAttribute("unit") or button.unit
  if not unit then return false end
  local attrs = self:Attributes(unit)
  if button.mercyKeys then
    for key in pairs(button.mercyKeys) do
      if attrs[key] == nil then button:SetAttribute(key, nil) end
    end
  end
  button.mercyKeys = {}
  for key, value in pairs(attrs) do
    button:SetAttribute(key, value)
    button.mercyKeys[key] = true
  end
  if button.RegisterForClicks then button:RegisterForClicks("AnyUp", "AnyDown") end
  return true
end

function Binds:ApplyAll()
  if M.UF then M.UF.rangeSpell = nil end   -- binds changed: measure range with the new heal
  Core:AfterCombat(function()
    if not M.Groups then return end
    for _, button in ipairs(M.Groups:Buttons()) do self:Apply(button) end
  end, "mercy-binds")
end

-------------------------------------------------------------------------------------------
-- Role binds, after the secure click
-------------------------------------------------------------------------------------------

local function modKey()
  local alt, ctrl, shift = IsAltKeyDown(), IsControlKeyDown(), IsShiftKeyDown()
  local parts = {}
  if alt then parts[#parts + 1] = "alt" end
  if ctrl then parts[#parts + 1] = "ctrl" end
  if shift then parts[#parts + 1] = "shift" end
  return #parts > 0 and table.concat(parts, "-") or "none"
end
Binds.ModKey = modKey

function Binds:PostClick(button, mouse, down)
  if down then return end
  local suffix
  for _, b in ipairs(self.BUTTONS) do if b.click == mouse then suffix = b.key end end
  if not suffix then return end
  local a = self.Parse(self:Get("friendly", modKey(), suffix))
  if not (a and a.role) then return end
  local unit = button:GetAttribute("unit") or button.unit
  if a.role == "menu" then
    self:RoleMenu(button, unit)
  else
    self:SetRole(unit, a.role)
  end
end

---Your own role marks, per realm, by name: for people the game has no role for. They only sort and label.
function Binds:Roles()
  local realm = M.Plain(GetRealmName) or "?"
  M.db.roles = M.db.roles or {}
  M.db.roles[realm] = M.db.roles[realm] or {}
  return M.db.roles[realm]
end

function Binds:SetRole(unit, role)
  local name = M.Plain(UnitName, unit)
  if not name then return end
  self:Roles()[name] = role ~= "NONE" and role or nil
  if M.Groups then M.Groups:UpdateAll() M.Groups:Layout() end
end

function Binds:RoleMenu(owner, unit)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("Role")
    for _, r in ipairs({ { "TANK", "Tank" }, { "HEALER", "Healer" }, { "DAMAGER", "Damage" }, { "NONE", "No role" } }) do
      root:CreateButton(r[2], function() self:SetRole(unit, r[1]) end)
    end
  end)
end

-------------------------------------------------------------------------------------------
-- For the spells tooltip
-------------------------------------------------------------------------------------------

---Every bind in a set as { key = "Shift-Left", text, action }, in modifier then button order.
function Binds:List(set)
  local out = {}
  for _, mod in ipairs(self.MODS) do
    for _, b in ipairs(self.BUTTONS) do
      local text = self:Get(set, mod.key, b.key)
      local a = self.Parse(text)
      if a then
        out[#out + 1] = { key = (mod.key == "none" and "" or (mod.label .. "-")) .. b.label, text = text, action = a, mod = mod.key }
      end
    end
  end
  return out
end
