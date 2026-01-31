--==[ SMART SERVER HOPPER – RANDOM PAGE + MID TRAFFIC ]==--

if not game:IsLoaded() then
    game.Loaded:Wait()
end

task.wait(20)

----------------------------------------------------------------------
-- SERVICES
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
local TARGET_MIN       = 3       -- target utama minimal player
local TARGET_MAX       = 4       -- target utama maksimal player

local MAX_SCAN_PAGES   = 6       -- page yang DISCAN setelah lompat
local REQUEST_LIMIT    = 100     -- jumlah server per page

local RANDOM_START     = true    -- lompat ke page acak dulu
local RANDOM_PAGE_MIN  = 5      -- minimal page yang dilompati
local RANDOM_PAGE_MAX  = 30     -- maksimal page yang dilompati

----------------------------------------------------------------------
-- 🔹 FRIEND LIST (info saja)
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
-- 🔹 GET SERVER LIST (Roblox API)
----------------------------------------------------------------------
local cursor = nil

local function GetServers()
    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&limit=%d")
        :format(placeId, REQUEST_LIMIT)

    if cursor then
        url = url .. "&cursor=" .. cursor
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
-- 🔹 LOMPAT KE PAGE ACAK (SIMULASI "PAGE 1000")
----------------------------------------------------------------------
local function SkipToRandomPage()
    if not RANDOM_START then return end

    local target = math.random(RANDOM_PAGE_MIN, RANDOM_PAGE_MAX)
    print(("[ServerHop] Random start page ~%d"):format(target))

    for i = 1, target - 1 do
        local servers = GetServers()
        if not servers or not cursor then
            print("[ServerHop] Stop skip di page", i, "(tidak ada page lanjutan)")
            break
        end
    end
end

----------------------------------------------------------------------
-- 🔎 CARI SERVER
----------------------------------------------------------------------
print("[ServerHop] Cari server 3–4 player dari page acak...")
print("[ServerHop] Current JobId:", currentJobId)

local foundServerId      = nil   -- server pas 3–4
local foundPlayerCount   = nil

local bestOverallId      = nil   -- server TERPADAT (fallback)
local bestOverallPlayers = -1

-- 1) Lompat page dulu
SkipToRandomPage()

-- 2) Scan beberapa page dari posisi sekarang
for page = 1, MAX_SCAN_PAGES do
    local servers = GetServers()
    if not servers then break end

    for _, server in ipairs(servers) do
        local id      = server.id
        local playing = server.playing or 0
        local maxP    = server.maxPlayers or 0

        print(("[ServerHop] Cek server %s | %d/%d pemain")
            :format(tostring(id), playing, maxP))

        -- skip server aneh / sama / penuh
        if not id or id == currentJobId or playing >= maxP then
            continue
        end

        -- 🎯 TARGET: 3–4 PLAYER
        if playing >= TARGET_MIN and playing <= TARGET_MAX then
            foundServerId    = id
            foundPlayerCount = playing
            print("[ServerHop] ✅ TARGET 3–4 FOUND:", id, "|", playing, "player")
            break
        end

        -- 🌟 FALLBACK: server TERPADAT yang belum full
        if playing > bestOverallPlayers then
            bestOverallPlayers = playing
            bestOverallId      = id
        end
    end

    if foundServerId or not cursor then
        break
    end
end

-- Kalau tidak ada 3–4 player, pakai server TERPADAT
if not foundServerId and bestOverallId then
    foundServerId    = bestOverallId
    foundPlayerCount = bestOverallPlayers
    print("[ServerHop] ⚠️ Pakai server TERPADAT:",
          foundServerId, "|", bestOverallPlayers, "player")
end

----------------------------------------------------------------------
-- 🚀 TELEPORT
----------------------------------------------------------------------
if foundServerId then
    print("[ServerHop] Teleporting ke:", foundServerId, "| players:", foundPlayerCount or "?")

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
    warn("[ServerHop] ❌ Tidak menemukan server yang bisa dipakai.")
    -- Kalau mau auto rejoin global (kadang dilempar ke server rame):
    -- TeleportService:Teleport(placeId)
end
