(async()=>{
const code=language,stageName=stage;
const delay=()=>new Promise(resolve=>setTimeout(resolve,30));
const wait=async(predicate,name)=>{for(let i=0;i<400;i++){if(predicate())return;await delay();}throw Error(code+' '+innerWidth+' '+name+' '+document.body.innerText.slice(-1800));};
const visible=node=>node.getClientRects().length&&getComputedStyle(node).visibility!=='hidden'&&!node.closest('[hidden],[inert],[data-closed],[aria-hidden="true"]');
const contained=selector=>{const root=document.querySelector(selector);if(!root)throw Error('Missing '+selector);if(root.scrollWidth>root.clientWidth+2)throw Error(code+' '+innerWidth+' overflow '+selector+' '+root.scrollWidth+'/'+root.clientWidth);const box=root.getBoundingClientRect();for(const n of root.querySelectorAll('input:not([type=hidden]),select,textarea')){if(!visible(n))continue;const r=n.getBoundingClientRect();if(r.left<box.left-2||r.right>box.right+2)throw Error('Input outside '+selector+' '+n.outerHTML.slice(0,180));}};
const click=async selector=>{await wait(()=>document.querySelector(selector)&&!document.querySelector(selector).disabled,selector);document.querySelector(selector).click();await delay();};
const set=(selector,value)=>{const node=document.querySelector(selector);if(!node)throw Error('Missing input '+selector);const proto=node.tagName==='SELECT'?HTMLSelectElement.prototype:node.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;Object.getOwnPropertyDescriptor(proto,'value').set.call(node,value);node.dispatchEvent(new Event(node.tagName==='SELECT'?'change':'input',{bubbles:true}));};
const post=async body=>{const r=await fetch('/api/recetario',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});const data=await r.json();if(!r.ok)throw Error(data.error);return data;};
await wait(()=>window.__recetarioLanguage&&document.querySelector('.library-toolbar'),'app startup');
if(stageName==='home'){await click('.bottom-nav button:first-child');await wait(()=>document.querySelector('.library-toolbar'),'home');contained('.library-toolbar');return {language:document.documentElement.lang,stage:'home'};}
await click('.bottom-nav button:last-child');await wait(()=>document.querySelector('.language-settings select'),'Settings');
set('.language-settings select',code);await wait(()=>window.__recetarioLanguage.get()===code&&document.querySelector('.language-settings select')?.value===code,'persist language');
if(document.documentElement.lang!==code)throw Error('Document language stale');
if(document.querySelector('.bottom-nav button:first-child').innerText.trim()!==labels.recipes||document.querySelector('.bottom-nav button:last-child').innerText.trim()!==labels.profile)throw Error('Navigation language stale');
contained('.language-settings');contained('.profile-page');
const {books}=await(await fetch('/api/recetario')).json(),book=books[0].id;
let backup=await window.__recetarioExport();
if(!backup.books.flatMap(b=>b.recipes).some(r=>r.title==='Original conservado'))await post({action:'save',bookId:book,recipe:{title:'Original conservado',url:'https://example.com/original',category:'Sin clasificar',ingredients:'200 g de arroz\n2 tomates',steps:'Cocer 10 minutos.\nServir.',notes:'Notas del autor. No traducir.',minutes:10,favorite:0,servings:2,tags:'',provenance:'Fuente original',photo:'art:pasta'}});
const original=(await window.__recetarioExport()).books.flatMap(b=>b.recipes).find(r=>r.title==='Original conservado');
await click('.bottom-nav button:first-child');await wait(()=>document.querySelector('.library-toolbar'),'library');contained('.library-toolbar');
for(const image of document.querySelectorAll('.recisave-lockup img'))await wait(()=>image.complete&&image.naturalWidth>0,'A4 image');
if(document.querySelectorAll('.masthead img[alt="ReciSave"]').length!==1)throw Error('Missing or duplicated wordmark');
const iconBox=document.querySelector('.masthead .recisave-icon').getBoundingClientRect(),wordBox=document.querySelector('.masthead .recisave-wordmark').getBoundingClientRect();
if(wordBox.width<80||iconBox.right>wordBox.left+1||Math.abs((iconBox.top+iconBox.bottom)/2-(wordBox.top+wordBox.bottom)/2)>4)throw Error('A4 lockup is not horizontal and legible');
await click('.add-recipe-button');await click('.add-menu button:nth-child(2)');await wait(()=>document.querySelector('.recipe-editor form'),'editor');
if(document.querySelector('.recipe-editor .recipe-language select').value!==code)throw Error('New recipe did not default to effective language');
const codes=['en','es','ca','de','fr','it','pt'],override=codes[(codes.indexOf(code)+1)%codes.length];
set('.recipe-editor .recipe-language select',override);
const title='Manual '+code+' '+innerWidth;
set('.recipe-editor input[required]',title);set('.recipe-editor [data-pane=ingredients] textarea','200 g de arroz\n2 tomates');set('.recipe-editor [data-pane=steps] textarea','Cocer 10 minutos.\nServir.');
for(const button of document.querySelectorAll('.editor-tabs button')){button.click();await delay();contained('.recipe-editor');contained('.approved-recipe-editor');}
// A locale rerender must preserve the in-progress manual content.
await window.__recetarioLanguage.set(code);await delay();
if(document.querySelector('.recipe-editor input[required]').value!==title)throw Error('Language change reset draft');
document.querySelector('.recipe-editor form').dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}));
await wait(()=>!document.querySelector('.recipe-editor'),'save recipe');
backup=await window.__recetarioExport();const saved=backup.books.flatMap(b=>b.recipes).find(r=>r.title===title);
if(!saved||saved.language!==override||saved.ingredients!=='200 g de arroz\n2 tomates'||saved.steps!=='Cocer 10 minutos.\nServir.')throw Error('Recipe override or manual text lost');
if(JSON.stringify(backup.books.flatMap(b=>b.recipes).find(r=>r.id===original.id))!==JSON.stringify(original))throw Error('Existing recipe changed with interface language');
if(window.__recetarioLanguage.get()!==code)throw Error('Recipe language changed app language');
await click('.add-recipe-button');await click('.add-menu button:first-child');await wait(()=>document.querySelector('.import-panel'),'import');
if(document.querySelector('.import-panel .recipe-language select').value!==code)throw Error('Import language default wrong');contained('.import-panel');
await click('.import-heading button');
await click('.bottom-nav button:nth-child(2)');await wait(()=>document.querySelector('.planner'),'planner');contained('.workspace');
if(![...document.querySelectorAll('.add-meal')].some(node=>node.innerText.replace(/\s+/g,' ').startsWith(labels.addBreakfast)))throw Error('Meal action language stale');
await click('.bottom-nav button:nth-child(3)');await wait(()=>document.querySelector('.cesta-page'),'shopping');contained('.cesta-page');
await click('.bottom-nav button:last-child');await wait(()=>document.querySelector('.language-settings select'),'profile');
contained('.profile-page');
return {language:code,override,width:innerWidth,manualPreserved:true,legacyPreserved:true,settingsPersisted:true,brand:'A4',stage:'profile'};
})()
