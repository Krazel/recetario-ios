> **Decisión vigente 04/11/2026:** candidata iPhone 0.3 (1), interfaz completa empaquetada y SQLite nativo. Recetas, fotos/pasos, cocina/voz/temporizadores, menú, despensa/compra/listas y gustos funcionan localmente sin cuenta. Copia JSON completa transaccional e importación del formato web. Clientes de cuenta y StoreKit excluidos. OCR Vision local; IA opcional mediante App Attest, endpoint de entrada exclusivamente IA y topes monetarios en el backend privado. Cliente público por orden expresa del titular; CI manual por API con `macos-26-intel` estándar, sin artefactos ni almacenamiento de pago. 168 pruebas JS/SQLite y TypeScript/build correctos. 22 pruebas nativas aprobadas, incluida apertura real del bundle y puente SQLite. Compilación universal arm64/x86_64 correcta por API (CI41897193981, fuente408b0b3). CI41892713913 completa en verde; repetición41894591504 pasó los 22 tests pero alcanzó20min al cerrar. Futuras pruebas tienen margen30min; la compilación directa mantiene15min. Entrada IA pública v2 activada tras autorización expresa, retos y rechazo de peticiones sin verificación comprobados, sin llamadas pagadas. Mantener `testflight.json` bloqueado: no nueva distribución hasta QA física. Beta conocida 0.2 (2) interna. Los apartados siguientes son historial; las cuentas y el Site remoto no forman parte del arranque actual.

# Recetario iOS Â· TestFlight 0.2 (2)

**Estado 19/10/2026:** Â«Recetario de KrazelÂ» 0.2 (2) disponible en TestFlight interno para el titular. Apple6824557637; build14cfca09-7596-4ae6-8e27-7748ce30a287 VALID e IN_BETA_TESTING, verificado por API18:31 UTC. CI39280237485 correcta: compilaciÃ³n, firma, validaciÃ³n y upload. Evidencias en evidence/testflight-20261019/STATUS.md. No publicaciÃ³n en App Store ni cobros activados.

**Historial de subida:** permiso especÃ­fico recibido y seis secretos cifrados configurados en entorno main-only. Primera compilaciÃ³n0.2(1) interrumpida durante upload; recompilaciÃ³n0.2(2) completada y asignada al Ãºnico titular. No hay proceso recurrente pendiente.

Proyecto UIKit + WKWebView que reutiliza el Site privado y sus datos, con preparaciÃ³n nativa StoreKit 2 para suscribirse, restaurar y gestionar (productos desactivados). Actualizado el19/10/2026: barra nativa, Ã¡reas seguras, teclado, icono y puente web. IPA instalable mediante TestFlight; validaciÃ³n en iPhone fÃ­sico pendiente.

## Compilar

En macOS con Xcode y XcodeGen: ejecutar `bash ios/build-simulator.sh`. Compila y ejecuta NavigationPolicyTests en un iPhone del SDK instalado. El usuario autorizÃ³ un repositorio pÃºblico dedicado al cliente: https://github.com/Krazel/recetario-ios . Se conserva el servidor y el Site privados. CI manual macos-26 estÃ¡ndar, sin cachÃ© ni artefactos subidos; no activa gastos. Primer intento compilÃ³ pero el simulador iOS18.5 fallÃ³ por libswiftWebKit ausente. CI39274368977 superada: Xcode26.6, simulador iPhone17Pro/iOS26.4.1, cuatro tests aprobados. Detalles en evidence/iphone-20261019/QA.md. Esa prueba de simulador no utilizÃ³ firma; la subida posterior de 0.2 (2) sÃ­ estÃ¡ completada y verificada en TestFlight.

## Suscripciones

Bundle registrado `com.krazel.recetario`; productos previstos `.plus.monthly` y `.plus.annual`. Precios propuestos para EspaÃ±a: 4,99 EUR/mes y 34,99 EUR/aÃ±o; prueba prevista de7 dÃ­as para cuentas elegibles. No se han creado estos productos en Apple. La app muestra el precio y elegibilidad devueltos por StoreKit cuando estÃ©n habilitados.

El servidor verifica la firma con la biblioteca oficial de Apple y consulta el estado actual antes de conceder acceso. Vincula la compra al usuario mediante appAccountToken. Se renueva la verificaciÃ³n tras cinco minutos antes de acciones con cuota. La raÃ­z pÃºblica de Apple se conserva en lib/apple-root.ts; ninguna clave privada se incluye en la app.

APPLE_IAP_ENABLED permanece sin activar. Antes de pruebas Sandbox: crear la ficha y grupo/productos de App Store Connect, configurar credenciales de In-App Purchase en el servidor, y probar compra, pendiente, cancelaciÃ³n, expiraciÃ³n, devoluciÃ³n, restauraciÃ³n y cambio de cuenta. BILLING_ENABLED es independiente de los topes de dinero de OpenAI. Se mantienen 1 USD total, 0,20 USD/dÃ­a y 0,05 USD/solicitud.

## Pendiente antes de distribuciÃ³n comercial

- Probar en iPhone fÃ­sico inicio de sesiÃ³n del Site privado, cÃ¡mara/fotos, enlaces y navegaciÃ³n. CompilaciÃ³n y cuatro tests de simulador superados.
- Definir autenticaciÃ³n comercial y acceso de clientes sin abrir los recetarios privados.
- Icono final, privacidad/soporte pÃºblicos, declaraciones de privacidad y auditorÃ­a de dependencias existentes antes de publicar. La auditorÃ­a npm detectÃ³ avisos en dependencias previas; no se hicieron actualizaciones incompatibles por este encargo.
- Firma, archivo, IPA y TestFlight interno completados. TestFlight externo y App Review no iniciados.
- El enlace `krazel-recetario://import?url=...` estÃ¡ preparado; todavÃ­a no hay extensiÃ³n de Compartir nativa.

Consulta oficial GET /v1/apps?filter[name]=Recetario no devolviÃ³ fichas el 12/10/2026; no prueba ausencia de otra ficha con nombre diferente.


# 4/11/2026 · arranque local integrado, sin nueva build

El target existente abre el recetario local sin identidad. Cuenta online opcional usa el mismo Site/cookies y guardado automático en `/api/mobile-sync`. No depende del prototipo Supabase, un gateway o otro servidor. El acceso online del Site privado aún exige ChatGPT; Apple/Google propios y el fallo Safari no se declaran resueltos. Tres XCTest locales integrados, sin ejecutar en Windows. No se compila/sube ni se elimina el bloqueo de `testflight.json`. Detalle: `../evidence/ACCOUNT-BUDGET-SITE-20261104.md`.

# 4/11/2026 · cuentas propias dentro de la puerta temporal

Registro y acceso del Site ya preparados con correo/contraseña propios de Recetario. El WKWebView sigue pasando por la puerta de Sites y después usa la cuenta interior; logout nativo cierra solo Recetario. Borrado explícito borra la caché identificada de esa cuenta mediante bridge del mismo origen. Fuente `evidence/OWN-ACCOUNTS-SITE-20261104.md` en la raíz del producto. Sin build, subida ni QA física nueva; conservar `testflight.json` bloqueado hasta validar el acceso completo.
