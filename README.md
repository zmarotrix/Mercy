<p align="center">
  <img src="https://img.shields.io/badge/WoW%20Forever-1.60.1-e7c66c?style=flat-square" alt="WoW Forever 1.60.1">
  <img src="https://img.shields.io/badge/status-not%20yet%20played%20in%20game-ffeea0?style=flat-square" alt="Status: not yet played in game">
  <img src="https://img.shields.io/badge/part%20of-NorgannonDB%20suite-2b2333?style=flat-square" alt="Part of the NorgannonDB suite">
</p>

> [!WARNING]
> **Very much a work in progress.** This first stage has passed its test harness but hasn't been played in the game. Expect things to need fixing.

**Mercy is a healer's party and raid frames.** Click a frame to heal it, with every mouse button and modifier bound to a spell, and see at
a glance who is hurt, who is out of range, and who has a debuff you can remove, in combat too.

WoW Forever runs on the modern client, which hides health, auras and range from add-ons in combat. Mercy is built around that: it hands
the hidden values straight to the bars and text that can show them, and asks the client's own aura filters which debuffs you can dispel.

## What it does

### Frames
Party (with you), Raid (by group or one block), Tanks, Pets, Target and Focus, each on or off and placed where you like. Five layouts:
Standard, Compact, Wide, Tiny and Classic. Health in class colour, green, or green to red; missing health or percent; incoming heals
(yours brighter) and absorbs past the bar's end; mana for healers. Dead, ghost, offline, role, raid mark and aggro show on the frame.
Out of range fades.

### Debuffs you can remove
A frame with a debuff your class removes lights up with the game's own raid frame dispel display (a gradient and border in the
debuff's colour, and its type icon), drawn by the game's code on Mercy's frames, so it works in combat too. Prefer a plain coloured border?
**Mercy's border** is a setting, out of combat only (this client won't let add-ons read auras in combat, so the game's display takes over
then). Raid leaders can show anything someone in the group can remove.

Debuff icons in combat are drawn by the game's own code on Mercy's frames, with bigger icons for boss debuffs and the boss mechanics
add-ons can never see.

### Helping you buff
Out of combat, anyone missing one of your buffs (Fortitude, Divine Spirit, Mark of the Wild, Thorns on tanks, Arcane Intellect,
your blessings), or about to lose it, has its icon on their frame, and the group's name says how many. The rebuff button beside it casts
on the next person who needs it, or the party version when three in one party do. Every click is one cast you make yourself. In combat
the reminders step aside (the game hides buff names then) and come back after. Your own buffs on people show with their time throughout.

The Buffs tab sets who each buff is for (everyone, mana users, tanks, or off), adds any other buff by name or by dragging it from
your spellbook, and can flip the icons to show what people have rather than what they're missing.

### Click-casting
Every mouse button (left, right, middle, 4 and 5) with no modifier, Shift, Ctrl, Alt or any mix, separately for friendly and hostile
frames. A bind can be a spell (`Renew`, or `Heal(Rank 2)`), `Item: name`, `Macro: name`, Target, Assist, Focus, Context (the menu),
Follow or Role. Drag spells from your spellbook. A spell click on a dead player casts your resurrection. Hovering a frame lists your binds
and how many casts your mana allows. Clique can bind Mercy's frames too.

#### What a bind can be

| Type in a box | What a click does |
|---|---|
| `Renew` | casts the spell on them, at its best rank |
| `Heal(Rank 2)` | casts that rank |
| `Buff` | casts the buff they're missing from you (the Buffs tab sets which); nothing if they need none |
| `Target` | makes them your target |
| `Assist` | targets their target |
| `Focus` | makes them your focus |
| `Menu` (or `Context`) | opens their right-click menu |
| `Follow` | follows them |
| `Role` | a menu to mark their role (Mercy uses it to sort and for the Tanks group) |
| `Role: Tank`, `Role: Healer`, `Role: Damage`, `Role: None` | marks that role at once |
| `Item: Major Healing Potion` | uses the item on them |
| `Macro: My macro` | runs one of your macros |

Capitals don't matter. An unbound left click targets and an unbound right click opens the menu. The ? on the Click-casting tab lists these too.

### From HealersMate
If HealersMate is on, `/mercy import` brings its binds and main settings over and turns it off for that character. Its export strings
work too: `/mercy import HM2|...`.

## Commands

| Command | |
|---|---|
| `/mercy` | settings |
| `/mercy test 5`, `/mercy test 25` | invented players, to place and style the frames; again to stop |
| `/mercy unlock`, `/mercy lock` | move the groups by their labels |
| `/mercy reset` | positions back to the defaults |
| `/mercy import [string]` | from HealersMate |
| `/mercy status` | whether the dispel highlight and the game's aura drawing are working on this client |

## What it can't do on this client
- Show debuffs or buffs **by name** in combat: names are secret then. The client's own filters do that job.
- Move, resize or re-sort frames in combat. Changes wait for it to end; someone joining mid-fight still appears.
- Pick who to heal for you. Nothing in Mercy chooses a target.

## Licence
All Rights Reserved: see `LICENSE`. Part of the NorgannonDB suite, built on NorgannonDB Core.
