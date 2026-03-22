# Addon Reference Research — DandersFrames, Cell, ElvUI

Research conducted 2026-03-22. Notes on how production WoW unit frame addons handle key systems.

---

## DandersFrames

**Source:** `Interface\AddOns\DandersFrames`

### Frame Construction
- XML templates (`DandersFrames.xml`) define `DandersUnitButtonTemplate` inheriting `SecureUnitButtonTemplate + SecureHandlerEnterLeaveTemplate`
- Lua `Frames/Create.lua:545` — `DF:CreateFrameElements(frame, isRaid)` builds all elements in order
- Content overlay at z-level +25 keeps text/icons above all StatusBars
- Borders built from 4 separate textures (top/bottom/left/right) at z-level +10 — avoids backdrop limitations

### Health Bar Color Modes
- `CUSTOM` — fixed RGBA from db
- `CLASS` — `RAID_CLASS_COLORS[class]` with per-class override support (`db.classColors[class]`)
- `PERCENT` — gradient via `C_CurveUtil.CreateColorCurve()` with weighted low/medium/high color points
  - Curve built once per class and cached — not rebuilt per update
  - Applied via `tex:SetVertexColor()` on the StatusBar texture (not SetStatusBarColor)
  - `UnitHealthPercent(unit, true, curve)` evaluates the curve at the current % point

### Secret Number Handling
- `issecretvalue()` used before any Lua comparison on health/absorb values
- `SetAlphaFromBoolean(hasExpiration, alpha, 0)` gates secret booleans without Lua evaluation
- `SetFormattedText()` used for display (C-side, accepts secret values directly)
- `SetValue()` / `SetMinMaxValues()` only — no Lua arithmetic

### Aura System
- `C_UnitAuras.GetAuraDataByAuraInstanceID()` — primary API
- `C_UnitAuras.GetAuraDuration(unit, auraInstanceID)` returns object with `EvaluateRemainingPercent(curve)` method
- Shared 5 FPS timer (AnimationGroup) for ALL icons — single timer, not per-icon OnUpdate
- Table pooling: `AcquireTable()` / `ReleaseTable()` to avoid GC pressure
- Duration color curve: 0%=red, 30%=orange, 50%=yellow, 100%=green
- "Hide above N seconds": Step curve with `Enum.LuaCurveType.Step` — avoids secret value comparisons

### Role Detection
- `UnitGroupRolesAssigned(unit)` for normal party members
- For delve companion NPCs: schedules a FOLLOWER_RECHECK 2 seconds after zone-in if `GetNumGroupMembers() < 5`. Max 3 retries. NPCs eventually report via `UnitGroupRolesAssigned()` normally.

### Performance
- `RegisterUnitEvent(event, unit)` instead of global `RegisterEvent()` — C++ level filtering, Lua never sees events for untracked units
- Central event dispatcher: single frame, `unitFrameMap[unit]` for O(1) frame lookup
- Throttled roster updates with `sliderDragging` flag to prevent recursive layout

### Settings
- Separate `db.party` and `db.raid` subtables — `GetFrameDB(frame)` returns correct one
- `db.absorbBarMode`: "OVERLAY" | "ATTACHED" | "FLOAT"
- Profile export/import: AceSerializer-3.0 + LibDeflate + base64

### Pixel Perfect
```lua
function DF:PixelPerfect(value)
    local scale = UIParent:GetEffectiveScale()
    return math.ceil(value * scale) / scale
end
```

---

## Cell

**Source:** `Interface\AddOns\Cell`

### Frame Hierarchy
```
CellParent (UIParent overlay)
└── CellMainFrame (secure)
    ├── CellRaidFrame (SecureGroupHeader instances, groups 1-8)
    ├── CellPartyFrame
    └── CellSoloFrame
```

### Unit Button Structure (`RaidFrames/UnitButton.lua`, 4012 lines)
```
Button
├── widgets
│   ├── healthBar (StatusBar)
│   │   ├── incomingHeal (texture overlay)
│   │   ├── absorbBar (overlay)
│   │   └── healAbsorbBar (overlay)
│   ├── healthBarLoss (damage taken visual)
│   ├── powerBar (StatusBar)
│   └── backdrop
├── indicators (30+ built-in + custom)
│   ├── nameText, healthText, powerText, statusText
│   ├── roleIcon, statusIcon
│   ├── debuffs, raidDebuffs
│   ├── defensiveCooldowns, externalCooldowns
│   ├── dispels, crowdControls, missingBuffs
└── states (cached: unit, guid, class, healthPercent, inRange, isDeadOrGhost...)
```

### Health Color
```lua
F.GetHealthBarColor(percent, isDeadOrGhost, r, g, b)
-- Returns barR, barG, barB, lossR, lossG, lossB
-- Blends via CellDB["appearance"]["colorThresholds"]
-- Red (low) → Yellow (mid) → class color (high)
```
Special states: offline=gray, charmed=purple, vehicle=yellow-green

### Aura System
- Uses `GetAuraSlots(unit, filter)` + `GetAuraDataBySlot(unit, slot)` (modern retail API)
- Dual caches: `button._buffs_cache` + `button._debuffs_cache` keyed by `auraInstanceID`
- Supports full rescan AND incremental updates from the same cache
- Debuff priority tiers: big debuffs → raid debuffs → normal debuffs → dispellable → CC
- Indicator update queue: **2 buttons processed per frame** via OnUpdate — prevents roster-update stutter
- Refresh animation detection: checks if `newExpiration > oldExpiration + 0.5` OR stack count increased

### Settings Structure (SavedVariables)
```lua
CellDB = {
    ["appearance"] = {
        ["barColor"] = {"class_color", {r,g,b}},  -- "class_color" or "custom"
        ["colorThresholds"] = {{1,0,0},{1,0.7,0},{0.7,1,0}, 0.05, 0.95, true},
        ["healPrediction"] = {true, false, {1,1,1,0.4}},
        ["shield"] = {true, {1,1,1,0.4}},
        ["overshield"] = {true, {1,1,1,1}},
        ["barAlpha"] = 1.0,
    },
    ["layouts"] = {
        ["default"] = { size={66,46}, powerSize=2, spacingX=3, spacingY=3, ... },
        ["party"] = { ... },
        ["raid_mythic"] = { ... },
    },
    ["layoutAutoSwitch"] = {
        ["role"] = { ["TANK"]={...}, ["HEALER"]={...}, ["DAMAGER"]={...} },
        ["WARRIOR"] = { ["TANK"]={...} },  -- class overrides
    },
    ["indicators"] = {
        { indicatorName="debuffs", enabled=true, size={{18,18},{24,24}}, num=5, numPerLine=5, ... },
        -- 30+ entries
    },
}
```

### Clever Patterns
- Callback system: `Cell.RegisterCallback(event, name, fn)` / `Cell.Fire(event, ...)` — decouples 150+ files
- Layout auto-switch by spec > role > instance type > PvP bracket
- `SecureGroupHeader` attributes drive all group management — no custom unit iteration
- Glow effects on priority debuffs: Normal, Pixel, Shine, Proc types

---

## ElvUI

**Source:** `Interface\AddOns\ElvUI`
**Key files:** `Game/Shared/Modules/UnitFrames/`

### Architecture
- Built on oUF framework (`ElvUF:SpawnHeader()`, `ElvUF:Spawn()`, `ElvUF:RegisterStyle()`)
- 35 element files — each element is self-contained with PostUpdate hooks
- `PostUpdate` / `PostUpdateColor` callbacks allow extension without modifying core

### Health Color (4 Modes)
- `FORCE_ON` — always class + reaction color
- `FORCE_OFF` — smooth gradient (red→yellow→class) OR solid custom color
- `USE_DEFAULT` — intelligent: gradient if enabled, else class color with reaction override
- `healthBreak` — custom threshold tiers with good/neutral/bad color bands

### Aura Filter Architecture
- String-based priority list: `'Personal,RaidDebuffs,Blacklist,NonPersonal'`
- Parsed at config time into `filterList` table — not recalculated per aura
- Each filter: type ('Whitelist'|'Blacklist') + spells table `{[spellID]={enable, priority}}`
- Stored in `E.global` (account-wide), not profile — shared across characters
- Blocklist checked first as fast-path

### Aura Sorting
5 sort functions: `TIME_REMAINING`, `DURATION`, `NAME`, `PLAYER`, `INDEX`
Direction: `ASCENDING` / `DESCENDING`

### Settings Schema (`Game/Shared/Defaults/Profile.lua`, 3496 lines)
```lua
P.unitframe = {
    colors = {
        healthclass = false,          -- use class color for health
        colorhealthbyvalue = true,    -- gradient by HP%
        healthBreak = { enabled, high, low, good/neutral/bad },
        power = { MANA={}, RAGE={}, FURY={}, ... },
        reaction = { [1]=hostile, [5]=friendly, ... },
        healPrediction = { personal={}, others={}, absorbs={} },
        debuffHighlight = { Magic={}, Curse={}, blendMode='ADD' },
    },
    units = {
        player = { width=270, height=54, orientation='LEFT',
            health = { text_format='[health:current/max]', ... },
            buffs = { perrow=8, numrows=2, ... },
            castbar = { latency=true, ... },
        },
        target = {...}, party = {...}, raid1 = {...}, raid2 = {...}, raid3 = {...},
    }
}
```

### Performance (40-man)
- Eventless update mode: GUID change detection drives full update vs. health-only fast path
- Update frequencies: secret values (slow) > health/power (moderate) > predictions (slowest)
- Auras: event-driven (`UNIT_AURA`), not frame-driven
- `Update_AllFrames()` — single batch pass, not per-frame individual calls

### Semantic Z-layering (RaisedElement system)
```
+0:  Auras
+5:  PrivateAuras
+10: PVPSpecIcon
+20: RaidDebuffs
+25: AuraWatch
+40: CastBar
```
Eliminates hard-coded frame level conflicts across 35 elements.

### Aura Stack Deduplication
```lua
ExcludeStacks = {[spellID]='name'}       -- never merge
SourceStacks  = {[spellID]='source_type'} -- merge per source
stacks = {['source:name'] = button}       -- track merged
```
Handles Evoker's Ebon Might (same buff from multiple sources).

### Layout
- 3 raid headers (raid1/2/3), each independent with own SecureGroupHeader
- `db.raidWideSorting` — sort all groups together vs. per-group
- Frame dimensions computed from: portrait presence, power bar mode (inset/spaced/offset), classbar height, infopanel height

---

## Key Takeaways for CHFrames

| Problem | Best Pattern Found |
|---------|-------------------|
| Health gradient | DandersFrames: `C_CurveUtil.CreateColorCurve()` + `UnitHealthPercent(unit, true, curve)` — cached per class |
| Aura timers | DandersFrames: single shared 5 FPS AnimationGroup timer, not per-icon OnUpdate |
| Secret values | All three: `issecretvalue()` + `SetAlphaFromBoolean()` + `SetFormattedText()` |
| Update throttling | Cell: 2 buttons per frame indicator queue; ElvUI: eventless GUID-change detection |
| Settings schema | Cell: flat per-layout tables with role/spec auto-switch; clean separation |
| Aura filtering | ElvUI: string priority list parsed at config time, blocklist first |
| Role detection | DandersFrames: delayed FOLLOWER_RECHECK for delve NPC companions |
| Debuff priority | Cell: tiered system (big → raid → normal → dispellable → CC) |
| Z-order | ElvUI: semantic layer offsets via RaisedElement (+0 to +40) |
| Separate party/raid DB | DandersFrames: `GetFrameDB(frame)` returns `db.party` or `db.raid` |
