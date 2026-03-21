# CH_DPadParty — Architecture

## CH UI Package Context

CH_DPadParty is part of the **CH UI** addon suite alongside **CHUI** (character sheet replacement). The two addons are intentionally separate so CH_DPadParty can be installed alone on a Steam Deck without requiring the full CHUI package.

| Addon | Purpose | Portability |
|---|---|---|
| CHUI | Character sheet replacement (gear, stats, reputation, vault) | Desktop only |
| CH_DPadParty | D-pad / numpad party frames for controller play | Standalone — Steam Deck portable |

CHUI is declared as `OptionalDeps: CHUI` in the TOC. CH_DPadParty must work identically whether CHUI is present or not. **Never read from or write to `CHUIDB` / `CHUIAccountDB`.** Shared conventions (naming, colors, pcall patterns) are followed for consistency, but there is no shared code.

---

## File Structure

```
CH_DPadParty/
├── CH_DPadParty.toc              # Manifest, load order, SavedVariables
├── CH_DPadParty_Frames.lua       # Frame construction (root anchor + unit frames)
├── CH_DPadParty_Minimap.lua      # Minimap button (orbit drag, auto-hide)
├── CH_DPadParty_Settings.lua     # Settings panel (lock/unlock, test mode, show/hide)
└── CH_DPadParty.lua              # Main module: constants, update logic, events, slash
```

**Load order** (defined in .toc):
```
CH_DPadParty_Frames.lua → CH_DPadParty_Minimap.lua → CH_DPadParty_Settings.lua → CH_DPadParty.lua
```

Frames are built before the main module loads so `CHDPadParty.BuildUnitFrame()` is available when `CHDPadParty.Init()` calls it.

---

## Global Namespace

All modules write to and read from the `CHDPadParty` table:

```lua
CHDPadParty = CHDPadParty or {}
```

Key references stored on the namespace:

| Key | Set by | Purpose |
|---|---|---|
| `CHDPadParty.root` | `BuildRootFrame()` | Drag anchor; all unit frames are children |
| `CHDPadParty.frames[unit]` | `Init()` | Unit frame refs keyed by unit string |
| `CHDPadParty.minimapBtn` | `BuildMinimapButton()` | Minimap button frame ref |
| `CHDPadParty.SettingsPanel` | `BuildSettingsPanel()` | Settings panel frame ref |

---

## Frame Hierarchy

```
UIParent
├── CHDPadPartyRoot (16×16 drag anchor, MEDIUM strata)
│   ├── CHDPadPartyFrame_party1  (200×78, BackdropTemplate)
│   ├── CHDPadPartyFrame_party2
│   ├── CHDPadPartyFrame_party3
│   ├── CHDPadPartyFrame_party4
│   └── CHDPadPartyFrame_player
│
└── CHDPadPartySecure_<unit> ×5  (SecureUnitButtonTemplate, parented to UIParent, overlays unit frame)
```

Each unit frame contains (top to bottom):

```
f (outer frame, 200×78)
├── healthBar (StatusBar, 40px tall, class-colored)
│   ├── absorbBar (StatusBar, SetAllPoints(healthBar), white overlay, reverse fill)
│   ├── healAbsorbBar (StatusBar, SetAllPoints(healthBar), red overlay, reverse fill)
│   ├── nameText (FontString, OVERLAY)
│   ├── hpText (FontString, OVERLAY)
│   └── roleIcon (Texture, OVERLAY)
├── overlay (dead/ghost/offline backdrop, hides when alive)
├── buffIcons[1..3] (20×20 frames with tex + count; timer FontString 9pt)
└── debuffIcons[1..3] (20×20 frames with tex + count; timer FontString 9pt)
```

**Frame level rules:**
- Absorb overlay bars: parented to `healthBar` — bar's OVERLAY layer (text, icons) renders above them
- secureBtn: frame level 100, parented to UIParent, overlays the unit frame for click interception

---

## Layout — Numpad / D-Pad

```
        [party1]
[party2] [root] [party3]
        [party4]
        [player]
```

Frame size: 200×78px (39px half-height). Root anchor is 16×16. Offsets from root CENTER with 8px gaps:

| Unit | x | y |
|---|---|---|
| party1 | 0 | +86 |
| party2 | -104 | 0 |
| party3 | +104 | 0 |
| party4 | 0 | -86 |
| player | 0 | -172 |

---

## SavedVariables — CHDPadPartyDB

```lua
CHDPadPartyDB = {
    position    = { point, relativePoint, x, y },  -- root anchor position
    visible     = true,       -- root shown/hidden
    locked      = true,       -- drag locked/unlocked
    minimapPos  = 210,        -- minimap button angle (degrees)
    testMode    = false,      -- always reset to false on ADDON_LOADED (session-only)
    settingsX   = nil,        -- settings panel position (nil = default center)
    settingsY   = nil,
}
```

**Rules:**
- Initialize each key with `if key == nil then` — never use `or` for boolean defaults
- `testMode` is always reset to `false` on `ADDON_LOADED`
- Never add keys that persist test/preview state

---

## Event Model

Single event frame `CHDPadPartyEventFrame` registered in `CH_DPadParty.lua`.

| Event | Guard | Action |
|---|---|---|
| `ADDON_LOADED` | arg1 == "CH_DPadParty" | Init DB, build frames, restore position |
| `GROUP_ROSTER_UPDATE` | — | UpdateVisibility + UpdateAll |
| `UNIT_HEALTH` | UNIT_LOOKUP[arg1] | UpdateFrame(arg1) |
| `UNIT_POWER_UPDATE` | UNIT_LOOKUP[arg1] | UpdateFrame(arg1) |
| `UNIT_AURA` | UNIT_LOOKUP + not testMode | UpdateAuras(arg1) |
| `PLAYER_FLAGS_CHANGED` | UNIT_LOOKUP[arg1] | UpdateFrame(arg1) |
| `PLAYER_ENTERING_WORLD` | — | UpdateVisibility + UpdateAll |
| `UNIT_ABSORB_AMOUNT_CHANGED` | UNIT_LOOKUP[arg1] | UpdateAbsorbs(arg1) |
| `UNIT_HEAL_ABSORB_AMOUNT_CHANGED` | UNIT_LOOKUP[arg1] | UpdateAbsorbs(arg1) |

`UNIT_LOOKUP` table (`party1–4 + player = true`) guards all unit-specific events to avoid processing untracked units.

---

## Key WoW APIs

| Area | API |
|---|---|
| Health | `UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)` — plain 0–100 float |
| Absorbs | `UnitGetTotalAbsorbs(unit)`, `UnitGetTotalHealAbsorbs(unit)` — secret numbers, C only |
| Heal prediction | `UnitGetIncomingHeals(unit)` — secret number, C only |
| Max HP | `UnitHealthMax(unit)` — secret number, C only (SetMinMaxValues) |
| Auras | `C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL"/"HARMFUL")` |
| Role | `UnitGroupRolesAssigned(unit)` → "TANK" / "HEALER" / "DAMAGER" / "NONE" |
| Range | `UnitInRange(unit)` (secret bool, guard with issecretvalue), `CheckInteractDistance(unit, 4)` |
| Resource | `UnitPower(unit)`, `UnitPowerMax(unit)`, `UnitPowerType(unit)` |
| Group state | `IsInGroup()`, `IsInRaid()`, `UnitExists(unit)` |
| Secure | `RegisterUnitWatch(secureBtn)` — manages secure frame visibility |

---

## Module Responsibilities

| Module | Owns |
|---|---|
| `CH_DPadParty_Frames.lua` | `BuildRootFrame()`, `BuildUnitFrame()` — frame creation only, no logic |
| `CH_DPadParty_Minimap.lua` | `BuildMinimapButton()`, `UpdateMinimapButtonPos()` |
| `CH_DPadParty_Settings.lua` | `BuildSettingsPanel()`, `RefreshSettingsButtons()` |
| `CH_DPadParty.lua` | `Init()`, `UpdateFrame()`, `UpdateAuras()`, `UpdateAbsorbs()`, `UpdateAll()`, `UpdateVisibility()`, `ApplyTestMode()`, event handler, slash commands |
