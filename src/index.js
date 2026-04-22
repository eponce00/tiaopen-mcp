// index.js — TIA Portal Openness MCP server (stdio transport)
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import { TOOLS } from './tools.js';

const server = new McpServer({
  name: 'tiaopen-mcp',
  version: '0.1.0',
});

// ── explicit zod schemas per tool ────────────────────────────────────────────

const schemas = {
  list_blocks: {
    project_path: z.string().optional().describe(
      'Optional: full path to the .ap20 project file. If omitted, attaches to the already-open TIA project.'),
  },
  list_data_types: {},
  list_groups: {},
  ensure_library_layout: {
    manifest_path: z.string().describe('Absolute path to layout manifest JSON file.'),
    dry_run: z.boolean().optional().default(true).describe('When true, report planned actions without applying changes.'),
  },
  get_block_xml: {
    block_name: z.string().describe('Name of the block to export, e.g. "Main" or "FB_Valve".'),
  },
  write_block: {
    xml_path: z.string().describe('Absolute path to the XML file to import.'),
  },
  write_scl_block: {
    scl_path: z.string().describe('Absolute path to the .scl file to import.'),
  },
  compile: {},
  list_tags: {},
  add_tag: {
    name: z.string().describe('Tag name.'),
    data_type: z.string().describe('TIA data type, e.g. "Bool", "Int", "Real".'),
    address: z.string().optional().describe('Absolute address, e.g. "%M0.0", "%MW10". Leave empty for unassigned.'),
    table: z.string().optional().describe('Name of the tag table. Defaults to the first table.'),
  },
  new_block: {
    template: z.string().describe(
      'Template path as returned by list_templates, e.g. "lad/contact-coil" or "scl/fc-skeleton".'),
    params: z.record(z.string()).describe(
      'PowerShell param names → values. BlockName is required. See tool description for all valid keys.'),
  },
  list_templates: {},
  delete_block: {
    block_name: z.string().describe('Name of the block to delete, e.g. "FC_Old".'),
  },
  preview_block: {
    template: z.string().describe('Template path, e.g. "lad/contact-coil".'),
    params: z.record(z.string()).describe('Same params as new_block. BlockName is required.'),
  },
  get_template_xml: {
    template: z.string().describe('Template path, e.g. "lad/contact-coil" or "scl/fc-skeleton".'),
  },
  create_tag_table: {
    table_name: z.string().describe('Name of the new tag table, e.g. "Conveyor_Tags".'),
  },
  create_global_db: {
    db_name:   z.string().describe('Name for the new DB, e.g. "Process_DB".'),
    db_number: z.number().int().optional().describe('DB number. Omit or use 0 to auto-assign.'),
  },
  create_instance_db: {
    db_name:   z.string().describe('Name for the new instance DB, e.g. "MyMotor_DB".'),
    fb_name:   z.string().describe('Name of the user FB to instantiate, e.g. "FB_Motor".'),
    db_number: z.number().int().optional().describe('DB number. Omit or use 0 to auto-assign.'),
  },
  lookup_instruction: {
    query: z.string().describe('Instruction name or keyword, e.g. "TON", "MOVE", "CTU", "DataLogCreate".'),
    language: z.enum(['LAD', 'FBD', 'SCL', 'Extended', 'any']).optional().default('any')
      .describe('Filter by programming language. Use "any" for all.'),
    max_results: z.number().int().optional().default(5)
      .describe('Maximum number of results to return.'),
  },
  build_lad_block: {
    name:         z.string().describe('Block name, e.g. "FB_StackLight".'),
    block_number: z.number().int().optional().describe('Block number, e.g. 30.'),
    block_type:   z.enum(['FC','FB','OB']).optional().default('FC').describe('Block type.'),
    networks:     z.array(z.record(z.unknown())).describe('One entry per LAD network.'),
    block_interface: z.object({
      input:  z.array(z.record(z.unknown())).optional(),
      output: z.array(z.record(z.unknown())).optional(),
      inout:  z.array(z.record(z.unknown())).optional(),
      static: z.array(z.record(z.unknown())).optional(),
      temp:   z.array(z.record(z.unknown())).optional(),
    }).optional().describe('Block interface members.'),
  },
  create_group: {
    group_path: z.string().describe('Slash-separated Program Blocks group path, e.g. "Kistler NC" or "bdtronic B1000/Helpers".'),
  },
  create_type_group: {
    group_path: z.string().describe('Slash-separated PLC data types group path, e.g. "Kistler NC".'),
  },
  move_block_to_group: {
    block_name: z.string().describe('Exact block name, e.g. "FB_KistlerNC".'),
    group_path: z.string().describe('Target slash-separated group path, e.g. "Kistler NC".'),
  },
  move_type_to_group: {
    block_name: z.string().describe('Exact PLC data type name, e.g. "UDT_KistlerNC_Cmd".'),
    group_path: z.string().describe('Target PLC data types group path, e.g. "Kistler NC".'),
  },
};

// Register all tools
for (const tool of TOOLS) {
  const schema = schemas[tool.name] ?? {};
  server.tool(tool.name, tool.description, schema, async (params) => {
    try {
      const text = await tool.handler(params);
      return { content: [{ type: 'text', text }] };
    } catch (err) {
      return { content: [{ type: 'text', text: `Error: ${err.message}` }], isError: true };
    }
  });
}

// Start
const transport = new StdioServerTransport();
await server.connect(transport);
