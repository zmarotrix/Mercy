-- Curves: the client does the maths on secret values for us. We hand it a curve and a unit, and get back a value
-- (also secret) that a widget can show: a colour for the bar, an alpha for the missing-health text, a percent.

local Core = NorgannonCore
local M = Mercy
if M.disabled then return end

local Curves = {}
M.Curves = Curves

-- The game's debuff colours (DebuffTypeColor), and the number the client gives each dispel type. The numbers are
-- HealersMate's guess; /hprobe reads the real ones out of combat, and docs/mercy-checklist.md asks to compare.
Curves.TYPE_COLORS = {
  Magic = { 0.2, 0.6, 1 }, Curse = { 0.6, 0, 1 }, Disease = { 0.6, 0.4, 0 }, Poison = { 0, 0.6, 0 },
  none = { 0.8, 0, 0 },
}
Curves.DISPEL_IDS = { none = 0, Magic = 1, Curse = 2, Disease = 3, Poison = 4 }

local function curveType(kind)
  return Enum and Enum.LuaCurveType and Enum.LuaCurveType[kind] or nil
end

local function numberCurve(points, kind)
  local create = M.Fn("C_CurveUtil", "CreateCurve")
  if not create then return nil end
  local ok, c = pcall(function()
    local curve = create()
    local t = curveType(kind or "Linear")
    if t ~= nil and curve.SetType then curve:SetType(t) end
    for _, p in ipairs(points) do curve:AddPoint(p[1], p[2]) end
    return curve
  end)
  return ok and c or nil
end

local function colorCurve(points, kind)
  local create = M.Fn("C_CurveUtil", "CreateColorCurve")
  if not (create and CreateColor) then return nil end
  local ok, c = pcall(function()
    local curve = create()
    local t = curveType(kind or "Linear")
    if t ~= nil and curve.SetType then curve:SetType(t) end
    for _, p in ipairs(points) do curve:AddPoint(p[1], CreateColor(p[2], p[3], p[4], p[5] or 1)) end
    return curve
  end)
  return ok and c or nil
end

function Curves:Build()
  self.percent = numberCurve({ { 0, 0 }, { 1, 100 } })
  self.missingAlpha = numberCurve({ { 0, 1 }, { 1, 0 } }, "Step")     -- 1 while anything is missing
  self.lowHealth = numberCurve({ { 0, 1 }, { 0.25, 0 } }, "Step")    -- 1 below a quarter
  self.gradient = colorCurve({ { 0, 0.85, 0.15, 0.1 }, { 0.35, 0.9, 0.35, 0.1 }, { 0.6, 0.85, 0.75, 0.15 }, { 1, 0.25, 0.75, 0.3 } })
  self:BuildDispel()
end

---The dispel colour curves: one where "no type" is invisible (the highlight), one where it's red (debuff borders).
function Curves:BuildDispel()
  local pts, border = {}, {}
  local ids = {}
  for name, id in pairs(self.DISPEL_IDS) do ids[#ids + 1] = { id, name } end
  table.sort(ids, function(a, b) return a[1] < b[1] end)
  for _, entry in ipairs(ids) do
    local c = self.TYPE_COLORS[entry[2]] or self.TYPE_COLORS.none
    pts[#pts + 1] = { entry[1], c[1], c[2], c[3], entry[2] == "none" and 0 or 1 }
    border[#border + 1] = { entry[1], c[1], c[2], c[3], 1 }
  end
  -- anything after the known types (bleed, enrage) reads as plain red
  local last = ids[#ids][1]
  pts[#pts + 1] = { last + 1, 0.8, 0, 0, 1 }
  border[#border + 1] = { last + 1, 0.8, 0, 0, 1 }
  self.dispel = colorCurve(pts, "Step")
  self.border = colorCurve(border, "Step")
end

---A colour for a plain dispel type name, as r, g, b.
function Curves.TypeColor(name)
  local c = Curves.TYPE_COLORS[name] or Curves.TYPE_COLORS.none
  return c[1], c[2], c[3]
end
