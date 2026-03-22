-- CHFrames_Minimap.lua
-- Minimap button for CHFrames — raw WoW API, no LibDBIcon
------------------------------------------------------------------------

CHFrames = CHFrames or {}

------------------------------------------------------------------------
-- UpdateMinimapButtonPos
------------------------------------------------------------------------

function CHFrames.UpdateMinimapButtonPos()
    local btn = CHFrames.minimapBtn
    if not btn then return end

    local angle = CHFramesDB and CHFramesDB.minimapPos or 210
    local rad   = math.rad(angle)
    -- G-062: dynamic radius, never hardcoded
    local r     = (Minimap:GetWidth() / 2) + 5

    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * r, math.sin(rad) * r)
end

------------------------------------------------------------------------
-- BuildMinimapButton
------------------------------------------------------------------------

function CHFrames.BuildMinimapButton()
    -- Pattern confirmed from LibDBIcon-1.0 source (used by BigWigs, Details,
    -- hundreds of other addons). Round appearance requires NO masking — just a
    -- small 18×18 icon that sits inside the ring's inner opening.
    local btn = CreateFrame("Button", "CHFramesMinimapBtn", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFixedFrameStrata(true)   -- prevent ElvUI/other addons overriding strata
    btn:SetFrameLevel(8)
    btn:SetFixedFrameLevel(true)    -- prevent ElvUI/other addons overriding level

    -- Background disc — dark fill inside the ring (BACKGROUND layer)
    -- FileID 136467 = "Interface\\Minimap\\UI-Minimap-Background"
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(136467)
    bg:SetSize(24, 24)
    bg:SetPoint("CENTER", 0, 0)

    -- Icon — 18×18 centered, NOT SetAllPoints. The small size means the icon's
    -- square corners are hidden behind the ring border — no mask needed.
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER", 0, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)   -- crop hard square icon border

    -- Border ring — 50×50 at TOPLEFT 0,0 (retail mainline size per LibDBIcon)
    -- FileID 136430 = "Interface\\Minimap\\MiniMap-TrackingBorder"
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture(136430)
    border:SetSize(50, 50)
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)

    -- Highlight on hover — FileID 136477 = UI-Minimap-ZoomButton-Highlight
    btn:SetHighlightTexture(136477)

    btn:RegisterForDrag("RightButton")
    btn:SetMovable(true)

    -- Left-click: toggle settings panel
    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            local panel = CHFrames.SettingsPanel
            if panel then
                if panel:IsShown() then
                    panel:Hide()
                else
                    panel:Show()
                end
            end
        end
    end)

    -- Right-drag: orbit button around minimap edge
    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            -- G-062: scale-corrected cursor position
            local cx, cy = GetCursorPosition()
            local scale  = UIParent:GetEffectiveScale()
            cx = cx / scale
            cy = cy / scale

            -- Minimap center in scaled coordinates
            local mx = Minimap:GetLeft()   + Minimap:GetWidth()  / 2
            local my = Minimap:GetBottom() + Minimap:GetHeight() / 2

            -- G-063: math.atan2(y, x) — NOT math.atan
            local angle = math.deg(math.atan2(cy - my, cx - mx))
            CHFramesDB.minimapPos = angle
            CHFrames.UpdateMinimapButtonPos()
        end)
    end)

    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    -- Auto-hide: visible only while hovering the minimap or the button itself.
    -- Start hidden; Minimap OnEnter/OnLeave reveal and re-hide it.
    btn:Hide()

    Minimap:HookScript("OnEnter", function()
        btn:Show()
    end)

    Minimap:HookScript("OnLeave", function()
        C_Timer.After(0.3, function()
            if not MouseIsOver(Minimap) and not MouseIsOver(btn) then
                btn:Hide()
            end
        end)
    end)

    btn:SetScript("OnEnter", function(self)
        -- Keep visible while hovering the button
    end)

    btn:SetScript("OnLeave", function(self)
        C_Timer.After(0.3, function()
            if not MouseIsOver(Minimap) and not MouseIsOver(self) then
                self:Hide()
            end
        end)
    end)

    CHFrames.minimapBtn = btn
    CHFrames.UpdateMinimapButtonPos()
end
