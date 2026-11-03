// Build Godslayer/Pvp.lua from the WoW: Forever client's own game data.
//
//   node tools/build_pvp_data.mjs [--check]
//
// Everything a PvP addon has to know about a spell is in the client and almost nobody reads it:
//
//   DiminishType   the game's own diminishing-returns group. Not a guess, not vanilla's table
//                  from 2006, the number this build actually uses. Spells that share it diminish
//                  together, and a 0 means the game does not diminish it at all.
//   Category       the shared cooldown group. Divine Shield and Ice Block are both category 37,
//                  "Invulnerability", so a paladin who bubbles has put Divine Protection on
//                  cooldown as well. An addon that tracks spells one at a time gets this wrong.
//   PvPDurationIndex  the duration the spell gets against a player, which is frequently not the
//                  duration it gets against anything else.
//
// The ids are not resolved from names here. They are taken from the lists Godslayer already
// verified against client data, because two spells in this client are called "Frost Blast" and
// only one of them is the mage's.
//
// Writes Godslayer/Pvp.lua and tools/pvp_report.md. --check writes nothing and exits non-zero if
// the generated file would differ, which is what the test suite uses.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..');
const KNOWLEDGE = '/home/yeeterson/projects/wow-forever-guild/site/scripts/knowledge';

const L = await import(path.join(KNOWLEDGE, 'lib.mjs'));

const BUILD = L.latestBuild();
if (!BUILD) throw new Error('no client build in the knowledge cache');

// ---------------------------------------------------------------------------
// The spells we care about, by the ids Godslayer already trusts.
// ---------------------------------------------------------------------------

function luaIdTable(file, startMarker) {
  const text = fs.readFileSync(path.join(ROOT, 'Godslayer', file), 'utf8');
  const start = text.indexOf(startMarker);
  if (start < 0) throw new Error(`${startMarker} not found in ${file}`);
  const open = text.indexOf('{', start);
  let depth = 0, end = open;
  for (let i = open; i < text.length; i++) {
    if (text[i] === '{') depth++;
    else if (text[i] === '}') { depth--; if (depth === 0) { end = i; break; } }
  }
  const body = text.slice(open, end + 1);
  const out = new Map();
  // ["Some Name"] = 123   or   Bareword = 123
  for (const m of body.matchAll(/\[\s*"([^"]+)"\s*\]\s*=\s*(\d+)/g)) out.set(m[1], Number(m[2]));
  for (const m of body.matchAll(/(?:^|[,{\s])([A-Za-z][A-Za-z0-9_]*)\s*=\s*(\d+)/gm)) {
    if (!out.has(m[1])) out.set(m[1], Number(m[2]));
  }
  return out;
}

// Fight.lua's SPELL_IDS: every spell with a sound or a finisher already verified.
const ids = luaIdTable('Fight.lua', 'local SPELL_IDS = {');

// Aura.lua's three tables carry `id = NNN` inside each entry, so they are read differently.
function auraIds() {
  const text = fs.readFileSync(path.join(ROOT, 'Godslayer', 'Aura.lua'), 'utf8');
  const out = new Map();
  for (const m of text.matchAll(/\[?"?([A-Za-z][A-Za-z0-9 :'\-,]*?)"?\]?\s*=\s*\{[^}]*?\bid\s*=\s*(\d+)/g)) {
    const name = m[1].trim();
    // `local CC = { ... id = 853 ...` matches the same shape as a spell entry, so the table's
    // own declaration would otherwise be imported as a spell called "local CC".
    if (/^local\s/.test(name)) continue;
    out.set(name, Number(m[2]));
  }
  return out;
}
for (const [name, id] of auraIds()) if (!ids.has(name)) ids.set(name, id);

// ---------------------------------------------------------------------------
// Client data
// ---------------------------------------------------------------------------

const cats = L.by('SpellCategories', 'SpellID', BUILD);
const cools = L.by('SpellCooldowns', 'SpellID', BUILD);
const misc = L.by('SpellMisc', 'SpellID', BUILD);
const catNames = new Map(L.table('SpellCategory', BUILD).map(r => [String(r.ID), r.Name_lang]));
const durations = new Map(L.table('SpellDuration', BUILD).map(r => [String(r.ID), r]));

const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };

// The engine's school bits. Index, not mask, is what the client's own strings are keyed on:
// SPELL_SCHOOL0_CAP is Physical and SPELL_SCHOOL6_CAP is Arcane, and the mask is 1 << index.
const SCHOOLS = [[1, 'Physical'], [2, 'Holy'], [4, 'Fire'], [8, 'Nature'],
                 [16, 'Frost'], [32, 'Shadow'], [64, 'Arcane']];

// Durations in this table are milliseconds; -1 means "until cancelled".
function seconds(index) {
  const row = durations.get(String(index));
  if (!row) return null;
  const ms = num(row.Duration);
  if (ms < 0) return -1;
  if (ms === 0) return null;
  return Math.round(ms) / 1000;
}

const spells = [];
for (const [name, id] of [...ids].sort((a, b) => a[0].localeCompare(b[0]))) {
  const c = (cats.get(String(id)) || [])[0] || {};
  const cd = (cools.get(String(id)) || [])[0] || {};
  const m = (misc.get(String(id)) || [])[0] || {};

  const own = Math.round(num(cd.RecoveryTime)) / 1000;
  const shared = Math.round(num(cd.CategoryRecoveryTime)) / 1000;
  const category = num(c.Category);

  spells.push({
    name, id,
    dr: num(c.DiminishType) || 0,
    mechanic: num(c.Mechanic) || 0,
    category: category || 0,
    categoryName: category ? (catNames.get(String(category)) || '') : '',
    cd: own || 0,
    sharedCd: shared || 0,
    duration: seconds(m.DurationIndex),
    pvpDuration: seconds(m.PvPDurationIndex),
    school: num(m.SchoolMask) || 0,
  });
}

// Diminishing groups are named from what is in them, not from an enum nobody shipped. A group's
// label is its best-known member, so the addon can print something a person recognises without
// anyone pretending to know Blizzard's own name for the number.
const groups = new Map();
for (const s of spells) {
  if (!s.dr) continue;
  if (!groups.has(s.dr)) groups.set(s.dr, []);
  groups.get(s.dr).push(s.name);
}
const PREFERRED = ['Polymorph', 'Hammer of Justice', 'Kidney Shot', 'Fear', 'Entangling Roots',
                   'Mind Control', 'Psychic Scream', 'Freezing Trap', 'Blind'];
const groupLabel = new Map();
for (const [dr, members] of groups) {
  const pick = PREFERRED.find(p => members.includes(p)) || members.slice().sort()[0];
  groupLabel.set(dr, pick);
}

// Spells that share a cooldown category with something else: the fact worth knowing.
const sharedBy = new Map();
for (const s of spells) {
  if (!s.category || !s.sharedCd) continue;
  if (!sharedBy.has(s.category)) sharedBy.set(s.category, []);
  sharedBy.get(s.category).push(s.name);
}

// ---------------------------------------------------------------------------
// Emit
// ---------------------------------------------------------------------------

const q = (s) => `"${String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
const key = (s) => (/^[A-Za-z_][A-Za-z0-9_]*$/.test(s) ? s : `[${q(s)}]`);

const lines = [];
lines.push('-- Written by tools/build_pvp_data.mjs from the client\'s own game data. Do not edit by hand.');
lines.push(`-- Build ${BUILD}. Every number here is what this client says, not what vanilla did.`);
lines.push('--');
lines.push('-- dr        the game\'s diminishing-returns group; spells sharing it diminish together, 0 never does');
lines.push('-- cat       a shared cooldown group: casting any spell in it puts the whole group on cooldown');
lines.push('-- catCd     how long casting THIS spell locks that group for, which differs per spell');
lines.push('-- cd        the spell\'s own cooldown in seconds');
lines.push('-- pvp       the duration it gets against a player, when that differs from `dur`');
lines.push('-- school    the spell\'s school as a bit mask, which is what a Counterspell locks out');
lines.push('local _, ns = ...');
lines.push('');
lines.push(`ns.PVP_BUILD = ${q(BUILD)}`);
lines.push('');
lines.push('-- Spell schools as the engine masks them: 1 << index, index 0 Physical to 6 Arcane.');
lines.push('-- A lockout from an interrupt is a mask of these, so it can name more than one school.');
lines.push('-- The strings are the client\'s own and are read at runtime; these are the fallback.');
lines.push('ns.SCHOOL_BITS = {');
for (const [bit, name] of SCHOOLS) lines.push(`  [${bit}] = { key = ${q('SPELL_SCHOOL' + Math.log2(bit) + '_CAP')}, name = ${q(name)} },`);
lines.push('}');
lines.push('');
lines.push('-- The diminishing groups this build actually has, labelled by a member you will recognise.');
lines.push('ns.DR_GROUPS = {');
for (const dr of [...groups.keys()].sort((a, b) => a - b)) {
  lines.push(`  [${dr}] = { label = ${q(groupLabel.get(dr))}, members = ${groups.get(dr).length} },`);
}
lines.push('}');
lines.push('');
lines.push('-- Cooldown groups with more than one spell in them: the ones an addon gets wrong by');
lines.push('-- tracking each spell on its own.');
lines.push('ns.CD_GROUPS = {');
for (const [cat, members] of [...sharedBy].sort((a, b) => a[0] - b[0])) {
  if (members.length < 2) continue;
  lines.push(`  [${cat}] = { name = ${q(catNames.get(String(cat)) || '')}, ${members.map(q).join(', ')} },`);
}
lines.push('}');
lines.push('');
lines.push('ns.PVP = {');
for (const s of spells) {
  const bits = [`id = ${s.id}`];
  if (s.dr) bits.push(`dr = ${s.dr}`);
  if (s.mechanic) bits.push(`mech = ${s.mechanic}`);
  if (s.cd) bits.push(`cd = ${s.cd}`);
  if (s.category) bits.push(`cat = ${s.category}`);
  if (s.sharedCd) bits.push(`catCd = ${s.sharedCd}`);
  if (s.duration != null) bits.push(`dur = ${s.duration}`);
  if (s.pvpDuration != null && s.pvpDuration !== s.duration) bits.push(`pvp = ${s.pvpDuration}`);
  if (s.school) bits.push(`school = ${s.school}`);
  if (s.categoryName) bits.push(`catName = ${q(s.categoryName)}`);
  lines.push(`  ${key(s.name)} = { ${bits.join(', ')} },`);
}
lines.push('}');
lines.push('');
lines.push('-- id -> name, so a cast seen by id is named without a round trip through the client.');
lines.push('ns.PVP_BY_ID = {}');
lines.push('for name, s in pairs(ns.PVP) do ns.PVP_BY_ID[s.id] = name end');
lines.push('');

const out = lines.join('\n');
const target = path.join(ROOT, 'Godslayer', 'Pvp.lua');

if (process.argv.includes('--check')) {
  const have = fs.existsSync(target) ? fs.readFileSync(target, 'utf8') : '';
  if (have !== out) { console.error('Pvp.lua is out of date; run node tools/build_pvp_data.mjs'); process.exit(1); }
  console.log(`Pvp.lua matches the client at build ${BUILD}`);
  process.exit(0);
}

fs.writeFileSync(target, out);

// A report, because a generated table nobody can read is a table nobody checks.
const rep = [];
rep.push(`# Godslayer PvP data, build ${BUILD}`);
rep.push('');
rep.push(`${spells.length} spells read from the client.`);
rep.push('');
rep.push('## Diminishing groups');
rep.push('');
rep.push('The client\'s own numbers. A spell with no group is one the game does not diminish, which');
rep.push('is worth reading twice before you trust a table from another expansion.');
rep.push('');
rep.push('| group | label | members |');
rep.push('|---|---|---|');
for (const dr of [...groups.keys()].sort((a, b) => a - b)) {
  rep.push(`| ${dr} | ${groupLabel.get(dr)} | ${groups.get(dr).sort().join(', ')} |`);
}
const noDr = spells.filter(s => !s.dr && s.mechanic).map(s => s.name).sort();
rep.push('');
rep.push(`Spells with a mechanic but **no** diminishing group (${noDr.length}): ${noDr.join(', ')}`);
rep.push('');
rep.push('## Shared cooldown groups');
rep.push('');
rep.push('The lock is the **casting** spell\'s own category cooldown applied to the whole group, not');
rep.push('one number per group: in category 56, Power Word: Shield locks the group for 4s and Lay on');
rep.push('Hands locks the same group for 1200s. Each member is listed with what casting it costs.');
rep.push('');
rep.push('| id | name | casting this | locks the group for |');
rep.push('|---|---|---|---|');
for (const [cat, members] of [...sharedBy].sort((a, b) => a[0] - b[0])) {
  if (members.length < 2) continue;
  const name = catNames.get(String(cat)) || '';
  for (const member of members.slice().sort()) {
    const s = spells.find(x => x.name === member);
    rep.push(`| ${cat} | ${name} | ${member} | ${s.sharedCd}s |`);
  }
}
rep.push('');
rep.push('## Where the PvP duration differs from the normal one');
rep.push('');
const diff = spells.filter(s => s.pvpDuration != null && s.pvpDuration !== s.duration);
if (!diff.length) rep.push('Nothing in this set. Every tracked spell lasts the same against a player.');
else {
  rep.push('| spell | normal | against a player |');
  rep.push('|---|---|---|');
  for (const s of diff) rep.push(`| ${s.name} | ${s.duration ?? '-'}s | ${s.pvpDuration}s |`);
}
rep.push('');
rep.push('## Schools, and what an interrupt locks');
rep.push('');
rep.push('A Counterspell or a Kick locks the **school** of the spell it hit, not the spell. These are');
rep.push('the masks the client gives each spell, so a lockout can be turned into a list of what is');
rep.push('still castable instead of a bare "interrupted".');
rep.push('');
rep.push('| mask | school | spells here |');
rep.push('|---|---|---|');
for (const [bit, name] of SCHOOLS) {
  const members = spells.filter(s => s.school === bit).map(s => s.name).sort();
  rep.push(`| ${bit} | ${name} | ${members.length ? members.join(', ') : '-'} |`);
}
const multi = spells.filter(s => s.school && !SCHOOLS.some(([b]) => b === s.school));
if (multi.length) {
  rep.push('');
  rep.push(`Spells in more than one school (${multi.length}): ` +
    multi.map(s => `${s.name} (${s.school})`).sort().join(', '));
}
const noSchool = spells.filter(s => !s.school).map(s => s.name).sort();
rep.push('');
rep.push(`Spells the client gives no school (${noSchool.length}): ${noSchool.length ? noSchool.join(', ') : 'none'}`);
rep.push('');
rep.push('## Longest cooldowns');
rep.push('');
rep.push('| spell | cooldown |');
rep.push('|---|---|');
for (const s of spells.filter(s => s.cd >= 60).sort((a, b) => b.cd - a.cd).slice(0, 25)) {
  rep.push(`| ${s.name} | ${s.cd}s |`);
}
rep.push('');
fs.writeFileSync(path.join(HERE, 'pvp_report.md'), rep.join('\n'));

console.log(`wrote Godslayer/Pvp.lua (${spells.length} spells, ${groups.size} diminishing groups) and tools/pvp_report.md`);
