--[[ ═══════════════════════════════════════════════════════════════════════════
     LXR-STORAGE — Server: the keeper's book
     © 2026 iBoss21 / LXRCore — All Rights Reserved
     ═══════════════════════════════════════════════════════════════════════════ ]]

local LXRCore = exports['lxr-core']:GetCoreObject()
local LXR = exports['lxr-core']:GetLXR()
local S = LXRStorage
local RES = GetCurrentResourceName()
local units = {}    -- yard → no → unit { yard, no, size, citizenid, until_, code, keys }
local buckets = {}

local function limited(src)
    local b = buckets[src]
    local now = GetGameTimer()
    if not b or now - b.at > Config.Security.rateLimit.windowMs then b = { at = now, n = 0 } buckets[src] = b end
    b.n = b.n + 1
    return b.n > Config.Security.rateLimit.burst
end
local function player(src) return LXRCore.Functions.GetPlayer(src) end
local function near(src, c)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and #(GetEntityCoords(ped) - vector3(c.x, c.y, c.z)) <= Config.Security.maxDistance
end
local function nameOf(cid)
    local P = LXRCore.Functions.GetPlayerByCitizenId(cid) or LXRCore.Functions.GetOfflinePlayerByCitizenId(cid)
    local c = P and P.PlayerData and P.PlayerData.charinfo
    return c and ((c.firstname or '') .. ' ' .. (c.lastname or '')) or cid
end

LXRCore.DB.RegisterMigration(RES, '0001_storage', [[
CREATE TABLE IF NOT EXISTS `lxr_storage_units` (
  `yard` VARCHAR(32) NOT NULL,
  `no` INT NOT NULL,
  `size` VARCHAR(16) NOT NULL,
  `citizenid` VARCHAR(50) NULL,
  `until_` INT NOT NULL DEFAULT 0,
  `code` VARCHAR(8) NULL,
  `keys` TEXT NULL,
  PRIMARY KEY (`yard`, `no`), KEY `citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]])

local function save(u)
    LXRCore.DB.UpdateAsync('INSERT INTO lxr_storage_units (yard, no, size, citizenid, until_, code, keys) VALUES (?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE size = VALUES(size), citizenid = VALUES(citizenid), until_ = VALUES(until_), code = VALUES(code), keys = VALUES(keys)',
        { u.yard, u.no, u.size, u.citizenid, u.until_ or 0, u.code, json.encode(u.keys or {}) })
end

-- lay the yards out: every configured unit exists in memory; tenancy rows come from the book
CreateThread(function()
    Wait(1000)
    for _, y in ipairs(Config.Yards) do
        units[y.id] = {}
        local no = 0
        for _, sz in ipairs(S.SizeOrder()) do for _ = 1, (y.units[sz.id] or 0) do no = no + 1 units[y.id][no] = { yard = y.id, no = no, size = sz.id, keys = {} } end end
    end
    local rows = LXRCore.DB.Query('SELECT yard, no, size, citizenid, until_, code, keys FROM lxr_storage_units') or {}
    for _, r in ipairs(rows) do
        local u = units[r.yard] and units[r.yard][r.no]
        if u then u.citizenid = r.citizenid u.until_ = r.until_ u.code = r.code u.keys = json.decode(r.keys or '[]') or {} u.size = r.size or u.size end
    end
    if Config.Debug.printBanner then local n = 0 for _, y in pairs(units) do for _ in pairs(y) do n = n + 1 end end print(('^1[lxr-storage]^7 v%s — %d yards, %d units, %d tenancies'):format(GetResourceMetadata(RES, 'version', 0), #Config.Yards, n, #rows)) end
end)

local function public(u, cid, now)
    local st = S.State(u, now)
    local mine = u.citizenid == cid
    return { no = u.no, size = u.size, state = st, mine = mine, key = (not mine) and S.MayOpen(u, cid) or false, daysLeft = mine and S.DaysLeft(u, now) or nil, code = mine and (u.code ~= nil) or nil, keys = mine and u.keys or nil, tenant = (mine or S.MayOpen(u, cid)) and nameOf(u.citizenid) or nil }
end
local function book(src, yard)
    local P = player(src)
    local cid = P.PlayerData.citizenid
    local now = os.time()
    local list = {}
    for no, u in pairs(units[yard.id] or {}) do list[#list + 1] = public(u, cid, now) end
    table.sort(list, function(a, b) return a.no < b.no end)
    local sizes = {}
    for _, sz in ipairs(S.SizeOrder()) do sizes[#sizes + 1] = { id = sz.id, slots = sz.slots, weight = sz.weight, rent = S.Price(yard, sz.id, 1) } end
    return { yard = { id = yard.id, label = yard.label }, units = list, sizes = sizes, cash = P.PlayerData.money[Config.Rent.account] or 0, maxDays = Config.Rent.maxDays, graceDays = Config.Rent.graceDays, maxKeys = Config.Rent.keys }
end
local function mine(cid)
    local n = 0
    for _, y in pairs(units) do for _, u in pairs(y) do if u.citizenid == cid then n = n + 1 end end end
    return n
end

LXR.RPC.Register('lxr-storage:open', function(src, yardId)
    if limited(src) then return false, 'rate' end
    local P, yard = player(src), S.Yard(yardId)
    if not P or not yard then return false, 'invalid' end
    if not near(src, yard.keeper.coords) then return false, 'too_far' end
    return true, book(src, yard)
end)

LXR.RPC.Register('lxr-storage:rent', function(src, yardId, no, days)
    if limited(src) then return false, 'rate' end
    local P, yard = player(src), S.Yard(yardId)
    local u = yard and units[yard.id] and units[yard.id][tonumber(no) or 0]
    if not P or not u then return false, 'invalid' end
    if not near(src, yard.keeper.coords) then return false, 'too_far' end
    local now, cid = os.time(), P.PlayerData.citizenid
    local st = S.State(u, now)
    local price, d = S.Price(yard, u.size, days)
    if st == 'free' or st == 'cleared' then
        if mine(cid) >= Config.Rent.maxUnitsPerCitizen then return false, 'too_many' end
        if st == 'cleared' and GetResourceState('lxr-inventory') == 'started' then exports['lxr-inventory']:ClearStash(S.StashId(u)) end
        if not P.Functions.RemoveMoney(Config.Rent.account, price, 'storage:' .. yard.id) then return false, 'no_money', price end
        u.citizenid, u.until_, u.code, u.keys = cid, now + d * 86400, nil, {}
    elseif u.citizenid == cid then
        local from = math.max(now, u.until_ or 0)
        if (from - now) / 86400 + d > Config.Rent.maxDays then return false, 'too_far_ahead' end
        if not P.Functions.RemoveMoney(Config.Rent.account, price, 'storage:' .. yard.id) then return false, 'no_money', price end
        u.until_ = from + d * 86400
    else return false, 'taken' end
    save(u)
    LXRCore.Emit('lxr:storage:rented', nil, src, yard.id, u.no, d, price)
    if Config.Debug.log then LXRCore.Log.info('storage', ('%s unit %d for %d days ($%.2f)'):format(yard.id, u.no, d, price), { source = src }) end
    return true, book(src, yard)
end)

LXR.RPC.Register('lxr-storage:manage', function(src, yardId, no, what, arg)
    if limited(src) then return false, 'rate' end
    local P, yard = player(src), S.Yard(yardId)
    local u = yard and units[yard.id] and units[yard.id][tonumber(no) or 0]
    if not P or not u then return false, 'invalid' end
    if not near(src, yard.keeper.coords) then return false, 'too_far' end
    local cid = P.PlayerData.citizenid
    if u.citizenid ~= cid then return false, 'not_yours' end
    if what == 'code' then
        local code = tostring(arg or ''):gsub('%D', '')
        if #code ~= 0 and (#code < 3 or #code > 6) then return false, 'bad_code' end
        u.code = #code > 0 and code or nil
    elseif what == 'key' then
        local T = LXRCore.Functions.GetPlayer(tonumber(arg) or -1)
        if not T or T == P then return false, 'nobody' end
        if #u.keys >= Config.Rent.keys then return false, 'too_many_keys' end
        local tcid = T.PlayerData.citizenid
        for _, k in ipairs(u.keys) do if k == tcid then return false, 'has_key' end end
        u.keys[#u.keys + 1] = tcid
        LXRCore.Notify(T.PlayerData.source, Lang:t('info.got_key', { yard = yard.label, no = u.no }), 'success')
    elseif what == 'unkey' then
        for i, k in ipairs(u.keys) do if k == arg then table.remove(u.keys, i) break end end
    elseif what == 'upgrade' then
        local cost = S.UpgradeCost(yard, u.size, tostring(arg), S.DaysLeft(u, os.time()))
        if not cost then return false, 'invalid' end
        local target
        for n2, u2 in pairs(units[yard.id]) do if u2.size == arg and S.State(u2, os.time()) == 'free' then target = u2 break end end
        if not target then return false, 'none_free' end
        if not P.Functions.RemoveMoney(Config.Rent.account, cost, 'storage:upgrade') then return false, 'no_money', cost end
        target.citizenid, target.until_, target.code, target.keys = cid, u.until_, u.code, u.keys
        u.citizenid, u.until_, u.code, u.keys = nil, 0, nil, {}
        if GetResourceState('lxr-inventory') == 'started' then
            local items = exports['lxr-inventory']:GetStashItems(S.StashId(u))
            for _, it in ipairs(items or {}) do exports['lxr-inventory']:AddStashItem(S.StashId(target), it.name, it.amount, it.info) end
            exports['lxr-inventory']:ClearStash(S.StashId(u))
        end
        save(target)
    elseif what == 'give_up' then
        if GetResourceState('lxr-inventory') == 'started' then exports['lxr-inventory']:ClearStash(S.StashId(u)) end
        u.citizenid, u.until_, u.code, u.keys = nil, 0, nil, {}
    else return false, 'invalid' end
    save(u)
    return true, book(src, yard)
end)

---at the door: open a unit (tenant, key holder, or anyone with the combination)
LXR.RPC.Register('lxr-storage:enter', function(src, yardId, no, code)
    if limited(src) then return false, 'rate' end
    local P, yard = player(src), S.Yard(yardId)
    local u = yard and units[yard.id] and units[yard.id][tonumber(no) or 0]
    if not P or not u then return false, 'invalid' end
    if not near(src, yard.door) then return false, 'too_far' end
    local st = S.State(u, os.time())
    if st ~= 'paid' then return false, st == 'locked' and 'padlocked' or 'not_rented' end
    local cid = P.PlayerData.citizenid
    local may = S.MayOpen(u, cid) or (u.code and tostring(code or '') == u.code)
    if not may then return false, 'no_key' end
    if GetResourceState('lxr-inventory') ~= 'started' then return false, 'invalid' end
    local sz = Config.Sizes[u.size]
    exports['lxr-inventory']:OpenInventory(src, 'stash', S.StashId(u), { label = ('%s · %s %d'):format(yard.label, Lang:t('ui.unit'), u.no), slots = sz.slots, weight = sz.weight })
    LXRCore.Emit('lxr:storage:opened', nil, src, yard.id, u.no)
    return true
end)

---the law at the door: search a rented unit; the tenant hears of it
LXR.RPC.Register('lxr-storage:search', function(src, yardId, no)
    if limited(src) then return false, 'rate' end
    local P, yard = player(src), S.Yard(yardId)
    local u = yard and units[yard.id] and units[yard.id][tonumber(no) or 0]
    if not P or not u then return false, 'invalid' end
    if not S.MayLaw(P.PlayerData.job) then LXRCore.Log.exploit(src, 'storage search without the law', { yard = yardId }) return false, 'not_law' end
    if not near(src, yard.door) then return false, 'too_far' end
    if not u.citizenid then return false, 'not_rented' end
    if GetResourceState('lxr-inventory') ~= 'started' then return false, 'invalid' end
    local sz = Config.Sizes[u.size]
    exports['lxr-inventory']:OpenInventory(src, 'stash', S.StashId(u), { label = ('%s · %s %d · %s'):format(yard.label, Lang:t('ui.unit'), u.no, Lang:t('ui.search')), slots = sz.slots, weight = sz.weight })
    if Config.Search.tellTenant then
        local T = LXRCore.Functions.GetPlayerByCitizenId(u.citizenid)
        if T then LXRCore.Notify(T.PlayerData.source, Lang:t('info.searched', { yard = yard.label, no = u.no }), 'info') end
    end
    LXRCore.Log.info('storage', 'unit searched by the law', { source = src, citizenid = P.PlayerData.citizenid, yard = yard.id, no = u.no, tenant = u.citizenid })
    LXRCore.Emit('lxr:storage:searched', nil, src, yard.id, u.no, u.citizenid)
    return true
end)

---which units at a yard may I open (for the door's prompt list)
LXR.RPC.Register('lxr-storage:doors', function(src, yardId)
    local P, yard = player(src), S.Yard(yardId)
    if not P or not yard then return false, 'invalid' end
    local cid, now, out = P.PlayerData.citizenid, os.time(), {}
    for no, u in pairs(units[yard.id] or {}) do if S.MayOpen(u, cid) then out[#out + 1] = { no = no, state = S.State(u, now), mine = u.citizenid == cid } end end
    table.sort(out, function(a, b) return a.no < b.no end)
    local law = nil
    if S.MayLaw(P.PlayerData.job) then
        law = {}
        for no, u in pairs(units[yard.id] or {}) do if u.citizenid then law[#law + 1] = { no = no, size = u.size, tenant = nameOf(u.citizenid) } end end
        table.sort(law, function(a, b) return a.no < b.no end)
    end
    return true, out, law
end)

-- rent runs on the clock: the hour tick pads nothing, it only clears what is a month unpaid
CreateThread(function()
    while true do
        Wait(3600000)
        local now = os.time()
        for _, y in pairs(units) do for _, u in pairs(y) do
            if u.citizenid and S.State(u, now) == 'cleared' then
                if GetResourceState('lxr-inventory') == 'started' then exports['lxr-inventory']:ClearStash(S.StashId(u)) end
                LXRCore.Log.info('storage', ('unit %s:%d cleared (unpaid %d days)'):format(u.yard, u.no, Config.Rent.graceDays))
                u.citizenid, u.until_, u.code, u.keys = nil, 0, nil, {}
                save(u)
            end
        end end
    end
end)

AddEventHandler('playerDropped', function() buckets[source] = nil end)
exports('UnitsOf', function(cid) local out = {} for _, y in pairs(units) do for _, u in pairs(y) do if u.citizenid == cid then out[#out + 1] = { yard = u.yard, no = u.no, size = u.size, until_ = u.until_ } end end end return out end)
exports('MayOpen', function(cid, yard, no) local u = units[yard] and units[yard][no] return u ~= nil and S.MayOpen(u, cid) end)
