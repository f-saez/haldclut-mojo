
from pathlib import Path
from haldclut import HaldClut
from ppm import Image
from time import now

def main():
    aaa = HaldClut.from_ppm( Path("validation").joinpath("haldclut") )
    if aaa:
        haldclut = aaa.take()

        img = Image.from_ppm(Path("validation").joinpath("woman"))
        tic = now()
        haldclut.process(img, 0.22, 8)
        t = Float64(now() - tic) / 1e6
        print("time : ",t," ms")
        print("MPixels/s : ", img.get_mpixels()/t*1000)
        _ = img.to_ppm(Path("validation").joinpath("result"))

