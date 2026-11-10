(async()=>{
const code=language,stageName=stage;
const delay=()=>new Promise(resolve=>setTimeout(resolve,30));
const wait=async(predicate,name)=>{for(let i=0;i<400;i++){if(predicate())return;await delay();}throw Error(code+' '+innerWidth+' '+name+' '+document.body.innerText.slice(-1800));};
const visible=node=>node.getClientRects().length&&getComputedStyle(node).visibility!=='hidden'&&!node.closest('[hidden],[inert],[data-closed],[aria-hidden="true"]');
const contained=selector=>{const root=document.querySelector(selector);if(!root)throw Error('Missing '+selector);if(root.scrollWidth>root.clientWidth+2)throw Error(code+' '+innerWidth+' overflow '+selector+' '+root.scrollWidth+'/'+root.clientWidth);const box=root.getBoundingClientRect();for(const n of root.querySelectorAll('input:not([type=hidden]),select,textarea')){if(!visible(n))continue;const r=n.getBoundingClientRect();if(r.left<box.left-2||r.right>box.right+2)throw Error('Input outside '+selector+' '+n.outerHTML.slice(0,180));}};
const click=async selector=>{await wait(()=>document.querySelector(selector)&&!document.querySelector(selector).disabled,selector);document.querySelector(selector).click();await delay();};
const set=(selector,value)=>{const node=document.querySelector(selector);if(!node)throw Error('Missing input '+selector);const proto=node.tagName==='SELECT'?HTMLSelectElement.prototype:node.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;Object.getOwnPropertyDescriptor(proto,'value').set.call(node,value);node.dispatchEvent(new Event(node.tagName==='SELECT'?'change':'input',{bubbles:true}));};
const post=async body=>{const r=await fetch('/api/recetario',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});const data=await r.json();if(!r.ok)throw Error(data.error);return data;};
await wait(()=>window.__recetarioLanguage&&document.querySelector('.bottom-nav'),'app startup');
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
const differentFields=(a,b)=>Object.keys({...a,...b}).filter(key=>JSON.stringify(a[key])!==JSON.stringify(b[key]));
if(window.__localeOriginal&&differentFields(window.__localeOriginal,original).length)throw Error('Changing interface language altered original recipe');
window.__localeOriginal??=original;
await click('.bottom-nav button:first-child');await wait(()=>document.querySelector('.library-toolbar'),'library');contained('.library-toolbar');
if(![...document.querySelector('.category-filter').options].some(option=>option.value==='Sin clasificar'))throw Error('Localized category changed its stored value');
set('.category-filter','Sin clasificar');if(document.querySelector('.category-filter').value!=='Sin clasificar')throw Error('Canonical category selection failed');set('.category-filter','Todas');
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
await window.__recetarioLanguage.set(override);await delay();await window.__recetarioLanguage.set(code);await delay();
if(document.querySelector('.recipe-editor input[required]').value!==title)throw Error('Language change reset draft');
document.querySelector('.recipe-editor form').dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}));
await wait(()=>!document.querySelector('.recipe-editor'),'save recipe');
backup=await window.__recetarioExport();const saved=backup.books.flatMap(b=>b.recipes).find(r=>r.title===title);
if(!saved||saved.language!==override||saved.ingredients!=='200 g de arroz\n2 tomates'||saved.steps!=='Cocer 10 minutos.\nServir.')throw Error('Recipe override or manual text lost');
const afterOriginal=backup.books.flatMap(b=>b.recipes).find(r=>r.id===original.id);
if(!afterOriginal)throw Error('Existing recipe disappeared');
// The native bridge serializes Swift dictionaries: key order is not data.
const changed=differentFields(window.__localeOriginal,afterOriginal);
if(changed.length)throw Error('Existing recipe fields changed with interface language: '+JSON.stringify(changed.map(key=>({key,before:original[key],after:afterOriginal[key]}))));
if(window.__recetarioLanguage.get()!==code)throw Error('Recipe language changed app language');
await click('.add-recipe-button');await click('.add-menu button:first-child');await wait(()=>document.querySelector('.import-panel'),'import');
if(document.querySelector('.import-panel .recipe-language select').value!==code)throw Error('Import language default wrong');contained('.import-panel');
await click('.import-heading button');
const currentBook=await(await fetch('/api/recetario?book='+encodeURIComponent(book))).json();
if(!currentBook.kitchen.shopping.some(item=>item.id==='locale-qa-milk')){await post({action:'kitchen',bookId:book,revision:currentBook.kitchen.revision,kitchen:{...currentBook.kitchen,shopping:[...currentBook.kitchen.shopping,{id:'locale-qa-milk',name:'QA milk unchanged',quantity:1,unit:'L',category:'Lácteos y huevos',sources:[],checked:false,emoji:'🥛'}]}});window.dispatchEvent(new Event('focus'));}
await click('.bottom-nav button:nth-child(2)');await wait(()=>document.querySelector('.planner'),'planner');contained('.workspace');
if(![...document.querySelectorAll('.add-meal')].some(node=>node.innerText.replace(/\s+/g,' ').startsWith(labels.addBreakfast)))throw Error('Meal action language stale');
for(const card of document.querySelectorAll('.daily-slot.empty')){const boundary=card.getBoundingClientRect();if(card.scrollWidth>card.clientWidth+2)throw Error(code+' overflowing empty meal card');for(const node of card.querySelectorAll('header,.add-meal,.add-meal>span')){const box=node.getBoundingClientRect();if(box.left<boundary.left-2||box.right>boundary.right+2||node.scrollWidth>node.clientWidth+2)throw Error(code+' clipped empty meal content '+node.className);}}
const settingsButton=[...document.querySelectorAll('button')].find(node=>node.getAttribute('aria-label')===labels.menuSettings);if(!settingsButton)throw Error('Menu settings missing');settingsButton.click();await wait(()=>document.querySelector('.planner-settings select'),'menu settings');
for(const [index,option]of [...document.querySelector('.planner-settings select').options].entries()){const expected=new Intl.DateTimeFormat(code,{weekday:'long'}).format(new Date(2024,0,7+index));if(option.value!==String(index)||option.text!==expected)throw Error('Weekday label or stored value changed '+option.text);}
await click('.planner-settings .page-title-row button');await wait(()=>document.querySelector('.planner:not(.planner-settings)'),'return from settings');
await click('.bottom-nav button:nth-child(3)');await wait(()=>document.querySelector('.cesta-page'),'shopping');contained('.cesta-page');
await wait(()=>[...document.querySelectorAll('.cesta-group h3')].some(node=>node.innerText.trim()===labels.dairy),'translated shopping aisle');
await click('.bottom-nav button:last-child');await wait(()=>document.querySelector('.language-settings select'),'profile');
contained('.profile-page');
return {language:code,override,width:innerWidth,manualPreserved:true,legacyPreserved:true,settingsPersisted:true,brand:'A4',stage:'profile'};
})()
