--[[
  Proximity Mirror v2.3 — Assetto Corsa / Custom Shaders Patch Lua app

  Draws the game's own virtual rear-view mirror (ui.drawVirtualMirror, as in
  the "AC Virtual Mirror" in-game app) inside a movable, resizable window.
  The draw is wrapped in ui.beginTonemapping()/endTonemapping(), which is what
  fixes the washed-out colours with Pure. The mirror phases in as other cars
  get close and phases out as they drop away; hovering can fade it too.

  Settings: cog button in the window header, or hover the window and press
  "Settings" to switch the window itself to the settings view.
]]

local sim = ac.getSim()
ac.log('Proximity Mirror v2.3: script loaded')

-- ---------------------------------------------------------------------------
-- Settings (persisted automatically)
-- ---------------------------------------------------------------------------
local DEFAULTS = {
  -- Visibility
  alwaysShow   = false, -- mirror always visible
  distance     = 40,    -- mirror starts fading in at this distance (m)
  fullPercent  = 50,    -- fully visible within this % of the distance
  rearOnly     = true,  -- only cars behind you count
  holdTime     = 1.0,   -- seconds to linger after the last car leaves range
  fadeIn       = 0.6,   -- seconds, smoothing when appearing
  fadeOut      = 1.4,   -- seconds, smoothing when disappearing
  -- Mouse hover: 0 = nothing, 1 = fade mirror IN, 2 = fade mirror OUT
  hoverMode    = 1,
  hoverFade    = 0.2,
  -- Look
  opacity      = 1.0,
  keepAspect   = true,  -- the mirror image is 4:1; letterbox it inside the window
  colorScheme  = 'Default',
  -- Tonemapping for Pure (values from Peter Boese's Pure fix):
  --   ui.endTonemapping(whiteRefPoint^0.125 * 1.7, 4.8, true)
  tmUseWrp     = true,  -- exposure = whiteReferencePoint^0.125 * tmScale
  tmScale      = 1.7,
  tmSecond     = 4.8,   -- 2nd value passed to endTonemapping
  showFrame    = true,
  showDistance = false,
}
local settings = ac.storage(DEFAULTS)

-- Colour schemes (from the reference app; mainly useful with Pure).
-- bg = backdrop behind the mirror, fg = tint multiplied onto the mirror.
local colorSchemes = {
  Default              = { bg = { 0, 0, 0, 1 },    fg = { 1, 1, 1, 1 } },
  Light                = { bg = { 0, 0, 0, 1 },    fg = { 0.8, 0.8, 0.8, 1 } },
  LightTransparent     = { bg = { 0, 0, 0, 0.3 },  fg = { 1, 1, 1, 0.8 } },
  LightMoreTransparent = { bg = { 0, 0, 0, 0.25 }, fg = { 1, 1, 1, 0.6 } },
  Inverted             = { bg = { 1, 1, 1, 1 },    fg = { 0, 0, 0, 1 } },
  DarkTransparent      = { bg = { 1, 1, 1, 0.6 },  fg = { 0, 0, 0, 0.7 } },
  DarkerTransparent    = { bg = { 1, 1, 1, 0.6 },  fg = { 0, 0, 0, 0.8 } },
}
local schemeOrder = { 'Default', 'Light', 'LightTransparent', 'LightMoreTransparent',
                      'Inverted', 'DarkTransparent', 'DarkerTransparent' }

local MIRROR_ASPECT = 4 -- width : height of the virtual mirror image

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function clamp01(x) return math.min(math.max(x, 0), 1) end

local function smoothstep(e0, e1, x)
  local t = clamp01((x - e0) / (e1 - e0))
  return t * t * (3 - 2 * t)
end

local function lag(current, target, tau, dt)
  return current + (target - current) * (1 - math.exp(-dt / math.max(tau, 0.01)))
end

local function getFocusedCar()
  return ac.getCar(math.max(sim.focusedCar, 0))
end

-- ---------------------------------------------------------------------------
-- Proximity -> gradual opacity
-- ---------------------------------------------------------------------------
local alpha, hoverAlpha = 0, 0
local nearest = math.huge
local lastTarget, holdLeft = 0, 0

local function scan(dt)
  local me = getFocusedCar()
  if not me then return end

  nearest = math.huge
  for i = 0, sim.carsCount - 1 do
    if i ~= me.index then
      local other = ac.getCar(i)
      if other and other.isConnected then
        local rel = other.position - me.position
        local d = rel:length()
        local counts = not (settings.rearOnly and rel:dot(me.look) > 0)
        if counts and d < nearest then nearest = d end
      end
    end
  end

  -- 0 at `distance`, 1 at `distance * fullPercent`, smooth in between.
  local target = 0
  if settings.alwaysShow then
    target = 1
  elseif nearest < math.huge then
    local startD = math.max(settings.distance, 1)
    local fullD = startD * clamp01(settings.fullPercent / 100)
    target = 1 - smoothstep(fullD, startD, nearest)
  end

  -- Linger briefly instead of dropping out the moment a car leaves range.
  if target > 0 then
    lastTarget = target
    holdLeft = settings.holdTime
  elseif holdLeft > 0 then
    holdLeft = holdLeft - dt
    target = lastTarget
  end

  -- Exponential smoothing = gradual phase in / out.
  alpha = lag(alpha, target, target > alpha and settings.fadeIn or settings.fadeOut, dt)
  if alpha < 0.003 and target == 0 then alpha = 0 end
end

local function currentAlpha()
  local mode = math.floor(settings.hoverMode + 0.5)
  local a = alpha
  if mode == 1 then a = math.max(a, hoverAlpha)            -- hover reveals mirror
  elseif mode == 2 then a = a * (1 - 0.8 * hoverAlpha) end -- hover fades mirror out
  return a * settings.opacity
end

-- ---------------------------------------------------------------------------
-- Mirror drawing
-- ---------------------------------------------------------------------------
local lastError, drawCount = '', 0

local function drawMirror(p1, p2, a)
  local scheme = colorSchemes[settings.colorScheme] or colorSchemes.Default
  local bg = rgbm(scheme.bg[1], scheme.bg[2], scheme.bg[3], scheme.bg[4] * a)
  local fg = rgbm(scheme.fg[1], scheme.fg[2], scheme.fg[3], scheme.fg[4] * a)

  -- Tonemapping around the draw is the fix for washed-out colours with Pure.
  ui.beginTonemapping()
  ui.drawRectFilled(p1, p2, bg)
  local ok, err = pcall(ui.drawVirtualMirror, p1, p2, fg)
  local exposure = settings.tmScale
  if settings.tmUseWrp then
    local okW, wrp = pcall(function() return ac.getSim().whiteReferencePoint end)
    if okW and type(wrp) == 'number' and wrp > 0 then
      exposure = (wrp ^ 0.125) * settings.tmScale
    end
  end
  ui.endTonemapping(exposure, settings.tmSecond, true)

  if not ok then
    if tostring(err) ~= lastError then ac.log('Proximity Mirror: ' .. tostring(err)) end
    lastError = tostring(err)
    return false
  end
  drawCount = drawCount + 1
  return true
end

-- ---------------------------------------------------------------------------
-- Settings UI (shared by the cog window and the in-window settings view)
-- ---------------------------------------------------------------------------
local function slider(label, key, min, max, fmt)
  local value, changed = ui.slider('##' .. key, settings[key], min, max, label .. ': ' .. fmt)
  if changed then settings[key] = value end
end

local function checkbox(label, key)
  if ui.checkbox(label, settings[key]) then settings[key] = not settings[key] end
end

local function radio(label, key, value)
  if ui.radioButton(label, math.floor(settings[key] + 0.5) == value) then settings[key] = value end
end

local function drawSettings()
  ui.text('Visibility')
  checkbox('Always visible', 'alwaysShow')
  slider('Trigger distance', 'distance', 5, 200, '%.0f m')
  slider('Fully visible within', 'fullPercent', 10, 100, '%.0f %% of distance')
  checkbox('Only cars behind me', 'rearOnly')
  slider('Linger time', 'holdTime', 0, 10, '%.1f s')
  slider('Fade-in smoothing', 'fadeIn', 0.05, 3, '%.2f s')
  slider('Fade-out smoothing', 'fadeOut', 0.05, 5, '%.2f s')

  ui.separator()
  ui.text('When mouse is over the mirror')
  radio('Fade in', 'hoverMode', 1)
  ui.sameLine()
  radio('Fade out', 'hoverMode', 2)
  ui.sameLine()
  radio('Nothing', 'hoverMode', 0)
  slider('Hover fade speed', 'hoverFade', 0.05, 1, '%.2f s')

  ui.separator()
  ui.text('Look')
  slider('Opacity', 'opacity', 0.1, 1, '%.2f')
  checkbox('Keep 4:1 mirror shape (letterbox)', 'keepAspect')
  checkbox('Frame', 'showFrame')
  checkbox('Show distance to nearest car', 'showDistance')
  ui.text('Color scheme (for Pure)')
  for _, name in ipairs(schemeOrder) do
    if ui.radioButton(name, settings.colorScheme == name) then settings.colorScheme = name end
  end

  ui.separator()
  ui.text('Tonemapping (Pure fix; defaults 1.7 / 4.8)')
  checkbox('Scale exposure with white reference point', 'tmUseWrp')
  slider('Exposure scale', 'tmScale', 0.5, 4, '%.2f')
  slider('Second tonemap value', 'tmSecond', 0, 10, '%.2f')

  ui.separator()
  ui.text('Diagnostics')
  ui.text(string.format('Nearest car: %s', nearest < math.huge and string.format('%.1f m', nearest) or 'none'))
  ui.text(string.format('Opacity: %.2f   Mirror draws: %d', currentAlpha(), drawCount))
  ui.text('White reference point: ' .. tostring(ac.getSim().whiteReferencePoint))
  ui.textWrapped('Last error: ' .. (lastError ~= '' and lastError or 'none'))

  ui.separator()
  if ui.button('Reset to defaults') then
    for k, v in pairs(DEFAULTS) do settings[k] = v end
  end
end

function script.windowSettings(dt)
  drawSettings()
end

-- ---------------------------------------------------------------------------
-- Mirror window
-- ---------------------------------------------------------------------------
local showConfig = false

function script.windowMain(dt)
  local sw, sh = ui.windowWidth(), ui.windowHeight()
  local size = vec2(sw, sh)

  -- In-window settings view (opened with the Settings button on hover).
  if showConfig then
    ui.drawRectFilled(vec2(0, 0), size, rgbm(0.07, 0.07, 0.07, 0.95))
    if ui.button('Back to mirror') then showConfig = false end
    ui.separator()
    drawSettings()
    return
  end

  -- Hover handling runs every frame, even while the mirror is invisible.
  local mode = math.floor(settings.hoverMode + 0.5)
  local hovered = ui.windowHovered()
  local hTarget = (hovered and mode ~= 0) and 1 or 0
  hoverAlpha = lag(hoverAlpha, hTarget, settings.hoverFade, dt)
  if hTarget == 0 and hoverAlpha < 0.003 then hoverAlpha = 0 end

  local a = currentAlpha()
  -- cameraMode < 3 = in-car style cameras only (same guard as the reference app).
  if a > 0.003 and sw >= 40 and sh >= 40 and ac.getSim().cameraMode < 3 then
    local p1, p2 = vec2(0, 0), size
    if settings.keepAspect then
      local bw, bh = sh * MIRROR_ASPECT, sh
      if bw > sw then bw, bh = sw, sw / MIRROR_ASPECT end
      p1 = vec2((sw - bw) / 2, (sh - bh) / 2)
      p2 = vec2((sw + bw) / 2, (sh + bh) / 2)
    end

    if drawMirror(p1, p2, a) then
      if settings.showFrame then
        pcall(ui.drawRect, p1, p2, rgbm(0.04, 0.04, 0.04, a), 0, nil, 4)
        pcall(ui.drawRect, p1, p2, rgbm(0.6, 0.6, 0.6, a * 0.5), 0, nil, 1)
      end
      if settings.showDistance and nearest < math.huge then
        ui.drawText(string.format('%.0f m', nearest), p1 + vec2(12, 8), rgbm(1, 1, 1, a))
      end
    else
      ui.drawRectFilled(vec2(0, 0), size, rgbm(0.1, 0, 0, a * 0.8))
      ui.drawText('Virtual mirror unavailable - see Settings', vec2(10, 10), rgbm(1, 0.5, 0.5, a))
    end
  end

  -- Settings button, only while the mouse is over the window.
  if hovered then
    ui.setCursorPos(vec2(math.max(sw - 80, 4), 6))
    if ui.button('Settings') then showConfig = true end
  end
end

-- ---------------------------------------------------------------------------
-- Per-frame update (defined last so every local above is in scope)
-- ---------------------------------------------------------------------------
function script.update(dt)
  scan(dt)
end
