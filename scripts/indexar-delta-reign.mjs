import fs from 'node:fs/promises';
import * as cheerio from 'cheerio';
import { GhostClient } from 'ghostfetch';

const COLLECTION_ID = String(process.env.COLLECTION_ID ?? '').trim();
const COLLECTION_NAME = String(process.env.COLLECTION_NAME ?? '').trim();
const COLLECTION_SLUG = String(process.env.COLLECTION_SLUG ?? COLLECTION_NAME.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')).trim();
const TCGCOLLECTOR_URL = String(process.env.TCGCOLLECTOR_URL ?? (COLLECTION_ID && COLLECTION_SLUG ? `https://www.tcgcollector.com/sets/${COLLECTION_ID}/${COLLECTION_SLUG}?setCardCountMode=anyCardVariant` : '')).trim();
const EXPECTED_COUNT = Number(process.env.EXPECTED_COUNT ?? 0) || null;
if (!COLLECTION_ID || !COLLECTION_NAME || !TCGCOLLECTOR_URL) {
  throw new Error('Informe COLLECTION_ID, COLLECTION_NAME e, opcionalmente, COLLECTION_SLUG/TCGCOLLECTOR_URL.');
}
const OUTPUT = 'assets/data/dados_cartas.json';
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
let client = new GhostClient({ browser: 'Chrome_131', timeout: 60000 });

async function resetClient() {
  try { await client.destroy(); } catch {}
  client = new GhostClient({ browser: 'Chrome_131', timeout: 60000 });
}

async function getText(url) {
  const maxAttempts = 3;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const startedAt = Date.now();
    console.log(`[HTTP] Tentativa ${attempt}/${maxAttempts}: ${url}`);
    try {
      const response = await client.fetch(url, {
        headers: {
          'Referer': 'https://www.tcgcollector.com/',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8'
        }
      });
      if (!response.ok) throw new Error(`HTTP ${response.status} em ${url}`);
      const html = await response.text();
      console.log(`[HTTP] OK em ${Math.round((Date.now() - startedAt) / 1000)}s; ${html.length} caracteres recebidos.`);
      return html;
    } catch (error) {
      console.error(`[HTTP] Falha ${attempt}/${maxAttempts} após ${Math.round((Date.now() - startedAt) / 1000)}s: ${error.message}`);
      if (attempt === maxAttempts) {
        throw new Error(`Não foi possível acessar ${url} após ${maxAttempts} tentativas. Último erro: ${error.message}`);
      }
      console.log('[HTTP] Reiniciando GhostFetch; nova tentativa em 5 segundos.');
      try { await resetClient(); } catch (resetError) {
        console.error(`[HTTP] Falha ao reiniciar GhostFetch: ${resetError.message}`);
      }
      await sleep(5000);
    }
  }
  throw new Error(`Falha inesperada ao acessar ${url}`);
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
    if (localId) cards.set(numericId(localId), { slug, url, total: total ? Number(total) : null });
  });
  return cards;
}
const KNOWN_TYPES = new Set(['Grass','Fire','Water','Lightning','Psychic','Fighting','Darkness','Metal','Fairy','Dragon','Colorless']);
function extractCardDetails(html, collector) {
  const $ = cheerio.load(html);
  const body = $('body').text().replace(/\s+/g, ' ').trim();
  const name = $('h1').first().text().trim();
  if (!name) throw new Error(`Nome não encontrado em ${collector.url}`);
  const categoryMatch = body.match(/\bHP\s*\d+\s*(Pokémon|Trainer|Energy)\b/i) ?? body.match(/\b(Trainer|Energy)\b/i) ?? body.match(/\bPokémon\b/i);
  const categoryLabel = categoryMatch?.[1] ?? categoryMatch?.[0] ?? '';
  const category = /^Pokémon$/i.test(categoryLabel) ? 'Pokemon' : (/^Trainer$/i.test(categoryLabel) ? 'Trainer' : (/^Energy$/i.test(categoryLabel) ? 'Energy' : 'Unknown'));
  const types = [...new Set($('img[alt]').map((_, el) => $(el).attr('alt')?.trim()).get().filter(x => KNOWN_TYPES.has(x)))];
  const stageMatch = body.match(/\b(Basic|Stage 1|Stage 2|VMAX|VSTAR|V-UNION|MEGA|BREAK)\b/i);
  const stage = stageMatch ? stageMatch[1] : null;
  const hpMatch = body.match(/\bHP\s*(\d+)\b/i);
  const rarityNames = ['Special Illustration Rare','Illustration Rare','Hyper Rare','Ultra Rare','Double Rare','Shiny Rare','Rare Holo','Rare','Uncommon','Common','Promo'];
  const rarity = rarityNames.find(x => body.toLowerCase().includes(x.toLowerCase())) ?? null;
  const trainerSubtype = category === 'Trainer'
    ? (['Pokémon Tool','Item','Supporter','Stadium','Tool'].find(x => body.toLowerCase().includes(x.toLowerCase())) ?? null)
    : null;
  const energyCategory = category === 'Energy' ? (/Special Energy/i.test(body) ? 'Special' : 'Basic') : null;
  const energyType = category === 'Energy' ? (types[0] ?? null) : null;
  const numberMatch = body.match(/(\d{1,4})\s*\/\s*(\d{1,4})/);
  const number = numberMatch ? Number(numberMatch[1]) : Number(collector.localId);
  const total = numberMatch ? Number(numberMatch[2]) : collector.total;
  return { name, category, types, stage, rarity, trainerSubtype, energyCategory, energyType, hp: hpMatch ? Number(hpMatch[1]) : null, number, total };
}

async function main() {
  console.log(`[INÍCIO] Indexando ${COLLECTION_NAME} (ID ${COLLECTION_ID}). Meta: ${EXPECTED_COUNT ?? 'não informada'} cartas.`);
  console.log(`[INÍCIO] Página da coleção: ${TCGCOLLECTOR_URL}`);
  const html = await getText(TCGCOLLECTOR_URL);
  const collectorCards = extractCollectorCards(html);
  if (!collectorCards.size) throw new Error('Nenhuma carta numerada foi encontrada na página do TCG Collector.');
  if (EXPECTED_COUNT && collectorCards.size !== EXPECTED_COUNT) {
    throw new Error(`TCG Collector retornou ${collectorCards.size} cartas; esperado ${EXPECTED_COUNT}. Índice não será alterado.`);
  }

  console.log(`[COLEÇÃO] ${collectorCards.size} cartas encontradas. Iniciando leitura individual.`);
  const details = [];
  const queue = [...collectorCards.entries()];
  const workers = Array.from({ length: 1 }, async () => {
    while (queue.length) {
      const [localId, collector] = queue.shift();
      console.log(`[PROGRESSO] ${details.length + 1}/${collectorCards.size} — lendo carta ${localId}: ${collector.url}`);
      const cardHtml = await getText(collector.url);
      details.push({ localId, collector, ...extractCardDetails(cardHtml, { ...collector, localId }) });
      console.log(`[PROGRESSO] ${details.length}/${collectorCards.size} concluídas: ${details.at(-1).name}`);
      await sleep(1200);
    }
  });
  await Promise.all(workers);
  if (details.length !== collectorCards.size) throw new Error(`Foram extraídas ${details.length} cartas; esperado ${collectorCards.size}.`);

  const records = [];
  for (const card of details) {
    const localId = numericId(card.localId);
    records.push({
      collectionId: COLLECTION_ID,
      collectionName: COLLECTION_NAME,
      slug: card.collector.slug,
      url: card.collector.url,
      name: card.name,
      number: `${String(card.number).padStart(3, '0')}/${card.total ?? Math.max(...details.map(x => x.total ?? x.number))}`,
      numberSort: card.number,
      supertype: card.category,
      types: card.types,
      stage: card.stage,
      evolvesFrom: null,
      trainerSubtype: card.trainerSubtype,
      energyCategory: card.energyCategory,
      energyType: card.energyType,
      hp: card.hp,
      rarity: card.rarity,
      file: card.collector.slug,
      needsReview: !['Pokemon', 'Trainer', 'Energy'].includes(card.category),
    });
  }
  records.sort((a, b) => a.numberSort - b.numberSort);
  if (records.length !== collectorCards.size || new Set(records.map(x => x.numberSort)).size !== records.length) {
    throw new Error('A validação de unicidade/quantidade falhou. Índice não será alterado.');
  }

  let previous = { version: 1, cards: [] };
  try {
    const raw = await fs.readFile(OUTPUT, 'utf8');
    previous = JSON.parse(raw);
    if (!previous || !Array.isArray(previous.cards)) throw new Error('Estrutura de dados_cartas.json inválida.');
  } catch (error) {
    if (error.code !== 'ENOENT') throw new Error(`Não foi possível ler o índice existente; nenhum dado será sobrescrito: ${error.message}`);
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
    cardsAdded: records.length,
    totalCardsInIndex: merged.length,
    firstCard: records[0].name,
    lastCard: records.at(-1).name,
    output: OUTPUT,
  }, null, 2));
}
main().catch(error => { console.error('[ERRO FATAL]', error); process.exitCode = 1; }).finally(async () => {
  try { await client.destroy(); } catch {}
});
