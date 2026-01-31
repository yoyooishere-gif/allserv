--==[ REJOIN SAMPAI SERVER RAME (MIN PLAYER) ]==--

if not game:IsLoaded() then
    game.Loaded:Wait()
end

----------------------------------------------------------------------
-- 🔧 KONFIGURASI
----------------------------------------------------------------------
local CONFIG = {
    DelayBeforeCheck   = 15,   -- tunggu world load dulu sebelum cek (detik)
    MinPlayersDesired  = 3,   -- minimal player yang kamu mau (ubah misal 4)
    MaxRejoinAttempts  = 8,   -- maksimal berapa kali coba rejoin
    RejoinDelay        = 6,   -- jeda sebelum kirim Teleport lagi (detik)
}

----------------------------------------------------------------------
-- SERVICES
----------------------------------------------------------------------
local Players         = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local placeId         = game.PlaceId

task.wait(CONFIG.DelayBeforeCheck)

----------------------------------------------------------------------
-- FUNGSI AMBIL JUMLAH PLAYER
----------------------------------------------------------------------
local function getPlayerCount()
    -- #Players:GetPlayers() biasanya lebih akurat daripada server.playing di API
    return #Players:GetPlayers()
end

----------------------------------------------------------------------
-- LOOP REJOIN
----------------------------------------------------------------------
local attempt = 0

while attempt < CONFIG.MaxRejoinAttempts do
    local count = getPlayerCount()
    print(("[RejoinMin] Server saat ini: %d pemain"):format(count))

    if count >= CONFIG.MinPlayersDesired then
        print(("[RejoinMin] ✅ Cukup rame (>= %d player). Stop rejoin."):format(CONFIG.MinPlayersDesired))
        break
    end

    attempt += 1
    warn(("[RejoinMin] Server sepi (%d/<%d). Rejoin attempt %d ...")
        :format(count, CONFIG.MinPlayersDesired, attempt))

    task.wait(CONFIG.RejoinDelay)

    local ok, err = pcall(function()
        TeleportService:Teleport(placeId)
    end)

    if not ok then
        warn("[RejoinMin] Teleport gagal:", err)
        break
    end

    -- Catatan penting:
    -- Mayoritas executor auto-execute script ulang setelah Teleport,
    -- jadi loop ini biasanya TIDAK lanjut, tapi akan mulai dari awal
    -- di server baru. Itu normal dan justru yang kita mau.
    break
end
