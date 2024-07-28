
from pathlib import Path
from haldclut import HaldClut
from ppm import Image
from time import now

def main():
    aaa = HaldClut.from_ppm( Path("validation").joinpath("haldclut") )
    if aaa:
        haldclut = aaa.take()

        img = Image.from_ppm(Path("validation").joinpath("woman"))

        haldclut.process(img, 0.22)
        _ = img.to_ppm(Path("validation").joinpath("result"))