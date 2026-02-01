-- Automix: Set Spec File
-- Sets the spec file path for the Automix script.
-- The path is stored in project metadata and persists with the project.

local DEFAULT_SPEC_FILENAME = "automix_spec.txt"
local EXT_STATE_SECTION = "Automix"
local EXT_STATE_KEY_SPEC_PATH = "SpecPath"

local function msg(text)
    reaper.ShowConsoleMsg(text .. "\n")
end

local function getStoredSpecPath()
    local retval, path = reaper.GetProjExtState(0, EXT_STATE_SECTION, EXT_STATE_KEY_SPEC_PATH)
    if retval > 0 and path ~= "" then
        return path
    end
    return nil
end

local function setStoredSpecPath(path)
    reaper.SetProjExtState(0, EXT_STATE_SECTION, EXT_STATE_KEY_SPEC_PATH, path)
end

local function main()
    local projectPath = reaper.GetProjectPath("")
    if projectPath == "" then
        reaper.ShowMessageBox("Please save your project first.", "Automix", 0)
        return
    end

    -- Show current spec if set
    local currentPath = getStoredSpecPath()
    if currentPath then
        msg("Current automix spec: " .. currentPath)
    end

    -- Prompt for new spec file
    local defaultPath = currentPath or (projectPath .. "/" .. DEFAULT_SPEC_FILENAME)
    local retval, selectedPath = reaper.GetUserFileNameForRead(
        defaultPath,
        "Select Automix Spec File",
        "*.txt"
    )

    if not retval then
        return  -- user cancelled
    end

    setStoredSpecPath(selectedPath)
    reaper.MarkProjectDirty(0)
    msg("Automix spec set to: " .. selectedPath)
end

main()
