-- lib/matrix.lua v0.24
-- CHANGELOG v0.24:
-- 1. FIX FATAL: Eliminado update_destination y el desempaquetado de 64 argumentos.
-- 2. ARQUITECTURA: Implementadas funciones connect/disconnect basadas en Deltas.

local Matrix = {}

function Matrix.connect(src_id, dst_id, G)
    G.patch[src_id][dst_id].active = true
    engine.patch_set(dst_id, src_id, 1.0)
end

function Matrix.disconnect(src_id, dst_id, G)
    G.patch[src_id][dst_id].active = false
    engine.patch_set(dst_id, src_id, 0.0)
end

function Matrix.init(G)
    -- Enviar solo las conexiones activas para evitar UDP Flood
    for src_id = 1, 64 do
        for dst_id = 1, 64 do
            if G.patch[src_id] and G.patch[src_id][dst_id] and G.patch[src_id][dst_id].active then
                engine.patch_set(dst_id, src_id, 1.0)
            end
        end
    end
    
    for i = 1, 64 do
        local lvl = params:get("node_lvl_" .. i)
        local node = G.nodes[i]
        
        if node then
            node.level = lvl
            if node.type == "out" then
                engine.set_out_level(i, lvl)
            elseif node.type == "in" then
                engine.set_in_level(i, lvl)
                
                if node.module == 8 and i >= 55 and i <= 58 then
                    local pan = params:get("node_pan_" .. i)
                    node.pan = pan
                    engine.set_in_pan(i, pan)
                end
            end
        end
    end
    
    print("ELIANNE: Matriz DSP y Niveles Inicializados al 100%.")
end

function Matrix.update_node_params(node)
    if node.type == "out" then
        engine.set_out_level(node.id, node.level)
    elseif node.type == "in" then
        engine.set_in_level(node.id, node.level)
        
        if node.module == 8 and node.id >= 55 and node.id <= 58 then
            engine.set_in_pan(node.id, node.pan)
            params:set("node_pan_" .. node.id, node.pan)
        end
    end
    
    params:set("node_lvl_" .. node.id, node.level)
end

return Matrix
