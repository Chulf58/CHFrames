# CH_DPadParty — Dispel Priority + Debuff Type Icons

**Date drafted:** 2026-03-21
**Status:** Ready for implementation (rev 2 — post code-review fixes)

---

## Overview

Four coordinated changes delivered as one PR:

1. **Debuff type corner badge** — 10x10 colored texture on each debuff icon slot (Magic/Curse/Poison/Disease).
2. **Class-aware dispel border** — f._dispelColor only fires when the local player can actually dispel that type.
3. **Dispel-first sort** — dispellable debuffs always fill slots 1-3 before non-dispellable ones.
4. **Private aura nil fix** — replace `break` on nil with skip-and-continue + consecutive-nil termination.

---

## Files Changed

| File | Nature of change |
|---|---|
| `CH_DPadParty_Frames.lua` | Add `icon.typeOverlay` texture to each debuff icon slot in `BuildUnitFrame` |
| `CH_DPadParty.lua` | Add constants + scratch tables + `isDispellable` + `UpdateDispelTypes`; rewrite debuff scan in `UpdateAuras`; fix test mode; hook events |

---

## Change 1 — CH_DPadParty_Frames.lua: add icon.typeOverlay

Inside the debuff icon construction loop, after `icon.timer = timer` and before `icon:Hide()`.

### Old (end of debuff loop)

        icon.timer = timer
        icon:Hide()
        f.debuffIcons[i] = icon

### New

        icon.timer = timer
        -- G-071: debuff type badge — 10x10 corner overlay, BOTTOMRIGHT, OVERLAY sub-layer 1.
        -- Texture: Interface\Buttons\UI-Debuff-Overlays, texcoords isolate type-color swatch.
        -- Colored at runtime via SetVertexColor from DISPEL_COLORS table.
        local typeOverlay = icon:CreateTexture(nil, "OVERLAY", nil, 1)
        typeOverlay:SetSize(10, 10)
        typeOverlay:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
        typeOverlay:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
        typeOverlay:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
        typeOverlay:Hide()
        icon.typeOverlay = typeOverlay
        icon:Hide()
        f.debuffIcons[i] = icon

---

## Change 2 — CH_DPadParty.lua: module-level declarations (A1)

Insert after BORDER_AGGRO line (after line 48), before POWER_COLORS.

### New (pure addition)

    -- G-072: dispel capability table, keyed by classFile string (uppercase).
    -- Values are sets (table with string keys = true) of dispel type names.
    -- Warlock: Magic self-only in retail — no party dispel capability.
    -- Evoker: Cauterizing Flame dispels Magic + Bleed; Bleed has no DISPEL_COLORS entry (harmless).
    local DISPEL_BY_CLASS = {
        PRIEST  = { Magic = true, Disease = true },
        DRUID   = { Magic = true, Curse = true, Poison = true },
        PALADIN = { Magic = true, Poison = true, Disease = true },
        SHAMAN  = { Magic = true, Curse = true, Poison = true },
        MONK    = { Magic = true, Poison = true, Disease = true },
        MAGE    = { Curse = true },
        EVOKER  = { Magic = true },
    }

    -- Populated by UpdateDispelTypes(); nil = not yet detected (treat as empty).
    local _playerDispelTypes = nil

    -- G-073: module-level scratch tables — wiped at the start of each debuff scan
    -- to avoid per-call allocation pressure. Never read outside UpdateAuras.
    local _debuffList = {}
    local _debuffSorted = {}

---

## Change 3 — CH_DPadParty.lua: isDispellable + UpdateDispelTypes (A2)

Insert after UpdateRangeSpell() ends (after line 128), before the OFFSETS table.

### New (pure addition)

    -- G-072: isDispellable — file-local; closes only over _playerDispelTypes.
    -- Hoisted here (not inside UpdateAuras) so it is allocated once, not per-call.
    local function isDispellable(aura)
        if not _playerDispelTypes then return false end
        local dtype = aura.dispelName or aura.dispelType
        return dtype and _playerDispelTypes[dtype] == true
    end

    ------------------------------------------------------------------------
    -- UpdateDispelTypes  (G-072)
    ------------------------------------------------------------------------

    local function UpdateDispelTypes()
        _playerDispelTypes = nil
        local _, classFile = UnitClass("player")
        if classFile then
            _playerDispelTypes = DISPEL_BY_CLASS[classFile] or {}
        end
    end

---

## Change 4 — CH_DPadParty.lua: rewrite UpdateAuras debuff section

Replace the entire debuff block (lines 522-573).

### Old

        -- Debuffs (up to 3 shown) + scan for dispellable debuffs for border highlight
        local dispelColor = nil
        for i = 1, 3 do
            local icon = f.debuffIcons[i]
            local ok2, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HARMFUL")
            if ok2 and aura and aura.icon then
                icon.tex:SetTexture(aura.icon)
                local apps = aura.applications or 0
                if apps > 1 then
                    icon.count:SetText(apps)
                    icon.count:Show()
                else
                    icon.count:Hide()
                end
                -- Cooldown swipe + expiry cache for timer ticker
                local expire = aura.expirationTime
                if icon.cooldown and expire and expire > 0 and aura.duration and aura.duration > 0 then
                    CooldownFrame_Set(icon.cooldown, expire - aura.duration, aura.duration, 1)
                    icon.cooldown:Show()
                elseif icon.cooldown then
                    icon.cooldown:Hide()
                end
                icon._expireTime = (expire and expire > 0) and expire or nil
                icon:Show()
                -- First dispellable type seen wins for the border color
                if not dispelColor and aura.dispelType then
                    dispelColor = DISPEL_COLORS[aura.dispelType]
                end
            else
                icon:Hide()
                icon._expireTime = nil
                if icon.cooldown then icon.cooldown:Hide() end
                if icon.timer then icon.timer:SetText("") end
            end
        end

        -- If no dispellable debuff in first 3 slots, scan remaining (up to 40)
        if not dispelColor then
            for i = 4, 40 do
                local ok2, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HARMFUL")
                if not ok2 or not aura then break end
                if aura.dispelType and DISPEL_COLORS[aura.dispelType] then
                    dispelColor = DISPEL_COLORS[aura.dispelType]
                    break
                end
            end
        end

        -- Store dispel color for UpdateBorder priority chain, then apply border
        f._dispelColor = dispelColor
        CHDPadParty.UpdateBorder(unit)

### New

        -- Debuffs: collect all visible debuffs, sort dispellable ones to front,
        -- then fill the 3 display slots.
        --
        -- G-073: GetAuraDataByIndex returns nil for BOTH empty slots AND private
        -- auras (hidden by server). A single nil does NOT mean the list ended —
        -- stop only after 2 consecutive nils (ok2=true, aura=nil).
        -- pcall failure (ok2=false) is an API error — terminate immediately.
        --
        -- G-074: dispelName is the documented AuraData field. Some builds may use
        -- dispelType instead. Bridge: (aura.dispelName or aura.dispelType).

        wipe(_debuffList)
        wipe(_debuffSorted)
        local consecutiveNils = 0
        for i = 1, 40 do
            local ok2, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HARMFUL")
            if not ok2 then
                break  -- API error — stop scanning immediately
            end
            if aura then
                consecutiveNils = 0
                if aura.icon then
                    _debuffList[#_debuffList + 1] = aura
                end
            else
                -- ok2=true, aura=nil: private aura gap — skip, keep counting
                consecutiveNils = consecutiveNils + 1
                if consecutiveNils >= 2 then break end
            end
        end

        -- Stable dispel-first partition (two-pass: Lua 5.1 sort is not stable).
        for _, aura in ipairs(_debuffList) do
            if isDispellable(aura) then _debuffSorted[#_debuffSorted + 1] = aura end
        end
        for _, aura in ipairs(_debuffList) do
            if not isDispellable(aura) then _debuffSorted[#_debuffSorted + 1] = aura end
        end

        -- Fill display slots 1-3 from sorted list
        local dispelColor = nil
        for i = 1, 3 do
            local icon = f.debuffIcons[i]
            local aura = _debuffSorted[i]
            if aura then
                icon.tex:SetTexture(aura.icon)
                local apps = aura.applications or 0
                if apps > 1 then
                    icon.count:SetText(apps)
                    icon.count:Show()
                else
                    icon.count:Hide()
                end
                local expire = aura.expirationTime
                if icon.cooldown and expire and expire > 0 and aura.duration and aura.duration > 0 then
                    CooldownFrame_Set(icon.cooldown, expire - aura.duration, aura.duration, 1)
                    icon.cooldown:Show()
                elseif icon.cooldown then
                    icon.cooldown:Hide()
                end
                icon._expireTime = (expire and expire > 0) and expire or nil
                -- Type badge (G-071): show colored overlay for any debuff with a type
                local dtype = aura.dispelName or aura.dispelType
                local dc = dtype and DISPEL_COLORS[dtype]
                if dc and icon.typeOverlay then
                    icon.typeOverlay:SetVertexColor(dc.r, dc.g, dc.b)
                    icon.typeOverlay:Show()
                elseif icon.typeOverlay then
                    icon.typeOverlay:Hide()
                end
                icon:Show()
                -- Dispel border: first slot the player can actually dispel
                if not dispelColor and isDispellable(aura) and dc then
                    dispelColor = dc
                end
            else
                icon:Hide()
                icon._expireTime = nil
                if icon.cooldown then icon.cooldown:Hide() end
                if icon.timer then icon.timer:SetText("") end
                if icon.typeOverlay then icon.typeOverlay:Hide() end
            end
        end

        -- Scan overflow slots for a dispellable debuff that didn't fit (border only)
        if not dispelColor then
            for i = 4, #_debuffSorted do
                if isDispellable(_debuffSorted[i]) then
                    local dtype = _debuffSorted[i].dispelName or _debuffSorted[i].dispelType
                    local dc = dtype and DISPEL_COLORS[dtype]
                    if dc then dispelColor = dc; break end
                end
            end
        end

        f._dispelColor = dispelColor
        CHDPadParty.UpdateBorder(unit)

---

## Change 5 — CH_DPadParty.lua: test mode typeOverlay fix

In ApplyTestMode, inside the fake debuff icons loop.

### Old

                for i = 1, 3 do
                    local icon = f.debuffIcons[i]
                    icon.tex:SetTexture(FAKE_DEBUFF_ICONS[i])
                    icon.count:Hide()
                    icon:Show()
                end

### New

                for i = 1, 3 do
                    local icon = f.debuffIcons[i]
                    icon.tex:SetTexture(FAKE_DEBUFF_ICONS[i])
                    icon.count:Hide()
                    -- G-071: hide typeOverlay so fake icons don't show stale badges
                    if icon.typeOverlay then icon.typeOverlay:Hide() end
                    icon:Show()
                end

---

## Change 6 — CH_DPadParty.lua: event handler hooks

### 6a: PLAYER_ENTERING_WORLD — add UpdateDispelTypes() after UpdateRangeSpell()

        UpdateRangeSpell()
        -- G-072: detect which debuff types the player can dispel.
        UpdateDispelTypes()

### 6b: PLAYER_TALENT_UPDATE — add UpdateDispelTypes()

    elseif event == "PLAYER_TALENT_UPDATE" then
        UpdateRangeSpell()
        UpdateDispelTypes()
    end

---

## Note on UpdateBorder

No changes needed. UpdateBorder reads f._dispelColor which is now only set when
the player can dispel that type (gated in isDispellable inside UpdateAuras).

---

## Open Questions (verify in-game)

| Question | Verify with | Fallback in plan |
|---|---|---|
| dispelName vs dispelType in live 12.0? | `/run local a=C_UnitAuras.GetAuraDataByIndex("player",1,"HARMFUL"); if a then print(a.dispelName,a.dispelType) end` while debuffed | `aura.dispelName or aura.dispelType` bridge |
| UI-Debuff-Overlays texcoord renders correct swatch? | Visual in test mode | Badge 10x10; only badge looks wrong if bad |
| consecutiveNils >= 2 sufficient for private gaps? | Diagnostic in dungeon | Trivial to change threshold |

---

## Non-Goals

- No type badge on buff icons.
- No test mode fake badge rendering (badges hidden in fake debuff loop).
- No Evoker spec-level distinction.
- No tooltip changes.

---

## Implementation Order

1. Frames.lua — add typeOverlay (Change 1)
2. CH_DPadParty.lua — add DISPEL_BY_CLASS + scratch tables (Change 2)
3. CH_DPadParty.lua — add isDispellable + UpdateDispelTypes (Change 3)
4. CH_DPadParty.lua — rewrite UpdateAuras debuff section (Change 4)
5. CH_DPadParty.lua — fix test mode (Change 5)
6. CH_DPadParty.lua — add event hooks (Change 6)
7. docs/GOTCHAS.md — append G-071 through G-074
