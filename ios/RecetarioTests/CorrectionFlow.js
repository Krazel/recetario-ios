(async()=>{
// Runs against the actual common UI in WKWebView. No provider requests are made.
let stage='start';
const wait = async predicate => {
  for(let i=0;i<800;i++){if(predicate())return;await new Promise(r=>setTimeout(r,25));}
  throw Error('UI timeout at '+stage+': '+JSON.stringify([...document.querySelectorAll('[data-slot=dialog-content]')].map(e=>({html:e.outerHTML.slice(-2400),rect:e.getBoundingClientRect().toJSON(),visibility:getComputedStyle(e).visibility})))+' '+document.body.innerText.slice(-1800));
};
const visible=e=>e.getClientRects().length>0&&getComputedStyle(e).visibility!=='hidden'&&!e.closest('[hidden],[inert],[data-closed]');
const button=name=>[...document.querySelectorAll('button')].find(e=>{const label=(e.getAttribute('aria-label')||e.innerText).replace(/\s+/g,' ').trim();return visible(e)&&(label===name||label.startsWith(name+' '));});
const tap=async name=>{stage='tap '+name;await wait(()=>button(name)&&!button(name).disabled);const target=button(name);target.scrollIntoView({block:'nearest'});target.click();await new Promise(r=>setTimeout(r,150));};
const write=(selector,value)=>{const e=document.querySelector(selector);if(!e)throw Error('Missing input: '+selector);Object.getOwnPropertyDescriptor(e.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype,'value').set.call(e,value);e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}));};
const check=(ok,message)=>{if(!ok)throw Error(message);};
const failNextSave=action=>{
 const previous=window.fetch;let pending=true;
 window.fetch=async(input,init)=>{if(pending&&typeof init?.body==='string'){try{if(JSON.parse(init.body).action===action){pending=false;return Response.json({error:'Fallo de guardado de prueba'},{status:503});}}catch{}}
 return previous(input,init);};return ()=>{window.fetch=previous;};
};
const noHorizontal=selector=>{const e=document.querySelector(selector);check(!!e,'Missing layout: '+selector);check(e.scrollWidth<=e.clientWidth+2,selector+' overflow '+e.scrollWidth+'/'+e.clientWidth+' '+JSON.stringify([...e.querySelectorAll('*')].filter(n=>{const r=n.getBoundingClientRect(),b=e.getBoundingClientRect();return visible(n)&&(r.right>b.right+2||r.left<b.left-2);}).slice(0,8).map(n=>({tag:n.tagName,class:n.className,w:n.getBoundingClientRect().width,style:getComputedStyle(n).cssText}))));for(const input of e.querySelectorAll('input:not([type=hidden]),textarea,select')){if(!visible(input))continue;const r=input.getBoundingClientRect(),box=e.getBoundingClientRect();check(r.left>=box.left-2&&r.right<=box.right+2,'Input outside '+selector+': '+input.outerHTML.slice(0,150));}};
await wait(()=>button('Añadir receta'));
await tap('Añadir receta');await tap('Escribir mi receta');await wait(()=>document.querySelector('.recipe-editor'));
noHorizontal('.recipe-editor');noHorizontal('.approved-recipe-editor');
write('.recipe-editor input[required]','Receta de correcciones');
write('.recipe-editor [data-pane=ingredients] textarea','200 g de arroz\n2 tomates');
await tap('Pasos');write('.recipe-editor [data-pane=steps] textarea','Cocer el arroz.\nMezclar con tomate.');
await tap('Detalles');write('.recipe-editor input[type=url]','https://example.com/'+('receta'.repeat(35)));noHorizontal('.recipe-editor');
await tap('Guardar receta');await wait(()=>!document.querySelector('.recipe-editor'));
await tap('Perfil');await wait(()=>button('Mis gustos'));
check(!document.body.innerText.includes('Guardado en este dispositivo'),'Removed storage block visible');
check(!button('Mi compra'),'Shopping shortcut remains in Profile');
const privacy=document.querySelector('.ai-privacy-controls');check(!!privacy,'Missing privacy controls');
check(privacy.querySelector('a[href="https://krazel.github.io/recetario/privacy/"]'),'Missing public privacy policy');
check(privacy.querySelector('a[href="https://krazel.github.io/recetario/support/"]'),'Missing public support');
let status=await (await fetch('/api/import')).json();check(status.requiresConsent===true&&!status.ai,'AI enabled before permission');
const native=window.__recetarioNative||window.webkit?.messageHandlers?.device;
const blocked=await native.postMessage({action:'ai-request',path:'/api/import',method:'POST',body:'e30='});
check(blocked.ok===false&&blocked.error.includes('permiso'),'Native bridge bypassed consent');
await tap('Permiso de ayuda de IA');await wait(()=>document.querySelector('.ai-consent-dialog'));noHorizontal('.ai-consent-dialog');
check(document.querySelector('.ai-consent-dialog').innerText.includes('OpenAI'),'Provider undisclosed');
check(document.querySelector('.ai-consent-dialog').innerText.includes('alergias'),'Allergies undisclosed');
await tap('Seguir sin IA');await wait(()=>!document.querySelector('.ai-consent-dialog'));
status=await (await fetch('/api/import')).json();check(status.requiresConsent===true,'Declining granted consent');
await tap('Permiso de ayuda de IA');await tap('Permitir ayuda de IA');await wait(()=>button('Retirar permiso de IA'));
check(JSON.parse((await native.postMessage({action:'kv-read'})).value['recetario:ai-consent']).granted===true,'Consent was not persisted');
await tap('Retirar permiso de IA');await wait(()=>button('Permiso de ayuda de IA'));
status=await (await fetch('/api/import')).json();check(status.requiresConsent===true&&!status.ai,'Revocation failed');
await tap('Mis gustos');write('.compact-preferences input[maxlength="600"]','Cacao de prueba');
let restoreFetch=failNextSave('preferences');await tap('Guardar preferencias');await wait(()=>document.body.innerText.includes('Fallo de guardado de prueba'));
check(document.querySelector('.compact-preferences input[maxlength="600"]').value==='Cacao de prueba','Preferences lost after failed save');restoreFetch();
await tap('Guardar preferencias');await wait(()=>button('Mis gustos'));
check(!document.querySelector('.compact-preferences'),'Preferences did not close after successful save');
await tap('Mi despensa');await tap('Escribir ingredientes');write('.pantry-card textarea','300 g de arroz\n2 tomates');
await tap('Volver al perfil');await wait(()=>button('Seguir editando'));await tap('Seguir editando');
check(document.querySelector('.pantry-card textarea').value.includes('300 g'),'Pantry draft lost');
await tap('Volver al perfil');restoreFetch=failNextSave('kitchen');await tap('Guardar y volver');await wait(()=>document.body.innerText.includes('No se pudo guardar. Tus cambios siguen aquí.'));
check(document.querySelector('.pantry-card textarea').value.includes('300 g'),'Pantry lost after failed save');restoreFetch();
await tap('Guardar y volver');await wait(()=>button('Mis gustos'));
await tap('Mi despensa');check(document.body.innerText.includes('arroz'),'Pantry not saved');await tap('Volver al perfil');
await tap('Compartir enlaces');await wait(()=>document.querySelector('.share-guide'));noHorizontal('.share-guide-dialog');
const guideBounds=document.querySelector('.share-guide-dialog').getBoundingClientRect();check(Math.abs(guideBounds.left)<2&&Math.abs(guideBounds.top)<2&&Math.abs(guideBounds.right-innerWidth)<2&&Math.abs(guideBounds.bottom-innerHeight)<2,'Guide is outside the viewport: '+JSON.stringify(guideBounds.toJSON()));
check(document.querySelectorAll('.share-guide-steps>li').length===3,'Approved guide steps missing');
const setup=document.querySelector('.share-guide-setup');check(!!setup,'iPhone shortcut setup missing');setup.open=true;await new Promise(r=>setTimeout(r,100));noHorizontal('.share-guide-dialog');
await tap('Ir a Importar');await wait(()=>document.querySelector('.import-panel'));await tap('Cerrar importación');
await tap('Compra');await wait(()=>document.querySelector('.cesta-page'));noHorizontal('.cesta-page');
check(!document.querySelector('.cesta-people'),'People icon remains');check(!document.querySelector('.cesta-purchase-cover'),'Redundant empty purchase cover remains');
const product='Leche QA '+innerWidth;write('input[aria-label="Añadir producto rápido"]',product);await tap('Preparar producto');await wait(()=>document.querySelector('.cesta-dialog form'));
await tap('Añadir a mi compra');await wait(()=>!document.querySelector('.cesta-dialog'));
check(document.body.innerText.includes(product),'Manual shopping item missing');
await tap('Mi menú');await wait(()=>document.querySelector('.planner'));
const add=[...document.querySelectorAll('.add-meal,.daily-slot header button')].find(e=>visible(e)&&!e.disabled);
check(!!add,'Missing meal action');add.click();await wait(()=>document.querySelector('.meal-compose-date'));
noHorizontal('.meal-compose');noHorizontal('.meal-compose-date');
const controls=[...document.querySelectorAll('.meal-compose-date input,.meal-compose-date select')];
check(controls.length===2,'Expected day and meal controls');const [a,b]=controls.map(e=>e.getBoundingClientRect());
check(a.right<=b.left||b.right<=a.left||a.bottom<=b.top||b.bottom<=a.top,'Date and meal overlap');
await tap('Escribir un plato');write('.meal-compose textarea','Desayuno de prueba');await tap('Guardar en el menú');await wait(()=>!document.querySelector('.meal-compose'));
check(document.body.innerText.includes('Desayuno de prueba'),'Meal not persisted');
await tap('Recetas');await tap('Añadir receta');await tap('Escribir mi receta');
write('.recipe-editor input[required]','Borrador que se conserva');
window.dispatchEvent(new CustomEvent('recetario-native-import',{detail:{url:'https://youtu.be/shared-test',text:'Ingredientes:\n2 huevos\nPreparación:\nBatir.'}}));
await new Promise(r=>setTimeout(r,100));
check(document.querySelector('.recipe-editor input[required]').value==='Borrador que se conserva','Shared input replaced the open editor');
await tap('Cerrar editor');await tap('Abrir siguiente enlace');await wait(()=>document.querySelector('.import-panel'));
check(document.querySelector('.import-panel input[type=url]').value==='https://youtu.be/shared-test','Shared URL lost');
check(document.querySelector('.import-panel textarea[aria-label="Descripción de la publicación"]').value.includes('2 huevos'),'Shared caption lost');
check(!document.body.innerText.includes('Analizamos el contenido accesible con OpenAI'),'Removed import explanation remains');
check(!document.querySelector('[data-slot=toast]'),'Success toast present');
return {width:innerWidth,height:innerHeight,editor:'contained',profile:'simplified',preferences:'closed on save',pantry:'guarded and persisted',shopping:'personal manual item saved',meal:'non-overlapping and saved'};

})()
