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
  { key = "indicators", label = "Indicators" }, { key = "buffs", label = "Buffs" }, { key = "healersmate", label = "HealersMate" } }

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
  list:Toggle("Only when needed", "A group's panel shows only when someone's in it, and Target and Focus only for friendly units.",
    function() return M.db.hideEmpty and M.db.friendlyOnly end,
    function(on) M.db.hideEmpty, M.db.friendlyOnly = on, on changed("layout") end)
  list:Header("Panel opacity")
  list:Toggle("Same opacity for every group", "Moving any slider below moves them all. Turning this on gives every group the Party's.",
    function() return M.db.syncAlpha end,
    function(on) M.db.syncAlpha = on if on then M:SetPanelAlpha("party", M:Group("party").alpha or 0.88) end list:Refresh() end)
  for _, key in ipairs(M.GROUPS) do
    list:Slider(labels[key][1], nil, 0, 1, 0.05, function() return M:Group(key).alpha or 0.88 end,
      function(v) M:SetPanelAlpha(key, v) if M.db.syncAlpha then list:Refresh() end end, "%.0f%%", 100)
  end
  list:Toggle("Party frames when you're alone", nil, opt("soloParty", "layout"))
  list:Toggle("Hide Blizzard's party and raid frames", "Turning this off takes a /reload.", function() return M.db.hideBlizzard end,
    function(on) M.db.hideBlizzard = on if on then M.Groups:HideBlizzard(true) else M:Print("Blizzard's frames come back after a /reload.") end end)
  list:Toggle("Lock the frames", "Unlocked, drag a group by its name (out of combat). /mercy unlock also shows empty groups, to move them.",
    function() return M.db.locked end, function(on) M:SetLocked(on) end)
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

-- every kind of bind, for the ? on the Click-casting tab (the README has the same table)
Settings.BIND_HELP = {
  { "Renew", "casts the spell on them (its best rank)" },
  { "Heal(Rank 2)", "a particular rank" },
  { "Buff", "the buff they're missing from you (Buffs tab)" },
  { "Target", "makes them your target" },
  { "Assist", "targets their target" },
  { "Focus", "makes them your focus" },
  { "Menu", "their right-click menu (or Context)" },
  { "Follow", "follows them" },
  { "Role", "a menu to mark their role" },
  { "Role: Tank", "marks them Tank (also Healer, Damage, None)" },
  { "Item: name", "uses that item on them" },
  { "Macro: name", "runs one of your macros" },
}

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
    "Target, Buff, Menu and more (the ? lists them), or drag a spell from your spellbook. Changes in combat apply when it ends.")
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
  -- what you can type in a box, beyond a spell's name
  local help = CreateFrame("Button", nil, top)
  help:SetSize(22, 22)
  help:SetPoint("LEFT", modDrop, "RIGHT", 10, 0)
  help.ring = UI.Icon(help, "circle", 22, C.lineStrong)
  help.ring:SetAllPoints()
  help.text = UI.Text(help, "title", 14, C.goldSoft)
  help.text:SetPoint("CENTER", 0, 1)
  help.text:SetText("?")
  help:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("What a bind can be", 1, 1, 1)
    for _, row in ipairs(Settings.BIND_HELP) do GameTooltip:AddDoubleLine(row[1], row[2], 1, 0.82, 0, 0.9, 0.9, 0.9) end
    GameTooltip:AddLine("Capitals don't matter. Hover a frame to see what each button does on it.", 0.66, 0.63, 0.54, true)
    GameTooltip:Show()
  end)
  help:SetScript("OnLeave", function() GameTooltip:Hide() end)
  for i, b in ipairs(M.Binds.BUTTONS) do
    local label = UI.Text(top, "body", 14, C.text)
    label:SetPoint("TOPLEFT", sets, "BOTTOMLEFT", 0, -16 - (i - 1) * 30)
    label:SetWidth(90)
    label:SetText(b.label)
    local box = CreateFrame("EditBox", nil, top, "InputBoxTemplate")
    box:SetSize(290, 22)
    box:SetPoint("LEFT", label, "RIGHT", 10, 0)
    box:SetAutoFocus(false)
    box:SetFontObject(UI.Font("body", 13))
    -- the spell's icon inside the box, as HealersMate shows it, and a soft red for a name that matches nothing you have
    box:SetTextInsets(22, 4, 0, 0)
    box.icon = box:CreateTexture(nil, "OVERLAY")
    box.icon:SetSize(18, 18)
    box.icon:SetPoint("LEFT", box, "LEFT", 0, 0)
    box.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    box:SetScript("OnTextChanged", function(self)
      local icon, ok, own = M.Binds.Icon(self:GetText())
      if icon then
        self.icon:SetTexture(icon)
        if own then
          self.icon:SetTexCoord(0, 1, 0, 1)
          self.icon:SetVertexColor(C.goldSoft[1], C.goldSoft[2], C.goldSoft[3])
        else
          self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
          self.icon:SetVertexColor(1, 1, 1)
        end
        self.icon:Show()
      else
        self.icon:Hide()
      end
      if ok then self:SetTextColor(1, 1, 1) else self:SetTextColor(1, 0.55, 0.5) end
    end)
    local function save(self)
      local text = self:GetText()
      if text ~= (M.Binds:Get(pane.set, pane.mod, b.key) or "") then
        M.Binds:Set(pane.set, pane.mod, b.key, text)
        if pane.FillShelf then pane:FillShelf() end
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
  -- beside the boxes: your spells that aren't bound yet. Drag one onto a box, or click it to fill the first empty box.
  local SHELF_COLS, SHELF_SIZE, SHELF_GAP, SHELF_MAX = 6, 28, 4, 18
  local shelf = CreateFrame("Frame", nil, top)
  shelf:SetPoint("TOPLEFT", pane.rows[1], "TOPRIGHT", 18, 0)
  shelf:SetSize(SHELF_COLS * (SHELF_SIZE + SHELF_GAP), 140)
  shelf.title = UI.Text(shelf, "title", 13, C.goldSoft)
  shelf.title:SetPoint("BOTTOMLEFT", shelf, "TOPLEFT", 0, 4)
  shelf.title:SetText("Not bound yet")
  shelf.empty = UI.Text(shelf, "body", 12, C.muted)
  shelf.empty:SetPoint("TOPLEFT", 0, -2)
  shelf.empty:SetWidth(SHELF_COLS * (SHELF_SIZE + SHELF_GAP) - SHELF_GAP)
  shelf.empty:SetWordWrap(true)
  shelf.more = UI.Text(shelf, "body", 11, C.faint)
  shelf.buttons = {}
  local function firstEmpty()
    for _, b in ipairs(M.Binds.BUTTONS) do
      if not M.Binds:Get(pane.set, pane.mod, b.key) then return b.key end
    end
  end
  local function shelfButton(i)
    local s = CreateFrame("Button", nil, shelf)
    s:SetSize(SHELF_SIZE, SHELF_SIZE)
    s:SetPoint("TOPLEFT", ((i - 1) % SHELF_COLS) * (SHELF_SIZE + SHELF_GAP), -math.floor((i - 1) / SHELF_COLS) * (SHELF_SIZE + SHELF_GAP))
    s.edge = s:CreateTexture(nil, "BACKGROUND")
    s.edge:SetAllPoints()
    s.edge:SetColorTexture(0, 0, 0, 1)
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetPoint("TOPLEFT", 1, -1)
    s.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    s.glow = s:CreateTexture(nil, "HIGHLIGHT")
    s.glow:SetAllPoints(s.icon)
    s.glow:SetColorTexture(1, 1, 1, 0.18)
    s:RegisterForDrag("LeftButton")
    s:SetScript("OnDragStart", function(self)
      local pick = M.Fn("C_Spell", "PickupSpell") or M.Fn(nil, "PickupSpell")
      if pick and self.spell then pcall(pick, self.spell.id) end
    end)
    s:SetScript("OnClick", function(self)
      local key = firstEmpty()
      if not (key and self.spell) then M:Print("Every button is bound for this modifier: drag the spell onto the one to replace.") return end
      M.Binds:Set(pane.set, pane.mod, key, self.spell.name)
      pane:Fill()
    end)
    s:SetScript("OnEnter", function(self)
      if not self.spell then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if not M.Set(GameTooltip, "SetSpellByID", self.spell.id) then GameTooltip:AddLine(self.spell.name, 1, 1, 1) end
      GameTooltip:AddLine("Drag onto a box, or click to put it in the first empty one.", M.ACCENT[1], M.ACCENT[2], M.ACCENT[3], true)
      GameTooltip:Show()
    end)
    s:SetScript("OnLeave", function() GameTooltip:Hide() end)
    shelf.buttons[i] = s
    return s
  end
  function pane:FillShelf()
    local list = M.Binds:Unbound(self.set)
    for i = 1, math.max(#shelf.buttons, math.min(#list, SHELF_MAX)) do
      local spell = list[i]
      local s = shelf.buttons[i] or (spell and i <= SHELF_MAX and shelfButton(i))
      if s then
        s.spell = i <= SHELF_MAX and spell or nil
        if s.spell then s.icon:SetTexture(spell.icon) s:Show() else s:Hide() end
      end
    end
    shelf.empty:SetText(#list == 0 and (self.set == "hostile" and "Every harmful spell you know is bound." or "Every healing and helpful spell you know is bound.") or "")
    local extra = #list - SHELF_MAX
    shelf.more:ClearAllPoints()
    shelf.more:SetPoint("TOPLEFT", 0, -math.ceil(SHELF_MAX / SHELF_COLS) * (SHELF_SIZE + SHELF_GAP))
    shelf.more:SetText(extra > 0 and ("and " .. extra .. " more") or "")
  end

  function pane:Fill()
    sets:Select(self.set, true)
    for i, b in ipairs(M.Binds.BUTTONS) do self.rows[i]:SetText(M.Binds:Get(self.set, self.mod, b.key) or "") end
    self:FillShelf()
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
  pane.list = list
  return pane
end

-------------------------------------------------------------------------------------------
-- Indicators
-------------------------------------------------------------------------------------------

Settings.panes.indicators = function(parent)
  local list = UI.SettingsList(parent)
  list:Header("Debuffs you can remove")
  list:Dropdown("Highlight", "How a frame lights up when it has a debuff you can remove. Blizzard style is the game's own raid frame display, "
    .. "drawn by the game on Mercy's frames, and works in combat. Mercy's border is out of combat only (add-ons can't read auras in combat), "
    .. "so in combat Blizzard's takes over either way.",
    { { "blizzard", "Blizzard style" }, { "mercy", "Mercy's border" } }, opt("highlight"))
  list:Dropdown("Show", "\"Anything\" also lights debuffs someone else in your group can remove: for raid leaders.",
    { { "mine", "Only mine" }, { "any", "Anything dispellable" } }, opt("dispelScope"))
  list:Toggle("Debuff icons", "In combat Blizzard's own code draws them on our frames, with boss mechanics add-ons can't see.", opt("debuffIcons"))
  list:Slider("Most debuff icons", nil, 1, 5, 1, function() return M.db.maxDebuffs end, function(v) M.db.maxDebuffs = v changed() end, "%.0f", 1)
  list:Toggle("Your buffs", "Your HoTs and buffs on each person, with their time, bottom right. In combat Blizzard's own code draws them.", opt("myBuffs"))
  list:Slider("Most buff icons", nil, 1, 5, 1, function() return M.db.maxBuffs end, function(v) M.db.maxBuffs = v changed() end, "%.0f", 1)
  list:Header("Health")
  list:Dropdown("Bar colour", nil, { { "class", "Class" }, { "green", "Green" }, { "gradient", "Green to red" } }, opt("color"))
  list:Dropdown("Name colour", nil, { { "class", "Class" }, { "white", "White" } }, opt("nameColor", "layout"))
  list:Dropdown("Text", nil, { { "current", "Current health" }, { "missing", "Missing health" }, { "percent", "Percent" }, { "none", "None" } }, opt("text"))
  list:Toggle("Short numbers", "1.3K instead of 1339. Handy in big raids with big health pools.", opt("shortNumbers"))
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
-- Buffs: who needs yours, and which ones Mercy tracks
-------------------------------------------------------------------------------------------

Settings.panes.buffs = function(parent)
  local list = UI.SettingsList(parent)
  list:Header("Who needs your buffs")
  list:Toggle("Buff reminders", "Out of combat (the game hides buff names in combat), small icons on each frame's top right.",
    opt("buffReminders"))
  list:Dropdown("Show icons for", "What's missing: the buffs someone needs from you. What they have: the ones they've got.",
    { { "missing", "What's missing" }, { "buffed", "What they have" } }, opt("buffShow"))
  list:Toggle("Rebuff button", "Under the group: each click casts the buff on the next person who needs it, or the party version when three need it.",
    opt("rebuffButton"))
  list:Slider("Rebuff when less than", nil, 1, 15, 1, function() return M.db.rebuffMinutes end,
    function(v) M.db.rebuffMinutes = v changed() end, "%.0f min", 1)
  list:Toggle("Downrank buffs for low levels", "A buff rank can't go on anyone more than 10 levels below it (\"Target is too low level\"). "
    .. "The rebuff button, Buff binds and buffs you've bound by name use the best rank that lands. A rank you typed is kept.",
    opt("downrank", "binds"))

  list:Header("Tracked buffs")
  for _, e in ipairs(M.Buffs:All()) do
    local choices = {}
    for _, w in ipairs(M.Buffs.WHO) do choices[#choices + 1] = w end
    if e.custom then choices[#choices + 1] = { "remove", "Remove" } end
    local desc = e.custom and (e.known and "Added by you." or "Added by you. You can't cast it, so it's tracked but not on the rebuff button.") or nil
    list:Dropdown(e.name, desc, choices, function() return e.who end, function(who)
      M.Buffs:SetWho(e, who)
      e.who = who
      if who == "remove" then Settings:Rebuild("buffs") end
    end)
  end

  -- adding one: type its name or drag it from your spellbook
  local row = list:Buttons("Add a buff", "Type its name or drag it here from your spellbook, then Add. Any buff works: Fear Ward, Power Infusion, Amplify Magic.",
    { { "Add", function() end } })
  local holder = row.control
  local box = CreateFrame("EditBox", nil, holder, "InputBoxTemplate")
  box:SetSize(100, 20)
  box:SetPoint("RIGHT", holder.button1, "LEFT", -8, 0)
  box:SetAutoFocus(false)
  box:SetFontObject(UI.Font("body", 12))
  local function add()
    local name = box:GetText()
    if M.Buffs:Add(name) then
      box:SetText("")
      Settings:Rebuild("buffs")
    elseif strtrim(name or "") ~= "" then
      M:Print(name .. " is already tracked.")
    end
  end
  holder.button1:SetScript("OnClick", add)
  box:SetScript("OnEnterPressed", function(self) add() self:ClearFocus() end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  box:SetScript("OnReceiveDrag", function(self)
    local text = spellFromCursor()
    if text then self:SetText(text) ClearCursor() add() end
  end)
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

---Descriptions wrap onto as many lines as they need. The Core's settings rows ask for wrapping, but in game they came out as one
---truncated line: so allow several lines explicitly, and lay the list out again once the pane has its real width.
local function wrapDescriptions(list)
  if not (list and list.rows) then return end
  for _, r in ipairs(list.rows) do
    if r.desc then
      r.desc:SetWordWrap(true)
      if r.desc.SetMaxLines then r.desc:SetMaxLines(6) end
    end
  end
  if list.Layout then list:Layout() end
end

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
  local list = p.rows and p or p.list
  wrapDescriptions(list)
  if C_Timer and C_Timer.After then C_Timer.After(0.05, function() wrapDescriptions(list) end) end
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

---A pane whose rows depend on data (the buff list): drop it and build it again.
function Settings:Rebuild(key)
  local p = self.built and self.built[key]
  if p then
    p.frame:Hide()
    self.built[key] = nil
  end
  if win and win:IsShown() and self.tab == key then show(key) end
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
  page:SetScript("OnShow", function() list:Refresh() end)
  M:AddSettingsPage(page)

  local function perf(label, tbl, method) Core:RegisterPerf("Mercy: " .. label, tbl, method, "mercy") end
  perf("frame update", M.UF, "Update")
  perf("health", M.UF, "UpdateHealth")
  perf("debuffs", M.Auras, "UpdateUnit")
  perf("range", M.UF, "UpdateRange")
end)
