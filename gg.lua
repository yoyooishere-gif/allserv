--==[ MID-TRAFFIC HOPPER – PRIORITAS 7–14 PLAYER + ANTI DUPLICATE ]==--

if not game:IsLoaded() then
    game.Loaded:Wait()
end

task.wait(8) -- tunggu world load dulu

----------------------------------------------------------------------
-- 🔧 KONFIGURASI
----------------------------------------------------------------------
local CONFIG = {
    MinMidPlayers   = 7,        -- batas bawah mid traffic
    MaxMidPlayers   = 14,       -- batas atas mid traffic
    ApiDelay        = 0.6,      -- anti HTTP 429
    VisitedFile     = "server-hop-visited.json",
    VisitedTTL      = 1800,     -- 30 menit
}

----------------------------------------------------------------------
-- SERVICES
----------------------------------------------------------------------
local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")

local placeId      = game.PlaceId
local currentJobId = game.JobId

print("[MidHop] Start. JobId sekarang:", currentJobId)

----------------------------------------------------------------------
-- 🧠 VISITED SYSTEM
----------------------------------------------------------------------
local visited = {}  -- [jobId] = timestamp

local function loadVisited()
    if not readfile then return end
    local ok, content = pcall(function()
        return readfile(CONFIG.VisitedFile)
    end)
    if not ok or not content or content == "" then return end

    local okDecode, data = pcall(function()
        return HttpService:JSONDecode(content)
    end)
    if okDecode and type(data) == "table" then
        visited = data
    end
end

local function saveVisited()
    if not writefile then return end
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(visited)
    end)
    if ok then
        pcall(function()
            writefile(CONFIG.VisitedFile, encoded)
        end)
    end
end

local function cleanupVisited()
    local now = os.time()
    local removed = 0
    for jobId, ts in pairs(visited) do
        if type(ts) ~= "number" or now - ts > CONFIG.VisitedTTL then
            visited[jobId] = nil
            removed += 1
        end
    end
    if removed > 0 then
        print("[MidHop] Hapus", removed, "visited lama.")
        saveVisited()
    end
end

local function isVisited(jobId)
    if not jobId then return false end
    local ts = visited[jobId]
    if not ts then return false end
    return (os.time() - ts) <= CONFIG.VisitedTTL
end

local function markVisited(jobId)
    if not jobId then return end
    visited[jobId] = os.time()
    saveVisited()
end

loadVisited()
cleanupVisited()
markVisited(currentJobId)

----------------------------------------------------------------------
-- 🌐 AMBIL 1 PAGE SERVER LIST
----------------------------------------------------------------------
local function getServersOnce()
    task.wait(CONFIG.ApiDelay)

    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100")
        :format(placeId)

    local ok, res = pcall(function()
        return game:HttpGet(url)
    end)
    if not ok then
        warn("[MidHop] HttpGet gagal:", res)
        return nil
    end

    local decoded
    local okDecode, err = pcall(function()
        decoded = HttpService:JSONDecode(res)
    end)
    if not okDecode then
        warn("[MidHop] JSON decode gagal:", err)
        return nil
    end

    return decoded.data
end

----------------------------------------------------------------------
-- 🔎 PILIH SERVER: PRIORITAS 7–14 PLAYER
----------------------------------------------------------------------
local servers = getServersOnce()
if not servers then
    warn("[MidHop] Tidak bisa ambil server list (API error).")
    return
end

local targetMidId, targetMidPlayers
local backupId,    backupPlayers

for _, server in ipairs(servers) do
    local id      = server.id
    local playing = server.playing or 0
    local maxP    = server.maxPlayers or 0

    print(("[MidHop] Cek server %s | %d/%d pemain")
        :format(tostring(id), playing, maxP))

    if not id or id == currentJobId or playing >= maxP or isVisited(id) then
        continue
    end

    -- 🎯 PRIORITAS: 7–14 PLAYER
    if playing >= CONFIG.MinMidPlayers and playing <= CONFIG.MaxMidPlayers then
        targetMidId      = id
        targetMidPlayers = playing
        break -- sudah ketemu mid, nggak perlu lanjut
    end

    -- 🤏 BACKUP: server apapun yang tidak penuh & belum visited
    if not backupId then
        backupId      = id
        backupPlayers = playing
    end
end

----------------------------------------------------------------------
-- 🚀 TELEPORT
----------------------------------------------------------------------
local finalId, finalPlayers

if targetMidId then
    finalId      = targetMidId
    finalPlayers = targetMidPlayers
    print("[MidHop] ✅ Dapat mid traffic:", finalId, "|", finalPlayers, "pemain")
elseif backupId then
    finalId      = backupId
    finalPlayers = backupPlayers
    print("[MidHop] ⚠️ Tidak ada 7–14 player di page ini, pakai server lain:",
          finalId, "|", finalPlayers, "pemain")
else
    -- 🔁 PERUBAHAN KECIL DI SINI:
    -- sebelumnya: return (stay di server sekarang)
    -- sekarang: tetap hop pakai rejoin random
    warn("[MidHop] ❌ Tidak ada server lain yang bisa dimasuki (semua penuh / visited). Rejoin random.")

    local ok, err = pcall(function()
        TeleportService:Teleport(placeId)
    end)
    if not ok then
        warn("[MidHop] Teleport(placeId) gagal:", err)
    end
    return
end

markVisited(finalId)

local ok, err = pcall(function()
    TeleportService:TeleportToPlaceInstance(placeId, finalId)
end)

if not ok then
    warn("[MidHop] Teleport gagal:", err)
end
