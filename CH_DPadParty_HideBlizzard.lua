-- CH_DPadParty_HideBlizzard.lua
-- Hides Blizzard default party frames when CH_DPadParty is active.
-- Uses RegisterStateDriver (secure C-level) — NOT :Hide() or
-- :UnregisterAllEvents(), which taint the execution context (G-CRITICAL).
------------------------------------------------------------------------

-- G-075: RegisterStateDriver routes through Blizzard's secure state driver
-- at the C level. Categorically different from frame:Hide() or
-- frame:UnregisterAllEvents() from Lua (both permanently taint — G-CRITICAL).

-- KNOWN LIMITATION: PLAYER_LOGIN does not re-fire on /reload.
-- During development, re-hide manually:
--   /run if PartyFrame then RegisterStateDriver(PartyFrame,"visibility","hide") end
-- CompactPartyFrame and CompactRaidFrameManager are NOT targeted here until
-- in-game RegisterStateDriver taint testing confirms they are safe (G-075).

local _blizzardFramesHidden = false

local hideFrame = CreateFrame("Frame", "CHDPadPartyHideFrame", UIParent)
hideFrame:RegisterEvent("PLAYER_LOGIN")

hideFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        if _blizzardFramesHidden then return end
        _blizzardFramesHidden = true

        if PartyFrame then
            RegisterStateDriver(PartyFrame, "visibility", "hide")
        end
    end
end)
