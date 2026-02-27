-- lib/matrix.lua v0.1
-- CHANGELOG v0.1:
-- 1. INIT: Creación del motor de ruteo OSC hacia SuperCollider.
-- 2. OPTIMIZACIÓN: Actualización por filas (Destinations) para evitar desbordamiento UDP.

local Matrix = {}

function Matrix.init(G)
    -- Inicializa la matriz en SuperCollider enviando ceros a todos los destinos
    for dst_id = 1, #G.nodes do
        Matrix.update_destination(dst_id, G)
    end
    print("ELIANNE: Matriz DSP Inicializada.")
end

function Matrix.update_destination(dst_id, G)
    -- Recopila el estado de las 32 fuentes posibles hacia este destino
    local row_data = {}
    
    -- Aseguramos enviar exactamente 32 valores (límite actual de nuestra arquitectura)
    for src_id = 1, 32 do
        if G.patch[src_id] and G.patch[src_id][dst_id] and G.patch[src_id][dst_id].active then
            table.insert(row_data, 1.0)
        else
            table.insert(row_data, 0.0)
        end
    end
    
    -- Enviar comando OSC al Engine: "patch_row", destino_id,[32 valores float]
    engine.patch_row(dst_id, table.unpack(row_data))
end

-- Esta función se llamará desde ScreenUI cuando el usuario mueva el Attenuverter (E2)
function Matrix.update_node_params(node)
    if node.type == "out" then
        engine.set_out_level(node.id, node.level)
    elseif node.type == "in" then
        engine.set_in_level(node.id, node.level)
        if node.module == 8 then -- Si es el Nexus, actualizar Paneo
            engine.set_in_pan(node.id, node.pan)
        end
    end
end

return Matrix
