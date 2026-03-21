-- CH_DPadParty.lua
-- Main module for CH_DPadParty — D-pad / numpad party frames for Steam Deck
------------------------------------------------------------------------

CHDPadParty = CHDPadParty or {}

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------

local UNIT_SLOTS = { "party1", "party2", "party3", "party4", "player" }

-- G-056: lookup table to guard UNIT_HEALTH / UNIT_POWER_UPDATE / UNIT_AURA events
local UNIT_LOOKUP = {
    party1 = true,
    party2 = true,
    party3 = true,
    party4 = true,
    player = true,
}

-- Role icon texture coordinates (G-052: "DAMAGER" not "DPS")
-- Texture: Interface\LFGFrame\UI-LFG-ICON-PORTRAITROLES (verified from DandersFrames)
-- SetTexCoord(left, right, top, bottom)
local ROLE_TEX_COORDS = {
    TANK    = { 0,        0.296875, 0.296875, 0.65     },
    HEALER  = { 0.296875, 0.59375,  0,        0.296875 },
    DAMAGER = { 0.296875, 0.59375,  0.296875, 0.65     },
}

-- Dispel type → border color.  dispelType in WoW 12.0 may be a string ("Magic") OR a
-- numeric enum value (Enum.DispelType: 1=Magic, 2=Curse, 3=Disease, 4=Poison).
-- Both keys are present so either form works.
local DISPEL_COLORS = {
    Magic   = { r = 0.20, g = 0.60, b = 1.00 },
    Curse   = { r = 0.60, g = 0.00, b = 1.00 },
    Poison  = { r = 0.00, g = 0.65, b = 0.00 },
    Disease = { r = 0.60, g = 0.40, b = 0.00 },
    [1]     = { r = 0.20, g = 0.60, b = 1.00 },
    [2]     = { r = 0.60, g = 0.00, b = 1.00 },
    [3]     = { r = 0.60, g = 0.40, b = 0.00 },
    [4]     = { r = 0.00, g = 0.65, b = 0.00 },
}

-- Default backdrop border color (restored when no dispellable debuff)
local BORDER_DEFAULT = { r = 0.3,  g = 0.3,  b = 0.3  }
local BORDER_TARGET  = { r = 1.0,  g = 0.82, b = 0.0  }  -- bright gold
local BORDER_AGGRO   = { r = 1.0,  g = 0.15, b = 0.0  }  -- bright red (threat >= 2)


-- Power type → bar color. UnitPowerType(unit) returns a numeric index (plain Lua number,
-- safe for table lookup). 0=Mana,1=Rage,2=Focus,3=Energy,6=RunicPower,8=LunarPower,
-- 13=Insanity,17=Fury,19=Essence. Unmapped types fall through to default.
local POWER_COLORS = {
    [0]  = { 0.2, 0.5,  1.0 },  -- Mana
    [1]  = { 1.0, 0.0,  0.0 },  -- Rage
    [2]  = { 1.0, 0.6,  0.0 },  -- Focus
    [3]  = { 1.0, 0.9,  0.0 },  -- Energy
    [6]  = { 0.0, 0.82, 1.0 },  -- Runic Power
    [8]  = { 0.6, 0.8,  1.0 },  -- Lunar Power
    [13] = { 0.4, 0.0,  0.8 },  -- Insanity
    [17] = { 0.8, 0.0,  1.0 },  -- Fury
    [19] = { 0.0, 1.0,  0.8 },  -- Essence
    default = { 0.2, 0.5, 1.0 },
}

-- Raid buff lookup: player class → buff they provide to the group.
-- Classes absent from this table have no trackable single raid buff; the
-- missing-buff indicator is suppressed for those players.
local RAID_BUFF_BY_CLASS = {
    PRIEST  = { spellID = 21562,  name = "Power Word: Fortitude" },
    MAGE    = { spellID = 1459,   name = "Arcane Intellect"      },
    DRUID   = { spellID = 1126,   name = "Mark of the Wild"      },
    WARRIOR = { spellID = 6673,   name = "Battle Shout"          },
    PALADIN = { spellID = 20217,  name = "Blessing of Kings"     },
    MONK    = { spellID = 116781, name = "Mystic Touch"          },
    SHAMAN  = { spellID = 462854, name = "Skyfury"               },
}
-- nil = not yet detected; false = player class has no raid buff to give
local _playerRaidBuff = nil

-- Range probe: C_Spell.IsSpellInRange(spellID, unit) returns plain 1/0/nil
-- (no secret values).  We detect which spell the player knows at login by
-- testing against "player" (always in range of yourself → returns 1 if known).
-- nil = not yet detected; false = no usable probe spell found for this class.
local _rangeProbeSpell = nil

-- Ordered by class prevalence.  40-yard spells preferred; 30-yard fallbacks
-- for pure-melee classes that have no long-range ability.
local RANGE_PROBE_CANDIDATES = {
    -- Healer 40yd
    139,    -- Renew            (Priest)
    2061,   -- Flash Heal       (Priest)
    774,    -- Rejuvenation     (Druid)
    8936,   -- Regrowth         (Druid)
    331,    -- Healing Wave     (Shaman)
    8004,   -- Healing Surge    (Shaman)
    116670, -- Vivify           (Monk)
    19750,  -- Flash of Light   (Paladin)
    82326,  -- Holy Light       (Paladin)
    361469, -- Emerald Blossom  (Evoker)
    -- Ranged DPS 40yd
    75,     -- Auto Shot        (Hunter)
    116,    -- Frostbolt        (Mage)
    133,    -- Fireball         (Mage)
    686,    -- Shadow Bolt      (Warlock)
    198,    -- Shoot            (wand, any class, 35yd)
    -- Melee-class 30yd fallbacks
    47541,  -- Death Coil       (Death Knight)
    57755,  -- Heroic Throw     (Warrior)
    185123, -- Throw Glaive     (Demon Hunter)
    114014, -- Shuriken Toss    (Rogue)
}

local function DetectRangeProbeSpell()
    _rangeProbeSpell = false  -- assume no probe unless found
    for _, id in ipairs(RANGE_PROBE_CANDIDATES) do
        local ok, result = pcall(C_Spell.IsSpellInRange, id, "player")
        if ok and result ~= nil then   -- non-nil → player knows this spell
            _rangeProbeSpell = id
            break
        end
    end
end

-- SetPoint offsets: CENTER of each unit frame relative to root CENTER
-- Layout mirrors a numpad: party1=Num8(top), party2=Num4(left),
-- party3=Num6(right), party4=Num2(bottom), player=below Num2
-- Spacing recalculated for 74px frame height (37px half-height) with 8px gaps.
-- Adjacent slot spacing: half-height(37) + gap(8) + half-height(37) = 82.
-- Player offset: 2 × 82 = 164.
-- Horizontal: frame width 200px, half-width(100) + gap(4) = 104 (unchanged).
local OFFSETS = {
    party1 = {   0,   82 },
    party2 = { -104,   0 },
    party3 = {  104,   0 },
    party4 = {   0,  -82 },
    player = {   0, -164 },
}

-- Test mode fake data
local TEST_NAMES    = { "Thorvald", "Lirien",  "Kazmok",  "Solvara", "Drakmis" }
local TEST_CLASSES  = { "WARRIOR",  "PALADIN", "HUNTER",  "PRIEST",  "MAGE"    }
local TEST_ROLES    = { "TANK",     "HEALER",  "DAMAGER", "HEALER",  "DAMAGER" }
local TEST_HP_FRACS    = { 1.0, 0.74, 0.48, 0.27, 0.10 }
local TEST_POWER_TYPES = { 1,   3,   2,   0,   0   }  -- Rage, Energy, Focus, Mana, Mana
local TEST_POWER_FRACS = { 0.6, 0.9, 0.45, 1.0, 0.3 }

-- Always-loaded spell icon textures for fake auras
local FAKE_BUFF_ICONS = {
    "Interface\\Icons\\Spell_Holy_PowerWordShield",
    "Interface\\Icons\\Spell_Nature_Rejuvenation",
    "Interface\\Icons\\Spell_Holy_ForbearancePaladin",
}
local FAKE_DEBUFF_ICONS = {
    "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
    "Interface\\Icons\\Spell_Nature_Slow",
    "Interface\\Icons\\Ability_Warrior_Sunder",
}

------------------------------------------------------------------------
-- Frame storage
------------------------------------------------------------------------

CHDPadParty.frames = CHDPadParty.frames or {}

------------------------------------------------------------------------
-- Alpha helper  (health fade × OOR fade)
------------------------------------------------------------------------

-- Each frame caches _healthAlpha (1.0 normal, 0.6 at full HP) and
-- _oorAlpha (1.0 in range, 0.4 OOR).  Combined product is applied once.
local function ApplyCombinedAlpha(f)
    f:SetAlpha((f._healthAlpha or 1.0) * (f._oorAlpha or 1.0))
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------

function CHDPadParty.Init()
    CHDPadParty.BuildRootFrame()
    local root = CHDPadParty.root

    -- G-054: ClearAllPoints before SetPoint on restore
    local pos = CHDPadPartyDB.position
    root:ClearAllPoints()
    root:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)

    -- Build unit frames positioned via SetPoint offsets from root
    for _, unit in ipairs(UNIT_SLOTS) do
        local f = CHDPadParty.BuildUnitFrame(unit)
        local ox, oy = OFFSETS[unit][1], OFFSETS[unit][2]
        f:SetPoint("CENTER", root, "CENTER", ox, oy)
        CHDPadParty.frames[unit] = f
    end

    -- Apply saved lock state (G-064: SetMovable + RegisterForDrag, never EnableMouse)
    if CHDPadPartyDB.locked then
        CHDPadParty.root:SetMovable(false)
        for _, unit in ipairs(UNIT_SLOTS) do
            local f = CHDPadParty.frames[unit]
            if f and f.secureBtn then
                f.secureBtn:RegisterForDrag()
            end
        end
    end

    -- Sync drag state from saved lock state.
    -- secureBtn visibility is managed by RegisterUnitWatch — never touch it from here.
    -- When locked: drag disabled, f is mouse-transparent, secureBtn intercepts clicks.
    -- When unlocked: drag enabled. secureBtn (always shown when unit exists) still
    -- intercepts clicks, but intentional drag movements also work — both coexist fine.
    do
        local locked = CHDPadPartyDB.locked
        for _, unit in ipairs(UNIT_SLOTS) do
            local fr = CHDPadParty.frames[unit]
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
    end

    -- Blizzard party frames: we intentionally do NOT suppress them here.
    -- Calling ANY method on CompactPartyFrame / CompactRaidFrameManager from insecure
    -- addon code (UnregisterAllEvents, Hide, hooksecurefunc) permanently taints our
    -- addon's execution context for the entire session.  Every subsequent call to
    -- UnitHealthPercent / UnitHealth from our event handlers then returns a tainted
    -- secret number, breaking health bar updates.  It also strips events WoW uses for
    -- group-chat channel tracking, causing "not in a party" / "invalid channel" spam.
    -- Players can disable the default party frames via Interface → Display settings.

    root:SetScale(CHDPadPartyDB.scale or 1.0)

    CHDPadParty.BuildMinimapButton()
    CHDPadParty.BuildSettingsPanel()
    CHDPadParty.RefreshSettingsButtons()

    CHDPadParty.UpdateAll()
    CHDPadParty.UpdateVisibility()

    -- If test mode was saved from a previous session, repopulate fake data now
    if CHDPadPartyDB.testMode then
        CHDPadParty.ApplyTestMode()
    end
end

------------------------------------------------------------------------
-- UpdateFrame
------------------------------------------------------------------------

function CHDPadParty.UpdateFrame(unit)
    -- In test mode, party1-4 show fake data — skip live updates for them.
    -- The player slot always shows real character data even in test mode.
    if CHDPadPartyDB and CHDPadPartyDB.testMode and unit ~= "player" then return end

    local f = CHDPadParty.frames[unit]
    if not f then return end

    local ok, err = pcall(function()
        -- Hide if unit does not exist
        if not UnitExists(unit) then
            f:Hide()
            return
        end
        f:Show()

        -- Health bar and HP% text.
        -- WoW 12.0+ secret numbers: UnitHealth/UnitHealthMax cannot be used in Lua
        -- arithmetic (throws "secret number" error in combat). DandersFrames pattern:
        -- use UnitHealthPercent(unit, true, CurveConstants.ScaleTo100) which returns a
        -- plain 0-100 float safe for any use. Normalise the bar to 0-100 to match.
        -- G-057: SetMinMaxValues before SetValue.
        -- G-070: UnitHealthPercent returns a secret number in tainted contexts.
        -- Pass the raw value directly to SetValue (C function accepts secret numbers).
        -- Wrap math.floor separately; only cache successfully floored integers.
        -- hpPct is always a plain integer after this block (safe for string concat).
        local hpPct = f._lastHpPct or 100
        do
            -- Raw HP range so healPredictBar can share the same range.
            -- UnitHealthMax / UnitHealth are secret numbers; pass to C functions only.
            local maxOk, maxHP = pcall(UnitHealthMax, unit)
            local hpOk,  hp    = pcall(UnitHealth, unit)
            if maxOk and maxHP and hpOk and hp then
                f.healthBar:SetMinMaxValues(0, maxHP)
                f.healthBar:SetValue(hp)
            else
                -- Taint/unavailability fallback: raw HP pcall failed this cycle.
                -- Use cached percent so the bar always receives a SetValue call.
                f.healthBar:SetMinMaxValues(0, 100)
                f.healthBar:SetValue(f._lastHpPct or 0)
            end
            -- UnitHealthPercent is still needed for the human-readable hpText display.
            local pctOk, raw = pcall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
            if pctOk and raw then
                local floorOk, pct = pcall(math.floor, raw)
                if floorOk then
                    f._lastHpPct = pct
                    hpPct = pct
                end
            end
        end

        -- Health fade disabled: subtle alpha reduction at full HP caused frames to
        -- appear permanently greyed out at normal health. Re-enable when a better
        -- visual treatment is designed (e.g. border dim rather than whole-frame alpha).
        f._healthAlpha = 1.0
        ApplyCombinedAlpha(f)

        -- Class icon (G-055: hide for disconnected/unknown class; health bar stays green always)
        local _, classFile = UnitClass(unit)
        if f.classIcon then
            local tcoords = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
            if tcoords then
                f.classIcon.tex:SetTexture("Interface\\WorldStateFrame\\Icons-Classes")
                f.classIcon.tex:SetTexCoord(unpack(tcoords))
                f.classIcon:Show()
            else
                f.classIcon:Hide()
            end
        end

        -- Name
        local name = UnitName(unit) or unit
        f.nameText:SetText(name)

        -- HP percentage text
        f.hpText:SetText(hpPct .. "%")

        -- Role icons (G-052: DAMAGER / HEALER / TANK; NONE hides slot 1)
        -- Slot 1 = LFG role. Hide all slots first then populate from left.
        for i = 1, #f.roleIcons do f.roleIcons[i]:Hide() end
        local role   = UnitGroupRolesAssigned(unit)
        local coords = ROLE_TEX_COORDS[role]
        if coords and f.roleIcons[1] then
            f.roleIcons[1].tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            f.roleIcons[1]:Show()
        end

        -- Leader crown (above class icon)
        if f.leaderCrown then
            if UnitIsGroupLeader(unit) then
                f.leaderCrown:Show()
            else
                f.leaderCrown:Hide()
            end
        end

        -- Dead / ghost / offline / AFK overlay (G-058: ghost before dead)
        local overlayLabel = ""
        if not UnitIsConnected(unit) then
            overlayLabel = "Offline"
        elseif UnitIsGhost(unit) then
            overlayLabel = "Ghost"
        elseif UnitIsDead(unit) then
            overlayLabel = "Dead"
        elseif UnitIsAFK(unit) then
            overlayLabel = "AFK"
        end

        if overlayLabel ~= "" then
            f.overlay.label:SetText(overlayLabel)
            f.overlay:Show()
            f.healthBar:SetValue(0)
        else
            f.overlay:Hide()
        end

        -- Aura icons (G-067: no-op if test mode active)
        CHDPadParty.UpdateAuras(unit)
    end)
    if not ok then
        print("|cffff4444CH_DPadParty|r UpdateFrame(" .. unit .. "): " .. tostring(err))
    end
end

------------------------------------------------------------------------
-- UpdateVisibility  (G-061: hide party1-4 when in raid or solo)
------------------------------------------------------------------------

function CHDPadParty.UpdateVisibility()
    -- Don't hide frames that test mode is intentionally showing
    if CHDPadPartyDB and CHDPadPartyDB.testMode then return end

    local inRaid  = IsInRaid()
    local inGroup = IsInGroup()

    for _, unit in ipairs(UNIT_SLOTS) do
        local f = CHDPadParty.frames[unit]
        if not f then
            -- frame not yet built; skip
        elseif unit == "player" then
            f:Show()
        elseif inRaid or not inGroup then
            -- G-061: party1-4 return nil in raid; hide when solo too
            f:Hide()
        else
            if UnitExists(unit) then
                f:Show()
            else
                f:Hide()
            end
        end
    end
end

------------------------------------------------------------------------
-- UpdateAll
------------------------------------------------------------------------

function CHDPadParty.UpdateAll()
    for _, unit in ipairs(UNIT_SLOTS) do
        CHDPadParty.UpdateFrame(unit)
        CHDPadParty.UpdateHealPrediction(unit)
        CHDPadParty.UpdateAbsorbs(unit)
        CHDPadParty.UpdatePower(unit)
        CHDPadParty.UpdateAuras(unit)
        CHDPadParty.UpdateMissingBuff(unit)
        CHDPadParty.UpdateRange(unit)
        CHDPadParty.UpdateRez(unit)
        CHDPadParty.UpdateRaidMarker(unit)
    end
end

------------------------------------------------------------------------
-- UpdateBorder  (target gold > dispel color > default grey)
------------------------------------------------------------------------

function CHDPadParty.UpdateBorder(unit)
    local f = CHDPadParty.frames[unit]
    if not f then return end

    local isTarget = UnitIsUnit(unit, "target")

    -- Target ring: separate frame that wraps outside f — show when targeted, hide otherwise.
    if f.targetRing then
        if isTarget then f.targetRing:Show() else f.targetRing:Hide() end
    end

    -- f's own border priority: aggro red > dispel color > default grey
    -- UnitThreatSituation: 0=no threat, 1=low, 2=pulling aggro, 3=tanking
    local threat
    if UnitExists(unit) then
        local ok, t = pcall(UnitThreatSituation, unit)
        if ok then threat = t end
    end

    local c
    if threat and threat >= 2 then
        c = BORDER_AGGRO
    elseif f._dispelColor then
        c = f._dispelColor
    else
        c = BORDER_DEFAULT
    end
    f:SetBackdropBorderColor(c.r, c.g, c.b, 1)
end

------------------------------------------------------------------------
-- UpdateAuras
------------------------------------------------------------------------

function CHDPadParty.UpdateAuras(unit)
    -- G-067: skip if test mode active — fake data owns the aura slots
    if CHDPadPartyDB and CHDPadPartyDB.testMode then return end

    local f = CHDPadParty.frames[unit]
    if not f then return end

    pcall(function()
        -- Buffs (up to 3 shown, combat-relevant only)
        -- Skip permanent auras (duration == 0: passive, stance, taxi, flight form)
        -- and very long buffs (> 1800s / 30 min: food, flask, well-fed, raid buffs).
        -- Only show auras with 0 < duration <= 1800 (procs, HoTs, defensive CDs, etc.)
        local shown = 0
        for i = 1, 40 do
            if shown >= 3 then break end
            local ok2, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
            if not ok2 or not aura then break end
            if aura.icon and aura.duration and aura.duration > 0 and aura.duration <= 1800 then
                shown = shown + 1
                local icon = f.buffIcons[shown]
                icon.tex:SetTexture(aura.icon)
                -- G-066: stack count is aura.applications, not aura.count
                local apps = aura.applications or 0
                if apps > 1 then
                    icon.count:SetText(apps)
                    icon.count:Show()
                else
                    icon.count:Hide()
                end
                -- Cooldown swipe + expiry cache for timer ticker
                local expire = aura.expirationTime
                if icon.cooldown and expire and expire > 0 then
                    CooldownFrame_Set(icon.cooldown, expire - aura.duration, aura.duration, 1)
                    icon.cooldown:Show()
                elseif icon.cooldown then
                    icon.cooldown:Hide()
                end
                icon._expireTime = (expire and expire > 0) and expire or nil
                icon:Show()
            end
        end
        for i = shown + 1, 3 do
            local icon = f.buffIcons[i]
            icon:Hide()
            icon._expireTime = nil
            if icon.cooldown then icon.cooldown:Hide() end
            if icon.timer then icon.timer:SetText("") end
        end

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
    end)
end

------------------------------------------------------------------------
-- UpdateMissingBuff
------------------------------------------------------------------------

function CHDPadParty.UpdateMissingBuff(unit)
    local f = CHDPadParty.frames[unit]
    if not f or not f.missingBuffIcon then return end

    -- Never show on the player's own frame
    if unit == "player" then
        f.missingBuffIcon:Hide()
        return
    end

    -- Lazy class detection: deferred because UnitClass("player") may return nil
    -- during early loading before the player object is fully initialised.
    if _playerRaidBuff == nil then
        local _, classFile = UnitClass("player")
        if classFile then
            _playerRaidBuff = RAID_BUFF_BY_CLASS[classFile] or false
        else
            f.missingBuffIcon:Hide()
            return
        end
    end

    -- Player class provides no trackable raid buff
    if not _playerRaidBuff then
        f.missingBuffIcon:Hide()
        return
    end

    local spellID = _playerRaidBuff.spellID

    -- Check whether the unit already has the buff (pcall for taint safety)
    local hasBuff = false
    local ok, result = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, spellID, "HELPFUL")
    if ok and result then
        hasBuff = true
    end

    if hasBuff then
        f.missingBuffIcon:Hide()
    else
        local iconOk, tex = pcall(C_Spell.GetSpellTexture, spellID)
        if iconOk and tex then
            f.missingBuffIcon.tex:SetTexture(tex)
        end
        f.missingBuffIcon:Show()
    end
end

------------------------------------------------------------------------
-- UpdatePower
------------------------------------------------------------------------

function CHDPadParty.UpdatePower(unit)
    if CHDPadPartyDB and CHDPadPartyDB.testMode and unit ~= "player" then return end
    local f = CHDPadParty.frames[unit]
    if not f or not f.powerBar then return end

    local ok, err = pcall(function()
        if not UnitExists(unit) then
            f.powerBar:SetMinMaxValues(0, 1)
            f.powerBar:SetValue(0)
            return
        end

        -- UnitPowerType returns a plain Lua number — safe for table lookup
        local powerType = UnitPowerType(unit)
        local color = POWER_COLORS[powerType] or POWER_COLORS.default
        f.powerBar:SetStatusBarColor(color[1], color[2], color[3], 1)

        -- UnitPowerMax / UnitPower are secret numbers: pass to C functions only (G-057)
        local maxOk, maxPow = pcall(UnitPowerMax, unit)
        local powOk, pow    = pcall(UnitPower, unit)
        if maxOk and maxPow and powOk and pow then
            f.powerBar:SetMinMaxValues(0, maxPow)
            f.powerBar:SetValue(pow)
        else
            f.powerBar:SetMinMaxValues(0, 1)
            f.powerBar:SetValue(0)
        end
    end)
    if not ok then
        print("|cffff4444CH_DPadParty|r UpdatePower(" .. unit .. "): " .. tostring(err))
    end
end

------------------------------------------------------------------------
-- UpdateHealPrediction
------------------------------------------------------------------------

function CHDPadParty.UpdateHealPrediction(unit)
    if CHDPadPartyDB and CHDPadPartyDB.testMode and unit ~= "player" then return end
    local f = CHDPadParty.frames[unit]
    if not f or not f.healPredictBar then return end

    local ok, err = pcall(function()
        if not UnitExists(unit) then
            f.healPredictBar:SetMinMaxValues(0, 1)
            f.healPredictBar:SetValue(0)
            return
        end

        -- Primary path: use the cached calculator (created once in BuildUnitFrame).
        -- UnitGetDetailedHealPrediction populates it with health + incoming heal data on
        -- the C side. calc:GetPredictedHealth() returns current health + capped incoming
        -- heals as a secret number on the same raw HP scale as UnitHealthMax.
        -- No Lua arithmetic on secret numbers anywhere in this path.
        local calcOk = pcall(function()
            local calc = f.healPredictCalc
            UnitGetDetailedHealPrediction(unit, nil, calc)
            -- GetPredictedHealth returns a secret number in the same raw HP range as
            -- UnitHealthMax — safe to pass directly to SetValue.
            -- OPEN QUESTION: verify method name at runtime (see PLAN.md Open Questions).
            local maxOk, maxHP = pcall(UnitHealthMax, unit)
            if maxOk and maxHP then
                f.healPredictBar:SetMinMaxValues(0, maxHP)
                f.healPredictBar:SetValue(calc:GetPredictedHealth())
            end
        end)

        -- Fallback: if calculator API is absent or throws, hide the bar silently.
        -- Do NOT attempt Lua arithmetic (UnitHealth + UnitGetIncomingHeals) as fallback —
        -- that throws "attempt to perform arithmetic on a secret number" in WoW 12.0.
        if not calcOk then
            f.healPredictBar:SetMinMaxValues(0, 1)
            f.healPredictBar:SetValue(0)
        end
    end)
    if not ok then
        print("|cffff4444CH_DPadParty|r UpdateHealPrediction(" .. unit .. "): " .. tostring(err))
    end
end

------------------------------------------------------------------------
-- UpdateAbsorbs
------------------------------------------------------------------------

function CHDPadParty.UpdateAbsorbs(unit)
    if CHDPadPartyDB and CHDPadPartyDB.testMode and unit ~= "player" then return end
    local f = CHDPadParty.frames[unit]
    if not f then return end

    pcall(function()
        if not UnitExists(unit) then
            if f.absorbBar     then f.absorbBar:SetMinMaxValues(0, 1);     f.absorbBar:SetValue(0)     end
            if f.healAbsorbBar then f.healAbsorbBar:SetMinMaxValues(0, 1); f.healAbsorbBar:SetValue(0) end
            return
        end

        local maxHP = UnitHealthMax(unit)   -- secret number; passed to C functions only

        -- Damage absorb (shields: Power Word: Shield, Ice Barrier, Devotion Aura, etc.)
        if f.absorbBar then
            local absorb = UnitGetTotalAbsorbs(unit) or 0
            f.absorbBar:SetMinMaxValues(0, maxHP)
            f.absorbBar:SetValue(absorb)
        end

        -- Heal absorb (Necrotic M+ affix, Mangle, Plaguebringer, etc.)
        if f.healAbsorbBar then
            local healAbsorb = UnitGetTotalHealAbsorbs(unit) or 0
            f.healAbsorbBar:SetMinMaxValues(0, maxHP)
            f.healAbsorbBar:SetValue(healAbsorb)
        end
    end)
end

------------------------------------------------------------------------
-- UpdateRange
------------------------------------------------------------------------

function CHDPadParty.UpdateRange(unit)
    -- G-RANGE-1: skip in test mode — fake frames always show at full alpha
    if CHDPadPartyDB and CHDPadPartyDB.testMode then return end

    local f = CHDPadParty.frames[unit]
    if not f then return end

    -- G-RANGE-2: skip if frame not shown — avoids wasted API calls
    if not f:IsShown() then return end

    -- G-RANGE-3: player is always in range
    if unit == "player" then
        f._oorAlpha = 1.0
        ApplyCombinedAlpha(f)
        return
    end

    -- G-RANGE-4: Use C_Spell.IsSpellInRange with the cached probe spell.
    -- Returns plain Lua 1 (in range) / 0 (OOR) / nil (can't determine).
    -- No secret values.  Default to in-range on any failure or missing probe.
    local inRange = true
    if _rangeProbeSpell then
        local ok, result = pcall(C_Spell.IsSpellInRange, _rangeProbeSpell, unit)
        if ok and result == 0 then
            inRange = false
        end
        -- result == 1 → in range; nil → indeterminate → assume in-range
    end

    f._oorAlpha = inRange and 1.0 or 0.4
    ApplyCombinedAlpha(f)
end

------------------------------------------------------------------------
-- UpdateRez  (incoming resurrection or summon indicator)
------------------------------------------------------------------------

function CHDPadParty.UpdateRez(unit)
    if CHDPadPartyDB and CHDPadPartyDB.testMode then return end
    local f = CHDPadParty.frames[unit]
    if not f or not f.rezIcon then return end

    local hasRez, hasSummon = false, false
    local ok, r = pcall(UnitHasIncomingResurrection, unit)
    if ok and r then hasRez = true end
    if not hasRez and C_IncomingSummon then
        local ok2, s = pcall(C_IncomingSummon.HasIncomingSummon, unit)
        if ok2 and s then hasSummon = true end
    end

    if hasRez then
        f.rezIcon:SetBackdropColor(0.0, 0.8, 0.2, 0.9)  -- green
        local ok2, tex = pcall(C_Spell.GetSpellTexture, 2006)  -- Resurrection
        if ok2 and tex then f.rezIcon.tex:SetTexture(tex) end
        f.rezIcon:Show()
    elseif hasSummon then
        f.rezIcon:SetBackdropColor(0.55, 0.0, 0.82, 0.9)  -- purple
        local ok2, tex = pcall(C_Spell.GetSpellTexture, 698)  -- Ritual of Summoning
        if ok2 and tex then f.rezIcon.tex:SetTexture(tex) end
        f.rezIcon:Show()
    else
        f.rezIcon:Hide()
    end
end

------------------------------------------------------------------------
-- UpdateRaidMarker
------------------------------------------------------------------------

function CHDPadParty.UpdateRaidMarker(unit)
    if CHDPadPartyDB and CHDPadPartyDB.testMode then return end
    local f = CHDPadParty.frames[unit]
    if not f or not f.raidMarker then return end

    local idx = GetRaidTargetIndex(unit)
    if idx then
        -- UI-RaidTargetingIcons: 4 columns × 2 rows, each cell 0.25 wide × 0.5 tall
        local col = (idx - 1) % 4
        local row = math.floor((idx - 1) / 4)
        f.raidMarker.tex:SetTexCoord(col * 0.25, (col + 1) * 0.25, row * 0.5, (row + 1) * 0.5)
        f.raidMarker:Show()
    else
        f.raidMarker:Hide()
    end
end

------------------------------------------------------------------------
-- ApplyTestMode
------------------------------------------------------------------------

function CHDPadParty.ApplyTestMode()
    for idx, unit in ipairs(UNIT_SLOTS) do
        if unit == "player" then
            -- Player always shows real character data — never overwrite with fake
            CHDPadParty.UpdateFrame("player")
        else
            local f = CHDPadParty.frames[unit]
            if f then
                f:Show()
                f._healthAlpha = 1.0
                f._oorAlpha    = 1.0
                f:SetAlpha(1.0)  -- G-RANGE-6: restore full alpha; ticker is suppressed in test mode
                f.overlay:Hide()

                -- Health
                local frac = TEST_HP_FRACS[idx] or 1.0
                f.healthBar:SetMinMaxValues(0, 100)
                f.healthBar:SetValue(frac * 100)

                -- Heal prediction bar: fake teal overshoot in test mode.
                -- Shares the same 0–100 normalised range as healthBar in test mode.
                -- Value = current health% + fake incoming 30%, capped at 100.
                if f.healPredictBar then
                    local fakePredict = math.min(100, frac * 100 + 30)
                    f.healPredictBar:SetMinMaxValues(0, 100)
                    f.healPredictBar:SetValue(fakePredict)
                end

                -- Class icon
                local classFile = TEST_CLASSES[idx] or "WARRIOR"
                if f.classIcon then
                    local tcoords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
                    if tcoords then
                        f.classIcon.tex:SetTexture("Interface\\WorldStateFrame\\Icons-Classes")
                        f.classIcon.tex:SetTexCoord(unpack(tcoords))
                        f.classIcon:Show()
                    end
                end

                -- Name and HP%
                f.nameText:SetText(TEST_NAMES[idx] or ("Test" .. idx))
                f.hpText:SetText(math.floor(frac * 100) .. "%")

                -- Role icons (slot 1 = LFG role; hide rest)
                for i = 1, #f.roleIcons do f.roleIcons[i]:Hide() end
                local role   = TEST_ROLES[idx] or "DAMAGER"
                local coords = ROLE_TEX_COORDS[role]
                if coords and f.roleIcons[1] then
                    f.roleIcons[1].tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
                    f.roleIcons[1]:Show()
                end
                -- Show leader crown on the first test slot for preview
                if f.leaderCrown then
                    if idx == 1 then f.leaderCrown:Show() else f.leaderCrown:Hide() end
                end

                -- Fake buff icons
                for i = 1, 3 do
                    local icon = f.buffIcons[i]
                    icon.tex:SetTexture(FAKE_BUFF_ICONS[i])
                    icon.count:Hide()
                    icon:Show()
                end

                -- Fake debuff icons
                for i = 1, 3 do
                    local icon = f.debuffIcons[i]
                    icon.tex:SetTexture(FAKE_DEBUFF_ICONS[i])
                    icon.count:Hide()
                    icon:Show()
                end

                -- Power bar
                if f.powerBar then
                    local powerType = TEST_POWER_TYPES[idx] or 0
                    local color = POWER_COLORS[powerType] or POWER_COLORS.default
                    f.powerBar:SetStatusBarColor(color[1], color[2], color[3], 1)
                    local pfrac = TEST_POWER_FRACS[idx] or 1.0
                    f.powerBar:SetMinMaxValues(0, 100)
                    f.powerBar:SetValue(pfrac * 100)
                end

                -- Missing buff indicator preview: show on slot 2 only so the layout
                -- is visible without every frame appearing alarming in test mode.
                if f.missingBuffIcon then
                    if idx == 2 then
                        local iconOk, tex = pcall(C_Spell.GetSpellTexture, 21562)
                        if iconOk and tex then
                            f.missingBuffIcon.tex:SetTexture(tex)
                        end
                        f.missingBuffIcon:Show()
                    else
                        f.missingBuffIcon:Hide()
                    end
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- Event Handler
------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame", "CHDPadPartyEventFrame", UIParent)

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")         -- G-053: not PARTY_MEMBERS_CHANGED
eventFrame:RegisterEvent("UNIT_HEALTH")
eventFrame:RegisterEvent("UNIT_POWER_UPDATE")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("PLAYER_FLAGS_CHANGED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UNIT_HEAL_PREDICTION")        -- incoming heals changed
eventFrame:RegisterEvent("UNIT_DISPLAYPOWER")           -- power type changed (druid forms, etc.)
eventFrame:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")  -- damage absorb shields changed
eventFrame:RegisterEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED") -- heal absorbs (Necrotic) changed
eventFrame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE") -- aggro/threat state changed
eventFrame:RegisterEvent("INCOMING_RESURRECT_CHANGED")  -- incoming rez changed
eventFrame:RegisterEvent("INCOMING_SUMMON_CHANGED")     -- incoming summon changed
eventFrame:RegisterEvent("RAID_TARGET_UPDATE")          -- raid marker assigned/cleared

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= "CH_DPadParty" then return end

        -- DB init: each field individually to avoid shared-table-reference bug
        if type(CHDPadPartyDB) ~= "table" then
            CHDPadPartyDB = {}
        end
        if type(CHDPadPartyDB.position) ~= "table" then
            CHDPadPartyDB.position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }
        end
        if CHDPadPartyDB.visible    == nil then CHDPadPartyDB.visible    = true  end
        if CHDPadPartyDB.locked     == nil then CHDPadPartyDB.locked     = true  end
        if CHDPadPartyDB.minimapPos == nil then CHDPadPartyDB.minimapPos = 210   end
        if CHDPadPartyDB.scale      == nil then CHDPadPartyDB.scale      = 1.0   end
        -- testMode always resets to false on load — it is a session-only preview
        -- tool, not a persistent setting. Saving it caused fake data to show on
        -- the next login even when the player is in a real party.
        CHDPadPartyDB.testMode = false
        -- settingsX / settingsY default to nil (panel uses default center position)

        CHDPadParty.Init()

        if CHDPadPartyDB.visible then
            CHDPadParty.root:Show()
        else
            CHDPadParty.root:Hide()
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        CHDPadParty.UpdateVisibility()
        CHDPadParty.UpdateAll()

    elseif event == "UNIT_HEALTH" then
        -- G-056: only process tracked units
        if UNIT_LOOKUP[arg1] then
            CHDPadParty.UpdateFrame(arg1)
        end

    elseif event == "UNIT_POWER_UPDATE" then
        if UNIT_LOOKUP[arg1] then
            CHDPadParty.UpdateFrame(arg1)
            CHDPadParty.UpdatePower(arg1)
        end

    elseif event == "UNIT_DISPLAYPOWER" then
        -- Power type changed (druid shifting, etc.) — update bar color and value
        if arg1 and UNIT_LOOKUP[arg1] then
            CHDPadParty.UpdatePower(arg1)
        end

    elseif event == "UNIT_AURA" then
        -- G-065: guard on arg1 before any work
        -- G-067: skip entirely if test mode active
        if UNIT_LOOKUP[arg1] and not (CHDPadPartyDB and CHDPadPartyDB.testMode) then
            CHDPadParty.UpdateAuras(arg1)
            CHDPadParty.UpdateMissingBuff(arg1)
        end

    elseif event == "PLAYER_TARGET_CHANGED" then
        -- No arg1 — loop all slots to clear old target and highlight new one
        for _, unit in ipairs(UNIT_SLOTS) do
            CHDPadParty.UpdateBorder(unit)
        end

    elseif event == "PLAYER_FLAGS_CHANGED" then
        -- Catches AFK, dead, ghost transitions
        if UNIT_LOOKUP[arg1] then
            CHDPadParty.UpdateFrame(arg1)
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        CHDPadParty.UpdateVisibility()
        CHDPadParty.UpdateAll()
        -- Re-position minimap button after zone transitions
        if CHDPadParty.minimapBtn then
            CHDPadParty.UpdateMinimapButtonPos()
        end
        -- Detect which spell to use for range probing (class-specific, done once).
        -- Re-runs on zone transition in case talents changed the spell availability.
        DetectRangeProbeSpell()

        -- G-RANGE-5: range ticker created here, not in Init — unit data unavailable
        -- at ADDON_LOADED time. Guard prevents stacking on every zone transition.
        if not CHDPadParty.rangeTicker then
            CHDPadParty.rangeTicker = C_Timer.NewTicker(0.5, function()
                for _, unit in ipairs(UNIT_SLOTS) do
                    CHDPadParty.UpdateRange(unit)
                end
            end)
        end
        -- Timer ticker: refreshes duration text on visible aura icons every second.
        if not CHDPadParty.timerTicker then
            CHDPadParty.timerTicker = C_Timer.NewTicker(1, function()
                local now = GetTime()
                for _, unit in ipairs(UNIT_SLOTS) do
                    local f = CHDPadParty.frames[unit]
                    if f then
                        for _, ilist in ipairs({ f.buffIcons, f.debuffIcons }) do
                            for _, icon in ipairs(ilist) do
                                if icon:IsShown() and icon._expireTime and icon.timer then
                                    local rem = icon._expireTime - now
                                    if rem > 0 then
                                        if rem >= 3600 then
                                            icon.timer:SetText(math.floor(rem / 3600) .. "h")
                                        elseif rem >= 60 then
                                            icon.timer:SetText(math.floor(rem / 60) .. "m")
                                        else
                                            icon.timer:SetText(math.floor(rem))
                                        end
                                    else
                                        icon.timer:SetText("")
                                    end
                                elseif icon.timer then
                                    icon.timer:SetText("")
                                end
                            end
                        end
                    end
                end
            end)
        end

    elseif event == "UNIT_HEAL_PREDICTION" then
        if UNIT_LOOKUP[arg1] then
            CHDPadParty.UpdateHealPrediction(arg1)
        end

    elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" then
        if UNIT_LOOKUP[arg1] then
            CHDPadParty.UpdateAbsorbs(arg1)
        end

    elseif event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
        if UNIT_LOOKUP[arg1] then
            CHDPadParty.UpdateAbsorbs(arg1)
        end

    elseif event == "UNIT_THREAT_SITUATION_UPDATE" then
        if arg1 and UNIT_LOOKUP[arg1] then
            CHDPadParty.UpdateBorder(arg1)
        end

    elseif event == "INCOMING_RESURRECT_CHANGED" or event == "INCOMING_SUMMON_CHANGED" then
        if arg1 and UNIT_LOOKUP[arg1] then
            CHDPadParty.UpdateRez(arg1)
        end

    elseif event == "RAID_TARGET_UPDATE" then
        -- Fires with no unit arg — refresh all frames
        for _, unit in ipairs(UNIT_SLOTS) do
            CHDPadParty.UpdateRaidMarker(unit)
        end
    end
end)

------------------------------------------------------------------------
-- Slash Command  /chdpad [show|hide|toggle|settings]
------------------------------------------------------------------------

SLASH_CHDPADPARTY1 = "/chdpad"

SlashCmdList["CHDPADPARTY"] = function(msg)
    local root = CHDPadParty.root
    if not root then return end

    local cmd = strtrim(msg):lower()

    if cmd == "show" then
        root:Show()
        CHDPadPartyDB.visible = true
        print("|cff00ff00CH_DPadParty:|r Frames shown.")

    elseif cmd == "hide" then
        root:Hide()
        CHDPadPartyDB.visible = false
        print("|cff00ff00CH_DPadParty:|r Frames hidden.")

    elseif cmd == "toggle" or cmd == "" then
        if root:IsShown() then
            root:Hide()
            CHDPadPartyDB.visible = false
            print("|cff00ff00CH_DPadParty:|r Frames hidden.")
        else
            root:Show()
            CHDPadPartyDB.visible = true
            print("|cff00ff00CH_DPadParty:|r Frames shown.")
        end

    elseif cmd == "settings" then
        local panel = CHDPadParty.SettingsPanel
        if panel then
            if panel:IsShown() then panel:Hide() else panel:Show() end
        end

    elseif cmd:sub(1, 5) == "scale" then
        local val = tonumber(cmd:sub(7))
        if val and val >= 0.5 and val <= 2.0 then
            CHDPadPartyDB.scale = math.floor(val * 10 + 0.5) / 10
            CHDPadParty.root:SetScale(CHDPadPartyDB.scale)
            CHDPadParty.RefreshSettingsButtons()
            print("|cff00ff00CH_DPadParty:|r Scale set to " .. CHDPadPartyDB.scale)
        else
            print("|cff00ff00CH_DPadParty:|r Scale must be 0.5 – 2.0  (e.g. /chdpad scale 1.5)")
        end

    else
        print("|cff00ff00CH_DPadParty:|r Usage: /chdpad [show|hide|toggle|settings|scale <0.5-2.0>]")
    end
end
