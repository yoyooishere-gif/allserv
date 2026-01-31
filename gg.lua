-- Pastikan game sudah selesai load
if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- Jeda 20 detik setelah auto-execute
task.wait(20)

local Players         = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")

local LocalPlayer  = Players.LocalPlayer
local placeId      = game.PlaceId
local currentJobId = game.JobId

--------------------------------------------------------------------
-- 🔧 KONFIGURASI
--------------------------------------------------------------------
local MIN_PLAYERS        = 7   -- minimal pemain di server PRIORITAS
local MAX_PLAYERS        = 15  -- maksimal pemain di server PRIORITAS
local FALLBACK_MIN_PLAY  = 2   -- minimal pemain untuk server fallback
local MAX_PAGES          = 5   -- maksimal halaman server yang dicek
--------------------------------------------------------------------

--------------------------------------------------------------------
-- 🔹 Load daftar teman (UserId)
--------------------------------------------------------------------
local FriendIds = {}

do
    local ok, pagesOrErr = pcall(function()
        return Players:GetFriendsAsync(LocalPlayer.UserId)
    end)

    if not ok then
        warn("[ServerHop] Gagal load daftar teman:", pagesOrErr)
    else
        local pages = pagesOrErr
        while true do
            for _, info in ipairs(pages:GetCurrentPage()) do
                FriendIds[info.Id] = true
            end

            if pages.IsFinished then
                break
            end

            local okNext, errNext = pcall(function()
                pages:AdvanceToNextPageAsync()
            end)

            if not okNext then
                warn("[ServerHop] Gagal ambil page teman berikutnya:", errNext)
                break
            end
        end
    end
end

local function HasFriendInCurrentServer()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and FriendIds[plr.UserId] then
            return true, plr.Name
        end
    end
    return false
end

local hasFriend, friendName = HasFriendInCurrentServer()
if hasFriend then
    warn("[ServerHop] Ada teman di server ini:", friendName, "→ akan hop ke server lain.")
else
    print("[ServerHop] Tidak ada teman di server ini.")
end

--------------------------------------------------------------------
-- 🔹 Ambil list server dari API Roblox
--------------------------------------------------------------------
local cursor = nil

local function GetServers()
    -- Pakai placeId dari game yang sedang kamu mainkan
    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(placeId)

    if cursor then
        url = url .. "&cursor=" .. cursor
    end

    local ok, result = pcall(function()
        return game:HttpGet(url)
    end)

    if not ok then
        warn("[ServerHop] Gagal ambil server list:", result)
        return nil
    end

    local decoded
    local okDecode, errDecode = pcall(function()
        decoded = HttpService:JSONDecode(result)
    end)

    if not okDecode then
        warn("[ServerHop] Gagal decode JSON:", errDecode)
        return nil
    end

    cursor = decoded.nextPageCursor
    return decoded.data
end

print(("[ServerHop] Mencari server lain... (prioritas %d–%d pemain)"):format(MIN_PLAYERS, MAX_PLAYERS))
print("[ServerHop] Server saat ini JobId:", currentJobId)

--------------------------------------------------------------------
-- 🔹 Scan server dan simpan ke kandidat:
--     - PRIORITAS: tidak penuh, beda JobId, pemain 7–15
--     - FALLBACK: tidak penuh, beda JobId, pemain ≥2
--------------------------------------------------------------------
local mediumCandidates  = {}
local fallbackCandidates = {}

math.randomseed(tick())

for page = 1, MAX_PAGES do
    local servers = GetServers()
    if not servers then break end

    for _, server in ipairs(servers) do
        local playing    = server.playing or 0
        local maxPlayers = server.maxPlayers or 0
        local serverId   = server.id

        print(("[ServerHop] Cek server %s | %d/%d pemain"):format(
            tostring(serverId),
            playing,
            maxPlayers
        ))

        local notFull         = playing < maxPlayers
        local differentServer = serverId ~= currentJobId

        if notFull and differentServer then
            -- PRIORITAS: medium traffic
            if playing >= MIN_PLAYERS and playing <= MAX_PLAYERS then
                table.insert(mediumCandidates, server)
            -- FALLBACK: server nggak sepi banget (>=2 pemain)
            elseif playing >= FALLBACK_MIN_PLAY then
                table.insert(fallbackCandidates, server)
            end
        end
    end

    if (cursor == nil) then
        break
    end
end

--------------------------------------------------------------------
-- 🔹 Pilih target server (random dari kandidat)
--------------------------------------------------------------------
local targetServerId
local targetPlayerCount

if #mediumCandidates > 0 then
    local index = math.random(1, #mediumCandidates)
    local chosen = mediumCandidates[index]
    targetServerId      = chosen.id
    targetPlayerCount   = chosen.playing
    print(("[ServerHop] Server PRIORITAS dipilih: %s | %d pemain")
        :format(targetServerId, targetPlayerCount))
elseif #fallbackCandidates > 0 then
    local index = math.random(1, #fallbackCandidates)
    local chosen = fallbackCandidates[index]
    targetServerId      = chosen.id
    targetPlayerCount   = chosen.playing
    print(("[ServerHop] Tidak ada server 7–15 pemain, pakai FALLBACK: %s | %d pemain")
        :format(targetServerId, targetPlayerCount))
end

--------------------------------------------------------------------
-- 🔹 Teleport & handle error (termasuk kode 773)
--------------------------------------------------------------------
if targetServerId then
    print("[ServerHop] Teleport ke server:", targetServerId,
          "| pemain:", targetPlayerCount)

    local okTp, tpErr = pcall(function()
        -- Pakai LocalPlayer biar pasti diri kamu yang ke-teleport
        TeleportService:TeleportToPlaceInstance(placeId, targetServerId, LocalPlayer)
    end)

    if not okTp then
        warn("[ServerHop] Teleport gagal:", tpErr)

        -- Deteksi error 773 (tempat dibatasi)
        local errStr = tostring(tpErr)
        if errStr:find("773") or errStr:lower():find("restricted") then
            warn("[ServerHop] Error 773 (tempat dibatasi). Ini batasan dari Roblox, tidak bisa di-bypass dari script.")
        end
    end
else
    warn("[ServerHop] Sama sekali tidak menemukan server lain yang cocok.")
    warn("[ServerHop] Kalau mau, kamu bisa rejoin manual atau pakai Teleport(placeId).")
    -- Contoh kalau mau auto rejoin ke game (matchmaking baru):
    -- pcall(function()
    --     TeleportService:Teleport(placeId, LocalPlayer)
    -- end)
end
