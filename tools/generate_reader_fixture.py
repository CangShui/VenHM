"""Generate deterministic, network-independent reader usability pages."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1] / 'entry/src/main/resources/rawfile/usability'
root.mkdir(parents=True, exist_ok=True)
font = ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf', 64)
small = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 28)
for chapter in range(1, 3):
    for page in range(1, 4):
        image = Image.new('RGB', (600, 900), ('#163b65', '#204d3d')[chapter - 1])
        draw = ImageDraw.Draw(image)
        draw.text((40, 70), 'VENERA HM', font=font, fill='white')
        draw.text((40, 270), f'CHAPTER {chapter}', font=font, fill='white')
        draw.text((40, 370), f'PAGE {page} / 3', font=font, fill='#f8d179')
        draw.text((40, 660), 'OFFLINE USABILITY FIXTURE', font=small, fill='white')
        draw.text((40, 720), 'No network / No source script', font=small, fill='white')
        image.save(root / f'c{chapter}p{page}.png', optimize=True)
print(f'Generated six 600x900 test pages in {root}')
