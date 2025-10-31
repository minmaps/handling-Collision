--=============================================================
-- Client-only Vehicle No-Collision (executor friendly)
-- - ON/OFF uniquement pour le joueur local (client-side)
-- - Garde la collision avec le monde/sol (jamais SetEntityCollision false)
-- - Ré-applique en continu (surtout aux véhicules) même en mouvement/stream
-- - Toggle par double-tap sur W (moins de conflits avec l'accélération)
--=============================================================

-- ========== CONFIG ==========
local DOUBLE_TAP_MS       = 350        -- fenêtre double-tap sur W
local BASE_RADIUS         = 110.0      -- rayon par défaut
local FAST_RADIUS         = 220.0      -- rayon si vitesse > seuil
local FAST_SPEED_MS       = 20.0       -- seuil vitesse (m/s ~ 72 km/h)
local VEHICLE_TICK_MS     = 0          -- appliquer véhicules à chaque frame
local OTHER_TICK_MS       = 80         -- peds/objets moins fréquent
local UI_X, UI_Y          = 0.12, 0.085
local UI_W, UI_H          = 0.22, 0.06
local UI_BG_ALPHA         = 150
local UI_BORDER_ALPHA     = 200

-- ========== STATE ==========
local enabled = false
local lastWTime = 0
local ghostVeh, ghostPed, ghostObj = {}, {}, {}
local lastVeh = 0

-- ========== UTILS ==========
local function drawText(x, y, scale, txt, r, g, b, a, center)
    SetTextFont(4); SetTextScale(scale, scale); SetTextColour(r or 255, g or 255, b or 255, a or 255)
    SetTextOutline(); SetTextCentre(center and true or false)
    BeginTextCommandDisplayText("STRING"); AddTextComponentSubstringPlayerName(txt); EndTextCommandDisplayText(x, y)
end

local function drawWindow(x, y, w, h, bgA, borderA)
    DrawRect(x, y, w, h, 0, 0, 0, bgA or 140)
    local bw = 0.002
    DrawRect(x, y - h/2 + bw/2, w, bw, 255,255,255, borderA or 200)
    DrawRect(x, y + h/2 - bw/2, w, bw, 255,255,255, borderA or 200)
    DrawRect(x - w/2 + bw/2, y, bw, h, 255,255,255, borderA or 200)
    DrawRect(x + w/2 - bw/2, y, bw, h, 255,255,255, borderA or 200)
end

local function restoreAllForVehicle(veh)
    for ent,_ in pairs(ghostVeh) do if DoesEntityExist(ent) then
        SetEntityNoCollisionEntity(veh, ent, false); SetEntityNoCollisionEntity(ent, veh, false) end end
    for ent,_ in pairs(ghostPed) do if DoesEntityExist(ent) then
        SetEntityNoCollisionEntity(veh, ent, false); SetEntityNoCollisionEntity(ent, veh, false) end end
    for ent,_ in pairs(ghostObj) do if DoesEntityExist(ent) then
        SetEntityNoCollisionEntity(veh, ent, false); SetEntityNoCollisionEntity(ent, veh, false) end end
    ghostVeh, ghostPed, ghostObj = {}, {}, {}
end

local function setEnabled(flag)
    enabled = flag
    local ped = PlayerPedId()
    if not enabled then
        if IsPedInAnyVehicle(ped, false) then
            local veh = GetVehiclePedIsIn(ped, false)
            if veh ~= 0 then restoreAllForVehicle(veh) end
        else ghostVeh, ghostPed, ghostObj = {}, {}, {} end
    end
end

-- ========== INPUT: double-tap W pour toggle ==========
CreateThread(function()
    while true do
        Wait(0)
        -- W = INPUT_MOVE_UP_ONLY (control = 32)
        if IsControlJustPressed(0, 32) then
            local t = GetGameTimer()
            if (t - lastWTime) <= DOUBLE_TAP_MS then
                setEnabled(not enabled)
                lastWTime = 0
            else
                lastWTime = t
            end
        end
    end
end)

-- ========= UI TRÈS DISCRÈTE (remplace ton ancien bloc UI) =========
-- Affiche uniquement "ON" ou "OFF" en petit, au niveau de la mini-carte.
-- Position auto-ajustée avec la safe zone pour différents ratios/résolutions.

-- CONFIG UI (tu peux ajuster finement si besoin)
local UI_SCALE        = 0.28   -- taille du texte
local UI_ALPHA        = 160    -- opacité (0-255)
local UI_OFFSET_X     = 0.172  -- offset horizontal relatif à la safe zone (≈ bord droit de la mini-carte)
local UI_OFFSET_Y     = 0.052  -- offset vertical relatif à la safe zone (≈ juste au-dessus de la mini-carte)

local function drawTinyStatusNearMinimap()
    -- calcule une position stable près de la mini-carte, en tenant compte de la safe zone
    local safe = GetSafeZoneSize()
    local sx = (1.0 - safe) * 0.5
    local sy = (1.0 - safe) * 0.5

    -- ancrage: coin bas-gauche + offsets pour viser la zone mini-carte
    local x = sx + UI_OFFSET_X
    local y = 1.0 - sy - UI_OFFSET_Y

    local txt = enabled and "~g~ON~s~" or "~r~OFF~s~"

    SetTextFont(4)
    SetTextScale(UI_SCALE, UI_SCALE)
    -- Couleur blanche légèrement transparente ; le code couleur (~g~/~r~) gère ON/OFF
    SetTextColour(255, 255, 255, UI_ALPHA)
    SetTextDropshadow(1, 0, 0, 0, 120)  -- légère lisibilité sans “bloc” visuel
    SetTextOutline()
    SetTextCentre(false)
    BeginTextCommandDisplayText("STRING")
    AddTextComponentSubstringPlayerName(txt)
    EndTextCommandDisplayText(x, y)
end

-- Boucle UI : texte minimal en permanence
CreateThread(function()
    while true do
        Wait(0)
        drawTinyStatusNearMinimap()
    end
end)
-- ========= FIN DU BLOC UI =========


-- ========== LOGIQUE: ré-applique en continu ==========
-- Boucle véhicules (frame-by-frame quand ON)
CreateThread(function()
    while true do
        if not enabled then
            Wait(200)
        else
            local ped = PlayerPedId()
            if not IsPedInAnyVehicle(ped, false) then
                Wait(120)
            else
                local veh = GetVehiclePedIsIn(ped, false)
                if veh == 0 then
                    Wait(120)
                else
                    -- si on a changé de véhicule, on restaure l'ancien
                    if veh ~= lastVeh and lastVeh ~= 0 then restoreAllForVehicle(lastVeh) end
                    lastVeh = veh

                    -- rayon dynamique selon la vitesse
                    local speed = GetEntitySpeed(veh) -- m/s
                    local radius = (speed > FAST_SPEED_MS) and FAST_RADIUS or BASE_RADIUS
                    local r2 = radius * radius
                    local myPos = GetEntityCoords(veh)

                    -- VEHICULES : ré-applique à CHAQUE frame (collisions parfois “perdues” par le moteur après gros chocs)
                    for _, other in ipairs(GetGamePool("CVehicle")) do
                        if other ~= veh and DoesEntityExist(other) then
                            local op = GetEntityCoords(other)
                            local dx,dy,dz = op.x - myPos.x, op.y - myPos.y, op.z - myPos.z
                            if (dx*dx + dy*dy + dz*dz) < r2 then
                                SetEntityNoCollisionEntity(veh, other, true)
                                SetEntityNoCollisionEntity(other, veh, true)
                                ghostVeh[other] = true
                            end
                        end
                    end

                    Wait(VEHICLE_TICK_MS) -- 0 = chaque frame
                end
            end
        end
    end
end)

-- Boucle Peds/Objets (moins fréquent)
CreateThread(function()
    while true do
        if not enabled then
            Wait(250)
        else
            local ped = PlayerPedId()
            if not IsPedInAnyVehicle(ped, false) then
                Wait(200)
            else
                local veh = GetVehiclePedIsIn(ped, false)
                if veh == 0 then
                    Wait(200)
                else
                    local speed = GetEntitySpeed(veh)
                    local radius = (speed > FAST_SPEED_MS) and FAST_RADIUS or BASE_RADIUS
                    local r2 = radius * radius
                    local myPos = GetEntityCoords(veh)

                    -- PEDS
                    for _, p in ipairs(GetGamePool("CPed")) do
                        if p ~= ped and DoesEntityExist(p) then
                            local pp = GetEntityCoords(p)
                            local dx,dy,dz = pp.x - myPos.x, pp.y - myPos.y, pp.z - myPos.z
                            if (dx*dx + dy*dy + dz*dz) < r2 then
                                SetEntityNoCollisionEntity(veh, p, true)
                                SetEntityNoCollisionEntity(p, veh, true)
                                ghostPed[p] = true
                            end
                        end
                    end

                    -- OBJETS
                    for _, obj in ipairs(GetGamePool("CObject")) do
                        if DoesEntityExist(obj) then
                            local op = GetEntityCoords(obj)
                            local dx,dy,dz = op.x - myPos.x, op.y - myPos.y, op.z - myPos.z
                            if (dx*dx + dy*dy + dz*dz) < r2 then
                                SetEntityNoCollisionEntity(veh, obj, true)
                                SetEntityNoCollisionEntity(obj, veh, true)
                                ghostObj[obj] = true
                            end
                        end
                    end

                    Wait(OTHER_TICK_MS)
                end
            end
        end
    end
end)

-- Sur changement de véhicule : nettoyage auto
CreateThread(function()
    while true do
        Wait(300)
        if not enabled then goto cont end
        local ped = PlayerPedId()
        local veh = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) or 0
        if veh ~= lastVeh then
            if lastVeh ~= 0 then restoreAllForVehicle(lastVeh) end
            lastVeh = veh
        end
        ::cont::
    end
end)
