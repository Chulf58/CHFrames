-- CH_DPadParty_Frames.lua
-- Frame construction helpers for CH_DPadParty
-- Builds the root anchor frame and individual unit frames
------------------------------------------------------------------------

CHDPadParty = CHDPadParty or {}

------------------------------------------------------------------------
-- Root Frame
------------------------------------------------------------------------

function CHDPadParty.BuildRootFrame()
    local root = CreateFrame("Frame", "CHDPadPartyRoot", UIParent)
    root:SetSize(16, 16)
    root:SetFrameStrata("MEDIUM")
    root:SetMovable(true)
    root:EnableMouse(true)
    root:RegisterForDrag("LeftButton")

    root:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)

    root:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        if point and x and y then
            CHDPadPartyDB.position = {
                point         = point,
                relativePoint = relativePoint or "CENTER",
                x             = x,
                y             = y,
            }
        end
    end)

    CHDPadParty.root = root
    return root
end

------------------------------------------------------------------------
-- Unit Frame
------------------------------------------------------------------------

function CHDPadParty.BuildUnitFrame(unit)
    local root = CHDPadParty.root
    if not root then
        error("CH_DPadParty: BuildRootFrame() must be called before BuildUnitFrame()")
    end

    -- Outer frame parented to root
    local f = CreateFrame("Frame", "CHDPadPartyFrame_" .. unit, root, "BackdropTemplate")
    f:SetSize(200, 78)
    f.unit = unit

    -- Drag is handled by secureBtn (not f) because secureBtn sits at frame level 100
    -- and intercepts all mouse input before f. Registering drag on f is ineffective.
    -- secureBtn:RegisterForDrag / OnDragStart are non-protected scripts — safe to set.

    -- SecureUnitButtonTemplate enables click-to-target and [@mouseover] macros.
    -- Parented to f (not UIParent). A cross-parent anchor (secureBtn:SetAllPoints(f) where
    -- f is NOT secureBtn's parent) makes f "anchor-restricted" — WoW then blocks f:Show()/
    -- f:Hide() from insecure code (ADDON_ACTION_BLOCKED). Parenting secureBtn to f makes it
    -- a normal child-to-parent anchor, eliminating the restriction on f. secureBtn visibility
    -- is managed implicitly: it shows/hides with f. Never call secureBtn:Show()/Hide() directly.
    local secureBtn = CreateFrame("Button", "CHDPadPartySecure_"..unit, f, "SecureUnitButtonTemplate")
    secureBtn:SetAllPoints(f)
    secureBtn:SetFrameStrata("MEDIUM")
    secureBtn:SetFrameLevel(100)
    secureBtn:RegisterForClicks("AnyUp")
    secureBtn:SetAttribute("unit", unit)
    secureBtn:SetAttribute("*type1", "target")
    secureBtn:SetAttribute("*type2", "togglemenu")

    -- Drag: secureBtn is on top (level 100) and receives all mouse input first.
    -- Registering drag here ensures OnDragStart actually fires.
    -- G-064: use RegisterForDrag + SetMovable to lock; never EnableMouse(false) on f.
    secureBtn:RegisterForDrag("LeftButton")
    secureBtn:SetScript("OnDragStart", function(self)
        if not (CHDPadPartyDB and CHDPadPartyDB.locked) then
            CHDPadParty.root:StartMoving()
        end
    end)
    secureBtn:SetScript("OnDragStop", function(self)
        CHDPadParty.root:StopMovingOrSizing()
        local point, _, relativePoint, x, y = CHDPadParty.root:GetPoint(1)
        if point and x and y then
            CHDPadPartyDB.position = {
                point         = point,
                relativePoint = relativePoint or "CENTER",
                x             = x,
                y             = y,
            }
        end
    end)

    f.secureBtn = secureBtn

    -- Backdrop
    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true,
        tileSize = 16,
        edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
    f:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    -- Health bar (top 40px of frame interior)
    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetPoint("TOPLEFT",  f, "TOPLEFT",  48, -4)  -- 4px inset + 40px class icon + 4px gap
    bar:SetPoint("TOPRIGHT", f, "TOPRIGHT",  -4, -4)
    bar:SetHeight(40)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.1, 0.8, 0.1, 1)
    bar:SetMinMaxValues(0, 100)  -- G-057: SetMinMaxValues BEFORE SetValue; range updated to raw HP in UpdateFrame
    bar:SetValue(100)
    f.healthBar = bar

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
    healPredictBar:SetMinMaxValues(0, 1)  -- G-057: range set properly on first UpdateHealPrediction call
    healPredictBar:SetValue(0)
    f.healPredictBar = healPredictBar

    -- Cache the calculator once per frame. CreateUnitHealPredictionCalculator is a
    -- persistent C-side object — creating it on every event is wasteful and unnecessary.
    -- Open question: verify CreateUnitHealPredictionCalculator exists in current build via
    -- /run print(type(CreateUnitHealPredictionCalculator))
    f.healPredictCalc = CreateUnitHealPredictionCalculator and CreateUnitHealPredictionCalculator() or nil

    -- Text pane: transparent frame above absorbBar/healAbsorbBar (those sit at
    -- bar:GetFrameLevel()+1). FontStrings on bar's own OVERLAY layer are occluded
    -- by any child frame at a higher frame level — so name/HP text must live on a
    -- frame whose level is above all overlay StatusBars.
    local textPane = CreateFrame("Frame", nil, bar)
    textPane:SetAllPoints(bar)
    textPane:SetFrameLevel(bar:GetFrameLevel() + 2)

    -- Name text
    local nameText = textPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("TOPLEFT", bar, "TOPLEFT", 4, -4)
    nameText:SetJustifyH("LEFT")
    nameText:SetTextColor(1, 1, 1, 1)
    f.nameText = nameText

    -- HP text
    local hpText = textPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hpText:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -4, 4)
    hpText:SetJustifyH("RIGHT")
    hpText:SetTextColor(1, 1, 1, 1)
    f.hpText = hpText
    -- Absorb presence flag. True when damage absorbs (shields) are active.
    -- UnitGetTotalAbsorbs and UnitHealthMax are both secret numbers in TWW —
    -- arithmetic between them always throws, so we cannot compute a percentage.
    -- UpdateAbsorbs sets this boolean; UpdateFrame uses it to show a "+" suffix.
    f._hasAbsorb = false

    -- Role icon row (below player name, slots grow left to right).
    -- Slot 1 = LFG role (TANK/HEALER/DAMAGER). Extra slots reserved for future use (MT, MA, etc.).
    -- Frames on f (not Textures on the StatusBar) — StatusBar redraws can re-show hidden OVERLAY
    -- textures, causing all unclipped role atlas slots to flash visible on every SetValue call.
    -- Positioned to sit below the name text inside the health bar area (52px from f left, 20px down).
    f.roleIcons = {}
    for i = 1, 3 do
        local ri = CreateFrame("Frame", nil, f)
        ri:SetSize(20, 20)
        ri:SetPoint("TOPLEFT", f, "TOPLEFT", 52 + (i - 1) * 22, -20)
        -- Explicit frame level above healthBar (f+1) so the StatusBar fill doesn't occlude
        -- role icons when both siblings share the same default level.
        ri:SetFrameLevel(f:GetFrameLevel() + 2)
        local tex = ri:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(ri)
        tex:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
        ri.tex = tex
        ri:Hide()
        f.roleIcons[i] = ri
    end

    -- Class icon (40x40 square to the left of the health bar)
    -- Above the dead/offline overlay (frame level +3) so class is always identifiable.
    -- Updated in UpdateFrame via CLASS_ICON_TCOORDS + Interface\WorldStateFrame\Icons-Classes.
    local classIconFrame = CreateFrame("Frame", nil, f, "BackdropTemplate")
    classIconFrame:SetSize(40, 40)
    classIconFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
    classIconFrame:SetFrameLevel(f:GetFrameLevel() + 3)
    classIconFrame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
    classIconFrame:SetBackdropColor(0, 0, 0, 0.8)
    local classIconTex = classIconFrame:CreateTexture(nil, "ARTWORK")
    classIconTex:SetAllPoints(classIconFrame)
    classIconFrame.tex = classIconTex
    classIconFrame:Hide()
    f.classIcon = classIconFrame

    -- Leader crown (16x16, floats above the class icon, hidden unless unit is group leader)
    -- Anchored to the TOP of classIconFrame so it peeks above it; child of f so it can
    -- render outside f's bounds without clipping issues.
    local crownFrame = CreateFrame("Frame", nil, f)
    crownFrame:SetSize(16, 16)
    crownFrame:SetPoint("BOTTOM", classIconFrame, "TOP", 0, 2)
    crownFrame:SetFrameLevel(f:GetFrameLevel() + 4)
    local crownTex = crownFrame:CreateTexture(nil, "ARTWORK")
    crownTex:SetAllPoints(crownFrame)
    crownTex:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
    crownFrame:Hide()
    f.leaderCrown = crownFrame

    -- Damage absorb overlay (shields: Power Word: Shield, Ice Barrier, etc.)
    -- Parented to healthBar; frame level +1 so it renders ON TOP of the health fill at all times —
    -- visible as a "forcefield" even at full health. Semi-transparent (alpha 0.4) keeps text readable.
    -- SetReverseFill: bar fills inward from the right edge so small absorb amounts show as a
    -- thin sliver on the right, growing left as the shield increases.
    local absorbBar = CreateFrame("StatusBar", nil, bar)
    absorbBar:SetFrameLevel(bar:GetFrameLevel() + 1)  -- above healthBar fill; semi-transparent so text shows through
    absorbBar:SetAllPoints(bar)
    absorbBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    absorbBar:SetStatusBarColor(0.0, 0.6, 1.0, 0.7)  -- electric blue: visible against all class colors
    absorbBar:SetMinMaxValues(0, 1)  -- G-057: SetMinMaxValues BEFORE SetValue; bar silently clamps to 0 otherwise
    absorbBar:SetValue(0)
    absorbBar:SetReverseFill(true)
    f.absorbBar = absorbBar

    -- Heal absorb overlay (Necrotic / Mangle / anti-heal effects, dark red)
    -- Fills left to right, anchored to the left edge. Small amount = thin red sliver on the left;
    -- more stacks = red grows rightward, showing how much of the health pool can't be healed back.
    local healAbsorbBar = CreateFrame("StatusBar", nil, bar)
    healAbsorbBar:SetFrameLevel(bar:GetFrameLevel() + 1)  -- above healthBar fill; semi-transparent so text shows through
    healAbsorbBar:SetAllPoints(bar)
    healAbsorbBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    healAbsorbBar:SetStatusBarColor(0.8, 0.1, 0.1, 0.45)
    healAbsorbBar:SetMinMaxValues(0, 1)  -- G-057: SetMinMaxValues BEFORE SetValue; bar silently clamps to 0 otherwise
    healAbsorbBar:SetValue(0)
    f.healAbsorbBar = healAbsorbBar

    -- Dead / offline overlay (BackdropTemplate required for SetBackdrop in retail)
    local overlay = CreateFrame("Frame", nil, f, "BackdropTemplate")
    overlay:SetAllPoints(f)
    overlay:SetFrameLevel(f:GetFrameLevel() + 2)
    overlay:Hide()
    overlay:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
    overlay:SetBackdropColor(0, 0, 0, 0.6)

    local overlayText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overlayText:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    overlayText:SetTextColor(0.8, 0.1, 0.1, 1)
    overlayText:SetText("")
    overlay.label = overlayText
    f.overlay = overlay

    -- Buff icons (3 slots, 20x20) — left side of the aura row, 54px below top.
    -- Buffs grow left→right starting from the left edge.
    f.buffIcons = {}
    for i = 1, 3 do
        local icon = CreateFrame("Frame", nil, f, "BackdropTemplate")
        icon:SetSize(20, 20)
        icon:SetPoint("TOPLEFT", f, "TOPLEFT", 4 + (i - 1) * 22, -54)
        icon:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
        icon:SetBackdropColor(0, 0, 0, 0.8)
        local tex = icon:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(icon)
        icon.tex = tex
        -- Cooldown swipe overlay (WoW animates the clock sweep automatically)
        local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
        cd:SetAllPoints(icon)
        cd:SetDrawEdge(false)
        cd:SetDrawBling(false)
        cd:SetHideCountdownNumbers(true)  -- we draw our own timer text
        cd:Hide()
        icon.cooldown = cd
        -- Stack count
        local count = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
        count:SetTextColor(1, 1, 1, 1)
        count:Hide()
        icon.count = count
        -- Timer text (top-left, tiny)
        local timer = icon:CreateFontString(nil, "OVERLAY")
        timer:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
        timer:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
        timer:SetTextColor(1, 1, 0.6, 1)
        timer:SetText("")
        icon.timer = timer
        icon:Hide()
        f.buffIcons[i] = icon
    end

    -- Debuff icons (3 slots, 20x20) — right side of the aura row, same vertical position.
    -- Debuffs grow right→left from the right edge (icon 1 is rightmost).
    f.debuffIcons = {}
    for i = 1, 3 do
        local icon = CreateFrame("Frame", nil, f, "BackdropTemplate")
        icon:SetSize(20, 20)
        icon:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(4 + (i - 1) * 22), -54)
        icon:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
        icon:SetBackdropColor(0.4, 0, 0, 0.8)   -- reddish bg for debuffs
        local tex = icon:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(icon)
        icon.tex = tex
        -- Cooldown swipe overlay
        local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
        cd:SetAllPoints(icon)
        cd:SetDrawEdge(false)
        cd:SetDrawBling(false)
        cd:SetHideCountdownNumbers(true)
        cd:Hide()
        icon.cooldown = cd
        -- Stack count
        local count = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
        count:SetTextColor(1, 0.3, 0.3, 1)
        count:Hide()
        icon.count = count
        -- Timer text (top-left, tiny)
        local timer = icon:CreateFontString(nil, "OVERLAY")
        timer:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
        timer:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
        timer:SetTextColor(1, 0.6, 0.6, 1)
        timer:SetText("")
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
    end

    -- Power / resource bar (6px, directly below health bar at y=-46)
    -- G-057: SetMinMaxValues before SetValue.
    -- Color and value set by UpdatePower on UNIT_POWER_UPDATE / UNIT_DISPLAYPOWER.
    local powerBar = CreateFrame("StatusBar", nil, f)
    powerBar:SetPoint("TOPLEFT",  f, "TOPLEFT",   4, -46)
    powerBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -46)
    powerBar:SetHeight(6)
    powerBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    powerBar:SetStatusBarColor(0.2, 0.5, 1.0, 1)  -- default: mana blue
    powerBar:SetMinMaxValues(0, 1)
    powerBar:SetValue(0)
    f.powerBar = powerBar

    -- Missing raid buff indicator (14x14, bottom-right corner of unit frame)
    -- Frame+Texture pattern to avoid StatusBar OVERLAY re-show bug.
    -- Red/orange tinted backdrop so the icon stands out against all health colors.
    -- Frame level +5: above overlay (+2), classIcon (+3), leaderCrown (+4) so it is
    -- never obscured even when the unit is dead.
    -- Hidden by default; shown by UpdateMissingBuff when the player owes a raid buff.
    local missingBuff = CreateFrame("Frame", nil, f, "BackdropTemplate")
    missingBuff:SetSize(14, 14)
    missingBuff:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
    missingBuff:SetFrameLevel(f:GetFrameLevel() + 5)
    missingBuff:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
    missingBuff:SetBackdropColor(0.8, 0.2, 0.0, 0.9)
    local missingBuffTex = missingBuff:CreateTexture(nil, "ARTWORK")
    missingBuffTex:SetAllPoints(missingBuff)
    missingBuff.tex = missingBuffTex
    missingBuff:Hide()
    f.missingBuffIcon = missingBuff

    -- Incoming resurrection / summon indicator (14×14, bottom-left corner).
    -- Reused for both: rez = green backdrop, summon = purple backdrop.
    -- They are mutually exclusive so sharing one frame is safe.
    local rezIcon = CreateFrame("Frame", nil, f, "BackdropTemplate")
    rezIcon:SetSize(14, 14)
    rezIcon:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 4)
    rezIcon:SetFrameLevel(f:GetFrameLevel() + 6)
    rezIcon:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
    rezIcon:SetBackdropColor(0.0, 0.8, 0.2, 0.9)
    local rezTex = rezIcon:CreateTexture(nil, "ARTWORK")
    rezTex:SetAllPoints(rezIcon)
    rezIcon.tex = rezTex
    rezIcon:Hide()
    f.rezIcon = rezIcon

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

    -- Raid target marker (20×20, top-right inside health bar area).
    -- Texture: UI-RaidTargetingIcons, 4×2 grid of markers.
    -- Shown/hidden by UpdateRaidMarker on RAID_TARGET_UPDATE.
    local raidMarker = CreateFrame("Frame", nil, f)
    raidMarker:SetSize(20, 20)
    raidMarker:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    raidMarker:SetFrameLevel(f:GetFrameLevel() + 6)
    local raidTex = raidMarker:CreateTexture(nil, "ARTWORK")
    raidTex:SetAllPoints(raidMarker)
    raidTex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    raidMarker.tex = raidTex
    raidMarker:Hide()
    f.raidMarker = raidMarker

    -- Target highlight ring: a border-only frame positioned 6px OUTSIDE f on all sides.
    -- Wraps visually around the unit frame instead of drawing inside it.
    -- No bgFile so the interior remains transparent — it is purely a ring.
    -- EnableMouse(false): extends beyond f's bounds so must not intercept clicks on
    -- neighbouring frames.  edgeSize 16 gives a visibly thick gold outline.
    local targetRing = CreateFrame("Frame", nil, f, "BackdropTemplate")
    targetRing:SetPoint("TOPLEFT",     f, "TOPLEFT",     -6,  6)
    targetRing:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  6, -6)
    targetRing:SetFrameLevel(f:GetFrameLevel() + 6)
    targetRing:EnableMouse(false)
    targetRing:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    targetRing:SetBackdropBorderColor(1, 0.82, 0, 1)
    targetRing:Hide()
    f.targetRing = targetRing

    return f
end
