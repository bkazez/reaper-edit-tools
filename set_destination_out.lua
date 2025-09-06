-- reaper-edit-tools
-- Set Destination OUT: Places a destination OUT marker at current cursor/play position
-- Author: Ben Kazez
-- GitHub: https://github.com/bkazez/reaper-edit-tools

local script_path = debug.getinfo(1, "S").source:match("@(.*)[\\/][^\\/]*$")
if script_path then
    package.path = package.path .. ";" .. script_path .. "/?.lua"
end

local common = require("source_destination_common")

function main()
    Undo_BeginBlock()
    
    local cur_pos = common.get_current_position()
    local track_num = common.get_selected_track_number()
    local marker_name = common.make_marker_name(track_num, common.DEST_OUT)
    
    if cur_pos ~= -1 then
        common.clear_existing_markers_of_type(common.DEST_OUT)
        AddProjectMarker2(0, false, cur_pos, 0, marker_name, -1, common.DEST_COLOR)
        UpdateArrange()
    end
    
    Undo_EndBlock("Set Destination OUT", 0)
end

main()