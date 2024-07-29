from pathlib import Path
from ppm import Image
from math import cbrt, sqrt
from helpers import set_extension
from algorithm import parallelize

# inspired by the work of Eskil Steenberg
# http://www.quelsolaar.com/technology/clut.html

@value
struct HaldClut:
	var clut         : DTypePointer[DType.float32]
	var level_haldclut : Int
	var level        : Int
	var level_square : Int
	var div_level255 : Float32
	var _num_threads : Int

	fn __init__(inout self, level : Int):
		self.level_haldclut = level
		self.level = level * level
		self.level_square = self.level * self.level
		var level255 = 255. / Float32(self.level - 1)	
		self.div_level255 = 1 / level255 # a "mul" is faster than a "div"
		var width = self.level_haldclut * self.level
		self.clut = DTypePointer[DType.float32]().alloc(width*width*4)
		self._num_threads = 1	

	fn identity(inout self):
		var cube_size = self.level_haldclut * self.level_haldclut
		var cube_size1 = Float32(cube_size - 1)

		var i = 0
		var rgba = SIMD[DType.float32,4](0.0, 0.0, 0, 1.0)
		for blue in range(cube_size):
			rgba[2] = Float32(blue) / cube_size1
			for green in range(cube_size):
				rgba[1] = Float32(green) / cube_size1
				for red in range(cube_size):
					rgba[0] = Float32(red) / cube_size1
					self.clut.store[width=4](i, rgba)
					i += 4
					

	@parameter
	@always_inline
	fn set_num_threads(inout self, num_threads : Int):
		if num_threads>0 and num_threads<1024:
			self._num_threads = num_threads

	@parameter
	@always_inline
	fn get_num_threads(self) -> Int:
		return self._num_threads

	@parameter
	@always_inline
	fn get_width(self) -> Int:
		return self.level_haldclut * self.level

	fn downsize(self, level : Int) -> Self:
		var haldclut2 = Self(level)
		haldclut2.identity()
		var width = haldclut2.get_width()
		self.process_4xf32_(haldclut2.clut, width, width, width*4, 1.0 )
		haldclut2.set_num_threads( self.get_num_threads() )
		return haldclut2

	@staticmethod
	fn from_ppm(filename : Path) raises -> Optional[Self]:

		var result = Optional[Self](None)
		var error_message = String()
		var img = Image.from_ppm( filename )
		if img.get_num_bytes()>256: # not enough bytes for a usable HaldClut
			if img.get_width()==img.get_height():	
				var level = Int(cbrt[DType.float32]( Float32(img.get_width()) ).cast[DType.int32]().value)
				var haldclut = Self(level)	
				var ps255_div = SIMD[DType.float32,4](1/255)
				var idx = 0
				for _ in  range(0,img.get_num_pixels()):
					var rgba = img.pixels.load[width=4](idx).cast[DType.float32]()
					rgba *= ps255_div
					haldclut.clut.store[width=4](idx, rgba)
					idx += 4
			
				result = Optional[Self](haldclut)
			else:
				error_message = "HaldClut is not a square "+String(img.get_width())+"x"+String(img.get_height())
		else:
			error_message = String("Unable to access file : ")+filename.__str__()
		return result

	fn to_ppm(self, filename : Path) raises -> Bool:
		var w = self.get_width()
		var header = "P6\n"+String(w)+" "+String(w)+"\n255\n"  
		var bytes = List[UInt8](capacity=w*w*3)
		var ps255 = SIMD[DType.float32,4](255)

		for adr in range(w*w): 
			var rgba = self.clut.load[width=4](adr*4) * ps255
			var rgb = rgba.cast[DType.uint8]()
			bytes.append( rgb[0] )
			bytes.append( rgb[1] )
			bytes.append( rgb[2] )
		var t = len(bytes)
		bytes.append(bytes[t-1]) # write remove the last byte of everything, string or not, so ...
		with open( set_extension(filename,"ppm"), "wb") as f:
			f.write(header)
			f.write(bytes)  
		return True

	fn process(self, inout img : Image, strength : Float32):
		var stride = img.get_stride()
		var height = img.get_height()
		var width = img.get_width()
		self.process_4xu8_(img.pixels, width, height, stride, strength)


	# TODO : add a fast path for the case where strength=1 
	fn process_4xu8_(self, pixels : DTypePointer[DType.uint8], width : Int, height : Int, stride : Int, strength : Float32):
		if strength>0:
			var coef = SIMD[DType.float32,4](strength)
			var coef1 = SIMD[DType.float32,4](1.0-strength)			
			var level4 = self.level*4
			var level_square4 = self.level_square*4
			var level4_level_square4 = level4 + level_square4
			var ps0  = SIMD[DType.float32,4](0)
			var ps1  = SIMD[DType.float32,4](1)
			var ps255 = SIMD[DType.float32,4](255)
			var epi32_0 = SIMD[DType.int32,4](0)
			var epi32_255 = SIMD[DType.int32,4](255)
			var ps_level2 = SIMD[DType.float32,4]( Float32(self.level - 2) )
			var coef_color = SIMD[DType.float32,4](1., Float32(self.level), Float32(self.level_square), 0.) 

			@parameter
			fn process_line(y : Int):	
				var idx = y*stride
				for _ in range(width):
					var rgb_src = pixels.load[width=4](idx).cast[DType.float32]()
					var rgb_src255 = rgb_src * self.div_level255 
					var r0 = rgb_src255.__round__()
					var tmp = r0.max(ps0)
					tmp = tmp.min(ps_level2)
					tmp *= coef_color

					var tmp_ = tmp.reduce_add[size_out=1]().cast[DType.int32]()
					var i = tmp_ * 4
					var i1 = i + level4
					var i2 = i + level_square4
					var i3 = i + level4_level_square4
					var rgb_fract = rgb_src255 - rgb_src255.__trunc__()
					var rgb1 = ps1 - rgb_fract
					
					var g = SIMD[DType.float32,4](rgb_fract[1])
					var b = SIMD[DType.float32,4](rgb_fract[2])

					var g1 = SIMD[DType.float32,4](rgb1[1])
					var b1 = SIMD[DType.float32,4](rgb1[2])
					
					var r_r1 = SIMD[DType.float32,8](rgb_fract[0],rgb_fract[0],rgb_fract[0],rgb_fract[0],rgb1[0],rgb1[0],rgb1[0],rgb1[0])
					var tmpa = self.clut.load[width=8](i)
					tmpa *= r_r1
					var tmp0 = tmpa.reduce_add[size_out=4]()
					tmpa = self.clut.load[width=8](i1)
					tmpa *= r_r1
					var tmp1 = tmpa.reduce_add[size_out=4]()
					var dst0 = tmp0 * g1 + tmp1 * g
					
					tmpa = self.clut.load[width=8](i2)
					tmpa *= r_r1
					tmp0 = tmpa.reduce_add[size_out=4]()

					tmpa = self.clut.load[width=8](i3)
					tmpa *= r_r1
					tmp1 = tmpa.reduce_add[size_out=4]()

					var dst1 = tmp0 * g1 + tmp1 * g
					var dst = (dst0 * b + dst1 * b1) * ps255
					dst = dst * coef + rgb_src * coef1
					var rgbi = dst.cast[DType.int32]().clamp(epi32_0, epi32_255)
					pixels.store[width=4](idx, rgbi.cast[DType.uint8]())
					idx += 4
			
			parallelize[process_line](height, self.get_num_threads() )

	# 4xf32 [0-1]
	fn process_4xf32_(self, pixels : DTypePointer[DType.float32], width : Int, height : Int, stride : Int, strength : Float32):
		if strength>0:
			var coef = SIMD[DType.float32,4](strength)
			var coef1 = SIMD[DType.float32,4](1.0-strength)			
			var level4 = self.level*4
			var level_square4 = self.level_square*4
			var level4_level_square4 = level4 + level_square4
			var ps0  = SIMD[DType.float32,4](0)
			var ps1  = SIMD[DType.float32,4](1)
			var ps255 = SIMD[DType.float32,4](255)
			var ps_div_255 = ps1 / ps255
			var ps_level2 = SIMD[DType.float32,4]( Float32(self.level - 2) )
			var coef_color = SIMD[DType.float32,4](1., Float32(self.level), Float32(self.level_square), 0.) 

			@parameter
			fn process_line(y : Int):	
				var idx = y*stride
				for _ in range(width):
					var rgb_src = pixels.load[width=4](idx) * ps255
					var rgb_src255 = rgb_src * self.div_level255 
					var r0 = rgb_src255.__round__()
					var tmp = r0.max(ps0)
					tmp = tmp.min(ps_level2)
					tmp *= coef_color

					var tmp_ = tmp.reduce_add[size_out=1]().cast[DType.int32]()
					var i = tmp_ * 4
					var i1 = i + level4
					var i2 = i + level_square4
					var i3 = i + level4_level_square4
					var rgb_fract = rgb_src255 - rgb_src255.__trunc__()
					var rgb1 = ps1 - rgb_fract
					
					var g = SIMD[DType.float32,4](rgb_fract[1])
					var b = SIMD[DType.float32,4](rgb_fract[2])

					var g1 = SIMD[DType.float32,4](rgb1[1])
					var b1 = SIMD[DType.float32,4](rgb1[2])
					
					var r_r1 = SIMD[DType.float32,8](rgb_fract[0],rgb_fract[0],rgb_fract[0],rgb_fract[0],rgb1[0],rgb1[0],rgb1[0],rgb1[0])
					var tmpa = self.clut.load[width=8](i)
					tmpa *= r_r1
					var tmp0 = tmpa.reduce_add[size_out=4]()
					tmpa = self.clut.load[width=8](i1)
					tmpa *= r_r1
					var tmp1 = tmpa.reduce_add[size_out=4]()
					var dst0 = tmp0 * g1 + tmp1 * g
					
					tmpa = self.clut.load[width=8](i2)
					tmpa *= r_r1
					tmp0 = tmpa.reduce_add[size_out=4]()

					tmpa = self.clut.load[width=8](i3)
					tmpa *= r_r1
					tmp1 = tmpa.reduce_add[size_out=4]()

					var dst1 = tmp0 * g1 + tmp1 * g
					var dst = (dst0 * b + dst1 * b1) * ps255
					dst = dst * coef + rgb_src * coef1
					var rgbi = dst.clamp(ps0, ps255) * ps_div_255
					pixels.store[width=4](idx, rgbi)
					idx += 4
			
			parallelize[process_line](height, self.get_num_threads() )

	fn __del__(owned self):
		self.clut.free()

			




		