-- CH_DPadParty_Settings.lua
-- Settings panel for CH_DPadParty
------------------------------------------------------------------------

CHDPadParty = CHDPadParty or {}

------------------------------------------------------------------------
-- Local helpers
------------------------------------------------------------------------

local function MakeButton(parent, width, height)
    local btn = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true,
        tileSize = 16,
        edgeSize = 10,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    btn:SetBackdropColor(0.1, 0.1, 0.12, 0.9)
    btn:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)
    btn:EnableMouse(true)

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    label:SetTextColor(1, 1, 1, 1)
    btn.label = label

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.18, 0.18, 0.22, 0.95)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.1, 0.1, 0.12, 0.9)
    end)

    return btn
end

------------------------------------------------------------------------
-- RefreshSettingsButtons
------------------------------------------------------------------------

function CHDPadParty.RefreshSettingsButtons()
    local lockBtn     = CHDPadParty.lockBtn
    local testModeBtn = CHDPadParty.testModeBtn
    if not (lockBtn and testModeBtn) then return end

    if CHDPadPartyDB and CHDPadPartyDB.locked then
        lockBtn.label:SetText("[Locked] Click to Unlock")
    else
        lockBtn.label:SetText("[Unlocked] Click to Lock")
    end

    if CHDPadPartyDB and CHDPadPartyDB.testMode then
        testModeBtn.label:SetText("Test Mode: ON")
    else
        testModeBtn.label:SetText("Test Mode: OFF")
    end
end

------------------------------------------------------------------------
-- BuildSettingsPanel
------------------------------------------------------------------------

function CHDPadParty.BuildSettingsPanel()
    local panel = CreateFrame("Frame", "CHDPadPartySettingsPanel", UIParent, "BackdropTemplate")
    panel:SetSize(200, 120)
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetClampedToScreen(true)
    panel:Hide()

    panel:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true,
        tileSize = 16,
        edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    panel:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
    panel:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)

    -- Restore saved position, or default to center-right of screen
    if CHDPadPartyDB and CHDPadPartyDB.settingsX and CHDPadPartyDB.settingsY then
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
            CHDPadPartyDB.settingsX, CHDPadPartyDB.settingsY)
    else
        panel:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    end

    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- G-054: persist position via GetLeft/GetTop (panel is TOPLEFT-anchored after drag)
        local x = self:GetLeft()
        local y = self:GetTop()
        if x and y then
            CHDPadPartyDB.settingsX = x
            CHDPadPartyDB.settingsY = y
        end
    end)

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
    title:SetTextColor(1, 0.82, 0, 1)
    title:SetText("CH D-Pad")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function() panel:Hide() end)

    -- Lock button (row 1)
    local lockBtn = MakeButton(panel, 180, 28)
    lockBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -28)
    lockBtn.label:SetText("[Locked] Click to Unlock")

    lockBtn:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        if not CHDPadPartyDB or not CHDPadParty.root then return end
        if InCombatLockdown() then
            print("|cff00ff00CH_DPadParty:|r Cannot change lock state in combat.")
            return
        end

        CHDPadPartyDB.locked = not CHDPadPartyDB.locked

        -- G-064: SetMovable is the correct lock mechanism, not EnableMouse
        if CHDPadPartyDB.locked then
            CHDPadParty.root:SetMovable(false)
            self.label:SetText("[Locked] Click to Unlock")
        else
            CHDPadParty.root:SetMovable(true)
            self.label:SetText("[Unlocked] Click to Lock")
        end

        -- Sync drag state only. secureBtn visibility is RegisterUnitWatch's responsibility.
        local locked = CHDPadPartyDB.locked
        for _, u in ipairs({ "party1", "party2", "party3", "party4", "player" }) do
            local fr = CHDPadParty.frames[u]
            if fr then
                if locked then
                    fr:RegisterForDrag()
                    fr:EnableMouse(false)
                else
                    fr:RegisterForDrag("LeftButton")
                    fr:EnableMouse(true)
                end
            end
        end
    end)

    -- Test Mode button (row 2)
    local testModeBtn = MakeButton(panel, 180, 28)
    testModeBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -62)
    testModeBtn.label:SetText("Test Mode: OFF")

    testModeBtn:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        if not CHDPadPartyDB then return end

        CHDPadPartyDB.testMode = not CHDPadPartyDB.testMode

        if CHDPadPartyDB.testMode then
            self.label:SetText("Test Mode: ON")
            CHDPadParty.ApplyTestMode()
        else
            self.label:SetText("Test Mode: OFF")
            CHDPadParty.UpdateVisibility()
            CHDPadParty.UpdateAll()
            for _, unit in ipairs({ "party1", "party2", "party3", "party4", "player" }) do
                CHDPadParty.UpdateAuras(unit)
            end
        end
    end)

    CHDPadParty.SettingsPanel = panel
    CHDPadParty.lockBtn       = lockBtn
    CHDPadParty.testModeBtn   = testModeBtn

    return panel
end
