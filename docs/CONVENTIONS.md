# CHFrames — Coding Conventions

## Namespace

Global table: `CHFrames`. All public functions are on this table.
```lua
CHFrames = CHFrames or {}
function CHFrames.MyFunction() ... end
```

Local helpers (used only within one file) are `local function`:
```lua
local function formatHP(pct) ... end
```

## Naming

| Thing | Convention | Example |
|---|---|---|
| Addon table | `CHFrames` | `CHFrames.Init()` |
| Frame globals | `CHFrames<Description>` | `CHFramesRoot`, `CHFramesFrame_party1` |
| Secure buttons | `CHFramesSecure_<unit>` | `CHFramesSecure_party1` |
| DB | `CHFramesDB` | SavedVariables key |
| Unit frame fields | Short descriptive names on `f` | `f.healthBar`, `f.nameText`, `f.buffIcons` |
| Constants | `ALL_CAPS` | `UNIT_SLOTS`, `UNIT_LOOKUP`, `OFFSETS` |

## Error Handling

All non-trivial frame update logic must be wrapped in `pcall`:
```lua
local ok, err = pcall(function()
    -- update work here
end)
if not ok then
    print("|cffff4444CHFrames|r FunctionName(" .. unit .. "): " .. tostring(err))
end
```

Inner API calls that may fail (especially WoW 12.0 secret-number APIs) get their own pcall:
```lua
local ok, raw = pcall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
if ok and raw then ... end
```

## Secret Number Pattern

Never do Lua arithmetic on WoW 12.0 secret numbers. Pass directly to C:
```lua
-- CORRECT
bar:SetMinMaxValues(0, UnitHealthMax(unit))
bar:SetValue(UnitGetTotalAbsorbs(unit) or 0)

-- WRONG — throws in combat
local pct = UnitHealth(unit) / UnitHealthMax(unit) * 100
```

For values that need display (HP%), use `UnitHealthPercent` which returns a plain float:
```lua
local ok, raw = pcall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
```

Cache the last good value for fallback:
```lua
local hpPct = f._lastHpPct or 100
-- ... update hpPct if pcall succeeds, then use hpPct for display
```

## SavedVariables Defaults

Always initialize with `if key == nil` — never `or` for booleans:
```lua
-- CORRECT
if CHFramesDB.locked == nil then CHFramesDB.locked = true end

-- WRONG — resets false to true
CHFramesDB.locked = CHFramesDB.locked or true
```

## G-Code Comments

When a non-obvious WoW API constraint requires a specific pattern, mark it with a `G-NNN` comment explaining why:
```lua
-- G-057: SetMinMaxValues BEFORE SetValue; bar silently clamps to 0 otherwise
bar:SetMinMaxValues(0, 100)
bar:SetValue(pct)
```

New gotchas discovered during development should be added to `docs/GOTCHAS.md` with a matching `G-NNN` tag.

## Frame Construction Rules

- `BuildUnitFrame()` creates frames only — no data, no events, no logic
- Never call `Show()` / `Hide()` on `SecureUnitButtonTemplate` frames from non-secure code
- Always `ClearAllPoints()` before `SetPoint()` when restoring a saved position
- Parent absorb/predict overlay bars to `healthBar`, not `f`, so OVERLAY text renders above them

## UI Style

- Outer frame backdrop: `bgFile = "Interface\\Tooltips\\UI-Tooltip-Background"`, bg color `(0.05, 0.05, 0.05, 0.85)`, border `(0.3, 0.3, 0.3, 1)`
- Dispel border colors: Magic=blue, Curse=purple, Poison=green, Disease=brown (see `DISPEL_COLORS` in CHFrames.lua)
- Health bar colors from `RAID_CLASS_COLORS[classFile]`, white fallback for disconnected
- Overlay text colors: dead/offline = `(0.8, 0.1, 0.1, 1)`
- Font: `GameFontNormalSmall` throughout

## Test Mode Rules

- `CHFramesDB.testMode` is session-only — always `false` on ADDON_LOADED
- In test mode: party1–4 show fake data, player shows real data
- All live update functions must guard: `if CHFramesDB and CHFramesDB.testMode and unit ~= "player" then return end`
- `UNIT_AURA` event handler skips entirely when testMode is true
