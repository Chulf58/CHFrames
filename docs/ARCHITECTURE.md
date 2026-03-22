# CHFrames — Architecture

## CH UI Package Context

CHFrames is part of the **CH UI** addon suite alongside **CHUI** (character sheet replacement). The two addons are intentionally separate so CHFrames can be installed alone on a Steam Deck without requiring the full CHUI package.

| Addon | Purpose | Portability |
|---|---|---|
| CHUI | Character sheet replacement (gear, stats, reputation, vault) | Desktop only |
| CHFrames | D-pad / numpad party frames for controller play | Standalone — Steam Deck portable |

CHUI is declared as `OptionalDeps: CHUI` in the TOC. CHFrames must work identically whether CHUI is present or not. **Never read from or write to `CHUIDB` / `CHUIAccountDB`.** Shared conventions (naming, colors, pcall patterns) are followed for consistency, but there is no shared code.

---

## File Structure

```
CHFrames/
├── CHFrames.toc              # Manifest, load order, SavedVariables
├── CHFrames_Frames.lua       # Frame construction (root anchor + unit frames)
├── CHFrames_Minimap.lua      # Minimap button (orbit drag, auto-hide)
├── CHFrames_Settings.lua     # Settings panel (lock/unlock, test mode, show/hide)
└── CHFrames.lua              # Main module: constants, update logic, events, slash
```

**Load order** (defined in .toc):
```
CHFrames_Frames.lua → CHFrames_Minimap.lua → CHFrames_Settings.lua → CHFrames.lua
```

Frames are built before the main module loads so `CHFrames.BuildUnitFrame()` is available when `CHFrames.Init()` calls it.

---

## Global Namespace

All modules write to and read from the `CHFrames` table:

```lua
CHFrames = CHFrames or {}
```

Key references stored on the namespace:

| Key | Set by | Purpose |
|---|---|---|
| `CHFrames.root` | `BuildRootFrame()` | Drag anchor; all unit frames are children |
| `CHFrames.frames[unit]` | `Init()` | Unit frame refs keyed by unit string |
| `CHFrames.minimapBtn` | `BuildMinimapButton()` | Minimap button frame ref |
| `CHFrames.SettingsPanel` | `BuildSettingsPanel()` | Settings panel frame ref |

---

## Frame Hierarchy

```
UIParent
├── CHFramesRoot (16×16 drag anchor, MEDIUM strata)
│   ├── CHFramesFrame_party1  (200×78, BackdropTemplate)
│   ├── CHFramesFrame_party2
│   ├── CHFramesFrame_party3
│   ├── CHFramesFrame_party4
│   └── CHFramesFrame_player
│
└── CHFramesSecure_<unit> ×5  (SecureUnitButtonTemplate, parented to UIParent, overlays unit frame)
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

**Per-frame state fields** (initialized in `BuildUnitFrame`, read by the priority engine):

| Field | Initial value | Purpose |
|---|---|---|
| `f._priorityLevel` | `6` | Last applied priority level; used to skip redundant visual updates |
| `f._priorityOwnsBorder` | `false` | When `true`, `UpdateBorder` returns immediately without touching the border color |

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

## SavedVariables — CHFramesDB

```lua
CHFramesDB = {
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

Single event frame `CHFramesEventFrame` registered in `CHFrames.lua`.

| Event | Guard | Action |
|---|---|---|
| `ADDON_LOADED` | arg1 == "CHFrames" | Init DB, build frames, restore position |
| `GROUP_ROSTER_UPDATE` | — | UpdateVisibility + UpdateAll |
| `UNIT_HEALTH` | UNIT_LOOKUP[arg1] | UpdateFrame(arg1) → UpdatePriority(arg1) |
| `UNIT_POWER_UPDATE` | UNIT_LOOKUP[arg1] | UpdateFrame(arg1) |
| `UNIT_AURA` | UNIT_LOOKUP + not testMode | UpdateAuras(arg1) → UpdatePriority(arg1) |
| `PLAYER_FLAGS_CHANGED` | UNIT_LOOKUP[arg1] | UpdateFrame(arg1) → UpdatePriority(arg1) |
| `PLAYER_ENTERING_WORLD` | — | UpdateVisibility + UpdateAll |
| `UNIT_ABSORB_AMOUNT_CHANGED` | UNIT_LOOKUP[arg1] | UpdateAbsorbs(arg1) → UpdateFrame(arg1) → UpdatePriority(arg1) |
| `UNIT_HEAL_ABSORB_AMOUNT_CHANGED` | UNIT_LOOKUP[arg1] | UpdateAbsorbs(arg1) → UpdatePriority(arg1) |

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
| `CHFrames_Frames.lua` | `BuildRootFrame()`, `BuildUnitFrame()` — frame creation only, no logic |
| `CHFrames_Minimap.lua` | `BuildMinimapButton()`, `UpdateMinimapButtonPos()` |
| `CHFrames_Settings.lua` | `BuildSettingsPanel()`, `RefreshSettingsButtons()` |
| `CHFrames.lua` | `Init()`, `UpdateFrame()`, `UpdateAuras()`, `UpdateAbsorbs()`, `UpdateAll()`, `UpdateVisibility()`, `ApplyTestMode()`, `EvaluatePriority()`, `ApplyPrioritySignal()`, `UpdatePriority()`, `UpdateBorder()`, event handler, slash commands |

---

## Priority Engine

The priority engine determines the single most urgent visual state for each unit frame. It runs last in every update path so it always reads state already written by `UpdateFrame`, `UpdateAuras`, and `UpdateAbsorbs`.

### Functions

| Function | Signature | Role |
|---|---|---|
| `EvaluatePriority` | `(unit) → level, payload` | Pure logic. Reads frame state and unit APIs. No side effects. Returns a priority level (1–6) and a payload table. |
| `ApplyPrioritySignal` | `(f, priorityLevel, payload)` | Applies the visual for the given level. Skips work if `f._priorityLevel` hasn't changed. Called only from `UpdatePriority`. |
| `UpdatePriority` | `(unit)` | Orchestrator. Calls `EvaluatePriority` then `ApplyPrioritySignal`. Entry point for all callers. |

### Priority Levels

Levels are evaluated top-down; the first match wins.

| Level | Name | Condition |
|---|---|---|
| 1 | DEAD | Unit disconnected, ghost, dead, or AFK (checked via `issecretvalue` guard) |
| 2 | LETHAL_MECHANIC | A HARMFUL aura spell ID is in `LETHAL_MECHANIC_SPELLS` (stub — table empty until populated per season) |
| 3 | DISPELLABLE | `f._dispelColor` is non-nil (set by `UpdateAuras`) |
| 4 | CRITICAL_HP | `f._lastHpPct <= CRITICAL_HP_THRESHOLD` (20) |
| 5 | INCOMING_DAMAGE | `UnitGetTotalHealAbsorbs(unit)` returns a secret value (heal absorb is active) |
| 6 | NORMAL | None of the above |

### Visual Signals per Level

| Level | healthBar vertex tint | Backdrop color | Border | defIcon |
|---|---|---|---|---|
| 1 (DEAD) | grey (0.4, 0.4, 0.4) | default (0.05, 0.05, 0.05, 0.85) | not owned | hidden |
| 2 (LETHAL_MECHANIC) | reset (1, 1, 1) | red (0.5, 0.0, 0.0, 0.9) | not owned | shows mechanic icon from payload |
| 3 (DISPELLABLE) | reset (1, 1, 1) | default | owned — set to `payload.color`; suppresses `UpdateBorder` | unchanged |
| 4 (CRITICAL_HP) | reset (1, 1, 1) | orange-red (0.5, 0.2, 0.0, 0.85) | not owned | unchanged |
| 5 (INCOMING_DAMAGE) | reset (1, 1, 1) | dark red (0.35, 0.0, 0.0, 0.85) | not owned | unchanged |
| 6 (NORMAL) | reset (1, 1, 1) | default | not owned; `UpdateBorder` called to restore | `UpdateDefensive` called to restore |

### Border ownership

`f._priorityOwnsBorder = true` is set only at level 3 (DISPELLABLE). While owned, `UpdateBorder` returns immediately without touching the border color, preventing target/aggro/dispel logic from overwriting the priority signal. Ownership is cleared at all other levels so normal `UpdateBorder` logic resumes as soon as the dispel condition resolves.

### Constants

| Constant | Value | Purpose |
|---|---|---|
| `CRITICAL_HP_THRESHOLD` | `20` | HP% at or below this triggers level 4 |
| `LETHAL_MECHANIC_SPELLS` | `{}` (stub) | Set of `[spellID] = true` entries for mechanics requiring immediate action |
