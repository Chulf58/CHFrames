# Plan: Redesign heal prediction — inline extension of the health bar

## Goal

Restore a working `healPredictBar` StatusBar that visually extends the health bar to the right with a teal tint, showing incoming heals as a colour overshoot beyond the current health fill. The bar must operate entirely on C-side secret numbers — no Lua arithmetic on health values.

---

## Constraints

- No Lua arithmetic on secret numbers (WoW 12.0 throws on `UnitHealth + UnitGetIncomingHeals`).
- `healPredictBar` must be UNDER `healthBar` in z-order so the health fill occludes it correctly.
- `healPredictBar` must be parented to `healthBar` (`bar`), not to `f`, to match the absorb bar pattern.
- Wrap everything in `pcall`; guard `UnitExists` before any unit API call.
- Do not touch frame geometry (200×88px), OFFSETS, buff/debuff icons, or the absorb bars.
- Do not register new events — `UNIT_HEAL_PREDICTION` is already registered and already dispatches to `UpdateHealPrediction`.

---

## Changes

### Change 1: `CH_DPadParty_Frames.lua` — add `healPredictBar` and cache calculator inside `BuildUnitFrame()`

**File:** `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\CH_DPadParty\CH_DPadParty_Frames.lua`

**Where:** Insert the new block immediately after line 117 (`f.healthBar = bar`) and before line 119 (`-- Name text`). The local variable `bar` still refers to `healthBar` at this point in the function.

**What:** Create a StatusBar named `healPredictBar` and cache a `CreateUnitHealPredictionCalculator` instance as `f.healPredictCalc`. Both are created once per frame at construction time.

```lua
-- Heal prediction bar: teal extension of healthBar showing incoming heals.
-- Parented to healthBar so it shares the same coordinate space.
-- Frame level BELOW healthBar so health fill occludes it; only the teal
-- portion to the right of the health fill is visible — that is the incoming heal.
-- SetAllPoints(bar): same origin, size, and position as healthBar.
-- Color: bright teal (0.0, 0.8, 0.6, 0.85).
-- SetMinMaxValues / SetValue accept secret numbers — passed directly to C functions.
-- math.max(1, ...) guards against frame level underflow if bar is at level 0.
local healPredictBar = CreateFrame("StatusBar", nil, bar)
healPredictBar:SetFrameLevel(math.max(1, bar:GetFrameLevel() - 1))
healPredictBar:SetAllPoints(bar)
healPredictBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
healPredictBar:SetStatusBarColor(0.0, 0.8, 0.6, 0.85)
healPredictBar:SetMinMaxValues(0, 1)
healPredictBar:SetValue(0)
f.healPredictBar = healPredictBar

-- Cache the calculator once per frame. CreateUnitHealPredictionCalculator is a
-- persistent C-side object — creating it on every event is wasteful and unnecessary.
f.healPredictCalc = CreateUnitHealPredictionCalculator()
```

**Why:** `f.healPredictBar` does not currently exist on `f` (it was removed in a prior refactor). Without it, the guard `if not f or not f.healPredictBar then return end` on line 372 of `CH_DPadParty.lua` short-circuits `UpdateHealPrediction()` before it does anything useful. Creating the bar here is the prerequisite for Changes 2 and 3.

Frame level `math.max(1, bar:GetFrameLevel() - 1)` guarantees `healthBar` renders on top of `healPredictBar` and prevents underflow if `bar` is ever at level 0. The absorb bars use `bar:GetFrameLevel()` (same level as healthBar); `healPredictBar` must be one level lower so health fill occludes it.

Caching the calculator as `f.healPredictCalc` at construction time avoids calling `CreateUnitHealPredictionCalculator()` on every `UNIT_HEAL_PREDICTION` event (which can fire frequently in combat). The object is reused across all subsequent updates.

---

### Change 2: `CH_DPadParty.lua` — switch `healthBar` to raw HP range in `UpdateFrame()`

**File:** `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\CH_DPadParty\CH_DPadParty.lua`

**Where:** Lines 184–198 — the `do` block inside `UpdateFrame()` that sets `healthBar` min/max and value.

**What:** Replace the normalised 0–100 range (driven by `UnitHealthPercent`) with a raw HP range `(0, UnitHealthMax(unit))` driven by `UnitHealth(unit)`. Both `UnitHealthMax` and `UnitHealth` return secret numbers, which are safe to pass directly to `SetMinMaxValues`/`SetValue` (C functions). `UnitHealthPercent` is still needed for the `hpText` FontString display — that usage is unchanged.

Replace the existing `do` block:

```lua
        local hpPct = f._lastHpPct or 100
        do
            local ok, raw = pcall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
            if ok and raw then
                f.healthBar:SetMinMaxValues(0, 100)
                f.healthBar:SetValue(raw)   -- C function: accepts secret numbers
                local floorOk, pct = pcall(math.floor, raw)
                if floorOk then
                    f._lastHpPct = pct
                    hpPct = pct
                end
            else
                -- Fallback for when UnitHealthPercent is unavailable
                f.healthBar:SetMinMaxValues(0, 100)
                f.healthBar:SetValue(hpPct)
            end
        end
```

with:

```lua
        local hpPct = f._lastHpPct or 100
        do
            -- Raw HP range so healPredictBar can share the same range.
            -- UnitHealthMax / UnitHealth are secret numbers; pass to C functions only.
            local maxOk, maxHP = pcall(UnitHealthMax, unit)
            local hpOk,  hp    = pcall(UnitHealth, unit)
            if maxOk and maxHP and hpOk and hp then
                f.healthBar:SetMinMaxValues(0, maxHP)
                f.healthBar:SetValue(hp)
            else
                -- Taint/unavailability fallback: raw HP pcall failed this cycle.
                -- Use cached percent so the bar always receives a SetValue call.
                f.healthBar:SetMinMaxValues(0, 100)
                f.healthBar:SetValue(f._lastHpPct or 0)
            end
            -- UnitHealthPercent is still needed for the human-readable hpText display.
            local pctOk, raw = pcall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
            if pctOk and raw then
                local floorOk, pct = pcall(math.floor, raw)
                if floorOk then
                    f._lastHpPct = pct
                    hpPct = pct
                end
            end
        end
```

**Why:** `healthBar` and `healPredictBar` use `SetAllPoints(bar)` — identical pixel geometry. For the visual mechanic (teal fill extends health fill to the right) to work, both bars must share the same min/max range. The prior plan had `healthBar` on a 0–100 range and `healPredictBar` on a `(0, UnitHealthMax)` range — a mismatch that would break the fill length correspondence. Switching both to the same raw HP range `(0, UnitHealthMax)` eliminates the mismatch. `UnitHealthPercent` is retained solely for the `hpText` percentage display on line 211.

---

### Change 3: `CH_DPadParty.lua` — replace dead `UpdateHealPrediction()` body with real implementation

**File:** `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\CH_DPadParty\CH_DPadParty.lua`

**Where:** Lines 369–387 (the entire `UpdateHealPrediction` function body as it exists after the prior refactor).

**What:** Replace the body of `UpdateHealPrediction` with a working implementation. Use the cached `f.healPredictCalc` (created in Change 1) instead of calling `CreateUnitHealPredictionCalculator()` on every event. Set both bars to the same raw HP range `(0, UnitHealthMax(unit))`. Keep the function signature (`function CHDPadParty.UpdateHealPrediction(unit)`) and the leading test-mode guard unchanged.

Delete lines 372–387 (from `if not f or not f.healPredictBar then return end` through the closing `end`) and replace with:

```lua
    local f = CHDPadParty.frames[unit]
    if not f or not f.healPredictBar then return end

    local ok, err = pcall(function()
        if not UnitExists(unit) then
            f.healPredictBar:SetMinMaxValues(0, 1)
            f.healPredictBar:SetValue(0)
            return
        end

        -- Primary path: use the cached calculator (created once in BuildUnitFrame).
        -- UnitGetDetailedHealPrediction populates it with health + incoming heal data on
        -- the C side. calc:GetPredictedHealth() returns current health + capped incoming
        -- heals as a secret number on the same raw HP scale as UnitHealthMax.
        -- No Lua arithmetic on secret numbers anywhere in this path.
        local calcOk, calcErr = pcall(function()
            local calc = f.healPredictCalc
            UnitGetDetailedHealPrediction(unit, nil, calc)
            -- GetPredictedHealth returns a secret number in the same raw HP range as
            -- UnitHealthMax — safe to pass directly to SetValue.
            -- (Exact method name must be verified at runtime — see Open Questions.)
            local maxOk, maxHP = pcall(UnitHealthMax, unit)
            if maxOk and maxHP then
                f.healPredictBar:SetMinMaxValues(0, maxHP)
                f.healPredictBar:SetValue(calc:GetPredictedHealth())
            end
        end)

        -- Fallback: if calculator API is absent or throws, hide the bar silently.
        -- Do NOT attempt Lua arithmetic (UnitHealth + UnitGetIncomingHeals) as fallback —
        -- that throws "attempt to perform arithmetic on a secret number" in WoW 12.0.
        if not calcOk then
            f.healPredictBar:SetMinMaxValues(0, 1)
            f.healPredictBar:SetValue(0)
        end
    end)
    if not ok then
        print("|cffff4444CH_DPadParty|r UpdateHealPrediction(" .. unit .. "): " .. tostring(err))
    end
```

**Why:** The existing body (lines 372–387) is dead code because `f.healPredictBar` never exists after the prior refactor removed it. Now that Change 1 creates `healPredictBar`, this guard passes and the implementation runs. The old body also passed `UnitGetIncomingHeals` (raw incoming amount) directly as the bar value — functionally wrong because the teal bar must represent `current HP + incoming`, not just `incoming`, for the visual mechanic to work. The calculator API produces the correct combined value on the C side with no Lua arithmetic.

Using the cached `f.healPredictCalc` rather than calling `CreateUnitHealPredictionCalculator()` on every event avoids unnecessary object allocation in a frequently-fired combat event handler.

---

### Change 4: `CH_DPadParty.lua` — set a fake `healPredictBar` value in `ApplyTestMode()`

**File:** `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\CH_DPadParty\CH_DPadParty.lua`

**Where:** Inside `ApplyTestMode()`, in the `else` branch (party1–4 slots), after the health bar block (after line 441 `f.healthBar:SetValue(frac * 100)`).

**What:** Add a fake visible value on `healPredictBar` to demonstrate the teal overshoot in test mode. The existing test mode health bar uses a normalised 0–100 range (`SetMinMaxValues(0, 100)`, value = `frac * 100`). The `healPredictBar` must share this same range to produce correct fill geometry. Use 30% of max (value 30) as a fixed fake incoming heal amount, added to the current health fraction to produce a combined fill.

```lua
                -- Heal prediction bar: fake teal overshoot in test mode.
                -- Shares the same 0–100 normalised range as healthBar in test mode.
                -- Value = current health% + fake incoming 30%, capped at 100.
                if f.healPredictBar then
                    local fakePredict = math.min(100, frac * 100 + 30)
                    f.healPredictBar:SetMinMaxValues(0, 100)
                    f.healPredictBar:SetValue(fakePredict)
                end
```

**Why:** Without a fake value, `healPredictBar` stays at 0 in test mode and the teal extension is invisible — providing no visual confirmation that the bar works. The `if f.healPredictBar then` guard ensures this is safe even before Change 1 is applied. Using the same 0–100 range as the test-mode health bar (rather than raw HP values) keeps test mode self-contained and consistent; test mode never calls `UnitHealthMax` because no real unit exists.

**Test-mode-exit transition (range mismatch window):** When test mode is turned off, `healthBar` is reset to the raw HP range by the next `UpdateFrame` call, while `healPredictBar` is still on the 0–100 range it was given in `ApplyTestMode`. This could cause a brief range mismatch until `healPredictBar` is updated. However, there is no separate test-mode-off toggle function — test mode is disabled only at session load via `CHDPadPartyDB.testMode = false` at line 514 of `CH_DPadParty.lua`, immediately followed by `CHDPadParty.Init()` at line 517. `Init()` calls `CHDPadParty.UpdateAll()` at line 144, and `UpdateAll()` (lines 283–289) explicitly calls `CHDPadParty.UpdateHealPrediction(unit)` for every unit slot. This means `healPredictBar` is synchronously updated to the raw HP range in the same `Init()` call that resets `healthBar` — no range mismatch window exists in practice.

---

## Visual Mechanic

`healthBar` fills class-colour from left for current health (raw HP range `(0, UnitHealthMax)`). `healPredictBar` fills teal from left for `health + incoming` over the same `(0, UnitHealthMax)` range but sits one frame level below `healthBar`. The health fill covers the teal fill up to the current health value; only the teal overshoot to the right of the health marker is visible. That overshoot is exactly the incoming heal amount.

---

## Rollback

If any change causes errors, revert in reverse order. Changes 1 and 2 are coupled — Change 2 switches `healthBar` to raw HP range to match `healPredictBar`; reverting one without the other reintroduces the range mismatch.

1. **Revert Change 4** (ApplyTestMode): Delete the `healPredictBar` fake-value block added after the health bar in the party slot loop. No other code is affected.

2. **Revert Change 3** (UpdateHealPrediction): Restore the original lines 372–387:
   ```lua
       local f = CHDPadParty.frames[unit]
       if not f or not f.healPredictBar then return end

       pcall(function()
           if not UnitExists(unit) then
               f.healPredictBar:SetMinMaxValues(0, 1)
               f.healPredictBar:SetValue(0)
               return
           end
           local maxHP   = UnitHealthMax(unit)
           local incoming = UnitGetIncomingHeals(unit) or 0
           f.healPredictBar:SetMinMaxValues(0, maxHP)
           f.healPredictBar:SetValue(incoming)
       end)
   ```
   This restores the dead-guard state (no-op because `f.healPredictBar` is nil after reverting Change 1) — safe regardless of whether Changes 1 and 2 have also been reverted.

3. **Revert Changes 1 and 2 together** (Frames.lua + UpdateFrame): These two must be reverted as a pair.
   - Revert Change 1 (Frames.lua): Delete the entire `healPredictBar` block and `f.healPredictCalc` assignment (the 11-line block from `local healPredictBar = CreateFrame` through `f.healPredictCalc = ...`). The guard in `UpdateHealPrediction` will immediately no-op again.
   - Revert Change 2 (UpdateFrame): Restore the original `do` block that uses `UnitHealthPercent` for `SetMinMaxValues(0, 100)` / `SetValue(raw)`. The exact code to restore is the "old code" block already quoted in the Change 2 section above under "Replace the existing `do` block" — do not write a new snippet independently. Do not revert Change 2 without also reverting Change 1 — leaving `healPredictBar` on a raw HP range while `healthBar` is back on 0–100 reintroduces the range mismatch.

---

## Open Questions

1. **Exact method name on the calculator object.** The Blizzard source uses `CreateUnitHealPredictionCalculator()` and `UnitGetDetailedHealPrediction(unit, nil, calc)`, but the method to retrieve the combined health+incoming total from `calc` needs confirmation at runtime. Candidates (in priority order):
   - `calc:GetPredictedHealth()` — most semantically correct name based on Blizzard naming conventions
   - `calc:GetTotalHealedHealth()` — alternative seen in some community documentation
   - `calc:GetValue()` — generic fallback if the above are absent

   The `pcall` wrapper around the primary path means a wrong method name will fail silently (bar shows 0) rather than throwing a visible error. Add a temporary `print` during development to confirm the method resolves: `print(type(calc.GetPredictedHealth), type(calc.GetTotalHealedHealth))`.

   The raw HP range assumption in Change 3 rests on `GetPredictedHealth` returning a value on the same scale as `UnitHealthMax`. If the method instead returns a normalised fraction or a percentage, `SetMinMaxValues` would need adjustment. Confirm the scale alongside the method name.

2. **Whether `CreateUnitHealPredictionCalculator` exists in retail TWW / 12.0.** This API shipped in Dragonflight for the new health prediction system. If it is absent in the running build, `pcall` will catch the "attempt to call a nil value" error and the bar will remain at 0 (no teal extension shown). No crash or taint results. Verify by running `/run print(type(CreateUnitHealPredictionCalculator))` in-game; expect `"function"`. Also confirm `f.healPredictCalc` is non-nil after frame construction: `/run print(CHDPadParty.frames.party1 and type(CHDPadParty.frames.party1.healPredictCalc))`.

3. **Frame level arithmetic at runtime.** `healPredictBar` uses `math.max(1, bar:GetFrameLevel() - 1)`. The `math.max(1, ...)` guard prevents underflow if `bar` is ever at level 0, though in practice `f` inherits a non-zero frame level from UIParent's tree and `bar` (parented to `f`) will always be at least level 1. Confirm by printing `bar:GetFrameLevel()` after frame construction if unexpected z-order behaviour is observed.
