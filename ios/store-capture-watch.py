"""Capture the running simulator's actual screen, never a resized WebView snapshot."""
import base64, hashlib, json, os, pathlib, re, struct, subprocess, sys, time

mode, device, family, output = sys.argv[1:]
out = pathlib.Path(output).resolve()
out.mkdir(parents=True, exist_ok=True)
accepted = {'iphone': {(1320, 2868), (1290, 2796), (1260, 2736)}, 'iphone-medium': {(1179, 2556), (1206, 2622)}, 'ipad': {(2064, 2752), (2048, 2732)}}
names = ['01-recetas', '02-receta', '03-cocinar', '04-menu', '05-compra', '06-despensa']
if family not in accepted:
    raise ValueError('Unknown device family')
if mode == 'emit':
    manifest = json.loads((out / 'manifest.json').read_text())
    if len(manifest['screens']) != 6:
        raise ValueError('Incomplete native capture set')
    print('RECETARIO_STORE_MANIFEST=' + json.dumps(manifest, separators=(',', ':')), flush=True)
    for screen in manifest['screens']:
        for fmt in ['png', 'jpg']:
            data = (out / (screen['name'] + '.' + fmt)).read_bytes()
            encoded = base64.b64encode(data).decode()
            label = family + ':' + screen['name'] + ':' + fmt
            print('RECETARIO_STORE_IMAGE_BEGIN=' + label + ':' + str(len(encoded)), flush=True)
            for n in range(0, len(encoded), 4096):
                print('RECETARIO_STORE_IMAGE_CHUNK=' + label + ':' + str(n // 4096) + ':' + encoded[n:n+4096], flush=True)
            print('RECETARIO_STORE_IMAGE_END=' + label, flush=True)
    sys.exit(0)
if mode != 'watch':
    raise ValueError('Unknown mode')
release = json.loads(pathlib.Path('testflight.json').read_text())
manifest = {'family': family, 'simulatorId': device, 'sourceCommit': os.environ.get('GITHUB_SHA', ''), 'appSourceCommit': os.environ.get('GITHUB_SHA', ''), 'version': release['marketingVersion'], 'build': release['buildNumber'], 'capture': 'xcrun simctl io screenshot (full device, original PNG and JPEG)', 'fixture': 'own text and existing approved art crops; no AI calls', 'screens': []}
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
    request = container / 'recetario-store-request.json'
    try:
        value = json.loads(request.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        time.sleep(.2)
        continue
    name = value.get('name')
    if name == last:
        time.sleep(.2)
        continue
    if name not in names:
        raise ValueError('Unexpected capture name')
    ack = {'name': name, 'ok': False}
    try:
        files = {}
        for fmt, kind in [('png', 'png'), ('jpg', 'jpeg')]:
            target = out / (name + '.' + fmt)
            subprocess.run(['xcrun', 'simctl', 'io', device, 'screenshot', '--type=' + kind, str(target)], check=True, capture_output=True, timeout=60)
            data = target.read_bytes()
            files[fmt] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
        raw = (out / (name + '.png')).read_bytes()
        if raw[:8] != b'\x89PNG\r\n\x1a\n':
            raise ValueError('Not a PNG capture')
        width, height = struct.unpack('>II', raw[16:24])
        if (width, height) not in accepted[family]:
            raise ValueError('Unexpected native screen resolution ' + str((width, height)))
        manifest['screens'].append({'name': name, 'width': width, 'height': height, 'files': files})
        (out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        ack['ok'] = True
        print('Captured actual simulator screen: ' + family + '/' + name, flush=True)
    except Exception as error:
        ack['error'] = str(error)[:400]
    temporary = container / 'recetario-store-ack.tmp'
    temporary.write_text(json.dumps(ack))
    temporary.replace(container / 'recetario-store-ack.json')
    last = name
    if not ack['ok']:
        raise RuntimeError(ack['error'])
    if len(manifest['screens']) == len(names):
        break
