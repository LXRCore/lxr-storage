--[[ ═══════════════════════════════════════════════════════════════════════════
     LXR-STORAGE — Shared rules: the keeper's arithmetic
     © 2026 iBoss21 / LXRCore — All Rights Reserved
     ═══════════════════════════════════════════════════════════════════════════ ]]

LXRStorage = LXRStorage or {}
local S = LXRStorage

function S.Yard(id) for _, y in ipairs(Config.Yards) do if y.id == id then return y end end end

---Rent for `days` of a size at a yard.
function S.Price(yard, size, days)
    local sz = Config.Sizes[size]
    if not sz then return nil end
    days = math.max(1, math.min(Config.Rent.maxDays, math.floor(tonumber(days) or 1)))
    return math.floor(sz.rent * days * (yard.priceMult or 1) * 100 + 0.5) / 100, days
end

---Unit state at `now` from its paid-until timestamp: 'free' | 'paid' | 'locked' | 'cleared'.
function S.State(unit, now)
    if not unit or not unit.citizenid then return 'free' end
    if now <= (unit.until_ or 0) then return 'paid' end
    if now <= (unit.until_ or 0) + Config.Rent.graceDays * 86400 then return 'locked' end
    return 'cleared'
end

---Days left (fractional, never negative).
function S.DaysLeft(unit, now) return math.max(0, ((unit.until_ or 0) - now) / 86400) end

---Does a citizen hold this unit or a key to it?
function S.MayOpen(unit, citizenid)
    if not unit or not unit.citizenid then return false end
    if unit.citizenid == citizenid then return true end
    for _, k in ipairs(unit.keys or {}) do if k == citizenid then return true end end
    return false
end

---The stash id an inventory opens for a unit.
---May this job search units? (type, duty and grade from Config.Search)
function S.MayLaw(job)
    local c = Config.Search
    if not c.enabled or not job then return false end
    local def = LXRShared.Jobs[job.name]
    if not def then return false end
    local ok = false
    for _, t in ipairs(c.jobTypes) do if def.type == t then ok = true end end
    if not ok then return false end
    if c.onDuty and not job.onduty then return false end
    return (tonumber(job.grade) or 0) >= (c.minGrade or 0)
end

function S.StashId(unit) return ('storage:%s:%d'):format(unit.yard, unit.no) end

---Upgrade cost: the rent difference for the days left (never below one day of the new size).
function S.UpgradeCost(yard, fromSize, toSize, daysLeft)
    local a, b = Config.Sizes[fromSize], Config.Sizes[toSize]
    if not a or not b or b.rent <= a.rent then return nil end
    local days = math.max(1, math.ceil(daysLeft))
    return math.floor((b.rent - a.rent) * days * (yard.priceMult or 1) * 100 + 0.5) / 100
end

---Sizes in rent order.
function S.SizeOrder()
    local out = {}
    for k, v in pairs(Config.Sizes) do out[#out + 1] = { id = k, rent = v.rent, slots = v.slots, weight = v.weight } end
    table.sort(out, function(x, y) return x.rent < y.rent end)
    return out
end
