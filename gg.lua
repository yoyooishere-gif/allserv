--==[ LOOP SERVER HOPPER – REJOIN TERUS + ANTI SERVER SAMA (30 MENIT) ]==--

if not game:IsLoaded() then
    game.Loaded:Wait()
end

----------------------------------------------------------------------
-- 🔧 KONFIGURASI
----------------------------------------------------------------------
local CONFIG = {
    FirstDelay          = 20,      -- tunggu world load sebelum cek pertama (detik)
    MinPlayers          = 3,      -- patokan "rame" untuk log & delay
    HopDelayGood        = 15,     -- jeda hop kalau server rame (>= MinPlayers)
    HopDelayBad         = 5,      -- jeda hop kalau server sepi  (< MinPlayers)

    VisitedFile         = "server-hop-visited.json",
    VisitedTTLSeconds   = 1800,   -- 30 menit: jangan betah di server yang sama
    RejoinIfVisitedDelay = 4,     -- kalau ternyata balik ke JobId lama → rejoin cepat
}

----------------------------------------------------------------------
-- SERVICES
----------------------------------------------------------------------
local Players         = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")

local placeId      = game.PlaceId
local currentJobId = game.JobId

print("[LoopHop] Start. JobId sekarang:", currentJobId)

----------------------------------------------------------------------
-- 🧠 SISTEM VISITED (ANTI NGEKOS DI SERVER SAMA)
----------------------------------------------------------------------
local visited = {}  -- [jobId] = timestamp

local function loadVisited()
    if not readfile then
        warn("[LoopHop] Executor tidak punya readfile, visited non-aktif.")
        return
    end

    local ok, content = pcall(function()
        return readfile(CONFIG.VisitedFile)
    end)

    if not ok or not content or content == "" then
        return
    end

    local okDecode, data = pcall(function()
        return HttpService:JSONDecode(content)
    end)

    if okDecode and type(data) == "table" then
        visited = data
    else
        warn("[LoopHop] File visited corrupt, reset baru.")
        visited = {}
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
    local ttl = CONFIG.VisitedTTLSeconds
    local removed = 0

    for jobId, ts in pairs(visited) do
        if type(ts) ~= "number" or now - ts > ttl then
            visited[jobId] = nil
            removed += 1
        end
    end

    if removed > 0 then
        print("[LoopHop] Hapus", removed, "server lama dari visited.")
        saveVisited()
    end
end

local function isRecentlyVisited(jobId)
    if not jobId then return false end
    local ts = visited[jobId]
    if not ts then return false end
    return (os.time() - ts) <= CONFIG.VisitedTTLSeconds
end

local function markVisited(jobId)
    if not jobId then return end
    visited[jobId] = os.time()
    saveVisited()
end

----------------------------------------------------------------------
-- 🔢 FUNGSI JUMLAH PLAYER
----------------------------------------------------------------------
local function getPlayerCount()
    return #Players:GetPlayers()
end

----------------------------------------------------------------------
-- 🚀 LOGIKA UTAMA
----------------------------------------------------------------------
task.wait(CONFIG.FirstDelay)

loadVisited()
cleanupVisited()

-- 1) Kalau server ini sudah pernah dikunjungi ≤30 menit → rejoin cepat
if isRecentlyVisited(currentJobId) then
    warn("[LoopHop] Server ini sudah ada di visited (<=30 menit). Rejoin cepat...")

    task.wait(CONFIG.RejoinIfVisitedDelay)

    local ok, err = pcall(function()
        TeleportService:Teleport(placeId)
    end)

    if not ok then
        warn("[LoopHop] Teleport(placeId) gagal:", err)
    else
        print("[LoopHop] Teleport rejoin (visited) dikirim.")
    end

    return
end

-- 2) Server baru: cek jumlah player, lalu jadwalkan hop
local count = getPlayerCount()
print(("[LoopHop] Server saat ini: %d pemain"):format(count))

local hopDelay
if count >= CONFIG.MinPlayers then
    print(("[LoopHop] ✅ Rame (>= %d). Akan hop lagi setelah %d detik.")
        :format(CONFIG.MinPlayers, CONFIG.HopDelayGood))
    hopDelay = CONFIG.HopDelayGood
else
    print(("[LoopHop] ⚠️ Sepi (< %d). Akan hop lagi lebih cepat (%d detik).")
        :format(CONFIG.MinPlayers, CONFIG.HopDelayBad))
    hopDelay = CONFIG.HopDelayBad
end

-- tandai server ini sebagai visited sebelum hop
markVisited(currentJobId)

task.wait(hopDelay)

print("[LoopHop] 🔁 Teleport ke server lain...")
local ok, err = pcall(function()
    TeleportService:Teleport(placeId)
end)

if not ok then
    warn("[LoopHop] Teleport(placeId) gagal:", err)
end
