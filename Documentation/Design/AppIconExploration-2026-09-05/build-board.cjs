const fs=require('fs'),path=require('path');
const sharp=require('/Users/euanspencer/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const base=__dirname;
const concepts=JSON.parse(fs.readFileSync(path.join(base,'concepts.json'),'utf8'));
const rows=[{name:'Original',tag:'The starting point',id:'original'},...concepts];
async function main(){
 const original='/Users/euanspencer/CosmoOS-Swift/Resources/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png';
 fs.copyFileSync(original,path.join(base,'original.png'));
 let defs='',tiles='';
 for(const [i,c] of rows.entries()){
  const x=100+(i%3)*540,y=190+Math.floor(i/3)*570;
  const file=c.id==='original'?original:path.join(base,'png',`${c.id}-1024.png`);
  const data=fs.readFileSync(file).toString('base64');
  defs+=`<clipPath id="tile${i}"><rect x="${x}" y="${y}" width="360" height="360" rx="81"/></clipPath>`;
  tiles+=`<image href="data:image/png;base64,${data}" x="${x}" y="${y}" width="360" height="360" clip-path="url(#tile${i})"/>`;
  tiles+=`<text x="${x}" y="${y+410}" font-family="Helvetica" font-size="29" fill="#234735">${i?'0'+i+'  ':''}${c.name}</text><text x="${x}" y="${y+449}" font-family="Helvetica" font-size="21" fill="#6C756C">${c.tag}</text>`;
  for(const [j,size] of [60,40,29].entries()){
   const sx=x+400,sy=y+24+j*112;
   defs+=`<clipPath id="s${i}-${j}"><rect x="${sx}" y="${sy}" width="${size}" height="${size}" rx="${size*.225}"/></clipPath>`;
   tiles+=`<image href="data:image/png;base64,${data}" x="${sx}" y="${sy}" width="${size}" height="${size}" clip-path="url(#s${i}-${j})"/><text x="${sx}" y="${sy+size+24}" font-family="Helvetica" font-size="14" fill="#7B8177">${size}px</text>`;
  }
 }
 const svg=`<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1800" height="1360" viewBox="0 0 1800 1360"><defs>${defs}</defs><rect width="1800" height="1360" fill="#E8E6DF"/><text x="100" y="83" font-family="Georgia" font-size="48" fill="#213C2E">Cosmo. A living system of thought.</text><text x="102" y="129" font-family="Helvetica" font-size="22" fill="#6C756C">APP ICON STUDY    /    FIVE FLAT VECTOR DIRECTIONS    /    SEPTEMBER 2026</text>${tiles}</svg>`;
 await sharp(Buffer.from(svg)).png().toFile(path.join(base,'comparison.png'));
}
main();
