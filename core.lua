-- Mercy: healer frames. Built on NorgannonDB_Core.
-- Plan and client findings: docs/mercy-v1.md; the look: design/suite/mercy.html.
--
-- Two rules the whole add-on keeps:
--   1. Protected frames (the unit buttons and their groups) are only created, shown, hidden, moved or given new
--      attributes out of combat. Anything asked for in combat waits for it to end (Core:AfterCombat).
--   2. A value that may be secret (health, auras, range, threat) is never compared, added or turned into text by us.
--      It's handed straight to a widget that accepts secrets, or checked with Core.IsSecret first.

local ADDON = ...
local Core = NorgannonCore

Mercy = Mercy or {}
local M = Mercy
M.addonName = ADDON or "Mercy"

if not (Core and Core:Require(1, 17)) then
  M.disabled = true
  C_Timer.After(5, function()
    print("|cffffeea0Mercy|r needs NorgannonDB Core 1.17 or newer; it is turned off.")
  end)
  return
end

M.PREFIX = "|cffffeea0Mercy|r"
M.ACCENT = { 1, 0.933, 0.627 }
M.GREEN = { 0.15, 0.85, 0.1 }   -- the health bar's green: a clear, warm green, not the blue-ish one 0.1.x had
function M:Print(msg) Core:Print(msg, self.PREFIX) end
M.IsSecret = Core.IsSecret

-------------------------------------------------------------------------------------------
-- Calling the client. Any call may be missing or refuse.
-------------------------------------------------------------------------------------------

---ns.name, or the global name when ns is nil; nil if the client lacks it.
function M.Fn(ns, name)
  if not ns then
    local fn = rawget(_G, name)
    return type(fn) == "function" and fn or nil
  end
  local t = rawget(_G, ns)
  local fn = type(t) == "table" and t[name]
  return type(fn) == "function" and fn or nil
end

---Calls a client function. Returns ok, ... with the values as they came, secrets included.
function M.Try(fn, ...)
  if type(fn) ~= "function" then return false end
  return pcall(fn, ...)
end

local function clean(ok, ...)
  if not ok then return nil end
  local n = select("#", ...)
  if n == 0 then return nil end
  local out = { ... }
  for i = 1, n do
    if Core.IsSecret(out[i]) then out[i] = nil end
  end
  return unpack(out, 1, n)
end

---The answer with every secret value turned into nil: for logic that must branch.
function M.Plain(fn, ...)
  if type(fn) ~= "function" then return nil end
  return clean(pcall(fn, ...))
end

---A widget method call that may get secret arguments; false if the client refused.
function M.Set(obj, method, ...)
  local fn = obj and obj[method]
  if type(fn) ~= "function" then return false end
  return (pcall(fn, obj, ...))
end

function M.InCombat()
  return InCombatLockdown and InCombatLockdown() and true or false
end

-------------------------------------------------------------------------------------------
-- Saved data: settings account-wide (MercyDB), binds per character (MercyCharDB)
-------------------------------------------------------------------------------------------

M.GROUPS = { "party", "raid", "tanks", "pets", "target", "focus" }

M.DEFAULTS = {
  locked = false,
  hideBlizzard = true,
  soloParty = true,                 -- party frames (you alone) when not in a group
  layout = "standard",              -- standard, compact, wide, tiny, classic
  raidLayout = "compact",
  raidBy = "group",                 -- group: one column per raid group; block: one block in raid order
  partySort = "role",               -- role, class, name, none
  color = "green",                  -- class, green, gradient
  nameColor = "class",              -- class or white
  panels = true,                    -- a rounded panel behind each group, with its name
  text = "current",                 -- current, missing, percent, none
  power = "healers",                -- healers, all, none
  range = true,
  rangeAlpha = 0.4,
  lowHealth = true,                 -- red pulse below 25%
  highlight = "mercy",              -- mercy (our border) or blizzard (the game's overlay)
  dispelScope = "mine",             -- mine (HARMFUL|RAID) or any (HARMFUL|RAID_PLAYER_DISPELLABLE)
  debuffIcons = true,
  myBuffs = true,                   -- your buffs and HoTs on people
  buffReminders = true,             -- who needs your buffs, out of combat
  rebuffButton = true,              -- the button that casts the next one
  rebuffMinutes = 5,                -- a buff with less than this left counts as needed
  buffTrack = {},                   -- [key] = on/off, for your class's buffs
  maxBuffs = 3,
  maxDebuffs = 3,
  aggro = true,
  castOn = "up",                    -- up or down
  autoRes = true,
  autoTarget = false,
  spellsTooltip = true,
  unitTooltip = false,
  groups = {},                      -- [key] = { on, point, x, y }
  firstRun = true,
}
M.GROUP_DEFAULTS = {
  party = { on = true, point = "LEFT", x = 220, y = 80 },
  raid = { on = true, point = "LEFT", x = 220, y = 120 },
  tanks = { on = true, point = "LEFT", x = 220, y = 260 },
  pets = { on = false, point = "LEFT", x = 220, y = -140 },
  target = { on = true, point = "LEFT", x = 400, y = 80 },
  focus = { on = false, point = "LEFT", x = 400, y = 20 },
}

local function fill(t, defaults)
  for k, v in pairs(defaults) do
    if t[k] == nil then
      if type(v) == "table" then t[k] = {} fill(t[k], v) else t[k] = v end
    end
  end
end

function M:Group(key)
  local g = self.db.groups[key]
  if not g then
    g = {}
    self.db.groups[key] = g
  end
  fill(g, self.GROUP_DEFAULTS[key] or { on = false, point = "CENTER", x = 0, y = 0 })
  return g
end

function M:InitDB()
  local saved = rawget(_G, "MercyDB")
  MercyDB = type(saved) == "table" and saved or {}
  fill(MercyDB, self.DEFAULTS)
  self.db = MercyDB
  -- 0.1.3: green bars and class-coloured names became the defaults. Nobody chose class bars before, they were just the default.
  if (self.db.schema or 1) < 2 then
    if self.db.color == "class" then self.db.color = "green" end
    self.db.schema = 2
  end
  -- 0.1.7: current health under the name became the default (missing health was only ever the default before)
  if self.db.schema < 3 then
    if self.db.text == "missing" then self.db.text = "current" end
    self.db.schema = 3
  end
  for _, key in ipairs(self.GROUPS) do self:Group(key) end
  local char = rawget(_G, "MercyCharDB")
  MercyCharDB = type(char) == "table" and char or {}
  self.char = MercyCharDB
  if self.Binds then self.Binds:InitChar() end
end

-------------------------------------------------------------------------------------------
-- The player
-------------------------------------------------------------------------------------------

function M.PlayerClass()
  local _, class = M.Plain(UnitClass, "player")
  return class
end

---Is this spell (by name, ranks stripped) in your spellbook?
function M.Knows(name)
  if type(name) ~= "string" or name == "" then return false end
  local base = name:gsub("%s*%(.-%)%s*$", "")
  local info = M.Plain(M.Fn("C_Spell", "GetSpellInfo"), base)
  if type(info) == "table" then return info.spellID ~= nil end
  local legacy = M.Fn(nil, "GetSpellInfo")
  return legacy and M.Plain(legacy, base) ~= nil or false
end

-------------------------------------------------------------------------------------------
-- Start-up and change notices
-------------------------------------------------------------------------------------------

---Settings changed: rebuild what depends on them. Layout and binds wait for combat to end.
function M:Changed(what)
  if what == "binds" or what == nil then
    if self.Binds then self.Binds:ApplyAll() end
  end
  if what == "layout" or what == nil then
    if self.Groups then self.Groups:Layout() end
  end
  if self.Auras then self.Auras:SettingsChanged() end
  if self.Groups then self.Groups:UpdateAll() end
  if self.Buffs then self.Buffs:Reset() end
  if self.Settings then self.Settings:Refresh() end
end

Core:On("ADDON_LOADED", M, function(_, name)
  if name ~= M.addonName then return end
  Core:Off("ADDON_LOADED", M)
  M:InitDB()
end)

Core:OnLogin(function()
  if not M.db then return end
  M.class = M.PlayerClass()
  if M.Curves then M.Curves:Build() end
  if M.Auras then M.Auras:Init() end
  -- the frames are protected: if you log in or reload in combat they're built when it ends
  Core:AfterCombat(function()
    M.Groups:Build()
    M.Binds:ApplyAll()
    M.Groups:Layout()
    M.Groups:HideBlizzard(M.db.hideBlizzard)
    M.Groups:UpdateAll()
  end, "mercy-start")
  if M.Import then M.Import:OnLogin() end
end)

Core:On("SPELLS_CHANGED", M, function()
  if not M.db or not M.Groups or not M.Groups.built then return end
  M.Auras:SpellsChanged()
  M.Binds:ApplyAll()
  if M.Buffs then M.Buffs:Reset() end
end)

-------------------------------------------------------------------------------------------
-- Commands, the minimap button and the suite
-------------------------------------------------------------------------------------------

Core:RegisterAddon("mercy", {
  version = C_AddOns and C_AddOns.GetAddOnMetadata(M.addonName, "Version") or "0.1.0",
  open = function() M:OpenSettings() end,
})

function M:OpenSettings(tab)
  if self.Settings then self.Settings:Open(tab) end
end

function M:SetLocked(locked)
  self.db.locked = locked and true or false
  if self.Groups then self.Groups:UpdateMovers() end
end

SLASH_MERCY1 = "/mercy"
SlashCmdList["MERCY"] = function(msg)
  msg = strtrim(msg or "")
  local lower = string.lower(msg)
  local cmd, rest = lower:match("^(%S+)%s*(.-)$")
  if lower == "" or lower == "settings" or lower == "options" then
    M:OpenSettings()
  elseif cmd == "binds" or cmd == "frames" or cmd == "indicators" or cmd == "healersmate" then
    M:OpenSettings(cmd)
  elseif lower == "lock" then
    M:SetLocked(true) M:Print("Frames locked.")
  elseif lower == "unlock" then
    M:SetLocked(false) M:Print("Frames unlocked: drag a group by its label. /mercy lock when you're done.")
  elseif lower == "reset" then
    M.Groups:ResetPositions()
  elseif cmd == "test" then
    M.Test:Toggle(tonumber(rest))
  elseif cmd == "import" then
    local text = strtrim(msg:sub(8))
    if text == "" then M.Import:FromHealersMate(true) else M.Import:FromString(text) end
  elseif lower == "status" then
    M:PrintStatus()
  else
    M:Print("/mercy opens settings. Also: test [5|10|20|40], lock, unlock, reset, import [string], status")
  end
end

function M:PrintStatus()
  local a = self.Auras
  self:Print(("Highlight: %s. Blizzard's aura drawing on our frames: %s. Our dispel count: %s.")
    :format(self.db.highlight == "mercy" and "Mercy's" or "Blizzard style",
      a.containerState or "not tried", a.countState or "not tried"))
  self:Print(("You can remove: %s."):format(a:CuresText()))
  if self.InCombat() then self:Print("In combat: layout and bind changes wait for it to end.") end
end

local function onClick(button)
  if button == "RightButton" then
    M:SetLocked(not M.db.locked)
    M:Print(M.db.locked and "Frames locked." or "Frames unlocked: drag a group by its label.")
  else
    M:OpenSettings()
  end
end
local function tooltip(tt)
  tt:AddLine("Mercy", M.ACCENT[1], M.ACCENT[2], M.ACCENT[3])
  tt:AddLine("Healer frames", 1, 1, 1)
  tt:AddLine("Click: settings  ·  Right-click: lock or unlock  ·  Drag: move", .43, .4, .32)
end
Core:OnLogin(function()
  if M.db then Core.MinimapButton:Add("mercy", { onClick = onClick, tooltip = tooltip }) end
end)
function Mercy_OnAddonCompartmentClick(_, button) onClick(button) end
function Mercy_OnAddonCompartmentEnter(_, frame)
  GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
  tooltip(GameTooltip)
  GameTooltip:Show()
end
function Mercy_OnAddonCompartmentLeave() GameTooltip:Hide() end
