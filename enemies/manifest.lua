-- enemies/manifest.lua (OPTIONAL)
-- Put this file inside your game folder at: enemies/manifest.lua
-- It lets you override how each sheet is cut.
--
-- Supported fields per file:
--   cols, rows            : grid size
--   frameW, frameH        : override frame size (defaults to imageW/cols, imageH/rows)
--   marginX, marginY      : pixels to skip before first frame
--   spacingX, spacingY    : pixels between frames
--   walkFrames            : how many columns to animate (defaults to cols)
--   fps                   : animation speed
--   rowMap                : mapping for rows (0-based): down/left/right/up
--   radius, scale, speed  : optional tuning
--
-- Example:
-- return {
--   ["my_demon_8x8_128.png"] = { cols=8, rows=8, fps=10, walkFrames=8 },
--   ["boss_blob_5x6.png"]    = { cols=5, rows=6, rowMap={down=0,left=1,right=2,up=3}, fps=6, scale=1.6 },
-- }

return {
  -- ["PUT_YOUR_FILENAME.png"] = { cols=8, rows=8, fps=9 },
}
return {
  defaults = { fps = 8, scale = 1.0 },

  files = {
    -- 12-panel montages (4x3). innerPad trims the dark gutter/border inside each panel.
    ["12 grids 1.png"] = { montage={cols=4, rows=3, innerPad=28}, sheet={cols=8, rows=8}, fps=8 },
    ["12 grids 2.png"] = { montage={cols=4, rows=3, innerPad=28}, sheet={cols=8, rows=8}, fps=8 },
    ["12 grids 3.png"] = { montage={cols=4, rows=3, innerPad=28}, sheet={cols=8, rows=8}, fps=8 },
    ["12 grids 4.png"] = { montage={cols=4, rows=3, innerPad=28}, sheet={cols=8, rows=8}, fps=8 },
    ["12 grids 5.png"] = { montage={cols=4, rows=3, innerPad=28}, sheet={cols=8, rows=8}, fps=8 },
    ["12 grids 6.png"] = { montage={cols=4, rows=3, innerPad=28}, sheet={cols=8, rows=8}, fps=8 },
    ["12 grids 7.png"] = { montage={cols=4, rows=3, innerPad=28}, sheet={cols=8, rows=8}, fps=8 },
    ["12 grids 8.png"] = { montage={cols=4, rows=3, innerPad=28}, sheet={cols=8, rows=8}, fps=8 },

    -- Single sheets (rectangular). Set cols/rows per file.
    ["1 rect 1.png"] = { cols=8, rows=6, fps=8, scale=1.0 },
    ["1 rect 2.png"] = { cols=8, rows=6, fps=8, scale=1.0 },
    ["1 rect 3.png"] = { cols=8, rows=6, fps=8, scale=1.0 },
    ["1 rect 4.png"] = { cols=8, rows=6, fps=8, scale=1.0 },
    ["1 rect 5.png"] = { cols=8, rows=6, fps=8, scale=1.0 },
    ["1 rect 6.png"] = { cols=8, rows=6, fps=8, scale=1.0 },

    ["sample creature w detail.png"] = { cols=8, rows=8, fps=8, scale=1.0 },
    ["sample creature blurr.png"]     = { cols=8, rows=8, fps=8, scale=1.0 },
  }
}