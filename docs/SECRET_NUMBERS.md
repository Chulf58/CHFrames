# WoW Midnight (12.0) — Secret Values Reference

Researched 2026-03-21. Canonical source: [Secret Values — Warcraft Wiki](https://warcraft.wiki.gg/wiki/Secret_Values), [Patch 12.0.0/API changes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes), Cell addon PR #457.

---

## What are secret values?

Secret values were introduced in **Patch 12.0.0 (Midnight)**. They are a Lua VM-level mechanism — the C runtime wraps certain return values in a "black box" that tainted (addon) code cannot inspect or compute on.

Restrictions are **conditional** — they only activate during:
- Active Mythic Keystone run
- Active PvP match
- Active instance encounter / boss fight
- Player in combat (varies per API)

Outside these contexts, most APIs return plain numbers. `issecretvalue(x)` returns `false` in open world. Test your addon in actual combat or M+.

---

## Which APIs return secret values (confirmed)

| API | Notes |
|---|---|
| `UnitHealth(unit)` | Secret during instances/encounters/M+ |
| `UnitHealthMax(unit)` | Secret for **enemy** units; **plain for player** as of 12.0 |
| `UnitPower(unit, powerType)` | Secret (primary resources: mana, energy, rage, etc.) |
| `UnitPowerMax(unit, powerType)` | Plain for **player**; secret for others |
| `UnitHealthMissing(unit)` | New in 12.0; always secret |
| `UnitPowerMissing(unit)` | New in 12.0; always secret |
| `UnitGetTotalAbsorbs(unit)` | Secret when shield active; plain `0` when no shield |
| `UnitGetTotalHealAbsorbs(unit)` | Secret |
| `UnitStagger(unit)` | Secret; **non-secret for player unit** |
| `UnitHealthPercent(unit)` | New in 12.0; see §New APIs below |

**NOT secret:**
- `GetRaidTargetIndex(unit)` — plain number 1–8 or nil. However, if called inside Blizzard's `SetRaidTarget` protected callback, it returns a secret number (context contamination, not by API design). Fix: defer with `C_Timer.After(0, ...)`. See G-077.
- Secondary resources: Combo Points, Runes, Soul Shards, Holy Power, Chi, Arcane Charges, Essence — never secret.

---

## Operations FORBIDDEN on secret values (in tainted code)

| Operation | Error |
|---|---|
| Arithmetic: `+ - * / % ^` | `attempt to perform arithmetic on a secret value` |
| Comparison: `== ~= < > <= >=` | `attempt to compare secret value` (returns tainted bool) |
| Table lookup as KEY: `t[secret]` | `table index is secret` |
| `math.floor(secret)` | Error (arithmetic) |
| `tonumber(secret)` | Blocked |
| `if secret then` / `not secret` | Tainted boolean — propagates silently |
| Saving to SavedVariables | Serialized as `nil` silently |

**`== nil` is explicitly SAFE** — you can always check `if GetRaidTargetIndex(unit) == nil then`.

---

## Operations SAFE on secret values

| Operation | Notes |
|---|---|
| Store in variable | `local hp = UnitHealth("target")` — fine |
| Store in table VALUE: `t.hp = secret` | Fine (value slot, not key) |
| `bar:SetValue(secret)` | C function accepts secrets directly |
| `bar:SetMinMaxValues(0, secret)` | C function |
| `string.format("%d", secret)` | Returns **secret string** (not error) |
| `secret .. " text"` | Concatenation ok; result is secret string |
| `AbbreviateNumbers(secret)` | Returns secret string |
| `WrapTextInColorCode(secret)` | Returns secret string |
| `type(secret)` | Returns actual type string `"number"` |
| `issecretvalue(secret)` | Returns plain bool |
| `canaccessvalue(secret)` | Returns plain bool |
| `== nil` comparison | Safe |
| `pcall(func, secret)` | Legal to pass through; ~10x overhead |
| `frame:SetAlphaFromBoolean(secretBool)` | New in 12.0; widget accepts secret bool |
| `frame:SetVertexColorFromBoolean(secretBool)` | New in 12.0 |
| `C_CurveUtil.EvaluateColorFromBoolean(secretBool)` | New in 12.0 |

---

## issecretvalue() and friends

```lua
issecretvalue(v)         -- true if v is secret, false if plain
canaccessvalue(v)        -- true if current context can access v
hasanysecretvalues(...)  -- true if any arg is secret
canaccesssecrets()       -- true if current context has secret access
```

All are `AllowedWhenUntainted` — callable from any tainted addon code.

**Canonical pattern for absorb detection:**
```lua
local ok, rawAbsorb = pcall(UnitGetTotalAbsorbs, unit)
if ok and rawAbsorb ~= nil then
    hasAbsorb = issecretvalue(rawAbsorb)  -- true = shield present, false = no shield
end
```

---

## New APIs in 12.0 that replace secret-prone patterns

### `UnitHealthPercent(unit [, usePredicted [, curve]])`
- **No args:** returns plain float 0.0–100.0. This is the key replacement for `math.floor(UnitHealth/UnitHealthMax * 100)`.
- **With `CurveConstants.ScaleTo100`:** Same, scaled through a curve.
```lua
local pct = UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
-- pct is a plain number, safe for math.floor, string.format, etc.
```

### `CurveConstants` global
- `CurveConstants.ScaleTo100` — linear 0→0, 1→100
- `CurveConstants.Reverse` — linear 0→1, 1→0
- `CurveConstants.ReverseTo100` — linear 0→100, 1→0

### `C_Secrets` namespace
Query restriction state before attempting work:
```lua
if not C_Secrets.HasSecretRestrictions() then
    -- safe to do math on unit values
end
```
Notable predicates: `ShouldUnitHealthMaxBeSecret`, `ShouldUnitPowerBeSecret`, `ShouldUnitAuraIndexBeSecret`, `ShouldSpellCooldownBeSecret`.

### `StatusBar:SetAlphaFromBoolean(secretBool)` / `SetVertexColorFromBoolean`
Lets you drive visibility from a secret boolean without `if secretBool then`.

### Test CVars (addon development only)
Simulate restricted state without being in M+/raid:
- `secretUnitPowerForced`
- `secretUnitPowerMaxForced`
- `secretAurasForced`
- `secretCooldownsForced`

---

## Tainted booleans — propagation

Any comparison of a secret value produces a **tainted boolean**. Tainted booleans propagate: any value derived from them is also tainted.

```lua
local hp = UnitHealth("target")  -- secret
local isLow = (hp < 20000)       -- ERRORS: attempt to compare secret value
-- Even if it didn't error, isLow would be a tainted boolean
-- if isLow then                  -- ERRORS: tainted boolean coercion
```

If you need to branch on health — use `C_Secrets.ShouldUnitComparisonBeSecret()` to check first, or restructure to use `UnitHealthPercent` for the plain-number path.

---

## Quick reference: TWW (11.x) vs Midnight (12.x)

| | TWW 11.x | Midnight 12.x |
|---|---|---|
| Secret values system | Does not exist | Introduced |
| `UnitHealth` | Always plain | Secret in combat/instances |
| `UnitHealthMax` | Always plain | Plain for player; secret for enemies |
| `UnitHealthPercent` | Does not exist | New; returns plain float |
| `issecretvalue()` | Does not exist | New global |
| `C_Secrets` namespace | Does not exist | 18+ new functions |
| `SetRaidTarget` | Unprotected | **Protected** (combat lockdown) |
| `UnitGetTotalAbsorbs` | Plain number | Secret when shield active |
| SavedVariables with secrets | N/A | Silently nil |
| Interface version | 110000+ | 120000+ |
