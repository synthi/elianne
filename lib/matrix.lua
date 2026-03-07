-- lib/matrix.lua v0.520
-- CHANGELOG v0.520:
-- 1. REFACTOR: Adaptación a topología Split TX/RX (36 TX).
-- 2. FIX: Protección Anti-Flooding con clock.sleep(0.002) en Matrix.init.

local Matrix = {}

local function evaluate_row_pause(dst_id, G)
    local dst_node = G.nodes[dst_id]
    if not dst_node or dst_node.type ~= "in" then return end
    
    local active_count = 0
    for src_id = 1, 64 do
        if G.patch[src_id] and G.patch[src_id][dst_id] and G.patch[src_id][dst_id].active then
            active_count = active_count + 1
        end
    end
    if active_count == 0 then engine.pause_matrix_row(dst_node.rx_idx - 1) else engine.resume_matrix_row(dst_node.rx_idx - 1) end
end

function Matrix.connect(src_id, dst_id, G)
    local src_node = G.nodes[src_id]
    local dst_node = G.nodes[dst_id]
    if not src_node or not dst_node then return end
    
    G.patch[src_id][dst_id].active = true; G.patch[src_id][dst_id].current_gain = 1.0
    engine.resume_matrix_row(dst_node.rx_idx - 1); engine.patch_set(dst_node.rx_idx, src_node.tx_idx, 1.0)
end

function Matrix.disconnect(src_id, dst_id, G)
    local src_node = G.nodes[src_id]
    local dst_node = G.nodes[dst_id]
    if not src_node or not dst_node then return end
    
    G.patch[src_id][dst_id].active = false; G.patch[src_id][dst_id].current_gain = 0.0
    engine.patch_set(dst_node.rx_idx, src_node.tx_idx, 0.0); evaluate_row_pause(dst_id, G)
end

function Matrix.init(G)
    clock.run(function()
        for dst_id = 1, 64 do
            local dst_node = G.nodes[dst_id]
            if dst_node and dst_node.type == "in" then
                local has_active = false; local row_vals = {}
                for i = 1, 36 do row_vals[i] = 0.0 end
                
                for src_id = 1, 64 do
                    local src_node = G.nodes[src_id]
                    if src_node and src_node.type == "out" then
                        local is_active = G.patch[src_id] and G.patch[src_id][dst_id] and G.patch[src_id][dst_id].active
                        G.patch[src_id][dst_id].current_gain = is_active and 1.0 or 0.0
                        row_vals[src_node.tx_idx] = is_active and 1.0 or 0.0
                        if is_active then has_active = true end
                    end
                end
                engine.patch_row_set(dst_node.rx_idx, table.concat(row_vals, ","))
                if has_active then engine.resume_matrix_row(dst_node.rx_idx - 1) else engine.pause_matrix_row(dst_node.rx_idx - 1) end
                clock.sleep(0.002)
            end
        end
        
        for i = 1, 64 do
            local lvl = params:get("node_lvl_" .. i)
            local node = G.nodes[i]
            if node then
                node.level = lvl
                if node.type == "out" then engine.set_out_level(i, lvl)
                elseif node.type == "in" then
                    engine.set_in_level(i, lvl)
                    if node.module == 8 and i >= 55 and i <= 58 then
                        local pan = params:get("node_pan_" .. i)
                        node.pan = pan; engine.set_in_pan(i, pan)
                    end
                end
            end
        end
        print("ELIANNE: Matriz DSP Inicializada al 100%.")
    end)
end

function Matrix.update_node_params(node)
    if node.type == "out" then engine.set_out_level(node.id, node.level)
    elseif node.type == "in" then
        engine.set_in_level(node.id, node.level)
        if node.module == 8 and node.id >= 55 and node.id <= 58 then
            engine.set_in_pan(node.id, node.pan); params:set("node_pan_" .. node.id, node.pan)
        end
    end
    params:set("node_lvl_" .. node.id, node.level)
end

return Matrix
