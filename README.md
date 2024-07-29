# haldclut-mojo
HaldCLUT code for Mojo

"Color grading for the dummies". (https://en.wikipedia.org/wiki/Color_grading)

There are basically 3 types of graphical LUT.

-(HaldCLUT : This one came from video-game world : fast and GPU-friendly. It is the less precise (bilinear interpolation) of the bunch but no one cares. It's nothing more than a square image and you can store and them in lossless compression PNG, QOI or you own format (ZSTD/LZ4/... compression for example). Obviously, a PNG 16 bits will offer more precision than a PNG 8 bits as long as they have the same level.

- The Cube3D files, that came from grading/movie world. A little less faster, but more precise (Tetrahedral interpolation : 
https://blogs.mathworks.com/steve/2006/11/24/tetrahedral-interpolation-for-colorspace-conversion/). 
It's just a text file and it could become quite "big"

- The parametrical ones, but they're not really LUT anymore. Instead of relying on a bunch a discrete data (some Cube3D file are quite big), we rely on equations. It solves the problem of precision and the problem of "the name of my interpolation sounds way cooler than yours". But that's a story I will told you another day :-)


## Enough talk ! I wanna play !

The hardest part will be to find HaldCLUT and you may have some luck here :

https://github.com/cedeber/hald-clut

https://rawpedia.rawtherapee.com/Film_Simulation


In this example, I've choose to reduce the dependencies by using PPM file format.

```
aaa = HaldClut.from_ppm( Path("validation").joinpath("haldclut") )
if aaa:
    haldclut = aaa.take()

    img = Image.from_ppm(Path("validation").joinpath("woman"))
    # 0.22 is the % of the LUT that will be applied to the image. Beware of high values !
    # 8 is the number of threads
    haldclut.process(img, 0.22,8)
    _ = img.to_ppm(Path("validation").joinpath("result"))
```
