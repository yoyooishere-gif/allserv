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
local Deleted = false
local S_T = game:GetService("TeleportService")
local S_H = game:GetService("HttpService")

local File = pcall(function()
    AllIDs = S_H:JSONDecode(readfile("server-hop-temp.json"))
end)

if not File then
    table.insert(AllIDs, actualHour)
    pcall(function()
        writefile("server-hop-temp.json", S_H:JSONEncode(AllIDs))
    end)
end

local function TPReturner()
    local Site
    if foundAnything == "" then
        Site = S_H:JSONDecode(game:HttpGet(
            "https://games.roblox.com/v1/games/" .. PLACE_ID .. "/servers/Public?sortOrder=Asc&limit=100"
        ))
    else
        Site = S_H:JSONDecode(game:HttpGet(
            "https://games.roblox.com/v1/games/" .. PLACE_ID .. "/servers/Public?sortOrder=Asc&limit=100&cursor=" .. foundAnything
        ))
    end

    if Site.nextPageCursor and Site.nextPageCursor ~= "null" then
        foundAnything = Site.nextPageCursor
    end

    local num = 0
    for _, v in pairs(Site.data) do
        local Possible = true
        local ID = tostring(v.id)

        if tonumber(v.maxPlayers) > tonumber(v.playing) then
            for _, Existing in pairs(AllIDs) do
                if num ~= 0 then
                    if ID == tostring(Existing) then
                        Possible = false
                    end
                else
                    if tonumber(actualHour) ~= tonumber(Existing) then
                        pcall(function()
                            delfile("server-hop-temp.json")
                            AllIDs = {}
                            table.insert(AllIDs, actualHour)
                        end)
                    end
                end
                num += 1
            end

            if Possible then
                table.insert(AllIDs, ID)
                task.wait()
                pcall(function()
                    writefile("server-hop-temp.json", S_H:JSONEncode(AllIDs))
                    task.wait()
                    S_T:TeleportToPlaceInstance(PLACE_ID, ID, game.Players.LocalPlayer)
                end)
                task.wait(4)
            end
        end
    end
end

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
