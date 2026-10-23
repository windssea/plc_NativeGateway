"""Render documentation pages and contact sheets for visual review."""
from pathlib import Path
import json
import pypdfium2 as pdfium
from pypdf import PdfReader
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
path = root / 'output/pdf/NativeGateway-项目说明.pdf'
out = root / 'tmp/pdfs/project-doc-review'
out.mkdir(parents=True, exist_ok=True)
reader = PdfReader(path)
texts = [p.extract_text() for p in reader.pages]
assert len(texts) > 10
assert '持久化' in ''.join(texts)
assert '{{' not in ''.join(texts)
pdf = pdfium.PdfDocument(str(path))
thumbs = []
for i in range(len(pdf)):
    page = pdf[i]
    img = page.render(scale=1.35).to_pil().convert('RGB')
    img.save(out / f'page-{i+1:02}.png')
    img.thumbnail((290, 410))
    tile = Image.new('RGB', (310, 440), '#dae3ec')
    tile.paste(img, ((310-img.width)//2, 20))
    ImageDraw.Draw(tile).text((12, 422), f'Page {i+1}', fill='#182c42')
    thumbs.append(tile)
    page.close()
for base in range(0, len(thumbs), 8):
    sheet = Image.new('RGB', (1240, 880), 'white')
    for j, tile in enumerate(thumbs[base:base+8]):
        sheet.paste(tile, ((j%4)*310, (j//4)*440))
    sheet.save(out / f'contact-{base//8+1:02}.png')
result = {'pages': len(texts), 'characters': sum(map(len, texts)), 'examplesValidated':
          json.loads((root/'docs/examples/validation.json').read_text(encoding='utf-8'))['passed'],
          'pageCharacters': [len(t) for t in texts], 'renderedDirectory': str(out)}
(out/'review.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
print(json.dumps(result))
