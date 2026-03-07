-- elianne.lua v0.520
-- CHANGELOG v0.520:
-- 1. REFACTOR: Topología Split TX/RX con DMZ implementada.
-- 2. FIX: Lectura de vúmetros adaptada a arrays concatenados (tx ++ rx) con offset matemático.

engine.name = 'Elianne'

print("========================================")
print("ELIANNE DEBUG: INICIANDO CARGA DE MÓDULOS v0.520")
print("========================================")

local G, GridUI, ScreenUI, Matrix, Params, Storage, Sixteen

local function load_dependencies()
    G = include('lib/globals')
    GridUI = include('lib/grid_ui')
    ScreenUI = include('lib/screen_ui')
    Matrix = include('lib/matrix')
    Params = include('lib/params_setup')
    Storage = include('lib/storage')
    Sixteen = include('lib/16n')
end

load_dependencies()

g = grid.connect()

local grid_metro
local screen_metro

osc.event = function(path, args, from)
    if path == '/elianne_levels' then
        if not G or not G.nodes then return end
        for i = 1, 64 do
            local node = G.nodes[i]
            if node then
                if node.type == "out" then
                    -- args[1] es nodeID, args[2] es replyID. Valores empiezan en args[3].
                    -- tx_idx empieza en 3 (DMZ). SC index es tx_idx - 1.
                    -- Fórmula: 2 + tx_idx
                    G.node_levels[i] = args[2 + node.tx_idx] or 0
                elseif node.type == "in" then
                    -- rx_idx empieza en 3. SC index es rx_idx - 1.
                    -- Array RX empieza después de 36 elementos TX.
                    -- Fórmula: 2 + 36 + rx_idx
                    G.node_levels[i] = args[38 + node.rx_idx] or 0
                end
            end
        end
        G.screen_dirty = true
    end
end

function init()
    G.booting = true
    pcall(G.init_nodes)
    pcall(Params.init, G)
    
    params.action_write = function(filename, name, number) Storage.save(G, number) end
    params.action_read = function(filename, silent, number) Storage.load(G, number) end
    
    params:default()
    pcall(Matrix.init, G)
    pcall(GridUI.init, G)
    
    grid_metro = metro.init()
    grid_metro.time = 1/30
    grid_metro.event = function() GridUI.redraw(G, g) end
    grid_metro:start()
    
    screen_metro = metro.init()
    screen_metro.time = 1/15
    screen_metro.event = function() 
        if G.screen_dirty then redraw(); G.screen_dirty = false end
    end
    screen_metro:start()
    
    Sixteen.init(function(msg)
        if G.booting then return end
        if G.morph_percent and G.morph_percent >= 0 and G.morph_percent < 100 then return end

        local slider_id = Sixteen.cc_2_slider_id(msg.cc)
        if not slider_id then return end

        local raw_val = msg.val
        local val = raw_val / 127 

        if not G.fader_last_param then G.fader_last_param = {} end
        if not G.fader_last_raw then G.fader_last_raw = {} end
        if not G.fine_link then G.fine_link = {["m1_tune"] = "m1_fine", ["m2_tune"] = "m2_fine",["m3_tune1"] = "m3_fine1", ["m3_tune2"] = "m3_fine2", ["m6_cutoff"] = "m6_fine",["m7_cutoff"] = "m7_fine"} end

        local now = util.time()
        if now - (G.fader_last_move[slider_id] or 0) > 0.2 then G.fader_move_start[slider_id] = now end
        G.fader_last_move[slider_id] = now
        local wake_ui = (now - G.fader_move_start[slider_id]) >= 0.05

        if G.learn_mode then
            if G.last_touched_param then
                G.fader_map[slider_id] = G.last_touched_param
                local p_name = G.last_touched_param
                local p = params.lookup[G.last_touched_param]
                if p then p_name = params.params[p].name end
                
                if wake_ui then
                    G.ui_text_state.text = "MAPPED: F" .. slider_id .. " -> " .. string.sub(p_name, 1, 10)
                    G.ui_text_state.level = 15
                    G.ui_text_state.timer = util.time() + 1.5
                    G.ui_text_state.is_fader = true
                    G.screen_dirty = true
                end
            end
        end

        local param_id = G.fader_map[slider_id]
        if param_id and params.lookup[param_id] then
            if G.shift_held then
                if G.fine_link[param_id] then
                    param_id = G.fine_link[param_id]
                else
                    local raw_delta = raw_val - (G.fader_last_raw[slider_id] or raw_val)
                    if raw_delta ~= 0 then
                        local dir = raw_delta > 0 and 1 or -1
                        params:delta(param_id, dir)
                        if wake_ui and not G.learn_mode then
                            local p_name = params.params[params.lookup[param_id]].name
                            G.ui_text_state.text = "[F" .. slider_id .. "] " .. string.sub(p_name, 1, 10) .. " ~ " .. params:string(param_id)
                            G.ui_text_state.level = 15
                            G.ui_text_state.timer = util.time() + 1.0
                            G.ui_text_state.is_fader = true
                            G.screen_dirty = true
                        end
                    end
                    G.fader_last_raw[slider_id] = raw_val
                    return 
                end
            end

            local param_changed = (G.fader_last_param[slider_id] ~= param_id)
            G.fader_last_param[slider_id] = param_id

            if param_changed then
                if G.learn_mode then G.fader_latched[slider_id] = true else G.fader_latched[slider_id] = false end
            end

            local current_val = params:get_raw(param_id)
            local p_name = params.params[params.lookup[param_id]].name
            local short_name = string.sub(p_name, 1, 10)

            if not G.fader_latched[slider_id] then
                if math.abs(val - current_val) < 0.05 then
                    G.fader_latched[slider_id] = true
                else
                    if wake_ui then
                        if val < current_val then G.ui_text_state.text = "[F" .. slider_id .. "] " .. short_name .. " >>>"
                        else G.ui_text_state.text = "<<< " .. short_name .. "[F" .. slider_id .. "]" end
                        G.ui_text_state.level = 15
                        G.ui_text_state.timer = util.time() + 1.0
                        G.ui_text_state.is_fader = true
                        G.screen_dirty = true
                    end
                    G.fader_last_raw[slider_id] = raw_val
                    return
                end
            end

            if G.fader_latched[slider_id] then
                params:set_raw(param_id, val)
                if wake_ui and not G.learn_mode then
                    G.ui_text_state.text = "[F" .. slider_id .. "] " .. short_name .. ": " .. params:string(param_id)
                    G.ui_text_state.level = 15
                    G.ui_text_state.timer = util.time() + 1.0
                    G.ui_text_state.is_fader = true
                    G.screen_dirty = true
                end
            end
        end
        G.fader_last_raw[slider_id] = raw_val
    end)
    
    params:bang()
    G.booting = false
    print("ELIANNE DEBUG: BOOT COMPLETADO")
end

function enc(n, d) ScreenUI.enc(G, n, d); G.screen_dirty = true end
function key(n, z) ScreenUI.key(G, n, z); G.screen_dirty = true end
g.key = function(x, y, z) GridUI.key(G, g, x, y, z) end
function redraw() screen.clear(); ScreenUI.draw(G); screen.update() end
function cleanup() if grid_metro then grid_metro:stop() end; if screen_metro then screen_metro:stop() end end
