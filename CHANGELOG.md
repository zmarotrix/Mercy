# Changelog

## 0.2.0, 2026-11-07

Helping you buff, and seeing who needs you:
- **Who needs your buffs:** out of combat, anyone missing one of your class's buffs, or with less than 5 minutes of it left, has its icon
  in their frame's top right (faded when it's only running out). Priest: Fortitude, Divine Spirit (mana users), Shadow Protection (off by
  default). Druid: Mark of the Wild, Thorns (tanks). Mage: Arcane Intellect (mana users). Paladin: any blessing of yours. Names come from
  the client, so every rank and language matches.
- **Rebuff button** by the group's name: each click casts on the next person who needs it, in range, or the party version (Prayer of
  Fortitude, Gift of the Wild) when three in one party do; a paladin's is Wisdom on mana users, Might on the rest. It hides in combat.
- **The group's summary**, by its name: "Dispel 2" (in combat too) and how many need each buff.
- The raid mark moved next to the role icon, to make room for the buff marker.
- Settings: Who needs your buffs, Rebuff button, Rebuff when less than N minutes, and each of your class's buffs on or off.

## 0.1.12, 2026-11-07

- Health and mana bars have the mockup's gradient: lighter on the top half, darker on the bottom half, the bar's own colour in the
  middle. It follows the fill as health changes and keeps the rounded corners.

## 0.1.11, 2026-11-07

- **Your buffs on people:** your HoTs and buffs on each person show bottom right, with their time, in combat too. Blizzard's own raid
  frame code draws them (its rule: buffs you cast that you can put on others, not self-only ones); Mercy draws its own if the game
  refuses. Debuff icons moved to bottom left. Settings: Your buffs, Most buff icons.
- **Fixed:** after dying and coming back, your frame kept saying Ghost with an empty bar. A health change now checks whether someone is
  dead first, and your own death, release and return redraw your frame.

## 0.1.10, 2026-11-07

Easier to read:
- Frames are about 10% larger in every layout (Standard is 132 x 52), with text a size up.
- Health under the name is in the bold font and full white.
- Names, health and status have a soft dark halo (four faint copies a pixel out) on top of the shadow, so they read on any bar
  colour without an outline's hard edge. The halo follows every write, secret values included.

## 0.1.9, 2026-11-07

- A group's panel fits the people in it: alone it wraps just your frame, and it grows and shrinks as people join and leave, in combat
  too (the panel isn't protected, so it can follow the game showing and hiding frames). Someone leaving mid-fight leaves a gap until
  combat ends, when the frames close up.

## 0.1.8, 2026-11-07

- The click-casting boxes show the spell's icon (or the item's or macro's) as soon as the text matches something you have, as
  HealersMate does. A name that matches nothing in your spellbook turns soft red, so a typo shows before you need it.

## 0.1.7, 2026-11-07

- **Rounded bars:** each layout ships masks the shape of its bars (`media/`, made by `tools/mercy_masks.py`), so health, incoming heals,
  absorbs and the power strip have round corners at their real size. The frame sits on a rounded card.
- **Current health** under the name, the new default (Text: Current, Missing, Percent or None). Saves that had the old default move to it once.
- The group's name sits top left on its panel.
- **Range:** frames next to you showed faded. Mercy now asks whether one of your bound heals can reach them first, and when the client
  can't check range at all, treats them as in range instead of fading them.

## 0.1.6, 2026-11-07

- The spells tooltip follows the keys you hold, as HealersMate's does: it shows the binds for Shift, Ctrl, Alt or none, every button
  with "Unbound" where there's nothing, and redraws the moment you press or let go of a modifier.
- Mouse buttons 4 and 5 are called Back and Forward.

## 0.1.5, 2026-11-07

Softer and rounded, closer to HealersMate (0.1.4's flat look went the wrong way, and its outlined text read as a border):
- The game's own modern raid frame art: soft gradient health and power fills, a rounded dark background, and rounded target and aggro
  frames (`RaidFrame-Hp-Fill`, `raidframe-hp-bg-white`, `_RaidFrame-Resource-*`, `RaidFrame-TargetFrame`, `RaidFrame-AgroFrame`).
  Plain textures stand in if a client lacks one.
- Bars sit 2 px inside the background, so it shows round them.
- The name is centred with missing health (or Dead, Offline) under it, with a soft shadow and no outline.
- A rounded panel behind each group, with its name centred at the top (setting: Panels behind the groups).

## 0.1.4, 2026-11-07

A modern look (it read like classic HealBot):
- Flat bars with a faint sheen from the top, instead of the glossy old bar texture.
- A crisp 1 px black edge around a dark slate well; the slate is what shows where health is missing.
- A thin 3 px power strip with a 1 px gap (6 px in the Classic layout), in softer power colours.
- The name sits in the middle on the left, missing health on the right, both outlined; the role icon is small, in the top corner.
- 3 px between frames.

## 0.1.3, 2026-11-07

- **Name colour** setting (Indicators): class or white. Class-coloured names, with a dark outline so they read on any bar, are the default.
- **Green bars are the default**, and a brighter, purer green (the old one leaned blue). Saves from 0.1.0 to 0.1.2 move to green bars once,
  since class bars were only ever the default there; choosing class bars again sticks.

## 0.1.2, 2026-11-07

- A new look: a pale holy yellow (`#ffeea0`) and a new mark, a halo over a falling drop of light. The red cross went: it's a protected
  emblem. Needs NorgannonDB Core 1.17.2, which carries the mark and the colour.

## 0.1.1, 2026-11-07

First look in game (a screenshot):
- Names showed twice, the second copy shifted right: the suite's text glow centres its copies, and these names are left-aligned. Unit frames
  use the font's shadow instead.
- Role icons were a wrong cut of an old texture. They're the client's own small role icons now (`roleicon-tiny-*` atlases).

## 0.1.0, 2026-11-07

First build: Stage 1 of `docs/mercy-v1.md`. Not yet run in game.

- **Frames:** Party, Raid, Tanks, Pets, Target and Focus on fixed unit buttons, shown by the game's own state drivers so they work in combat.
  Five layouts. Health, missing health or percent, incoming heals and absorbs, mana for healers, dead, offline, role, raid mark, aggro,
  low health and range fade, all drawn from secret values without reading them.
- **Dispel highlight:** a pulsing border in the debuff's colour for debuffs you can remove (`HARMFUL|RAID`), in combat too. "Blizzard style"
  uses the game's own overlay instead, through the same private aura container the game's raid frames use. If the count turns out secret in
  game, Mercy switches to Blizzard's overlay by itself.
- **Debuff icons:** drawn by Blizzard's container in combat; Mercy's own icons stand in if the client refuses it.
- **Click-casting:** five mouse buttons, eight modifier combinations, friendly and hostile; spells with ranks, items, macros, target,
  assist, focus, menu, follow and roles. Resurrect on click, target on cast, spells tooltip with casts left, Clique support.
- **HealersMate:** its saved binds and settings, or an export string, come over with `/mercy import`.
- **Test mode:** `/mercy test 5 | 25 | 40`.
- Needs NorgannonDB Core 1.17.1 (Mercy's registry entry and mark).
