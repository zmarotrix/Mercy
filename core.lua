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

if not (Core and Core.NewAddon) then
  Mercy = { disabled = true }
  print("Mercy needs NorgannonDB Core 1.26 or newer; it is turned off.")
  return
end

Mercy = Mercy or {}
local M = Mercy

-- The suite's plumbing (Core:NewAddon): version check, the slash command, the minimap row and the add-on menu. Mercy has
-- no main window: a click or right-click opens its settings window, and Shift-click locks or unlocks the frames.
-- Its saved data stays its own (M:InitDB), because of the schema steps below.
Core:NewAddon("mercy", {
  folder = ADDON, api = { 1, 26 },
  slash = { "/mercy" },
  commands = {
    binds = { function() M:OpenSettings("binds") end, "the click-casting tab" },
    frames = { function() M:OpenSettings("frames") end, "the frames tab" },
    indicators = { function() M:OpenSettings("indicators") end, "the indicators tab" },
    healersmate = { function() M:OpenSettings("healersmate") end, "the HealersMate tab" },
    lock = { function() M:SetLocked(true) M:Print("Frames locked.") end, "stop the groups being dragged" },
    unlock = { function()
      M:SetLocked(false, true)
      M:Print("Every group's name is showing, empty ones too: drag one to move it. /mercy lock when you're done.")
    end, "drag groups by their names" },
    reset = { function() M.Groups:ResetPositions() end, "put the groups back" },
    test = { function(rest) M.Test:Toggle(tonumber(rest)) end, "[5|10|20|40]: invented players, to place the frames" },
    import = { function(rest)
      if rest == "" then M.Import:FromHealersMate(true) else M.Import:FromString(rest) end
    end, "[string]: binds from HealersMate, or from a string" },
    status = { function() M:PrintStatus() end, "what the client allows here" },
    clicks = { function()
      M.debugClicks = not M.debugClicks
      M:Print(M.debugClicks and "Click report on: each click on a frame prints what the game did with it. /mercy clicks again to stop."
        or "Click report off.")
    end, "report what each click on a frame does (for bug reports)" },
  },
  minimap = {
    onShiftClick = function()
      M:SetLocked(not M.db.locked)
      M:Print(M.db.locked and "Frames locked." or "Frames unlocked: drag a group by its name.")
    end,
    shiftHint = "lock or unlock",
  },
})
if M.disabled then return end

M.GREEN = { 0.15, 0.85, 0.1 }   -- the health bar's green: a clear, warm green, not the blue-ish one 0.1.x had
M.IsSecret = Core.IsSecret

-------------------------------------------------------------------------------------------
-- Calling the client. Any call may be missing or refuse.
-------------------------------------------------------------------------------------------

-- Core's helpers, under the names Mercy's files use: Fn finds a client function; Try calls it and returns ok, ... with
-- secrets as they came; Plain turns secrets into nil, for logic that must branch; Set hands a widget values that may be
-- secret, and is false if the client refused.
M.Fn, M.Try, M.Plain, M.Set = Core.Fn, Core.Call, Core.Plain, Core.SetSecret

function M.InCombat()
  return InCombatLockdown and InCombatLockdown() and true or false
end

-------------------------------------------------------------------------------------------
-- Saved data: settings account-wide (MercyDB), binds per character (MercyCharDB)
-------------------------------------------------------------------------------------------

M.GROUPS = { "party", "raid", "tanks", "pets", "target", "focus" }

M.DEFAULTS = {
  locked = false,                   -- true: groups can't be dragged by their names (Lock the frames, /mercy lock)
  hideBlizzard = false,             -- Blizzard's party and raid frames stay unless you hide them (Frames tab)
  soloParty = true,                 -- party frames (you alone) when not in a group
  layout = "standard",              -- standard, compact, wide, tiny, classic
  raidLayout = "compact",
  raidBy = "group",                 -- group: one column per raid group; block: one block in raid order
  partySort = "role",               -- role, class, name, none
  color = "green",                  -- class, green, gradient
  nameColor = "class",              -- class or white
  panels = true,                    -- a rounded panel behind each group, with its name
  hideEmpty = true,                 -- a group's panel shows only when someone's in it
  syncAlpha = false,                -- one panel opacity for every group
  friendlyOnly = true,              -- target and focus frames only for friendly units
  text = "current",                 -- current, missing, percent, none
  shortNumbers = false,             -- 1.3K instead of 1339
  power = "healers",                -- healers, all, none
  range = true,
  rangeAlpha = 0.4,
  lowHealth = true,                 -- red pulse below 25%
  highlight = "blizzard",           -- blizzard (the game's raid frame dispel display, works in combat) or mercy (our border)
  dispelScope = "mine",             -- mine (HARMFUL|RAID) or any (HARMFUL|RAID_PLAYER_DISPELLABLE)
  debuffIcons = true,
  myBuffs = true,                   -- your buffs and HoTs on people
  buffReminders = true,             -- who needs your buffs, out of combat
  rebuffButton = true,              -- the button that casts the next one
  rebuffMinutes = 5,                -- a buff with less than this left counts as needed
  buffTrack = {},                   -- [key] = on/off, for your class's buffs (older saves; buffWho replaces it)
  buffWho = {},                     -- [key] = "off", "all", "mana" or "tanks": who your class's buffs are for
  customBuffs = {},                 -- { { name, who } }: buffs you added yourself
  buffShow = "missing",             -- marks show what's "missing", or what they're "buffed" with
  downrank = true,                  -- buffs on someone too low for your best rank go down to one that lands
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
  -- 0.2.3: frames start locked, so empty panels can hide ("only when needed"); unlocked was only ever the default
  if self.db.schema < 4 then
    self.db.locked = true
    self.db.schema = 4
  end
  -- 0.2.7: dragging by a group's name works again by default; 0.2.4-0.2.6 locked every save, which only hid empty panels
  if self.db.schema < 5 then
    self.db.locked = false
    self.db.schema = 5
  end
  -- 0.2.10: Blizzard's party and raid frames aren't hidden by default any more (they were only ever hidden by default)
  if self.db.schema < 6 then
    self.db.hideBlizzard = false
    self.db.schema = 6
  end
  -- 0.2.14: the game's own dispel display is the default, in and out of combat (Mercy's border was only ever the default)
  if self.db.schema < 7 then
    self.db.highlight = "blizzard"
    self.db.schema = 7
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

M:OnReady(function() M:InitDB() end)

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
    -- the roster settles over the first seconds after login: sort and redraw again then
    if C_Timer and C_Timer.After then
      for _, delay in ipairs({ 2, 6 }) do C_Timer.After(delay, function() M.Groups:RosterChanged() end) end
    end
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
-- Settings, locking and status
-------------------------------------------------------------------------------------------

---Mercy's own settings window (it replaces NewAddon's, which opens the game's Settings page).
function M:OpenSettings(tab)
  if self.Settings then self.Settings:Open(tab) end
end

---Lock (no dragging) or unlock. Unlocking with /mercy unlock also shows every group's name, empty ones too, until you lock again,
---so a Focus or Target with nobody in it can be found and moved.
---A group's panel opacity, or every group's when "Same opacity for every group" is on.
function M:SetPanelAlpha(key, alpha)
  if self.db.syncAlpha then
    for _, k in ipairs(self.GROUPS) do self:Group(k).alpha = alpha end
  else
    self:Group(key).alpha = alpha
  end
  if self.Groups then self.Groups:UpdateMovers() end
end

function M:SetLocked(locked, showAll)
  self.db.locked = locked and true or false
  self.showAll = (not locked and showAll) and true or false
  if self.Groups then self.Groups:UpdateMovers() end
end

function M:PrintStatus()
  local a = self.Auras
  self:Print(("Highlight: %s. Blizzard's aura drawing on our frames: %s. Our dispel count: %s.")
    :format(self.db.highlight == "mercy" and "Mercy's" or "Blizzard style",
      a.containerState or "not tried", a.countState or "not tried"))
  self:Print(("You can remove: %s."):format(a:CuresText()))
  if self.InCombat() then self:Print("In combat: layout and bind changes wait for it to end.") end
end
