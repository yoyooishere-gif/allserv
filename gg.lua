if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- ⚙️ KONFIGURASI
local CONFIG = {
    InitialDelay  = 20,  -- jeda awal setelah game load (detik)
    HopCooldown   = 20,  -- minimal jarak waktu antar teleport (detik)
}

-- ⏳ Tunggu setelah game benar-benar load
task.wait(CONFIG.InitialDelay)

-- 🎯 PLACE ID TETAP
local PLACE_ID = 121864768012064

local AllIDs = {}
local foundAnything = ""
local actualHour = os.date("!*t").hour

local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")
local Players         = game:GetService("Players")

--------------------------------------------------
-- 📂 LOAD / INIT FILE VISITED SERVER
--------------------------------------------------
local function SaveIDs()
    pcall(function()
        writefile("server-hop-temp.json", HttpService:JSONEncode(AllIDs))
    end)
end

local FileOk = pcall(function()
    AllIDs = HttpService:JSONDecode(readfile("server-hop-temp.json"))
end)

-- Struktur: indeks [1] = hour, [2..n] = JobId server yang sudah dikunjungi
if not FileOk or type(AllIDs) ~= "table" or #AllIDs == 0 then
    AllIDs = { actualHour }
    SaveIDs()
else
    -- kalau jam sudah beda, reset list supaya fresh
    local savedHour = tonumber(AllIDs[1]) or actualHour
    if savedHour ~= actualHour then
        AllIDs = { actualHour }
        SaveIDs()
    end
end

--------------------------------------------------
-- 🔍 FUNGSI CEK SUDAH PERNAH DIKUNJUNGI
--------------------------------------------------
local function AlreadyVisited(jobId)
    jobId = tostring(jobId)
    for i = 2, #AllIDs do -- mulai dari 2, karena [1] itu hour
        if tostring(AllIDs[i]) == jobId then
            return true
        end
    end
    return false
end

-- tandai server SEKARANG juga sebagai sudah dikunjungi
local currentJob = game.JobId
if not AlreadyVisited(currentJob) then
    table.insert(AllIDs, currentJob)
    SaveIDs()
end

--------------------------------------------------
-- 🧠 LOGIC AMBIL SERVER BARU
-- return true kalau berhasil teleport, false kalau tidak ada server valid
--------------------------------------------------
local function TPReturner()
    local url
    if foundAnything == "" then
        url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(PLACE_ID)
    else
        url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100&cursor=%s"):format(PLACE_ID, foundAnything)
    end

    local success, Site = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(url))
    end)

    if not success or not Site or not Site.data then
        return false
    end

    if Site.nextPageCursor and Site.nextPageCursor ~= "null" then
        foundAnything = Site.nextPageCursor
    else
        foundAnything = ""
    end

    for _, v in ipairs(Site.data) do
        local serverJobId = tostring(v.id)
        local maxPlayers  = tonumber(v.maxPlayers) or 0
        local playing     = tonumber(v.playing) or 0

        -- ⛔ skip kalau server penuh / sama dengan server sekarang / sudah pernah dikunjungi
        if playing < maxPlayers
            and serverJobId ~= currentJob
            and not AlreadyVisited(serverJobId)
        then
            -- tandai sebagai sudah dikunjungi
            table.insert(AllIDs, serverJobId)
            SaveIDs()

            -- 🚀 TELEPORT
            local ok, err = pcall(function()
                TeleportService:TeleportToPlaceInstance(PLACE_ID, serverJobId, Players.LocalPlayer)
            end)

            -- kalau teleport dipanggil, kita anggap sukses (Roblox yang urus lanjutannya)
            return ok
        end
    end

    -- tidak ada server valid di page ini
    return false
end

--------------------------------------------------
-- 🔁 MODULE TELEPORT LOOP DENGAN COOLDOWN
--------------------------------------------------
local module = {}
local lastTeleport = 0

function module:Teleport()
    while true do
        task.wait(1) -- jangan spam, cek tiap 1 detik saja

        -- cek cooldown antar teleport
        if tick() - lastTeleport >= CONFIG.HopCooldown then
            pcall(function()
                local hopped = TPReturner()

                -- kalau barusan teleport, update waktu terakhir
                if hopped then
                    lastTeleport = tick()
                -- kalau belum dapat server dan masih ada next page, coba lagi sekali lagi
                elseif foundAnything ~= "" then
                    local hopped2 = TPReturner()
                    if hopped2 then
                        lastTeleport = tick()
                    end
                end
            end)
        end
    end
end

-- 🚀 AUTO START
module:Teleport()

return module
