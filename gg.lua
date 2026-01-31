--==[ SMART SERVER HOPPER – 3–4 PLAYER PRIORITY ]==--

-- Pastikan game sudah load
if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- Delay setelah auto execute
task.wait(20)

----------------------------------------------------------------------
-- SERVICES & INFO
----------------------------------------------------------------------
local Players         = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")

local LocalPlayer  = Players.LocalPlayer
local placeId      = game.PlaceId
local currentJobId = game.JobId

----------------------------------------------------------------------
-- 🔧 KONFIGURASI
----------------------------------------------------------------------
local TARGET_MIN      = 3      -- target utama minimal player
local TARGET_MAX      = 4      -- target utama maksimal player
local MAX_PAGES       = 6      -- jumlah page server yang discan
local REQUEST_LIMIT   = 100    -- jangan diubah

----------------------------------------------------------------------
-- 🔹 LOAD FRIEND LIST (INFO SAJA)
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

local function HasFriendHere()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and FriendIds[plr.UserId] then
            return true, plr.Name
        end
    end
    return false
end

local hasFriend, friendName = HasFriendHere()
if hasFriend then
    warn("[ServerHop] Ada teman di server:", friendName)
else
    print("[ServerHop] Tidak ada teman di server ini")
end

----------------------------------------------------------------------
-- 🔹 GET SERVER LIST
----------------------------------------------------------------------
local cursor = nil

local function GetServers()
    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=%d")
        :format(placeId, REQUEST_LIMIT)

    if cursor then
        url ..= "&cursor=" .. cursor
    end

    local ok, res = pcall(function()
        return game:HttpGet(url)
    end)

    if not ok then
        warn("[ServerHop] Gagal HttpGet:", res)
        return nil
    end

    local decoded
    local okDecode, err = pcall(function()
        decoded = HttpService:JSONDecode(res)
    end)

    if not okDecode then
        warn("[ServerHop] Gagal decode JSON:", err)
        return nil
    end

    cursor = decoded.nextPageCursor
    return decoded.data
end

----------------------------------------------------------------------
-- 🔎 SEARCH SERVER
----------------------------------------------------------------------
print("[ServerHop] Mencari server 3–4 player...")
print("[ServerHop] Current JobId:", currentJobId)

local foundServerId    = nil
local foundPlayerCount = nil

local fallbackId       = nil
local fallbackPlayers  = -1

for page = 1, MAX_PAGES do
    local servers = GetServers()
    if not servers then break end

    for _, server in ipairs(servers) do
        local id      = server.id
        local playing = server.playing or 0
        local maxP    = server.maxPlayers or 0

        print(("[ServerHop] Cek server %s | %d/%d pemain")
            :format(tostring(id), playing, maxP))

        if not id or id == currentJobId or playing >= maxP then
            continue
        end

        -- 🎯 TARGET UTAMA: 3–4 PLAYER
        if playing >= TARGET_MIN and playing <= TARGET_MAX then
            foundServerId    = id
            foundPlayerCount = playing
            print("[ServerHop] ✅ TARGET FOUND:", id, "|", playing, "player")
            break
        end

        -- ⚠️ FALLBACK: <3 PLAYER (AMBIL YANG TERBESAR)
        if playing < TARGET_MIN and playing > fallbackPlayers then
            fallbackPlayers = playing
            fallbackId      = id
        end
    end

    if foundServerId or not cursor then break end
end

-- PAKAI FALLBACK JIKA TARGET UTAMA TIDAK ADA
if not foundServerId and fallbackId then
    foundServerId    = fallbackId
    foundPlayerCount = fallbackPlayers
    print("[ServerHop] ⚠️ Fallback server dipakai:",
          foundServerId, "|", foundPlayerCount, "player")
end

----------------------------------------------------------------------
-- 🚀 TELEPORT
----------------------------------------------------------------------
if foundServerId then
    print("[ServerHop] Teleporting ke:", foundServerId)

    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(placeId, foundServerId)
    end)

    if not ok then
        warn("[ServerHop] Teleport gagal:", err)
        if tostring(err):find("773") then
            warn("[ServerHop] Error 773 (Restricted Place)")
        end
    end
else
    warn("[ServerHop] ❌ Tidak ada server yang bisa dipakai.")
    -- uncomment kalau mau rejoin paksa
    -- TeleportService:Teleport(placeId)
end
