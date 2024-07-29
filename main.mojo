
from pathlib import Path
from haldclut import HaldClut
from ppm import Image
from time import now
from testing import assert_equal

def main():

    aaa = HaldClut.from_ppm( Path("validation").joinpath("haldclut") )
    if aaa:
        haldclut = aaa.take()
        haldclut.set_num_threads(8) 
        img = Image.from_ppm(Path("validation").joinpath("woman"))
        tic = now()
        haldclut.process(img, 0.22)
        t = Float64(now() - tic) / 1e6
        print("time : ",t," ms")
        print("MPixels/s : ", img.get_mpixels()/t*1000)
        _ = img.to_ppm(Path("validation").joinpath("result"))

        img = Image.from_ppm(Path("validation").joinpath("woman"))
        tic = now()

    aaa = HaldClut.from_ppm( Path("validation").joinpath("grayscale") )
    if aaa:
        haldclut1 = aaa.take()        
        haldclut1.set_num_threads(8)  # processing with 8 threads
        
        # downsizing mean faster to process and a less memory used
        haldclut = haldclut1.downsize(8) # 8 is the level of the haldclut, haldclut1 is level 12
        _ = haldclut.to_ppm(Path("validation").joinpath("grayscale_level8"))

        # dowwnscaling keep the number of threads of the parent 
        assert_equal( haldclut.get_num_threads(), haldclut1.get_num_threads() )
        img = Image.from_ppm(Path("validation").joinpath("woman"))
        tic = now()
        haldclut.process(img, 1.)
        t = Float64(now() - tic) / 1e6
        print("time : ",t," ms")
        print("MPixels/s : ", img.get_mpixels()/t*1000)
        _ = img.to_ppm(Path("validation").joinpath("result_grayscale"))        

