--==[ SIMPLE NON-DUPLICATE SERVER HOPPER ]==--

if not game:IsLoaded() then
    game.Loaded:Wait()
end

task.wait(12) -- tunggu sebentar setelah join

----------------------------------------------------------------------
-- SERVICES
----------------------------------------------------------------------
local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")

local placeId      = game.PlaceId
local currentJobId = game.JobId

print("[HopNoDup] Start. JobId sekarang:", currentJobId)

----------------------------------------------------------------------
-- 🔧 KONFIGURASI VISITED
----------------------------------------------------------------------
local VISITED_FILE       = "server-hop-visited.json"
local VISITED_TTL_SECONDS = 7200-- 2 jam

----------------------------------------------------------------------
-- 🧠 LOAD / SAVE VISITED
----------------------------------------------------------------------
local visited = {}  -- [jobId] = timestamp

local function loadVisited()
    if not readfile then return end

    local ok, content = pcall(function()
        return readfile(VISITED_FILE)
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
            writefile(VISITED_FILE, encoded)
        end)
    end
end

local function cleanupVisited()
    local now = os.time()
    local removed = 0
    for jobId, ts in pairs(visited) do
        if type(ts) ~= "number" or now - ts > VISITED_TTL_SECONDS then
            visited[jobId] = nil
            removed += 1
        end
    end
    if removed > 0 then
        print("[HopNoDup] Hapus", removed, "server lama dari visited.")
        saveVisited()
    end
end

local function isRecentlyVisited(jobId)
    if not jobId then return false end
    local ts = visited[jobId]
    if not ts then return false end
    return (os.time() - ts) <= VISITED_TTL_SECONDS
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
-- 🌐 AMBIL LIST SERVER SEKALI
----------------------------------------------------------------------
local function getServersOnce()
    -- kecilin limit supaya ringan
    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100")
        :format(placeId)

    local ok, res = pcall(function()
        return game:HttpGet(url)
    end)
    if not ok then
        warn("[HopNoDup] HttpGet gagal:", res)
        return nil
    end

    local decoded
    local okDecode, err = pcall(function()
        decoded = HttpService:JSONDecode(res)
    end)
    if not okDecode then
        warn("[HopNoDup] JSON decode gagal:", err)
        return nil
    end

    return decoded.data
end

----------------------------------------------------------------------
-- 🔎 PILIH SERVER YANG BEDA JOBID & BELUM VISITED
----------------------------------------------------------------------
local servers = getServersOnce()
if not servers then
    warn("[HopNoDup] Tidak bisa ambil list server. (API error)")
    return
end

local targetId

for _, server in ipairs(servers) do
    local id      = server.id
    local playing = server.playing or 0
    local maxP    = server.maxPlayers or 0

    print(("[HopNoDup] Cek server %s | %d/%d pemain")
        :format(tostring(id), playing, maxP))

    if not id then
        continue
    end

    -- syarat: beda JobId, tidak penuh, belum visited 30 menit
    if id ~= currentJobId
        and playing < maxP
        and not isRecentlyVisited(id)
    then
        targetId = id
        break
    end
end

----------------------------------------------------------------------
-- 🚀 TELEPORT
----------------------------------------------------------------------
if targetId then
    print("[HopNoDup] ✅ Teleport ke server baru:", targetId)
    markVisited(targetId)

    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(placeId, targetId)
    end)

    if not ok then
        warn("[HopNoDup] Teleport gagal:", err)
    end
else
    warn("[HopNoDup] ❌ Tidak ada server lain yang cocok (semua penuh / sudah dikunjungi).")
end
