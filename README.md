# Transport Fever 2 GIS Exporter

Experimental Lua mod for exporting entities from a loaded Transport Fever 2
save. Published by Artistkisa under the MIT License.

## Status

Development snapshot, not a stable release. Earlier runs exported towns,
station groups, lines, vehicles, network nodes and edges, and citizen records.
Recent coroutine-based versions have caused severe simulation stalls, audio
stuttering and game exits. The precise crash cause has not been isolated.
Syntax validation alone does not establish runtime safety or data completeness.

## Installation and output

Copy mod.lua and res/ into a local mod directory named codex_save_gis_export_1.
Both game scripts currently use USERPROFILE/VSC/transport-fever-2-save-analysis/export/
as the output directory. Create it first or edit outputRoot in both scripts.
Enable Save GIS Exporter when loading a disposable copy of a save.
Exports are automatically triggered by simulation updates, so pausing prevents
update-driven export from progressing. Disable the mod and reload to stop it.

save_gis_export.lua attempts one full export; dynamic_snapshot.lua writes a
snapshot every 120 simulation updates. No save files or player data are shipped.

## Data limitations

- Entity counts and errors: 0 do not prove that exported fields are complete.
- Some userdata values are currently serialized as memory-address strings;
  these cannot be used as stable IDs or joined across records.
- Platform-to-line mappings and platform waiting counts remain unverified.
  Station-group service lists are not individual platform assignments.
- Emission export currently contains grid metadata, not emission intensity values.
- Terrain/water records require decoding and geometry validation; contours are
  not yet generated. Track speed/type fields may be absent.
- Network endpoints alone do not represent curved track geometry or train routes.
- Categories exported on different updates are not an atomic simulation snapshot.
- Files are overwritten during export; an old summary can coexist with partial
  or empty new files. Preserve previous exports separately before a new run.

## Development

Lua syntax can be checked using npx --yes luaparse -q followed by a script path.
Future work includes bounded per-update batches, stable structured IDs, verified
terminal mappings, emission values, terrain decoding and transactional output.
