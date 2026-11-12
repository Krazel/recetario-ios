(async () => {
 const check = (condition, message) => { if (!condition) throw Error(message); };
 const wait = async (predicate, message) => {
  for (let i = 0; i < 480; i++) {
   const result = predicate();
   if (result) return result;
   await new Promise(resolve => setTimeout(resolve, 25));
  }
  throw Error(message + ': ' + document.body.innerText.slice(-950));
 };
 const select = selector => document.querySelector(selector);
 const popup = '.cooking-editorial';
 const title = 'Pasta con tomate y albahaca';
 const longStep = 'Mezclar la pasta con la salsa, añadir la albahaca fresca y comprobar el punto antes de repartirla entre los platos. Añadir un poco del agua de cocción si hace falta y servir enseguida.';
 const instruction = 'Calentar agua abundante con una pizca de sal.';
 const steps = [instruction, 'Cocer la pasta durante 10 minutos.', 'Calentar la salsa durante 2 segundos.', longStep].join('\n');
 const tap = async selector => {
  const button = await wait(() => {
   const target = select(selector);
   return target && !target.disabled && target.getClientRects().length && target;
  }, 'Control no disponible: ' + selector);
  button.click();
 };
 const layout = () => {
  const scroll = select(popup + ' .cooking-scroll');
  const bounds = select(popup).getBoundingClientRect();
  const bottom = select(popup + ' footer').getBoundingClientRect();
  check(scroll.scrollWidth <= scroll.clientWidth + 2, 'Desborde horizontal en cocina');
  check(bottom.bottom <= bounds.bottom + 1 && bottom.height >= 48, 'Pie fuera del área visible');
  for (const button of document.querySelectorAll(popup + ' footer button, ' + popup + ' .read-step')) {
   const rect = button.getBoundingClientRect();
   check(rect.left >= bounds.left - 1 && rect.right <= bounds.right + 1 && rect.height >= 44, 'Control cortado: ' + button.textContent);
  }
  return {width: Math.round(bounds.width), height: Math.round(bounds.height), instructionFont: getComputedStyle(select('.cooking-instruction')).fontFamily};
 };
 const openRecipe = async label => {
  const card = await wait(() => [...document.querySelectorAll('.recipe-card')].find(node => node.innerText.includes(label)), 'Falta receta de prueba');
  const open = card.querySelector('.card-open');
  check(open, 'Falta apertura de ficha');
  open.click();
  await tap('.detail-sticky .primary');
  await wait(() => select(popup), 'No abrió modo cocinar');
 };
 const close = async () => {
  await tap(popup + ' header button');
  await wait(() => !select(popup), 'Modo cocinar no se cerró');
 };
 const post = async body => {
  const response = await fetch('/api/recetario', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(body)});
  const result = await response.json();
  check(response.ok, result.error || 'No se guardó el dato de prueba');
  return result;
 };
 if (stage === 'prepare') {
  await wait(() => window.__recetarioLanguage && select('.library-toolbar'), 'Recetario no inició');
  await window.__recetarioLanguage.set('es');
  const {books} = await post({action:'bootstrap'});
  const bookId = books[0].id;
  const beforeSeed = await (await fetch('/api/recetario?book=' + encodeURIComponent(bookId))).json();
  const bundledPhoto = typeof photoDataURL === 'string' ? photoDataURL : null;
  let photoURL = bundledPhoto;
  if (!photoURL) {
   const response = await fetch('/images/tomato-pasta.jpg');
   check(response.ok, 'Falta imagen de la receta de prueba');
   photoURL = URL.createObjectURL(await response.blob());
  }
  const image = new Image();
  image.src = photoURL;
  await image.decode();
  const canvas = document.createElement('canvas');
  canvas.width = 640;
  canvas.height = Math.round(640 * image.naturalHeight / image.naturalWidth);
  canvas.getContext('2d').drawImage(image, 0, 0, canvas.width, canvas.height);
  const photo = bundledPhoto ?? canvas.toDataURL('image/jpeg', .82);
  canvas.width = 240;
  canvas.height = Math.round(240 * image.naturalHeight / image.naturalWidth);
  canvas.getContext('2d').drawImage(image, 0, 0, canvas.width, canvas.height);
  const stepPhoto = bundledPhoto ?? canvas.toDataURL('image/jpeg', .7);
  if (!bundledPhoto) URL.revokeObjectURL(photoURL);
  const step_media = JSON.stringify({version:1,sourceUrl:'',items:[{step:3,text:longStep,photo:stepPhoto,kind:'photo',selection:'manual',caption:'Pasta servida'}]});
  const fixture = {title, url:'', category:'Platos principales', minutes:20, servings:2, photo, step_media, ingredients:'200 g de pasta\n3 tomates\n1 diente de ajo\n1 cucharada de aceite de oliva\n6 hojas de albahaca\nSal', steps, language:'es', notes:'QA de cocina editorial', favorite:0, tags:'', provenance:'Datos de prueba'};
  const fixtures = [fixture, {...fixture,title:'Pasta sin imagen · QA',photo:'',step_media:'',url:'https://www.youtube.com/watch?v=ReciSaveQA0'}];
  for (const recipe of fixtures) {
   if (!beforeSeed.recipes.some(item => item.title === recipe.title)) await post({action:'save',bookId,recipe});
  }
  const saved = await (await fetch('/api/recetario?book=' + encodeURIComponent(bookId))).json();
  window.__cookingFixture = {bookId, recipes:saved.recipes.filter(item => fixtures.some(recipe => recipe.title === item.title))};
  window.dispatchEvent(new Event('recetario-local-restored'));
  window.dispatchEvent(new Event('focus'));
  await openRecipe(title);
  await wait(() => {
   const img = select('.cooking-photo img');
   return img?.complete && img.naturalWidth > 0;
  }, 'No cargó foto existente');
  check(select('.cooking-photo figcaption').textContent === 'Imagen de la receta', 'La portada se atribuye al paso');
  check(select('.cooking-instruction').textContent === instruction, 'Cambió el texto de cocina');
  check(select('.cook-ingredients').open && select('.cooking-ingredient-list').children.length === 6, 'Faltan ingredientes');
  check(select('.cooking-tools .cook-video-toggle').textContent.includes('Añadir enlace'), 'Falta añadir enlace');
  check(!select('.cook-timer') && !select('.timer-dock'), 'Arrancó un temporizador sin interacción');
  await document.fonts.ready;
  return layout();
 }
 if (stage === 'controls') {
  await tap('.cooking-tools .read-step');
  await wait(() => select('.read-step[aria-pressed=true]'), 'No se activó lectura');
  await tap('.cooking-tools .read-step');
  await tap('.cook-ingredients summary');
  check(!select('.cook-ingredients').open, 'Ingredientes no se pliegan');
  await tap('.cook-ingredients summary');
  await tap('.cooking-ingredient-list input');
  check(select('.cooking-ingredient-list input').checked, 'No se marca ingrediente');
  await tap(popup + ' footer .primary');
  await wait(() => select('.cook-timer [role=timer]')?.textContent === '10:00', 'Duración del paso perdida');
  check(!select('.timer-dock'), 'Paso nuevo arrancó solo');
  await tap('.cook-timer .primary');
  await wait(() => select('.timer-dock-row'), 'No aparece temporizador activo');
  await tap(popup + ' footer .primary');
  await wait(() => select('.cook-timer [role=timer]')?.textContent === '0:02', 'No abrió otro paso');
  check(select('.timer-dock-row button').getAttribute('aria-label').includes('2'), 'No conserva el temporizador del otro paso');
  layout();
  await tap('.timer-dock-row button');
  await wait(() => select('.cook-timer .primary')?.textContent.includes('Pausar'), 'El dock no vuelve al paso activo');
  await tap('.cook-timer .primary');
  await wait(() => select('.cook-timer .primary')?.textContent.includes('Continuar'), 'No quedó en pausa');
  await tap('.cook-timer .secondary');
  check(Number(select('.cook-timer [role=timer]').textContent.split(':')[0]) >= 10, 'No sumó un minuto');
  await tap('.cook-timer .icon-button');
  await wait(() => !select('.timer-dock'), 'No se quitó temporizador reiniciado');
  await tap(popup + ' footer .primary');
  await tap('.cook-timer .primary');
  await wait(() => select('.cook-timer [role=alert]') && select('.timer-dock-row.finished'), 'No se anunció el final');
  await close();
  await tap('.detail-sticky .primary');
  await wait(() => select('.timer-dock-row.finished'), 'No recuperó temporizador terminado');
  await tap('.timer-dock-row .icon-button:last-child');
  await wait(() => !select('.timer-dock'), 'El dock no permite quitar temporizador');
  await tap('.cooking-progress button:last-child');
  await wait(() => select('.cooking-instruction').textContent === longStep, 'No abrió paso largo');
  check(select('.cooking-step-photo figcaption')?.textContent === 'Pasta servida', 'No se muestra la foto asociada al paso');
  layout();
  await tap(popup + ' footer .primary');
  await wait(() => !select(popup), 'Terminar no cierra el modo');
  const {bookId,recipes} = window.__cookingFixture;
  const current = await (await fetch('/api/recetario?book=' + encodeURIComponent(bookId))).json();
  for (const recipe of recipes) {
   const saved = current.recipes.find(item => item.id === recipe.id);
   check(saved, 'La receta de prueba dejó de estar disponible');
   const fields = new Set([...Object.keys(recipe), ...Object.keys(saved)]);
   const changed = [...fields].filter(field => JSON.stringify(recipe[field]) !== JSON.stringify(saved[field]));
   check(changed.length === 0, 'Cocinar modificó estos campos: ' + changed.join(', '));
  }
  const detailClose = document.querySelector('.recipe-sheet .sheet-header button');
  if (detailClose) detailClose.click();
  await openRecipe('Pasta sin imagen · QA');
  check(!select('.cooking-photo'), 'Se muestra un hueco o foto ajena');
  check(select('.cooking-tools .cook-video-toggle').textContent.includes('Ver vídeo'), 'Falta el vídeo original');
  return layout();
 }
 if (stage === 'languages') {
  for (const language of ['en','es','ca','de','fr','it','pt']) {
   await window.__recetarioLanguage.set(language);
   await wait(() => document.documentElement.lang === language && select('.cooking-instruction'), 'No se aplicó idioma ' + language);
   check(select('.cooking-instruction').textContent === instruction, 'Se tradujo receta guardada');
   layout();
  }
  await window.__recetarioLanguage.set('es');
  return layout();
 }
 if (stage === 'grid') {
  if(select(popup))await close();
  const closeDetail=select('.recipe-sheet .sheet-header button');
  if(closeDetail){closeDetail.click();await wait(()=>!select('.recipe-sheet .sheet-header button'),'La ficha no se cerró');}
  const grid=await wait(()=>select('.library-card-grid:has(.recipe-card)'), 'Falta cuadrícula de recetas');
  check(getComputedStyle(grid).gridTemplateColumns.split(' ').length===2, 'El móvil no muestra dos columnas');
  const search=select('.library-toolbar input[type=search]');
  const nav=select('.bottom-nav');
  const bottom=nav.getBoundingClientRect().bottom;
  for(let cycle=0;cycle<2;cycle++){
   search.focus();
   await wait(()=>document.activeElement===search,'La búsqueda no obtuvo foco');
   search.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true}));
   await wait(()=>document.activeElement!==search&&!document.documentElement.classList.contains('keyboard-open'), 'La búsqueda conserva el foco o el estado del teclado');
   check(Math.abs(nav.getBoundingClientRect().bottom-bottom)<=1, 'Cambió el anclaje del menú inferior');
  }
  return {columns:2,searchFocusCycles:2,softKeyboardVerified:false};
 }
 if (stage === 'shopping') {
  const {bookId}=window.__cookingFixture;
  const saved=await (await fetch('/api/recetario?book='+encodeURIComponent(bookId))).json();
  const ingredients=[['Leche',1,'L','Lácteos y huevos'],['Huevos',4,'ud','Lácteos y huevos'],['Tomates',2,'ud','Frutas y verduras']];
  await post({action:'kitchen',bookId,revision:saved.kitchen.revision,kitchen:{...saved.kitchen,shopping:ingredients.map(([name,quantity,unit,category])=>({id:crypto.randomUUID(),name,quantity,unit,category,sources:['Añadido a mano'],checked:false}))}});
  window.dispatchEvent(new Event('focus'));
  await tap('.bottom-nav button:nth-child(3)');
  const buy=await wait(()=>select('.cesta-page:has(.cesta-item)'), 'No se abrió la compra con productos');
  check(!buy.querySelector('.cesta-heading')&&buy.querySelectorAll('.cesta-nav button').length===3, 'Cabecera de compra incorrecta');
  return {products:buy.querySelectorAll('.cesta-item').length};
 }
 if (stage === 'profile') {
  await tap('.bottom-nav button:last-child');
  await wait(()=>select('.profile-settings'), 'No se abrió Perfil');
  check(!select('.backup-actions,.ai-privacy-controls'), 'Se conservaron tarjetas de Perfil');
  check(!select('.profile-settings select'), 'El selector se muestra antes de tocar Idioma');
  return {compactSettings:true};
 }
 if (stage === 'header') {
  await wait(()=>select('.library-toolbar')&&select('.recipe-card,.empty-state'), 'No inició la biblioteca');
  await document.fonts.ready;
  const measure=()=>{
   const header=select('.approved-app > .masthead');
   const logo=header.querySelector('.recisave-wordmark');
   const box=header.getBoundingClientRect(), brand=logo.getBoundingClientRect();
   return {height:box.height,border:box.bottom,logo:brand.top};
  };
  const positions={};
  const sections=['recipes','planner','shopping','profile'];
  for(const [index,section] of sections.entries()){
   await tap('.bottom-nav button:nth-child('+(index+1)+')');
   await wait(()=>select('.approved-app').dataset.section===section, 'No cambió a '+section);
   positions[section]=measure();
  }
  const match=(current,expected)=>Object.keys(expected).every(key=>Math.abs(current[key]-expected[key])<=.75);
  for(const section of sections)check(match(positions[section],positions.profile), 'Cabecera distinta: '+JSON.stringify(positions));
  await tap('.bottom-nav button:first-child');
  const add=select('.masthead .add-recipe-button');
  const target=add.getBoundingClientRect();
  const header=select('.approved-app > .masthead').getBoundingClientRect();
  check(target.width>=44&&target.height>=44,'El área táctil del + es demasiado pequeña');
  const padding=getComputedStyle(select('.approved-app > .masthead'));
  const center=(header.top+header.bottom+parseFloat(padding.paddingTop)-parseFloat(padding.paddingBottom))/2;
  check(Math.abs(target.top+target.height/2-center)<=1,'El + no está centrado');
  await tap('.masthead .add-recipe-button');
  await wait(()=>select('.masthead .add-menu button:nth-child(2)'), 'El + no abrió las acciones');
  check(match(measure(),positions.profile),'Abrir el + desplaza la cabecera');
  await tap('.masthead .add-recipe-button');
  await tap('.library-switch button:nth-child(2)');
  await wait(()=>select('.library-switch button:nth-child(2)[aria-pressed=true]'), 'No abrió Recetarios');
  check(match(measure(),positions.profile),'Recetarios desplaza la cabecera');
  await tap('.library-switch button:first-child');
  return {viewport:innerWidth,positions,addTarget:[target.width,target.height],addActions:2};
 }
 throw Error('Etapa de prueba desconocida: ' + stage);
})()
