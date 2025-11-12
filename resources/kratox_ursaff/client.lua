local ESX = nil
local fiscalPed = nil
local playerIsBoss = false

------------------------------------------------------
-- 🔹 Initialisation ESX
------------------------------------------------------
CreateThread(function()
    while ESX == nil do
        TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
        Wait(100)
    end

    while not ESX.IsPlayerLoaded() do Wait(500) end
    Wait(1000)
    CheckIfBoss()
end)

RegisterNetEvent('esx:playerLoaded', function()
    Wait(1000)
    CheckIfBoss()
end)

RegisterNetEvent('esx:setJob', function()
    Wait(500)
    CheckIfBoss()
end)

------------------------------------------------------
-- 🔹 Vérifie si le joueur est patron
------------------------------------------------------
function CheckIfBoss()
    local job = ESX.GetPlayerData().job
    local isBossNow = job and job.grade_name and tableHasValue(Config.BossGradeNames, job.grade_name)

    if isBossNow and not playerIsBoss then
        playerIsBoss = true
        spawnFiscalPed()
    elseif not isBossNow and playerIsBoss then
        playerIsBoss = false
        deleteFiscalPed()
    end
end

------------------------------------------------------
-- 🔹 Gestion du PNJ fiscal
------------------------------------------------------
function spawnFiscalPed()
    if fiscalPed and DoesEntityExist(fiscalPed) then return end

    loadModel(Config.Ped.model or 'cs_bankman')
    local ped = CreatePed(4, GetHashKey(Config.Ped.model or 'cs_bankman'),
        Config.Ped.coords.x, Config.Ped.coords.y, Config.Ped.coords.z - 1.0,
        Config.Ped.heading or 180.0, false, true)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    fiscalPed = ped
end

function deleteFiscalPed()
    if fiscalPed and DoesEntityExist(fiscalPed) then
        DeleteEntity(fiscalPed)
        fiscalPed = nil
    end
end

function loadModel(model)
    local hash = GetHashKey(model)
    RequestModel(hash)
    while not HasModelLoaded(hash) do Wait(10) end
end

------------------------------------------------------
-- 🔹 Interaction joueur (E)
------------------------------------------------------
CreateThread(function()
    while true do
        local sleep = 1000

        if playerIsBoss and fiscalPed and DoesEntityExist(fiscalPed) then
            local pCoords = GetEntityCoords(PlayerPedId())
            local dist = #(pCoords - Config.Ped.coords)

            if dist < 3.0 then
                sleep = 0
                DrawMarker(2, Config.Ped.coords.x, Config.Ped.coords.y, Config.Ped.coords.z + 1.0,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    0.3, 0.3, 0.3, 108, 96, 255, 180, false, true, 2)
                if dist < 1.5 then
                    ShowHelpNotification("Appuyez sur ~INPUT_CONTEXT~ pour ~p~accéder au service fiscal~s~")
                    if IsControlJustReleased(0, 38) then openFiscal() end
                end
            end
        end

        Wait(sleep)
    end
end)

------------------------------------------------------
-- 🔹 Notifications ESX / OX
------------------------------------------------------
RegisterNetEvent('fiscal:notify', function(type, msg)
    if Config.UseOxNotify then
        exports.ox_lib:notify({
            type = (type == 'error' and 'error' or 'success'),
            description = msg
        })
    else
        SetNotificationTextEntry('STRING')
        AddTextComponentString(msg)
        DrawNotification(false, true)
    end
end)

------------------------------------------------------
-- 🔹 Historique / callbacks client
------------------------------------------------------
RegisterNetEvent('fiscal:updateHistory', function(history)
    SendNUIMessage({ action = 'updateHistory', history = history or {} })
end)

RegisterNetEvent('fiscal:alreadyDeclared', function()
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'alreadyDeclared',
        message = "⚠️ Vous avez déjà effectué une déclaration cette semaine."
    })
end)

------------------------------------------------------
-- 🔹 Commande alternative
------------------------------------------------------
if Config.EnableCommand then
    RegisterCommand(Config.CommandName, function() openFiscal() end, false)
end

------------------------------------------------------
-- 🔹 Ouverture du menu fiscal
------------------------------------------------------
function openFiscal()
    local job = ESX.GetPlayerData().job
    if not job or not job.name then
        return TriggerEvent('fiscal:notify', 'error', "Métier introuvable.")
    end

    ESX.TriggerServerCallback('fiscal:getInit', function(data)
        if not data or not data.ok then
            return TriggerEvent('fiscal:notify', 'error', data and data.msg or "Erreur init fiscale.")
        end

        SetNuiFocus(true, true)
        SendNUIMessage({
            action = 'open',
            society = job.name,
            rate = data.rate,
            weeklyBlocked = data.weeklyBlocked,
            history = data.history or {}
        })
    end, job.name)
end

------------------------------------------------------
-- 🔹 NUI callbacks
------------------------------------------------------
RegisterNUICallback('close', function(_, cb)
    SetNuiFocus(false, false)
    cb({ ok = true })
end)

RegisterNUICallback('declare', function(data, cb)
    local amount = tonumber(data.amount or 0)
    local link = tostring(data.link or '')
    local job = ESX.GetPlayerData().job

    if not job or not job.name then
        return cb({ ok = false, msg = 'Métier introuvable.' })
    end
    if not amount or amount <= 0 then
        return cb({ ok = false, msg = 'Montant invalide.' })
    end

    TriggerServerEvent('fiscal:serverDeclare', job.name, amount, link)
    cb({ ok = true })
end)

RegisterNUICallback('payDebt', function(_, cb)
    local job = ESX.GetPlayerData().job
    if not job or not job.name then
        return cb({ ok = false, msg = 'Métier introuvable.' })
    end
    TriggerServerEvent('fiscal:payDebt', job.name)
    cb({ ok = true })
end)

RegisterNUICallback('payDebtById', function(data, cb)
    local id = tonumber(data.id)
    if not id then return cb({ ok = false, msg = 'ID manquant.' }) end
    TriggerServerEvent('fiscal:payDebtById', id)
    cb({ ok = true })
end)

RegisterNUICallback('openLink', function(data, cb)
    if not data.link or data.link == '' then return cb({ ok = false }) end
    SendNUIMessage({ action = 'openUrl', url = data.link })
    cb({ ok = true })
end)

------------------------------------------------------
-- 🔹 Fiche comptable
------------------------------------------------------
RegisterNUICallback('openAccountingPopup', function(data, cb)
    local declId = tonumber(data.id)
    if not declId then return cb({ ok = false }) end
    SendNUIMessage({ action = 'showAccountingPopup', id = declId })
    cb({ ok = true })
end)

RegisterNUICallback('sendAccountingLink', function(data, cb)
    local declId = tonumber(data.id)
    if not declId then
        TriggerEvent('fiscal:notify', 'error', "ID invalide.")
        cb({ ok = false })
        return
    end

    TriggerServerEvent('fiscal:sendAccountingLink', declId)
    TriggerEvent('fiscal:notify', 'success', "📄 Fiche comptable envoyée sur Discord.")
    cb({ ok = true })
end)


------------------------------------------------------
-- 🔹 Fonctions utilitaires
------------------------------------------------------
function ShowHelpNotification(msg)
    BeginTextCommandDisplayHelp("STRING")
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

function tableHasValue(tbl, val)
    for _, v in pairs(tbl or {}) do
        if v == val then return true end
    end
    return false
end

