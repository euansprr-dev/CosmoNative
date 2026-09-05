const fs = require('fs');
const path = require('path');
const sharp = require('/Users/euanspencer/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const out = __dirname;
const ink = '#245B43', paper = '#F6F2E7', night = '#173F32', cream = '#F5F0E2', gold = '#B69B62';

// Every design is authored as editable vectors on an unmasked 1024 px square.
// Overlap cuts use the background colour; monochrome foreground exports use masks.
const concepts = [
  {
    id:'01-living-orbit', name:'Living Orbit', tag:'The faithful evolution',
    rationale:'A fuller orbit, quieter intersections, and one decisive leaf. Closest to the original.',
    bg:paper, fg:ink, accent:ink,
    draw:(f,b,a)=>`
      <path d="M738 379 C784 268 740 225 660 252 C546 289 407 423 317 560 C225 700 249 775 347 741 C468 700 662 545 791 428" fill="none" stroke="${f}" stroke-width="30"/>
      <path d="M678 409 C548 368 354 390 262 450 C164 514 228 584 363 611 C476 635 590 624 661 608" fill="none" stroke="${f}" stroke-width="32"/>
      <path d="M616 582 C633 474 692 401 810 413 C820 526 765 603 660 615 C734 578 779 506 781 443 C705 443 656 492 616 582Z" fill="${f}"/>
      <circle cx="506" cy="511" r="44" fill="${a}"/>`,
  },
  {
    id:'02-verdant', name:'Verdant', tag:'The confident signature',
    rationale:'A single broad, rising orbit and a leaf cut from its terminal. Strongest balance of warmth and clarity.',
    bg:paper, fg:ink, accent:ink,
    draw:(f,b,a)=>`
      <path d="M764 365 C688 288 555 290 434 354 C290 429 209 565 255 651 C304 743 462 748 614 661 C687 619 747 560 782 496 C734 544 666 590 585 625 C458 680 335 679 304 619 C270 552 344 441 463 380 C564 328 664 330 727 377 Z" fill="${f}"/>
      <path d="M604 563 C609 466 674 389 805 390 C813 502 750 579 644 594 C691 553 729 508 762 443 C695 467 650 506 604 563Z" fill="${f}"/>
      <circle cx="481" cy="495" r="53" fill="${a}"/>
      <path d="M313 633 C279 541 334 397 456 295" fill="none" stroke="${f}" stroke-width="24"/>
      <path d="M456 295 C544 220 614 219 635 277" fill="none" stroke="${f}" stroke-width="24"/>`,
  },
  {
    id:'03-folio', name:'Folio', tag:'The editorial emblem',
    rationale:'An orbital C and a folded leaf share one silhouette. Knowledge, growth, and the Cosmo initial.',
    bg:paper, fg:ink, accent:ink,
    draw:(f,b,a)=>`
      <path d="M732 299 C648 224 497 232 381 311 C230 414 189 597 287 704 C381 807 566 773 712 641 L661 597 C552 695 419 728 352 658 C279 582 313 447 425 366 C514 302 622 292 694 344 Z" fill="${f}"/>
      <path d="M560 551 C577 440 665 368 811 385 C808 513 727 596 588 607 C677 565 736 505 768 426 C676 444 613 484 560 551Z" fill="${f}"/>
      <path d="M287 548 C378 591 484 591 566 567" fill="none" stroke="${f}" stroke-width="29"/>
      <circle cx="477" cy="468" r="43" fill="${a}"/>`,
  },
  {
    id:'04-meridian', name:'Meridian', tag:'The considered instrument',
    rationale:'Two measured orbits and a small gilt seed. A quieter, more scholarly expression of the same idea.',
    bg:'#F3EFE4', fg:ink, accent:gold,
    draw:(f,b,a)=>`
      <path d="M675 411 C548 376 365 391 269 449 C170 510 222 577 349 610 C466 641 584 627 655 606" fill="none" stroke="${f}" stroke-width="29"/>
      <path d="M696 362 C720 291 703 245 659 245 C573 245 435 365 344 499 C253 633 229 756 286 777 C374 809 629 582 787 419" fill="none" stroke="${f}" stroke-width="27"/>
      <path d="M601 590 C611 470 687 389 806 404 C812 515 747 597 644 621 C711 571 756 513 768 440 C692 449 639 504 601 590Z" fill="${f}"/>
      <circle cx="494" cy="519" r="47" fill="${a}"/>`,
  },
  {
    id:'05-evergreen', name:'Evergreen', tag:'The bold seal',
    rationale:'Parchment on deep forest, with a broad open orbit and an integrated leaf. The strongest Home Screen presence.',
    bg:night, fg:cream, accent:cream,
    draw:(f,b,a)=>`
      <path d="M765 353 C673 260 500 276 366 382 C226 492 196 634 277 706 C361 781 531 739 676 616 C760 545 808 468 808 402 C677 388 602 456 584 566 C628 518 696 467 771 442 C730 514 676 575 619 617 C507 697 387 709 334 660 C280 611 314 499 417 416 C522 332 651 310 726 377Z" fill="${f}"/>
      <path d="M295 658 C260 559 341 389 474 285 C550 225 617 219 641 263" fill="none" stroke="${f}" stroke-width="26"/>
      <circle cx="479" cy="494" r="53" fill="${a}"/>`,
  }
];
const svgFor=(c,mode='default',foreground=false)=>{
  let bg=c.bg, fg=c.fg, accent=c.accent;
  if(mode==='dark'){bg=night;fg=cream;accent=c.id.startsWith('04')?'#CAB17B':cream;}
  if(mode==='mono'){bg=paper;fg=ink;accent=ink;}
  const content=c.draw(fg,bg,accent);
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><title>Cosmo — ${c.name}</title><desc>Flat vector app icon. ${c.rationale}</desc>${foreground?'':`<rect width="1024" height="1024" fill="${bg}"/>`}<g stroke-linecap="round" stroke-linejoin="round">${content}</g></svg>`;
};
async function main(){
  fs.mkdirSync(path.join(out,'svg'),{recursive:true});fs.mkdirSync(path.join(out,'png'),{recursive:true});
  for(const c of concepts){
    for(const mode of ['default','dark','mono']){
      const svg=svgFor(c,mode);const suffix=mode==='default'?'':`-${mode}`;
      fs.writeFileSync(path.join(out,'svg',`${c.id}${suffix}.svg`),svg);
      await sharp(Buffer.from(svg)).removeAlpha().png().toFile(path.join(out,'png',`${c.id}${suffix}-1024.png`));
    }
  }
  fs.writeFileSync(path.join(out,'concepts.json'),JSON.stringify(concepts.map(({draw,...c})=>c),null,2));
  console.log('Rendered five concepts in default, dark and monochrome appearances.');
}
main().catch(e=>{console.error(e);process.exit(1)});
