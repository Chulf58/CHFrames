# Plan: Party Priority Engine

## Request

Add a priority evaluation engine to CHFrames that classifies each unit frame into one of six urgency levels and applies a single dominant visual signal per frame.

## Affected Files

- `CHFrames.lua` — all new logic lives here: new constants (`LETHAL_MECHANIC_SPELLS`, `CRITICAL_HP_THRESHOLD`), three new public functions (`EvaluatePriority`, `ApplyPrioritySignal`, `UpdatePriority`), and modifications to `UpdateBorder`, `UpdateAll`, and specific event handlers
- `CHFrames_Frames.lua` — `BuildUnitFrame`: initialize `f._priorityLevel = 6` and `f._priorityOwnsBorder = false` on the frame table so these fields are never nil on first read

## Reuse Opportunities

- `f._lastHpPct` — read directly in `EvaluatePriority` for CRITICAL_HP comparison; already a plain integer, no secret-number concern
- `f._dispelColor` — read directly in `EvaluatePriority` for DISPELLABLE signal; already set by `UpdateAuras` before `UpdatePriority` is called
- `issecretvalue()` pattern (G-076) — used in `EvaluatePriority` to detect heal absorb presence (`UnitGetTotalHealAbsorbs`) for the INCOMING_DAMAGE signal; same pattern as absorb detection in `UpdateAbsorbs`
- `DEFENSIVE_EXTERNALS` table structure — `LETHAL_MECHANIC_SPELLS` follows the same `[spellID] = true` set pattern
- `f.defIcon` — 30×30 frame parented to `bar` (healthBar), centered on it, frame level `bar:GetFrameLevel() + 2`; reused as the icon display slot for the LETHAL_MECHANIC signal; no size or position change needed
- `pcall` + cache pattern — `EvaluatePriority` follows the same guard structure as all other update functions
- `isDispellable()` (local function in UpdateAuras) — `EvaluatePriority` reads `f._dispelColor` instead of re-evaluating; no need to call the inner function directly

## Steps

1. Add `CRITICAL_HP_THRESHOLD = 20` constant near the other border/color constants in `CHFrames.lua`

2. Add `LETHAL_MECHANIC_SPELLS` table in `CHFrames.lua` using the same `[spellID] = true` set structure as `DEFENSIVE_EXTERNALS`; populate with an initial set of spell IDs representing <2s-window mechanics (exact IDs TBD — see Open Questions)

3. Initialize `f._priorityLevel = 6` and `f._priorityOwnsBorder = false` in `BuildUnitFrame` (`CHFrames_Frames.lua`) immediately after the frame table is created, so these fields are never nil when `UpdateBorder` or `EvaluatePriority` first reads them

4. Implement `CHFrames.EvaluatePriority(unit)` in `CHFrames.lua`:
   - Guard: `if not unit or not CHFrames.frames[unit] then return 6, {} end`
   - Guard: `if CHFramesDB and CHFramesDB.testMode and unit ~= "player" then return 6, {} end` (G-067)
   - Read `f = CHFrames.frames[unit]`
   - DEAD check (level 1): covers disconnected (`not UnitIsConnected`), ghost (G-058: check before dead), dead, and AFK — return early with `{color=grey}`. This must include disconnected and AFK to prevent CRITICAL_HP or DISPELLABLE signals firing on a disconnected unit whose HP cache shows 0%
   - LETHAL_MECHANIC check (level 2): scan harmful auras slot-by-slot with early exit; before each table lookup, guard with `if issecretvalue(aura.spellId) then -- skip end` (G-077: table index is secret if `secretAurasForced` CVar is active); return `{icon=aura.icon}` on match
   - DISPELLABLE check (level 3): if `f._dispelColor` is non-nil, return `{color=f._dispelColor}`
   - CRITICAL_HP check (level 4): if `f._lastHpPct` is non-nil and `f._lastHpPct <= CRITICAL_HP_THRESHOLD`, return `{color=orange}`
   - INCOMING_DAMAGE check (level 5): detect heal absorb presence via `pcall(UnitGetTotalHealAbsorbs, unit)` + `issecretvalue(raw)` (G-076); return `{color=dark_red}` if present
   - Default: return `6, {}`
   - Wrap entire body in `pcall`; print error on failure; return `6, {}` on error

5. Implement `CHFrames.ApplyPrioritySignal(f, priorityLevel, payload)` in `CHFrames.lua`:
   - Level 1 (DEAD): set healthBar vertex color grey `(0.4, 0.4, 0.4)`; overlay already handles text
   - Level 2 (LETHAL_MECHANIC): set backdrop bg color to full red `(0.5, 0.0, 0.0, 0.9)`; show `f.defIcon` with `payload.icon` texture; set `f._priorityOwnsBorder = false` (border not claimed at this level)
   - Level 3 (DISPELLABLE): set backdrop border color to `payload.color` at full alpha 1.0 (same API as `UpdateBorder` — `SetBackdropBorderColor`); do not change bg; set `f._priorityOwnsBorder = true`
   - Level 4 (CRITICAL_HP): set backdrop bg color to orange-red `(0.5, 0.2, 0.0, 0.85)`; set `f._priorityOwnsBorder = false`
   - Level 5 (INCOMING_DAMAGE): set backdrop bg color to dark red `(0.35, 0.0, 0.0, 0.85)`; set `f._priorityOwnsBorder = false`
   - Level 6 (NORMAL): restore healthBar vertex color to white `(1, 1, 1)` — `SetVertexColor(1,1,1)` multiplies by the texture at 1× so the class color set by `SetStatusBarColor` (applied in `UpdateFrame`) shows through unmodified; restore backdrop bg to default `(0.05, 0.05, 0.05, 0.85)`; hide `f.defIcon` unless `UpdateDefensive` has a real defensive icon to show (see Open Questions); call `UpdateBorder(unit)` to restore border; set `f._priorityOwnsBorder = false`
   - Do not touch `f.overlay`, `f.secureBtn`, or any absorb bars
   - Note on `SetBackdropColor` taint: assumed safe — `SetBackdropBorderColor` is already used in `UpdateBorder` with no restriction; `SetBackdropColor` on a BackdropTemplate frame is expected to behave identically. Flag if in-game testing shows otherwise (no G-code assigned yet)

6. Implement `CHFrames.UpdatePriority(unit)` in `CHFrames.lua`:
   - Guard: same test-mode and unit-lookup guards as all other Update functions
   - Call `EvaluatePriority(unit)` → `priorityLevel, payload`
   - Store result: `f._priorityLevel = priorityLevel`
   - Call `ApplyPrioritySignal(f, priorityLevel, payload)`
   - Wrap in `pcall`

7. Modify `UpdateBorder(unit)` in `CHFrames.lua`: add guard at the top — `if f._priorityOwnsBorder then return end` — so the priority engine retains ownership of the border color when DISPELLABLE (level 3) is active. Use `f._priorityOwnsBorder` (set by `ApplyPrioritySignal`) rather than checking `_priorityLevel` directly. This is necessary because `UpdateBorder` is called directly from `UNIT_THREAT_SITUATION_UPDATE` and `PLAYER_TARGET_CHANGED` event handlers, not through `UpdatePriority`, so `_priorityLevel` may be stale at the moment `UpdateBorder` runs

8. Modify `UpdateAll()` in `CHFrames.lua`: after the existing per-unit loop, add `CHFrames.UpdatePriority(unit)` as the final call for each unit in `UNIT_SLOTS`. `UpdateAll` calls `UpdateAuras` (which sets `f._dispelColor`) and `UpdateDefensive` before reaching this point, ensuring `EvaluatePriority` reads fresh data. Do NOT add tail calls to `UpdatePriority` inside `UpdateFrame` or `UpdateAuras` individually — `UpdateFrame` internally calls `UpdateAuras`, so a tail call in each would produce two or three `UpdatePriority` invocations per `UpdateAll` iteration

9. Modify event handlers in `CHFrames.lua` — add `CHFrames.UpdatePriority(unit)` at the end of each handler block that changes a priority signal input, so `_priorityLevel` and `_priorityOwnsBorder` are always current:
   - `UNIT_HEALTH` handler: add `CHFrames.UpdatePriority(arg1)` after `UpdateFrame` (CRITICAL_HP input: `_lastHpPct` is updated inside `UpdateFrame`)
   - `UNIT_AURA` handler: add `CHFrames.UpdatePriority(arg1)` after the existing `UpdateAtonement` call (DISPELLABLE input: `_dispelColor` is set by `UpdateAuras`; LETHAL_MECHANIC input: aura set changed; DEAD input: AFK changes trigger `PLAYER_FLAGS_CHANGED` not `UNIT_AURA` but defensive re-evaluation needed here)
   - `UNIT_ABSORB_AMOUNT_CHANGED` handler: add `CHFrames.UpdatePriority(arg1)` after `UpdateFrame` (INCOMING_DAMAGE input: absorb state changed)
   - `UNIT_HEAL_ABSORB_AMOUNT_CHANGED` handler: add `CHFrames.UpdatePriority(arg1)` after `UpdateAbsorbs` (INCOMING_DAMAGE input: heal absorb state changed)
   - `PLAYER_FLAGS_CHANGED` handler: add `CHFrames.UpdatePriority(arg1)` after `UpdateFrame` (DEAD input: AFK, dead, ghost, disconnect transitions)
   - `UNIT_THREAT_SITUATION_UPDATE` handler: `UpdateBorder` already runs here; `UpdatePriority` is not needed unless threat itself becomes a signal — skip for now
   - `PLAYER_TARGET_CHANGED` handler: calls `UpdateBorder` for all slots; because `_priorityOwnsBorder` guards `UpdateBorder`, no `UpdatePriority` call is required here — existing behavior is preserved

## Frame / Layout Changes

- `f.defIcon` — no size or position change; remains 30×30, parented to `bar` (healthBar), centered on it, frame level `bar:GetFrameLevel() + 2` (confirmed from `CHFrames_Frames.lua` line 428); reused as signal icon slot for LETHAL_MECHANIC (level 2); shown/hidden by `ApplyPrioritySignal` and `UpdateDefensive` independently (see Open Questions)
- Backdrop bg color override — applied via `f:SetBackdropColor(r, g, b, a)`; restored to `(0.05, 0.05, 0.05, 0.85)` at NORMAL (level 6)
- Backdrop border color override for DISPELLABLE — applied via `f:SetBackdropBorderColor(r, g, b, 1.0)`; same API already used by `UpdateBorder`; restored at NORMAL via `UpdateBorder(unit)` call inside `ApplyPrioritySignal`
- HealthBar vertex color — set grey at DEAD via `f.healthBar:SetVertexColor(0.4, 0.4, 0.4)`; restored to white at NORMAL via `f.healthBar:SetVertexColor(1, 1, 1)`. Restoring to `(1,1,1)` multiplies the texture fill at 1× (no tint), so the class color applied by `SetStatusBarColor` in `UpdateFrame` shows through correctly. These are independent: `SetStatusBarColor` sets the fill color; `SetVertexColor` multiplies it. No size or position change

## Call Graph (post-changes)

```
UpdateAll()
  for each unit:
    UpdateAbsorbs(unit)      -- populates _hasAbsorb
    UpdateFrame(unit)        -- internally calls UpdateAuras → sets _dispelColor
    UpdateHealPrediction(unit)
    UpdatePower(unit)
    UpdateAuras(unit)        -- sets _dispelColor (second call; idempotent)
    UpdateMissingBuff(unit)
    UpdateRange(unit)
    UpdateRez(unit)
    UpdateVehicle(unit)
    UpdateRaidMarker(unit)
    UpdateDefensive(unit)
    UpdateAtonement(unit)
    UpdatePriority(unit)     -- ONCE, at the tail; reads fresh _dispelColor/_lastHpPct

UNIT_HEALTH → UpdateFrame(arg1) → UpdatePriority(arg1)
UNIT_AURA → UpdateAuras + UpdateMissingBuff + UpdateDefensive + UpdateAtonement → UpdatePriority(arg1)
UNIT_ABSORB_AMOUNT_CHANGED → UpdateAbsorbs + UpdateFrame → UpdatePriority(arg1)
UNIT_HEAL_ABSORB_AMOUNT_CHANGED → UpdateAbsorbs → UpdatePriority(arg1)
PLAYER_FLAGS_CHANGED → UpdateFrame → UpdatePriority(arg1)
UNIT_THREAT_SITUATION_UPDATE → UpdateBorder (guarded by _priorityOwnsBorder)
PLAYER_TARGET_CHANGED → UpdateBorder for all slots (guarded by _priorityOwnsBorder per unit)
```

## Out of Scope

- `f.defIcon` position adjustment to avoid overlap with hpText (noted as acceptable for now; follow-up task)
- Any new SavedVariables keys for priority settings
- Any UI to configure priority thresholds or which signals are enabled
- Populating `LETHAL_MECHANIC_SPELLS` with a comprehensive spell list (initial stub only; separate research task)
- CC tracker integration as a priority signal (tracked separately as task #13)
- Raid frame support (priority engine operates on `UNIT_SLOTS` party frames only)

## Open Questions

1. **`C_UnitAuras.GetAuraDataBySpellID` availability** — confirm this function exists in WoW 12.0 retail and its exact signature. If absent, the LETHAL_MECHANIC scan must use slot-by-slot iteration with early exit (current plan already specifies slot-by-slot). Fallback must not perform a full second 40-slot scan on top of the existing UpdateAuras scan.

2. **`f.defIcon` ownership conflict between `UpdateDefensive` and `ApplyPrioritySignal`** — both functions may want to show/hide `f.defIcon`. When priorityLevel is 2 (LETHAL_MECHANIC), `ApplyPrioritySignal` shows `f.defIcon` with the lethal mechanic icon. When priorityLevel is 6 (NORMAL), `ApplyPrioritySignal` hides it — but `UpdateDefensive` may need it visible for a defensive CD. Clarify ownership: either `ApplyPrioritySignal` at NORMAL calls `UpdateDefensive(unit)` to re-evaluate, or `UpdateDefensive` always runs after `ApplyPrioritySignal` and only hides when both conditions are absent.

3. **`LETHAL_MECHANIC_SPELLS` initial spell ID list** — which specific spell IDs qualify as <2s window mechanics? Needs a separate research pass. The constant should be added as an empty table stub in this implementation; content filled separately.
