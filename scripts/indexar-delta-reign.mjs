import fs from 'node:fs/promises';
import * as cheerio from 'cheerio';

const COLLECTION_ID = '111247';
const COLLECTION_NAME = 'Delta Reign';
const TCGCOLLECTOR_URL = 'https://www.tcgcollector.com/sets/111247/delta-reign?setCardCountMode=anyCardVariant';
const TCGDEX_SET_ID = 'me6';
const OUTPUT = 'assets/data/dados_cartas.json';
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

async function getJson(url) {
  const response = await fetch(url, { headers: { 'user-agent': 'Mozilla/5.0 TCG-Collector-Indexer/1.0', accept: 'application/json' } });
  if (!response.ok) throw new Error(`HTTP ${response.status} em ${url}`);
  return response.json();
}
async function getText(url) {
  const response = await fetch(url, { headers: { 'user-agent': 'Mozilla/5.0 TCG-Collector-Indexer/1.0', accept: 'text/html' } });
  if (!response.ok) throw new Error(`HTTP ${response.status} em ${url}`);
  return response.text();
}
function numericId(value) {
  const match = String(value ?? '').match(/\d+/);
  return match ? String(Number(match[0])) : '';
}
function extractCollectorCards(html) {
  const $ = cheerio.load(html);
  const cards = new Map();
  $('a[href*="/cards/"]').each((_, element) => {
    const href = $(element).attr('href');
    if (!href) return;
    const url = new URL(href, TCGCOLLECTOR_URL).href.split('?')[0];
    const slug = url.split('/').filter(Boolean).at(-1);
    if (!slug) return;
    const label = $(element).text().replace(/\s+/g, ' ').trim();
    const numberMatch = label.match(/(\d{1,3})\s*\/\s*103/);
    const slugMatch = slug.match(/-(\d{1,3})-103$/);
    const localId = numberMatch?.[1] ?? slugMatch?.[1];
    if (localId) cards.set(numericId(localId), { slug, url });
  });
  return cards;
}
function normalizeTypes(card) {
  const raw = card.types ?? card.type ?? [];
  if (Array.isArray(raw)) return raw.map(x => typeof x === 'string' ? x : x?.name).filter(Boolean);
  return typeof raw === 'string' ? [raw] : [];
}
async function main() {
  const [set, html] = await Promise.all([
    getJson(`https://api.tcgdex.net/v2/en/sets/${TCGDEX_SET_ID}`),
    getText(TCGCOLLECTOR_URL),
  ]);
  const collectorCards = extractCollectorCards(html);
  if (!Array.isArray(set.cards) || set.cards.length !== 141) {
    throw new Error(`TCGdex retornou ${set.cards?.length ?? 0} cartas; esperado 141. Índice não será alterado.`);
  }
  if (collectorCards.size !== 141) {
    throw new Error(`TCG Collector retornou ${collectorCards.size} links numerados; esperado 141. Índice não será alterado.`);
  }

  const details = await Promise.all(set.cards.map(async brief => {
    const detail = await getJson(`https://api.tcgdex.net/v2/en/cards/${encodeURIComponent(brief.id)}`);
    await sleep(80);
    return detail;
  }));
  const records = [];
  for (const card of details) {
    const localId = numericId(card.localId);
    const collector = collectorCards.get(localId);
    if (!collector) throw new Error(`Sem URL TCG Collector para a carta ${card.localId} - ${card.name}`);
    const category = String(card.category ?? 'Unknown');
    const types = normalizeTypes(card);
    const stage = card.stage ?? null;
    const evolvesFrom = card.evolveFrom ?? card.evolvesFrom ?? null;
    const trainerSubtype = card.trainerType ?? null;
    const energyCategory = category === 'Energy'
      ? (card.energyType === 'Special' ? 'Special' : 'Basic')
      : null;
    const energyType = category === 'Energy'
      ? (types[0] ?? card.energyType ?? null)
      : null;
    records.push({
      collectionId: COLLECTION_ID,
      collectionName: COLLECTION_NAME,
      slug: collector.slug,
      url: collector.url,
      name: card.name,
      number: `${String(localId).padStart(3, '0')}/103`,
      numberSort: Number(localId),
      supertype: category,
      types,
      stage,
      evolvesFrom,
      trainerSubtype,
      energyCategory,
      energyType,
      rarity: card.rarity ?? null,
      // O app associa este slug ao prefixo slug__hash dos arquivos locais.
      file: collector.slug,
      needsReview: !['Pokemon', 'Trainer', 'Energy'].includes(category),
    });
  }
  records.sort((a, b) => a.numberSort - b.numberSort);
  if (records.length !== 141 || new Set(records.map(x => x.numberSort)).size !== 141) {
    throw new Error('A validação de unicidade/quantidade falhou. Índice não será alterado.');
  }

  let previous = { version: 1, cards: [] };
  try { previous = JSON.parse(await fs.readFile(OUTPUT, 'utf8')); } catch {}
  const kept = (previous.cards ?? []).filter(card => String(card.collectionId) !== COLLECTION_ID);
  const merged = [...kept, ...records];
  await fs.writeFile(OUTPUT, JSON.stringify({
    version: 1,
    generatedAt: new Date().toISOString(),
    cards: merged,
  }, null, 2) + '\n');
  console.log(JSON.stringify({
    collection: COLLECTION_NAME,
    collectionId: COLLECTION_ID,
    cardsAdded: records.length,
    totalCardsInIndex: merged.length,
    firstCard: records[0].name,
    lastCard: records.at(-1).name,
    output: OUTPUT,
  }, null, 2));
}
main().catch(error => { console.error(error); process.exit(1); });
