"""Reproduce the exact PixelLab grid recipes locally and export WoW TGA textures."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'art' / 'grimoire'
TARGET = ROOT / 'addon' / 'AzerMind' / 'Art' / 'Grimoire'

def build():
    (ART / 'sources').mkdir(parents=True, exist_ok=True)
    TARGET.mkdir(parents=True, exist_ok=True)
    for name in ['leather', 'parchment', 'parchment-warm']:
        recipe = json.loads((ART / 'recipes' / (name + '.json')).read_text())
        image = Image.new('RGBA', tuple(recipe['job']['canvas']))
        for grid in recipe['scene']['views']['material']['nodes']['texture']['draw']:
            ox, oy = grid['at']
            for y, row in enumerate(grid['rows']):
                for x, key in enumerate(row):
                    color = grid['legend'][key].lstrip('#')
                    image.putpixel((ox+x, oy+y), tuple(bytes.fromhex(color)) + (255,))
        image.save(ART / 'sources' / (name + '.png'))
    for name in ['emblem', 'leather', 'parchment', 'parchment-warm']:
        with Image.open(ART / 'sources' / (name + '.png')) as source:
            source.convert('RGBA').save(TARGET / (name + '.tga'), compression=None)

    # Show each material repeated 2x2, with a text sample over the actual paper.
    sheet = Image.new('RGB', (1560, 590), '#17100c')
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 18)
        body = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 19)
    except OSError:
        font = body = ImageFont.load_default()
    for i, (name, label) in enumerate([
        ('leather', 'COURO ESPRESSO'), ('parchment', 'PERGAMINHO MARFIM'),
        ('parchment-warm', 'PERGAMINHO QUENTE / IA')
    ]):
        left = 12 + i*516
        draw.text((left, 14), label, fill='#ead9b8', font=font)
        tile = Image.open(ART / 'sources' / (name + '.png')).convert('RGB')
        for y in range(2):
            for x in range(2):
                sheet.paste(tile, (left+x*256, 50+y*256))
        if i:
            draw.text((left+24, 92), 'AzerMind', fill='#38251b', font=body)
            draw.text((left+24, 136), 'Conhecimento para sua aventura.', fill='#38251b', font=body)
            draw.text((left+24, 175), 'Texto sobre o fundo real, repetido 2 x 2.', fill='#38251b', font=body)
    (ART / 'previews').mkdir(exist_ok=True)
    sheet.save(ART / 'previews' / 'materials.png')
    print('Built 4 PNG sources, 4 RGBA TGA textures, and materials preview.')

if __name__ == '__main__':
    build()
