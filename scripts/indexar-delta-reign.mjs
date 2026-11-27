import fs from 'node:fs/promises';
import * as cheerio from 'cheerio';
import { GhostClient } from 'ghostfetch';

const COLLECTION_ID = String(process.env.COLLECTION_ID ?? '111247').trim();
const COLLECTION_NAME = String(process.env.COLLECTION_NAME ?? 'Delta Reign').trim();
const COLLECTION_SLUG = String(process.env.COLLECTION_SLUG ?? 'delta-reign').trim();
const TCGDEX_SET_ID = String(process.env.TCGDEX_SET_ID ?? 'me06').trim();
const TCGCOLLECTOR_URL = String(process.env.TCGCOLLECTOR_URL ??
  `https://www.tcgcollector.com/sets/${COLLECTION_ID}/${COLLECTION_SLUG}?setCardCountMode=anyCardVariant`).trim();
const EXPECTED_COUNT = Number(process.env.EXPECTED_COUNT ?? 141) || null;
const OUTPUT = 'assets/data/dados_cartas.json';
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const KNOWN_TYPES = ['Grass','Fire','Water','Lightning','Psychic','Fighting','Darkness','Metal','Fairy','Dragon','Colorless'];

let client = new GhostClient({ browser: 'Chrome_131', timeout: 90000 });

async function resetClient() {
  try { await client.destroy(); } catch {}
  client = new GhostClient({ browser: 'Chrome_131', timeout: 90000 });
}

async function getHtml(url) {
  let lastError;
  for (let attempt = 1; attempt <= 5; attempt++) {
    try {
      const response = await client.fetch(url, {
        headers: {
          Referer: 'https://www.tcgcollector.com/',
          Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
      });
      if (!response.ok) throw new Error(`HTTP ${response.status} em ${url}`);
      return await response.text();
    } catch (error) {
      lastError = error;
      console.error(`[TCGCOLLECTOR] tentativa ${attempt}/5: ${error.message}`);
      if (attempt < 5) {
        await resetClient();
        await sleep(3000 * attempt);
      }
    }
  }
  throw lastError;
}

async function getJson(url) {
  let lastError;
  for (let attempt = 1; attempt <= 5; attempt++) {
    try {
      const response = await fetch(url, {
        headers: { Accept: 'application/json', 'User-Agent': 'TCG-Collector-Index/1.0' },
        signal: AbortSignal.timeout(30000),
      });
      if (!response.ok) throw new Error(`HTTP ${response.status} em ${url}`);
      return await response.json();
    } catch (error) {
      lastError = error;
      console.error(`[TCGDEX] tentativa ${attempt}/5: ${error.message}`);
      if (attempt < 5) await sleep(1500 * attempt);
    }
  }
  throw lastError;
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
    const numberMatch = label.match(/(\d{1,4})\s*\/\s*(\d{1,4})/);
    const slugMatch = slug.match(/-(\d{1,4})-(\d{1,4})$/);
    const localId = numberMatch?.[1] ?? slugMatch?.[1];
    const total = numberMatch?.[2] ?? slugMatch?.[2] ?? null;
    if (localId) cards.set(numericId(localId), {
      slug, url, localId: numericId(localId), total: total ? Number(total) : null,
    });
  });
  return cards;
}

function energyElementalType(name, types) {
  const normalized = String(name ?? '').toLowerCase().replace(/^basic\\s+/, '');
  return KNOWN_TYPES.find(type => normalized.startsWith(type.toLowerCase() + ' ')) ??
    (Array.isArray(types) ? types[0] ?? null : null);
}

async function main() {
  if (!COLLECTION_ID || !COLLECTION_NAME || !TCGDEX_SET_ID) {
    throw new Error('ID, nome da coleção e ID TCGdex são obrigatórios.');
  }
  console.log(`[INÍCIO] ${COLLECTION_NAME} — TCG Collector ${COLLECTION_ID}; TCGdex ${TCGDEX_SET_ID}`);
  const collectorHtml = await getHtml(TCGCOLLECTOR_URL);
  const collectorCards = extractCollectorCards(collectorHtml);
  if (!collectorCards.size) throw new Error('Nenhuma carta numerada encontrada no TCG Collector.');
  if (EXPECTED_COUNT && collectorCards.size !== EXPECTED_COUNT) {
    throw new Error(`TCG Collector retornou ${collectorCards.size}; esperado ${EXPECTED_COUNT}. Índice preservado.`);
  }

  const tcgdexSet = await getJson(`https://api.tcgdex.net/v2/en/sets/${encodeURIComponent(TCGDEX_SET_ID)}`);
  if (!Array.isArray(tcgdexSet.cards) || !tcgdexSet.cards.length) {
    throw new Error(`TCGdex não retornou a lista de cartas para ${TCGDEX_SET_ID}. Índice preservado.`);
  }
  if (tcgdexSet.cards.length !== collectorCards.size) {
    throw new Error(`Divergência de catálogo: TCGdex ${tcgdexSet.cards.length}, TCG Collector ${collectorCards.size}. Índice preservado.`);
  }

  const queue = [...tcgdexSet.cards];
  const records = [];
  const failures = [];
  const workers = Array.from({ length: 5 }, async () => {
    while (queue.length) {
      const brief = queue.shift();
      const localId = numericId(brief.localId);
      const collector = collectorCards.get(localId);
      if (!collector) {
        failures.push(`Carta ${brief.name} (${brief.localId}) sem correspondência no TCG Collector.`);
        continue;
      }
      const cardId = brief.id || `${TCGDEX_SET_ID}-${brief.localId}`;
      const card = await getJson(`https://api.tcgdex.net/v2/en/cards/${encodeURIComponent(cardId)}`);
      if (!['Pokemon', 'Trainer', 'Energy'].includes(card.category)) {
        failures.push(`Categoria inválida em ${cardId}: ${card.category}`);
        continue;
      }
      const number = Number(card.localId ?? brief.localId);
      const types = Array.isArray(card.types) ? card.types : [];
      const isEnergy = card.category === 'Energy';
      // O campo energyType do catálogo pode vir como "Normal" mesmo em
      // Energias Especiais ilustradas. Só é Básica quando o nome é exatamente
      // "Grass Energy", "Basic Grass Energy" etc.; as demais são Especiais.
      const normalizedEnergyName = String(card.name ?? '').normalize('NFD')
        .replace(/[\\u0300-\\u036f]/g, '').trim().toLowerCase();
      const isBasicEnergy = isEnergy &&
        /^(?:basic )?(grass|fire|water|lightning|psychic|fighting|darkness|metal|fairy|dragon|colorless) energy$/.test(normalizedEnergyName);
      const energyCategory = isEnergy ? (isBasicEnergy ? 'Basic' : 'Special') : null;
      const record = {
        collectionId: COLLECTION_ID,
        collectionName: COLLECTION_NAME,
        slug: collector.slug,
        url: collector.url,
        name: card.name || brief.name,
        number: `${number}/${collector.total ?? EXPECTED_COUNT ?? tcgdexSet.cardCount?.total ?? collectorCards.size}`,
        numberSort: number,
        supertype: card.category,
        types,
        stage: card.stage || null,
        evolvesFrom: card.evolveFrom || null,
        trainerSubtype: card.trainerType || null,
        energyCategory,
        energyType: isBasicEnergy ? energyElementalType(card.name, types) : null,
        hp: card.hp ?? null,
        rarity: card.rarity || null,
        file: collector.slug,
        needsReview: (card.category === 'Pokemon' && !types.length) ||
          (card.category === 'Trainer' && !card.trainerType) ||
          (isEnergy && !energyCategory),
      };
      records.push(record);
      console.log(`[CARTA] ${records.length}/${tcgdexSet.cards.length} ${record.number} ${record.name} — ${record.supertype}`);
    }
  });
  await Promise.all(workers);

  if (failures.length) throw new Error(failures.join('\n'));
  if (records.length !== collectorCards.size) {
    throw new Error(`Foram montados ${records.length} registros; esperado ${collectorCards.size}. Índice preservado.`);
  }
  if (new Set(records.map(card => card.numberSort)).size !== records.length) {
    throw new Error('Números de carta duplicados. Índice preservado.');
  }
  records.sort((a, b) => a.numberSort - b.numberSort);
  const review = records.filter(card => card.needsReview);
  if (review.length) {
    throw new Error(`${review.length} cartas precisam de revisão; índice preservado: ${review.map(x => x.name).join(', ')}`);
  }

  let previous = { version: 1, cards: [] };
  try {
    previous = JSON.parse(await fs.readFile(OUTPUT, 'utf8'));
    if (!previous || !Array.isArray(previous.cards)) throw new Error('Estrutura de índice inválida.');
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  const kept = previous.cards.filter(card => String(card.collectionId) !== COLLECTION_ID);
  const merged = [...kept, ...records];
  await fs.writeFile(OUTPUT, JSON.stringify({
    version: 1,
    generatedAt: new Date().toISOString(),
    cards: merged,
  }, null, 2) + '\n');
  console.log(JSON.stringify({
    collection: COLLECTION_NAME,
    collectionId: COLLECTION_ID,
    tcgdexSetId: TCGDEX_SET_ID,
    cardsAdded: records.length,
    pokemon: records.filter(x => x.supertype === 'Pokemon').length,
    trainers: records.filter(x => x.supertype === 'Trainer').length,
    energies: records.filter(x => x.supertype === 'Energy').length,
    totalCardsInIndex: merged.length,
    firstCard: records[0].name,
    lastCard: records.at(-1).name,
    output: OUTPUT,
  }, null, 2));
}

main().catch(error => {
  console.error('[ERRO FATAL]', error);
  process.exitCode = 1;
}).finally(async () => {
  try { await client.destroy(); } catch {}
});
