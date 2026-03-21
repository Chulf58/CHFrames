-- CH_DPadParty_Settings.lua
-- Tabbed settings panel for CH_DPadParty
------------------------------------------------------------------------

CHDPadParty = CHDPadParty or {}

------------------------------------------------------------------------
-- Layout dropdown data
------------------------------------------------------------------------

local LAYOUT_OPTIONS = {
    { value = "handheld",   label = "D-Pad (Handheld)"  },
    { value = "sidebyside", label = "Side by Side"       },
    { value = "stacked",    label = "Stacked (Vertical)" },
}

------------------------------------------------------------------------
-- RefreshSettingsPanel — sync UI widgets from DB state
------------------------------------------------------------------------

function CHDPadParty.RefreshSettingsPanel()
    if not CHDPadPartyDB then return end

    if CHDPadParty.lockCheckbox then
        CHDPadParty.lockCheckbox:SetChecked(CHDPadPartyDB.locked or false)
    end
    if CHDPadParty.testModeCheckbox then
        CHDPadParty.testModeCheckbox:SetChecked(CHDPadPartyDB.testMode or false)
    end
    if CHDPadParty.scaleSlider then
        CHDPadParty.scaleSlider:SetValue(CHDPadPartyDB.scale or 1.0)
    end
    if CHDPadParty.layoutDropdown and CHDPadPartyDB.layout then
        for _, opt in ipairs(LAYOUT_OPTIONS) do
            if opt.value == CHDPadPartyDB.layout then
                CHDPadParty.layoutDropdown:SetText(opt.label)
                break
            end
        end
    end
end

-- Backward-compat alias used by Init()
CHDPadParty.RefreshSettingsButtons = CHDPadParty.RefreshSettingsPanel

------------------------------------------------------------------------
-- BuildSettingsPanel
------------------------------------------------------------------------

function CHDPadParty.BuildSettingsPanel()
    local PANEL_W, PANEL_H = 420, 380

    local panel = CreateFrame("Frame", "CHDPadPartySettingsPanel", UIParent, "BackdropTemplate")
    panel:SetSize(PANEL_W, PANEL_H)
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

    -- Restore saved position
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
        local x, y = self:GetLeft(), self:GetTop()
        if x and y then
            CHDPadPartyDB.settingsX = x
            CHDPadPartyDB.settingsY = y
        end
    end)

    -- Sync widget state each time the panel opens
    panel:SetScript("OnShow", function() CHDPadParty.RefreshSettingsPanel() end)

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -8)
    title:SetTextColor(1, 0.82, 0, 1)
    title:SetText("CH D-Pad Party")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function() panel:Hide() end)

    --------------------------------------------------------------------
    -- Tab buttons (anchored below title, starting at y=-24)
    --------------------------------------------------------------------

    local tabNames = { "General", "Layout", "Appearance", "Auras" }

    -- Content area: below tab buttons, fills rest of panel
    local contentArea = CreateFrame("Frame", nil, panel)
    contentArea:SetPoint("TOPLEFT",  panel, "TOPLEFT",  8,  -56)
    contentArea:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 8)

    -- One content frame per tab
    local views = {}
    for i = 1, #tabNames do
        local v = CreateFrame("Frame", nil, contentArea)
        v:SetAllPoints(contentArea)
        v:Hide()
        views[i] = v
    end

    -- PanelTemplates_SetTab requires panel.Tabs[i] to exist
    panel.Tabs = {}

    for i, name in ipairs(tabNames) do
        local tab = CreateFrame("Button", nil, panel, "PanelTopTabButtonTemplate")
        tab:SetText(name)
        -- Size the tab immediately (mirrors Baganator pattern)
        tab:SetScript("OnShow", function(self)
            PanelTemplates_TabResize(self, 15, nil, 70)
            PanelTemplates_DeselectTab(self)
        end)
        tab:GetScript("OnShow")(tab)

        if i == 1 then
            tab:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -24)
        else
            tab:SetPoint("LEFT", panel.Tabs[i-1], "RIGHT", -2, 0)
        end

        local idx = i
        tab:SetScript("OnClick", function()
            for j = 1, #views do views[j]:Hide() end
            views[idx]:Show()
            PanelTemplates_SetTab(panel, idx)
        end)

        panel.Tabs[i] = tab
    end

    PanelTemplates_SetNumTabs(panel, #panel.Tabs)

    --------------------------------------------------------------------
    -- Helpers
    --------------------------------------------------------------------

    local function MakeLabel(parent, text, anchor, ox, oy)
        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", anchor, "TOPLEFT", ox or 0, oy or 0)
        lbl:SetTextColor(0.85, 0.85, 0.85, 1)
        lbl:SetText(text)
        return lbl
    end

    local function MakeSeparator(parent, anchor, oy)
        local sep = parent:CreateTexture(nil, "ARTWORK")
        sep:SetHeight(1)
        sep:SetPoint("TOPLEFT",  anchor, "BOTTOMLEFT",  0, oy or -6)
        sep:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, oy or -6)
        sep:SetColorTexture(0.3, 0.3, 0.3, 0.7)
        return sep
    end

    --------------------------------------------------------------------
    -- TAB 1: General
    --------------------------------------------------------------------

    local v1 = views[1]

    local lbl1 = MakeLabel(v1, "Frames", v1, 10, -6)
    local sep1 = MakeSeparator(v1, lbl1, -4)

    -- Lock checkbox
    local lockCb = CreateFrame("CheckButton", nil, v1, "UICheckButtonTemplate")
    lockCb:SetSize(24, 24)
    lockCb:SetPoint("TOPLEFT", sep1, "BOTTOMLEFT", 0, -10)
    local lockLbl = v1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lockLbl:SetPoint("LEFT", lockCb, "RIGHT", 4, 0)
    lockLbl:SetText("Lock frames (prevent dragging)")
    lockCb:SetChecked(CHDPadPartyDB and CHDPadPartyDB.locked or false)
    lockCb:SetScript("OnClick", function(self)
        if not CHDPadPartyDB or not CHDPadParty.root then return end
        if InCombatLockdown() then
            self:SetChecked(CHDPadPartyDB.locked)
            print("|cff00ff00CH_DPadParty:|r Cannot change lock state in combat.")
            return
        end
        CHDPadPartyDB.locked = not not self:GetChecked()
        CHDPadParty.root:SetMovable(not CHDPadPartyDB.locked)
        local locked = CHDPadPartyDB.locked
        for _, u in ipairs({ "party1", "party2", "party3", "party4", "player" }) do
            local fr = CHDPadParty.frames[u]
            if fr and fr.secureBtn then
                if locked then
                    fr.secureBtn:RegisterForDrag()
                else
                    fr.secureBtn:RegisterForDrag("LeftButton")
                end
            end
        end
    end)
    CHDPadParty.lockCheckbox = lockCb

    -- Test mode checkbox
    local testCb = CreateFrame("CheckButton", nil, v1, "UICheckButtonTemplate")
    testCb:SetSize(24, 24)
    testCb:SetPoint("TOPLEFT", lockCb, "BOTTOMLEFT", 0, -8)
    local testLbl = v1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    testLbl:SetPoint("LEFT", testCb, "RIGHT", 4, 0)
    testLbl:SetText("Test mode (show fake party data)")
    testCb:SetChecked(CHDPadPartyDB and CHDPadPartyDB.testMode or false)
    testCb:SetScript("OnClick", function(self)
        if not CHDPadPartyDB then return end
        CHDPadPartyDB.testMode = not not self:GetChecked()
        if CHDPadPartyDB.testMode then
            CHDPadParty.ApplyTestMode()
        else
            CHDPadParty.UpdateVisibility()
            CHDPadParty.UpdateAll()
        end
    end)
    CHDPadParty.testModeCheckbox = testCb

    --------------------------------------------------------------------
    -- TAB 2: Layout
    --------------------------------------------------------------------

    local v2 = views[2]

    local lbl2 = MakeLabel(v2, "Frame Layout", v2, 10, -6)
    local sep2 = MakeSeparator(v2, lbl2, -4)

    -- Layout dropdown label
    local layoutLbl = MakeLabel(v2, "Layout:", sep2, 0, -14)

    -- Layout dropdown (WowStyle1DropdownTemplate — 12.0 standard)
    local layoutDD = CreateFrame("DropdownButton", nil, v2, "WowStyle1DropdownTemplate")
    layoutDD:SetSize(200, 22)
    layoutDD:SetPoint("LEFT", layoutLbl, "RIGHT", 10, 0)
    layoutDD:SetupMenu(function(_, rootDescription)
        for _, opt in ipairs(LAYOUT_OPTIONS) do
            local o = opt  -- upvalue for closure
            rootDescription:CreateRadio(
                o.label,
                function() return CHDPadPartyDB and CHDPadPartyDB.layout == o.value end,
                function()
                    if InCombatLockdown() then
                        print("|cff00ff00CH_DPadParty:|r Cannot change layout in combat.")
                        return
                    end
                    CHDPadParty.ApplyLayout(o.value)
                    layoutDD:SetText(o.label)
                end
            )
        end
    end)
    -- Set initial display text from saved layout
    local curLayout = (CHDPadPartyDB and CHDPadPartyDB.layout) or "handheld"
    for _, opt in ipairs(LAYOUT_OPTIONS) do
        if opt.value == curLayout then
            layoutDD:SetText(opt.label)
            break
        end
    end
    CHDPadParty.layoutDropdown = layoutDD

    -- Scale section
    MakeLabel(v2, "Scale", sep2, 0, -52)
    local sep2b = MakeSeparator(v2, sep2, -66)

    local scaleLbl = MakeLabel(v2, "Scale:", sep2b, 0, -14)

    -- Scale value readout (updated by slider)
    local scaleReadout = v2:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    scaleReadout:SetPoint("LEFT", scaleLbl, "RIGHT", 8, 0)
    scaleReadout:SetText(string.format("%.1f", (CHDPadPartyDB and CHDPadPartyDB.scale) or 1.0))

    local scaleHolder = CreateFrame("Frame", nil, v2, "MinimalSliderWithSteppersTemplate")
    scaleHolder:SetSize(260, 20)
    scaleHolder:SetPoint("TOPLEFT", sep2b, "BOTTOMLEFT", 0, -38)
    local scaleSlider = scaleHolder.Slider
    if scaleSlider then
        scaleSlider:EnableMouse(true)
        scaleSlider:SetMinMaxValues(0.5, 2.0)
        scaleSlider:SetValueStep(0.1)
        scaleSlider:SetObeyStepOnDrag(true)
        scaleSlider:SetValue((CHDPadPartyDB and CHDPadPartyDB.scale) or 1.0)
        scaleSlider:SetScript("OnValueChanged", function(_, v)
            if not CHDPadPartyDB or not CHDPadParty.root then return end
            local s = math.floor(v * 10 + 0.5) / 10
            CHDPadPartyDB.scale = s
            CHDPadParty.root:SetScale(s)
            scaleReadout:SetText(string.format("%.1f", s))
        end)
        CHDPadParty.scaleSlider = scaleSlider
    end

    --------------------------------------------------------------------
    -- TAB 3: Appearance (placeholder)
    --------------------------------------------------------------------

    local v3 = views[3]
    local ph3 = v3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ph3:SetPoint("TOP", v3, "TOP", 0, -40)
    ph3:SetJustifyH("CENTER")
    ph3:SetTextColor(0.55, 0.55, 0.55, 1)
    ph3:SetText("Appearance options coming soon.\n\nHealth bar color mode, frame style,\nclass icon vs spec icon vs portrait,\nbackground color, border style, and more.")

    --------------------------------------------------------------------
    -- TAB 4: Auras (placeholder)
    --------------------------------------------------------------------

    local v4 = views[4]
    local ph4 = v4:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ph4:SetPoint("TOP", v4, "TOP", 0, -40)
    ph4:SetJustifyH("CENTER")
    ph4:SetTextColor(0.55, 0.55, 0.55, 1)
    ph4:SetText("Aura options coming soon.\n\nBuff/debuff slot count, icon size,\nduration display filter, timer visibility,\nAtonement tracker, and more.")

    --------------------------------------------------------------------
    -- Select General tab by default
    --------------------------------------------------------------------

    views[1]:Show()
    PanelTemplates_SetTab(panel, 1)

    CHDPadParty.SettingsPanel = panel
    return panel
end
