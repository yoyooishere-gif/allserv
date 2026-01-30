if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- ⏳ Tunggu 10 detik setelah game benar-benar load
task.wait(10)

-- 🎯 PLACE ID TETAP
local PLACE_ID = 121864768012064

local AllIDs = {}
local foundAnything = ""
local actualHour = os.date("!*t").hour
local S_T = game:GetService("TeleportService")
local S_H = game:GetService("HttpService")
local PLAYERS = game:GetService("Players")

--------------------------------------------------
-- 📂 LOAD / INIT FILE VISITED SERVER
--------------------------------------------------
local function SaveIDs()
    pcall(function()
        writefile("server-hop-temp.json", S_H:JSONEncode(AllIDs))
    end)
end

local FileOk = pcall(function()
    AllIDs = S_H:JSONDecode(readfile("server-hop-temp.json"))
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
--------------------------------------------------
local function TPReturner()
    local url
    if foundAnything == "" then
        url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(PLACE_ID)
    else
        url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100&cursor=%s"):format(PLACE_ID, foundAnything)
    end

    local success, Site = pcall(function()
        return S_H:JSONDecode(game:HttpGet(url))
    end)

    if not success or not Site or not Site.data then
        return
    end

    if Site.nextPageCursor and Site.nextPageCursor ~= "null" then
        foundAnything = Site.nextPageCursor
    else
        foundAnything = ""
    end

    for _, v in ipairs(Site.data) do
        local serverJobId = tostring(v.id)
        local maxPlayers = tonumber(v.maxPlayers) or 0
        local playing    = tonumber(v.playing) or 0

        -- ⛔ skip kalau server penuh / hampir penuh / sama dengan server sekarang / sudah pernah dikunjungi
        if playing < maxPlayers
            and serverJobId ~= currentJob
            and not AlreadyVisited(serverJobId)
        then
            -- tandai sebagai sudah dikunjungi
            table.insert(AllIDs, serverJobId)
            SaveIDs()

            -- 🚀 TELEPORT
            pcall(function()
                S_T:TeleportToPlaceInstance(PLACE_ID, serverJobId, PLAYERS.LocalPlayer)
            end)

            task.wait(4)
            return -- stop setelah dapat 1 server valid
        end
    end
end

--------------------------------------------------
-- 🔁 MODULE TELEPORT LOOP
--------------------------------------------------
local module = {}

function module:Teleport()
    while task.wait() do
        pcall(function()
            TPReturner()
            if foundAnything ~= "" then
                TPReturner()
            end
        end)
    end
end

-- 🚀 AUTO START
module:Teleport()

return module
