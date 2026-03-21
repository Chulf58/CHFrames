# CH_DPadParty — Known Gotchas

Hard-won lessons from development. Every entry here was a real bug.
Agents: read this before planning or coding anything.

---

## WoW 12.0 Secret Numbers

**G-070 — UnitHealthPercent returns a secret number in tainted contexts.**
Do NOT call `UnitHealthPercent` from inside event handlers that have been tainted (e.g. after touching CompactPartyFrame). Wrap in `pcall` and fall back to `f._lastHpPct` if it fails.

**WoW 12.0 — UnitHealth / UnitHealthMax cannot be used in Lua arithmetic.**
In combat or tainted contexts these return secret numbers. Lua `+`, `-`, `*`, `/`, `math.floor` on them throws. Pass directly to C StatusBar API (`SetValue`, `SetMinMaxValues`) only. Use `UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)` for a plain 0–100 float when you need arithmetic.

**WoW 12.0 — UnitGetIncomingHeals, UnitGetTotalAbsorbs, UnitGetTotalHealAbsorbs.**
All return secret numbers. Pass directly to `SetValue` / `SetMinMaxValues`. Never do Lua math on them.

**WoW 12.0 — UnitInRange returns a secret boolean.**
Guard with `issecretvalue(result)` before any conditional. If tainted, fall back to `CheckInteractDistance(unit, 4)` or assume in-range.

**Pattern: always use pcall + cache for secret-number reads.**
```lua
local ok, raw = pcall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
if ok and raw then
    bar:SetValue(raw)          -- C function: accepts secret numbers
    local floorOk, pct = pcall(math.floor, raw)
    if floorOk then cache = pct end
end
```

---

## Taint & Secure Execution

**G-CRITICAL — Never call Show() / Hide() on a SecureUnitButtonTemplate frame from insecure code.**
Using `HookScript("OnShow")` to show the secureBtn inside a UNIT_HEALTH handler taints that execution context. Every subsequent call to `UnitHealthPercent` from that chain returns a tainted secret number and `math.floor` throws. Use `RegisterUnitWatch(secureBtn)` — it manages visibility through the secure system with zero insecure calls.

**G-CRITICAL — Never call ANY method on CompactPartyFrame or CompactRaidFrameManager.**
`UnregisterAllEvents`, `Hide`, `hooksecurefunc` — any of these permanently taints our addon's execution context for the entire session. All subsequent `UnitHealthPercent` / `UnitHealth` calls then return tainted secret numbers. Also strips WoW's group-chat channel events causing "not in a party" / "invalid channel" spam. Do not suppress Blizzard party frames from addon code. Tell users to disable them via Interface → Display settings.

**G-CRITICAL — Cross-parent anchor to a secure frame makes the anchor target restricted.**
If `secureBtn` (SecureUnitButtonTemplate, parented to UIParent) anchors to `f` via `secureBtn:SetAllPoints(f)`, WoW treats `f` as "anchor-restricted" and blocks `f:Show()`/`f:Hide()` from insecure code with ADDON_ACTION_BLOCKED. Fix: parent `secureBtn` to `f` directly — the anchor becomes a normal child-to-parent anchor, eliminating the restriction on `f`.

**SecureUnitButtonTemplate frame level must be high (100).**
Set `secureBtn:SetFrameStrata("MEDIUM")` and `secureBtn:SetFrameLevel(100)` explicitly. When parented to `f`, these explicit values still apply and keep it on top for click interception.

---

## Event Handling

**G-053 — Use GROUP_ROSTER_UPDATE, not PARTY_MEMBERS_CHANGED.**
`PARTY_MEMBERS_CHANGED` is deprecated / unreliable in WoW 12.0. Use `GROUP_ROSTER_UPDATE`.

**G-056 — Always guard events with UNIT_LOOKUP before doing work.**
`UNIT_HEALTH`, `UNIT_POWER_UPDATE`, `UNIT_AURA` fire for every unit in the game. Guard with `if UNIT_LOOKUP[arg1] then` to skip untracked units. Without this, health updates for enemies, NPCs, etc. all trigger frame rebuilds.

**G-065 — Guard on event arg1 before any work, even logging.**
Some events fire with nil arg1. Always `if arg1 and UNIT_LOOKUP[arg1]` before doing anything.

**G-067 — Skip aura updates entirely in test mode.**
`UNIT_AURA` fires on real party members. In test mode, fake auras own the icon slots — real aura events must be suppressed or they overwrite fake data.

---

## Frame & Layout

**G-057 — SetMinMaxValues BEFORE SetValue.**
Setting `SetValue` before `SetMinMaxValues` can cause the bar to silently clamp to 0. Always set the range first.

**G-054 — ClearAllPoints before SetPoint on position restore.**
Restoring a saved position without `ClearAllPoints()` first leaves a dangling anchor that fights the new position. Result is frames that jump or refuse to move.

**G-064 — Use SetMovable for lock, not EnableMouse(false).**
Calling `EnableMouse(false)` on the unit frame breaks click-to-target because the secureBtn (which overlays the frame) also loses mouse interaction. Use `SetMovable(false)` and `RegisterForDrag()` (with no args) to lock movement while preserving clicks.

**G-061 — party1–4 are nil in raid; hide when solo too.**
`UnitExists("party1")` returns false when solo and in raid. Always call `UpdateVisibility()` on `GROUP_ROSTER_UPDATE` and `PLAYER_ENTERING_WORLD`. Do not show party frames when `IsInRaid()` is true.

**Absorb bars parented to healthBar at frame level +1.**
Parent `absorbBar` and `healAbsorbBar` to the healthBar StatusBar. Set their frame level to `bar:GetFrameLevel() + 1` so they render ON TOP of the health fill at all times — visible even at full health. Semi-transparent alpha (0.4 / 0.45) keeps nameText/hpText readable through the overlay. Using `bar:GetFrameLevel()` (same level as healthBar) buries the absorb under the health fill texture when health is full — the absorb becomes invisible.

**SetReverseFill(bool) is a valid WoW StatusBar method.**
`StatusBar:SetReverseFill(true)` has existed since MoP and is valid in retail/TWW. It takes a plain boolean, not a value — no secret number concern.

**CooldownFrame SetAllPoints scales automatically with its parent icon frame.**
No explicit width/height resize is needed on the CooldownFrame when the parent icon frame is resized — `SetAllPoints` keeps it in sync automatically.

**Frame height changes require recalculating OFFSETS; horizontal offsets are unaffected.**
OFFSETS encode vertical spacing as `half-height + gap + half-height`. Changing frame height means this value must be recomputed. Horizontal offsets (party2/party3 left/right positions) depend only on frame width, so they are unaffected by height changes.

**OFFSETS is the only place that encodes frame height.**
No other hardcoded height references exist in the layout code. When resizing frames vertically, OFFSETS is the only constant that needs updating.

---

## Unit & Role API

**G-052 — Role enum is "DAMAGER", not "DPS".**
`UnitGroupRolesAssigned(unit)` returns `"TANK"`, `"HEALER"`, `"DAMAGER"`, or `"NONE"`. Using `"DPS"` as a key silently fails — role icon never shows for DPS players.

**G-055 — Always provide a white fallback for disconnected units.**
`UnitClass(unit)` returns nil for disconnected players. `RAID_CLASS_COLORS[nil]` is nil. Always fallback: `local color = (classFile and RAID_CLASS_COLORS[classFile]) or { r=1, g=1, b=1 }`.

**G-058 — Check ghost before dead.**
A ghost is also "dead" per `UnitIsDead()`. Check `UnitIsGhost()` first or ghost players will show "Dead" instead of "Ghost".

**G-066 — Aura stack count is aura.applications, not aura.count.**
`C_UnitAuras.GetAuraDataByIndex` returns an AuraData table. The stack count field is `aura.applications`. `aura.count` does not exist (always nil). Using count means stacks never show.

---

## SavedVariables

**Initialize each field individually on ADDON_LOADED.**
Do NOT do `CHDPadPartyDB = CHDPadPartyDB or {}` followed by `CHDPadPartyDB = defaults`. This wipes saved data on every load. Set each key only if nil:
```lua
if type(CHDPadPartyDB) ~= "table" then CHDPadPartyDB = {} end
if CHDPadPartyDB.locked == nil then CHDPadPartyDB.locked = true end
```

**testMode must never persist across sessions.**
testMode is a session-only preview tool. Always reset it to `false` on `ADDON_LOADED`. If saved as true, fake data shows on next login even in a real party.

**Use `if var == nil then` not `var or default` for booleans.**
`false or true` evaluates to `true`. The `or` pattern is broken for boolean defaults. Always use explicit nil checks.

---

## Test Mode

**G-067 — Test mode blocks live aura updates.**
When `CHDPadPartyDB.testMode` is true, `UpdateAuras` must return immediately for all party slots. The UNIT_AURA event handler also skips entirely. Otherwise real aura events wipe fake icons.

**Test mode never overwrites player slot.**
The player frame always shows real character data even in test mode. Only party1–4 get fake data. `ApplyTestMode` skips `unit == "player"` and calls `UpdateFrame("player")` instead.


**G-075 — Use RegisterStateDriver to hide Blizzard party frames; never call Lua methods on them.**
`RegisterStateDriver(frame, "visibility", "hide")` routes through Blizzard's secure C-level state driver without tainting our context. Calling `:Hide()`, `:UnregisterAllEvents()`, or any Lua method on `PartyFrame`/`CompactPartyFrame`/`CompactRaidFrameManager` triggers G-CRITICAL taint. Implemented in `CH_DPadParty_HideBlizzard.lua`, triggered on `PLAYER_LOGIN` with a guard flag. KNOWN LIMITATION: `PLAYER_LOGIN` does not re-fire on `/reload`. CompactPartyFrame and CompactRaidFrameManager are excluded until in-game taint testing confirms safety.
