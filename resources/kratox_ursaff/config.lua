Config = {}

-- Framework
Config.Framework = 'esx'     -- ESX Legacy

-- Taxes
Config.DefaultTaxPercent     = 15
Config.DebtPenaltyPercent    = 5
Config.OneDeclarationPerWeek = true

-- Comptes
Config.GovAccountName = 'society_gouv'
Config.SocietyPrefix  = 'society_'

-- Grades de patrons
Config.BossGradeNames = { 'boss', 'owner', 'chief' }

-- Webhooks
Config.WebhookDeclaration = 'https://discord.com/api/webhooks/1428877807634612264/wD89N0AZjLMyYh5RlfDjI1buaC3cCS5C6U4yRH9HHv9zEbOm46-9fHlu7senlFIiLmLL'
Config.WebhookUnpaid      = 'https://discord.com/api/webhooks/1428877807634612264/wD89N0AZjLMyYh5RlfDjI1buaC3cCS5C6U4yRH9HHv9zEbOm46-9fHlu7senlFIiLmLL'
Config.WebhookReminder    = 'https://discord.com/api/webhooks/1428877807634612264/wD89N0AZjLMyYh5RlfDjI1buaC3cCS5C6U4yRH9HHv9zEbOm46-9fHlu7senlFIiLmLL'
Config.WebhookAccounting = 'https://discord.com/api/webhooks/1428877807634612264/wD89N0AZjLMyYh5RlfDjI1buaC3cCS5C6U4yRH9HHv9zEbOm46-9fHlu7senlFIiLmLL' -- Webhook pour fiches comptables

-- Notifs
Config.UseOxNotify = true

-- Cron (ms)
Config.CronCheckInterval = 60 * 60 * 1000 -- 1h

-- PNJ unique
Config.Ped = {
    model = 'cs_bankman',
    coords = vector3(-555.3658, -187.6581, 38.2210), -- bâtiment du gouvernement par exemple
    heading = 197.4120,
    label = 'Service Fiscal'
}

-- Commande fallback
Config.EnableCommand = true
Config.CommandName   = 'declaration'

-- Historique NUI
Config.HistoryLimit = 5
