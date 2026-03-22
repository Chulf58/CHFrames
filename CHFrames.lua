-- CHFrames.lua
-- Main module for CHFrames — party / raid / unit frames
------------------------------------------------------------------------

CHFrames = CHFrames or {}

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

-- Atonement tracker: only active when player is Discipline Priest (spec ID 256).
-- Populated by UpdateDiscSpec(); nil = not yet detected.
local _isDiscPriest = nil

-- Defensive cooldown spell IDs tracked by UpdateDefensive.
-- EXTERNALS: cast by another player onto a party member; highest healer awareness priority.
-- PERSONALS: cast by the unit on themselves.
-- Source: TODO.md defensive ability icon spec.
local DEFENSIVE_EXTERNALS = {
    [6940]   = true,  -- Blessing of Sacrifice (Paladin)
    [33206]  = true,  -- Pain Suppression (Priest)
    [47788]  = true,  -- Guardian Spirit (Priest)
    [116849] = true,  -- Life Cocoon (Monk)
    [97462]  = true,  -- Rallying Cry (Warrior)
    [370665] = true,  -- Rescue (Evoker)
    [370960] = true,  -- Emerald Boon (Evoker)
}
local DEFENSIVE_PERSONALS = {
    [642]    = true,  -- Divine Shield (Paladin)
    [22812]  = true,  -- Barkskin (Druid)
    [61336]  = true,  -- Survival Instincts (Druid)
    [45438]  = true,  -- Ice Block (Mage)
    [198589] = true,  -- Blur (Demon Hunter)
    [48707]  = true,  -- Anti-Magic Shell (Death Knight)
}

-- Range check: use C_Spell.IsSpellInRange with a spec-specific friendly spell.
-- Spell validated with IsPlayerSpell() — reliable unlike probing against "player".
-- Result is a plain Lua boolean (== true / == false), not a secret value.
-- Approach mirrors Grid2 / DandersFrames which confirmed this works in WoW 12.0.
local _rangeFriendlySpell = nil  -- nil = not yet detected

-- Friendly spell per spec ID (IsSpellInRange works on friendly targets at ~40yd).
-- Classes with no friendly spell (DK, DH, Hunter, Warrior, Rogue) fall back to
-- CheckInteractDistance (~28yd) out of combat, then assume in-range in combat.
local RANGE_SPELL_BY_SPEC = {
    [102] = 8936,   [103] = 8936,   [104] = 8936,   [105] = 774,    -- Druid
    [256] = 17,     [257] = 2061,   [258] = 17,                      -- Priest
    [62]  = 1459,   [63]  = 1459,   [64]  = 1459,                    -- Mage
    [268] = 116670, [269] = 116670, [270] = 116670,                  -- Monk
    [65]  = 19750,  [66]  = 19750,  [70]  = 19750,                   -- Paladin
    [262] = 8004,   [263] = 8004,   [264] = 8004,                    -- Shaman
    [265] = 20707,  [266] = 20707,  [267] = 20707,                   -- Warlock
    [1467]= 355913, [1468]= 355913, [1473]= 355913,                  -- Evoker
}

-- Class-level fallback if spec detection fails
local RANGE_SPELL_BY_CLASS = {
    DRUID   = 8936,   PRIEST  = 2061,  MAGE    = 1459,
    MONK    = 116670, PALADIN = 19750, SHAMAN  = 8004,
    WARLOCK = 20707,  EVOKER  = 355913,
}

local function UpdateRangeSpell()
    _rangeFriendlySpell = nil
    -- Spec-specific first
    local specIndex = GetSpecialization and GetSpecialization()
    if specIndex then
        local specID = GetSpecializationInfo and GetSpecializationInfo(specIndex)
        local id = specID and RANGE_SPELL_BY_SPEC[specID]
        if id and IsPlayerSpell(id) then
            _rangeFriendlySpell = id
            return
        end
    end
    -- Class fallback
    local _, classFile = UnitClass("player")
    local id = classFile and RANGE_SPELL_BY_CLASS[classFile]
    if id and IsPlayerSpell(id) then
        _rangeFriendlySpell = id
    end
    -- DK/DH/Hunter/Warrior/Rogue: _rangeFriendlySpell stays nil → fallback path
end

-- G-077: GetRaidTargetIndex can return a tainted secret number when called from a
-- tainted execution context (e.g. Blizzard UI's SetRaidTarget from protected code).
-- Arithmetic on a secret number always throws in TWW.  Pre-compute all 8 sets of
-- SetTexCoord args so UpdateRaidMarker never needs arithmetic on the return value.
-- Table lookup (t[secretNum]) does NOT go through the arithmetic taint checker and works.
-- UI-RaidTargetingIcons: 4 columns × 2 rows; col=(idx-1)%4, row=floor((idx-1)/4).

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

-- Layout offset tables: CENTER of each unit frame relative to root CENTER.
-- Three modes selectable at runtime via CHFramesDB.layout.
--
-- handheld  — D-pad/numpad (default). Vertical stride 86 (39+8+39), horizontal 104 (100+4).
-- sidebyside — single horizontal row. Stride 208 (100+8+100) per TODO spec.
-- stacked    — single vertical column. Same stride as handheld vertical (86).
local LAYOUT_OFFSETS = {
    handheld = {
        party1 = {    0,   86 },
        party2 = { -104,    0 },
        party3 = {  104,    0 },
        party4 = {    0,  -86 },
        player = {    0, -172 },
    },
    sidebyside = {
        -- Left→right: party1, party2, party3, party4, player
        party1 = { -416, 0 },
        party2 = { -208, 0 },
        party3 = {    0, 0 },
        party4 = {  208, 0 },
        player = {  416, 0 },
    },
    stacked = {
        -- Top→bottom: party1, party2, party3, party4, player
        party1 = { 0,  172 },
        party2 = { 0,   86 },
        party3 = { 0,    0 },
        party4 = { 0,  -86 },
        player = { 0, -172 },
    },
}
-- Convenience alias so Init() doesn't need a DB lookup
local OFFSETS = LAYOUT_OFFSETS.handheld

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

CHFrames.frames = CHFrames.frames or {}

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

function CHFrames.Init()
    CHFrames.BuildRootFrame()
    local root = CHFrames.root

    -- G-054: ClearAllPoints before SetPoint on restore
    local pos = CHFramesDB.position
    root:ClearAllPoints()
    root:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)

    -- Build unit frames positioned via SetPoint offsets from root
    for _, unit in ipairs(UNIT_SLOTS) do
        local f = CHFrames.BuildUnitFrame(unit)
        local ox, oy = OFFSETS[unit][1], OFFSETS[unit][2]
        f:SetPoint("CENTER", root, "CENTER", ox, oy)
        CHFrames.frames[unit] = f
    end

    -- Apply saved lock state (G-064: SetMovable + RegisterForDrag, never EnableMouse)
    if CHFramesDB.locked then
        CHFrames.root:SetMovable(false)
        for _, unit in ipairs(UNIT_SLOTS) do
            local f = CHFrames.frames[unit]
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
        local locked = CHFramesDB.locked
        for _, unit in ipairs(UNIT_SLOTS) do
            local fr = CHFrames.frames[unit]
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

    root:SetScale(CHFramesDB.scale or 1.0)

    CHFrames.BuildMinimapButton()
    CHFrames.BuildSettingsPanel()
    CHFrames.RefreshSettingsButtons()

    CHFrames.UpdateAll()
    CHFrames.UpdateVisibility()

    -- If test mode was saved from a previous session, repopulate fake data now
    if CHFramesDB.testMode then
        CHFrames.ApplyTestMode()
    end
end

------------------------------------------------------------------------
-- UpdateFrame
------------------------------------------------------------------------

function CHFrames.UpdateFrame(unit)
    -- In test mode, party1-4 show fake data — skip live updates for them.
    -- The player slot always shows real character data even in test mode.
    if CHFramesDB and CHFramesDB.testMode and unit ~= "player" then return end

    local f = CHFrames.frames[unit]
    if not f then return end

    local ok, err = pcall(function()
        -- Hide if unit does not exist
        if not UnitExists(unit) then
            f:Hide()
            return
        end
        f:Show()

        -- Health bar and HP% text.
        -- UnitHealth / UnitHealthMax are secret numbers — pass to C functions only.
        -- G-057: SetMinMaxValues before SetValue.
        -- Guard: check only pcall success booleans (plain bools), never use secret
        -- numbers in boolean coercion context (if secret then) — that creates a
        -- tainted boolean which propagates and silently breaks downstream conditionals.
        do
            local maxOk, maxHP = pcall(UnitHealthMax, unit)
            local hpOk,  hp    = pcall(UnitHealth, unit)
            if maxOk and hpOk then
                f.healthBar:SetMinMaxValues(0, maxHP)
                f.healthBar:SetValue(hp)
            else
                f.healthBar:SetMinMaxValues(0, 100)
                f.healthBar:SetValue(f._lastHpPct or 0)
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

        -- HP% text: UnitHealthPercent(unit, true, CurveConstants.ScaleTo100) → 0–100,
        -- secret in M+/PvP/encounters. SetFormattedText is C-level and accepts secret
        -- values directly (mirrors DandersFrames GetSafeHealthPercent). No math.floor.
        -- _lastHpPct cache updated via pcall(math.floor) for overlay/fallback contexts.
        if UnitHealthPercent then
            local raw = UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
            if raw ~= nil then
                f.hpText:SetFormattedText("%.0f%%", raw)
                local floorOk, pct = pcall(math.floor, raw)
                if floorOk then f._lastHpPct = pct end
            else
                f.hpText:SetText((f._lastHpPct or 100) .. "%")
            end
        else
            f.hpText:SetText((f._lastHpPct or 100) .. "%")
        end

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
        -- G-079: UnitIsGroupLeader may return a secret boolean; guard with issecretvalue().
        if f.leaderCrown then
            local isLeader = UnitIsGroupLeader(unit)
            if not issecretvalue(isLeader) and isLeader then
                f.leaderCrown:Show()
            else
                f.leaderCrown:Hide()
            end
        end

        -- Dead / ghost / offline / AFK overlay (G-058: ghost before dead)
        -- G-079: UnitIsConnected/IsGhost/IsDead/IsAFK may return secret booleans.
        -- issecretvalue() guard prevents "boolean test on secret value" errors.
        -- Short-circuit: the not/truthy test only executes when the value is non-secret.
        local connected = UnitIsConnected(unit)
        local ghost     = UnitIsGhost(unit)
        local dead      = UnitIsDead(unit)
        local afk       = UnitIsAFK(unit)
        local overlayLabel = ""
        if not issecretvalue(connected) and not connected then
            overlayLabel = "Offline"
        elseif not issecretvalue(ghost) and ghost then
            overlayLabel = "Ghost"
        elseif not issecretvalue(dead) and dead then
            overlayLabel = "Dead"
        elseif not issecretvalue(afk) and afk then
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
        CHFrames.UpdateAuras(unit)
    end)
    if not ok then
        print("|cffff4444CHFrames|r UpdateFrame(" .. unit .. "): " .. tostring(err))
    end
end

------------------------------------------------------------------------
-- UpdateVisibility  (G-061: hide party1-4 when in raid or solo)
------------------------------------------------------------------------

function CHFrames.UpdateVisibility()
    -- Don't hide frames that test mode is intentionally showing
    if CHFramesDB and CHFramesDB.testMode then return end

    local inRaid  = IsInRaid()
    local inGroup = IsInGroup()

    for _, unit in ipairs(UNIT_SLOTS) do
        local f = CHFrames.frames[unit]
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

function CHFrames.UpdateAll()
    for _, unit in ipairs(UNIT_SLOTS) do
        CHFrames.UpdateAbsorbs(unit)       -- must run before UpdateFrame to populate _hasAbsorb
        CHFrames.UpdateFrame(unit)
        CHFrames.UpdateHealPrediction(unit)
        CHFrames.UpdatePower(unit)
        CHFrames.UpdateAuras(unit)
        CHFrames.UpdateMissingBuff(unit)
        CHFrames.UpdateRange(unit)
        CHFrames.UpdateRez(unit)
        CHFrames.UpdateVehicle(unit)
        CHFrames.UpdateRaidMarker(unit)
        CHFrames.UpdateDefensive(unit)
        CHFrames.UpdateAtonement(unit)
    end
end

------------------------------------------------------------------------
-- ApplyLayout  (handheld / sidebyside / stacked)
------------------------------------------------------------------------

function CHFrames.ApplyLayout(layout)
    if InCombatLockdown() then
        print("|cff00ff00CHFrames:|r Cannot change layout in combat.")
        return
    end
    local offsets = LAYOUT_OFFSETS[layout] or LAYOUT_OFFSETS.handheld
    CHFramesDB.layout = layout or "handheld"
    for unit, f in pairs(CHFrames.frames) do
        local o = offsets[unit]
        if o then
            f:ClearAllPoints()
            f:SetPoint("CENTER", CHFrames.root, "CENTER", o[1], o[2])
        end
    end
end

------------------------------------------------------------------------
-- UpdateBorder  (target gold > dispel color > default grey)
------------------------------------------------------------------------

function CHFrames.UpdateBorder(unit)
    local f = CHFrames.frames[unit]
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

function CHFrames.UpdateAuras(unit)
    -- G-067: skip if test mode active — fake data owns the aura slots
    if CHFramesDB and CHFramesDB.testMode then return end

    local f = CHFrames.frames[unit]
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
        CHFrames.UpdateBorder(unit)
    end)
end

------------------------------------------------------------------------
-- UpdateMissingBuff
------------------------------------------------------------------------

function CHFrames.UpdateMissingBuff(unit)
    local f = CHFrames.frames[unit]
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

function CHFrames.UpdatePower(unit)
    if CHFramesDB and CHFramesDB.testMode and unit ~= "player" then return end
    local f = CHFrames.frames[unit]
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
        -- Guard on pcall success booleans only — secret numbers must not be used in
        -- boolean coercion context (if secretNum then) as that creates tainted booleans.
        local maxOk, maxPow = pcall(UnitPowerMax, unit)
        local powOk, pow    = pcall(UnitPower, unit)
        if maxOk and powOk then
            f.powerBar:SetMinMaxValues(0, maxPow)
            f.powerBar:SetValue(pow)
        else
            f.powerBar:SetMinMaxValues(0, 1)
            f.powerBar:SetValue(0)
        end
    end)
    if not ok then
        print("|cffff4444CHFrames|r UpdatePower(" .. unit .. "): " .. tostring(err))
    end
end

------------------------------------------------------------------------
-- UpdateHealPrediction
------------------------------------------------------------------------

function CHFrames.UpdateHealPrediction(unit)
    if CHFramesDB and CHFramesDB.testMode and unit ~= "player" then return end
    local f = CHFrames.frames[unit]
    if not f or not f.healPredictBar then return end

    local ok, err = pcall(function()
        if not UnitExists(unit) then
            f.healPredictBar:Hide()
            return
        end

        local calc = f.healPredictCalc
        if not calc then
            f.healPredictBar:Hide()
            return
        end

        -- Populate calculator. calc:GetIncomingHeals() → total, fromHealer, fromOthers, clamped.
        -- All return values are secret numbers in restricted contexts; passed to C only.
        -- == nil is explicitly safe on secret numbers — hides bar when no heal incoming.
        UnitGetDetailedHealPrediction(unit, nil, calc)
        local amount = calc:GetIncomingHeals()
        if amount == nil then
            f.healPredictBar:Hide()
            return
        end

        -- DandersFrames SANDWICH pattern: anchor left edge of prediction bar to the right
        -- edge of the health fill texture. No Lua arithmetic — the C StatusBar API handles
        -- fill proportion via SetMinMaxValues(0, maxHP) + SetValue(incomingHeals).
        local fillTex = f.healthBar:GetStatusBarTexture()
        if fillTex then
            f.healPredictBar:ClearAllPoints()
            f.healPredictBar:SetPoint("TOPLEFT",    fillTex, "TOPRIGHT",    0, 0)
            f.healPredictBar:SetPoint("BOTTOMLEFT", fillTex, "BOTTOMRIGHT", 0, 0)
            f.healPredictBar:SetWidth(f.healthBar:GetWidth())
        end

        local maxOk, maxHP = pcall(UnitHealthMax, unit)
        if maxOk then
            f.healPredictBar:SetMinMaxValues(0, maxHP)
            f.healPredictBar:SetValue(amount)
            f.healPredictBar:Show()
        else
            f.healPredictBar:Hide()
        end
    end)
    if not ok then
        print("|cffff4444CHFrames|r UpdateHealPrediction(" .. unit .. "): " .. tostring(err))
    end
end

------------------------------------------------------------------------
-- UpdateAbsorbs
------------------------------------------------------------------------

function CHFrames.UpdateAbsorbs(unit)
    if CHFramesDB and CHFramesDB.testMode and unit ~= "player" then return end
    local f = CHFrames.frames[unit]
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
            -- Note: absorb presence for hpText is now detected inline in UpdateFrame
            -- using issecretvalue(UnitGetTotalAbsorbs(unit)) — no cache needed here.
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

function CHFrames.UpdateRange(unit)
    -- G-RANGE-1: skip in test mode — fake frames always show at full alpha
    if CHFramesDB and CHFramesDB.testMode then return end

    local f = CHFrames.frames[unit]
    if not f then return end

    -- G-RANGE-2: skip if frame not shown — avoids wasted API calls
    if not f:IsShown() then return end

    -- G-RANGE-3: player is always in range
    if unit == "player" then
        f._oorAlpha = 1.0
        ApplyCombinedAlpha(f)
        return
    end

    -- G-RANGE-4: DandersFrames pattern — C_Spell.IsSpellInRange returns plain
    -- Lua true/false (not secret booleans).  Compare with == true / == false.
    -- nil = can't determine (unit not yet loaded) → assume in-range.
    -- Fallback: CheckInteractDistance(unit,4) ~28yd when spell returns false OOC.
    -- Combat fallback: if in combat and spell returns false → still assume in-range
    -- (we cannot reliably check range mid-combat without a spell).
    local inRange = true
    if _rangeFriendlySpell then
        local result = C_Spell.IsSpellInRange(_rangeFriendlySpell, unit)
        if result == true then
            inRange = true
        elseif result == false then
            if not InCombatLockdown() and CheckInteractDistance(unit, 4) then
                inRange = true
            else
                inRange = false
            end
        end
        -- result == nil: indeterminate → leave inRange = true
    else
        -- No friendly range spell known (DK/DH/Hunter/Warrior/Rogue)
        -- Use interact distance OOC only; assume in-range in combat
        if not InCombatLockdown() then
            inRange = CheckInteractDistance(unit, 4) and true or false
        end
    end

    f._oorAlpha = inRange and 1.0 or 0.4
    ApplyCombinedAlpha(f)
end

------------------------------------------------------------------------
-- UpdateRez  (incoming resurrection or summon indicator)
------------------------------------------------------------------------

function CHFrames.UpdateRez(unit)
    if CHFramesDB and CHFramesDB.testMode then return end
    local f = CHFrames.frames[unit]
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
-- UpdateVehicle
------------------------------------------------------------------------

function CHFrames.UpdateVehicle(unit)
    if CHFramesDB and CHFramesDB.testMode then return end
    local f = CHFrames.frames[unit]
    if not f or not f.vehicleIcon then return end
    local ok, result = pcall(UnitHasVehicleUI, unit)
    if ok and result then
        f.vehicleIcon:Show()
    else
        f.vehicleIcon:Hide()
    end
end

------------------------------------------------------------------------
-- UpdateRaidMarker
------------------------------------------------------------------------

function CHFrames.UpdateRaidMarker(unit)
    if CHFramesDB and CHFramesDB.testMode then return end
    local f = CHFrames.frames[unit]
    if not f or not f.raidMarker then return end

    -- G-077: GetRaidTargetIndex returns a secret number — cannot use as table index.
    -- SetRaidTargetIconTexture is a C-side function that accepts the secret value directly.
    local idx = GetRaidTargetIndex(unit)
    if idx then
        SetRaidTargetIconTexture(f.raidMarker.tex, idx)
        f.raidMarker:Show()
    else
        f.raidMarker:Hide()
    end
end

------------------------------------------------------------------------
-- UpdateDiscSpec / UpdateAtonement
------------------------------------------------------------------------

-- Detect whether the player is currently Discipline Priest (spec ID 256).
-- Called on PLAYER_ENTERING_WORLD and PLAYER_TALENT_UPDATE.
local function UpdateDiscSpec()
    local specIndex = GetSpecialization and GetSpecialization()
    if specIndex then
        local specID = GetSpecializationInfo and GetSpecializationInfo(specIndex)
        _isDiscPriest = (specID == 256)
    else
        _isDiscPriest = false
    end
    -- When spec changes, hide all atonement icons immediately.
    if not _isDiscPriest then
        for _, unit in ipairs(UNIT_SLOTS) do
            local f = CHFrames.frames[unit]
            if f and f.atonementIcon then
                f.atonementIcon:Hide()
            end
        end
    end
end

-- Atonement tracker: show a prominent icon + cooldown swipe on the unit frame when
-- Atonement (194384) is active. Uses GetAuraDataBySpellName for O(1) lookup (no loop).
-- expirationTime - GetTime() is safe: Atonement is a whitelisted public aura; both
-- values are plain numbers (confirmed by DandersFrames AuraDesigner research).
function CHFrames.UpdateAtonement(unit)
    if not _isDiscPriest then return end
    if CHFramesDB and CHFramesDB.testMode then return end
    local f = CHFrames.frames[unit]
    if not f or not f.atonementIcon then return end

    pcall(function()
        if not UnitExists(unit) then
            f.atonementIcon:Hide()
            return
        end

        -- Filter "HELPFUL|PLAYER": only Atonements applied by the player (us).
        local aura = C_UnitAuras.GetAuraDataBySpellName(unit, "Atonement", "HELPFUL|PLAYER")
        if aura and aura.icon and aura.expirationTime and aura.expirationTime > 0 then
            f.atonementIcon.tex:SetTexture(aura.icon)
            -- Cooldown swipe: SetCooldown(start, duration) — start = expirationTime - duration
            if aura.duration and aura.duration > 0 then
                CooldownFrame_Set(f.atonementIcon.cooldown,
                    aura.expirationTime - aura.duration, aura.duration, 1)
                f.atonementIcon.cooldown:Show()
            else
                f.atonementIcon.cooldown:Hide()
            end
            -- Cache expiration for the timer ticker
            f.atonementIcon._expireTime = aura.expirationTime
            f.atonementIcon:Show()
        else
            f.atonementIcon:Hide()
            f.atonementIcon._expireTime = nil
            f.atonementIcon.timer:SetText("")
        end
    end)
end

------------------------------------------------------------------------
-- UpdateDefensive
------------------------------------------------------------------------

function CHFrames.UpdateDefensive(unit)
    if CHFramesDB and CHFramesDB.testMode then return end
    local f = CHFrames.frames[unit]
    if not f or not f.defIcon then return end

    pcall(function()
        if not UnitExists(unit) then
            f.defIcon:Hide()
            return
        end

        -- Scan HELPFUL auras for known defensive spell IDs.
        -- Defensive buffs are public (not private) — a single nil means list ended;
        -- simple break is correct here (no consecutive-nil logic needed).
        -- Duration filter: >0 (not permanent) and <=600 (10 min cap, excludes permanent
        -- buffs like Blessing of Kings that happen to share no ID with defensives, but
        -- provides an extra safety net against future table collisions).
        local bestIcon     = nil
        local bestPriority = 0  -- 0=none, 1=personal, 2=external

        for i = 1, 40 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
            if not ok or not aura then break end
            if aura.spellId and aura.icon
               and aura.duration and aura.duration > 0 and aura.duration <= 600 then
                local priority = 0
                if DEFENSIVE_EXTERNALS[aura.spellId] then
                    priority = 2
                elseif DEFENSIVE_PERSONALS[aura.spellId] then
                    priority = 1
                end
                if priority > bestPriority then
                    bestPriority = priority
                    bestIcon = aura.icon
                end
            end
        end

        if bestIcon then
            f.defIcon.tex:SetTexture(bestIcon)
            f.defIcon:Show()
        else
            f.defIcon:Hide()
        end
    end)
end

------------------------------------------------------------------------
-- ApplyTestMode
------------------------------------------------------------------------

function CHFrames.ApplyTestMode()
    for idx, unit in ipairs(UNIT_SLOTS) do
        if unit == "player" then
            -- Player always shows real character data — never overwrite with fake
            CHFrames.UpdateFrame("player")
        else
            local f = CHFrames.frames[unit]
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

                -- Heal prediction bar: fake 30% incoming in test mode.
                -- Anchors to health fill texture right edge (same as live mode).
                if f.healPredictBar then
                    local fillTex = f.healthBar:GetStatusBarTexture()
                    if fillTex then
                        f.healPredictBar:ClearAllPoints()
                        f.healPredictBar:SetPoint("TOPLEFT",    fillTex, "TOPRIGHT",    0, 0)
                        f.healPredictBar:SetPoint("BOTTOMLEFT", fillTex, "BOTTOMRIGHT", 0, 0)
                        f.healPredictBar:SetWidth(f.healthBar:GetWidth())
                    end
                    f.healPredictBar:SetMinMaxValues(0, 100)
                    f.healPredictBar:SetValue(30)
                    f.healPredictBar:Show()
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
                    -- G-071: hide typeOverlay so fake icons don't show stale badges
                    if icon.typeOverlay then icon.typeOverlay:Hide() end
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

local eventFrame = CreateFrame("Frame", "CHFramesEventFrame", UIParent)

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")         -- G-053: not PARTY_MEMBERS_CHANGED
eventFrame:RegisterEvent("UNIT_HEALTH")
eventFrame:RegisterEvent("UNIT_POWER_UPDATE")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("PLAYER_FLAGS_CHANGED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")          -- spec/talent changes → re-detect range spell
eventFrame:RegisterEvent("UNIT_HEAL_PREDICTION")        -- incoming heals changed
eventFrame:RegisterEvent("UNIT_DISPLAYPOWER")           -- power type changed (druid forms, etc.)
eventFrame:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")  -- damage absorb shields changed
eventFrame:RegisterEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED") -- heal absorbs (Necrotic) changed
eventFrame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE") -- aggro/threat state changed
eventFrame:RegisterEvent("INCOMING_RESURRECT_CHANGED")  -- incoming rez changed
eventFrame:RegisterEvent("INCOMING_SUMMON_CHANGED")     -- incoming summon changed
eventFrame:RegisterEvent("RAID_TARGET_UPDATE")          -- raid marker assigned/cleared
eventFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")        -- unit mounted a vehicle
eventFrame:RegisterEvent("UNIT_EXITED_VEHICLE")         -- unit dismounted from vehicle

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1:lower() ~= "chframes" then return end

        -- DB init: each field individually to avoid shared-table-reference bug
        if type(CHFramesDB) ~= "table" then
            CHFramesDB = {}
        end
        if type(CHFramesDB.position) ~= "table" then
            CHFramesDB.position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }
        end
        if CHFramesDB.visible    == nil then CHFramesDB.visible    = true  end
        if CHFramesDB.locked     == nil then CHFramesDB.locked     = true  end
        if CHFramesDB.minimapPos == nil then CHFramesDB.minimapPos = 210   end
        if CHFramesDB.scale      == nil then CHFramesDB.scale      = 1.0   end
        if CHFramesDB.layout     == nil then CHFramesDB.layout     = "handheld" end
        -- testMode always resets to false on load — it is a session-only preview
        -- tool, not a persistent setting. Saving it caused fake data to show on
        -- the next login even when the player is in a real party.
        CHFramesDB.testMode = false
        -- settingsX / settingsY default to nil (panel uses default center position)

        CHFrames.Init()
        -- Restore saved layout (Init uses handheld by default; this re-anchors if different)
        if CHFramesDB.layout ~= "handheld" then
            CHFrames.ApplyLayout(CHFramesDB.layout)
        end

        if CHFramesDB.visible then
            CHFrames.root:Show()
        else
            CHFrames.root:Hide()
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        CHFrames.UpdateVisibility()
        CHFrames.UpdateAll()

    elseif event == "UNIT_HEALTH" then
        -- G-056: only process tracked units
        if UNIT_LOOKUP[arg1] then
            CHFrames.UpdateFrame(arg1)
        end

    elseif event == "UNIT_POWER_UPDATE" then
        if UNIT_LOOKUP[arg1] then
            CHFrames.UpdateFrame(arg1)
            CHFrames.UpdatePower(arg1)
        end

    elseif event == "UNIT_DISPLAYPOWER" then
        -- Power type changed (druid shifting, etc.) — update bar color and value
        if arg1 and UNIT_LOOKUP[arg1] then
            CHFrames.UpdatePower(arg1)
        end

    elseif event == "UNIT_AURA" then
        -- G-065: guard on arg1 before any work
        -- G-067: skip entirely if test mode active
        if UNIT_LOOKUP[arg1] and not (CHFramesDB and CHFramesDB.testMode) then
            CHFrames.UpdateAuras(arg1)
            CHFrames.UpdateMissingBuff(arg1)
            CHFrames.UpdateDefensive(arg1)
            CHFrames.UpdateAtonement(arg1)
        end

    elseif event == "PLAYER_TARGET_CHANGED" then
        -- No arg1 — loop all slots to clear old target and highlight new one
        for _, unit in ipairs(UNIT_SLOTS) do
            CHFrames.UpdateBorder(unit)
        end

    elseif event == "PLAYER_FLAGS_CHANGED" then
        -- Catches AFK, dead, ghost transitions
        if UNIT_LOOKUP[arg1] then
            CHFrames.UpdateFrame(arg1)
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        CHFrames.UpdateVisibility()
        CHFrames.UpdateAll()
        -- Re-position minimap button after zone transitions
        if CHFrames.minimapBtn then
            CHFrames.UpdateMinimapButtonPos()
        end
        -- Detect which spell to use for range probing (class/spec-specific).
        -- Re-runs on zone transition in case talents changed spell availability.
        UpdateRangeSpell()
        -- G-072: detect which debuff types the player can dispel.
        UpdateDispelTypes()
        UpdateDiscSpec()

        -- G-RANGE-5: range ticker created here, not in Init — unit data unavailable
        -- at ADDON_LOADED time. Guard prevents stacking on every zone transition.
        if not CHFrames.rangeTicker then
            CHFrames.rangeTicker = C_Timer.NewTicker(0.1, function()
                for _, unit in ipairs(UNIT_SLOTS) do
                    CHFrames.UpdateRange(unit)
                end
            end)
        end
        -- Timer ticker: refreshes duration text on visible aura icons every second.
        if not CHFrames.timerTicker then
            CHFrames.timerTicker = C_Timer.NewTicker(1, function()
                local now = GetTime()
                for _, unit in ipairs(UNIT_SLOTS) do
                    local f = CHFrames.frames[unit]
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
                        -- Atonement countdown timer
                        if f.atonementIcon and f.atonementIcon:IsShown()
                           and f.atonementIcon._expireTime then
                            local rem = f.atonementIcon._expireTime - now
                            if rem > 0 then
                                f.atonementIcon.timer:SetText(math.floor(rem))
                            else
                                f.atonementIcon.timer:SetText("")
                            end
                        end
                    end
                end
            end)
        end

    elseif event == "UNIT_HEAL_PREDICTION" then
        if UNIT_LOOKUP[arg1] then
            CHFrames.UpdateHealPrediction(arg1)
        end

    elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" then
        if UNIT_LOOKUP[arg1] then
            CHFrames.UpdateAbsorbs(arg1)
            CHFrames.UpdateFrame(arg1)    -- refresh hpText with updated _hasAbsorb
        end

    elseif event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
        if UNIT_LOOKUP[arg1] then
            CHFrames.UpdateAbsorbs(arg1)
        end

    elseif event == "UNIT_THREAT_SITUATION_UPDATE" then
        if arg1 and UNIT_LOOKUP[arg1] then
            CHFrames.UpdateBorder(arg1)
        end

    elseif event == "INCOMING_RESURRECT_CHANGED" or event == "INCOMING_SUMMON_CHANGED" then
        if arg1 and UNIT_LOOKUP[arg1] then
            CHFrames.UpdateRez(arg1)
        end

    elseif event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
        if arg1 and UNIT_LOOKUP[arg1] then
            CHFrames.UpdateVehicle(arg1)
        end

    elseif event == "RAID_TARGET_UPDATE" then
        -- G-077: RAID_TARGET_UPDATE can fire while inside Blizzard's protected SetRaidTarget
        -- call chain (e.g. the right-click unit popup). In that tainted context,
        -- GetRaidTargetIndex returns a secret number — unusable for arithmetic OR table lookup.
        -- Defer to the next frame via C_Timer.After(0) so the callback runs in a clean,
        -- untainted execution context where GetRaidTargetIndex returns a plain number.
        C_Timer.After(0, function()
            for _, unit in ipairs(UNIT_SLOTS) do
                CHFrames.UpdateRaidMarker(unit)
            end
        end)

    elseif event == "PLAYER_TALENT_UPDATE" then
        UpdateRangeSpell()
        UpdateDispelTypes()
        UpdateDiscSpec()
    end
end)

------------------------------------------------------------------------
-- Slash Command  /chframes [show|hide|toggle|settings]
------------------------------------------------------------------------

SLASH_CHFRAMES1 = "/chframes"

SlashCmdList["CHFRAMES"] = function(msg)
    local root = CHFrames.root
    if not root then return end

    local cmd = strtrim(msg):lower()

    if cmd == "show" then
        root:Show()
        CHFramesDB.visible = true
        print("|cff00ff00CHFrames:|r Frames shown.")

    elseif cmd == "hide" then
        root:Hide()
        CHFramesDB.visible = false
        print("|cff00ff00CHFrames:|r Frames hidden.")

    elseif cmd == "toggle" or cmd == "" then
        if root:IsShown() then
            root:Hide()
            CHFramesDB.visible = false
            print("|cff00ff00CHFrames:|r Frames hidden.")
        else
            root:Show()
            CHFramesDB.visible = true
            print("|cff00ff00CHFrames:|r Frames shown.")
        end

    elseif cmd == "settings" then
        local panel = CHFrames.SettingsPanel
        if panel then
            if panel:IsShown() then panel:Hide() else panel:Show() end
        end

    elseif cmd:sub(1, 5) == "scale" then
        local val = tonumber(cmd:sub(7))
        if val and val >= 0.5 and val <= 2.0 then
            CHFramesDB.scale = math.floor(val * 10 + 0.5) / 10
            CHFrames.root:SetScale(CHFramesDB.scale)
            CHFrames.RefreshSettingsButtons()
            print("|cff00ff00CHFrames:|r Scale set to " .. CHFramesDB.scale)
        else
            print("|cff00ff00CHFrames:|r Scale must be 0.5 – 2.0  (e.g. /chframes scale 1.5)")
        end

    else
        print("|cff00ff00CHFrames:|r Usage: /chframes [show|hide|toggle|settings|scale <0.5-2.0>]")
    end
end
