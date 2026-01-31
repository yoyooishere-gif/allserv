--==[ NO-API SERVER HOPPER – ANTI SERVER SAMA (30 MENIT) ]==--

if not game:IsLoaded() then
    game.Loaded:Wait()
end

----------------------------------------------------------------------
-- 🔧 KONFIGURASI
----------------------------------------------------------------------
local CONFIG = {
    DelayBeforeCheck   = 8,     -- tunggu beberapa detik setelah join
    VisitedFile        = "server-hop-visited.json",
    VisitedTTLSeconds  = 1800,  -- 30 menit
    RejoinDelay        = 5,     -- tunggu sebentar sebelum rejoin
}

task.wait(CONFIG.DelayBeforeCheck)

----------------------------------------------------------------------
-- SERVICES & INFO
----------------------------------------------------------------------
local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")

local placeId      = game.PlaceId
local currentJobId = game.JobId

print("[NoApiHop] Start. JobId sekarang:", currentJobId)

----------------------------------------------------------------------
-- 🧠 SISTEM VISITED (ANTI BALIK SERVER YANG SAMA)
----------------------------------------------------------------------
local visited = {}  -- [jobId] = lastTime

local function loadVisited()
    if not readfile then
        warn("[NoApiHop] Executor tidak punya readfile, visited tidak aktif.")
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
        warn("[NoApiHop] File visited corrupt, reset baru.")
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
        print("[NoApiHop] Hapus", removed, "server lama dari visited.")
        saveVisited()
    end
end

local function markVisited(jobId)
    if not jobId then return end
    visited[jobId] = os.time()
    saveVisited()
end

local function isRecentlyVisited(jobId)
    if not jobId then return false end
    local ts = visited[jobId]
    if not ts then return false end
    local now = os.time()
    return (now - ts) <= CONFIG.VisitedTTLSeconds
end

----------------------------------------------------------------------
-- 🚀 LOGIKA UTAMA
----------------------------------------------------------------------
loadVisited()
cleanupVisited()

if isRecentlyVisited(currentJobId) then
    -- Server ini sudah dikunjungi dalam 30 menit terakhir → rejoin lagi
    warn("[NoApiHop] Server ini sudah pernah dikunjungi (<=30 menit). Rejoin ke server lain...")

    task.wait(CONFIG.RejoinDelay)

    local ok, err = pcall(function()
        TeleportService:Teleport(placeId)
    end)

    if not ok then
        warn("[NoApiHop] Teleport(placeId) gagal:", err)
    else
        print("[NoApiHop] Teleport rejoin dikirim. Roblox akan pilih server lain.")
    end
else
    -- Server baru (belum di-visited atau sudah lewat >30 menit)
    print("[NoApiHop] ✅ Server ini BELUM ada di visited 30 menit terakhir. Stay di sini.")
    markVisited(currentJobId)
end
