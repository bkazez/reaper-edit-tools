-- Binary Volume Search
-- Zero in on the ideal track volume using binary search.
--
-- Workflow:
-- 1. Select a track
-- 2. Run script
-- 3. Volume is set to midpoint of range (-60 to +12 dB)
-- 4. Press Up (louder) or Down (softer) to narrow the range
-- 5. Press Enter to accept, Esc to cancel (restores original volume)

-- Constants
local MIN_RANGE_DB = 0.5
local LOW_DB = -60.0
local HIGH_DB = 12.0
local KEY_UP = 30064
local KEY_DOWN = 1685026670
local KEY_ENTER = 13
local KEY_ESCAPE = 27
local WINDOW_W = 320
local WINDOW_H = 200
local SCRIPT_NAME = "Binary Volume Search"

-- State
local track = nil
local track_name = ""
local original_db = 0
local low_db = LOW_DB
local high_db = HIGH_DB
local current_db = 0
local iteration = 0
local is_running = true

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function dbToLinear(db)
    return 10 ^ (db / 20)
end

local function linearToDb(lin)
    if lin <= 0 then return LOW_DB end
    return 20 * math.log(lin, 10)
end

local function setTrackVolumeDb(db)
    reaper.SetMediaTrackInfo_Value(track, "D_VOL", dbToLinear(db))
end

local function getTrackVolumeDb()
    return linearToDb(reaper.GetMediaTrackInfo_Value(track, "D_VOL"))
end

local function applyMidpoint()
    current_db = (low_db + high_db) / 2
    setTrackVolumeDb(current_db)
end

---------------------------------------------------------------------------
-- Binary Search Logic
---------------------------------------------------------------------------

local function stepSearch(want_louder)
    if want_louder then
        low_db = current_db
    else
        high_db = current_db
    end

    iteration = iteration + 1
    applyMidpoint()

    reaper.ShowConsoleMsg(string.format("Step %d: %.1f dB (range: %.1f dB)\n",
        iteration, current_db, high_db - low_db))
end

local function accept()
    reaper.Undo_BeginBlock()
    setTrackVolumeDb(current_db)
    reaper.Undo_EndBlock(SCRIPT_NAME .. ": set volume", -1)

    reaper.ShowConsoleMsg(string.format("\nAccepted: %.1f dB\n", current_db))
    is_running = false
end

local function cancel()
    setTrackVolumeDb(original_db)
    reaper.ShowConsoleMsg("\nCancelled. Restored original volume.\n")
    is_running = false
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function dbToFraction(db)
    return (db - LOW_DB) / (HIGH_DB - LOW_DB)
end

local function drawUI()
    gfx.clear = 0x1a1a1a

    gfx.set(0.7, 0.7, 0.7)
    gfx.x = 10; gfx.y = 10
    gfx.drawstr(track_name)

    gfx.set(1, 1, 1)
    gfx.x = 10; gfx.y = 35
    gfx.drawstr(string.format("Volume: %.1f dB", current_db))

    gfx.x = 10; gfx.y = 60
    gfx.drawstr(string.format("Step %d", iteration))

    -- Range bar
    local bar_x = 10
    local bar_y = 90
    local bar_w = WINDOW_W - 20
    local bar_h = 20

    gfx.set(0.3, 0.3, 0.3)
    gfx.rect(bar_x, bar_y, bar_w, bar_h, true)

    gfx.set(0.2, 0.5, 0.8)
    local lo_frac = dbToFraction(low_db)
    local hi_frac = dbToFraction(high_db)
    gfx.rect(bar_x + lo_frac * bar_w, bar_y, (hi_frac - lo_frac) * bar_w, bar_h, true)

    gfx.set(1, 1, 0)
    local cur_frac = dbToFraction(current_db)
    gfx.rect(bar_x + cur_frac * bar_w - 1, bar_y - 3, 3, bar_h + 6, true)

    gfx.set(0.6, 0.6, 0.6)
    gfx.x = 10; gfx.y = 120
    gfx.drawstr(string.format("Range: %.1f dB", high_db - low_db))

    gfx.set(0.5, 0.5, 0.5)
    gfx.x = 10; gfx.y = 150
    gfx.drawstr("Up = louder  |  Down = softer")
    gfx.x = 10; gfx.y = 170
    gfx.drawstr("Enter = accept  |  Esc = cancel")

    gfx.update()
end

---------------------------------------------------------------------------
-- Main Loop
---------------------------------------------------------------------------

local function update()
    if not is_running then
        gfx.quit()
        return
    end

    local char = gfx.getchar()

    if char == -1 then
        cancel()
        return
    end

    if char == KEY_ESCAPE then
        cancel()
        gfx.quit()
        return
    end

    if char == KEY_ENTER then
        accept()
        gfx.quit()
        return
    end

    if high_db - low_db > MIN_RANGE_DB then
        if char == KEY_UP then
            stepSearch(true)
        elseif char == KEY_DOWN then
            stepSearch(false)
        end
    else
        if char == KEY_UP or char == KEY_DOWN then
            reaper.ShowConsoleMsg("Range is narrow enough. Press Enter to accept.\n")
        end
    end

    drawUI()
    reaper.defer(update)
end

---------------------------------------------------------------------------
-- Entry
---------------------------------------------------------------------------

track = reaper.GetSelectedTrack(0, 0)
if not track then
    reaper.ShowMessageBox("Select a track first.", SCRIPT_NAME, 0)
    return
end

local _, name = reaper.GetTrackName(track)
track_name = name
original_db = getTrackVolumeDb()

reaper.ClearConsole()
reaper.ShowConsoleMsg("=== " .. SCRIPT_NAME .. " ===\n")
reaper.ShowConsoleMsg("Track: " .. track_name .. "\n")
reaper.ShowConsoleMsg(string.format("Original: %.1f dB\n", original_db))
reaper.ShowConsoleMsg("\nUp = louder, Down = softer, Enter = accept, Esc = cancel\n\n")

iteration = 1
applyMidpoint()

gfx.init(SCRIPT_NAME, WINDOW_W, WINDOW_H)
drawUI()
reaper.defer(update)
