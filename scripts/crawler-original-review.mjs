import { GhostClient } from "ghostfetch";
import * as cheerio from "cheerio";
import fs from "node:fs";
import path from "node:path";

const BASE = "https://www.tcgcollector.com";
const INPUT = "tcgcollector_362_ids.txt";
const OUTPUT = "TCG_Collector";
const STATE = path.join(OUTPUT, "estado");
const WAIT = 900;

fs.mkdirSync(OUTPUT, { recursive: true });
fs.mkdirSync(STATE, { recursive: true });

if (!fs.existsSync(INPUT)) {
  console.error("ERRO: arquivo tcgcollector_362_ids.txt não encontrado.");
  process.exit(1);
}

const sets = fs.readFileSync(INPUT, "utf8")
  .split(/\r?\n/)
  .filter(Boolean)
  .map(line => {
    const [id, name, url] = line.split("\t");
    return { id, name, url };
  });

const doneFile = path.join(STATE, "colecoes_concluidas.json");
const done = new Set(
  fs.existsSync(doneFile)
    ? JSON.parse(fs.readFileSync(doneFile, "utf8"))
    : []
);

const failuresFile = path.join(STATE, "falhas.jsonl");

const INDEX_LOCAL = path.join(STATE, "dados_cartas.json");
const INDEX_ANDROID = "/sdcard/meuapp/dados_cartas.json";
const normalizeText = value => String(value || "")
  .normalize("NFD").replace(/[\u0300-\u036f]/g, "")
  .toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();

let cardIndex = new Map();
for (const file of [INDEX_LOCAL, INDEX_ANDROID]) {
  try {
    const parsed = JSON.parse(fs.readFileSync(file, "utf8"));
    for (const card of parsed.cards || []) {
      cardIndex.set(String(card.collectionId) + "|" + card.slug, card);
    }
    break;
  } catch {}
}

function extractCardMetadata(html, cardUrl, set, filename) {
  const $ = cheerio.load(html);
  const body = $("body").text().replace(/\s+/g, " ").trim();
  const normalized = normalizeText(body);
  const slug = safeName(new URL(cardUrl).pathname.split("/").filter(Boolean).pop());
  const title = $("h1").first().text().trim() ||
    $('meta[property="og:title"]').attr("content") || $("title").text().trim();
  const numberMatch = body.match(/\b(\d{1,4})\s*\/\s*(\d{1,4})\b/);
  const knownTypes = ["Grass", "Fire", "Water", "Lightning", "Psychic",
    "Fighting", "Darkness", "Metal", "Fairy", "Dragon", "Colorless"];
  const types = [];
  $("[alt], [title], [aria-label], [data-type], img").each((_, el) => {
    const value = [$(el).attr("alt"), $(el).attr("title"),
      $(el).attr("aria-label"), $(el).attr("data-type"),
      $(el).attr("class")].filter(Boolean).join(" ");
    for (const type of knownTypes) {
      if (normalizeText(value).includes(normalizeText(type)) && !types.includes(type)) {
        types.push(type);
      }
    }
  });

  let supertype = "Unknown";
  if (/\btrainer\b/.test(normalized)) supertype = "Trainer";
  else if (/\b(basic|special) energy\b/.test(normalized) || /\benergy\b/.test(normalized)) supertype = "Energy";
  else if (/\bpokemon\b/.test(normalized)) supertype = "Pokemon";

  const stageMatch = body.match(/\b(Basic|Stage\s*1|Stage\s*2|Level[- ]?Up|Restored|BREAK|LEGEND|VMAX|VSTAR|V-UNION)\s*(?:Pok[eé]mon)?\b/i);
  const stage = stageMatch ? stageMatch[1].replace(/\s+/g, " ") : null;
  const evolvesMatch = body.match(/Evolves\s+from\s+([A-Za-z0-9'’ .-]+?)(?=\s+(?:HP|Pok[eé]mon|Stage|Type|Weakness|Resistance|Retreat|Expansion|Card number|Illustrator)\b|$)/i);
  const evolvesFrom = evolvesMatch ? evolvesMatch[1].trim().replace(/[.,;]+$/, "") : null;

  let trainerSubtype = null;
  if (supertype === "Trainer") {
    if (/pokemon tool/i.test(body)) trainerSubtype = "Pokemon Tool";
    else if (/\bstadium\b/i.test(body)) trainerSubtype = "Stadium";
    else if (/\bsupporter\b/i.test(body)) trainerSubtype = "Supporter";
    else if (/\bitem\b/i.test(body)) trainerSubtype = "Item";
  }
  const energyCategory = supertype === "Energy"
    ? (/special energy/i.test(body) ? "Special" : (/basic energy/i.test(body) ? "Basic" : "Unknown"))
    : null;

  const record = {
    collectionId: String(set.id),
    collectionName: set.name,
    slug,
    url: cardUrl,
    name: title.split("|")[0].replace(/\s*-\s*TCG Collector.*$/i, "").trim(),
    number: numberMatch ? numberMatch[1] + "/" + numberMatch[2] : null,
    numberSort: numberMatch ? Number(numberMatch[1]) : null,
    supertype,
    types,
    stage,
    evolvesFrom,
    trainerSubtype,
    energyCategory,
    energyType: supertype === "Energy" ? (types[0] || null) : null,
    file: filename || null,
    needsReview: supertype === "Unknown" ||
      (supertype === "Pokemon" && (!stage || !types.length)) ||
      (supertype === "Trainer" && !trainerSubtype) ||
      (supertype === "Energy" && energyCategory === "Unknown")
  };
  return record;
}

function saveCardIndex() {
  const payload = JSON.stringify({
    version: 1,
    generatedAt: new Date().toISOString(),
    cards: [...cardIndex.values()]
  }, null, 2);
  fs.writeFileSync(INDEX_LOCAL, payload);
  try {
    fs.mkdirSync(path.dirname(INDEX_ANDROID), { recursive: true });
    fs.writeFileSync(INDEX_ANDROID, payload);
  } catch (error) {
    console.log("  Índice salvo localmente; pasta Android indisponível: " + error.message);
  }
}

let client = new GhostClient({
  browser: "Chrome_131",
  timeout: 45000
});


const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

async function resetClient() {
  try {
    await client.destroy();
  } catch {}

  client = new GhostClient({
    browser: "Chrome_131",
    timeout: 90000
  });
}

async function fetchWithRetry(url, options = {}) {
  let attempt = 0;

  while (true) {
    attempt++;

    try {
      const response = await client.fetch(url, options);

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }

      return response;
    } catch (error) {
      console.log(`  TENTATIVA ${attempt} FALHOU: ${error.message}`);
      console.log("  Nova tentativa em 5 segundos. Sem limite de tentativas.");

      try {
        await resetClient();
      } catch (resetError) {
        console.log(`  ERRO AO REINICIAR: ${resetError.message}`);
      }

      await sleep(5000);
    }
  }
}

function safeName(value) {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-zA-Z0-9_-]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function logFailure(type, info, error) {
  const entry = {
    date: new Date().toISOString(),
    type,
    info,
    error: String(error?.message || error)
  };

  fs.appendFileSync(failuresFile, JSON.stringify(entry) + "\n");
  console.log("  FALHA:", entry.error);
}

async function getHtml(url) {
  const response = await fetchWithRetry(url, {
    headers: {
      "Referer": BASE + "/"
    }
  });

  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`);
  }

  return await response.text();
}

function extractCardLinks(html) {
  const $ = cheerio.load(html);
  const links = new Set();

  $(
    ".card-image-grid-item a[href], " +
    ".card-grid-item a[href], " +
    "a[href*='/cards/']"
  ).each((_, element) => {
    let href = $(element).attr("href");
    if (!href) return;

    try {
      const url = new URL(href, BASE);
      if (
        url.hostname === "www.tcgcollector.com" &&
        (/^\/cards\/\d+\/[^/]+/.test(url.pathname))
      ) {
        url.search = "";
        url.hash = "";
        links.add(url.href);
      }
    } catch {}
  });

  return [...links];
}

function extractImage(html) {
  const $ = cheerio.load(html);

  let image =
    $('meta[property="og:image"]').attr("content") ||
    $('meta[name="twitter:image"]').attr("content") ||
    $('img[src*="/cards/"]').first().attr("src") ||
    $('img[data-src*="/cards/"]').first().attr("data-src");

  if (!image) return null;

  try {
    return new URL(image, BASE).href;
  } catch {
    return null;
  }
}

function imageExtension(url, contentType) {
  const pathname = new URL(url).pathname;
  const ext = path.extname(pathname).toLowerCase();

  if ([".jpg", ".jpeg", ".png", ".webp", ".gif"].includes(ext)) {
    return ext;
  }

  if (contentType.includes("png")) return ".png";
  if (contentType.includes("webp")) return ".webp";
  if (contentType.includes("gif")) return ".gif";

  return ".jpg";
}

function validImage(buffer) {
  return (
    buffer.length > 100 &&
    (
      buffer.subarray(0, 3).toString("hex") === "ffd8ff" ||
      buffer.subarray(0, 8).toString("hex") === "89504e470d0a1a0a" ||
      buffer.subarray(0, 4).toString() === "RIFF" ||
      buffer.subarray(0, 3).toString() === "GIF"
    )
  );
}

async function downloadImage(url, destination) {
  if (fs.existsSync(destination)) return "skip";

  const response = await fetchWithRetry(url, {
    headers: {
      "Referer": BASE + "/"
    }
  });

  if (!response.ok) {
    throw new Error(`Download HTTP ${response.status}`);
  }

  const contentType = (
    response.headers.get("content-type") || ""
  ).toLowerCase();

  if (!contentType.startsWith("image/")) {
    throw new Error(`Resposta não é imagem: ${contentType}`);
  }

  const buffer = Buffer.from(await response.arrayBuffer());

  if (!validImage(buffer)) {
    throw new Error("Arquivo recebido não passou na validação de imagem");
  }

  fs.writeFileSync(destination, buffer);
  return "ok";
}

async function processSet(set) {
  console.log(`\\n========================================`);
  console.log(`COLEÇÃO: ${set.name} | ID ${set.id}`);
  console.log(`========================================`);

  const folder = path.join(
    OUTPUT,
    `${set.id}_${safeName(set.name)}`
  );

  fs.mkdirSync(folder, { recursive: true });

  const listingUrl =
    `${set.url}?setCardCountMode=anyCardVariant` +
    `&releaseDateOrder=oldToNew&displayAs=images`;

  let links = [];

  while (true) {
    try {
      const html = await getHtml(listingUrl);
      links = extractCardLinks(html);

      if (!links.length) {
        throw new Error("Nenhum link de carta encontrado na página.");
      }

      break;
    } catch (error) {
      console.log(`  ERRO NA LISTA DA COLEÇÃO: ${error.message}`);
      console.log("  Tentando novamente em 5 segundos...");
      try { await resetClient(); } catch {}
      await sleep(5000);
    }
  }

  console.log(`Cartas encontradas: ${links.length}`);

  let downloaded = 0;
  let skipped = 0;
  let errors = 0;

  for (let i = 0; i < links.length; i++) {
    const cardUrl = links[i];

    console.log(`\\n[${i + 1}/${links.length}] ${cardUrl}`);

    while (true) {
      try {
        const cardHtml = await getHtml(cardUrl);
        const imageUrl = extractImage(cardHtml);

        if (!imageUrl) {
          throw new Error("Imagem não encontrada na página da carta");
        }

        const cardSlug = safeName(
          new URL(cardUrl).pathname.split("/").filter(Boolean).pop()
        );

        const imageBase = path.basename(
          new URL(imageUrl).pathname
        );

        const ext = imageExtension(
          imageUrl,
          new URL(imageUrl).pathname
        );

        const baseWithoutExt = path.basename(
          imageBase,
          path.extname(imageBase)
        );

        const filename = `${cardSlug}__${safeName(baseWithoutExt)}${ext}`;
        const destination = path.join(folder, filename);

        const result = await downloadImage(imageUrl, destination);

        const metadata = extractCardMetadata(cardHtml, cardUrl, set, filename);
        const indexKey = String(set.id) + "|" + metadata.slug;
        const previous = cardIndex.get(indexKey) || {};
        cardIndex.set(indexKey, { ...previous, ...metadata });
        saveCardIndex();

        if (result === "ok") {
          downloaded++;
          console.log(`  BAIXADA: ${filename}`);
        } else {
          skipped++;
          console.log(`  JÁ EXISTIA: ${filename}`);
        }

        break;
      } catch (error) {
        console.log(`  CARTA NÃO CONCLUÍDA: ${error.message}`);
        console.log("  A carta não será pulada. Nova tentativa em 5 segundos...");

        try {
          await resetClient();
        } catch {}

        await sleep(5000);
      }
    }

    await sleep(WAIT);
  }

  console.log(
    `\\nResultado ${set.name}: ${downloaded} novas, ` +
    `${skipped} existentes, ${errors} falhas.`
  );

  fs.writeFileSync(
    path.join(folder, "cartas.json"),
    JSON.stringify({
      id: set.id,
      name: set.name,
      listingUrl,
      cards: links
    }, null, 2)
  );

  if (errors === 0) {
    done.add(set.id);
    fs.writeFileSync(doneFile, JSON.stringify([...done], null, 2));
  } else {
    done.delete(set.id);
    fs.writeFileSync(doneFile, JSON.stringify([...done], null, 2));
    console.log("COLEÇÃO INCOMPLETA: será retomada posteriormente.");
  }
}

async function indexExistingCollections() {
  // Três trabalhadores independentes: acelera sem sobrecarregar o Android
  // nem compartilhar reinicializações do GhostClient entre requisições.
  const CONCURRENCY = 3;
  const REQUEST_GAP = 900;
  const roots = [OUTPUT, "/sdcard/meuapp/tcg fisico", "/sdcard/Download/TCG_Collector"]
    .filter(root => fs.existsSync(root));

  const foldersById = new Map();
  for (const root of roots) {
    for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
      if (!entry.isDirectory() || entry.name === "estado") continue;
      const folder = path.join(root, entry.name);
      const manifest = path.join(folder, "cartas.json");
      if (!fs.existsSync(manifest)) continue;
      try {
        const data = JSON.parse(fs.readFileSync(manifest, "utf8"));
        const id = String(data.id || entry.name.split("_")[0]);
        if (!foldersById.has(id)) {
          foldersById.set(id, { folder, data, name: data.name || entry.name });
        }
      } catch (error) {
        console.log("Manifesto inválido: " + manifest + " — " + error.message);
      }
    }
  }

  const tasks = [];
  for (const [id, item] of foldersById) {
    const set = { id, name: item.name };
    const files = fs.readdirSync(item.folder);
    const urls = Array.isArray(item.data.cards) ? item.data.cards : [];
    for (const cardUrl of urls) {
      try {
        const slug = safeName(new URL(cardUrl).pathname.split("/").filter(Boolean).pop());
        const existing = cardIndex.get(id + "|" + slug);
        // Não refaz consultas já concluídas; tenta novamente apenas dados incompletos.
        if (existing && !existing.needsReview && existing.supertype !== "Unknown") continue;
        const filename = files.find(name => name.startsWith(slug + "__")) || null;
        tasks.push({ set, cardUrl, slug, filename });
      } catch {}
    }
  }

  console.log("Coleções únicas encontradas: " + foldersById.size);
  console.log("Cartas que precisam de indexação/verificação: " + tasks.length);
  console.log("Concorrência: " + CONCURRENCY + " requisições simultâneas.");

  let cursor = 0;
  let processed = 0;
  let errors = 0;

  async function worker(workerId) {
    let workerClient = new GhostClient({
      browser: "Chrome_131",
      timeout: 90000
    });

    async function workerHtml(url) {
      let attempt = 0;
      while (true) {
        attempt++;
        try {
          const response = await workerClient.fetch(url, {
            headers: { Referer: BASE + "/" }
          });
          if (!response.ok) throw new Error("HTTP " + response.status);
          return await response.text();
        } catch (error) {
          console.log("[Worker " + workerId + "] tentativa " + attempt +
            " falhou: " + error.message + ". Reiniciando em 5 segundos.");
          try { await workerClient.destroy(); } catch {}
          await sleep(5000);
          workerClient = new GhostClient({
            browser: "Chrome_131",
            timeout: 90000
          });
        }
      }
    }

    try {
      while (true) {
        const taskIndex = cursor++;
        if (taskIndex >= tasks.length) break;
        const task = tasks[taskIndex];

        try {
          const html = await workerHtml(task.cardUrl);
          const metadata = extractCardMetadata(
            html, task.cardUrl, task.set, task.filename
          );
          cardIndex.set(task.set.id + "|" + task.slug, metadata);
          processed++;

          if (processed % 10 === 0) {
            saveCardIndex();
            console.log("Metadados processados nesta execução: " + processed +
              " | total no índice: " + cardIndex.size);
          }
        } catch (error) {
          errors++;
          console.log("[Worker " + workerId + "] ERRO " +
            task.cardUrl + ": " + error.message);
        }

        await sleep(REQUEST_GAP);
      }
    } finally {
      try { await workerClient.destroy(); } catch {}
    }
  }

  await Promise.all(
    Array.from({ length: Math.min(CONCURRENCY, tasks.length) }, (_, i) => worker(i + 1))
  );

  saveCardIndex();
  const cards = [...cardIndex.values()];
  const report = {
    generatedAt: new Date().toISOString(),
    collections: foldersById.size,
    indexedCards: cards.length,
    processedThisRun: processed,
    pendingReview: cards.filter(card => card.needsReview).length,
    errors
  };
  const reportPath = path.join(STATE, "relatorio_indice_cartas.json");
  fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
  console.log("\nÍNDICE FINALIZADO");
  console.log(JSON.stringify(report, null, 2));
  console.log("Índice: " + INDEX_ANDROID);
  console.log("Cópia local: " + INDEX_LOCAL);
}
async function main() {
  if (process.argv.includes("--index-existing")) {
    try { await indexExistingCollections(); }
    finally { await client.destroy(); }
    return;
  }

  const limitArg = process.argv.find(arg => arg.startsWith("--limit="));
  const limit = limitArg
    ? Number(limitArg.split("=")[1])
    : Infinity;

  const pending = sets.filter(set => !done.has(String(set.id)));
    const idArg = process.argv.find(arg => arg.startsWith("--id="));
  const selected = idArg
    ? pending.filter(set => String(set.id) === idArg.split("=")[1])
    : pending;
  const queue = selected.slice(0, limit);

  console.log("TCG COLLECTOR CRAWLER");
  console.log(`Coleções na lista: ${sets.length}`);
  console.log(`Já concluídas: ${done.size}`);
  console.log(`Nesta execução: ${queue.length}`);

  try {
    for (const set of queue) {
      try {
        await processSet(set);
      } catch (error) {
        logFailure("colecao", {
          id: set.id,
          name: set.name,
          url: set.url
        }, error);
      }

      await sleep(1500);
    }
  } finally {
    await client.destroy();
  }

  console.log("\nPROCESSAMENTO ENCERRADO.");
  console.log(`Coleções concluídas: ${done.size}/${sets.length}`);
  console.log(`Falhas registradas em: ${failuresFile}`);
}

main().catch(error => {
  console.error("ERRO FATAL:", error);
  process.exitCode = 1;
});
