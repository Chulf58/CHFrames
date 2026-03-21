# CH_DPadParty — TODO

## High Priority / Infrastructure

- [ ] **Auto-hide default WoW party frames when this addon is enabled**
  - Players shouldn't have to manually disable the Blizzard party frames in Interface settings
  - **Constraint**: calling `CompactPartyFrame:Hide()` or `UnregisterAllEvents()` from insecure
    addon code permanently taints the addon's execution context, breaking health/power updates
  - Safe approaches to investigate:
    1. `InterfaceOptionsFrame` / `C_CVar.SetCVar("showPartyFrames", 0)` — may exist in 12.0
    2. `CompactRaidFrameManager_SetSetting("IsShown", false)` via `hooksecurefunc` — check taint risk
    3. Direct CVar: `SetCVar("useCompactPartyFrames", 1)` forces the compact (raid-style) frames
       which can then be hidden without tainting; confirm CVar name in 12.0
    4. Ask the user to disable via Interface → Display → "Show Party Frames" as a fallback

- [x] **Frame scaling for Steam Deck / handhelds**
  - `CHDPadPartyDB.scale` (default 1.0), applied via `root:SetScale()`
  - Settings panel: Scale – / Scale + buttons (step 0.1, clamped 0.5–2.0)
  - Slash command: `/chdpad scale 1.5`

- [x] **Publish to Wago.io & set up automated releases**

- [ ] **Automate Wago releases** — currently requires a manual click on Wago after each GitHub release
  - Generate a Wago API token at https://addons.wago.io/account/apikeys
  - Add as GitHub secret `WAGO_API_TOKEN` at github.com/Chulf58/CH_DPadParty/settings/secrets/actions
  - Update `.github/workflows/release.yml` to use BigWigs packager with `WAGO_API_TOKEN`
  - After this, tagging a commit fully automates both GitHub Release and Wago release

  Full workflow researched. Steps:

  1. **Create Wago developer account** at https://addons.wago.io/ and accept the Developer Agreement
  2. **Create addon project** in the developer dashboard → receive an 8-digit project ID
  3. **Add to `.toc` file:**
     ```
     ## X-Wago-ID: <your-8-digit-project-id>
     ```
  4. **Put the addon in a GitHub repo** (required for the GitHub Actions integration)
  5. **Generate a Wago API token** at https://addons.wago.io/account/apikeys
  6. **Add the token as a GitHub secret** named `WAGO_API_TOKEN` in the repo settings
  7. **Create `.github/workflows/release.yml`** using BigWigs Packager:
     ```yaml
     name: Release
     on:
       push:
         tags: ['*']
     jobs:
       release:
         runs-on: ubuntu-latest
         steps:
           - uses: actions/checkout@v3
           - uses: BigWigsMods/packager@v2
             env:
               WAGO_API_TOKEN: ${{ secrets.WAGO_API_TOKEN }}
     ```
  8. **To release a new version:** bump version in `.toc`, commit, tag (`git tag v1.0.1`), push tag — GitHub Actions packages and uploads automatically

  After setup, users can install via WowUp/CurseBreaker and receive automatic update notifications.

## Already Implemented
- [x] 5 unit frames (party1–4 + player) in d-pad/numpad layout
- [x] Health bar with class color
- [x] HP% text (secret-number safe)
- [x] Name display
- [x] Role icon (Tank / Healer / DPS)
- [x] Dead / Ghost / Offline overlay
- [x] Buff icons (3 slots) with stack count
- [x] Debuff icons (3 slots) with stack count
- [x] Dispel border highlight (Magic/Curse/Poison/Disease — border color changes)
- [x] Incoming heal prediction bar (green, below health bar)
- [x] Damage absorb bar (yellow thin bar below health — placeholder, see redesign below)
- [x] Heal absorb bar (red thin bar below health — placeholder, see redesign below)
- [x] Click-to-target via SecureUnitButtonTemplate + RegisterUnitWatch
- [x] [@mouseover] macro support
- [x] Drag to reposition (root anchor, all frames move together)
- [x] Lock / Unlock toggle
- [x] Test mode (fake party data for layout preview)
- [x] Minimap button (auto-hide, right-drag to orbit)
- [x] Saved position across sessions
- [x] /chdpad slash command

---

## Redesigns / Fixes to Existing Features

- [x] **Redesign absorb bars — overlay on health bar instead of separate thin bars**

  Current implementation is placeholder thin bars stacked below the health bar.
  Desired design (both bars use `SetAllPoints(f.healthBar)` — same size/position as the health bar):

  - **Damage absorb (white)** — semi-transparent white overlay on top of the health bar
    - Right-anchored, fills from **right to left** as shield grows
    - `bar:SetReverseFill(true)`, `bar:SetStatusBarColor(1, 1, 1, 0.4)`
    - Small shield = small white sliver on the right. Large shield = white covers most of the bar.
    - `UnitGetTotalAbsorbs(unit)` → secret number → pass directly to `SetValue`
    - `UnitHealthMax(unit)` → secret number → pass directly to `SetMinMaxValues(0, max)`
    - Event: `UNIT_ABSORB_AMOUNT_CHANGED` (already registered)

  - **Heal absorb / Necrotic (red)** — semi-transparent red overlay on top of the health bar
    - Right-anchored, fills from **right to left** as anti-heal grows
    - `bar:SetReverseFill(true)`, `bar:SetStatusBarColor(0.8, 0.1, 0.1, 0.45)`
    - Visually "eats into" the health bar from the right — the more Necrotic stacks, the more
      red covers the right side, showing how much of that health can't be healed back.
    - `UnitGetTotalHealAbsorbs(unit)` → secret number → pass directly to `SetValue`
    - Event: `UNIT_HEAL_ABSORB_AMOUNT_CHANGED` (already registered)

  - Remove the current `absorbBar` and `healAbsorbBar` StatusBar frames from `BuildUnitFrame`.
  - Shift buff/debuff icons back up (remove the 18px gap that was reserved for the thin bars).
  - The current standalone heal prediction thin bar below the health bar should be removed
    in favour of the inline prediction bar described below (see next entry).

- [x] **Redesign heal prediction — inline extension of the health bar**

  Current implementation is a separate thin green bar below the health bar.
  Desired design: the incoming heal shows as a continuation of the health bar itself,
  in a different colour, so the bar reads as one coherent strip.

  Example: unit at 50% health with a 20% heal incoming →
  `[██████████░░░░░░░░░░]`  (█ = class colour health, ░ = incoming heal colour, blank = missing)

  Implementation approach:
  - Create `healPredictBar` StatusBar with `SetAllPoints(f.healthBar)` (same size as health bar)
  - Place it at a **lower frame level** than `healthBar` so the real health renders on top
  - Set a distinct colour, e.g. bright teal `(0.0, 0.8, 0.6, 0.85)` or soft white-green
  - The health bar (on top) fills to current health in class colour, covering the left portion
  - Only the portion of `healPredictBar` that extends **beyond** the health fill is visible —
    that is exactly the incoming heal, shown in the prediction colour

  **Secret-number challenge**: we need `SetValue(health + incoming)` but both values are secret
  numbers in WoW 12.0 and cannot be added in Lua arithmetic. Options to investigate:
  - `CreateUnitHealPredictionCalculator()` + `UnitGetDetailedHealPrediction(unit, nil, calc)`:
    the calculator object may expose a clamped "health + incoming" total on the C side that
    can be passed directly to `SetValue` without Lua arithmetic
  - Check if `UnitHealthPercent` with the prediction curve bakes prediction in already
  - Fallback: keep the thin separate bar if the overlay approach proves impossible with
    secret numbers in 12.0

  - `SetMinMaxValues(0, UnitHealthMax(unit))` — secret number, safe to pass to C
  - Event: `UNIT_HEAL_PREDICTION` (already registered)

---

## Bugs

- [x] **Debuff icons not showing — fixed**

  Root cause: `UpdateAll()` never called `UpdateAuras()`. On login and zone transitions,
  `PLAYER_ENTERING_WORLD` and `GROUP_ROSTER_UPDATE` both call `UpdateAll()` — but aura icons
  were only ever populated by `UNIT_AURA` events (which fire on changes, not on initial load).
  Pre-existing debuffs at addon load time were never shown.

  Fix: added `CHDPadParty.UpdateAuras(unit)` to the `UpdateAll()` loop.

---

## Investigate / Research

- [ ] **Investigate how DandersFrames detects role for delve companion NPCs**

  Our addon uses `UnitGroupRolesAssigned(unit)` which may return `"NONE"` for delve companions
  (e.g. Brann Bronzebeard) even when the companion is visibly set to a specific role. DandersFrames
  correctly shows only the assigned role (e.g. TANK). Questions to answer:

  - Does DandersFrames use `UnitGroupRolesAssigned` or a different API?
  - Is there a delve-companion-specific API (e.g. `C_DelvesUI`, `UnitHasRole`, or a companion role
    attribute)?
  - Does Blizzard populate a different role field for NPC companions vs. player party members?
  - DandersFrames source: `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\DandersFrames`
    (if installed) — search for role detection logic.

---

## Must-Have (significant gameplay impact)

- [x] **Missing raid buff indicator** — icon/glow when a party member is missing a buff the player can provide
  - Detect which raid buff the player's class/spec provides (e.g. Stamina for Priest, Intellect for Mage/Paladin/Druid, Battle Shout for Warrior, etc.)
  - Scan each party member's buffs for the presence of that buff; show an indicator if absent
  - Relevant buffs to map per class: Power Word: Fortitude (Priest, spellID 21562), Arcane Intellect (Mage, 1459), Mark of the Wild (Druid, 1126), Blessing of Kings (Paladin, 20217), Battle Shout (Warrior, 6673), Mystic Touch (Monk, 116781), etc.
  - Detection: scan `f.buffIcons` already populated data, or call `C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")` directly scanning for the buff spellID (`aura.spellId`)
  - Visual: small glow or colored dot on the frame (e.g. bottom-right corner icon) when missing
  - Event: `UNIT_AURA` already registered — hook into `UpdateAuras` or add a separate `UpdateMissingBuff(unit)` call
  - Player class detected once via `UnitClassBase("player")` or `select(2, UnitClass("player"))`
  - Only show the indicator when the player is in a group (not solo) and the buff is castable at range

- [x] **Range indicator — grey out at >40 yards**
  - Uses `C_Spell.IsSpellInRange` with a spec/class-specific friendly spell (DandersFrames/Grid2 pattern)
  - Spell validated with `IsPlayerSpell()` before use; result compared with `== true` / `== false` (plain booleans)
  - `CheckInteractDistance(unit, 4)` (~28yd) as OOC fallback when spell returns false
  - In combat with no result: assume in-range (no reliable fallback mid-combat)
  - Classes with no friendly spell (DK/DH/Hunter/Warrior/Rogue): interact distance OOC, assume in-range in combat
  - `PLAYER_TALENT_UPDATE` re-detects the range spell on spec change
  - Polls every 0.1s (matches action bar responsiveness)

- [x] **Resource / mana bar** — small bar showing mana, rage, energy, focus
  - `UnitPower(unit)` + `UnitPowerMax(unit)` (secret numbers — pass to SetValue/SetMinMaxValues directly)
  - `UnitPowerType(unit)` → color (blue=mana, red=rage, yellow=energy, orange=focus, etc.)
  - Event: `UNIT_POWER_UPDATE` (already registered), `UNIT_DISPLAYPOWER` for type changes
  - Thin bar (6px) below the heal-absorb bar

- [x] **Target highlight** — thick gold border when this frame's unit is your current target
  - `UnitIsUnit(unit, "target")` on `PLAYER_TARGET_CHANGED` event
  - Swaps `edgeSize` 12→24 via `SetBackdrop` for a visibly thicker ring; re-applies bg color after swap

- [x] **Aggro / threat highlight** — red border when unit has aggro
  - `UnitThreatSituation(unit)` >= 2; event `UNIT_THREAT_SITUATION_UPDATE`
  - Priority chain: aggro red > dispel color > default grey

- [x] **Buff/debuff duration timers** — cooldown swipe + tiny countdown text on each aura icon
  - `CooldownFrame_Set` drives the clock sweep; 1s ticker updates timer text
  - Format: >=3600s → "Xh", >=60s → "Xm", <60s → seconds; `SetHideCountdownNumbers(true)` suppresses OmniCC

---

## Nice-to-Have (quality of life)

- [x] **Incoming resurrection icon** — green icon (bottom-left) when a res is incoming
  - `UnitHasIncomingResurrection` + `INCOMING_RESURRECT_CHANGED`

- [x] **Summon pending icon** — purple icon (same frame as rez, bottom-left) when summoned
  - `C_IncomingSummon.HasIncomingSummon` + `INCOMING_SUMMON_CHANGED`

- [x] **Raid target marker** — skull/X/star shown in top-right corner of unit frame
  - `GetRaidTargetIndex` → SetTexCoord on `UI-RaidTargetingIcons`; `RAID_TARGET_UPDATE`

- [x] **AFK status** — "AFK" shown in the dead/ghost/offline overlay
  - `UnitIsAFK`; `PLAYER_FLAGS_CHANGED` already registered

- [x] **Leader icon** — crown above class icon (already implemented via leaderCrown frame)

- [ ] **Vehicle icon** — icon when unit is in a vehicle
  - `UnitHasVehicleUI(unit)` → bool, event `UNIT_ENTERED_VEHICLE` / `UNIT_EXITED_VEHICLE`

- [ ] **Health fade** *(disabled — caused permanent grey-out)*
  - Whole-frame alpha reduction at full HP was too visible and confusing
  - Better approach: dim only the health bar backdrop or border, not the whole frame

- [ ] **HP text: show absorb% alongside health%** — e.g. "74% + 13%" with absorb in yellow
  - Absorb% = `UnitGetTotalAbsorbs(unit)` / `UnitHealthMax(unit)` — both secret numbers,
    so compute the ratio on the C side or use a percentage bar trick
  - Simplest approach: show the absorb bar's fill percentage using a cached value updated
    in `UpdateAbsorbs` → store `f._absorbPct` as a plain number, format in `UpdateFrame`
  - HP text FontString should be at a high frame level (above absorb bar overlay)
  - Format: `"74%"` normally, `"74% +13%"` (yellow +13%) when absorbs present

- [x] **Resource bar layout** — health bar → power bar → buffs/debuffs
  - Power bar at y=-46 (directly below health bar); buffs/debuffs at y=-54
  - Frame stays 74px — pixel math worked out exactly

- [ ] **Dispel priority + class-aware filtering**
  - Dispellable debuffs should always show first in the debuff slots (sort by dispellability)
  - Only highlight dispellable debuffs that the player's class can actually remove:
    - Priests: Magic, Disease
    - Druids: Magic, Curse, Poison
    - Paladins: Magic, Poison, Disease
    - Shamans: Magic, Curse, Poison  (Purge on enemies)
    - Monks: Magic, Poison, Disease (Detox)
    - Mages: Curse (Remove Curse)
    - Warlocks: Magic on self only (Singe Magic via Imp)
  - Border color should only activate for dispel types the player can remove
  - The debuff's dispel highlight should be more prominent (maybe a glow or thicker colored border on the icon itself, not just the frame border)

---

## Stretch / Future

- [ ] Player frame: show own castbar (channel + cast progress)
- [ ] Configurable frame size and layout from settings panel
- [ ] Show number of active crowd-control debuffs (CC tracker)
- [ ] Clickcasting support (right-click = custom spell on unit)
- [ ] Separate settings for party vs. raid (5-man vs 10/25-man layouts)
