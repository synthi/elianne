-- lib/matrix.lua v0.22
-- CHANGELOG v0.22:
-- 1. FIX FATAL: Eliminada la asunción de índices rígidos (i <= 32).
-- 2. MAPEO: Los IDs de nodo se envían directamente a SC, coincidiendo con la matriz plana de 64 buses.

local Matrix = {}

function Matrix.init(G)
    for dst_id = 1, 64 do
        Matrix.update_destination(dst_id, G)
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
                
                -- Paneo exclusivo para las entradas del Nexus (IDs 55 a 58)
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

function Matrix.update_destination(dst_id, G)
    local row_data = {}
    
    for src_id = 1, 64 do
        if G.patch[src_id] and G.patch[src_id][dst_id] and G.patch[src_id][dst_id].active then
            table.insert(row_data, 1.0)
        else
            table.insert(row_data, 0.0)
        end
    end
    
    engine.patch_row(dst_id, table.unpack(row_data))
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
