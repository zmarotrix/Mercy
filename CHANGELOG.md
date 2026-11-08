# Changelog

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
