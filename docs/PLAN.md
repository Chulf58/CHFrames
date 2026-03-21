# CH_DPadParty — Auto-Hide Blizzard Party Frames

**Date drafted:** 2026-03-21
**Status:** Ready for implementation

---

## Overview

When CH_DPadParty loads, automatically hide the default WoW party frames.
The ONLY safe mechanism is `RegisterStateDriver` — a Blizzard secure C-level
state driver. Do NOT call `:Hide()`, `:UnregisterAllEvents()`, or any other
Lua method on these frames (G-CRITICAL taint).

Frames targeted:
- `PartyFrame` — modern party UI (default in current retail)
- `CompactPartyFrame` — compact/raid-style UI
- `CompactRaidFrameManager` — the toggle arrow widget on screen-left

---

## New File: CH_DPadParty_HideBlizzard.lua

Self-contained. Own event frame. No dependency on CHDPadParty.* or CHDPadPartyDB.

### Code

    -- CH_DPadParty_HideBlizzard.lua
    -- Hides Blizzard default party frames when CH_DPadParty is active.
    -- Uses RegisterStateDriver (secure C-level) — NOT :Hide() or
    -- :UnregisterAllEvents(), which taint the execution context (G-CRITICAL).
    ------------------------------------------------------------------------

    -- G-075: RegisterStateDriver routes through Blizzard's secure state driver
    -- at the C level. Categorically different from frame:Hide() or
    -- frame:UnregisterAllEvents() from Lua (both permanently taint — G-CRITICAL).

    local _blizzardFramesHidden = false

    local hideFrame = CreateFrame("Frame", "CHDPadPartyHideFrame", UIParent)
    hideFrame:RegisterEvent("PLAYER_LOGIN")

    hideFrame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_LOGIN" then
            if _blizzardFramesHidden then return end
            _blizzardFramesHidden = true

            -- G-075: Target PartyFrame only. CompactPartyFrame and
            -- CompactRaidFrameManager are excluded until in-game RegisterStateDriver
            -- taint test confirms they are safe (see Open Questions below).
            -- KNOWN LIMITATION: PLAYER_LOGIN does not re-fire on /reload — use
            -- /run RegisterStateDriver(PartyFrame,"visibility","hide") to re-hide
            -- after a reload if needed during development.

            if PartyFrame then
                RegisterStateDriver(PartyFrame, "visibility", "hide")
            end
        end
    end)

---

## TOC Change: CH_DPadParty.toc

Add as the FIRST file in the load list.

### Old

    CH_DPadParty_Frames.lua
    CH_DPadParty_Minimap.lua
    CH_DPadParty_Settings.lua
    CH_DPadParty.lua

### New

    CH_DPadParty_HideBlizzard.lua
    CH_DPadParty_Frames.lua
    CH_DPadParty_Minimap.lua
    CH_DPadParty_Settings.lua
    CH_DPadParty.lua

---

## GOTCHAS.md Addition

Append to "Taint & Secure Execution" section:

    G-075: Use RegisterStateDriver to hide Blizzard party frames; never call Lua
    methods on them. RegisterStateDriver(frame, "visibility", "hide") routes through
    Blizzard's secure C-level state driver without tainting our context. Calling
    :Hide(), :UnregisterAllEvents(), or any Lua method on PartyFrame/CompactPartyFrame/
    CompactRaidFrameManager triggers G-CRITICAL taint. Implemented in
    CH_DPadParty_HideBlizzard.lua, triggered on PLAYER_LOGIN with a guard flag.

---

## Open Questions (verify in-game)

- Does RegisterStateDriver on CompactPartyFrame/CompactRaidFrameManager cause taint?
  Test: `/run print(issecretvalue(UnitHealthPercent("player", true, CurveConstants.ScaleTo100)))`
  Should print false after login. If true: remove CompactPartyFrame/CompactRaidFrameManager lines.
- Are both PartyFrame and CompactPartyFrame present simultaneously?
  Test: `/run print(PartyFrame and "P" or "nil", CompactPartyFrame and "C" or "nil")`
  Nil guards in code handle any combination.

---

## Non-Goals

- No settings toggle (disable the addon to get frames back)
- No UnregisterAllEvents under any circumstance (G-CRITICAL)
- No EditMode manipulation

---

## Implementation Order

1. Create CH_DPadParty_HideBlizzard.lua with exact code above
2. Edit CH_DPadParty.toc — insert as first file
3. Append G-075 to docs/GOTCHAS.md
