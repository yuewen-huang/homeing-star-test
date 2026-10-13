local input_path = app.params["input"]
local output_path = app.params["output"]

if not input_path or not output_path then
  error("Expected -script-param input=... and output=...")
end

local sprite = app.open(input_path)
if not sprite then
  error("Could not open input sprite sheet: " .. input_path)
end

if sprite.colorMode == ColorMode.INDEXED then
  app.command.ChangePixelFormat { format="rgb" }
end

local function rgba(r, g, b, a)
  return app.pixelColor.rgba(r, g, b, a or 255)
end

-- Exact source-palette substitutions. Pixel positions and alpha are untouched.
local palette = {
  [rgba(178, 178, 255)] = rgba(226, 220, 202), -- cape light
  [rgba(156, 160, 250)] = rgba(197, 198, 184), -- cape mid
  [rgba(173,  95, 173)] = rgba(151, 157, 151), -- cape shadow

  [rgba(  3,  33, 188)] = rgba( 30,  91,  94), -- teal cloth
  [rgba( 28,  21,  77)] = rgba( 30,  57,  60), -- deep teal
  [rgba( 64,  34,  95)] = rgba( 43,  70,  70), -- teal shadow
  [rgba( 47,  24,  80)] = rgba( 35,  55,  57), -- dark teal
  [rgba( 21,  16,  55)] = rgba( 24,  38,  40), -- outline

  [rgba(255, 255, 255)] = rgba(246, 218, 158), -- long-hair light
  [rgba(255, 255, 204)] = rgba(238, 199, 128), -- long-hair mid
  [rgba(169, 110, 103)] = rgba(184, 133,  74), -- long-hair/fur shadow
  [rgba(255, 140,  94)] = rgba(224, 181, 102), -- pale-gold fur

  [rgba(136,  35,  35)] = rgba(112,  52,  36), -- leather
  [rgba( 88,   3,   3)] = rgba( 63,  31,  25), -- leather dark
  [rgba(140,  35,   9)] = rgba(127,  57,  34), -- leather red-brown
  [rgba(166,  75,  10)] = rgba(155,  83,  42), -- leather mid
  [rgba(255,  14,   0)] = rgba(181,  67,  40), -- leather highlight
  [rgba(224,  94,  43)] = rgba(194,  98,  50), -- warm highlight
  [rgba( 77,  47,  30)] = rgba( 58,  43,  34), -- leather outline

  [rgba(255, 163,   3)] = rgba(204, 147,  52), -- antique brass
  [rgba(151, 192, 255)] = rgba( 66, 210, 216), -- cyan glow
}

local function rgb_key(pixel)
  return string.format(
    "%d,%d,%d",
    app.pixelColor.rgbaR(pixel),
    app.pixelColor.rgbaG(pixel),
    app.pixelColor.rgbaB(pixel))
end

local palette_by_rgb = {}
for source, replacement in pairs(palette) do
  palette_by_rgb[rgb_key(source)] = replacement
end

print("Lan palette script colorMode=" .. tostring(sprite.colorMode))
print("White replacement=" .. tostring(palette_by_rgb["255,255,255"]))
for probe in sprite.cels[1].image:pixels() do
  local value = probe()
  if app.pixelColor.rgbaA(value) > 0 then
    print("First opaque pixel=" .. rgb_key(value) .. ", raw=" .. tostring(value))
    break
  end
end

local changed = 0
app.transaction("Lan palette conversion", function()
  local image = sprite.cels[1].image
  for pixel in image:pixels() do
    local old = pixel()
    local replacement = palette_by_rgb[rgb_key(old)]
    if replacement then
      pixel(replacement)
      changed = changed + 1
    end
  end
end)
print("Changed pixels=" .. tostring(changed))

sprite:saveCopyAs(output_path)
sprite:close()
