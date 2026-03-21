# Plan: Increase buff/debuff aura icon size for Steam Deck readability

## Goal

Increase buff/debuff aura icon size from 16×16 to 20×20px, timer font from 7pt
to 9pt, frame height from 74px to 78px, and update OFFSETS math accordingly.
No other geometry is touched.

---

## Constraints

- 3 slots per side still fit: 3×20 + 2×2gap + 4inset = 68px per side, frame 200px wide. ✓
- CooldownFrame uses SetAllPoints — scales automatically with the icon frame. ✓
- Stack count anchor BOTTOMRIGHT 0,0 needs no change. ✓
- Timer anchor TOPLEFT 1,-1 still fits at 9pt in a 20×20 icon. ✓
- No taint risk. ✓
- OFFSETS math: half-height(39) + gap(8) + half-height(39) = 86.
  party1=+86, party4=-86, player=-172. ✓
- Frame height 78px: icons at y=-54, height 20 -> bottom edge y=-74, plus 4px
  bottom inset = 78px. ✓
- Do not touch health bar, power bar, class icon, backdrop, role icons,
  missingBuff, rezIcon, raidMarker, targetRing, overlay, or any event logic.

---

## Files changed

1. `CH_DPadParty_Frames.lua` -- icon size, slot x-spacing, timer font size
2. `CH_DPadParty.lua` -- OFFSETS comment + values, frame SetSize height

---

## Changes

### Change 1 - `CH_DPadParty_Frames.lua`: frame height

Old:
    f:SetSize(200, 74)

New:
    f:SetSize(200, 78)

---

### Change 2 - `CH_DPadParty_Frames.lua`: buff icon size and x-spacing

Old:
    icon:SetSize(16, 16)
    icon:SetPoint("TOPLEFT", f, "TOPLEFT", 4 + (i - 1) * 18, -54)
    timer:SetFont("Fonts\\FRIZQT__.TTF", 7, "OUTLINE")

New:
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", f, "TOPLEFT", 4 + (i - 1) * 22, -54)
    timer:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")

Stride changes from 18 (16px + 2px gap) to 22 (20px + 2px gap). y=-54 unchanged.

---

### Change 3 - `CH_DPadParty_Frames.lua`: debuff icon size and x-spacing

Old:
    icon:SetSize(16, 16)
    icon:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(4 + (i - 1) * 18), -54)
    timer:SetFont("Fonts\\FRIZQT__.TTF", 7, "OUTLINE")

New:
    icon:SetSize(20, 20)
    icon:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(4 + (i - 1) * 22), -54)
    timer:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")

---

### Change 4 - `CH_DPadParty.lua`: OFFSETS comment block

Old:
    -- Spacing recalculated for 74px frame height (37px half-height) with 8px gaps.
    -- Adjacent slot spacing: half-height(37) + gap(8) + half-height(37) = 82.
    -- Player offset: 2 x 82 = 164.

New:
    -- Spacing recalculated for 78px frame height (39px half-height) with 8px gaps.
    -- Adjacent slot spacing: half-height(39) + gap(8) + half-height(39) = 86.
    -- Player offset: 2 x 86 = 172.

---

### Change 5 - `CH_DPadParty.lua`: OFFSETS values

Old:
    local OFFSETS = {
        party1 = {   0,   82 },
        party2 = { -104,   0 },
        party3 = {  104,   0 },
        party4 = {   0,  -82 },
        player = {   0, -164 },
    }

New:
    local OFFSETS = {
        party1 = {   0,   86 },
        party2 = { -104,   0 },
        party3 = {  104,   0 },
        party4 = {   0,  -86 },
        player = {   0, -172 },
    }

party2/party3 horizontal offsets unchanged (depend on frame width, not height).

---

## Geometry verification

| Quantity        | Old   | New   | Calculation                              |
|-----------------|-------|-------|------------------------------------------|
| Icon size       | 16x16 | 20x20 | requirement                              |
| Slot stride     | 18px  | 22px  | icon(20) + gap(2)                        |
| 3-slot span     | 52px  | 64px  | 3x20 + 2x2 = 64; +4px inset = 68 <= 100 |
| Aura row top    | y=-54 | y=-54 | unchanged                                |
| Aura row bottom | y=-70 | y=-74 | -54 - 20 = -74                           |
| Bottom inset    | 4px   | 4px   | unchanged                                |
| Required height | 74px  | 78px  | 74 + 4 = 78                              |
| Half-height     | 37px  | 39px  | 78 / 2 = 39                              |
| Vertical offset | 82px  | 86px  | 39 + 8 + 39 = 86                         |
| Player offset   | 164px | 172px | 2 x 86 = 172                             |
| Timer font      | 7pt   | 9pt   | requirement                              |

---

## Rollback

All changes are self-contained value substitutions with no new logic. To revert,
restore the six old values: one SetSize, two SetSize/SetPoint/font pairs,
one comment block, one OFFSETS table.
