"""Capture the running simulator's full screen. Emit original JPEGs, without resizing."""
import base64, hashlib, json, os, pathlib, struct, subprocess, sys, time

mode, device, family, output = sys.argv[1:]
out = pathlib.Path(output).resolve()
out.mkdir(parents=True, exist_ok=True)
accepted = {'iphone': {(1320, 2868), (1290, 2796), (1260, 2736)}, 'iphone-medium': {(1179, 2556), (1206, 2622)}, 'ipad': {(2064, 2752), (2048, 2732)}}
names = ['01-recetas', '02-receta', '03-cocinar', '04-menu', '05-compra', '06-despensa', '07-redes']
languages = ['en', 'es', 'ca', 'de', 'fr', 'it', 'pt']
chosen = os.environ['RECETARIO_STORE_LOCALE']
locales = languages if chosen == 'all' else [chosen]
if family not in accepted or any(locale not in languages for locale in locales):
    raise ValueError('Unknown device family or locale')
if mode == 'emit':
    for locale in locales:
        directory = out / locale
        manifest = json.loads((directory / 'manifest.json').read_text())
        if [screen['name'] for screen in manifest['screens']] != names:
            raise ValueError('Incomplete native capture set')
        print('RECETARIO_STORE_MANIFEST=' + json.dumps(manifest, separators=(',', ':')), flush=True)
        for screen in manifest['screens']:
            # Original full-device JPEGs are accepted by the stores. PNG is
            # captured and checked as a resolution proof, but not log-encoded.
            encoded = base64.b64encode((directory / (screen['name'] + '.jpg')).read_bytes()).decode()
            label = locale + ':' + family + ':' + screen['name'] + ':jpg'
            print('RECETARIO_STORE_IMAGE_BEGIN=' + label + ':' + str(len(encoded)), flush=True)
            for n in range(0, len(encoded), 4096):
                print('RECETARIO_STORE_IMAGE_CHUNK=' + label + ':' + str(n // 4096) + ':' + encoded[n:n+4096], flush=True)
            print('RECETARIO_STORE_IMAGE_END=' + label, flush=True)
    sys.exit(0)
if mode != 'watch':
    raise ValueError('Unknown mode')
release = json.loads(pathlib.Path('testflight.json').read_text())
manifests = {locale: {'locale': locale, 'formats': ['jpg'], 'commonBundleManifestSHA256': release['commonBundleManifestSHA256'], 'identity': 'ReciSave A4 definitive', 'family': family, 'simulatorId': device, 'sourceCommit': os.environ.get('GITHUB_SHA', ''), 'appSourceCommit': os.environ.get('GITHUB_SHA', ''), 'version': release['marketingVersion'], 'build': release['buildNumber'], 'capture': 'xcrun simctl io screenshot; full device, original JPEG. PNG resolution proof captured and hashed on runner.', 'fixture': 'own localized demonstration text; existing approved art; no AI calls', 'screens': []} for locale in locales}
container = None
last = None
deadline = time.time() + 42 * 60
while time.time() < deadline:
    if container is None:
        result = subprocess.run(['xcrun', 'simctl', 'get_app_container', device, 'com.krazel.recetario', 'data'], capture_output=True, text=True)
        if result.returncode == 0:
            container = pathlib.Path(result.stdout.strip()) / 'Documents'
        else:
            time.sleep(1)
            continue
    try:
        value = json.loads((container / 'recetario-store-request.json').read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        time.sleep(.2)
        continue
    name, locale = value.get('name'), value.get('locale')
    if (locale, name) == last:
        time.sleep(.2)
        continue
    if name not in names or locale not in locales:
        raise ValueError('Unexpected capture request')
    ack = {'name': name, 'locale': locale, 'ok': False}
    try:
        directory = out / locale
        directory.mkdir(parents=True, exist_ok=True)
        manifest = manifests[locale]
        if any(screen['name'] == name for screen in manifest['screens']):
            raise ValueError('Duplicate native capture')
        files = {}
        for fmt, kind in [('png', 'png'), ('jpg', 'jpeg')]:
            target = directory / (name + '.' + fmt)
            subprocess.run(['xcrun', 'simctl', 'io', device, 'screenshot', '--type=' + kind, str(target)], check=True, capture_output=True, timeout=60)
            data = target.read_bytes()
            files[fmt] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
        raw = (directory / (name + '.png')).read_bytes()
        if raw[:8] != b'\x89PNG\r\n\x1a\n':
            raise ValueError('Not a PNG capture')
        width, height = struct.unpack('>II', raw[16:24])
        if (width, height) not in accepted[family]:
            raise ValueError('Unexpected native resolution ' + str((width, height)))
        manifest['screens'].append({'name': name, 'width': width, 'height': height, 'files': files})
        (directory / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        ack['ok'] = True
        print('Captured actual simulator screen: ' + locale + '/' + family + '/' + name, flush=True)
    except Exception as error:
        ack['error'] = str(error)[:400]
    temporary = container / 'recetario-store-ack.tmp'
    temporary.write_text(json.dumps(ack))
    temporary.replace(container / 'recetario-store-ack.json')
    last = (locale, name)
    if not ack['ok']:
        raise RuntimeError(ack['error'])
    if all(len(manifest['screens']) == len(names) for manifest in manifests.values()):
        break
