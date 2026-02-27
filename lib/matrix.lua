-- lib/matrix.lua v0.21
-- CHANGELOG v0.2:
-- 1. MAPEO TOTAL: Implementadas funciones para enviar niveles de los 64 nodos a SC.
-- 2. SINCRONIZACIÓN: Enlaza los cambios de UI con los parámetros ocultos de Norns.

local Matrix = {}

function Matrix.init(G)
    -- 1. Inicializa la matriz de ruteo en SuperCollider (Ceros)
    for dst_id = 1, 32 do
        Matrix.update_destination(dst_id, G)
    end
    
    -- 2. Inicializa los niveles de los 64 nodos basándose en los parámetros guardados
    for i = 1, 64 do
        local lvl = params:get("node_lvl_" .. i)
        if i <= 32 then
            -- Nodos 1 a 32 son SALIDAS (Sources para la matriz)
            engine.set_out_level(i, lvl)
            if G.nodes[i] then G.nodes[i].level = lvl end
        else
            -- Nodos 33 a 64 son ENTRADAS (Destinations para la matriz)
            -- Nota: En globals.lua los IDs van del 1 al 64 secuencialmente.
            -- Asumimos que 1-32 son Outs y 33-64 son Ins para el mapeo OSC.
            engine.set_in_level(i - 32, lvl)
            if G.nodes[i] then G.nodes[i].level = lvl end
            
            -- Paneo para el Nexus
            if i >= 61 and i <= 64 then -- IDs de entradas del Nexus
                local pan = params:get("node_pan_" .. i)
                engine.set_in_pan(i - 32, pan)
                if G.nodes[i] then G.nodes[i].pan = pan end
            end
        end
    end
    
    print("ELIANNE: Matriz DSP y Niveles Inicializados al 100%.")
end

function Matrix.update_destination(dst_id, G)
    local row_data = {}
    
    -- Recopila el estado de las 64 fuentes hacia este destino
    for src_id = 1, 64 do
        if G.patch[src_id] and G.patch[src_id][dst_id] and G.patch[src_id][dst_id].active then
            table.insert(row_data, 1.0)
        else
            table.insert(row_data, 0.0)
        end
    end
    
    -- Enviar comando OSC al Engine
    engine.patch_row(dst_id, table.unpack(row_data))
end

-- Llamada desde ScreenUI cuando el usuario gira E2/E3 en un nodo
function Matrix.update_node_params(node)
    -- 1. Actualizar SuperCollider
    if node.type == "out" then
        engine.set_out_level(node.id, node.level)
    elseif node.type == "in" then
        -- Ajuste de ID: Si las entradas en SC están indexadas de 1 a 32
        local sc_in_id = node.id - 32 
        engine.set_in_level(sc_in_id, node.level)
        
        if node.module == 8 then
            engine.set_in_pan(sc_in_id, node.pan)
            params:set("node_pan_" .. node.id, node.pan) -- Guardar en Norns
        end
    end
    
    -- 2. Guardar en el sistema de parámetros ocultos de Norns para Snapshots
    params:set("node_lvl_" .. node.id, node.level)
end

return Matrix
