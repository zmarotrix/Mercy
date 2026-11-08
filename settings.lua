-- Mercy's settings window (design/suite/mercy.html): Frames, Click-casting, Indicators and HealersMate. /mercy
-- A small page under NorgannonDB in the game's Settings opens it too.

local Core = NorgannonCore
local M = Mercy
if M.disabled then return end
local UI = Core.UI
local C = UI.C

local Settings = { panes = {} }
M.Settings = Settings

local W, H = 640, 580
local TABS = { { key = "frames", label = "Frames" }, { key = "binds", label = "Click-casting" },
  { key = "indicators", label = "Indicators" }, { key = "healersmate", label = "HealersMate" } }

local win

local function changed(what) M:Changed(what) end
local function opt(key, what) return function() return M.db[key] end, function(v) M.db[key] = v changed(what) end end

-------------------------------------------------------------------------------------------
-- Frames
-------------------------------------------------------------------------------------------

Settings.panes.frames = function(parent)
  local list = UI.SettingsList(parent)
  list:Header("Layout")
  list:Dropdown("Party frames", "A starting point for size and text.", M.UF.LAYOUT_NAMES, opt("layout", "layout"))
  list:Dropdown("Raid frames", nil, M.UF.LAYOUT_NAMES, opt("raidLayout", "layout"))
  list:Dropdown("Raid arrangement", nil, { { "group", "By raid group" }, { "block", "One block" } }, opt("raidBy", "layout"))
  list:Dropdown("Sort the party by", "Applied when combat ends.", { { "role", "Role" }, { "class", "Class" }, { "name", "Name" }, { "none", "Party order" } },
    opt("partySort", "layout"))
  list:Header("Groups")
  local labels = { party = { "Party", "You and your party." }, raid = { "Raid", nil }, tanks = { "Tanks", "Tanks in a raid, in their own frames." },
    pets = { "Pets", "Your pet and your party's." }, target = { "Target", nil }, focus = { "Focus", nil } }
  for _, key in ipairs(M.GROUPS) do
    list:Toggle(labels[key][1], labels[key][2], function() return M:Group(key).on end,
      function(on) M:Group(key).on = on changed("layout") end)
  end
  list:Toggle("Panels behind the groups", "A rounded panel with the group's name.", opt("panels", "layout"))
  list:Toggle("Party frames when you're alone", nil, opt("soloParty", "layout"))
  list:Toggle("Hide Blizzard's party and raid frames", "Turning this off takes a /reload.", function() return M.db.hideBlizzard end,
    function(on) M.db.hideBlizzard = on if on then M.Groups:HideBlizzard(true) else M:Print("Blizzard's frames come back after a /reload.") end end)
  list:Toggle("Lock the frames", "Unlocked, each group has a label to drag it by.", function() return M.db.locked end, function(on) M:SetLocked(on) end)
  list:Buttons("Test", "Invented players, to place and style the frames.", {
    { "Party", function() M.Test:Toggle(5) end }, { "Raid of 25", function() M.Test:Toggle(25) end }, { "Stop", function() if M.Test.active then M.Test:Stop() end end } })
  list:Buttons("Positions", nil, { { "Reset", function() M.Groups:ResetPositions() end } })
  return list
end

-------------------------------------------------------------------------------------------
-- Click-casting
-------------------------------------------------------------------------------------------

local function spellFromCursor()
  local kind, a, b, c = GetCursorInfo()
  local id
  if kind == "spell" then id = c or b
  elseif kind == "item" then
    local name = M.Plain(M.Fn("C_Item", "GetItemNameByID"), a)
    return name and ("Item: " .. name) or nil
  elseif kind == "macro" then
    local name = M.Plain(GetMacroInfo, a)
    return name and ("Macro: " .. name) or nil
  end
  if not id then return nil end
  local info = M.Plain(M.Fn("C_Spell", "GetSpellInfo"), id)
  return type(info) == "table" and info.name or nil
end

Settings.panes.binds = function(parent)
  local pane = { set = "friendly", mod = "none", rows = {} }
  local top = CreateFrame("Frame", nil, parent)
  top:SetPoint("TOPLEFT")
  top:SetPoint("TOPRIGHT")
  top:SetHeight(250)
  local lead = UI.Text(top, "body", 13, C.muted)
  lead:SetPoint("TOPLEFT", 0, 0)
  lead:SetPoint("TOPRIGHT", 0, 0)
  lead:SetWordWrap(true)
  lead:SetText("Each mouse button casts on the frame you click. Type a spell (Renew, or Heal(Rank 2)), Item: name, Macro: name, " ..
    "Target, Assist, Focus, Context, Follow or Role, or drag a spell from your spellbook. Changes in combat apply when it ends.")
  local sets = UI.Segmented(top, { { key = "friendly", label = "Friendly" }, { key = "hostile", label = "Hostile" } }, function(key)
    pane.set = key pane:Fill()
  end, 22)
  sets:SetPoint("TOPLEFT", lead, "BOTTOMLEFT", 0, -12)
  local mods = {}
  for _, m in ipairs(M.Binds.MODS) do mods[#mods + 1] = { m.key, m.label } end
  local modDrop = UI.Dropdown(top, mods, function(v) pane.mod = v pane:Fill() end)
  modDrop:SetPoint("LEFT", sets, "RIGHT", 14, 0)
  modDrop:SetWidth(170)
  modDrop:SetValue("none", true)
  for i, b in ipairs(M.Binds.BUTTONS) do
    local label = UI.Text(top, "body", 14, C.text)
    label:SetPoint("TOPLEFT", sets, "BOTTOMLEFT", 0, -16 - (i - 1) * 30)
    label:SetWidth(90)
    label:SetText(b.label)
    local box = CreateFrame("EditBox", nil, top, "InputBoxTemplate")
    box:SetSize(320, 22)
    box:SetPoint("LEFT", label, "RIGHT", 10, 0)
    box:SetAutoFocus(false)
    box:SetFontObject(UI.Font("body", 13))
    local function save(self)
      local text = self:GetText()
      if text ~= (M.Binds:Get(pane.set, pane.mod, b.key) or "") then
        M.Binds:Set(pane.set, pane.mod, b.key, text)
        if M.InCombat() then M:Print("Saved. It works once combat ends.") end
      end
    end
    box:SetScript("OnEnterPressed", function(self) save(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusLost", save)
    box:SetScript("OnEscapePressed", function(self) self:SetText(M.Binds:Get(pane.set, pane.mod, b.key) or "") self:ClearFocus() end)
    box:SetScript("OnReceiveDrag", function(self)
      local text = spellFromCursor()
      if text then self:SetText(text) save(self) ClearCursor() end
    end)
    box:HookScript("OnMouseUp", function(self) if GetCursorInfo() then self:GetScript("OnReceiveDrag")(self) end end)
    pane.rows[i] = box
  end
  function pane:Fill()
    sets:Select(self.set, true)
    for i, b in ipairs(M.Binds.BUTTONS) do self.rows[i]:SetText(M.Binds:Get(self.set, self.mod, b.key) or "") end
  end

  local holder = CreateFrame("Frame", nil, parent)
  holder:SetPoint("TOPLEFT", top, "BOTTOMLEFT", -12, 0)
  holder:SetPoint("BOTTOMRIGHT", 12, 0)
  local list = UI.SettingsList(holder)
  list:Header("Casting")
  list:Dropdown("Cast on", nil, { { "up", "Mouse up" }, { "down", "Mouse down" } }, opt("castOn", "binds"))
  list:Toggle("Resurrect the dead", "A spell click on a dead player casts your resurrection instead.", opt("autoRes", "binds"))
  list:Toggle("Also target them", "Every spell click also makes them your target.", opt("autoTarget", "binds"))
  list:Toggle("Spells tooltip", "Your binds, and casts left on your mana, when you hover a frame.", opt("spellsTooltip"))
  list:Toggle("The game's unit tooltip", "Also makes [@mouseover] in your macros work on our frames.", opt("unitTooltip"))
  function pane:Refresh() self:Fill() list:Refresh() end
  return pane
end

-------------------------------------------------------------------------------------------
-- Indicators
-------------------------------------------------------------------------------------------

Settings.panes.indicators = function(parent)
  local list = UI.SettingsList(parent)
  list:Header("Debuffs you can remove")
  list:Dropdown("Highlight", "How a frame lights up when it has a debuff you can remove. Works in combat.",
    { { "mercy", "Mercy" }, { "blizzard", "Blizzard style" } }, opt("highlight"))
  list:Dropdown("Show", "\"Anything\" also lights debuffs someone else in your group can remove: for raid leaders.",
    { { "mine", "Only mine" }, { "any", "Anything dispellable" } }, opt("dispelScope"))
  list:Toggle("Debuff icons", "In combat Blizzard's own code draws them on our frames, with boss mechanics add-ons can't see.", opt("debuffIcons"))
  list:Slider("Most debuff icons", nil, 1, 5, 1, function() return M.db.maxDebuffs end, function(v) M.db.maxDebuffs = v changed() end, "%.0f", 1)
  list:Header("Health")
  list:Dropdown("Bar colour", nil, { { "class", "Class" }, { "green", "Green" }, { "gradient", "Green to red" } }, opt("color"))
  list:Dropdown("Name colour", nil, { { "class", "Class" }, { "white", "White" } }, opt("nameColor", "layout"))
  list:Dropdown("Text", nil, { { "missing", "Missing health" }, { "percent", "Percent" }, { "none", "None" } }, opt("text"))
  list:Dropdown("Mana bar", nil, { { "healers", "Healers only" }, { "all", "Everyone" }, { "none", "None" } }, opt("power", "layout"))
  list:Toggle("Fade out of range", "Beyond 40 yards. The game hides range in combat but lets a frame fade by it.", opt("range"))
  list:Slider("Faded to", nil, 0.1, 0.9, 0.05, function() return M.db.rangeAlpha end, function(v) M.db.rangeAlpha = v changed() end, "%.0f%%", 100)
  list:Toggle("Low health", "A red pulse below a quarter of their health.", opt("lowHealth"))
  list:Toggle("Aggro", "A red border on anyone a monster is attacking.", opt("aggro"))
  list:Header("What the client allows here")
  list:Buttons("Check", "Says in chat whether Mercy's highlight and Blizzard's aura drawing are working on this client.",
    { { "Status", function() M:PrintStatus() end } })
  return list
end

-------------------------------------------------------------------------------------------
-- HealersMate
-------------------------------------------------------------------------------------------

Settings.panes.healersmate = function(parent)
  local pane = {}
  local text = UI.Text(parent, "body", 14, C.text)
  text:SetPoint("TOPLEFT", 0, 0)
  text:SetPoint("TOPRIGHT", 0, 0)
  text:SetWordWrap(true)
  text:SetJustifyV("TOP")
  local use = UI.Button(parent, "Use them", "primary", function()
    M.Import:FromHealersMate(true)
    pane:Refresh()
  end)
  use:SetSize(110, 24)
  use:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -12)
  local note = UI.Text(parent, "body", 12, C.muted)
  note:SetPoint("TOPLEFT", use, "BOTTOMLEFT", 0, -16)
  note:SetWidth(W - 60)
  note:SetWordWrap(true)
  note:SetText("Or paste a HealersMate export string (from its Share tab, or /hm export):")
  local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  box:SetSize(440, 22)
  box:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 6, -8)
  box:SetAutoFocus(false)
  box:SetFontObject(UI.Font("body", 13))
  local go = UI.Button(parent, "Import", "quiet", function()
    if M.Import:FromString(box:GetText()) then box:SetText("") end
  end)
  go:SetSize(80, 22)
  go:SetPoint("LEFT", box, "RIGHT", 10, 0)
  box:SetScript("OnEnterPressed", function() go:Click() end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  function pane:Refresh()
    local s = M.Import:Summary()
    if s then
      local lines = { "HealersMate is installed. For this character it has:",
        ("  •  %d binds (friendly and hostile)%s"):format(s.binds, s.ranks > 0 and (", " .. s.ranks .. " with ranks") or ""),
        s.party and ("  •  Party layout \"%s\", which becomes %s"):format(s.party, M.Import.LAYOUTS[s.party] or "standard") or nil,
        s.raid and ("  •  Raid layout \"%s\", which becomes %s"):format(s.raid, M.Import.LAYOUTS[s.raid] or "compact") or nil,
        s.extraDebuffs > 0 and ("  •  %d extra tracked debuffs (Mercy can't use names in combat, so these aren't brought over)"):format(s.extraDebuffs) or nil,
        "", "\"Use them\" copies these to Mercy and turns HealersMate off for this character from your next /reload. HealersMate's own files aren't changed. Frame positions aren't brought over." }
      local out = {}
      for i = 1, 9 do if lines[i] then out[#out + 1] = lines[i] end end
      text:SetText(table.concat(out, "\n"))
      use:Show()
    else
      text:SetText(M.char.importedFrom and ("Your binds came from " .. M.char.importedFrom .. ".") or
        "HealersMate isn't loaded, so Mercy can't read its saved settings. Turn it on and /reload to bring them over, or paste an export string below.")
      use:Hide()
    end
  end
  return pane
end

-------------------------------------------------------------------------------------------
-- The window
-------------------------------------------------------------------------------------------

local function show(key)
  for k, pane in pairs(Settings.built or {}) do pane.frame:SetShown(k == key) end
  local p = Settings.built[key]
  if not p then
    local frame = CreateFrame("Frame", nil, win.paneArea)
    frame:SetAllPoints()
    p = Settings.panes[key](frame)
    p.frame = frame
    Settings.built[key] = p
  end
  p.frame:Show()
  if p.Refresh then p:Refresh() end
end

local function build()
  win = UI.Window({ name = "MercySettings", addon = "mercy", title = "Mercy", sub = "Settings", width = W, height = H, footer = true })
  win:SetAccent("mercy")
  win:Hide()
  Settings.built = {}
  win.tabs = UI.Tabs(win.body, TABS, function(key) Settings.tab = key show(key) end)
  win.tabs:SetPoint("TOPLEFT")
  win.tabs:SetPoint("TOPRIGHT")
  win.tabs:ApplyAccent(UI.Accent("mercy"))
  win.paneArea = CreateFrame("Frame", nil, win.body)
  win.paneArea:SetPoint("TOPLEFT", win.tabs, "BOTTOMLEFT", 14, -10)
  win.paneArea:SetPoint("BOTTOMRIGHT", -14, 10)
  win.footerText:SetText("/mercy test shows invented players  ·  /mercy unlock to move the frames")
end

function Settings:Open(tab)
  if not M.db then return end
  if not win then build() end
  if tab and self.panes[tab] then self.tab = tab end
  self.tab = self.tab or "frames"
  win.tabs:Select(self.tab, true)
  win:Show()
  show(self.tab)
end

function Settings:Refresh()
  if not (win and win:IsShown() and self.built) then return end
  local p = self.built[self.tab]
  if p and p.Refresh then p:Refresh() end
end

Core:OnLogin(function()
  if not M.db then return end
  local page = CreateFrame("Frame")
  page:Hide()
  local list = UI.SettingsList(page)
  list:Header("Mercy")
  list:Buttons("Settings", "Mercy's own window: frames, click-casting, indicators and HealersMate.", { { "Open", function() M:OpenSettings() end } })
  list:Toggle("Show the minimap button", "Mercy is also in the game's add-on menu and opens with /mercy.",
    function() return Core.MinimapButton:IsShown("mercy") end, function(on) Core.MinimapButton:SetShown("mercy", on) end)
  page:SetScript("OnShow", function() list:Refresh() end)
  M.settingsCategory = Core:AddSettingsPage(page, "Mercy")

  local function perf(label, tbl, method) Core:RegisterPerf("Mercy: " .. label, tbl, method, "mercy") end
  perf("frame update", M.UF, "Update")
  perf("health", M.UF, "UpdateHealth")
  perf("debuffs", M.Auras, "UpdateUnit")
  perf("range", M.UF, "UpdateRange")
end)
