import fs from 'node:fs/promises';
import path from 'node:path';
import { GhostClient } from 'ghostfetch';
import * as cheerio from 'cheerio';

const SETS = [
  { id: '1118', name: 'EX Dragon', slug: 'ex-dragon', tcgdex: 'ex3', count: 100 },
  { id: '1121', name: 'EX FireRed & LeafGreen', slug: 'ex-firered-and-leafgreen', tcgdex: 'ex6', count: 116 },
  { id: '1130', name: 'EX Dragon Frontiers', slug: 'ex-dragon-frontiers', tcgdex: 'ex15', count: 101 },
  { id: '1153', name: 'Dragons Exalted', slug: 'dragons-exalted', tcgdex: 'bw6', count: 128 },
];
const DEFAULT_INDEX = '/sdcard/meuapp/dados_cartas.json';
const INPUT = process.env.INDEX_INPUT || DEFAULT_INDEX;
const OUTPUTS = [...new Set([
  process.env.INDEX_OUTPUT || INPUT,
  process.env.REPO_OUTPUT || '',
].filter(Boolean))];
const REPORT = process.env.REPORT_PATH || '/sdcard/Download/relatorio_reindexacao_4_colecoes.json';
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const norm = s => String(s ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]/g, '');
const KNOWN_TYPES = ['Grass','Fire','Water','Lightning','Psychic','Fighting','Darkness','Metal','Fairy','Dragon','Colorless'];
let client = new GhostClient({ browser: 'Chrome_131', timeout: 90000 });

async function resetClient() {
  try { await client.destroy(); } catch {}
  client = new GhostClient({ browser: 'Chrome_131', timeout: 90000 });
}
async function getHtml(url) {
  let last;
  for (let attempt = 1; attempt <= 6; attempt++) {
    try {
      const response = await client.fetch(url, {
        headers: { Referer: 'https://www.tcgcollector.com/', Accept: 'text/html,application/xhtml+xml,*/*;q=0.8' },
      });
      if (!response.ok) throw new Error('HTTP ' + response.status + ' em ' + url);
      return await response.text();
    } catch (error) {
      last = error;
      console.error('[TCGCOLLECTOR] tentativa ' + attempt + '/6: ' + error.message);
      if (attempt < 6) { await resetClient(); await sleep(2000 * attempt); }
    }
  }
  throw last;
}
async function getJson(url) {
  let last;
  for (let attempt = 1; attempt <= 5; attempt++) {
    try {
      const response = await fetch(url, {
        headers: { Accept: 'application/json', 'User-Agent': 'TCG-Collector-Index/2.0' },
        signal: AbortSignal.timeout(30000),
      });
      if (!response.ok) throw new Error('HTTP ' + response.status + ' em ' + url);
      return await response.json();
    } catch (error) {
      last = error;
      console.error('[TCGDEX] tentativa ' + attempt + '/5: ' + error.message);
      if (attempt < 5) await sleep(1500 * attempt);
    }
  }
  throw last;
}
function numericId(value) {
  const m = String(value ?? '').match(/\d+/);
  return m ? String(Number(m[0])) : '';
}
function extractCollectorCards(html, baseUrl) {
  const $ = cheerio.load(html);
  const cards = new Map();
  $('a[href*="/cards/"]').each((_, el) => {
    const href = $(el).attr('href');
    if (!href) return;
    const url = new URL(href, baseUrl).href.split('?')[0];
    const slug = url.split('/').filter(Boolean).at(-1);
    if (!slug) return;
    const label = $(el).text().replace(/\s+/g, ' ').trim();
    const m = label.match(/(\d{1,4})\s*\/\s*(\d{1,4})/) || slug.match(/-(\d{1,4})-(\d{1,4})$/);
    if (!m) return;
    const localId = numericId(m[1]);
    if (localId) cards.set(localId, { slug, url, localId, total: Number(m[2]) });
  });
  return cards;
}
async function verifyCollectorCard(card, expectedName, expectedNumber) {
  const html = await getHtml(card.url);
  const $ = cheerio.load(html);
  const heading = $('h1').first().text().replace(/\s+/g, ' ').trim();
  const body = $('body').text().replace(/\s+/g, ' ').trim();
  const numberMatch = body.match(/Card number\s*(\d{1,4})\s*\/\s*(\d{1,4})/i);
  if (!heading) throw new Error('TCG Collector sem título em ' + card.url);
  if (norm(heading) !== norm(expectedName)) {
    throw new Error('Nome divergente ' + card.url + ': TCG Collector="' + heading + '"; TCGdex="' + expectedName + '"');
  }
  if (!numberMatch || Number(numberMatch[1]) !== Number(expectedNumber)) {
    throw new Error('Número divergente em ' + card.url + ': TCG Collector="' + (numberMatch?.[0] ?? 'ausente') + '"; TCGdex=' + expectedNumber);
  }
  return { heading, number: numberMatch[0] };
}
function energyElementalType(name, types) {
  const normalized = norm(name).replace(/^basic/, '');
  return KNOWN_TYPES.find(type => normalized.startsWith(norm(type) + 'energy')) ??
    (Array.isArray(types) ? types[0] ?? null : null);
}
async function main() {
  const raw = await fs.readFile(INPUT, 'utf8');
  const previous = JSON.parse(raw);
  if (!previous || !Array.isArray(previous.cards)) throw new Error('Índice de entrada inválido; nada foi alterado.');
  const oldCards = previous.cards;
  const replacements = new Map();
  const reports = [];

  for (const set of SETS) {
    const setUrl = 'https://www.tcgcollector.com/sets/' + set.id + '/' + set.slug + '?setCardCountMode=anyCardVariant';
    console.log('\n[COLEÇÃO] ' + set.id + ' — ' + set.name);
    const collectorCards = extractCollectorCards(await getHtml(setUrl), setUrl);
    if (collectorCards.size !== set.count) {
      throw new Error(set.name + ': TCG Collector retornou ' + collectorCards.size + ' cartas; esperado ' + set.count + '. Índice preservado.');
    }
    const tcgdexSet = await getJson('https://api.tcgdex.net/v2/en/sets/' + encodeURIComponent(set.tcgdex));
    if (!Array.isArray(tcgdexSet.cards) || tcgdexSet.cards.length !== collectorCards.size) {
      throw new Error(set.name + ': divergência de quantidade — TCG Collector ' + collectorCards.size + ', TCGdex ' + (tcgdexSet.cards?.length ?? 0) + '. Índice preservado.');
    }

    const oldByNumber = new Map(oldCards.filter(c => String(c.collectionId) === set.id)
      .map(c => [numericId(c.numberSort ?? c.number), c]));
    const queue = [...tcgdexSet.cards];
    const records = [];
    const failures = [];
    const workers = Array.from({ length: 4 }, async () => {
      while (queue.length) {
        const brief = queue.shift();
        const localId = numericId(brief.localId);
        const collector = collectorCards.get(localId);
        if (!collector) { failures.push('Carta TCGdex sem correspondência no TCG Collector: ' + brief.name + ' #' + brief.localId); continue; }
        try {
          const cardId = brief.id || set.tcgdex + '-' + brief.localId;
          const card = await getJson('https://api.tcgdex.net/v2/en/cards/' + encodeURIComponent(cardId));
          if (!['Pokemon', 'Trainer', 'Energy'].includes(card.category)) throw new Error('Categoria TCGdex inválida: ' + card.category);
          const check = await verifyCollectorCard(collector, card.name || brief.name, localId);
          const types = Array.isArray(card.types) ? card.types : [];
          const isEnergy = card.category === 'Energy';
          const energyName = norm(card.name || '');
          const isBasicEnergy = isEnergy && /^(basic)?(grass|fire|water|lightning|psychic|fighting|darkness|metal|fairy|dragon|colorless)energy$/.test(energyName);
          const old = oldByNumber.get(localId);
          const record = {
            collectionId: set.id,
            collectionName: set.name,
            slug: collector.slug,
            url: collector.url,
            name: card.name || brief.name,
            number: localId + '/' + collector.total,
            numberSort: Number(localId),
            supertype: card.category,
            types,
            stage: card.stage || null,
            evolvesFrom: card.evolveFrom || null,
            trainerSubtype: card.trainerType || null,
            energyCategory: isEnergy ? (isBasicEnergy ? 'Basic' : 'Special') : null,
            energyType: isBasicEnergy ? energyElementalType(card.name, types) : null,
            hp: card.hp ?? null,
            rarity: card.rarity || null,
            file: old?.file || collector.slug,
            needsReview: (card.category === 'Pokemon' && !types.length) ||
              (card.category === 'Trainer' && !card.trainerType) ||
              (isEnergy && !['Basic', 'Special'].includes(isEnergy ? (isBasicEnergy ? 'Basic' : 'Special') : '')),
          };
          if (record.needsReview) throw new Error('Metadados incompletos: ' + JSON.stringify(record));
          records.push(record);
          console.log('[OK] ' + set.id + ' ' + record.number + ' ' + record.name + ' — ' + record.supertype + ' | verificado: ' + check.heading);
        } catch (error) { failures.push(set.id + ' #' + localId + ' ' + (brief.name || '') + ': ' + error.message); }
        await sleep(250);
      }
    });
    await Promise.all(workers);
    if (failures.length) throw new Error(set.name + ': ' + failures.length + ' falhas:\n' + failures.join('\n') + '\nÍndice preservado.');
    if (records.length !== set.count || new Set(records.map(x => x.numberSort)).size !== set.count) {
      throw new Error(set.name + ': quantidade ou numeração duplicada. Índice preservado.');
    }
    records.sort((a, b) => a.numberSort - b.numberSort);
    for (const record of records) replacements.set(set.id + '|' + record.slug, record);
    reports.push({
      id: set.id, name: set.name, count: records.length,
      pokemon: records.filter(x => x.supertype === 'Pokemon').length,
      trainers: records.filter(x => x.supertype === 'Trainer').length,
      energies: records.filter(x => x.supertype === 'Energy').length,
      first: records[0]?.name, last: records.at(-1)?.name,
      comparedWithTCGCollector: records.length,
    });
  }

  const targetIds = new Set(SETS.map(x => x.id));
  const preserved = oldCards.filter(c => !targetIds.has(String(c.collectionId)));
  const merged = [...preserved, ...replacements.values()];
  const result = { version: previous.version || 1, generatedAt: new Date().toISOString(), cards: merged };
  const output = JSON.stringify(result, null, 2) + '\n';
  for (const file of OUTPUTS) {
    await fs.mkdir(path.dirname(file), { recursive: true });
    if (path.resolve(file) === path.resolve(INPUT)) {
      const backup = file + '.backup1';
      try { await fs.access(backup); } catch { await fs.copyFile(file, backup); }
    }
    await fs.writeFile(file, output);
    console.log('[SALVO] ' + file + ' (' + Buffer.byteLength(output) + ' bytes)');
  }
  const report = {
    source: INPUT,
    totalBefore: oldCards.length,
    totalAfter: merged.length,
    replacedCollections: reports,
    removedOldTargetRecords: oldCards.filter(c => targetIds.has(String(c.collectionId))).length,
    newTargetRecords: replacements.size,
    verifiedAgainstTCGCollector: true,
  };
  await fs.mkdir(path.dirname(REPORT), { recursive: true });
  await fs.writeFile(REPORT, JSON.stringify(report, null, 2) + '\n');
  console.log('\n[RELATÓRIO FINAL]\n' + JSON.stringify(report, null, 2));
}
main().catch(error => { console.error('\n[ERRO FATAL] ' + error.stack); process.exitCode = 1; })
  .finally(async () => { try { await client.destroy(); } catch {} });
