# scripts/

Exported copies of every script in the Breakaway Studio place. **Roblox Studio is the source of truth.** Edit scripts in Studio, then re-export here after big changes (at minimum, at the end of every milestone) and commit.

Edits made directly to files in this folder do **not** flow back into Studio.

## Layout

Folders mirror the Studio hierarchy, starting at the service:

```
scripts/
  ReplicatedStorage/
    Config.luau                       ModuleScript
    Simulation/                       ModuleScript with children
      init.luau                       the Simulation module itself
      SkaterSim.luau
      ServerLoader.server.luau        Script
      ClientLoader.client.luau        LocalScript
  ServerScriptService/
    PlayerSetup.server.luau
  StarterPlayer/
    StarterPlayerScripts/
      CameraController.client.luau
```

| Studio class | File name |
|---|---|
| `Script` (RunContext Legacy or Server) | `Name.server.luau` |
| `Script` with RunContext = Client | `Name.client.luau` (e.g. `Simulation/ClientLoader`, which must run from ReplicatedStorage) |
| `LocalScript` | `Name.client.luau` |
| `ModuleScript` | `Name.luau` |
| Any script that has children | a folder `Name/` with the script itself in `init.luau` / `init.server.luau` / `init.client.luau` |

Non-script containers (Folders, Models) become plain folders. These names follow Rojo's conventions, so moving to Rojo later wouldn't require renaming anything.

Scripts under `Workspace` (if any) export to `scripts/Workspace/...` the same way. Default CoreGui/Roblox-inserted scripts are not exported.

## How to re-export

Ask Claude to "re-export scripts". Claude reads every `LuaSourceContainer` in the place through the Studio MCP server, rewrites this folder to match (including deleting files for scripts removed in Studio), and shows the diff before committing.
