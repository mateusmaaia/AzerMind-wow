"""Prepare the image-generated master artwork as WoW-compatible slice textures.

This is an asset export step: preserve masters, crop transparent gutters,
resample to declared texture sizes, and clear only the expandable frame centers.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps

ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'art/grimoire'
OUT=ROOT/'addon/AzerMind/Art/Grimoire'

def crop_art(image):
    image=image.convert('RGBA')
    bounds=image.getchannel('A').point(lambda a: 255 if a>192 else 0).getbbox()
    if bounds is None:
        raise ValueError('Empty illustrated master')
    bounds=(max(0,bounds[0]-3),max(0,bounds[1]-3),min(image.width,bounds[2]+3),min(image.height,bounds[3]+3))
    image=image.crop(bounds)
    image.putalpha(image.getchannel('A').point(lambda a:0 if a<64 else a))
    return image

def save(name,image):
    (ART/'sources').mkdir(parents=True,exist_ok=True)
    OUT.mkdir(parents=True,exist_ok=True)
    image.save(ART/'sources'/f'{name}.png')
    image.save(OUT/f'{name}.tga',compression=None)

def rails(name,image,sx,sy):
    w,h=image.size
    # Mirror a short straight section and repeat it to get exact matching seams.
    for side in ['top','bottom','left','right']:
        tile=Image.new('RGBA',(256,256))
        if side in ['top','bottom']:
            y=0 if side=='top' else h-sy
            piece=image.crop((w//2-64,y,w//2,y+sy))
            for x in range(0,256,128):
                tile.paste(piece,(x,0));tile.paste(ImageOps.mirror(piece),(x+64,0))
        else:
            x=0 if side=='left' else w-sx
            piece=image.crop((x,h//2-64,x+sx,h//2))
            for y in range(0,256,128):
                tile.paste(piece,(0,y));tile.paste(ImageOps.flip(piece),(0,y+64))
        save(f'{name}-{side}',tile)

def build():
    window=crop_art(Image.open(ART/'masters/window-frame.png')).resize((1024,1024),Image.Resampling.LANCZOS)
    # Alpha cleanup outside protected borders prevents isolated generation noise.
    ImageDraw.Draw(window).rectangle((192,192,831,831),fill=(0,0,0,0))
    for name in ['frame-window','frame-panel','frame-popup']:
        save(name,window)
    rails('frame-window',window,192,192)
    window.save(ART/'previews/frames.png')
    master=Image.open(ART/'masters/controls.png').convert('RGBA')
    midx,midy=master.width//2,master.height//2
    crops=[(0,0,midx,midy),(midx,0,master.width,midy),(0,midy,midx,master.height),(midx,midy,master.width,master.height)]
    buttons=[crop_art(master.crop(box)).resize((512,256),Image.Resampling.LANCZOS) for box in crops]
    for name,index in [('button-paper',0),('button-primary',1),('conversation-selection',1),('button-secondary',2)]:
        save(name,buttons[index])
    for name,index in [('button-paper',0),('button-primary',1),('button-secondary',2)]:
        rails(name,buttons[index],64,64)
    field=buttons[3].copy()
    ImageDraw.Draw(field).rectangle((64,64,447,191),fill=(0,0,0,0))
    for name in ['frame-card','frame-input']:
        save(name,field)
    rails('frame-card',field,64,64)
    preview=Image.new('RGBA',(1024,512),'#28190f')
    for i,image in enumerate(buttons):preview.alpha_composite(image,(i%2*512,i//2*256))
    preview.convert('RGB').save(ART/'previews/illustrated-controls.png')
    for kind in ['copy','resend','delete','user','items','quests','instances','character','settings']:
        Image.open(ART/'sources'/f'icon-{kind}.png').convert('RGBA').save(OUT/f'icon-{kind}.tga',compression=None)
    print('Exported 9 illustrated skins and 20 repeating rails from preserved masters.')

if __name__=='__main__':build()
