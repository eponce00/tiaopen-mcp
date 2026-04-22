// tools.js — MCP tool definitions and handlers
import { readFileSync, writeFileSync, readdirSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { runPs } from './ps-runner.js';

const PKG_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

// Paths are relative to package root; override with env vars if needed
const SCRIPTS = process.env.TIA_SCRIPTS_DIR
  || join(PKG_ROOT, 'scripts');

const TEMPLATES = process.env.TIA_TEMPLATES_DIR
  || join(PKG_ROOT, 'templates');

const INSTRUCTIONS_JSON = process.env.TIA_INSTRUCTIONS_JSON
  || join(PKG_ROOT, 'data', 'tia-v20-instructions.json');

let _instrIndex = null;
function getInstrIndex() {
  if (!_instrIndex) {
    const data = JSON.parse(readFileSync(INSTRUCTIONS_JSON, 'utf8'));
    // Flatten to array for search
    _instrIndex = data.sections.flatMap((s) =>
      s.instructions.map((i) => ({ ...i, language: s.label }))
    );
  }
  return _instrIndex;
}

// ─── template helpers ────────────────────────────────────────────────────────

/** Recursively list all .xml files under a directory, returning relative posix paths without extension. */
function walkTemplates(dir, base = dir) {
  const results = [];
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, e.name);
    if (e.isDirectory()) results.push(...walkTemplates(full, base));
    else if (e.name.endsWith('.xml')) {
      const rel = full.slice(base.length + 1).replace(/\\/g, '/').replace(/\.xml$/, '');
      results.push({ name: rel, path: full });
    }
  }
  return results;
}

/** Extract Purpose and token placeholder names from the XML comment header. */
function parseTemplateComment(xmlPath) {
  const lines = readFileSync(xmlPath, 'utf8').split('\n').slice(0, 40);
  let purpose = '';
  const tokens = [];
  let inTokens = false;
  for (const line of lines) {
    if (!purpose) {
      const m = line.match(/Purpose\s*:\s*(.+)/);
      if (m) purpose = m[1].trim();
    }
    if (/TOKENS/.test(line)) { inTokens = true; continue; }
    if (inTokens) {
      const m = line.match(/\{\{([A-Z_]+)\}\}/);
      if (m) tokens.push(m[1]);
      if (/^\s*--/.test(line) && tokens.length > 0) break;
    }
  }
  return { purpose, tokens };
}

// ─── hint helpers ───────────────────────────────────────────────────────────

const HINT_COMPILE = `
---
⚡ NEXT STEP: Call \`compile\` now to verify the whole project builds clean after this change.`;

const HINT_SCL_XML = `
---
📖 SCL StructuredText XML rules (TIA V20):
- Use individual elements per token — NOT a single Token element with multi-line text.
- Keywords/operators: <Token Text="IF"/>, <Token Text=":="/>, <Token Text="&lt;"/>, <Token Text="&gt;"/>
- Variables: <Access Scope="LocalVariable"><Symbol><Component Name="VarName"/></Symbol></Access>
- Global tags: same but Scope="GlobalVariable" and add <BooleanAttribute Name="HasQuotes">true</BooleanAttribute>
- Literals: <Access Scope="LiteralConstant"><Constant><ConstantValue>TRUE</ConstantValue></Constant></Access>
- Spacing: <Blank Num="1"/>, indentation: <Blank Num="4"/>, line breaks: <NewLine Num="1"/>
- SCL comments (// text) are NOT supported as Token elements — omit them.
- FB formal param names (IN, PT, etc.) inside calls are NOT supported as Token elements — use empty call "DB_Name"() instead.
- Namespace: xmlns="http://www.siemens.com/automation/Openness/SW/NetworkSource/StructuredText/v4"
- Use lookup_instruction to find correct instruction names and parameters.

⚠️  SCL RESERVED KEYWORDS — NEVER use these as variable, struct-member, UDT field, or tag names.
    Doing so causes "Invalid tag definition" / "Identifier expected" compile errors with no clear message.
    Control flow : IF THEN ELSIF ELSE END_IF CASE OF END_CASE FOR TO BY DO END_FOR WHILE END_WHILE
                   REPEAT UNTIL END_REPEAT CONTINUE EXIT RETURN GOTO JMP JMPC JMPN
    Block types   : FUNCTION FUNCTION_BLOCK ORGANIZATION_BLOCK END_FUNCTION END_FUNCTION_BLOCK
                   END_ORGANIZATION_BLOCK TYPE END_TYPE STRUCT END_STRUCT VAR VAR_INPUT VAR_OUTPUT
                   VAR_IN_OUT VAR_TEMP VAR_STAT END_VAR BEGIN
    Operators     : AND OR XOR NOT MOD DIV
    Literals/types: TRUE FALSE NULL
    Data types    : BOOL BYTE WORD DWORD LWORD INT DINT LINT UINT UDINT ULINT SINT USINT REAL LREAL
                   TIME LTIME DATE TIME_OF_DAY TOD DATE_AND_TIME DT CHAR WCHAR STRING WSTRING
                   ARRAY OF AT
    System/misc   : WITH BY PROGRAM CONFIGURATION RESOURCE TASK RETAIN NON_RETAIN CONSTANT
                   EN ENO VOID ANY POINTER REF NULL
    Practical safe alternatives when a name collides:
      Continue  → ContWait  |  Exit → ExitFlag  |  Return → RetVal
      State     → fine (not reserved, widely used)
      Access    → fine (not reserved, widely used)
      Type      → avoid — use Kind, Category, or prefix with block name (e.g. MpType)`;

const HINT_LAD_XML = `
---
📖 LAD FlgNet XML rules (TIA V20):
- BitOffset is total bits from area start: %I0.0=0, %I0.1=1, %I0.2=2, %I1.0=8, %I1.3=11, etc.
- Normally Closed contact: Part Name="Contact" with child <Negated Name="operand"/>
- OR gate: Part Name="O" (NOT "Or") — requires <TemplateValue Name="Card" Type="Cardinality">2</TemplateValue>
- Set coil: Part Name="SCoil" | Reset coil: Part Name="RCoil" | Normal coil: Part Name="Coil"
- Powerrail can connect to multiple contacts in one Wire element (branch from rail)
- TON timer DB must pre-exist before write_block import — create it first via new_block ton-timer
- XML comments (<!-- -->) are NOT allowed inside <ObjectList> — TIA rejects them as schema violations
- Each <Access Scope="Address"> holds exactly ONE <Address> child element
- Namespace: xmlns="http://www.siemens.com/automation/Openness/SW/NetworkSource/FlgNet/v5"`;

/** Append a hint string to a JSON result string. */
function withHint(jsonStr, hint) {
  return jsonStr + hint;
}

/** Return the right error hint based on programming language. */
function errorHint(language) {
  if (language === 'SCL') return HINT_SCL_XML;
  if (language === 'LAD' || language === 'FBD') return HINT_LAD_XML;
  // Both hints when language unknown
  return HINT_SCL_XML + HINT_LAD_XML;
}

/** If runPs threw but the payload contains compile JSON (Imported:true), extract it. */
function tryParseCompileError(err) {
  const m = err.message.match(/\{[\s\S]*\}/);
  if (!m) return null;
  try {
    const r = JSON.parse(m[0]);
    if (r?.Imported !== undefined) return r;
  } catch {}
  return null;
}

// ─── LAD XML generator ───────────────────────────────────────────────────────

/**
 * Parse "%I0.2", "%Q1.0", "%M3.5", "%MW10", "%IW4" → { Area, Type, BitOffset }
 * Bool BitOffset = byte*8 + bit.  Word/DWord BitOffset = byte*8.
 */
function parseAddress(addr) {
  const boolM = addr.match(/^%([IQM])(\d+)\.([0-7])$/);
  if (boolM) {
    const areaMap = { I: 'Input', Q: 'Output', M: 'Bit memory' };
    return { Area: areaMap[boolM[1]], Type: 'Bool', BitOffset: String(parseInt(boolM[2]) * 8 + parseInt(boolM[3])) };
  }
  const wordM = addr.match(/^%([IQM])(DW|D|W)(\d+)$/i);
  if (wordM) {
    const areaMap = { I: 'Input', Q: 'Output', M: 'Bit memory' };
    const typeMap = { W: 'Word', D: 'DWord', DW: 'DWord' };
    return { Area: areaMap[wordM[1].toUpperCase()], Type: typeMap[wordM[2].toUpperCase()], BitOffset: String(parseInt(wordM[3]) * 8) };
  }
  throw new Error(`Unrecognized address format: "${addr}". Use %I0.0, %Q1.2, %M3.4, %MW10, etc.`);
}

function escXml(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

/**
 * Emit an <Access> element for a pin value.
 * value can be:
 *   "%I0.0" style string        → Scope="Address" with <Address>
 *   { addr: "%M0.0" }           → same
 *   { literal: "T#5S" }         → Scope="LiteralConstant"
 *   { local: "VarName" }        → Scope="LocalVariable"
 *   { global: "TagName" }       → Scope="GlobalVariable"
 *   null / undefined            → returns null (caller emits OpenCon)
 */
function emitAccess(value, uid) {
  if (value == null) return null;
  const addr = typeof value === 'string' ? value : value.addr;
  if (addr) {
    const { Area, Type, BitOffset } = parseAddress(addr);
    return `<Access Scope="Address" UId="${uid}"><Address Area="${Area}" Type="${Type}" BitOffset="${BitOffset}"/></Access>`;
  }
  if (value.literal != null) {
    return `<Access Scope="LiteralConstant" UId="${uid}"><Constant><ConstantValue>${escXml(value.literal)}</ConstantValue></Constant></Access>`;
  }
  if (value.typed != null) {
    // TypedConstant: for IEC time literals like T#500ms, T#5s
    return `<Access Scope="TypedConstant" UId="${uid}"><Constant><ConstantValue>${escXml(value.typed)}</ConstantValue></Constant></Access>`;
  }
  if (value.local) {
    // Support dot-path for nested members, e.g. "Timer_Slow.Q" → two Components
    const components = value.local.split('.').map(n => `<Component Name="${escXml(n)}"/>`).join('');
    return `<Access Scope="LocalVariable" UId="${uid}"><Symbol>${components}</Symbol></Access>`;
  }
  if (value.global) {
    const components = value.global.split('.').map(n => `<Component Name="${escXml(n)}"/>`).join('');
    return `<Access Scope="GlobalVariable" UId="${uid}"><Symbol>${components}</Symbol></Access>`;
  }
  throw new Error(`Unrecognized pin value: ${JSON.stringify(value)}`);
}

/**
 * Recursively emit LAD flow elements into parts[] and wires[].
 *
 * Flow element types:
 *
 *   { type: "contact", addr, negated? }
 *     Series contact. Power in→out. addr wired to operand.
 *
 *   { type: "coil", addr, coil_type? }
 *     Output coil (Coil/SCoil/RCoil). Power in (terminal). addr→operand.
 *
 *   { type: "parallel", branches: Array<flow[]> }
 *     Parallel OR block. Each branch is a flow array that starts from powerrail.
 *     Branches OR'd through an O gate. Power out from OR gate.
 *     Note: for "contact before parallel block" pattern, put the contact in EACH branch.
 *
 *   { type: "part", name, template_values?, in_pin?, out_pin?, pins? }
 *     Arbitrary instruction box. name = TIA Part name e.g. "TON", "MOVE", "CMP_EQ".
 *     in_pin:  power-flow input pin name (default "EN")
 *     out_pin: power-flow output pin name (default "ENO")
 *     template_values: [ { name, value } ] or { name: value }
 *     pins: { pinName: addr_string | {literal/local/global} | null }
 *       null → OpenCon (unconnected output)
 *
 * Returns { outUid, outPin } — where power exits this element (null for coil/terminal).
 * prevUid/prevPin describe the incoming power connection (null → from powerrail).
 */
function emitFlowElements(elements, parts, wires, nextUid, prevUid, prevPin) {
  for (const el of elements) {
    if (el.type === 'contact') {
      const addrUid = nextUid();
      const partUid = nextUid();
      const neg = el.negated ? '<Negated Name="operand"/>' : '';
      parts.push(emitAccess(el.addr, addrUid));
      parts.push(`<Part Name="Contact" UId="${partUid}">${neg}</Part>`);
      if (prevUid == null) {
        wires.push(`<Wire UId="${nextUid()}"><Powerrail/><NameCon UId="${partUid}" Name="in"/></Wire>`);
      } else {
        wires.push(`<Wire UId="${nextUid()}"><NameCon UId="${prevUid}" Name="${prevPin}"/><NameCon UId="${partUid}" Name="in"/></Wire>`);
      }
      wires.push(`<Wire UId="${nextUid()}"><IdentCon UId="${addrUid}"/><NameCon UId="${partUid}" Name="operand"/></Wire>`);
      prevUid = partUid; prevPin = 'out';

    } else if (el.type === 'coil') {
      const addrUid = nextUid();
      const partUid = nextUid();
      const coilName = el.coil_type || 'Coil';
      parts.push(emitAccess(el.addr, addrUid));
      parts.push(`<Part Name="${coilName}" UId="${partUid}"/>`);
      // in_from_prev_pin: connect coil.in from a specific output pin of the previous part
      const inSrcPin = el.in_from_prev_pin ?? prevPin;
      if (prevUid == null && !el.in_from_prev_pin) {
        wires.push(`<Wire UId="${nextUid()}"><Powerrail/><NameCon UId="${partUid}" Name="in"/></Wire>`);
      } else if (prevUid != null) {
        wires.push(`<Wire UId="${nextUid()}"><NameCon UId="${prevUid}" Name="${inSrcPin}"/><NameCon UId="${partUid}" Name="in"/></Wire>`);
      }
      wires.push(`<Wire UId="${nextUid()}"><IdentCon UId="${addrUid}"/><NameCon UId="${partUid}" Name="operand"/></Wire>`);
      prevUid = null; prevPin = null; // coil is terminal

    } else if (el.type === 'parallel') {
      const branches = el.branches;
      const card = branches.length;
      const orUid = nextUid();
      parts.push(`<Part Name="O" UId="${orUid}"><TemplateValue Name="Card" Type="Cardinality">${card}</TemplateValue></Part>`);

      // Process each branch with prevUid=null so first contacts emit powerrail wires.
      // We then collect and merge all those powerrail NameCons into ONE shared wire.
      const allBranchParts = [], nonPowerrailWires = [], powerrailNameCons = [];
      for (let bi = 0; bi < branches.length; bi++) {
        const branchParts = [], branchWires = [];
        const { outUid: bOut, outPin: bPin } = emitFlowElements(branches[bi], branchParts, branchWires, nextUid, null, null);
        allBranchParts.push(...branchParts);
        for (const w of branchWires) {
          // Detect the auto-generated powerrail wire and strip it; collect its NameCon targets
          if (/<Powerrail\s*\/>/.test(w)) {
            const matches = [...w.matchAll(/<NameCon[^>]*\/>/g)];
            powerrailNameCons.push(...matches.map(m => m[0]));
          } else {
            nonPowerrailWires.push(w);
          }
        }
        if (bOut != null) {
          nonPowerrailWires.push(`<Wire UId="${nextUid()}"><NameCon UId="${bOut}" Name="${bPin}"/><NameCon UId="${orUid}" Name="in${bi + 1}"/></Wire>`);
        }
      }

      // Emit ONE combined upstream wire for all branch first-contacts
      if (powerrailNameCons.length > 0) {
        const source = prevUid == null
          ? '<Powerrail/>'
          : `<NameCon UId="${prevUid}" Name="${prevPin}"/>`;
        wires.push(`<Wire UId="${nextUid()}">${source}${powerrailNameCons.join('')}</Wire>`);
      }
      parts.push(...allBranchParts);
      wires.push(...nonPowerrailWires);
      prevUid = orUid; prevPin = 'out';

    } else if (el.type === 'part') {
      const partUid = nextUid();
      const inPin  = el.in_pin  ?? 'EN';
      const outPin = el.out_pin ?? 'ENO';

      // Instance inside Part — must come BEFORE TemplateValue (TIA schema order)
      // Only GlobalVariable scope is valid; LocalVariable multi-instance is not supported in LAD FlgNet.
      let instanceXml = '';
      if (el.instance && el.instance.global) {
        const instUid = nextUid();
        instanceXml = `<Instance Scope="GlobalVariable" UId="${instUid}"><Component Name="${escXml(el.instance.global)}"/></Instance>`;
      }

      // template values — after Instance, auto-detect Type vs Cardinality
      let tvXml = '';
      if (el.template_values) {
        const tvs = Array.isArray(el.template_values)
          ? el.template_values
          : Object.entries(el.template_values).map(([n,v]) => ({ name: n, value: v }));
        tvXml = tvs.map(tv => {
          const tvType = tv.tv_type ?? (/^(Time|LTime|DInt|Int|UInt|USInt|Real|LReal|Bool)$/.test(String(tv.value)) ? 'Type' : 'Cardinality');
          return `<TemplateValue Name="${escXml(tv.name)}" Type="${tvType}">${escXml(String(tv.value))}</TemplateValue>`;
        }).join('');
      }

      const versionAttr = el.version ? ` Version="${escXml(el.version)}"` : '';
      parts.push(`<Part Name="${escXml(el.name)}"${versionAttr} UId="${partUid}">${instanceXml}${tvXml}</Part>`);

      // power flow in
      if (prevUid == null) {
        wires.push(`<Wire UId="${nextUid()}"><Powerrail/><NameCon UId="${partUid}" Name="${inPin}"/></Wire>`);
      } else {
        wires.push(`<Wire UId="${nextUid()}"><NameCon UId="${prevUid}" Name="${prevPin}"/><NameCon UId="${partUid}" Name="${inPin}"/></Wire>`);
      }

      // data pins
      for (const [pinName, pinVal] of Object.entries(el.pins || {})) {
        if (pinVal === null || pinVal === undefined) {
          // OpenCon for unconnected output pins
          const ocUid = nextUid();
          wires.push(`<Wire UId="${nextUid()}"><NameCon UId="${partUid}" Name="${pinName}"/><OpenCon UId="${ocUid}"/></Wire>`);
        } else {
          const accessUid = nextUid();
          const accessXml = emitAccess(pinVal, accessUid);
          if (accessXml) {
            parts.push(accessXml);
            wires.push(`<Wire UId="${nextUid()}"><IdentCon UId="${accessUid}"/><NameCon UId="${partUid}" Name="${pinName}"/></Wire>`);
          }
        }
      }

      prevUid = partUid; prevPin = outPin;

    } else {
      throw new Error(`Unknown flow element type: "${el.type}". Valid: contact, coil, parallel, part.`);
    }
  }
  return { outUid: prevUid, outPin: prevPin };
}

/**
 * Convert legacy { contacts, or_branches, coil } rung to flow[] format.
 */
function rungToFlow(rung) {
  const flow = [];
  if (rung.or_branches && rung.or_branches.length > 0) {
    flow.push({
      type: 'parallel',
      branches: rung.or_branches.map(branch =>
        branch.map(c => ({ type: 'contact', addr: c.addr, negated: c.negated }))
      ),
    });
  } else {
    for (const c of (rung.contacts || [])) {
      flow.push({ type: 'contact', addr: c.addr, negated: c.negated });
    }
  }
  if (rung.coil) {
    flow.push({ type: 'coil', addr: rung.coil.addr, coil_type: rung.coil.type });
  }
  return flow;
}

/**
 * Build a complete TIA Portal V20 LAD block XML.
 *
 * blockDef.networks[i] can use either:
 *   flow: Array<FlowElement>   — full recursive model (contacts, coils, parallels, parts)
 *   rungs: Array<SimpleRung>   — legacy shorthand (contacts + optional or_branches + coil)
 */
function buildLadXml(blockDef) {
  const { name, number, type = 'FC', networks } = blockDef;
  const blockTag = type === 'FB' ? 'SW.Blocks.FB' : type === 'OB' ? 'SW.Blocks.OB' : 'SW.Blocks.FC';

  let _uid = 100;
  const nextUid = () => String(_uid++);

  const ns = 'http://www.siemens.com/automation/Openness/SW/NetworkSource/FlgNet/v5';

  const networkXmls = (networks || []).map((net, ni) => {
    const cuId = String(200 + ni * 100);
    const titleText  = escXml(net.title   || `Network ${ni + 1}`);
    const commentText = escXml(net.comment || '');

    const parts = [], wires = [];

    // Support "flow", "elements", and legacy "rungs"
    const flowElements = net.flow
      ? net.flow
      : net.elements
      ? net.elements
      : (net.rungs || []).flatMap(rungToFlow);

    emitFlowElements(flowElements, parts, wires, nextUid, null, null);

    return `
      <SW.Blocks.CompileUnit ID="${cuId}" CompositionName="CompileUnits">
        <AttributeList>
          <NetworkSource>
            <FlgNet xmlns="${ns}">
              <Parts>
                ${parts.join('\n                ')}
              </Parts>
              <Wires>
                ${wires.join('\n                ')}
              </Wires>
            </FlgNet>
          </NetworkSource>
          <ProgrammingLanguage>LAD</ProgrammingLanguage>
        </AttributeList>
        <ObjectList>
          <MultilingualText ID="${nextUid()}" CompositionName="Comment">
            <ObjectList>
              <MultilingualTextItem ID="${nextUid()}" CompositionName="Items">
                <AttributeList><Culture>en-US</Culture><Text>${commentText}</Text></AttributeList>
              </MultilingualTextItem>
            </ObjectList>
          </MultilingualText>
          <MultilingualText ID="${nextUid()}" CompositionName="Title">
            <ObjectList>
              <MultilingualTextItem ID="${nextUid()}" CompositionName="Items">
                <AttributeList><Culture>en-US</Culture><Text>${titleText}</Text></AttributeList>
              </MultilingualTextItem>
            </ObjectList>
          </MultilingualText>
        </ObjectList>
      </SW.Blocks.CompileUnit>`;
  });

  const returnSection = type === 'FC' ? `
          <Section Name="Return">
            <Member Name="RET_VAL" Datatype="Void"/>
          </Section>` : '';

  // Build interface sections from optional iface definition
  // iface: { input, output, inout, static, temp } each is [{name, type, comment?}]
  const iface = blockDef.block_interface || blockDef.interface || {};
  function buildSection(sectionName, members) {
    if (!Array.isArray(members) || members.length === 0) return `<Section Name="${sectionName}"/>`;
    const mXml = members.map(m => {
      const commentXml = m.comment
        ? `<Comment><MultiLanguageText Lang="en-US">${escXml(m.comment)}</MultiLanguageText></Comment>`
        : '';
      const startVal = m.startValue ? `<StartValue>${escXml(m.startValue)}</StartValue>` : '';
      const inner = commentXml + startVal;
      return inner
        ? `<Member Name="${escXml(m.name)}" Datatype="${escXml(m.type)}">${inner}</Member>`
        : `<Member Name="${escXml(m.name)}" Datatype="${escXml(m.type)}"/>`;
    }).join('\n            ');
    return `<Section Name="${sectionName}">\n            ${mXml}\n          </Section>`;
  }

  return `<?xml version="1.0" encoding="utf-8"?>
<Document>
  <Engineering version="V20" />
  <${blockTag} ID="0">
    <AttributeList>
      <AutoNumber>false</AutoNumber>
      <Interface>
        <Sections xmlns="http://www.siemens.com/automation/Openness/SW/Interface/v5">
          ${buildSection('Input',  iface.input)}
          ${buildSection('Output', iface.output)}
          ${buildSection('InOut',  iface.inout)}
          ${type === 'FB' ? buildSection('Static', iface.static ?? iface.stat) : ''}
          ${buildSection('Temp',   iface.temp)}${returnSection}
        </Sections>
      </Interface>
      <Name>${name}</Name>
      <Namespace />
      <Number>${number}</Number>
      <ProgrammingLanguage>LAD</ProgrammingLanguage>
    </AttributeList>
    <ObjectList>${networkXmls.join('')}
    </ObjectList>
  </${blockTag}>
</Document>`;
}

// ─── tool definitions ────────────────────────────────────────────────────────

export const TOOLS = [
  {
    name: 'list_blocks',
    description: 'List all PLC blocks (FCs, FBs, OBs, DBs) in the open TIA Portal project. Returns a JSON array with name, type, number, and group path.',
    inputSchema: {
      type: 'object',
      properties: {
        project_path: {
          type: 'string',
          description: 'Optional: full path to the .ap20 project file. If omitted, attaches to the already-open TIA project.',
        },
      },
    },
    handler: async ({ project_path }) => {
      const args = project_path ? ['-ProjectPath', project_path] : [];
      const result = await runPs(join(SCRIPTS, 'get-blocks.ps1'), args);
      return JSON.stringify(result, null, 2);
    },
  },

  {
    name: 'list_data_types',
    description: 'List all PLC data types in the open TIA Portal project. Returns a JSON array with name, type, consistency, and group path.',
    inputSchema: { type: 'object', properties: {} },
    handler: async () => {
      const result = await runPs(join(SCRIPTS, 'get-data-types.ps1'));
      return JSON.stringify(result, null, 2);
    },
  },

  {
    name: 'list_groups',
    description: 'List both group trees in the open TIA Portal project: Program Blocks groups and PLC data types groups.',
    inputSchema: { type: 'object', properties: {} },
    handler: async () => {
      const result = await runPs(join(SCRIPTS, 'get-groups.ps1'));
      return JSON.stringify(result, null, 2);
    },
  },

  {
    name: 'ensure_library_layout',
    description: `Apply a manifest-driven library layout for Program Blocks and PLC data types.

Manifest JSON path is required and uses this shape:
{
  "program_blocks": [
    { "block_name": "FB_KistlerNC", "group_path": "Kistler NC" }
  ],
  "plc_data_types": [
    { "type_name": "UDT_KistlerNC_Cmd", "group_path": "Kistler NC" }
  ]
}

Use dry_run=true first to preview planned moves without changing the project.
Then run with dry_run=false to apply changes.`,
    inputSchema: {
      type: 'object',
      properties: {
        manifest_path: {
          type: 'string',
          description: 'Absolute path to layout manifest JSON file.',
        },
        dry_run: {
          type: 'boolean',
          description: 'When true, only reports planned actions. Default true.',
          default: true,
        },
      },
      required: ['manifest_path'],
    },
    handler: async ({ manifest_path, dry_run = true }) => {
      const args = ['-ManifestPath', manifest_path];
      if (dry_run) args.push('-DryRun');
      const result = await runPs(join(SCRIPTS, 'ensure-library-layout.ps1'), args);
      return JSON.stringify(result, null, 2);
    },
  },

  {
    name: 'get_block_xml',
    description: 'Export a PLC block as raw TIA Portal XML. Use this to read the current logic of any block before editing.',
    inputSchema: {
      type: 'object',
      properties: {
        block_name: { type: 'string', description: 'Name of the block to export (e.g. "Main", "FB_Valve").' },
      },
      required: ['block_name'],
    },
    handler: async ({ block_name }) => {
      const result = await runPs(join(SCRIPTS, 'read-block.ps1'), ['-BlockName', block_name]);
      return typeof result.xml === 'string' ? result.xml : JSON.stringify(result, null, 2);
    },
  },

  {
    name: 'write_block',
    description: 'Import a block XML file into TIA Portal and compile it. The XML file must already exist on disk. Returns compile result including any errors.',
    inputSchema: {
      type: 'object',
      properties: {
        xml_path: { type: 'string', description: 'Absolute path to the XML file to import.' },
      },
      required: ['xml_path'],
    },
    handler: async ({ xml_path }) => {
      // Detect language from XML content for correct error hint
      let lang = 'unknown';
      try {
        const xmlContent = readFileSync(xml_path, 'utf8');
        if (xmlContent.includes('StructuredText')) lang = 'SCL';
        else if (xmlContent.includes('FlgNet')) lang = 'LAD';
      } catch {}
      let result;
      try {
        result = await runPs(join(SCRIPTS, 'write-block.ps1'), ['-XmlPath', xml_path]);
      } catch (err) {
        const r = tryParseCompileError(err);
        if (r) return withHint(JSON.stringify(r, null, 2), errorHint(lang));
        throw err;
      }
      const json = JSON.stringify(result, null, 2);
      const errors = result?.Errors ?? 0;
      return withHint(json, errors > 0 ? errorHint(lang) : `\n---\n✅ Block imported${result?.Compiled ? ' and compiled' : ''}. Call \`compile\` to verify full project consistency.`);
    },
  },

  {
    name: 'write_scl_block',
    description: `Import a plain SCL source file into TIA Portal as an ExternalSource, generate block(s) from it, and compile.

The .scl file must contain a complete IEC 61131-3 block declaration. Example:

  FUNCTION_BLOCK "FB_MyBlock"
  { S7_Optimized_Access := 'TRUE' }
  VAR_INPUT
    Enable : Bool;
  END_VAR
  VAR_OUTPUT
    Done : Bool;
  END_VAR
  VAR
    State : Int;
  END_VAR
  BEGIN
    Done := Enable;
  END_FUNCTION_BLOCK

The file name (without extension) is used as the ExternalSource name in TIA. If a source with that name already exists it is replaced.
Supported block types: FUNCTION_BLOCK, FUNCTION, ORGANIZATION_BLOCK, and TYPE...END_TYPE (UDT).

⚠️  RESERVED KEYWORD RULE — Before writing any SCL, check that NO variable name, struct member, UDT field, or tag
name is an SCL/IEC 61131-3 reserved keyword. Using a reserved word as an identifier causes cryptic
"Invalid tag definition in STRUCT" or "Identifier expected" errors with only a line-number hint.
Common collisions to watch for:
  CONTINUE, EXIT, RETURN  (control flow)
  AND, OR, XOR, NOT, MOD  (operators)
  TYPE, STRUCT, ARRAY, OF, AT  (type system)
  TRUE, FALSE, NULL       (literals)
  IN, OUT, INOUT — also avoid as field names (confusing and sometimes rejected)
Safe renames: Continue->ContWait, Exit->ExitFlag, Type->MpType/Kind

⚠️  ASCII-ONLY RULE — All SCL text (comments, strings, identifiers) must use plain ASCII characters only (code points 0x00-0x7F).
Do NOT use Unicode characters such as:
  — (em-dash U+2014)  → use plain hyphen -
  – (en-dash U+2013)  → use plain hyphen -
  → (right arrow U+2192)  → use ->
  • (bullet U+2022)  → use *
  Any other non-ASCII symbol  → use ASCII equivalent or remove
TIA Portal Openness imports SCL as Windows-1252. Non-ASCII UTF-8 sequences corrupt silently, showing as â€" or â†' in comments inside TIA.`,
    inputSchema: {
      type: 'object',
      properties: {
        scl_path: { type: 'string', description: 'Absolute path to the .scl file to import.' },
      },
      required: ['scl_path'],
    },
    handler: async ({ scl_path }) => {
      let result;
      try {
        result = await runPs(join(SCRIPTS, 'import-scl.ps1'), ['-SclPath', scl_path]);
      } catch (err) {
        const r = tryParseCompileError(err);
        if (r) return withHint(JSON.stringify(r, null, 2), errorHint('SCL'));
        throw err;
      }
      const json = JSON.stringify(result, null, 2);
      const errors = result?.Errors ?? 0;
      return withHint(json, errors > 0 ? errorHint('SCL') : `\n---\n✅ SCL block imported and generated. Call \`compile\` to verify the full project builds clean.`);
    },
  },

  {
    name: 'preflight_scl',
    description: 'Run static checks on an SCL file before import. Detects non-ASCII characters and reserved-keyword identifier collisions.',
    inputSchema: {
      type: 'object',
      properties: {
        scl_path: { type: 'string', description: 'Absolute path to the .scl file to validate.' },
      },
      required: ['scl_path'],
    },
    handler: async ({ scl_path }) => {
      try {
        const result = await runPs(join(SCRIPTS, 'preflight-scl.ps1'), ['-SclPath', scl_path]);
        return JSON.stringify(result, null, 2);
      } catch (err) {
        const m = err.message.match(/\{[\s\S]*\}/);
        if (m) return m[0];
        throw err;
      }
    },
  },

  {
    name: 'create_group',
    description: `Create a group (folder) inside the Program Blocks tree of the open TIA Portal project.
Use "/" to create nested groups in one call, e.g. "bdtronic B1000" or "Kistler NC/Helpers".
If the group (or any parent) already exists it is reused - safe to call repeatedly.
This tool is only for Program Blocks. PLC data types use create_type_group.`,
    inputSchema: {
      type: 'object',
      properties: {
        group_path: {
          type: 'string',
          description: 'Slash-separated group path, e.g. "Kistler NC" or "bdtronic B1000/UDTs".',
        },
      },
      required: ['group_path'],
    },
    handler: async ({ group_path }) => {
      const result = await runPs(join(SCRIPTS, 'manage-block-group.ps1'), [
        '-Action', 'create_block_group',
        '-GroupPath', group_path,
      ]);
      return JSON.stringify(result, null, 2);
    },
  },

  {
    name: 'create_type_group',
    description: `Create a group (folder) inside the PLC data types tree of the open TIA Portal project.
Use "/" to create nested groups in one call, e.g. "Kistler NC" or "bdtronic B1000/Common".
If the group (or any parent) already exists it is reused - safe to call repeatedly.
Use this before calling move_type_to_group for UDTs and other PLC data types.`,
    inputSchema: {
      type: 'object',
      properties: {
        group_path: {
          type: 'string',
          description: 'Slash-separated PLC data types group path, e.g. "Kistler NC".',
        },
      },
      required: ['group_path'],
    },
    handler: async ({ group_path }) => {
      const result = await runPs(join(SCRIPTS, 'manage-block-group.ps1'), [
        '-Action', 'create_type_group',
        '-GroupPath', group_path,
      ]);
      return JSON.stringify(result, null, 2);
    },
  },

  {
    name: 'move_block_to_group',
    description: `Move an existing Program Blocks item into a group folder in the Program Blocks tree.
The target group must exist - call create_group first if needed.
Works with FB, FC, DB, and OB blocks.

Example workflow to organise all Kistler blocks:
  1. create_group("Kistler NC")
  2. move_block_to_group(block_name:"FB_KistlerNC", group_path:"Kistler NC")
  3. move_block_to_group(block_name:"FC_KistlerNC_StatusUnpack", group_path:"Kistler NC")`,
    inputSchema: {
      type: 'object',
      properties: {
        block_name: {
          type: 'string',
          description: 'Exact block name as it appears in TIA Portal, e.g. "FB_KistlerNC".',
        },
        group_path: {
          type: 'string',
          description: 'Target slash-separated group path, e.g. "Kistler NC" or "bdtronic B1000/UDTs".',
        },
      },
      required: ['block_name', 'group_path'],
    },
    handler: async ({ block_name, group_path }) => {
      const result = await runPs(join(SCRIPTS, 'manage-block-group.ps1'), [
        '-Action', 'move_block',
        '-BlockName', block_name,
        '-GroupPath', group_path,
      ]);
      return JSON.stringify(result, null, 2);
    },
  },

  {
    name: 'move_type_to_group',
    description: `Move an existing PLC data type into a group folder in the PLC data types tree.
The target group must exist - call create_type_group first if needed.
Works with UDTs and other PLC data types that live under PLC data types.

Example workflow to organise Kistler PLC data types:
  1. create_type_group("Kistler NC")
  2. move_type_to_group(block_name:"UDT_KistlerNC_Cmd", group_path:"Kistler NC")
  3. move_type_to_group(block_name:"UDT_KistlerNC_Status", group_path:"Kistler NC")`,
    inputSchema: {
      type: 'object',
      properties: {
        block_name: {
          type: 'string',
          description: 'Exact PLC data type name as it appears in TIA Portal, e.g. "UDT_KistlerNC_Cmd".',
        },
        group_path: {
          type: 'string',
          description: 'Target slash-separated PLC data types group path, e.g. "Kistler NC".',
        },
      },
      required: ['block_name', 'group_path'],
    },
    handler: async ({ block_name, group_path }) => {
      const result = await runPs(join(SCRIPTS, 'manage-block-group.ps1'), [
        '-Action', 'move_type',
        '-BlockName', block_name,
        '-GroupPath', group_path,
      ]);
      return JSON.stringify(result, null, 2);
    },
  },

  {
    name: 'compile',
    description: 'Compile the PLC software in the open TIA Portal project. Returns compile state and any error/warning messages.',
    inputSchema: { type: 'object', properties: {} },
    handler: async () => {
      const result = await runPs(join(SCRIPTS, 'compile.ps1'));
      const json = JSON.stringify(result, null, 2);
      const errors = result?.Errors ?? 0;
      const hint = errors > 0
        ? HINT_SCL_XML + HINT_LAD_XML
        : `\n---\n✅ Project compiles clean — no errors, no warnings.`;
      return withHint(json, hint);
    },
  },

  {
    name: 'list_tags',
    description: 'List all PLC tags from all tag tables in the open TIA Portal project. Returns name, data type, address, and table.',
    inputSchema: { type: 'object', properties: {} },
    handler: async () => {
      const result = await runPs(join(SCRIPTS, 'get-tags.ps1'));
      return JSON.stringify(result, null, 2);
    },
  },

  {
    name: 'add_tag',
    description: 'Add a new PLC tag to the default tag table (or a named table) in the open TIA Portal project.',
    inputSchema: {
      type: 'object',
      properties: {
        name: { type: 'string', description: 'Tag name.' },
        data_type: { type: 'string', description: 'TIA data type, e.g. "Bool", "Int", "Real".' },
        address: {
          type: 'string',
          description:
            'Absolute address. IMPORTANT: bit number must be 0–7, never 8 or higher. ' +
            'Examples: "%I0.0"=byte0 bit0, "%Q1.0"=byte1 bit0 (NOT "%Q0.8"), "%MW10"=memory word 10. ' +
            'Formula: address %Xbyte.bit — byte=floor(n/8), bit=n%8. Leave empty for unassigned.',
        },
        table: { type: 'string', description: 'Name of the tag table. Defaults to the default tag table.' },
      },
      required: ['name', 'data_type'],
    },
    handler: async ({ name, data_type, address, table }) => {
      const args = ['-Name', name, '-DataType', data_type];
      if (address) args.push('-Address', address);
      if (table) args.push('-TableName', table);
      const result = await runPs(join(SCRIPTS, 'add-tag.ps1'), args);
      return withHint(JSON.stringify(result, null, 2), HINT_COMPILE);
    },
  },

  {
    name: 'list_templates',
    description:
      'List all available XML block templates. Returns each template name (pass as `template` to new_block), its purpose description, and the token placeholder names it uses. Always call this before new_block to discover what templates exist and which params they need.',
    inputSchema: { type: 'object', properties: {} },
    handler: async () => {
      const files = walkTemplates(TEMPLATES);
      const result = files.map(({ name, path }) => {
        const { purpose, tokens } = parseTemplateComment(path);
        return { template: name, purpose, tokens };
      });
      return JSON.stringify(result, null, 2);
    },
  },

  {
    name: 'new_block',
    description: `Create a new PLC block from a verified XML template, import it into TIA Portal, and compile.

WORKFLOW: Call list_templates first to see available templates and required token names.

PARAMS — pass as the \`params\` object (keys = PowerShell parameter names):

  Required:
    BlockName          – Block name, e.g. "FC_RunMotor"

  Common:
    BlockNumber        – Integer string, e.g. "200"  (default "100")
    BlockType          – "SW.Blocks.FC" | "SW.Blocks.FB" | "SW.Blocks.OB"  (default FC)
    NetworkTitle       – Title for the rung/network

  Input/Output rung (contact-coil, contact-noc-coil, set/reset-coil):
    InputArea / InputBitOffset     – e.g. "Input" / "0"  (%I0.0)
    OutputArea / OutputBitOffset   – e.g. "Output" / "0" (%Q0.0)

  Timer (ton-timer):
    EnableArea / EnableBitOffset, DoneArea / DoneBitOffset
    PresetTime (e.g. "T#5S"), TimerDB (instance DB name)

  Counter (ctu-counter):
    InputArea / InputBitOffset, OutputArea / OutputBitOffset, CounterDB

  Move / Compare (move, compare-eq):
    SrcArea / SrcBitOffset, DstArea / DstBitOffset, DataType

  Parallel-or:
    Input1Area / Input1BitOffset, Input2Area / Input2BitOffset
    OutputArea / OutputBitOffset

  Compare operands (compare-eq):
    In1Area / In1BitOffset / In1Type, In2Area / In2BitOffset / In2Type

  Math / Calculate:
    Input1Area / Input1BitOffset, Input2Area / Input2BitOffset
    OutputArea / OutputBitOffset, DataType
    CalcEquation – e.g. "IN1 + IN2"  (calculate template only)

  Block calls:
    CalleeFc – FC name (fc-call)
    FbName / InstanceDB – FB name + instance DB (fbd/fb-call)

  SCL:
    SclBody – SCL source text (fc-skeleton, fb-skeleton)
    ConditionTag / OutputTag / ThenValue / ElseValue  (fc-if-then)

  Project filter:
    ProjectMatch – substring of TIA project name (default "Testing_Playground")`,

    inputSchema: {
      type: 'object',
      properties: {
        template: {
          type: 'string',
          description: 'Template path as returned by list_templates, e.g. "lad/contact-coil" or "scl/fc-skeleton".',
        },
        params: {
          type: 'object',
          description: 'PowerShell param names → string values. BlockName is required. See tool description for all valid keys.',
          additionalProperties: { type: 'string' },
        },
      },
      required: ['template', 'params'],
    },

    handler: async ({ template, params }) => {
      if (!params?.BlockName) throw new Error('params.BlockName is required.');
      const templatePath = join(TEMPLATES, ...template.split('/')) + '.xml';
      if (!existsSync(templatePath)) {
        throw new Error(`Template not found: ${templatePath}. Call list_templates to see available templates.`);
      }
      const args = ['-Template', templatePath];
      for (const [k, v] of Object.entries(params)) args.push(`-${k}`, v);
      let result;
      try {
        result = await runPs(join(SCRIPTS, 'new-block.ps1'), args);
      } catch (err) {
        const r = tryParseCompileError(err);
        if (r) return withHint(JSON.stringify(r, null, 2), errorHint(params?.ProgrammingLanguage ?? 'unknown'));
        throw err;
      }
      const json = JSON.stringify(result, null, 2);
      const errors = result?.Errors ?? 0;
      return withHint(json, errors > 0 ? errorHint(params?.ProgrammingLanguage ?? 'unknown') : `\n---\n✅ Block created. Call \`compile\` to verify the full project builds clean.`);
    },
  },

  // ── build_lad_block ────────────────────────────────────────────────────────
  {
    name: 'build_lad_block',
    description: `Generate and import a LAD block into TIA Portal from a structured JSON description. No XML required.

Each network has either a "flow" array (full model) or "rungs" array (simple shorthand).

─── FLOW ELEMENTS ────────────────────────────────────────────────────────────

{ type: "contact", addr, negated? }
  Series NO/NC contact. Power flows in → out.
  negated: true = NC contact.

{ type: "coil", addr, coil_type? }
  Output coil. Terminal — power flow ends here.
  coil_type: "Coil" (default) | "SCoil" (set) | "RCoil" (reset)

{ type: "parallel", branches: [ flow[], flow[], ... ] }
  OR block. Each branch is an independent flow array starting from powerrail.
  Branches are merged through an OR gate. Power continues from OR output.
  For "contact before OR block" — include that contact in every branch.

{ type: "part", name, in_pin?, out_pin?, template_values?, pins }
  Arbitrary instruction box (TON, CTU, MOVE, ADD, CMP_EQ, etc.)
  in_pin:  power-flow input pin name (default "EN")
  out_pin: power-flow output pin name (default "ENO")
  template_values: { "pinName": "value" }  — for instructions with cardinality
  pins: { "pinName": addr | {literal} | {local} | {global} | null }
    addr string "%I0.0"        → address access
    { literal: "T#5S" }        → literal constant
    { local: "VarName" }       → local variable
    { global: "TagName" }      → global tag
    null                       → OpenCon (leave output unconnected)

─── ADDRESS FORMAT ────────────────────────────────────────────────────────────
  Bool:        %I0.0, %Q1.3, %M2.4   (bit must be 0-7)
  Word/DWord:  %IW4, %QW0, %MW10, %MD8

─── SIMPLE RUNGS SHORTHAND ────────────────────────────────────────────────────
  rungs: [ { contacts: [{addr, negated?}], or_branches?: [[{addr}]], coil: {addr, type?} } ]

─── EXAMPLES ─────────────────────────────────────────────────────────────────

Simple contact → coil:
  flow: [ {type:"contact", addr:"%I0.0"}, {type:"coil", addr:"%Q0.0"} ]

Two contacts in series (AND):
  flow: [ {type:"contact", addr:"%I0.0"}, {type:"contact", addr:"%I0.1", negated:true}, {type:"coil", addr:"%Q0.0"} ]

TON timer (create instance DB first via create_instance_db or new_block ton-timer template):
  flow: [
    {type:"contact", addr:"%I0.0"},
    {type:"part", name:"TON", pins:{ IN:"%M0.0", PT:{literal:"T#5S"}, Q:"%Q0.1", ET:null }},
  ]

OR parallel block:
  flow: [ {type:"parallel", branches:[ [{type:"contact",addr:"%I0.0"}], [{type:"contact",addr:"%I0.1"}] ]}, {type:"coil",addr:"%Q0.0"} ]`,

    inputSchema: {
      type: 'object',
      properties: {
        name:         { type: 'string',  description: 'Block name, e.g. "FB_StackLight".' },
        block_number: { type: 'integer', description: 'Block number, e.g. 30.' },
        block_type:   { type: 'string',  enum: ['FC','FB','OB'], description: 'Block type. Default FC.' },
        networks: {
          type: 'array',
          description: 'One entry per LAD network.',
          items: {
            type: 'object',
            properties: {
              title:   { type: 'string' },
              comment: { type: 'string' },
              flow: {
                type: 'array',
                description: 'Full recursive flow model. Each element is a contact, coil, parallel block, or instruction part.',
                items: { type: 'object' },
              },
              rungs: {
                type: 'array',
                description: 'Simple shorthand: array of { contacts, or_branches?, coil } rungs.',
                items: { type: 'object' },
              },
            },
          },
        },
        block_interface: {
          type: 'object',
          description: 'Block interface members (inputs, outputs, static vars, etc.). Use {local:"VarName"} in flow pins to reference these.',

          properties: {
            input:  { type: 'array', items: { type: 'object', properties: { name: { type: 'string' }, type: { type: 'string' }, comment: { type: 'string' } }, required: ['name','type'] } },
            output: { type: 'array', items: { type: 'object', properties: { name: { type: 'string' }, type: { type: 'string' }, comment: { type: 'string' } }, required: ['name','type'] } },
            inout:  { type: 'array', items: { type: 'object', properties: { name: { type: 'string' }, type: { type: 'string' }, comment: { type: 'string' } }, required: ['name','type'] } },
            static: { type: 'array', items: { type: 'object', properties: { name: { type: 'string' }, type: { type: 'string' }, comment: { type: 'string' } }, required: ['name','type'] } },
            temp:   { type: 'array', items: { type: 'object', properties: { name: { type: 'string' }, type: { type: 'string' }, comment: { type: 'string' } }, required: ['name','type'] } },
          },
        },
      },
      required: ['name', 'block_number', 'networks'],
    },

    handler: async ({ name, block_number, block_type = 'FC', networks, block_interface }) => {
      let xml;
      try {
        xml = buildLadXml({ name, number: block_number, type: block_type, networks, block_interface });
      } catch (genErr) {
        throw new Error(`LAD generator error: ${genErr.message}`);
      }
      const xmlPath = join(PKG_ROOT, 'tmp', `${name}.xml`);
      writeFileSync(xmlPath, xml, 'utf8');
      let result;
      try {
        result = await runPs(join(SCRIPTS, 'write-block.ps1'), ['-XmlPath', xmlPath]);
      } catch (err) {
        const r = tryParseCompileError(err);
        if (r) return withHint(JSON.stringify(r, null, 2), HINT_LAD_XML);
        throw err;
      }
      const json = JSON.stringify(result, null, 2);
      const errors = result?.Errors ?? 0;
      return withHint(json, errors > 0 ? HINT_LAD_XML : `\n---\n✅ LAD block "${name}" imported${result?.Compiled ? ' and compiled' : ''}. Call \`compile\` to verify full project consistency.`);
    },
  },

  {
    name: 'delete_block',
    description: 'Delete a PLC block by name from the open TIA Portal project. Returns confirmation JSON.',
    inputSchema: {
      type: 'object',
      properties: {
        block_name: { type: 'string', description: 'Name of the block to delete, e.g. "FC_Old".' },
      },
      required: ['block_name'],
    },
    handler: async ({ block_name }) => {
      const result = await runPs(join(SCRIPTS, 'delete-block.ps1'), ['-BlockName', block_name]);
      return JSON.stringify(result, null, 2);
    },
  },

  // ── preview_block ──────────────────────────────────────────────────────────
  {
    name: 'preview_block',
    description:
      'Render a template with params substituted and return the resolved XML — WITHOUT importing into TIA Portal. ' +
      'Use this to verify the generated XML looks correct before calling new_block. ' +
      'Accepts the same `template` and `params` arguments as new_block.',
    inputSchema: {
      type: 'object',
      properties: {
        template: {
          type: 'string',
          description: 'Template path as returned by list_templates, e.g. "lad/contact-coil".',
        },
        params: {
          type: 'object',
          description: 'Same param names as new_block. BlockName is required.',
          additionalProperties: { type: 'string' },
        },
      },
      required: ['template', 'params'],
    },
    handler: async ({ template, params }) => {
      if (!params?.BlockName) throw new Error('params.BlockName is required.');
      const templatePath = join(TEMPLATES, ...template.split('/')) + '.xml';
      if (!existsSync(templatePath)) {
        throw new Error(`Template not found: ${templatePath}. Call list_templates to see available templates.`);
      }
      const args = ['-Template', templatePath, '-DryRun'];
      for (const [k, v] of Object.entries(params)) args.push(`-${k}`, v);
      // DryRun prints raw XML to stdout — ps-runner wraps non-JSON as { raw: "..." }
      const result = await runPs(join(SCRIPTS, 'new-block.ps1'), args);
      return typeof result === 'string' ? result : (result.raw ?? JSON.stringify(result, null, 2));
    },
  },

  // ── get_template_xml ───────────────────────────────────────────────────────
  {
    name: 'get_template_xml',
    description:
      'Return the raw unresolved XML of a template file, including its comment header with token descriptions. ' +
      'Use this to inspect the full wiring topology, namespace requirements, or comment notes before hand-crafting XML.',
    inputSchema: {
      type: 'object',
      properties: {
        template: {
          type: 'string',
          description: 'Template path as returned by list_templates, e.g. "lad/contact-coil" or "scl/fc-skeleton".',
        },
      },
      required: ['template'],
    },
    handler: async ({ template }) => {
      const templatePath = join(TEMPLATES, ...template.split('/')) + '.xml';
      if (!existsSync(templatePath)) {
        throw new Error(`Template not found: ${templatePath}. Call list_templates to see available templates.`);
      }
      return readFileSync(templatePath, 'utf8');
    },
  },

  // ── create_tag_table ───────────────────────────────────────────────────────
  {
    name: 'create_tag_table',
    description:
      'Create a new user-defined PLC tag table in the open TIA Portal project. ' +
      'After creation, use add_tag with the table name to populate it.',
    inputSchema: {
      type: 'object',
      properties: {
        table_name: { type: 'string', description: 'Name of the new tag table, e.g. "Conveyor_Tags".' },
      },
      required: ['table_name'],
    },
    handler: async ({ table_name }) => {
      const result = await runPs(join(SCRIPTS, 'new-tag-table.ps1'), ['-TableName', table_name]);
      return withHint(JSON.stringify(result, null, 2), `\n---\n⚡ Tag table created. Use \`add_tag\` to populate it, then \`compile\` to verify consistency.`);
    },
  },

  // ── create_global_db ───────────────────────────────────────────────────────
  {
    name: 'create_global_db',
    description:
      'Create a new empty global Data Block (DB) in the open TIA Portal project. ' +
      'Use this to hold persistent process data. After creation the DB appears in the block list. ' +
      'Add variables to it using write_block with hand-crafted XML, or edit it directly in TIA Portal.',
    inputSchema: {
      type: 'object',
      properties: {
        db_name:   { type: 'string',  description: 'Name for the new DB, e.g. "Process_DB".' },
        db_number: { type: 'integer', description: 'DB number. Omit or use 0 to auto-assign.' },
      },
      required: ['db_name'],
    },
    handler: async ({ db_name, db_number }) => {
      const args = ['-DBName', db_name];
      if (db_number && db_number > 0) args.push('-DBNumber', String(db_number));
      else args.push('-AutoNumber');
      const result = await runPs(join(SCRIPTS, 'new-global-db.ps1'), args);
      return withHint(JSON.stringify(result, null, 2), `\n---\n⚡ Global DB created. Call \`compile\` to check project consistency.`);
    },
  },

  // ── create_instance_db ─────────────────────────────────────────────────────
  {
    name: 'create_instance_db',
    description:
      'Create an instance DB for a user-defined Function Block (FB) already in the project. ' +
      'NOTE: Does NOT work for system FBs (TON, TOF, CTU, etc.) — TIA manages those internally. ' +
      'System FB instance DBs are created automatically when using the ton-timer / ctu-counter templates via new_block.',
    inputSchema: {
      type: 'object',
      properties: {
        db_name:   { type: 'string',  description: 'Name for the new instance DB, e.g. "MyMotor_DB".' },
        fb_name:   { type: 'string',  description: 'Name of the user FB to instantiate, e.g. "FB_Motor".' },
        db_number: { type: 'integer', description: 'DB number. Omit or use 0 to auto-assign.' },
      },
      required: ['db_name', 'fb_name'],
    },
    handler: async ({ db_name, fb_name, db_number }) => {
      const args = ['-DBName', db_name, '-FBName', fb_name];
      if (db_number && db_number > 0) args.push('-DBNumber', String(db_number));
      else args.push('-AutoNumber');
      const result = await runPs(join(SCRIPTS, 'new-instance-db.ps1'), args);
      return withHint(JSON.stringify(result, null, 2), `\n---\n⚡ Instance DB created. Call \`compile\` to verify the FB instance is consistent.`);
    },
  },

  {
    name: 'lookup_instruction',
    description: 'Search the TIA Portal V20 instruction reference for documentation about a specific instruction. Returns title, description, and parameter tables. Covers LAD, FBD, SCL, and Extended instructions.',
    inputSchema: {
      type: 'object',
      properties: {
        query: {
          type: 'string',
          description: 'Instruction name or keyword to search for, e.g. "TON", "MOVE", "CTU", "DataLogCreate".',
        },
        language: {
          type: 'string',
          enum: ['LAD', 'FBD', 'SCL', 'Extended', 'any'],
          description: 'Filter by programming language. Use "any" to search all.',
          default: 'any',
        },
        max_results: {
          type: 'integer',
          description: 'Maximum number of results to return. Default 5.',
          default: 5,
        },
      },
      required: ['query'],
    },
    handler: async ({ query, language = 'any', max_results = 5 }) => {
      const index = getInstrIndex();
      const q = query.toLowerCase();

      const matches = index.filter((i) => {
        if (language !== 'any' && i.language !== language) return false;
        return i.title.toLowerCase().includes(q);
      });

      // Exact/prefix matches first
      matches.sort((a, b) => {
        const aExact = a.title.toLowerCase().startsWith(q) ? 0 : 1;
        const bExact = b.title.toLowerCase().startsWith(q) ? 0 : 1;
        return aExact - bExact;
      });

      const top = matches.slice(0, max_results);
      if (top.length === 0) return `No instructions found matching "${query}".`;

      return top.map((i) => {
        const lines = [`## ${i.title} (${i.language})`, `_ItemId: ${i.itemId}_`, ''];
        if (i.text) lines.push(i.text.substring(0, 600), '');
        for (const rows of (i.tables || []).slice(0, 2)) {
          if (rows.length > 0) {
            lines.push(rows[0].join(' | '));
            lines.push(rows[0].map(() => '---').join(' | '));
            for (const row of rows.slice(1)) lines.push(row.join(' | '));
            lines.push('');
          }
        }
        return lines.join('\n');
      }).join('\n---\n');
    },
  },
];
