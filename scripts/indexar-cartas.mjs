import fs from 'node:fs/promises';
import path from 'node:path';
import { GhostClient } from 'ghostfetch';
import * as cheerio from 'cheerio';

const ROOT='/sdcard/meuapp', OUT=path.join(ROOT,'dados_cartas.json');
const REPORT='/sdcard/Download/relatorio_indice_cartas.json';
const INPUT=path.join(process.cwd(),'tcgcollector_362_ids.txt');
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const norm=s=>String(s||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]+/g,' ').trim();
const readJson=async(p,d)=>{try{return JSON.parse(await fs.readFile(p,'utf8'))}catch{return d}};
const slugOf=u=>{try{return new URL(u).pathname.split('/').filter(Boolean).at(-1)||''}catch{return ''}};

let client;
function getClient(){if(!client)client=new GhostClient({browser:'Chrome_131',timeout:90000});return client}
async function fetchHtml(url){
  let last;
  for(let i=1;i<=5;i++){
    try{const r=await getClient().fetch(url,{method:'GET'});if(!r.ok)throw Error('HTTP '+r.status);return await r.text()}
    catch(e){last=e;try{if(client)await client.destroy()}catch{}client=new GhostClient({browser:'Chrome_131',timeout:90000});await sleep(1500*i)}
  }
  throw last;
}
function parseCard($,url){
  const body=$('body').text().replace(/\s+/g,' ').trim();
  const title=$('h1').first().text().trim()||$('meta[property="og:title"]').attr('content')||$('title').text().trim();
  const low=norm(body), slug=slugOf(url);
  const num=body.match(/\b(\d{1,4})\s*\/\s*(\d{1,4})\b/);
  const known=['Grass','Fire','Water','Lightning','Psychic','Fighting','Darkness','Metal','Fairy','Dragon','Colorless'];
  const types=[];
  $('img,[title],[aria-label],[alt]').each((_,el)=>{
    const v=[$(el).attr('alt'),$(el).attr('title'),$(el).attr('aria-label'),$(el).attr('data-type'),$(el).attr('class')].filter(Boolean).join(' ');
    for(const t of known)if(norm(v).includes(norm(t))&&!types.includes(t))types.push(t);
  });
  let supertype='Unknown';
  if(/\btrainer\b/.test(low))supertype='Trainer';
  else if(/\b(?:basic|special)\s+energy\b/.test(low))supertype='Energy';
  else if(/\bpokemon\b/.test(low))supertype='Pokemon';
  else if(/\benergy\b/.test(low))supertype='Energy';
  const sm=body.match(/\b(Basic|Stage\s*1|Stage\s*2|Level[- ]?Up|Restored|BREAK|LEGEND|VMAX|VSTAR|V-UNION)\s*(?:Pok[eé]mon)?\b/i);
  let stage=sm?sm[1].replace(/\s+/g,' ').replace(/^./,c=>c.toUpperCase()):null;
  const em=body.match(/Evolves\s+from\s+([A-Za-z0-9'’ .-]+?)(?=\s+(?:HP|Pok[eé]mon|Stage|Type|Weakness|Resistance|Retreat|Expansion|Card number|Illustrator)\b|$)/i);
  const evolvesFrom=em?em[1].trim().replace(/[.,;]+$/,''):null;
  let trainerSubtype=null;
  if(supertype==='Trainer'){
    if(/\bpokemon\s+tool\b/i.test(body))trainerSubtype='Pokemon Tool';
    else if(/\bstadium\b/i.test(body))trainerSubtype='Stadium';
    else if(/\bsupporter\b/i.test(body))trainerSubtype='Supporter';
    else if(/\bitem\b/i.test(body))trainerSubtype='Item';
  }
  let energyCategory=null;
  if(supertype==='Energy')energyCategory=/special\s+energy/i.test(body)?'Special':(/basic\s+energy/i.test(body)?'Basic':'Unknown');
  const name=title.split('|')[0].replace(/\s*-\s*TCG Collector.*$/i,'').trim();
  const record={slug,url,name,number:num?num[1]+'/'+num[2]:null,numberSort:num?Number(num[1]):null,
    supertype,types,stage,evolvesFrom,trainerSubtype,energyCategory,
    energyType:supertype==='Energy'?(types[0]||null):null};
  record.needsReview=supertype==='Unknown'||(supertype==='Pokemon'&&(!stage||!types.length))||
    (supertype==='Trainer'&&!trainerSubtype)||(supertype==='Energy'&&(!energyCategory||energyCategory==='Unknown'));
  return record;
}
async function main(){
  const dirs=await fs.readdir(ROOT,{withFileTypes:true});
  const base=dirs.find(x=>x.isDirectory()&&norm(x.name)==='tcg fisico');
  if(!base)throw Error('Pasta tcg físico não encontrada em /sdcard/meuapp');
  const root=path.join(ROOT,base.name);
  let sets=[];
  try{sets=(await fs.readFile(INPUT,'utf8')).split(/\r?\n/).map(line=>{const p=line.split('\t');return{id:p[0]?.trim(),name:p[1]?.trim(),url:p[2]?.trim()}}).filter(x=>x.id&&/^https?:\/\//i.test(x.url||''))}catch{}
  if(!sets.length)sets=(await readJson(path.join(ROOT,'logos/catalogo.json'),[])).map(x=>({id:String(x.id),name:x.nome,url:x.pagina})).filter(x=>x.id&&x.url);
  sets=[...new Map(sets.map(x=>[x.id,x])).values()];
  if(!sets.length)throw Error('Não encontrei coleções no catálogo nem em tcgcollector_362_ids.txt');
  await fs.mkdir('/sdcard/Download',{recursive:true});
  const old=await readJson(OUT,{cards:[]}), index=new Map((old.cards||[]).map(x=>[x.collectionId+'|'+x.slug,x]));
  let setCount=0,cardCount=0,errorCount=0;
  try{
    for(const set of sets){
      const entries=await fs.readdir(root,{withFileTypes:true});
      const folder=entries.find(x=>x.isDirectory()&&x.name.startsWith(set.id+'_'));
      if(!folder)continue;
      const folderPath=path.join(root,folder.name);
      const files=(await fs.readdir(folderPath,{recursive:true})).filter(x=>/\.(jpe?g|png|webp|gif)$/i.test(String(x)));
      const bySlug=new Map();
      for(const f of files){const baseName=path.basename(String(f)),slug=baseName.split('__')[0];if(!bySlug.has(slug))bySlug.set(slug,[]);bySlug.get(slug).push(String(f))}
      console.log('\n['+set.id+'] '+(set.name||folder.name));
      let html;
      try{html=await fetchHtml(set.url)}catch(e){errorCount++;console.log('Falha na coleção: '+e.message);continue}
      setCount++;
      const $=cheerio.load(html), links=new Map();
      $('a[href*="/cards/"]').each((_,el)=>{const href=$(el).attr('href');if(!href)return;const url=new URL(href,set.url).href.split('?')[0],slug=slugOf(url);if(slug)links.set(slug,url)});
      console.log('Páginas de cartas: '+links.size);
      for(const [slug,url] of links){
        cardCount++;
        const key=set.id+'|'+slug, filesForCard=bySlug.get(slug)||[];
        let record=index.get(key);
        if(!record||record.needsReview||!record.name){
          try{record={...parseCard(cheerio.load(await fetchHtml(url)),url),collectionId:String(set.id),collectionName:set.name||folder.name,files:filesForCard};index.set(key,record)}
          catch(e){errorCount++;record=record||{slug,url,collectionId:String(set.id),collectionName:set.name||folder.name,supertype:'Unknown',types:[],files:filesForCard,needsReview:true,error:String(e)};record.files=filesForCard;index.set(key,record)}
        }else{record.files=filesForCard;index.set(key,record)}
        if(cardCount%20===0){await fs.writeFile(OUT,JSON.stringify({version:1,generatedAt:new Date().toISOString(),cards:[...index.values()]},null,2));console.log('Progresso: '+cardCount+' páginas; '+errorCount+' erros')}
        await sleep(900);
      }
      await fs.writeFile(OUT,JSON.stringify({version:1,generatedAt:new Date().toISOString(),cards:[...index.values()]},null,2));
    }
  }finally{try{if(client)await client.destroy()}catch{}}
  const cards=[...index.values()],matched=new Set(cards.flatMap(c=>(c.files||[]).map(f=>c.collectionId+'|'+path.basename(f))));
  const unmatched=[];
  for(const set of sets){
    const es=await fs.readdir(root,{withFileTypes:true}),folder=es.find(x=>x.isDirectory()&&x.name.startsWith(set.id+'_'));if(!folder)continue;
    const fs2=await fs.readdir(path.join(root,folder.name),{recursive:true});
    for(const f of fs2.filter(x=>/\.(jpe?g|png|webp|gif)$/i.test(String(x))))if(!matched.has(set.id+'|'+path.basename(String(f))))unmatched.push({collectionId:set.id,file:String(f)});
  }
  const review=cards.filter(c=>c.needsReview);
  const report={collections:sets.length,collectionPagesRead:setCount,cardPagesFound:cardCount,indexedCards:cards.length,needsReview:review.length,errors:errorCount,imagesWithoutMatch:unmatched.length,unmatchedImages:unmatched.slice(0,500),cardsNeedingReview:review.map(c=>({collectionId:c.collectionId,name:c.name,slug:c.slug,supertype:c.supertype,files:c.files})).slice(0,1000)};
  await fs.writeFile(OUT,JSON.stringify({version:1,generatedAt:new Date().toISOString(),cards},null,2));
  await fs.writeFile(REPORT,JSON.stringify(report,null,2));
  console.log('\nÍNDICE GERADO\n'+JSON.stringify(report,null,2)+'\nArquivo: '+OUT+'\nRelatório: '+REPORT);
}
main().catch(e=>{console.error(e);process.exitCode=1});
