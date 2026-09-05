const fs = require('fs');
const path = require('path');
const sharp = require('/Users/euanspencer/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root = __dirname;
const previous = path.join(root, '../AppIconExploration-2026-09-05');
const ink='#285D46', paper='#F6F2E8', night='#153E30', ivory='#F5F0E3';
const f=n=>Number(n.toFixed(4));
const P=p=>p.map(f).join(' ');

// Elliptical segments are derived from a single analytic ellipse. Subdividing
// to <=45 degrees yields matching tangents at every join and very low error.
function ellipsePoint(cx,cy,rx,ry,rotation,angle){
 const a=angle*Math.PI/180,r=rotation*Math.PI/180;
 return [cx+rx*Math.cos(a)*Math.cos(r)-ry*Math.sin(a)*Math.sin(r),cy+rx*Math.cos(a)*Math.sin(r)+ry*Math.sin(a)*Math.cos(r)];
}
function ellipseDerivative(rx,ry,rotation,angle){
 const a=angle*Math.PI/180,r=rotation*Math.PI/180;
 return [-rx*Math.sin(a)*Math.cos(r)-ry*Math.cos(a)*Math.sin(r),-rx*Math.sin(a)*Math.sin(r)+ry*Math.cos(a)*Math.cos(r)];
}
function ellipseArc(cx,cy,rx,ry,rotation,start,end){
 const n=Math.ceil(Math.abs(end-start)/45), step=(end-start)/n;
 let d=`M ${P(ellipsePoint(cx,cy,rx,ry,rotation,start))}`;
 const joints=[];
 for(let i=0;i<n;i++){
  const a=start+i*step,b=a+step,k=4/3*Math.tan((b-a)*Math.PI/720);
  const p=ellipsePoint(cx,cy,rx,ry,rotation,a),q=ellipsePoint(cx,cy,rx,ry,rotation,b);
  const dp=ellipseDerivative(rx,ry,rotation,a),dq=ellipseDerivative(rx,ry,rotation,b);
  const c1=p.map((v,j)=>v+k*dp[j]),c2=q.map((v,j)=>v-k*dq[j]);
  d+=` C ${P(c1)} ${P(c2)} ${P(q)}`;
  joints.push({start:p,control1:c1,control2:c2,end:q});
 }
 return {d,joints};
}
function leaf(c,variant){
 const tint=variant==='dark'?'#365B45':'#D8E3CE';
 // A true pointed leaf, drawn in its own coordinate system. Both sides are
 // continuous cubics. The long central vein is separate from the paired V veins.
 const a=[602,595],length=282,angle=-43*Math.PI/180;
 const scale=['02-verdant','05-evergreen'].includes(c.id)?1.08:1;
 const pt=(x,y)=>P([a[0]+scale*(x*Math.cos(angle)-y*Math.sin(angle)),a[1]+scale*(x*Math.sin(angle)+y*Math.cos(angle))]);
 const outline=`M${pt(0,0)} C${pt(112,-75)} ${pt(170,-75)} ${pt(length,0)} C${pt(170,75)} ${pt(112,75)} ${pt(0,0)}Z`;
 const inset=`M${pt(34,0)} C${pt(120,-47)} ${pt(162,-47)} ${pt(length-34,0)} C${pt(162,47)} ${pt(120,47)} ${pt(34,0)}Z`;
 const vein=`M${pt(30,0)} L${pt(length-30,0)}`;
 const branches=`M${pt(163,-43)} Q${pt(125,-18)} ${pt(102,0)} Q${pt(125,18)} ${pt(163,43)}`;
 return `<g id="leaf"><path d="${outline}" fill="${c.fg}"/><path d="${inset}" fill="${c.tonal?tint:c.bg}"/><path d="${vein}" fill="none" stroke="${c.fg}" stroke-width="${c.vein}" stroke-linecap="round"/><path d="${branches}" fill="none" stroke="${c.fg}" stroke-width="${c.vein*.7}" stroke-linecap="round" stroke-linejoin="round"/></g>`;
}
const concepts=[
 {id:'01-living-orbit',name:'Living Orbit',description:'A precise restoration of the original.',bg:paper,fg:ink,weight:26,secondary:25,vein:20,seed:40,tonal:false},
 {id:'02-verdant',name:'Verdant',description:'A sculpted leaf with open, legible veins.',bg:paper,fg:ink,weight:32,secondary:27,vein:22,seed:44,tonal:true},
 {id:'03-folio',name:'Folio',description:'A flowing orbital C and a botanical counterpoint.',bg:paper,fg:ink,weight:40,secondary:24,vein:20,seed:41,tonal:false,folio:true},
 {id:'04-meridian',name:'Meridian',description:'Fine orbital geometry and a single gilt seed.',bg:'#F3EFE5',fg:'#2C5945',weight:25,secondary:23,vein:19,seed:40,tonal:false,meridian:true},
 {id:'05-evergreen',name:'Evergreen',description:'A luminous leaf, held in a forest-green orbit.',bg:night,fg:ivory,weight:32,secondary:28,vein:22,seed:44,tonal:true}
];
const geometryAudit=[];
function artwork(original,appearance='default'){
 let c={...original};
 if(appearance==='dark'){c.bg=night;c.fg=ivory;}
 if(appearance==='mono'){c.bg=paper;c.fg=ink;c.tonal=false;}
 const isDark=c.bg===night;
 const horizontal=ellipseArc(507,512,295,119,0,-56,-282);
 const horizontalJoin=ellipsePoint(507,512,295,119,0,-282);
 const horizontalTangent=ellipseDerivative(295,119,0,-282).map(x=>-x);
 const length=Math.hypot(...horizontalTangent);
 const joinControl=horizontalJoin.map((v,i)=>v+36*horizontalTangent[i]/length);
 horizontal.d+=` C ${P(joinControl)} 611.5 586.1 634.91 564.31`;
 const diagonal=ellipseArc(522,509,335,116,-43,['02-verdant','05-evergreen'].includes(c.id)?30:35,-270);
 const diagonalEnd=ellipsePoint(522,509,335,116,-43,-270);
 diagonal.d+=` L${P([diagonalEnd[0]+60*Math.cos(-43*Math.PI/180),diagonalEnd[1]+60*Math.sin(-43*Math.PI/180)])}`;
 const secondaryColor=c.id==='05-evergreen'&&appearance!=='mono'?'#ABC2AB':c.fg;
 const dotColor=c.meridian&&appearance!=='mono'?(isDark?'#CEB77D':'#B19458'):c.fg;
 let glyph='';
 const stroke=(d,width,color=c.fg)=>`<path d="${d}" fill="none" stroke="${color}" stroke-width="${width}" stroke-linecap="round" stroke-linejoin="round"/>`;
 if(c.folio){
  const orbit=ellipseArc(500,511,285,232,-18,-50,-310);
  glyph+=stroke(orbit.d,c.weight);
  glyph+=stroke(ellipseArc(509,522,286,91,-6,204,344).d,c.secondary);
  geometryAudit.push({id:c.id,curve:'C orbit',segments:orbit.joints});
 }else{
  glyph+=stroke(diagonal.d,c.secondary,secondaryColor);
  // Cut only at the rear crossing: a deliberate, flat interlacing gesture.
  glyph+=stroke(ellipseArc(507,512,295,119,0,-217,-234).d,c.weight+18,c.bg);
  glyph+=stroke(horizontal.d,c.weight);
  glyph+=stroke(ellipseArc(522,509,335,116,-43,-78,-86).d,c.secondary+18,c.bg);
  glyph+=stroke(ellipseArc(522,509,335,116,-43,-70,-94).d,c.secondary,secondaryColor);
  geometryAudit.push({id:c.id,curve:'horizontal',segments:horizontal.joints},{id:c.id,curve:'diagonal',segments:diagonal.joints});
 }
 glyph+=leaf(c,isDark?'dark':'light');
 glyph+=`<circle cx="503" cy="510" r="${c.seed}" fill="${dotColor}"/>`;
 return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><title>Cosmo · ${c.name}</title><desc>${c.description} Flat vector artwork.</desc><rect width="1024" height="1024" fill="${c.bg}"/>${glyph}</svg>`;
}
async function main(){
 for(const d of ['svg','png','proofs'])fs.mkdirSync(path.join(root,d),{recursive:true});
 for(const c of concepts){
  for(const mode of ['default','dark','mono']){
   const suffix=mode==='default'?'':'-'+mode;
   const svg=artwork(c,mode);fs.writeFileSync(path.join(root,'svg',c.id+suffix+'.svg'),svg);
   await sharp(Buffer.from(svg),{density:288}).resize(1024,1024).removeAlpha().png().toFile(path.join(root,'png',c.id+suffix+'-1024.png'));
  }
 }
 fs.writeFileSync(path.join(root,'concepts.json'),JSON.stringify(concepts,null,2));
 fs.writeFileSync(path.join(root,'proofs/geometry.json'),JSON.stringify(geometryAudit,null,2));
 let defs='',content='';
 for(const [i,c] of concepts.entries()){
  const x=70+i*358, y=165, size=310;
  const uri='data:image/png;base64,'+fs.readFileSync(path.join(root,'png',c.id+'-1024.png')).toString('base64');
  defs+=`<clipPath id="c${i}"><rect x="${x}" y="${y}" width="${size}" height="${size}" rx="70"/></clipPath>`;
  content+=`<image href="${uri}" x="${x}" y="${y}" width="${size}" height="${size}" clip-path="url(#c${i})"/><text x="${x}" y="${y+size+49}" font-family="Helvetica" font-size="25" fill="#244B38">0${i+1} ${c.name}</text>`;
  for(const [j,s] of [60,40,29].entries()){
   const xx=x+j*100,yy=570;
   defs+=`<clipPath id="s${i}${j}"><rect x="${xx}" y="${yy}" width="${s}" height="${s}" rx="${s*.225}"/></clipPath>`;
   content+=`<image href="${uri}" x="${xx}" y="${yy}" width="${s}" height="${s}" clip-path="url(#s${i}${j})"/><text x="${xx}" y="${yy+85}" font-family="Helvetica" font-size="16" fill="#72786C">${s}px</text>`;
  }
 }
 const board=`<svg xmlns="http://www.w3.org/2000/svg" width="1860" height="735"><defs>${defs}</defs><rect width="1860" height="735" fill="#E8E6DD"/><text x="70" y="75" font-family="Georgia" font-size="42" fill="#244B38">Cosmo — curve &amp; leaf refinement</text><text x="70" y="116" font-family="Helvetica" font-size="18" fill="#72786C">ROUND TWO / CONTINUOUS ORBITS · ARTICULATED VEINS · FLAT VECTOR ARTWORK</text>${content}</svg>`;
 await sharp(Buffer.from(board)).png().toFile(path.join(root,'comparison.png'));
 console.log('Rendered refined vectors and proof board.');
}
main().catch(e=>{console.error(e);process.exit(1)});
