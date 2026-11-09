(async()=>{
// Test fixture only: own recipe text and the app's existing approved art crops.
const wait=async predicate=>{for(let i=0;i<800;i++){if(predicate())return;await new Promise(r=>setTimeout(r,25));}throw Error('Store fixture UI timeout: '+document.body.innerText.slice(-1400));};
const visible=e=>e.getClientRects().length>0&&getComputedStyle(e).visibility!=='hidden'&&!e.closest('[hidden],[inert],[data-closed]');
window.__storeWait=wait;
window.__storeTap=async name=>{let target;await wait(()=>{target=[...document.querySelectorAll('button')].find(e=>{const label=(e.getAttribute('aria-label')||e.innerText).replace(/\s+/g,' ').trim();return visible(e)&&(label===name||label.startsWith(name+' '));});return target&&!target.disabled;});target.scrollIntoView({block:'nearest'});target.click();await new Promise(r=>setTimeout(r,500));};
// Wait for the real book's initial load before seeding its database.
await wait(()=>document.querySelector('.empty-state,.recipe-card'));
const post=async body=>{const r=await fetch('/api/recetario',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});const value=await r.json();if(!r.ok)throw Error(value.error);return value;};
const {books}=await post({action:'bootstrap'}),bookId=books[0].id;
const recipes=[
 {title:'Crema de calabacín',category:'Entrantes',minutes:25,servings:2,photo:'art:soup',ingredients:'2 calabacines\n1 patata\n1 cebolla\n500 ml de agua\n1 cucharada de aceite de oliva\nSal',steps:'Lavar y cortar las verduras.\nRehogar la cebolla con el aceite durante 5 minutos.\nAñadir el calabacín, la patata y el agua. Cocer 15 minutos.\nTriturar hasta obtener una crema y ajustar la sal.'},
 {title:'Tortilla de verduras',category:'Platos principales',minutes:20,servings:2,photo:'art:omelette',ingredients:'4 huevos\n1 calabacín\n1 cebolla\n1 cucharada de aceite de oliva\nSal',steps:'Cortar el calabacín y la cebolla en dados pequeños.\nRehogar las verduras durante 8 minutos.\nBatir los huevos y mezclar con las verduras.\nCuajar en la sartén a fuego suave y servir.'},
 {title:'Pasta con tomate y albahaca',category:'Platos principales',minutes:20,servings:2,photo:'art:pasta',ingredients:'200 g de pasta\n3 tomates\n1 diente de ajo\n1 cucharada de aceite de oliva\n6 hojas de albahaca\nSal',steps:'Calentar agua abundante con una pizca de sal.\nCocer la pasta durante 10 minutos y reservar un poco del agua.\nDorar el ajo con aceite, añadir el tomate troceado y cocinar 8 minutos.\nMezclar la pasta con la salsa y terminar con albahaca fresca.'}
];
const ids=[];for(const r of recipes){const saved=await post({action:'save',bookId,recipe:{url:'',notes:'Receta propia de demostración.',favorite:1,tags:'Casero',provenance:'Receta propia',...r}});ids.push(saved.id);}
const snapshot=async()=>{const r=await fetch('/api/recetario?book='+bookId);return r.json();};
let s=await snapshot();await post({action:'kitchen',bookId,revision:s.kitchen.revision,kitchen:{...s.kitchen,pantry:'2 tomates\n200 g de arroz\n4 huevos\nAceite de oliva\nSal',shopping:[{id:crypto.randomUUID(),name:'Leche',quantity:1,unit:'L',sources:['Añadido a mano'],checked:false,emoji:'🥛',category:'Lácteos y huevos'}]}});
s=await snapshot();const today=new Date(),date=d=>d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0'),monday=new Date(today);monday.setDate(today.getDate()-((today.getDay()+6)%7));
await post({action:'workspace',bookId,kitchenRevision:s.kitchen.revision,workspace:{...s.workspace,shoppingWeek:date(monday),subtractPantry:false,meals:[{id:crypto.randomUUID(),date:date(today),slot:'Comida',recipeId:ids[2],servings:2,note:''},{id:crypto.randomUUID(),date:date(today),slot:'Cena',recipeId:ids[1],servings:2,note:''}]}});
window.dispatchEvent(new Event('recetario-local-restored'));
// A restore keeps the same book ID. Returning to the app refreshes that book;
// bootstrap alone only refreshes the list of books.
window.dispatchEvent(new Event('focus'));
await wait(()=>[...document.querySelectorAll('.recipe-card')].some(e=>e.innerText.includes(recipes[2].title)));
await document.fonts.ready;await new Promise(r=>setTimeout(r,800));
return {bookId,recipes:recipes.map(r=>r.title),source:'own demo recipe text; approved built-in art:pasta/soup/omelette; no AI requests'};
})()
