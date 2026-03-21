# PLAN_ABSORB.md — Absorb% in HP Text

**Date drafted:** 2026-03-21
**Status:** Ready for implementation

---

## Overview

HP text shows "74%" normally. When absorbs are present: "74% +13%" where "+13%"
is gold-colored via WoW inline color tag. Single FontString approach — no extra frames.

---

## Files Changed

| File | Change |
|---|---|
| `CH_DPadParty_Frames.lua` | Initialize `f._absorbPct = 0` after hpText block |
| `CH_DPadParty.lua` | UpdateAbsorbs: cache absorb%; UpdateFrame: compose hpText; ApplyTestMode: preview |

---

## Change 1 — Frames.lua: initialize f._absorbPct

After `f.hpText = hpText`.

### Old

    f.hpText = hpText

### New

    f.hpText = hpText
    -- Absorb percent cache (plain integer, 0 = no absorb).
    -- Updated by UpdateAbsorbs; read by UpdateFrame to compose hpText suffix.
    f._absorbPct = 0

---

## Change 2 — CH_DPadParty.lua: UpdateAbsorbs UnitExists branch

Add `f._absorbPct = 0` when unit does not exist.

### Old

        if not UnitExists(unit) then
            if f.absorbBar     then f.absorbBar:SetMinMaxValues(0, 1);     f.absorbBar:SetValue(0)     end
            if f.healAbsorbBar then f.healAbsorbBar:SetMinMaxValues(0, 1); f.healAbsorbBar:SetValue(0) end
            return
        end

### New

        if not UnitExists(unit) then
            if f.absorbBar     then f.absorbBar:SetMinMaxValues(0, 1);     f.absorbBar:SetValue(0)     end
            if f.healAbsorbBar then f.healAbsorbBar:SetMinMaxValues(0, 1); f.healAbsorbBar:SetValue(0) end
            f._absorbPct = 0
            return
        end

---

## Change 3 — CH_DPadParty.lua: UpdateAbsorbs damage absorb block

Add zero-clear when absorb drops to 0, and pcall-guarded absorb% cache after SetValue.
Both `absorb` and `UnitHealthMax` are obtained inside the inner pcall to avoid secret-number
taint propagating from bare Lua arithmetic.

### Old

        if f.absorbBar then
            local absorb = UnitGetTotalAbsorbs(unit) or 0
            f.absorbBar:SetMinMaxValues(0, maxHP)
            f.absorbBar:SetValue(absorb)
        end

### New

        if f.absorbBar then
            local absorb = UnitGetTotalAbsorbs(unit) or 0
            f.absorbBar:SetMinMaxValues(0, maxHP)
            f.absorbBar:SetValue(absorb)
            -- Zero-clear: if shield has dropped, clear suffix immediately.
            if absorb == 0 then
                f._absorbPct = 0
            else
                -- Inner pcall: both absorb and UnitHealthMax inside to prevent
                -- secret-number taint from bare arithmetic in combat.
                -- On failure: cache retains previous value (stale but safe).
                local pctOk, pct = pcall(function()
                    return math.floor(UnitGetTotalAbsorbs(unit) / UnitHealthMax(unit) * 100)
                end)
                if pctOk then
                    f._absorbPct = pct
                end
            end
        end

---

## Change 4 — CH_DPadParty.lua: UpdateFrame hpText

### Old

        f.hpText:SetText(hpPct .. "%")

### New

        -- Append gold absorb% suffix when shields are present.
        -- |cffFFD900 = gold. f._absorbPct cached by UpdateAbsorbs (0 = none).
        if f._absorbPct and f._absorbPct > 0 then
            f.hpText:SetText(hpPct .. "% |cffFFD900+" .. f._absorbPct .. "%|r")
        else
            f.hpText:SetText(hpPct .. "%")
        end

---

## Change 5 — CH_DPadParty.lua: ApplyTestMode hpText

### Old

                f.hpText:SetText(math.floor(frac * 100) .. "%")

### New

                local fakePct = math.floor(frac * 100)
                if idx == 1 then
                    f.hpText:SetText(fakePct .. "% |cffFFD900+18%|r")
                else
                    f.hpText:SetText(fakePct .. "%")
                end

---

## Edge Cases

| Scenario | Behavior |
|---|---|
| No absorb | absorb=0, pct=0, _absorbPct=0, suffix hidden |
| maxHP=0 (fresh unit) | division by zero caught by pcall; cache unchanged |
| Combat taint | pcall catches; stale cache shown until next OOC event |
| Overabsorb (>100%) | Shows +130% etc. Valid |
| f._absorbPct nil (old frame) | nil-guard in UpdateFrame handles safely |
