# Reaper Lua Scripts Project

This project contains standalone REAPER Lua scripts for audio production and editing.

## Development Guidelines
- Each script must be self-contained and not depend on each other
- Use descriptive filenames and clear comment headers
- This is production code: write maintainable code with small, focused functions
- Code should be as succinct, simple, and DRY as possible
- Always check if required objects exist before operating on them
- Use `reaper.Undo_BeginBlock()` and `reaper.Undo_EndBlock()` for undoable operations
- Test scripts manually in REAPER before committing

## Script Actions
- Execute ReaScript: `oscsend localhost 8000 /action s _RS99cfa19d6ca95db4fd14fcff75f330e47aa2696d`
- Reorder Tracks by First Item Timestamp action ID: `_RS99cfa19d6ca95db4fd14fcff75f330e47aa2696d`
- _RS17342a401c9da2f62f40abd6694d5d4fb6ff2676: Script: Convert_Proxies_To_Multitrack.lua
- _RSaf8b92e4c1f687f86dd63cb434d336b33b000829: Script: Reorder_Tracks_By_First_Item_Timestamp.lua