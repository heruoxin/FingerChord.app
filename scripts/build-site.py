#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Build the static website into a folder that works from any domain or subpath."""
from copy import deepcopy
import html
import json
from pathlib import Path
import plistlib
import re
import shutil
from string import Template
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'site'
URL = 'https://fingerchord.catchingnow.com/'
REPO = 'https://github.com/heruoxin/FingerChord.app'
DOWNLOAD = f'{REPO}/releases/latest/download/FingerChord.dmg'
LANGUAGES = {'zh-Hans': '简体中文', 'en': 'English', 'zh-Hant': '繁體中文'}
OG_LOCALES = {'zh-Hans': 'zh_CN', 'en': 'en_US', 'zh-Hant': 'zh_TW'}
SVG = '{http://www.w3.org/2000/svg}'
APPLE = ('<svg viewBox="0 0 24 28" aria-hidden="true"><path fill="currentColor" d="M18.9 14.6c0-3 2.5-4.5 2.6-4.6-1.4-2.1-3.6-2.4-4.4-2.4-1.9-.2-3.7 1.1-4.7 1.1-1 0-2.5-1.1-4.1-1.1-2.1 0-4 1.2-5.1 3-2.2 3.7-.6 9.1 1.5 12.1 1 1.5 2.2 3.1 3.8 3 1.5-.1 2.1-1 4-1s2.4 1 4.1.9c1.7 0 2.8-1.5 3.8-3 1.2-1.7 1.7-3.4 1.7-3.5-.1 0-3.2-1.2-3.2-4.5ZM15.7 5.7c.9-1.1 1.5-2.6 1.3-4.1-1.3.1-2.9.9-3.8 2-.8.9-1.6 2.5-1.4 4 1.5.1 3-.7 3.9-1.9Z"/></svg>')
GITHUB = ('<svg viewBox="0 0 16 16" aria-hidden="true"><path fill="currentColor" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0 0 16 8c0-4.42-3.58-8-8-8Z"/></svg>')
# Fingertips on a 480 × 300 trackpad, in the order index, middle, ring, little.
FINGERS = {
    'tap': [(178, 150, 'rest'), (240, 126, 'tap'), (302, 148, 'rest')],
    'three': [(176, 152, 'press'), (240, 126, 'press'), (304, 146, 'press')],
    'four': [(150, 160, 'press'), (212, 132, 'press'), (276, 128, 'press'), (338, 152, 'press')],
}


def esc(value):
    return html.escape(str(value), quote=True)


def lines(items):
    """Spaces keep stacked lines apart for plain-text readers; CSS drops them between block spans."""
    return ' '.join(f'<span>{esc(line)}</span>' for line in items)


def page_url(locale):
    return URL + ('' if locale == 'zh-Hans' else f'{locale}/')


def icon_layers(output):
    """Split the app icon into trackpad, tap arc and glass hand so the hero can animate each."""
    ET.register_namespace('', SVG[1:-1])
    icon = ET.parse(ROOT / 'Resources/AppIcon.svg').getroot()
    defs = icon.find(f'{SVG}defs')
    scene, arc, *hand = [child for child in icon if child is not defs]
    layers = {}
    pad = deepcopy(icon)
    pad[:] = [deepcopy(defs)]
    pad.find(f"{SVG}defs/{SVG}g[@id='scene']").remove(pad.find(f"{SVG}defs/{SVG}g[@id='scene']/{SVG}rect"))
    pad.append(deepcopy(scene))
    layers['pad'] = pad
    stroke = deepcopy(icon)
    stroke[:] = [deepcopy(arc)]
    layers['arc'] = stroke
    glass = deepcopy(icon)
    glass[:] = [deepcopy(defs), *map(deepcopy, hand)]
    layers['hand'] = glass
    for name, layer in layers.items():
        ET.ElementTree(layer).write(output / f'hero-{name}.svg', encoding='unicode')
    numbers = re.findall(r'[\d.]+', arc.get('d'))
    x0, y0, x1, y1 = map(float, numbers[:2] + numbers[-2:])
    return f'{(x0 + x1) / 20.48:.1f}% {(y0 + y1) / 20.48:.1f}%'


def download_button(content, version):
    return (f'<div class="download"><div class="download-actions">'
            f'<a class="download-button" href="{DOWNLOAD}">{APPLE}{esc(content["downloadMac"])}</a>'
            f'<a class="github-button" href="{REPO}">{GITHUB}GitHub</a></div>'
            f'<p class="download-meta">{version} · {esc(content["requirement"])}</p></div>')


def gesture_section(index, gesture):
    key = ['tap', 'three', 'four'][index]
    group = 'tap' if key == 'tap' else 'press'
    dots = ''.join(f'<circle class="dot {role}" cx="{x}" cy="{y}" r="18"/>' for x, y, role in FINGERS[key])
    if key == 'tap':
        x, y, _ = FINGERS[key][1]
        dots += f'<circle class="ripple" cx="{x}" cy="{y}" r="27"/>'
    tone = '244,45,98' if index % 2 else '244,0,100'
    return f'''  <section class="feature gesture" data-tone="{tone}" id="{key}" aria-labelledby="{key}-title">
    <div class="feature-grid wrap">
      <div class="section-copy"><h2 id="{key}-title">{esc(gesture["name"])}</h2><p class="section-intro">{esc(gesture["body"])}</p></div>
      <figure class="feature-art"><div class="pad-demo" data-gesture="{group}" role="img" aria-label="{esc(gesture["demo"])}"><svg viewBox="0 0 480 300" aria-hidden="true"><rect class="pad-surface" width="480" height="300" rx="28"/>{dots}</svg><span class="pad-action" aria-hidden="true">{esc(gesture["action"])}</span></div></figure>
    </div>
  </section>
'''


def metadata(locale, content, version):
    canonical = page_url(locale)
    graph = [
        {'@type': 'WebSite', '@id': URL + '#website', 'url': URL, 'name': 'FingerChord',
         'alternateName': ['指间', '指間'], 'inLanguage': list(LANGUAGES)},
        {'@type': 'WebPage', '@id': canonical + '#webpage', 'url': canonical, 'name': content['title'],
         'description': content['description'], 'inLanguage': locale, 'isPartOf': {'@id': URL + '#website'},
         'about': {'@id': URL + '#app'}},
        {'@type': 'SoftwareApplication', '@id': URL + '#app', 'name': content['brand'],
         'alternateName': [name for name in ['FingerChord', '指间', '指間'] if name != content['brand']],
         'description': content['description'], 'url': canonical, 'applicationCategory': 'UtilitiesApplication',
         'operatingSystem': 'macOS 27', 'softwareVersion': version, 'downloadUrl': DOWNLOAD,
         'image': URL + 'assets/icon.png', 'license': 'https://www.gnu.org/licenses/gpl-3.0.html', 'sameAs': REPO,
         'author': {'@type': 'Person', 'name': 'Ruoxin He'},
         'offers': {'@type': 'Offer', 'price': 0, 'priceCurrency': 'USD'}},
        {'@type': 'FAQPage', '@id': canonical + '#faq', 'inLanguage': locale, 'isPartOf': {'@id': canonical + '#webpage'},
         'mainEntity': [{'@type': 'Question', 'name': item['question'],
                         'acceptedAnswer': {'@type': 'Answer', 'text': item['answer']}} for item in content['helpItems']]},
    ]
    alternates = ''.join(f'\n  <link rel="alternate" hreflang="{code}" href="{page_url(code)}">' for code in LANGUAGES)
    og_alternates = ''.join(f'\n  <meta property="og:locale:alternate" content="{value}">'
                            for code, value in OG_LOCALES.items() if code != locale)
    data = json.dumps({'@context': 'https://schema.org', '@graph': graph}, ensure_ascii=False, separators=(',', ':')).replace('<', '\\u003c')
    return f'''<meta name="description" content="{esc(content["description"])}">
  <link rel="canonical" href="{canonical}">{alternates}
  <link rel="alternate" hreflang="x-default" href="{page_url('zh-Hans')}">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="{esc(content["brand"])}">
  <meta property="og:title" content="{esc(content["title"])}">
  <meta property="og:description" content="{esc(content["description"])}">
  <meta property="og:url" content="{canonical}">
  <meta property="og:locale" content="{OG_LOCALES[locale]}">{og_alternates}
  <meta property="og:image" content="{URL}assets/icon.png">
  <meta name="twitter:card" content="summary">
  <script type="application/ld+json">{data}</script>'''


def render(locale, content, version, arc_origin):
    base = './' if locale == 'zh-Hans' else '../'
    values = {key: esc(value) for key, value in content.items() if isinstance(value, str)}
    values.update({
        'locale': locale,
        'base': base,
        'headline': lines(content['headline']),
        'intro': '<br>'.join(esc(line) for line in content['intro']),
        'quietTitle': lines(content['quietTitle']),
        'closingTitle': lines(content['closingTitle']),
        'gestureSections': ''.join(gesture_section(index, gesture) for index, gesture in enumerate(content['gestures'])),
        'helpItems': ''.join(
            f'<details class="help-item" name="help"><summary>{esc(item["question"])}'
            f'<span class="help-toggle" aria-hidden="true"></span></summary><p>{esc(item["answer"])}</p></details>'
            for item in content['helpItems']),
        'downloadButton': download_button(content, version),
        'downloadURL': DOWNLOAD,
        'repoURL': REPO,
        'changelogURL': f'{REPO}/blob/main/CHANGELOG.md',
        'currentLanguage': LANGUAGES[locale],
        'languageLinks': ''.join(
            f'<a href="{base}{"" if code == "zh-Hans" else code + "/"}index.html" lang="{code}" hreflang="{code}"'
            + (' aria-current="page"' if code == locale else '') + f'>{label}</a>' for code, label in LANGUAGES.items()),
        'arcOrigin': arc_origin,
        'seoMetadata': metadata(locale, content, version),
    })
    return Template((SOURCE / 'page.html').read_text()).substitute(values)


def main():
    output = ROOT / '.build/site'
    shutil.rmtree(output, ignore_errors=True)
    (output / 'assets').mkdir(parents=True)
    content = json.loads((SOURCE / 'content.json').read_text())
    version = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())['CFBundleShortVersionString']
    arc_origin = icon_layers(output / 'assets')
    shutil.copyfile(ROOT / 'docs/media/icon.png', output / 'assets/icon.png')
    for locale in LANGUAGES:
        shutil.copyfile(ROOT / f'docs/media/settings-{locale}.png', output / f'assets/settings-{locale}.png')
        folder = output if locale == 'zh-Hans' else output / locale
        folder.mkdir(exist_ok=True)
        (folder / 'index.html').write_text(render(locale, content[locale], version, arc_origin))
    for name in ['style.css', 'site.js']:
        shutil.copyfile(SOURCE / name, output / name)
    (output / 'robots.txt').write_text(f'User-agent: *\nAllow: /\n\nSitemap: {URL}sitemap.xml\n')
    (output / 'sitemap.xml').write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
        + ''.join(f'  <url><loc>{page_url(locale)}</loc></url>\n' for locale in LANGUAGES) + '</urlset>\n')
    print(output / 'index.html')


if __name__ == '__main__':
    main()
