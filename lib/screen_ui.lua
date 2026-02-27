-- lib/screen_ui.lua
-- Motor de Renderizado OLED y Menús Contextuales

local ScreenUI = {}

-- Función auxiliar para mapear Grid (X,Y) a Pantalla (Px, Py)
local function grid_to_screen(x, y)
    local px = (x - 1) * 8 + 4
    local py = (y - 1) * 8 + 4
    return px, py
end

function ScreenUI.draw_idle(G)
    -- Dibujar Minimapa del Grid (Estilo granchild / o-o-o)
    screen.aa(1) -- Activar Anti-aliasing para los cables
    
    -- 1. Dibujar Cables Activos
    screen.level(10)
    for src_id, dests in pairs(G.patch) do
        for dst_id, data in pairs(dests) do
            if data.active then
                local src_node = G.nodes[src_id]
                local dst_node = G.nodes[dst_id]
                local sx1, sy1 = grid_to_screen(src_node.x, src_node.y)
                local sx2, sy2 = grid_to_screen(dst_node.x, dst_node.y)
                
                -- Dibujar línea curva simple (Bezier cuadrática simulada)
                screen.move(sx1, sy1)
                -- Curva hacia abajo para simular gravedad
                local cx = (sx1 + sx2) / 2
                local cy = math.max(sy1, sy2) + 10 
                screen.curve(sx1, sy1, cx, cy, sx2, sy2)
                screen.stroke()
            end
        end
    end
    
    screen.aa(0) -- Desactivar AA para los cuadrados del Grid
    
    -- 2. Dibujar Nodos del Grid
    for x = 1, 16 do
        for y = 1, 8 do
            local node = G.grid_map[x][y]
            local is_menu = (y == 4)
            if node or is_menu then
                local px, py = grid_to_screen(x, y)
                local module_idx = math.ceil(x / 2)
                local is_even = (module_idx % 2 == 0)
                
                screen.level(is_even and 4 or 2)
                screen.rect(px - 2, py - 2, 4, 4)
                screen.fill()
            end
        end
    end
    
    -- 3. Info de Sistema
    screen.level(15)
    screen.move(2, 62)
    screen.text("ELIANNE")
    screen.move(126, 62)
    screen.text_right("IDLE")
end

function ScreenUI.draw_node_menu(G)
    local node = G.grid_map[G.focus.node_x][G.focus.node_y]
    if not node then return end
    
    screen.level(15)
    screen.move(64, 10)
    screen.text_center(node.name)
    
    screen.level(4)
    screen.move(64, 20)
    screen.text_center(node.type == "in" and "INPUT ATTENUVERTER" or "OUTPUT LEVEL")
    
    -- Dibujar UI del Attenuverter
    screen.level(15)
    screen.rect(14, 30, 100, 10)
    screen.stroke()
    
    -- Centro (Cero)
    screen.level(4)
    screen.move(64, 30)
    screen.line(64, 40)
    screen.stroke()
    
    -- Barra de Nivel
    screen.level(15)
    local val_px = node.level * 50
    if node.level > 0 then
        screen.rect(64, 32, val_px, 6)
    else
        screen.rect(64 + val_px, 32, math.abs(val_px), 6)
    end
    screen.fill()
    
    screen.move(10, 55)
    screen.text("E2: LEVEL/PHASE")
    
    if node.module == 8 and node.type == "in" then
        screen.move(118, 55)
        screen.text_right("E3: PAN")
    end
end

function ScreenUI.draw(G)
    if G.focus.state == "idle" or G.focus.state == "patching" then
        ScreenUI.draw_idle(G)
    elseif G.focus.state == "in" or G.focus.state == "out" then
        ScreenUI.draw_node_menu(G)
    elseif G.focus.state == "menu" then
        -- Aquí implementaremos el renderizado de los menús de los 8 módulos (Fase 2)
        screen.level(15)
        screen.move(64, 32)
        screen.text_center("MODULE " .. G.focus.module_id .. " - PAGE " .. G.focus.page)
    end
end

function ScreenUI.enc(G, n, d)
    if G.focus.state == "in" or G.focus.state == "out" then
        local node = G.grid_map[G.focus.node_x][G.focus.node_y]
        if n == 2 then
            node.level = util.clamp(node.level + (d * 0.05), -1.0, 1.0)
        elseif n == 3 and node.module == 8 and node.type == "in" then
            node.pan = util.clamp(node.pan + (d * 0.05), -1.0, 1.0)
        end
    end
end

function ScreenUI.key(G, n, z)
    -- Lógica de botones de Norns (K2/K3)
end

return ScreenUI
