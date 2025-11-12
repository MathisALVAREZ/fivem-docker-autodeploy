local ESX
TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)

-- ============================
-- 🧩 UTILITAIRES
-- ============================

local function isBoss(xPlayer)
    if not xPlayer or not xPlayer.job then return false end
    local grade = (xPlayer.job.grade_name or tostring(xPlayer.job.grade) or ''):lower()
    for _, g in ipairs(Config.BossGradeNames) do
        if grade == tostring(g):lower() then return true end
    end
    return false
end

local function sendWebhook(url, embed)
    if not url or url == '' then return end
    PerformHttpRequest(url, function() end, 'POST',
        json.encode({ username = 'Service Fiscal', embeds = { embed }}),
        { ['Content-Type'] = 'application/json' }
    )
end

local function getSharedAccount(name, cb)
    TriggerEvent('esx_addonaccount:getSharedAccount', name, cb)
end

local function nowSql()
    return os.date('%Y-%m-%d %H:%M:%S', os.time())
end

local function inLast7Days(sqlDate)
    if not sqlDate then return false end
    local t
    if type(sqlDate) == "number" then
        t = sqlDate
    elseif type(sqlDate) == "string" then
        local y, m, d, H, M, S = sqlDate:match("(%d+)%-(%d+)%-(%d+)%s+(%d+):(%d+):(%d+)")
        if y then
            t = os.time({
                year = tonumber(y), month = tonumber(m), day = tonumber(d),
                hour = tonumber(H), min = tonumber(M), sec = tonumber(S)
            })
        else
            return false
        end
    end
    return (os.time() - t) < (7 * 24 * 60 * 60)
end

-- ============================
-- 📊 CALLBACK INIT CLIENT
-- ============================

ESX.RegisterServerCallback('fiscal:getInit', function(src, cb, societyName)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return cb({ ok = false, msg = 'Player not found' }) end
    if not xPlayer.job or xPlayer.job.name ~= societyName then
        return cb({ ok = false, msg = 'Job mismatch' })
    end

    local rate = Config.DefaultTaxPercent
    local rows = MySQL.query.await(
        'SELECT declaration_date FROM fiscal_declarations WHERE society_name = ? ORDER BY declaration_date DESC LIMIT 1',
        { societyName }
    )

    local weeklyBlocked = false
    if Config.OneDeclarationPerWeek and rows[1] and inLast7Days(rows[1].declaration_date) then
        weeklyBlocked = true
    end

    local hist = MySQL.query.await(
        'SELECT id, declaration_date, declared_amount, tax_amount, debt_amount, paid, accounting_link FROM fiscal_declarations WHERE society_name = ? ORDER BY declaration_date DESC LIMIT ?',
        { societyName, Config.HistoryLimit }
    ) or {}

    cb({ ok = true, rate = rate, weeklyBlocked = weeklyBlocked, history = hist })
end)

-- ============================
-- 💰 DÉCLARATION FISCALE
-- ============================

RegisterNetEvent('fiscal:serverDeclare', function(societyName, declaredAmount, link)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    -- 🔗 Vérification lien Google
    if link and link ~= '' then
        local valid = link:match('^https://docs.google.com/') or link:match('^https://drive.google.com/')
        if not valid then link = nil end
    else
        link = nil
    end

    local taxRate = Config.DefaultTaxPercent
    local taxAmount = math.floor(declaredAmount * taxRate / 100)
    local debtAmount, paid = 0, 1
    local socAccName = Config.SocietyPrefix .. societyName
    local govAccName = Config.GovAccountName

    getSharedAccount(socAccName, function(socAcc)
        if not socAcc then return TriggerClientEvent('fiscal:notify', src, 'error', "Compte société introuvable.") end
        getSharedAccount(govAccName, function(govAcc)
            if not govAcc then return TriggerClientEvent('fiscal:notify', src, 'error', "Compte gouvernement introuvable.") end

            if (socAcc.money or 0) < taxAmount then
                debtAmount = math.floor(taxAmount * (1 + Config.DebtPenaltyPercent / 100))
                paid = 0
                socAcc.removeMoney(socAcc.money)
            else
                socAcc.removeMoney(taxAmount)
                govAcc.addMoney(taxAmount)
            end

            local now = nowSql()
            local nextWeek = os.date('%Y-%m-%d %H:%M:%S', os.time() + 7 * 24 * 60 * 60)
            local warnAt = os.date('%Y-%m-%d %H:%M:%S', os.time() + 6 * 24 * 60 * 60)

            MySQL.insert.await(
                [[INSERT INTO fiscal_declarations
                (society_name, boss_identifier, declared_amount, tax_amount, debt_amount, paid, declaration_date, next_due_date, warned_at, accounting_link)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
                { societyName, xPlayer.identifier, declaredAmount, taxAmount, debtAmount, paid, now, nextWeek, warnAt, link }
            )

            TriggerClientEvent('fiscal:notify', src,
                paid == 1 and 'success' or 'error',
                paid == 1 and ("Impôt payé : $" .. taxAmount) or ("Fonds insuffisants. Dette : $" .. debtAmount)
            )

            -- webhook
            sendWebhook(Config.WebhookDeclaration, {
                title = "Déclaration fiscale",
                color = paid == 1 and 3066993 or 15158332,
                fields = {
                    { name = "Entreprise", value = societyName, inline = true },
                    { name = "Patron", value = ("%s (%s)"):format(xPlayer.getName(), xPlayer.identifier), inline = true },
                    { name = "Montant déclaré", value = "$" .. declaredAmount, inline = false },
                    { name = "Lien comptable", value = link or "Aucun", inline = false },
                    { name = "Impôt (" .. taxRate .. "%)", value = "$" .. taxAmount, inline = true },
                    { name = "Statut", value = paid == 1 and "✅ Payé" or ("❌ Dette $" .. debtAmount), inline = true }
                },
                timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
            })

            local hist = MySQL.query.await(
                'SELECT id, declaration_date, declared_amount, tax_amount, debt_amount, paid, accounting_link FROM fiscal_declarations WHERE society_name = ? ORDER BY declaration_date DESC LIMIT ?',
                { societyName, Config.HistoryLimit }
            )
            TriggerClientEvent('fiscal:updateHistory', src, hist or {})
        end)
    end)
end)

-- ============================
-- 🧾 RÉGULARISATION D'UNE DETTE
-- ============================

RegisterNetEvent('fiscal:payDebtById', function(declarationId)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local declaration = MySQL.single.await('SELECT * FROM fiscal_declarations WHERE id = ?', { declarationId })
    if not declaration then
        return TriggerClientEvent('fiscal:notify', src, 'error', "Déclaration introuvable.")
    end
    if declaration.paid == 1 then
        return TriggerClientEvent('fiscal:notify', src, 'error', "Cette déclaration est déjà réglée.")
    end

    local socAccName = Config.SocietyPrefix .. declaration.society_name
    local govAccName = Config.GovAccountName

    getSharedAccount(socAccName, function(socAcc)
        getSharedAccount(govAccName, function(govAcc)
            if not socAcc or not govAcc then
                return TriggerClientEvent('fiscal:notify', src, 'error', "Compte société ou gouvernement introuvable.")
            end

            local toPay = declaration.debt_amount > 0 and declaration.debt_amount or declaration.tax_amount
            if (socAcc.money or 0) < toPay then
                TriggerClientEvent('fiscal:notify', src, 'error', "Fonds insuffisants pour régler la dette.")
                return TriggerClientEvent('fiscal:debtPaid', src, declarationId, false)
            end

            socAcc.removeMoney(toPay)
            govAcc.addMoney(toPay)
            MySQL.update.await('UPDATE fiscal_declarations SET paid = 1, debt_amount = 0 WHERE id = ?', { declarationId })

            TriggerClientEvent('fiscal:notify', src, 'success', "💰 Dette fiscale régularisée.")
            TriggerClientEvent('fiscal:debtPaid', src, declarationId, true)
        end)
    end)
end)

-- ============================
-- 📘 ENVOI FICHE COMPTABLE
-- ============================

RegisterNetEvent('fiscal:sendAccountingLink', function(declId, link)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer or not declId or not link then return end

    local row = MySQL.single.await(
        'SELECT society_name, declared_amount, tax_amount, paid FROM fiscal_declarations WHERE id = ?',
        { declId }
    )
    if not row then
        return TriggerClientEvent('fiscal:notify', src, 'error', "Déclaration introuvable.")
    end

    local embed = {
        title = "📘 Fiche comptable envoyée",
        color = 3447003,
        fields = {
            { name = "ID Déclaration", value = tostring(declId), inline = true },
            { name = "Entreprise", value = row.society_name, inline = true },
            { name = "Montant déclaré", value = "$" .. row.declared_amount, inline = true },
            { name = "Impôt", value = "$" .. row.tax_amount, inline = true },
            { name = "Statut", value = row.paid == 1 and "✅ Payé" or "❌ Non payé", inline = true },
            { name = "Lien comptable", value = link, inline = false },
            { name = "Envoyé par", value = ("%s (%s)"):format(xPlayer.getName(), xPlayer.identifier), inline = false },
        },
        footer = { text = "Service Fiscal — Evogen RP" },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
    }

    sendWebhook(Config.WebhookAccounting, embed)
end)

RegisterNetEvent('fiscal:sendAccountingLink', function(declId)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer or not declId then return end

    local row = MySQL.single.await('SELECT society_name, declared_amount, tax_amount, paid FROM fiscal_declarations WHERE id = ?', { declId })
    if not row then return end

    local embed = {
        title = "📘 Fiche comptable envoyée",
        color = 3447003,
        fields = {
            { name = "ID Déclaration", value = tostring(declId), inline = true },
            { name = "Entreprise", value = row.society_name, inline = true },
            { name = "Montant déclaré", value = "$"..row.declared_amount, inline = true },
            { name = "Impôt", value = "$"..row.tax_amount, inline = true },
            { name = "Statut", value = row.paid == 1 and "✅ Payé" or "❌ Non payé", inline = true },
            { name = "Envoyé par", value = ("%s (%s)"):format(xPlayer.getName(), xPlayer.identifier), inline = false },
        },
        footer = { text = "Service Fiscal — Evogen RP" },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
    }

    PerformHttpRequest(Config.WebhookAccounting, function() end, 'POST',
        json.encode({ username = "Service Fiscal", embeds = { embed } }),
        { ['Content-Type'] = 'application/json' })
end)
