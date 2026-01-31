--==[ HYBRID SERVER HOPPER – API HOP + REJOIN + ANTI DUPLICATE ]==--

-- Pastikan game sudah load
if not game:IsLoaded() then
    game.Loaded:Wait()
end

----------------------------------------------------------------------
-- 🔧 KONFIGURASI
----------------------------------------------------------------------
local CONFIG = {
    DelayBeforeStart   = 10,    -- jeda sebelum mulai (detik)

    -- Target player di server tujuan (mid traffic)
    MinPlayers         = 3,     -- minimal pemain
    MaxPlayers         = 15,    -- maksimal pemain

    -- Pengaturan scan server list
    MaxPagesToScan     = 6,     -- berapa page sesudah skip yang discan
    RandomSkipMin      = 0,     -- minimal page yang diskip di awal
    RandomSkipMax      = 8,     -- maksimal page yang diskip di awal
    ApiDelay           = 0.6,   -- delay antar HttpGet (anti HTTP 429)

    -- File penyimpanan server yang pernah dikunjungi
    VisitedFile        = "server-hop-visited.json",
    VisitedTTLSeconds  = 1800,  -- 1800 detik = 30 menit tidak balik server yang sama

    -- Fallback kalau API gagal / tidak nemu server
    UseRejoinFallback  = true,  -- true = pakai Teleport(placeId) kalau API gagal
}

task.wait(CONFIG.DelayBeforeStart)

----------------------------------------------------------------------
-- SERVICES & INFO
----------------------------------------------------------------------
local Players         = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")

local LocalPlayer     = Players.LocalPlayer
local placeId         = game.PlaceId
local currentJobId    = game.JobId

print("[HybridHop] Start. PlaceId:", placeId, "| JobId:", currentJobId)

----------------------------------------------------------------------
-- 🧠 SISTEM VISITED SERVER (ANTI BALIK 30 MENIT)
----------------------------------------------------------------------
local visited = {}  -- [jobId] = lastTime

local function loadVisited()
    if not readfile then
        warn("[HybridHop] Executor tidak punya readfile, visited tidak bisa dipakai.")
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
        warn("[HybridHop] JSON visited corrupt, reset baru.")
        visited = {}
    end
end

local function saveVisited()
    if not writefile then
        return
    end

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
        print("[HybridHop] Bersihkan", removed, "server lama dari visited.")
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

-- Load dan bersihkan visited, lalu tandai server sekarang
loadVisited()
cleanupVisited()
markVisited(currentJobId)
print("[HybridHop] Tandai server sekarang sebagai visited.")

----------------------------------------------------------------------
-- 🔹 OPTIONAL: CEK TEMAN DI SERVER (INFO SAJA)
----------------------------------------------------------------------
local FriendIds = {}

pcall(function()
    local pages = Players:GetFriendsAsync(LocalPlayer.UserId)
    repeat
        for _, info in ipairs(pages:GetCurrentPage()) do
            FriendIds[info.Id] = true
        end
    until pages.IsFinished or not pcall(function()
        pages:AdvanceToNextPageAsync()
    end)
end)

local function hasFriendHere()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and FriendIds[plr.UserId] then
            return true, plr.Name
        end
    end
    return false
end

local friendInServer, friendName = hasFriendHere()
if friendInServer then
    warn("[HybridHop] Ada teman di server:", friendName, "(hanya info, tetap akan hop).")
else
    print("[HybridHop] Tidak ada teman di server ini.")
end

----------------------------------------------------------------------
-- 🌐 FUNGSI GET SERVER LIST VIA API ROBLOX
----------------------------------------------------------------------
local cursor = nil
local lastApiError = nil

local function getServers()
    task.wait(CONFIG.ApiDelay)  -- anti 429

    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=%d")
        :format(placeId, 100)

    if cursor then
        url = url .. "&cursor=" .. cursor
    end

    local ok, res = pcall(function()
        return game:HttpGet(url)
    end)

    if not ok then
        lastApiError = tostring(res)
        warn("[HybridHop] Gagal HttpGet:", lastApiError)
        return nil
    end

    local decoded
    local okDecode, err = pcall(function()
        decoded = HttpService:JSONDecode(res)
    end)

    if not okDecode then
        lastApiError = tostring(err)
        warn("[HybridHop] Gagal decode JSON:", lastApiError)
        return nil
    end

    cursor = decoded.nextPageCursor
    return decoded.data
end

----------------------------------------------------------------------
-- 🔎 COBA CARI SERVER VIA API
----------------------------------------------------------------------
local function tryApiHop()
    print("[HybridHop] Mulai cari server via API...")
    cursor = nil
    lastApiError = nil

    -- Skip beberapa page secara acak
    local skipCount = 0
    if CONFIG.RandomSkipMax > 0 then
        skipCount = math.random(CONFIG.RandomSkipMin, CONFIG.RandomSkipMax)
    end

    if skipCount > 0 then
        print(("[HybridHop] Skip ~%d page dulu sebelum scan."):format(skipCount))
        for i = 1, skipCount do
            local servers = getServers()
            if not servers or not cursor then
                print("[HybridHop] Skip berhenti di page", i, "(tidak ada page lanjutan / error).")
                break
            end
        end
    end

    local bestServerId    = nil
    local bestPlayerCount = -1

    for page = 1, CONFIG.MaxPagesToScan do
        local servers = getServers()
        if not servers then
            -- kalau error (429/dll), keluar
            break
        end

        if #servers == 0 then
            print("[HybridHop] Page", page, "kosong.")
            if not cursor then break end
        end

        for _, server in ipairs(servers) do
            local id      = server.id
            local playing = server.playing or 0
            local maxP    = server.maxPlayers or 0

            print(("[HybridHop] Cek server %s | %d/%d pemain")
                :format(tostring(id), playing, maxP))

            -- skip kalau:
            -- - id nil
            -- - server ini sama dengan server sekarang
            -- - server penuh
            -- - server ini baru saja dikunjungi (anti balik 30 menit)
            if not id
                or id == currentJobId
                or playing >= maxP
                or isRecentlyVisited(id)
            then
                continue
            end

            -- hanya ambil server dalam range player yang diinginkan
            local enoughPlayers = playing >= CONFIG.MinPlayers
            local notTooMany    = playing <= CONFIG.MaxPlayers

            if enoughPlayers and notTooMany then
                -- pilih server dengan player TERBANYAK dalam range
                if playing > bestPlayerCount then
                    bestPlayerCount = playing
                    bestServerId    = id
                end
            end
        end

        if bestServerId or not cursor then
            break
        end
    end

    if not bestServerId then
        if lastApiError then
            warn("[HybridHop] API tidak bisa dipakai. Error terakhir:", lastApiError)
        else
            warn("[HybridHop] Sama sekali tidak menemukan server yang cocok di range",
                 CONFIG.MinPlayers, "-", CONFIG.MaxPlayers, "pemain.")
        end
        return false
    end

    print(("[HybridHop] ✅ Server terpilih: %s | %d pemain (tidak visited, tidak penuh)")
        :format(bestServerId, bestPlayerCount))

    -- tandai server target sebagai visited sebelum teleport
    markVisited(bestServerId)

    local ok, tpErr = pcall(function()
        TeleportService:TeleportToPlaceInstance(placeId, bestServerId)
    end)

    if not ok then
        warn("[HybridHop] TeleportToPlaceInstance gagal:", tpErr)
        return false
    end

    print("[HybridHop] Teleport via API hop dikirim.")
    return true
end

----------------------------------------------------------------------
-- 🔁 FALLBACK: REJOIN RANDOM SERVER (TANPA API)
----------------------------------------------------------------------
local function fallbackRejoin()
    if not CONFIG.UseRejoinFallback then
        warn("[HybridHop] Fallback rejoin dimatikan di config.")
        return
    end

    warn("[HybridHop] Fallback aktif: rejoin random server via Teleport(placeId).")

    local ok, err = pcall(function()
        TeleportService:Teleport(placeId)
    end)

    if not ok then
        warn("[HybridHop] Teleport(placeId) gagal:", err)
    else
        print("[HybridHop] Teleport rejoin dikirim. Roblox akan pilih server lain (sering beda JobId).")
    end
end

----------------------------------------------------------------------
-- 🚀 EKSEKUSI UTAMA
----------------------------------------------------------------------
local success = tryApiHop()
if not success then
    fallbackRejoin()
end
