# PLAN_VEHICLE.md — Vehicle Icon for Party Frames

**Date drafted:** 2026-03-21
**Status:** Ready for implementation

---

## Overview

Show a 14x14 icon at BOTTOMLEFT x=22 (right of rezIcon) when UnitHasVehicleUI(unit) is true.

---

## Files Changed

| File | Change |
|---|---|
| `CH_DPadParty_Frames.lua` | Add `vehicleIcon` frame after rezIcon block |
| `CH_DPadParty.lua` | Add UpdateVehicle, call from UpdateAll, register events, add handlers |

---

## Change 1 — Frames.lua: add vehicleIcon

Insert immediately after `f.rezIcon = rezIcon`, before the raid marker comment.

### New (pure addition)

    -- Vehicle indicator (14x14, bottom-left slot 2, x=22 = 4+14+4).
    -- Shown when UnitHasVehicleUI(unit) is true.
    -- Frame level +6: same as rezIcon — different x-position, no z-conflict.
    local vehicleIcon = CreateFrame("Frame", nil, f, "BackdropTemplate")
    vehicleIcon:SetSize(14, 14)
    vehicleIcon:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 22, 4)
    vehicleIcon:SetFrameLevel(f:GetFrameLevel() + 6)
    vehicleIcon:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
    vehicleIcon:SetBackdropColor(0.0, 0.4, 0.8, 0.9)
    local vehicleTex = vehicleIcon:CreateTexture(nil, "ARTWORK")
    vehicleTex:SetAllPoints(vehicleIcon)
    vehicleTex:SetTexture("Interface\\Minimap\\Vehicle-Icon")
    vehicleIcon.tex = vehicleTex
    vehicleIcon:Hide()
    f.vehicleIcon = vehicleIcon

---

## Change 2 — CH_DPadParty.lua: UpdateVehicle function

Insert after the UpdateRez block, before the UpdateRaidMarker separator comment.

### New (pure addition)

    ------------------------------------------------------------------------
    -- UpdateVehicle
    ------------------------------------------------------------------------

    function CHDPadParty.UpdateVehicle(unit)
        if CHDPadPartyDB and CHDPadPartyDB.testMode then return end
        local f = CHDPadParty.frames[unit]
        if not f or not f.vehicleIcon then return end
        local ok, result = pcall(UnitHasVehicleUI, unit)
        if ok and result then
            f.vehicleIcon:Show()
        else
            f.vehicleIcon:Hide()
        end
    end

---

## Change 3 — CH_DPadParty.lua: UpdateAll

Add `CHDPadParty.UpdateVehicle(unit)` after UpdateRez in the UpdateAll loop.

### Old

        CHDPadParty.UpdateRez(unit)
        CHDPadParty.UpdateRaidMarker(unit)

### New

        CHDPadParty.UpdateRez(unit)
        CHDPadParty.UpdateVehicle(unit)
        CHDPadParty.UpdateRaidMarker(unit)

---

## Change 4 — CH_DPadParty.lua: event registration

After `eventFrame:RegisterEvent("RAID_TARGET_UPDATE")`.

### Old

    eventFrame:RegisterEvent("RAID_TARGET_UPDATE")          -- raid marker assigned/cleared

### New

    eventFrame:RegisterEvent("RAID_TARGET_UPDATE")          -- raid marker assigned/cleared
    eventFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")        -- unit mounted a vehicle
    eventFrame:RegisterEvent("UNIT_EXITED_VEHICLE")         -- unit dismounted from vehicle

---

## Change 5 — CH_DPadParty.lua: OnEvent handlers

After the INCOMING_RESURRECT_CHANGED/INCOMING_SUMMON_CHANGED handler, before RAID_TARGET_UPDATE.

### Old

    elseif event == "INCOMING_RESURRECT_CHANGED" or event == "INCOMING_SUMMON_CHANGED" then
        if arg1 and UNIT_LOOKUP[arg1] then
            CHDPadParty.UpdateRez(arg1)
        end

    elseif event == "RAID_TARGET_UPDATE" then

### New

    elseif event == "INCOMING_RESURRECT_CHANGED" or event == "INCOMING_SUMMON_CHANGED" then
        if arg1 and UNIT_LOOKUP[arg1] then
            CHDPadParty.UpdateRez(arg1)
        end

    elseif event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
        if arg1 and UNIT_LOOKUP[arg1] then
            CHDPadParty.UpdateVehicle(arg1)
        end

    elseif event == "RAID_TARGET_UPDATE" then

---

## Implementation Order

1. Frames.lua — vehicleIcon (Change 1)
2. CH_DPadParty.lua — UpdateVehicle (Change 2)
3. CH_DPadParty.lua — UpdateAll (Change 3)
4. CH_DPadParty.lua — events (Change 4)
5. CH_DPadParty.lua — handlers (Change 5)

---

## Verification

    /run print(UnitHasVehicleUI("player"))

Board a vehicle. Confirm icon appears at x=22 bottom-left. Confirm rezIcon unaffected.
If texture missing (blank/question mark), the blue backdrop still shows; note for follow-up.
