# Changelog

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
