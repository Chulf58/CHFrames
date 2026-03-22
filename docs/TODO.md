# CH_DPadParty — TODO

## High Priority / Infrastructure

- [ ] **Party frame: Decision mode (new display mode, toggled in settings)**

  Vision: *One frame = one decision*

  Toggle: `CHDPadPartyDB.displayMode = "legacy" | "decision"`. D-pad / Side-by-Side / Stacked layout is unchanged regardless of mode.

  ### Must-haves

  - **Priority engine** — evaluates all states on a unit, outputs ONE dominant state:
    `DEAD > LETHAL_MECHANIC > DISPELLABLE > CRITICAL_HP > INCOMING_DAMAGE > NORMAL`
    This is hardcoded logic, not user-configurable.
  - **Single dominant signal renderer** — consumes the priority engine output and applies ONE visual to the frame (full frame color override OR strong border glow OR large central icon). Replace, don't stack.
  - **Curated debuff list** — hardcoded, maintained per patch/season. Two tiers:
    - Lethal mechanics: must act in <2s (full red frame override)
    - Dispellable + dangerous: highlight by dispel type (magic=blue, curse=purple, etc.)
    - Everything else: hidden
  - **Settings toggle** — one button in the settings panel: `Mode: Legacy / Decision`. No other config in decision mode.

  ### Implementation order
  1. Priority engine (pure logic, returns state — no visuals yet)
  2. Decision renderer (visual layer consuming engine output)
  3. Toggle (wires legacy vs. decision render path)

  ### Design principles
  - Zero setup: install → instantly usable in Mythic+
  - Opinionated: the addon decides what matters, not the user
  - Instant readability: at a glance (<200ms) player knows who is in danger, why, and if they can fix it
  - No visual noise: hide everything that doesn't answer "do I need to act right now?"

  ### What decision mode does NOT have
  - Appearance customisation
  - Indicator grids
  - Multiple small simultaneous indicators
  - Any toggles beyond the mode switch itself

---

- [ ] **Raid frames — structured high-density grid (separate module: `CHFrames_Raid.lua`)**

  Vision: *Many frames, one coherent picture*

  Auto-shown when `IsInRaid()` is true; party frames hidden. Returns to party frames on raid leave. Trigger: `GROUP_ROSTER_UPDATE`.

  ### Core architecture differences from party frames

  Raid uses **structured multi-signal layering** (not single dominant signal). Each position on the frame has a fixed meaning:

  | Zone | Signal |
  |------|--------|
  | Center / health bar | HP + status |
  | Corners | HoTs / tracked buffs |
  | Border | Debuff state (color = type) |
  | Text | Name + HP% |

  Signals layer with hierarchy — critical debuff overrides border color, but HoTs remain visible in corners. Information is organized, not suppressed.

  ### Must-have systems

  - **Indicator system** — position-based, fixed meaning per slot. Every frame behaves identically so peripheral vision works.
  - **Debuff prioritization** — most critical feature. Lethal mechanics and dispellable debuffs must be immediately obvious. Dispellable vs. non-dispellable distinction must be clear. Raid wipes happen because mechanics are missed.
  - **HoT / buff tracking** — required for Druid, Priest, Monk healers. Show presence + optional duration (minimal). Fixed corner positions, must not clutter.
  - **Range / status** — out-of-range fade, dead/ghost/offline states. Essential for triage.
  - **Aggro / threat** — lightweight indicator (not dominant). Useful for tanks losing aggro, DPS pulling.
  - **Layout adaptability** — handles 10 / 20 / 30+ / 40-man without breaking. Configurable rows × columns (e.g. 5×8, 8×5, 10×4). `CHDPadPartyDB.raidLayout` settings independent from party layout.
  - **Performance at scale** — 40 units × multiple simultaneous updates. No CPU spikes, no frame drops. This is where bad addons die.

  ### Key differences from party display mode

  | Party (decision mode) | Raid |
  |-----------------------|------|
  | One dominant signal | Structured multi-signal |
  | Replace on priority | Layer with hierarchy |
  | Fully opinionated | Config expected by users |
  | No customisation | Role-adaptive (healer/DPS/tank emphasis) |

  ### Configuration philosophy

  Unlike party frames, raid users expect customisation because different classes need different info. Healers need HoTs + debuffs. DPS need minimal + mechanics. Tanks need threat + externals. The config must be **powerful but understandable** — current opportunity: Grid2 is powerful but painful.

  ### Technical notes
  - `UNIT_LOOKUP` table extended dynamically on roster update to cover active `raidN` tokens (`raid1`–`raid40`)
  - Hide Blizzard raid frames the same way as party frames (via `RegisterStateDriver`, see G-075)
  - Sub-group headers, main tank / main assist markers, role sorting: post-MVP
  - This is a significant new system — plan as a separate module (`CHFrames_Raid.lua`) to keep party code clean

- [ ] **Rename addon from "CH D-Pad Party" to "CHFrames"**
  - Rename the addon folder: `CH_DPadParty` → `CHFrames`
  - Update `.toc` file: `## Title:`, `## Interface:`, SavedVariables name (`CHDPadPartyDB` → `CHFramesDB`), and all `## X-*` metadata fields
  - Rename all `.lua` files: `CH_DPadParty*.lua` → `CHFrames*.lua`
  - Global namespace: replace `CHDPadParty` → `CHFrames` throughout all Lua files
  - SavedVariables rename: `CHDPadPartyDB` → `CHFramesDB` (existing saves will be lost unless a migration shim is added)
  - In-game strings: update slash command (`/chdpad` → `/chframe`), minimap tooltip, settings panel title, and any print messages
  - GitHub repo rename: `CH_DPadParty` → `CHFrames` (update remote URL in local git config)
  - Wago project: update addon title; the `X-Wago-ID` stays the same so existing installs continue receiving updates

- [ ] **Full appearance customisation system** — deep-dive all visual options and expose everything in the settings panel

  ### Health bar style
  - **Color mode**: class color (current default) | solid green | solid white | role color (blue=tank, green=heal, red=dps) | custom RGBA
  - **Texture**: which StatusBar texture to use (UI-StatusBar, Blizzard default, smooth gradient, etc.)
  - **Show HP% text**: toggle on/off
  - **HP% text position**: bottom-center (current) | top-center | center | BOTTOMRIGHT
  - **HP% text font size**: small / normal / large

  ### Class icon (left panel)
  - **Show/hide** class icon: toggle
  - **Icon style**:
    - Class icon (current) — `Interface\WorldStateFrame\Icons-Classes`, texcoords per class
    - Spec icon — `C_Specialization.GetSpecializationInfoByID` returns a `specIcon` FileID; show spec instead of class
    - 3D portrait — `SetPortraitTexture(texture, unit)` renders the in-game 3D face portrait into a texture; needs a `Model` frame or `SetPortraitTextureFromUnit`
    - 2D portrait — `SetPortraitToTexture(texture, unit)` for the flat portrait
  - **Icon border**: none | thin black | colored by class

  ### Frame background / border
  - **Background color**: current dark RGBA | transparent | custom
  - **Background alpha**: slider 0–1
  - **Border color**: default grey | class color | custom
  - **Border style**: thin (edgeSize 12) | thick (edgeSize 16) | none

  ### Absorb / overlay bars
  - **Absorb bar color**: electric blue (current) | white | custom RGBA
  - **Absorb bar alpha**: slider 0–1
  - **Heal absorb bar color**: dark red (current) | custom
  - **Show absorb bar**: toggle

  ### Power bar
  - **Show/hide** power bar: toggle
  - **Power bar height**: 4px / 6px (current) / 8px

  ### Buff / debuff icons
  - **Number of buff slots**: 0–5 (current 3)
  - **Number of debuff slots**: 0–5 (current 3)
  - **Icon size**: 16×16 | 20×20 (current) | 24×24
  - **Show duration timer text**: toggle
  - **Show cooldown swipe**: toggle
  - **Show stack count**: toggle
  - **Duration filter**: show all with duration | only short (<30s) | only medium (<3min) | all with timers
  - **Aura layout**: left-to-right (current) | right-to-left | stacked vertically
  - **Show dispel border**: toggle (currently always on for player's dispel class)

  ### Role icon
  - **Show/hide** role icon: toggle
  - **Role icon position**: top-left inside bar (current) | below class icon | top-right

  ### Leader crown
  - **Show/hide** crown: toggle

  ### Defensive icon
  - **Show/hide** defensive CD icon: toggle
  - **Icon size**: 16×16 | 20×20 (current) | 24×24
  - **Priority**: external > personal (current) | personal > external | show both

  ### Range dimming
  - **Out-of-range alpha**: 0.4 (current) | 0.2 | 0.6 | custom
  - **Enable/disable** range check: toggle

  ### Frame size
  - **Width**: slider (default 200)
  - **Height**: slider (default 78)

  ### Implementation notes
  - All settings stored in `CHDPadPartyDB` with per-setting defaults
  - Settings panel needs overhaul (tabbed layout) before most of these can be exposed
  - 3D portrait (`SetPortraitTextureFromUnit`) requires a `PlayerModel` frame — research taint implications
  - Spec icon: `GetSpecializationInfoByID(GetInspectSpecialization(unit))` may require inspect; check availability for party members without inspect

- [ ] **Settings panel overhaul** — current flat button layout won't scale as more options are added
  - Replace the flat single-column panel with a tabbed or sectioned layout (e.g. General / Layout / Appearance / Auras tabs)
  - Layout selector: convert cycle button to a proper dropdown menu (WoW `UIDropDownMenu` or a custom scrollable list)
  - Group related settings: lock/unlock + drag under "General"; layout mode + scale under "Layout"; colors, opacity, frame size under "Appearance"; aura slot count, duration display, icon size under "Auras"
  - Add descriptive sub-labels or tooltips for each setting (what it does, valid range)
  - Consistent spacing system: fixed row height, section headers with separator lines
  - The panel should grow gracefully — adding a new setting should be one line, not a layout restructuring
  - Consider using WoW's built-in `InterfaceOptions` panel registration (`Settings.RegisterAddOnCategory`) for discoverability, alongside the minimap button shortcut


- [x] **Auto-hide default WoW party frames when this addon is enabled**
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

## Class-Specific Mechanics

- [x] **Atonement tracker (Discipline Priest)** — make it immediately obvious which party members have Atonement active
  - Atonement (spellID 194384) is applied by the Disc Priest to party members via Power Word: Shield, Plea, Shadow Mend, etc.
  - When the Priest deals damage, all active Atonement targets are healed — knowing who has it (and for how long) is the core gameplay loop of Disc Priest healing
  - **Visual options to consider:**
    - Bright golden/white glow or border pulse on the unit frame when Atonement is present
    - A dedicated Atonement duration bar (thin bar below/above the health bar, distinct color — e.g. bright yellow or white)
    - Large prominent icon (30×30 or bigger) in a fixed position on the frame, not mixed in with regular buff icons
    - Remaining duration text shown prominently (countdown in large font, center of frame or below health bar)
    - Frames WITHOUT Atonement could be visually dimmed or have a distinct "needs Atonement" border color
  - Detection: `C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")` scanning for spellId == 194384
  - Expiration: `aura.expirationTime` drives the duration display; `aura.duration` is typically 15s
  - Event: `UNIT_AURA` already registered
  - This feature is only relevant when the player is a Discipline Priest — detect via `select(2, UnitClass("player")) == "PRIEST"` and `GetSpecialization() == 1` (Discipline is spec index 1)
  - Could be extended to a general "highlighted spell" system: player configures a spell ID to always show prominently regardless of class

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

- [x] **Dispel priority + class-aware filtering + debuff type icons**
  - **⚠ Research needed**: Blizzard changed private/public aura visibility rules for debuffs (TWW patch, 2026-03-21 week). Must verify which debuffs are visible to non-casters via `C_UnitAuras` before implementing.
  - Dispellable debuffs must always appear first in the debuff slots (sort by dispellability)
  - Only highlight dispellable debuffs that the player's class can actually remove:
    - Priests: Magic, Disease
    - Druids: Magic, Curse, Poison
    - Paladins: Magic, Poison, Disease
    - Shamans: Magic, Curse, Poison
    - Monks: Magic, Poison, Disease (Detox)
    - Mages: Curse (Remove Curse)
    - Warlocks: Magic on self only (Singe Magic via Imp)
  - Colored border per debuff type (Magic=blue, Curse=purple, Poison=green, Disease=brown) — only active for types the player can dispel
  - **Debuff type icon**: small icon in the corner of each debuff slot showing the type (same icons Blizzard default frames use — `DebuffTypeAtlas` or `Interface\Icons\Debuff_*` textures). Easier to read than border color alone on Steam Deck.
  - Source: `aura.dispelName` from `C_UnitAuras.GetAuraDataByIndex` gives the type string directly

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

- [x] **Defensive ability icon** — show the icon of the active defensive cooldown in the center of the health bar
  - **Personal defensives**: when a unit activates a personal defensive (e.g. Barkskin, Ice Block, Divine Shield, Survival Instincts, Blur, etc.) show the ability icon centered on their health bar
  - **External defensives**: when an external defensive is cast ON another party member (e.g. Blessing of Sacrifice, Rallying Cry, Pain Suppression, Guardian Angel, Life Cocoon, etc.) show the icon on the target's frame
  - Icon size: approximately the same as the class icon (20×20 or 22×22)
  - Positioned in the center of the health bar, overlaid on top
  - Detection via UNIT_AURA: scan buffs for known defensive spell IDs; show the icon of the most recently applied one (or highest priority)
  - Priority: external defensives > personal defensives (external ones matter more for healer awareness)
  - Auto-hide when the buff expires (use expiration time from aura data to drive visibility)
  - Key spells to track:
    - **Paladins**: Blessing of Sacrifice (6940), Divine Shield (642)
    - **Druids**: Barkskin (22812), Survival Instincts (61336)
    - **Priests**: Pain Suppression (33206), Guardian Spirit (47788)
    - **Monks**: Life Cocoon (116849)
    - **Warriors**: Rallying Cry (97462)
    - **Mages**: Ice Block (45438)
    - **Demon Hunters**: Blur (198589)
    - **Death Knights**: Anti-Magic Shell (48707)
    - **Evokers**: Emerald Boon (370960), Rescue (370665)
  - Research needed: confirm which auras are visible via C_UnitAuras on other party members (private vs public aura rules)

- [x] **Incoming resurrection icon** — green icon (bottom-left) when a res is incoming
  - `UnitHasIncomingResurrection` + `INCOMING_RESURRECT_CHANGED`

- [x] **Summon pending icon** — purple icon (same frame as rez, bottom-left) when summoned
  - `C_IncomingSummon.HasIncomingSummon` + `INCOMING_SUMMON_CHANGED`

- [x] **Raid target marker** — skull/X/star shown in top-right corner of unit frame
  - `GetRaidTargetIndex` → SetTexCoord on `UI-RaidTargetingIcons`; `RAID_TARGET_UPDATE`

- [x] **AFK status** — "AFK" shown in the dead/ghost/offline overlay
  - `UnitIsAFK`; `PLAYER_FLAGS_CHANGED` already registered

- [x] **Leader icon** — crown above class icon (already implemented via leaderCrown frame)

- [x] **Vehicle icon** — icon when unit is in a vehicle
  - `UnitHasVehicleUI(unit)` → bool, event `UNIT_ENTERED_VEHICLE` / `UNIT_EXITED_VEHICLE`

- [ ] **Health fade** *(disabled — caused permanent grey-out)*
  - Whole-frame alpha reduction at full HP was too visible and confusing
  - Better approach: dim only the health bar backdrop or border, not the whole frame

- [ ] **HP text: absorb indicator** — blocked by secret numbers (see GOTCHAS G-076, G-078)
  - `UnitGetTotalAbsorbs` has `SecretReturns` predicate: returns a secret-wrapped value in ALL
    restricted contexts (M+/combat/PvP) regardless of whether a shield is present.
    `issecretvalue()` therefore always returns `true` in combat → false-positive indicator.
  - Absorb % cannot be computed: arithmetic between two secret numbers throws.
  - Current workaround: the blue `absorbBar` overlay visually shows shield presence and magnitude.
  - Possible future solution: if Blizzard adds a `UnitAbsorbPercent()` API (like they added
    `UnitHealthPercent`) this becomes straightforward. Watch for it in future patches.

- [x] **Resource bar layout** — health bar → power bar → buffs/debuffs
  - Power bar at y=-46 (directly below health bar); buffs/debuffs at y=-54
  - Frame stays 74px — pixel math worked out exactly

- [x] **Buff/debuff icon size + duration readability**
  - Current icons are 16×16 — too small to read duration text (7pt font) at a glance, especially on Steam Deck
  - Options to investigate:
    1. Increase icon size to 20×20 or 22×22; may require reducing slot count from 3 to 2 per side to fit
    2. Keep 16×16 icons but increase font size for duration (e.g. 8–9pt) and move timer below the icon instead of overlapping
    3. Show duration only on hover / only for short durations (<30s) to reduce clutter
  - Duration format is fine (Xh/Xm/s) — just needs to be bigger/more visible
  - Should be consistent for both buff and debuff icons


---

## Stretch / Future

- [x] **Multiple frame layout modes** — selectable in the settings panel
  - **Handheld** *(current)*: D-pad/numpad layout — party1 top, party2 left, party3 right, party4 bottom, player below. Optimised for Steam Deck thumb navigation.
  - **Side-by-side**: all 5 frames in a single horizontal row (party1–4 + player left→right). Good for widescreen/ultrawide.
  - **Stacked**: all 5 frames in a single vertical column (party1 at top, player at bottom). Good for a vertical sidebar on the left/right edge of the screen.
  - Implementation: swap the `OFFSETS` table based on a `CHDPadPartyDB.layout` setting (`"handheld"` / `"sidebyside"` / `"stacked"`). Settings panel gets a cycle button. Saved across sessions.
  - Horizontal spacing for side-by-side: frame width(200) + gap(8) = 208 per slot.
  - Vertical spacing for stacked: already known — frame height(78) + gap(8) = 86 per slot.

- [ ] Player frame: show own castbar (channel + cast progress)
- [ ] **Configurable frame size (width & height) in settings panel**
  - Width slider (default 200px, range 120–320) and height slider (default 78px, range 50–120)
  - Stored as `CHDPadPartyDB.frameWidth` / `CHDPadPartyDB.frameHeight`
  - Changing width: call `f:SetWidth()` on all unit frames; update layout OFFSETS for side-by-side spacing (`frameWidth + 8`)
  - Changing height: call `f:SetHeight()` on all unit frames; recalculate OFFSETS vertical spacing (`half-height + gap + half-height`) — see GOTCHAS "Frame height changes require recalculating OFFSETS"
  - Health bar height = `frameHeight - 38` (keeps 6px power bar + 20px aura row + bottom padding)
  - Settings panel: two sliders in the Layout tab, alongside the existing scale/layout controls
  - Must be blocked in combat (`InCombatLockdown()`) since frame resizing is a layout operation
- [ ] Show number of active crowd-control debuffs (CC tracker)
- [ ] Clickcasting support (right-click = custom spell on unit)
- [ ] Separate settings for party vs. raid (5-man vs 10/25-man layouts)

---

## Unit Frames (Player / Target / Focus)

Vision: *Always-visible, always-readable combat anchors*

These answer: "What is happening to ME and my target?" — personal state + combat context.
Not decision engines. Not group awareness. Pure state display.

### Must-haves (non-negotiable)

- **Health + resource bars** — foundation of everything. Smooth updates, no jitter, instantly readable. If this feels bad, everything fails.
- **Cast bar** — for target, focus, and boss. Must show: cast name, progress bar, interruptible vs. not. One of the highest-value elements in combat.
- **Curated buff/debuff display** — show: important player buffs, important target debuffs, DoTs for DPS tracking. Hide: full aura lists, 20+ icon dumps. Curate, don't dump.
- **Combat state indicators** — in combat / out of combat, dead/ghost, target classification.
- **Threat awareness** — lightweight (safe / warning / pulling aggro). Not visually dominant unless critical.
- **Target identity** — name, level/classification (boss, elite), optional role/type. Must answer instantly: what am I targeting, is it dangerous?
- **Pet frame** — exists, clear, unobtrusive. Health + important states only. Do not overdesign.

### Differentiators

- **Readability during movement** — peripheral-vision first. Player is moving, dodging, reacting to mechanics. Frames must be readable without direct focus.
- **Smoothness** — fluid transitions, instant feedback. Health jumps and laggy updates are the biggest failure mode here.
- **Information hierarchy**: always-important (health, resource) → situational (casts, debuffs) → secondary (minor buffs, flavor). Never reversed.
- **Screen placement synergy** — competes with action bars, nameplates, mechanic callouts. Must fit cleanly without dominating.

### Optional / post-MVP

- Focus frame support
- Target-of-target
- Some positioning and scaling options (users expect this, unlike party frames)

### Design constraints

- Do NOT try to replace combat logic systems or encounter awareness
- Do NOT show full aura lists
- Do NOT make frames oversized — they are anchors, not dashboards
- Minimal config, but some flexibility on positioning and scale is expected
