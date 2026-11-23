from pathlib import Path
from subprocess import run
from tempfile import TemporaryDirectory

root = Path(__file__).resolve().parents[1]

def render(svg, size, path):
    run(['rsvg-convert', '-w', str(size), '-h', str(size), '-o', str(path)], input=svg.encode(), check=True)

neck = 'M7 1.3 Q5.7 1.3 6 3 L6.8 6.6 Q7 7.6 5.3 9.3 Q4.7 10 4.7 11 V15.4 Q4.7 16.6 6 16.6 H10 Q11.3 16.6 11.3 15.4 V11 Q11.3 10 10.7 9.3 Q9 7.6 9.2 6.6 L10 3 Q10.3 1.3 9 1.3 Z'
for state in ['on', 'off', 'unknown']:
    shift = -2 if state == 'unknown' else 1
    body = f'<g transform="translate({shift} 0)" fill="none" stroke="black" stroke-width="1.6" stroke-linejoin="round"><path d="{neck}"/></g>'
    if state == 'on':
        body += '<rect x="5.8" y="11" width="6.4" height="5" rx=".7"/>'
    elif state == 'off':
        body = '<defs><mask id="cut"><rect width="18" height="18" fill="white"/><path d="M2 2 L16 16" stroke="black" stroke-width="4"/></mask></defs><g mask="url(#cut)">' + body + '</g><path d="M2 2 L16 16" stroke="black" stroke-width="1.8" stroke-linecap="round"/>'
    else:
        body += '<path d="M11.5 7.8 C11.7 4.7 16.7 4.8 16.7 7.7 C16.7 10 14 10.1 14 12.3" fill="none" stroke="black" stroke-width="1.8" stroke-linecap="round"/><circle cx="14" cy="15" r="1.1"/>'
    for size, suffix in [(18,''),(36,'@2x')]:
        render(f'<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18">{body}</svg>', size, root / f'ampoule-{state}{suffix}.png')

with TemporaryDirectory() as tmp:
    iconset = Path(tmp) / 'AppIcon.iconset'
    iconset.mkdir()
    for base in [16,32,128,256,512]:
        for scale, suffix in [(1,''),(2,'@2x')]:
            render((root/'src/app.svg').read_text(), base*scale, iconset/f'icon_{base}x{base}{suffix}.png')
    types = ['icp4','ic11','icp5','ic12','ic07','ic13','ic08','ic14','ic09','ic10']
    blocks = bytearray()
    for kind, path in zip(types, [iconset/f'icon_{n}x{n}{s}.png' for n in [16,32,128,256,512] for s in ['', '@2x']]):
        data = path.read_bytes()
        blocks.extend(kind.encode() + (8+len(data)).to_bytes(4,'big') + data)
    (root/'AppIcon.icns').write_bytes(b'icns' + (8+len(blocks)).to_bytes(4,'big') + blocks)
