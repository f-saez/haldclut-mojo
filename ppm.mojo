from pathlib import Path
from testing import assert_equal
from memory import AddressSpace
from time import now
from helpers import set_extension

@value
struct Image:
    var pixels      : DTypePointer[DType.uint8, AddressSpace.GENERIC]
    var _num_pixels : Int    
    var _width      : Int
    var _height     : Int
    var _stride     : Int
    var _bpp        : Int
    
    fn __init__(inout self, pixels : DTypePointer[DType.uint8, AddressSpace.GENERIC], width : Int, height : Int):
        self.pixels = pixels
        self._width  = width
        self._height = height
        self._num_pixels = width*height
        self._bpp    = 4
        self._stride = width*self._bpp

    @staticmethod
    fn new(width : Int, height : Int) -> Self:
        var pixels = DTypePointer[DType.uint8, AddressSpace.GENERIC]().alloc(width*height*4, alignment=32) # alignment on 256 bits, not sure it is usefull 
        return Self(pixels, width, height)

    fn to_ppm(self,filename : Path ) raises -> Bool:        
        var w = self.get_width()
        var h = self.get_height()
        var header = "P6\n"+String(w)+" "+String(h)+"\n255\n"  
        var bytes = List[UInt8](capacity=self.get_width()*self.get_height()*3)
        
        for adr in range(self._num_pixels): 
            var rgba = self.pixels.load[width=4](adr*self._bpp)
            bytes.append( rgba[0] )
            bytes.append( rgba[1] )
            bytes.append( rgba[2] )
        var t = len(bytes)
        bytes.append(bytes[t-1]) # write remove the last byte of everything, string or not, so ...
        with open( set_extension(filename,"ppm"), "wb") as f:
            f.write(header)
            f.write(bytes)  # expect a string but is happy to accept a bunch of bytes (why ?), except it just eat the last byte thinking it's a zero-terminal string        
        return True

    @staticmethod
    fn from_ppm(filename : Path) raises -> Self:
        """
        Only PPM P6 => RGB <=> 3xUInt8
        PPM could contains a comment and the comment must begin with #
        here we see a point of failure because we could use a comment starting with a digit
        and it will break the with/height detection
        a good pratice'll have been to put the mandatory fields (width/height/maxval) right after the magic byte 
        and the facultative comment at the end of the header.
        """        
        var width = 0
        var height = 0
        var idx = 0
        var file_name = set_extension(filename,"ppm")
        if file_name.is_file():
            var header = List[UInt8]()
            with open( file_name, "rb") as f:
                header = f.read_bytes(512)
            if header[0] == 0x50 and header[1] == 0x36:  # => P6 
                idx = 2
                for _ in range(idx, header.size):  # entering a comment area that may not exist
                    if header[idx] == 0x0A:
                        if header[idx+1]!=ord("#"):  # it's not a comment                        
                            break
                    idx += 1
                var idx_start = idx
                for _ in range(idx, header.size):  # the width
                    if header[idx] == 0x20:                        
                        idx += 1
                        width = atol( String(header[idx_start:idx]) )
                        break
                    idx += 1
                idx_start = idx
                for _ in range(idx, header.size): # the height
                    if header[idx] == 0x0A:
                        idx += 1
                        height = atol( String(header[idx_start:idx]) )
                        break
                    idx += 1
                for _ in range(idx, header.size):  # MAXVAL. I don't care because I only use Uint8 
                    if header[idx] == 0x0A:
                        idx += 1 
                        break
                    idx += 1                    

        var result = Self.new(width,height)
        if width>0 and height>0:
            var bytes = List[UInt8](capacity=width*height*3)
            with open(file_name, "rb") as f:
                bytes = f.read_bytes()   
            if bytes.size>=width*height*3:
                for idx1 in range(0,result.get_num_bytes(),4):
                    result.pixels[idx1]   = bytes[idx]
                    result.pixels[idx1+1] = bytes[idx+1]
                    result.pixels[idx1+2] = bytes[idx+2]
                    result.pixels[idx1+3] = 255
                    idx  += 3
        return result
    
    fn __del__(owned self):
        self.pixels.free()

    @always_inline
    fn get_num_bytes(self) -> Int:
        return self._num_pixels*self._bpp

    @always_inline
    fn get_num_pixels(self) -> Int:
        return self._num_pixels

    @always_inline
    fn get_width(self) -> Int:
        return self._width
    
    @always_inline
    fn get_height(self) -> Int:
        return self._height

    @always_inline
    fn get_stride(self) -> Int:
        return self._stride

    @always_inline
    fn get_num_channels(self) -> Int:
        return 4

    @always_inline
    fn get_mpixels(self) -> Float32:
        return Float32(self.get_height()*self.get_width()) / Float32(1024*1024)

    @staticmethod
    fn validation() raises :      
        var filename = Path("test/result.ppm") # this file have a comment
        var ppm = Image.from_ppm(filename)
        assert_equal(ppm.get_width(),320)
        assert_equal(ppm.get_height(),214)
        assert_equal(ppm.get_num_channels(),4)
        var y = 0
        var x = 0
        # first pixel is red
        var rgba = ppm.get_at(x,y)
        assert_equal(rgba[0],255)
        assert_equal(rgba[1],0)
        assert_equal(rgba[2],0)
        assert_equal(rgba[3],255)

        # second pixel is green
        x = 1
        rgba = ppm.get_at(x,y)
        assert_equal(rgba[0],0)
        assert_equal(rgba[1],255)
        assert_equal(rgba[2],0)
        assert_equal(rgba[3],255)

        # third pixel is blue
        x = 2
        rgba = ppm.get_at(x,y)
        assert_equal(rgba[0],0)
        assert_equal(rgba[1],0)
        assert_equal(rgba[2],255)
        assert_equal(rgba[3],255)

        # fourth pixel is black
        x = 3
        rgba = ppm.get_at(x,y)
        assert_equal(rgba[0],0)
        assert_equal(rgba[1],0)
        assert_equal(rgba[2],0)
        assert_equal(rgba[3],255)

        # fifth pixel is white
        x = 4
        rgba = ppm.get_at(x,y)
        assert_equal(rgba[0],255)
        assert_equal(rgba[1],255)
        assert_equal(rgba[2],255)
        assert_equal(rgba[3],255)

        filename = Path("test/result2.ppm") # this file have no comment
        ppm = Image.from_ppm(filename)
        assert_equal(ppm.get_num_channels(),4)
        assert_equal(ppm.get_width(),298)
        assert_equal(ppm.get_height(),205)
        y = 0
        x = 0
        # first pixel is red
        rgba = ppm.get_at(x,y)
        assert_equal(rgba[0],255)
        assert_equal(rgba[1],0)
        assert_equal(rgba[2],0)
        assert_equal(rgba[3],255)

        # second pixel is green
        x = 1
        rgba = ppm.get_at(x,y)
        assert_equal(rgba[0],0)
        assert_equal(rgba[1],255)
        assert_equal(rgba[2],0)
        assert_equal(rgba[3],255)

        # third pixel is blue
        x = 2
        rgba = ppm.get_at(x,y)
        assert_equal(rgba[0],0)
        assert_equal(rgba[1],0)
        assert_equal(rgba[2],255)
        assert_equal(rgba[3],255)

        # fourth pixel is black
        x = 3
        rgba = ppm.get_at(x,y)
        assert_equal(rgba[0],0)
        assert_equal(rgba[1],0)
        assert_equal(rgba[2],0)
        assert_equal(rgba[3],255)

        # fifth pixel is white
        x = 4 
        rgba = ppm.get_at(x,y)
        #assert_equal(rgba[0],255)
        assert_equal(rgba[1],255)
        assert_equal(rgba[2],255)
        assert_equal(rgba[3],255)


  

