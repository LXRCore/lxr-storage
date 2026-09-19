--[[ ═══════════════════════════════════════════════════════════════════════════
     LXR-STORAGE — Client: the keeper, the doors, the book
     © 2026 iBoss21 / LXRCore — All Rights Reserved
     ═══════════════════════════════════════════════════════════════════════════ ]]

local LXRCore = exports['lxr-core']:GetCoreObject()
local LXR = exports['lxr-core']:GetLXR()
local N = Citizen.InvokeNative
local keepers, open, current = {}, false, nil

local function toast(key, kind, vars) LXRCore.Notify(Lang:t(key, vars), kind or 'info') end
local function page(action, payload) SendNUIMessage({ action = action, payload = payload, brand = LXRCore.Brand, lang = Config.Lang, locale = Lang.bundle() }) end
local function close() if not open then return end open = false current = nil SetNuiFocus(false, false) page('close') end
local function openBook(yard)
    if open then return end
    local ok, data = LXR.RPC.Server('lxr-storage:open', yard.id)
    if not ok then return toast('error.' .. tostring(data), 'error') end
    open = true current = yard
    SetNuiFocus(true, true)
    page('open', data)
end

RegisterNUICallback('close', function(_, cb) close() cb({ ok = true }) end)
RegisterNUICallback('rent', function(d, cb)
    if not current then return cb({ ok = false }) end
    local ok, res, extra = LXR.RPC.Server('lxr-storage:rent', current.id, d.no, d.days)
    if not ok then toast('error.' .. tostring(res), 'error', { amount = extra and ('%.2f'):format(extra) }) return cb({ ok = false }) end
    toast('info.rented', 'success')
    cb({ ok = true, data = res })
end)
RegisterNUICallback('manage', function(d, cb)
    if not current then return cb({ ok = false }) end
    local arg = d.arg
    if d.what == 'key' then
        local p, dist = LXRCore.Functions.GetClosestPlayer()
        if p == -1 or dist > 3.0 then toast('error.nobody', 'error') return cb({ ok = false }) end
        arg = GetPlayerServerId(p)
    end
    local ok, res, extra = LXR.RPC.Server('lxr-storage:manage', current.id, d.no, d.what, arg)
    if not ok then toast('error.' .. tostring(res), 'error', { amount = extra and ('%.2f'):format(extra) }) return cb({ ok = false }) end
    cb({ ok = true, data = res })
end)

-- the door: a prompt that lists what you may open, or asks for a combination
local function atDoor(yard)
    local ok, list, law = LXR.RPC.Server('lxr-storage:doors', yard.id)
    if not ok then return end
    local options = {}
    for _, u in ipairs(list) do
        options[#options + 1] = { label = ('%s %d%s'):format(Lang:t('ui.unit'), u.no, u.state == 'padlocked' and (' — ' .. Lang:t('ui.padlocked')) or ''), onSelect = function()
            local ok2, err = LXR.RPC.Server('lxr-storage:enter', yard.id, u.no)
            if not ok2 then toast('error.' .. tostring(err), 'error') end
        end }
    end
    options[#options + 1] = { label = Lang:t('ui.with_code'), onSelect = function()
        exports['lxr-nui']:Input({ title = Lang:t('ui.with_code'), fields = { { id = 'no', label = Lang:t('ui.unit'), type = 'number', min = 1 }, { id = 'code', label = Lang:t('ui.code'), type = 'number' } } }, function(v)
            if not v then return end
            local ok2, err = LXR.RPC.Server('lxr-storage:enter', yard.id, tonumber(v.no), tostring(v.code or ''))
            if not ok2 then toast('error.' .. tostring(err), 'error') end
        end)
    end }
    if law then
        options[#options + 1] = { label = Lang:t('ui.search'), onSelect = function()
            local items = {}
            for _, u in ipairs(law) do
                items[#items + 1] = { label = ('%s %d · %s · %s'):format(Lang:t('ui.unit'), u.no, Lang:t('ui.size_' .. u.size), u.tenant or '?'), onSelect = function()
                    local ok2, err = LXR.RPC.Server('lxr-storage:search', yard.id, u.no)
                    if not ok2 then toast('error.' .. tostring(err), 'error') end
                end }
            end
            if #items == 0 then return toast('error.not_rented', 'error') end
            exports['lxr-nui']:Menu({ title = Lang:t('ui.search'), items = items }, function() end)
        end }
    end
    exports['lxr-nui']:Menu({ title = yard.label, items = options }, function() end)
end

local function spawnKeeper(y)
    local model = joaat(y.keeper.ped)
    if not IsModelValid(model) then return end
    RequestModel(model)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < t do Wait(10) end
    if not HasModelLoaded(model) then return end
    local ped = CreatePed(model, y.keeper.coords.x, y.keeper.coords.y, y.keeper.coords.z - 1.0, y.keeper.heading or 0.0, false, false, false, false)
    N(0x283978A15512B2FE, ped, true)
    SetEntityInvincible(ped, true) SetBlockingOfNonTemporaryEvents(ped, true) FreezeEntityPosition(ped, true)
    SetModelAsNoLongerNeeded(model)
    keepers[y.id] = ped
    exports['lxr-interact']:AddEntity('lxr-storage:keeper:' .. y.id, ped, { label = y.label, distance = Config.Security.promptDistance, options = { { label = Lang:t('ui.the_book'), key = 'J', onSelect = function() openBook(y) end } } })
end
local function removeKeeper(y)
    local ped = keepers[y.id]
    if not ped then return end
    exports['lxr-interact']:Remove('lxr-storage:keeper:' .. y.id)
    if DoesEntityExist(ped) then DeleteEntity(ped) end
    keepers[y.id] = nil
end

CreateThread(function()
    while GetResourceState('lxr-interact') ~= 'started' do Wait(1000) end
    for _, y in ipairs(Config.Yards) do
        exports['lxr-interact']:AddPoint('lxr-storage:door:' .. y.id, y.door, { label = Lang:t('ui.units'), distance = Config.Security.promptDistance, options = { { label = Lang:t('ui.open_unit'), key = 'J', onSelect = function() atDoor(y) end } } })
        if y.blip then
            local b = N(0x554D9D53F696D002, 1664425300, y.keeper.coords.x, y.keeper.coords.y, y.keeper.coords.z)
            if b and b ~= 0 then N(0x74F74D3207ED525C, b, joaat('blip_shop_store'), true) if GetResourceState('lxr-mapcolor') == 'started' then pcall(function() N(0x662D364ABF16DE2F, b, exports['lxr-mapcolor']:modifier('storage')) end) end N(0x9CB1A1623062F402, b, y.label) end
        end
    end
    while true do
        if LocalPlayer.state.isLoggedIn then
            local pos = GetEntityCoords(PlayerPedId())
            for _, y in ipairs(Config.Yards) do
                local d = #(pos - y.keeper.coords)
                if d < 60.0 and not keepers[y.id] then spawnKeeper(y) elseif d > 80.0 and keepers[y.id] then removeKeeper(y) end
            end
        end
        Wait(2000)
    end
end)

RegisterNetEvent('lxr:client:unloaded', function() close() for _, y in ipairs(Config.Yards) do removeKeeper(y) end end)
AddEventHandler('onResourceStop', function(res) if res == GetCurrentResourceName() then close() for _, y in ipairs(Config.Yards) do removeKeeper(y) exports['lxr-interact']:Remove('lxr-storage:door:' .. y.id) end end end)
exports('IsOpen', function() return open end)
