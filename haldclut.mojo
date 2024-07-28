from pathlib import Path
from ppm import Image
from math import cbrt
from helpers import set_extension
from algorithm import parallelize

# inspired by the work of Eskil Steenberg
# http://www.quelsolaar.com/technology/clut.html
@value
struct HaldClut:
	var clut         : DTypePointer[DType.float32]
	var level        : Int
	var level_square : Int
	var level255     : Float32

	@staticmethod
	fn from_ppm(filename : Path) raises -> Optional[Self]:

		var result = Optional[Self](None)
		var error_message = String()
		var img = Image.from_ppm( filename )
		if img.get_num_bytes()>256: # not enought bytes for a usable HaldClut
			if img.get_width()==img.get_height():		
				var clut = DTypePointer[DType.float32]().alloc(img.get_width()*img.get_height()*4)

				var ps255_div = SIMD[DType.float32,4](1/255)
				var idx = 0
				for _ in  range(0,img.get_num_pixels()):
					var rgba = img.pixels.load[width=4](idx).cast[DType.float32]()
					rgba *= ps255_div
					clut.store[width=4](idx, rgba)
					idx += 4
				var level = Int(cbrt[DType.float32]( Float32(img.get_width()) ).cast[DType.int32]().value)
				level = level * level
				var level_square = level * level
				var level255 = 255. / Float32(level - 1)
				var haldclut = Self (
					clut,
					level,
					level_square,
					level255,
				)
				result = Optional[Self](haldclut)
			else:
				error_message = "HaldClut is not a square "+String(img.get_width())+"x"+String(img.get_height())
		else:
			error_message = String("Unable to access file : ")+filename.__str__()
		return result


	fn process(self, inout img : Image, strength : Float32, num_threads : Int):
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
		var ps_level255 = SIMD[DType.float32,4](1/self.level255)
		var ps_level2 = SIMD[DType.float32,4]( Float32(self.level - 2) )
		var coef_color = SIMD[DType.float32,4](1., Float32(self.level), Float32(self.level_square), 0.) 

		var stride = img.get_stride()
		var height = img.get_height()
		var width = img.get_width()

		@parameter
		fn process_line(y : Int):	
			var idx = y*stride
			for _ in range(width):
				var rgb_src = img.pixels.load[width=4](idx).cast[DType.float32]()
				var rgb_src255 = rgb_src / self.level255
				var r0 = (rgb_src * ps_level255).__round__()
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
				img.pixels.store[width=4](idx, rgbi.cast[DType.uint8]())
				idx += 4
		
		parallelize[process_line](height,num_threads)

	fn __del__(owned self):
		self.clut.free()

			




		