"""Extract authoritative bit map for state, alarm, receive.status, send.control, move
by tracing each Coil's 'operand' (target bit) -> 'in' wire -> Contact 'operand' (source).
"""
import re
from xml.etree import ElementTree as ET
from collections import defaultdict

PATH = r'C:\Users\MudasserWahab\Claude Code\udt_export\LSicar_KistlerPress.xml'
text = open(PATH, encoding='utf-8').read()
text = re.sub(r'\sxmlns="[^"]+"', '', text)
root = ET.fromstring(text)

def describe(acc):
    sym = acc.find('Symbol')
    if sym is None:
        return f'(scope={acc.get("Scope")})'
    parts = []
    for c in sym.iter('Component'):
        nm = c.get('Name', '')
        am = c.get('AccessModifier')
        sm = c.get('SliceAccessModifier', '')
        if am == 'Array':
            inner = c.find('Access')
            inner_desc = describe(inner) if inner is not None else '?'
            parts.append(f'{nm}[{inner_desc}]')
        else:
            label = nm
            if sm: label += f'.{sm}'
            parts.append(label)
    return '.'.join(parts)

def title(net):
    for mt in net.iter('MultilingualTextItem'):
        cul = mt.find('AttributeList/Culture')
        txt = mt.find('AttributeList/Text')
        if cul is not None and cul.text == 'en-US' and txt is not None and txt.text:
            return txt.text.strip()
    return ''

def trace_part_source(part_uid, parts, accesses, wires, depth=0, seen=None):
    """Walk back from a part's 'in' pin to find the original Access source.
    Returns a list of (part_name, neg, access_path) tuples representing the chain."""
    if seen is None: seen = set()
    if part_uid in seen or depth > 30: return []
    seen.add(part_uid)
    p = parts.get(part_uid)
    if p is None: return []
    chain = []
    # Find 'in' wire(s) for this part
    for w in wires:
        ncs = [c for c in w if c.tag == 'NameCon' and c.get('UId') == part_uid and c.get('Name') == 'in']
        if not ncs: continue
        identcons = [c for c in w if c.tag == 'IdentCon']
        other_parts = [c for c in w if c.tag == 'NameCon' and c.get('UId') != part_uid]
        for ic in identcons:
            src = accesses.get(ic.get('UId'))
            if src is not None:
                neg = 'NC' if any(k.tag == 'Negated' for k in p) else 'NO'
                chain.append((p.get('Name'), neg, describe(src)))
        for onc in other_parts:
            chain.extend(trace_part_source(onc.get('UId'), parts, accesses, wires, depth+1, seen))
    return chain

def get_coil_target(coil_uid, parts, accesses, wires):
    """Get the Access that a coil writes to (its 'operand')."""
    for w in wires:
        ncs = [c for c in w if c.tag == 'NameCon' and c.get('UId') == coil_uid and c.get('Name') == 'operand']
        if not ncs: continue
        identcons = [c for c in w if c.tag == 'IdentCon']
        for ic in identcons:
            a = accesses.get(ic.get('UId'))
            if a is not None: return a
    return None

def get_contact_operand(contact_uid, parts, accesses, wires):
    """Get the Access that a contact reads from (its 'operand')."""
    for w in wires:
        ncs = [c for c in w if c.tag == 'NameCon' and c.get('UId') == contact_uid and c.get('Name') == 'operand']
        if not ncs: continue
        identcons = [c for c in w if c.tag == 'IdentCon']
        for ic in identcons:
            a = accesses.get(ic.get('UId'))
            if a is not None: return a
    return None

def bit_of(acc):
    sym = acc.find('Symbol')
    if sym is None: return None
    comps = list(sym.iter('Component'))
    if not comps: return None
    sm = comps[-1].get('SliceAccessModifier', '')
    m = re.match(r'x(\d+)', sm)
    return int(m.group(1)) if m else None

def analyze_network(net, field_filter):
    flgnet = net.find('.//FlgNet')
    if flgnet is None: return {}
    parts = {p.get('UId'): p for p in flgnet.iter('Part')}
    accesses = {a.get('UId'): a for a in flgnet.iter('Access') if a.get('UId')}
    wires = list(flgnet.iter('Wire'))

    bit_map = {}
    for puid, p in parts.items():
        pn = p.get('Name')
        if pn not in ('Coil', 'RCoil', 'SCoil', 'NCoil'): continue
        target = get_coil_target(puid, parts, accesses, wires)
        if target is None: continue
        target_path = describe(target)
        if field_filter not in target_path: continue
        bit = bit_of(target)
        if bit is None: continue

        # Trace input chain
        chain = trace_part_source(puid, parts, accesses, wires)
        # Also get any direct Contact operands traversed
        contact_sources = []
        # Walk: find all parts in the chain leading to this coil, get their operands
        seen2 = set()
        def collect_contacts(this_uid, dep=0):
            if this_uid in seen2 or dep > 30: return
            seen2.add(this_uid)
            for w in wires:
                ncs = [c for c in w if c.tag == 'NameCon' and c.get('UId') == this_uid and c.get('Name') == 'in']
                if not ncs: continue
                for onc in w:
                    if onc.tag == 'NameCon' and onc.get('UId') != this_uid:
                        other_uid = onc.get('UId')
                        other_part = parts.get(other_uid)
                        if other_part is None: continue
                        op = get_contact_operand(other_uid, parts, accesses, wires)
                        if op is not None:
                            neg = any(k.tag == 'Negated' for k in other_part)
                            contact_sources.append((other_part.get('Name'), 'NC' if neg else 'NO', describe(op)))
                        collect_contacts(other_uid, dep+1)
        collect_contacts(puid)
        bit_map[bit] = (pn, target_path, contact_sources)
    return bit_map

nets = list(root.iter('SW.Blocks.CompileUnit'))
# Try-find networks by title
def find_net(pattern):
    found = []
    for i, n in enumerate(nets, 1):
        if pattern.lower() in title(n).lower():
            found.append((i, n))
    return found

for label, pattern, field_filter in [
    ('receive.status (Map FIx Receieved Data)', 'receieved', 'receive.status'),
    ('send.control (Map Fix Send Data)',        'send data', 'send.control'),
    ('state (HMI state Mapping)',                'state mapping', '.state.'),
    ('alarm (Map Alarms to HMI Interface)',      'alarms to hmi', '.alarm.'),
    ('move (Run Sequence + JOG + Home + Ref + Ack + Cont)', 'control remotely', '.move.'),  # multiple networks
]:
    print(f'\n{"="*70}\n{label}\n{"="*70}')
    # We may have several matching networks for some fields (e.g. move spans multiple)
    matches = find_net(pattern)
    # Also fallback to scanning all networks for the field_filter
    if not matches:
        matches = [(i, n) for i, n in enumerate(nets, 1)]
    seen_bits = set()
    for idx, net in matches:
        bm = analyze_network(net, field_filter)
        if not bm: continue
        print(f'  network {idx} "{title(net)}":')
        for bit in sorted(bm):
            if (field_filter, bit) in seen_bits: continue
            seen_bits.add((field_filter, bit))
            kind, dst, srcs = bm[bit]
            srcs_str = ' AND '.join(f'{n}({neg}){"!" if neg=="NC" else ""}{p}' for n,neg,p in srcs[:6]) if srcs else 'powerrail'
            print(f'    bit {bit:2}  [{kind:5}] -> {dst.split(".")[-1]:15}  SRC: {srcs_str}')
