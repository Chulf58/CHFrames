# CH_DPadParty — TODO

## High Priority / Infrastructure

- [x] **Publish to Wago.io & set up automated releases**

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
  - Grey out the entire unit frame when the party member is more than 40 yards away
  - 40 yards = standard maximum healing range (Flash Heal, Chain Heal, Healing Touch, etc.)
  - Fixed range, not class-specific — keeps it simple and consistent for all users
  - Visual: desaturate + dim the frame (`f:SetAlpha(0.4)` when OOR, `f:SetAlpha(1.0)` in range)
  - Implementation: use a known 40-yard spell to probe range via `C_Spell.IsSpellInRange(spellID, unit)`
    - Spell ID 139 = Renew (Priest, 40 yards) — available to all as a reference probe
    - Spell ID 774 = Rejuvenation (Druid, 40 yards) — alternative
    - Pick whichever the player has learned; fall back to `CheckInteractDistance(unit, 4)` (28yd)
      or `UnitInRange(unit)` (40yd) as a last resort
    - `UnitInRange(unit)` returns a secret boolean in WoW 12.0 — must guard with `issecretvalue(result)`
      before using it; if tainted, fall back to CheckInteractDistance or assume in-range
  - Poll every 0.5s via a repeating `C_Timer.NewTicker(0.5, callback)` — no WoW event fires
    reliably for range changes
  - Player frame: always considered in range (skip check entirely)
  - Combine with health fade alpha when both are implemented: `finalAlpha = baseAlpha * oorAlpha`
    so they stack rather than overwrite each other

- [ ] **Resource / mana bar** — small bar showing mana, rage, energy, focus
  - `UnitPower(unit)` + `UnitPowerMax(unit)` (secret numbers — pass to SetValue/SetMinMaxValues directly)
  - `UnitPowerType(unit)` → color (blue=mana, red=rage, yellow=energy, orange=focus, etc.)
  - Event: `UNIT_POWER_UPDATE` (already registered), `UNIT_DISPLAYPOWER` for type changes
  - Thin bar (6px) below the heal-absorb bar

- [ ] **Target highlight** — glow/border when this frame's unit is your current target
  - `UnitIsUnit(unit, "target")` on `PLAYER_TARGET_CHANGED` event
  - Change backdrop border to bright white or gold when targeted

- [ ] **Aggro / threat highlight** — red border when unit has aggro
  - `UnitThreatSituation(unit)` returns 0–3 (3 = tanking, 2 = pulling aggro)
  - Event: `UNIT_THREAT_SITUATION_UPDATE`
  - Overlay on top of dispel highlight (aggro takes priority)

- [ ] **Buff/debuff duration timers** — countdown text on each aura icon
  - `aura.expirationTime` from `C_UnitAuras.GetAuraDataByIndex` minus `GetTime()` = seconds left
  - Format: `>60s` → show minutes ("2m"), `<60s` → show seconds ("14")
  - Cooldown swipe overlay: `CooldownFrame_Set(icon.cooldown, aura.expirationTime - aura.duration, aura.duration, 1)`

---

## Nice-to-Have (quality of life)

- [ ] **Incoming resurrection icon** — small icon when a res is on its way
  - `UnitHasIncomingResurrection(unit)` → bool, event `INCOMING_RESURRECT_CHANGED`

- [ ] **Summon pending icon** — icon when player has a pending summon
  - `C_IncomingSummon.HasIncomingSummon(unit)` → bool, event `INCOMING_SUMMON_CHANGED`

- [ ] **Raid target marker** — show skull/X/star etc. on frame
  - `GetRaidTargetIndex(unit)` → 1–8 or nil
  - Texture: `"Interface\\TargetingFrame\\UI-RaidTargetingIcons"` with SetTexCoord per index
  - Event: `RAID_TARGET_UPDATE`

- [ ] **AFK icon** — icon + timer when unit is AFK
  - `UnitIsAFK(unit)` → bool, event `CHAT_MSG_AFK` or poll on `UNIT_FLAGS`

- [ ] **Leader icon** — crown on group/raid leader
  - `UnitIsGroupLeader(unit)` → bool, event `GROUP_ROSTER_UPDATE` (already registered)

- [ ] **Vehicle icon** — icon when unit is in a vehicle
  - `UnitHasVehicleUI(unit)` → bool, event `UNIT_ENTERED_VEHICLE` / `UNIT_EXITED_VEHICLE`

- [ ] **Health fade** — frame fades toward transparent at full health (less visual noise)
  - `UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)` → fade alpha when >95%
  - Combine with OOR alpha (multiply both, don't just overwrite)

---

## Stretch / Future

- [ ] Player frame: show own castbar (channel + cast progress)
- [ ] Configurable frame size and layout from settings panel
- [ ] Show number of active crowd-control debuffs (CC tracker)
- [ ] Clickcasting support (right-click = custom spell on unit)
- [ ] Separate settings for party vs. raid (5-man vs 10/25-man layouts)
