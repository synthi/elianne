-- lib/matrix.lua v0.102
-- CHANGELOG v0.101:
-- 1. FIX: Reconstruido sobre la base correcta v0.24 (Deltas con patch_set en lugar de UDP Flood).
-- 2. OPTIMIZATION: Dynamic Node Pausing integrado con la lógica de Deltas para ahorrar CPU.

local Matrix = {}

-- Función auxiliar para evaluar si una fila debe pausarse (0 cables) o reanudarse (>0 cables)
local function evaluate_row_pause(dst_id, G)
    local active_count = 0
    for src_id = 1, 64 do
        if G.patch[src_id] and G.patch[src_id][dst_id] and G.patch[src_id][dst_id].active then
            active_count = active_count + 1
        end
    end
    
    -- SC usa índices 0-63 para los synth_matrix_rows, por eso enviamos dst_id - 1
    if active_count == 0 then
        engine.pause_matrix_row(dst_id - 1)
    else
        engine.resume_matrix_row(dst_id - 1)
    end
end

function Matrix.connect(src_id, dst_id, G)
    G.patch[src_id][dst_id].active = true
    -- 1. Primero reanudamos la fila por si estaba pausada (ahorro de CPU)
    engine.resume_matrix_row(dst_id - 1)
    -- 2. Luego enviamos el delta de conexión
    engine.patch_set(dst_id, src_id, 1.0)
end

function Matrix.disconnect(src_id, dst_id, G)
    G.patch[src_id][dst_id].active = false
    -- 1. Enviamos el delta para apagar la conexión
    engine.patch_set(dst_id, src_id, 0.0)
    -- 2. Evaluamos si era la última conexión para pausar la fila y ahorrar CPU
    evaluate_row_pause(dst_id, G)
end

function Matrix.init(G)
   -- 1. Enviar SOLO las conexiones activas y evaluar pausas (Evita UDP Flood)
    for dst_id = 1, 64 do
        local has_active = false
        for src_id = 1, 64 do
            if G.patch[src_id] and G.patch[src_id][dst_id] and G.patch[src_id][dst_id].active then
                engine.patch_set(dst_id, src_id, 1.0)
                has_active = true
            end
        end
        
        -- Pausar o reanudar la fila según su estado inicial
        if has_active then
            engine.resume_matrix_row(dst_id - 1)
        else
            engine.pause_matrix_row(dst_id - 1)
        end
    end
    
    -- 2. Inicializar niveles y paneos
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
    
    print("ELIANNE: Matriz DSP (Deltas + Pausing) y Niveles Inicializados al 100%.")
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
