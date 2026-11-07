-- Moving over from HealersMate: its binds and main settings, read from its saved variables (only there while
-- HealersMate is loaded) or from one of its export strings. HealersMate itself is never changed, except that
-- "Use them" turns it off for this character so you don't get two sets of frames.

local Core = NorgannonCore
local M = Mercy
if M.disabled then return end

local Import = {}
M.Import = Import

local MODS = { None = "none", Shift = "shift", Control = "ctrl", Alt = "alt", ["Shift+Control"] = "ctrl-shift",
  ["Shift+Alt"] = "alt-shift", ["Control+Alt"] = "alt-ctrl", ["Shift+Control+Alt"] = "alt-ctrl-shift" }
local BUTTONS = { LeftButton = "Left", RightButton = "Right", MiddleButton = "Middle", Button4 = "Button4", Button5 = "Button5" }
local LEGACY_MODS = { [0] = "None", "Shift", "Control", "Alt", "Shift+Control", "Shift+Alt", "Control+Alt", "Shift+Control+Alt" }
local LEGACY_BUTTONS = { "LeftButton", "RightButton", "MiddleButton", "Button4", "Button5" }
local LAYOUTS = { ["Default"] = "standard", ["Default (Short Bar)"] = "standard", ["Small"] = "compact", ["Very Small"] = "tiny",
  ["Very Small (Horizontal)"] = "tiny", ["Long"] = "wide", ["Long (Small)"] = "wide", ["Long (Integrated)"] = "wide", ["Legacy"] = "classic" }
Import.LAYOUTS = LAYOUTS

function Import:Loaded()
  local fn = M.Fn("C_AddOns", "IsAddOnLoaded") or M.Fn(nil, "IsAddOnLoaded")
  return fn and M.Plain(fn, "HealersMate") == true or false
end

local function saved()
  local char, account = rawget(_G, "HealersMateCharDB"), rawget(_G, "HealersMateDB")
  return type(char) == "table" and char or nil, type(account) == "table" and account or nil
end

---HealersMate's spells table ({ Friendly = { [mod] = { [button] = text } }, Hostile = ... }) as Mercy binds.
function Import.Convert(spells)
  local binds, count, ranks = M.Binds:Empty(), 0, 0
  for ctx, set in pairs({ Friendly = "friendly", Hostile = "hostile" }) do
    for mod, buttons in pairs(type(spells[ctx]) == "table" and spells[ctx] or {}) do
      local m = MODS[mod]
      if m and type(buttons) == "table" then
        for btn, text in pairs(buttons) do
          local b = BUTTONS[btn]
          if b and type(text) == "string" and strtrim(text) ~= "" then
            binds[set][m][b] = strtrim(text)
            count = count + 1
            if text:find("%(Rank") then ranks = ranks + 1 end
          end
        end
      end
    end
  end
  return binds, count, ranks
end

---What HealersMate has for this character, for the settings tab: nil if it isn't loaded.
function Import:Summary()
  if not self:Loaded() then return nil end
  local char, account = saved()
  local spells = char and char.spells
  local _, count, ranks = self.Convert(type(spells) == "table" and spells or {})
  local opt = account and account.options or {}
  local profiles = type(opt.ChosenProfiles) == "table" and opt.ChosenProfiles or {}
  local extra = type(opt.TrackedDebuffsExtra) == "table" and #opt.TrackedDebuffsExtra or 0
  return { binds = count, ranks = ranks, party = profiles.Party, raid = profiles.Raid, extraDebuffs = extra }
end

local function applyOptions(opt)
  if type(opt) ~= "table" then return end
  local db = M.db
  if opt.AutoResurrect ~= nil then db.autoRes = opt.AutoResurrect and true or false end
  if opt.AutoTarget ~= nil then db.autoTarget = opt.AutoTarget and true or false end
  if opt.CastWhen then db.castOn = opt.CastWhen == "Mouse Down" and "down" or "up" end
  if opt.ShowWhenSolo ~= nil then db.soloParty = opt.ShowWhenSolo and true or false end
  if opt.ShowUnitTooltip ~= nil then db.unitTooltip = opt.ShowUnitTooltip and true or false end
  if opt.HideBlizzardParty or opt.HideBlizzardRaid then db.hideBlizzard = true end
  if type(opt.ShowFocus) == "boolean" then M:Group("focus").on = opt.ShowFocus end
  local profiles = type(opt.ChosenProfiles) == "table" and opt.ChosenProfiles or {}
  if LAYOUTS[profiles.Party] then db.layout = LAYOUTS[profiles.Party] end
  if LAYOUTS[profiles.Raid] then db.raidLayout = LAYOUTS[profiles.Raid] end
  if type(opt.SpellsTooltip) == "table" and opt.SpellsTooltip.Enabled ~= nil then db.spellsTooltip = opt.SpellsTooltip.Enabled and true or false end
end

---Uses HealersMate's binds and settings. confirmed: from a click or /mercy import, so HealersMate may be turned off.
function Import:FromHealersMate(confirmed)
  if not self:Loaded() then
    M:Print("HealersMate isn't loaded, so its settings can't be read. Turn it on, /reload, then /mercy import. Or paste one of its export strings: /mercy import HM2|...")
    return false
  end
  local char, account = saved()
  local spells = char and char.spells
  if type(spells) ~= "table" then M:Print("HealersMate has no binds saved for this character.") return false end
  local binds, count = self.Convert(spells)
  M.char.binds = binds
  M.char.freshBinds = nil
  applyOptions(account and account.options)
  M.db.firstRun = false
  M.char.importedFrom = "HealersMate"
  if confirmed then
    local disable = M.Fn("C_AddOns", "DisableAddOn") or M.Fn(nil, "DisableAddOn")
    if disable then pcall(disable, "HealersMate", M.Plain(UnitName, "player")) end
    M:Print(("Imported %d binds from HealersMate. HealersMate is off for this character from your next /reload."):format(count))
  end
  M:Changed()
  return true
end

---A HealersMate export string: "HM2|key=value;...|F:<mod>:<button>=<spell>|..." or the older "w:h:p:flags:...|F<m><b>=<spell>".
function Import.ParseString(text)
  text = strtrim(text or "")
  if text == "" then return nil end
  local spells = { Friendly = {}, Hostile = {} }
  for _, ctx in ipairs({ "Friendly", "Hostile" }) do
    for mod in pairs(MODS) do spells[ctx][mod] = {} end
  end
  local options = {}
  if text:sub(1, 4) == "HM2|" then
    local first = true
    for field in text:sub(5):gmatch("[^|]+") do
      local tag, mod, btn, spell = field:match("^([FH]):([%w%+]+):(%w+)=(.+)$")
      if tag and MODS[mod] and BUTTONS[btn] then
        spells[tag == "F" and "Friendly" or "Hostile"][mod][btn] = spell
      elseif first then
        for k, v in field:gmatch("(%w+)=([^;]*)") do
          if v == "1" then v = true elseif v == "0" then v = false end
          options[k] = v
        end
      end
      first = false
    end
  else
    local rest = text:match("^%d+:%d+:%d+:%d+:%d+:%d+:%d+:(.*)$") or text:match("^%d+:%d+:%d+:%d+:(.*)$")
    if not rest then return nil end
    for part in rest:gmatch("[^|]+") do
      local ctx, m, b, spell = part:match("^([FH])(%d)(%d)=(.+)$")
      local mod, btn = ctx and LEGACY_MODS[tonumber(m)], ctx and LEGACY_BUTTONS[tonumber(b)]
      if mod and btn then spells[ctx == "F" and "Friendly" or "Hostile"][mod][btn] = spell end
    end
  end
  return spells, options
end

function Import:FromString(text)
  local spells, options = self.ParseString(text)
  if not spells then M:Print("That isn't a HealersMate export string.") return false end
  local binds, count = self.Convert(spells)
  if count == 0 then M:Print("That string has no binds in it.") return false end
  M.char.binds = binds
  M.char.freshBinds = nil
  applyOptions(options)
  M.char.importedFrom = "HealersMate string"
  M:Print(("Imported %d binds."):format(count))
  M:Changed()
  return true
end

---On login: if HealersMate is here and Mercy is new to this character, say once where to bring its settings over.
function Import:OnLogin()
  if not (M.char.freshBinds and self:Loaded()) or M.char.toldAboutImport then return end
  M.char.toldAboutImport = true
  C_Timer.After(4, function()
    M:Print("HealersMate is installed. To bring its binds over and turn it off for this character: /mercy import (or /mercy healersmate to see what it has first).")
  end)
end
