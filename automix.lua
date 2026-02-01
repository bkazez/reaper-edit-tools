-- Automix
-- Solves for optimal fader levels given signal component breakdowns and a target mix.
-- Uses Python for constrained optimization, Lua for REAPER integration.
--
-- Requires: automix_solve.py in the same directory, python3 with numpy/scipy

local DEFAULT_SPEC_FILENAME = "automix_spec.txt"
local TRACK_VOL_PARAM = "D_VOL"

--------------------------------------------------------------------------------
-- Utility functions
--------------------------------------------------------------------------------

local function msg(text)
    reaper.ShowConsoleMsg(text .. "\n")
end

local function getScriptPath()
    local info = debug.getinfo(1, "S")
    local script_path = info.source:match("@(.+[\\/])")
    return script_path or ""
end

local function fileExists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*all")
    f:close()
    return content
end

local function writeFile(path, content)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

local function deleteFile(path)
    os.remove(path)
end

--------------------------------------------------------------------------------
-- JSON parser (minimal, for reading solver output)
--------------------------------------------------------------------------------

local function parseJson(str)
    -- Simple JSON parser for our specific output format
    local pos = 1
    local function skipWhitespace()
        while pos <= #str and str:sub(pos, pos):match("%s") do
            pos = pos + 1
        end
    end

    local function parseValue()
        skipWhitespace()
        local c = str:sub(pos, pos)

        if c == '"' then
            -- String
            pos = pos + 1
            local start = pos
            while pos <= #str and str:sub(pos, pos) ~= '"' do
                if str:sub(pos, pos) == '\\' then pos = pos + 1 end
                pos = pos + 1
            end
            local s = str:sub(start, pos - 1)
            pos = pos + 1
            return s
        elseif c == '{' then
            -- Object
            pos = pos + 1
            local obj = {}
            skipWhitespace()
            if str:sub(pos, pos) ~= '}' then
                while true do
                    skipWhitespace()
                    local key = parseValue()
                    skipWhitespace()
                    pos = pos + 1  -- skip ':'
                    local value = parseValue()
                    obj[key] = value
                    skipWhitespace()
                    if str:sub(pos, pos) == '}' then break end
                    pos = pos + 1  -- skip ','
                end
            end
            pos = pos + 1  -- skip '}'
            return obj
        elseif c == '[' then
            -- Array
            pos = pos + 1
            local arr = {}
            skipWhitespace()
            if str:sub(pos, pos) ~= ']' then
                while true do
                    arr[#arr + 1] = parseValue()
                    skipWhitespace()
                    if str:sub(pos, pos) == ']' then break end
                    pos = pos + 1  -- skip ','
                end
            end
            pos = pos + 1  -- skip ']'
            return arr
        elseif c == 't' then
            pos = pos + 4
            return true
        elseif c == 'f' then
            pos = pos + 5
            return false
        elseif c == 'n' then
            pos = pos + 4
            return nil
        else
            -- Number
            local start = pos
            while pos <= #str and str:sub(pos, pos):match("[%d%.eE%+%-]") do
                pos = pos + 1
            end
            return tonumber(str:sub(start, pos - 1))
        end
    end

    return parseValue()
end

--------------------------------------------------------------------------------
-- Track operations
--------------------------------------------------------------------------------

local function normalizeTrackName(name)
    return name:lower():gsub("_", " ")
end

local function getAllTrackNames()
    local names = {}
    local numTracks = reaper.CountTracks(0)
    for i = 0, numTracks - 1 do
        local track = reaper.GetTrack(0, i)
        local _, name = reaper.GetTrackName(track)
        names[#names + 1] = name
    end
    return names
end

local function findTrackByName(name)
    local numTracks = reaper.CountTracks(0)
    local nameNorm = normalizeTrackName(name)

    for i = 0, numTracks - 1 do
        local track = reaper.GetTrack(0, i)
        local _, trackName = reaper.GetTrackName(track)
        if normalizeTrackName(trackName) == nameNorm then
            return track
        end
    end
    return nil
end

local function setTrackVolume(track, linearVol)
    reaper.SetMediaTrackInfo_Value(track, TRACK_VOL_PARAM, linearVol)
end

local function promptForSpecFile(projectPath)
    local defaultPath = projectPath .. "/" .. DEFAULT_SPEC_FILENAME
    local retval, selectedPath = reaper.GetUserFileNameForRead(
        defaultPath,
        "Select Automix Spec File",
        "*.txt"
    )
    if not retval then
        return nil  -- user cancelled
    end
    return selectedPath
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local function main()
    local projectPath = reaper.GetProjectPath("")
    if projectPath == "" then
        reaper.ShowMessageBox("Please save your project first.", "Automix", 0)
        return
    end

    local scriptPath = getScriptPath()
    local solverPath = scriptPath .. "automix_solve.py"

    -- Prompt user to select spec file
    local specPath = promptForSpecFile(projectPath)
    if not specPath then
        return  -- user cancelled
    end

    -- Check file exists
    if not fileExists(specPath) then
        reaper.ShowMessageBox(
            "Spec file not found: " .. specPath,
            "Automix", 0)
        return
    end

    if not fileExists(solverPath) then
        reaper.ShowMessageBox(
            "Solver not found: " .. solverPath,
            "Automix", 0)
        return
    end

    msg("\n=== Automix ===")
    msg("Spec: " .. specPath)

    -- Write track list to temp file
    local trackListPath = os.tmpname()
    local trackNames = getAllTrackNames()
    writeFile(trackListPath, table.concat(trackNames, "\n"))

    -- Run Python solver
    local outputPath = os.tmpname()
    local errorPath = os.tmpname()
    local pythonPath = "/opt/homebrew/bin/python3"
    local cmd = string.format('"%s" "%s" "%s" "%s" "%s" 2>"%s"',
        pythonPath, solverPath, specPath, trackListPath, outputPath, errorPath)

    msg("Running solver...")
    msg("Command: " .. cmd)
    local exitCode = os.execute(cmd)

    -- Clean up track list
    deleteFile(trackListPath)

    -- Check for errors
    local errorOutput = readFile(errorPath)
    deleteFile(errorPath)
    if errorOutput and errorOutput ~= "" then
        msg("Python error: " .. errorOutput)
    end

    -- Read result
    local resultJson = readFile(outputPath)
    deleteFile(outputPath)

    if not resultJson then
        msg("ERROR: Solver failed to produce output")
        if exitCode then
            msg("Exit code: " .. tostring(exitCode))
        end
        return
    end

    msg("Solver output: " .. resultJson:sub(1, 200) .. "...")

    local result = parseJson(resultJson)
    if not result then
        msg("ERROR: Failed to parse solver output")
        msg("Raw JSON: " .. resultJson)
        return
    end

    if not result.success then
        msg("\nWARNING: Target mix not achievable!")

        -- Build alert message showing what changed
        local alertLines = {"Target mix not achievable.", "", "To fix, change these target values:"}
        if result.achieved_mix then
            for name, data in pairs(result.achieved_mix) do
                local diff = data.diff or 0
                if math.abs(diff) > 0.005 then
                    -- Parse component name (e.g., "pno_early" -> instrument "pno", type "early")
                    local instr, compType = name:match("^(%w+)_(%w+)$")
                    if instr and compType then
                        local suggestion
                        if diff > 0 then
                            suggestion = "increase"
                        else
                            suggestion = "decrease"
                        end
                        table.insert(alertLines, string.format(
                            "  %s %s: %s to at least %.0f%%",
                            instr, compType, suggestion,
                            (data.achieved or 0) * 100
                        ))
                        table.insert(alertLines, string.format(
                            "    (you set %.0f%%, minimum achievable is %.0f%%)",
                            (data.target or 0) * 100,
                            (data.achieved or 0) * 100
                        ))
                    end
                end
            end
        end

        reaper.ShowMessageBox(table.concat(alertLines, "\n"), "Automix", 0)

        if result.error_message then
            msg(result.error_message)
        end
        msg("\nApplying best approximation anyway...\n")
    end

    -- Display analysis
    if result.analysis then
        msg("\n" .. result.analysis)
    end

    -- Display info
    msg("\nInstruments: " .. table.concat(result.instruments or {}, ", "))
    msg("Components: " .. table.concat(result.components or {}, ", "))

    -- Display target
    msg("\nTarget mix:")
    if result.achieved_mix then
        for name, data in pairs(result.achieved_mix) do
            msg(string.format("  %s: %.1f%%", name, (data.target or 0) * 100))
        end
    end

    -- Apply fader levels
    msg("\nSolution:")
    local totalHall = 0

    reaper.Undo_BeginBlock()

    if result.levels then
        for name, data in pairs(result.levels) do
            local level = data.linear or 0
            local db = data.db or -150
            local hallMarker = data.is_hall and " [hall]" or ""

            if data.is_hall then
                totalHall = totalHall + level
            end

            msg(string.format("  %s: %.4f (%.1f dB)%s", name, level, db, hallMarker))

            local track = findTrackByName(name)
            if track then
                setTrackVolume(track, level)
                msg("    -> Applied")
            else
                msg("    -> Track not found!")
            end
        end
    end

    reaper.Undo_EndBlock("Automix: Set levels", -1)

    msg(string.format("\nTotal artificial reverb: %.4f (%.1f%%)", totalHall, totalHall * 100))

    -- Display achieved mix
    msg("\nAchieved mix:")
    if result.achieved_mix then
        for name, data in pairs(result.achieved_mix) do
            msg(string.format("  %s: %.1f%% (target: %.1f%%, diff: %+.2f%%)",
                name,
                (data.achieved or 0) * 100,
                (data.target or 0) * 100,
                (data.diff or 0) * 100))
        end
    end

    msg("\nDone.")
end

main()
