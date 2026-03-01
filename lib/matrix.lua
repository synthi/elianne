-- lib/matrix.lua v0.302
-- CHANGELOG v0.301: Bucles expandidos a 69 para soportar Nodos MIDI y Clock.

local Matrix = {}

local function evaluate_row_pause(dst_id, G)
    local active_count = 0
    for src_id = 1, 69 do
        if G.patch[src_id] and G.patch[src_id][dst_id] and G.patch[src_id][dst_id].active then
            active_count = active_count + 1
        end
    end
    if active_count == 0 then engine.pause_matrix_row(dst_id - 1) else engine.resume_matrix_row(dst_id - 1) end
end

function Matrix.connect(src_id, dst_id, G)
    G.patch[src_id][dst_id].active = true
    engine.resume_matrix_row(dst_id - 1)
    engine.patch_set(dst_id, src_id, 1.0)
end

function Matrix.disconnect(src_id, dst_id, G)
    G.patch[src_id][dst_id].active = false
    engine.patch_set(dst_id, src_id, 0.0)
    evaluate_row_pause(dst_id, G)
end


function Matrix.init(G)
    -- FIX: Si Storage.load ya está enviando los cables, Matrix.init se salta este paso para evitar Race Condition
    if not G.pset_loaded then
        for dst_id = 1, 64 do
            local has_active = false
            for src_id = 1, 69 do
                if G.patch[src_id] and G.patch[src_id][dst_id] and G.patch[src_id][dst_id].active then
                    engine.patch_set(dst_id, src_id, 1.0)
                    has_active = true
                end
            end
            if has_active then engine.resume_matrix_row(dst_id - 1) else engine.pause_matrix_row(dst_id - 1) end
        end
    end
    
    for i = 1, 69 do
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
    print("ELIANNE: Matriz DSP (69x64) Inicializada.")
end

function Matrix.update_node_params(node)
    if node.type == "out" then engine.set_out_level(node.id, node.level)
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
