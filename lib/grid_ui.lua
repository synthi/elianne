-- lib/grid_ui.lua v0.200
-- CHANGELOG v0.200:
-- 1. FEATURE: Botón SHIFT (X=1, Y=8) y lógica de "Desconectar Todo" (Shift + Hold > 1s).
-- 2. FEATURE: Máquina de estados visual y lógica para 6 Snapshots (X=3 a 8, Y=8).

local GridUI = {}

GridUI.cache = {}
GridUI.held_nodes = {} 
GridUI.disconnect_timer = nil
GridUI.refresh_counter = 0
GridUI.key_times = {}

function GridUI.init(G)
    for x = 1, 16 do
        GridUI.cache[x] = {}
        for y = 1, 8 do
            GridUI.cache[x][y] = -1
        end
    end
    G.grid_cache = GridUI.cache 
end

function GridUI.key(G, g, x, y, z)
    local key_id = x .. "," .. y
    if z == 1 then
        local now = util.time()
        if GridUI.key_times[key_id] and (now - GridUI.key_times[key_id]) < 0.05 then return end
        GridUI.key_times[key_id] = now
    end

    -- LÓGICA DEL BOTÓN SHIFT
    if x == 1 and y == 8 then
        G.shift_held = (z == 1)
        G.screen_dirty = true
        return
    end

    -- LÓGICA DE SNAPSHOTS
    if y == 8 and x >= 3 and x <= 8 then
        if z == 1 then
            local snap_id = x - 2
            local Storage = include('lib/storage')
            
            if G.shift_held then
                -- BORRAR
                if G.snapshots[snap_id].has_data then
                    G.snapshots[snap_id].has_data = false
                    G.snapshots[snap_id].patch = nil
                    G.snapshots[snap_id].params = nil
                    if G.active_snap == snap_id then G.active_snap = nil end
                    print("ELIANNE: Snapshot " .. snap_id .. " borrado.")
                end
            else
                if not G.snapshots[snap_id].has_data or G.active_snap == snap_id then
                    -- GUARDAR / SOBREESCRIBIR
                    Storage.save_snapshot(G, snap_id)
                else
                    -- CARGAR (MORPH)
                    Storage.load_snapshot(G, snap_id)
                end
            end
            G.screen_dirty = true
        end
        return
    end

    local node = G.grid_map[x][y]
    local is_menu = (y == 4)

    if z == 1 then
        table.insert(GridUI.held_nodes, {x=x, y=y, time=util.time(), node=node, is_menu=is_menu})
        
        if is_menu then
            local module_idx = math.ceil(x / 2)
            local page = (x % 2 == 1) and "A" or "B"
            G.focus.state = "menu"
            G.focus.module_id = module_idx
            G.focus.page = page
        elseif node and node.type ~= "dummy" then
            G.focus.state = node.type
            G.focus.node_x = x
            G.focus.node_y = y
            
            -- LÓGICA "DESCONECTAR TODO" (SHIFT + HOLD)
            if G.shift_held then
                GridUI.disconnect_timer = clock.run(function()
                    clock.sleep(1.0)
                    local Matrix = include('lib/matrix')
                    local count = 0
                    if node.type == "out" then
                        for dst = 1, 64 do
                            if G.patch[node.id][dst].active then
                                G.patch[node.id][dst].active = false
                                if Matrix.disconnect then Matrix.disconnect(node.id, dst, G) else Matrix.update_destination(dst, G) end
                                count = count + 1
                            end
                        end
                    elseif node.type == "in" then
                        for src = 1, 64 do
                            if G.patch[src][node.id].active then
                                G.patch[src][node.id].active = false
                                if Matrix.disconnect then Matrix.disconnect(src, node.id, G) else Matrix.update_destination(node.id, G) end
                                count = count + 1
                            end
                        end
                    end
                    print("ELIANNE: " .. count .. " cables desconectados del nodo " .. node.name)
                    G.screen_dirty = true
                    GridUI.disconnect_timer = nil
                end)
            -- LÓGICA DE PARCHEO NORMAL
            elseif #GridUI.held_nodes == 2 then
                local n1 = GridUI.held_nodes[1].node
                local n2 = GridUI.held_nodes[2].node
                
                if n1 and n2 and n1.type ~= n2.type and n1.type ~= "dummy" and n2.type ~= "dummy" then
                    local src = (n1.type == "out") and n1 or n2
                    local dst = (n1.type == "in") and n1 or n2
                    local Matrix = include('lib/matrix')
                    
                    if G.patch[src.id][dst.id].active then
                        GridUI.disconnect_timer = clock.run(function()
                            clock.sleep(1.0)
                            G.patch[src.id][dst.id].active = false
                            if Matrix.disconnect then Matrix.disconnect(src.id, dst.id, G) else Matrix.update_destination(dst.id, G) end
                            G.screen_dirty = true
                            print("ELIANNE: Cable desconectado.")
                            GridUI.disconnect_timer = nil
                        end)
                    else
                        G.patch[src.id][dst.id].active = true
                        if Matrix.connect then Matrix.connect(src.id, dst.id, G) else Matrix.update_destination(dst.id, G) end
                        print("ELIANNE: Cable conectado.")
                    end
                    
                    G.focus.state = "patching"
                end
            end
        end
    elseif z == 0 then
        if GridUI.disconnect_timer then
            clock.cancel(GridUI.disconnect_timer)
            GridUI.disconnect_timer = nil
        end

        for i, h in ipairs(GridUI.held_nodes) do
            if h.x == x and h.y == y then
                table.remove(GridUI.held_nodes, i)
                break
            end
        end
        
        if #GridUI.held_nodes == 0 then
            G.focus.state = "idle"
        end
    end
    
    G.screen_dirty = true
end

function GridUI.redraw(G, g)
    if not g then return end

    GridUI.refresh_counter = GridUI.refresh_counter + 1
    if GridUI.refresh_counter > 60 then
        for x = 1, 16 do for y = 1, 8 do GridUI.cache[x][y] = -1 end end
        GridUI.refresh_counter = 0
    end

    for x = 1, 16 do
        for y = 1, 8 do
            local b = 0
            
            -- DIBUJO FILA 8 (SHIFT Y SNAPSHOTS)
            if y == 8 then
                if x == 1 then
                    b = G.shift_held and 15 or 8
                elseif x >= 3 and x <= 8 then
                    local snap_id = x - 2
                    if G.active_snap == snap_id then
                        b = 11
                    elseif G.snapshots[snap_id].has_data then
                        b = 7
                    else
                        b = 1
                    end
                end
            else
                -- DIBUJO NODOS NORMALES
                local module_idx = math.ceil(x / 2)
                local is_even_module = (module_idx % 2 == 0)
                local node = G.grid_map[x][y]
                local is_menu = (y == 4)
                
                if (node and node.type ~= "dummy") or is_menu then
                    b = is_even_module and 4 or 2
                    
                    for _, h in ipairs(GridUI.held_nodes) do
                        if h.x == x and h.y == y then
                            b = 15
                        elseif h.node and node then
                            if h.node.type == "out" and node.type == "in" and G.patch[h.node.id][node.id].active then
                                b = 10
                            elseif h.node.type == "in" and node.type == "out" and G.patch[node.id][h.node.id].active then
                                b = 10
                            end
                        end
                    end
                    
                    if node and G.focus.state == "idle" and b ~= 15 and b ~= 10 then
                        local has_connection = false
                        if node.type == "out" then
                            for dst = 1, 64 do
                                if G.patch[node.id] and G.patch[node.id][dst] and G.patch[node.id][dst].active then has_connection = true; break end
                            end
                        elseif node.type == "in" then
                            for src = 1, 64 do
                                if G.patch[src] and G.patch[src][node.id] and G.patch[src][node.id].active then has_connection = true; break end
                            end
                        end
                        if has_connection then b = math.max(b, 8) end 
                    end
                end
            end
            
            if GridUI.cache[x][y] ~= b then
                g:led(x, y, b)
                GridUI.cache[x][y] = b
            end
        end
    end
    g:refresh()
end

return GridUI
