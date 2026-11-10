(async()=>{
// Test fixture only: own recipe text and the app's existing approved art crops.
window.__storeLocale=locale;window.__storeLabels=fixture.labels;
await window.__recetarioLanguage.set(locale);if(document.documentElement.lang!==locale)throw Error('Store language not applied');
const wait=async predicate=>{for(let i=0;i<800;i++){if(predicate())return;await new Promise(r=>setTimeout(r,25));}throw Error('Store fixture UI timeout: '+document.body.innerText.slice(-1400));};
const visible=e=>e.getClientRects().length>0&&getComputedStyle(e).visibility!=='hidden'&&!e.closest('[hidden],[inert],[data-closed]');
window.__storeWait=wait;
window.__storeTap=async name=>{let target;await wait(()=>{target=[...document.querySelectorAll('button')].find(e=>{const label=(e.getAttribute('aria-label')||e.innerText).replace(/\s+/g,' ').trim();return visible(e)&&(label===name||label.startsWith(name+' '));});return target&&!target.disabled;});target.scrollIntoView({block:'nearest'});target.click();await new Promise(r=>setTimeout(r,500));};
// Wait for the real book's initial load before seeding its database.
await wait(()=>document.querySelector('.empty-state,.recipe-card'));
const post=async body=>{const r=await fetch('/api/recetario',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});const value=await r.json();if(!r.ok)throw Error(value.error);return value;};
const {books}=await post({action:'bootstrap'}),bookId=books[0].id;
const recipes=['soup','omelette','pasta'].map((kind,index)=>({title:fixture.titles[index],category:index?'Platos principales':'Entrantes',minutes:index?20:25,servings:2,photo:'art:'+kind,ingredients:fixture[kind][0],steps:fixture[kind][1],language:locale}));
window.__storeRecipeTitle=recipes[2].title;
const ids=[];for(const r of recipes){const saved=await post({action:'save',bookId,recipe:{url:'',notes:fixture.note,favorite:1,tags:'',provenance:fixture.provenance,...r}});ids.push(saved.id);}
const snapshot=async()=>{const r=await fetch('/api/recetario?book='+bookId);return r.json();};
let s=await snapshot();await post({action:'kitchen',bookId,revision:s.kitchen.revision,kitchen:{...s.kitchen,pantry:fixture.pantry,shopping:[{id:crypto.randomUUID(),name:fixture.milk,quantity:1,unit:'L',sources:[],checked:false,emoji:'🥛',category:'Lácteos y huevos'}]}});
s=await snapshot();const today=new Date(),date=d=>d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0'),monday=new Date(today);monday.setDate(today.getDate()-((today.getDay()+6)%7));
await post({action:'workspace',bookId,kitchenRevision:s.kitchen.revision,workspace:{...s.workspace,shoppingWeek:date(monday),subtractPantry:false,meals:[{id:crypto.randomUUID(),date:date(today),slot:'Comida',recipeId:ids[2],servings:2,note:''},{id:crypto.randomUUID(),date:date(today),slot:'Cena',recipeId:ids[1],servings:2,note:''}]}});
window.dispatchEvent(new Event('recetario-local-restored'));
// A restore keeps the same book ID. Returning to the app refreshes that book;
// bootstrap alone only refreshes the list of books.
window.dispatchEvent(new Event('focus'));
await wait(()=>[...document.querySelectorAll('.recipe-card')].some(e=>e.innerText.includes(recipes[2].title)));
await document.fonts.ready;await new Promise(r=>setTimeout(r,800));
if(document.documentElement.lang!==locale)throw Error('Store language changed');
return {locale,bookId,recipes:recipes.map(r=>r.title),source:'own demo recipe text; approved built-in art:pasta/soup/omelette; no AI requests'};
})()
