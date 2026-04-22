# tiaopen-mcp

MCP server that exposes TIA Portal Openness as Copilot tools — create, write, compile, and inspect PLC blocks without leaving VS Code.

## Requirements

- TIA Portal V20 Update 4 with a project open in the UI
- Node.js 18+

## Setup

```bash
npm install
```

Add to `.vscode/mcp.json` (already included in this repo):

```json
{
  "servers": {
    "tiaopen": {
      "type": "stdio",
      "command": "node",
      "args": ["${workspaceFolder}/src/index.js"]
    }
  }
}
```

Restart the MCP server after any change to `src/`.

## Tools

| Tool | Description |
|------|-------------|
| `list_blocks` | List all PLC blocks |
| `get_block_xml` | Export a block as XML |
| `build_lad_block` | Generate and import a LAD FB/FC/OB from a JSON flow description |
| `write_block` | Import a raw XML file into TIA |
| `delete_item` | Delete any named item: block (FB/FC/OB/DB), UDT, or data type |
| `compile` | Compile all PLC blocks and return per-block errors with network paths |
| `create_global_db` | Create an empty global DB |
| `create_instance_db` | Create an instance DB for a user FB |
| `list_templates` | List available XML templates |
| `get_template_xml` | Inspect a raw template |
| `create_tag_table` | Create a PLC tag table |
| `add_tag` | Add a tag to a tag table |
| `save_project` | Save the currently open TIA Portal project to disk |
| `list_tags` | List tags in a tag table |

## Notes

- LAD blocks use `Scope="LocalVariable"` for FB static members and `Scope="GlobalVariable"` for global tags/DBs.
- TON timers inside FBs should use `TON_TIME` static members (multi-instance), not external DBs.
- Scripts in `scripts/` are called via PowerShell by the MCP server and require TIA Portal to be running.
