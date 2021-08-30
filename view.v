/**********************************************************************
*
* simple Picture Viewer V. 0.7
*
* Copyright (c) 2021 Dario Deledda. All rights reserved.
* Use of this source code is governed by an MIT license
* that can be found in the LICENSE file.
*
* TODO:
* - add an example with shaders
**********************************************************************/
import os
import gg
import gx
//import math
import sokol.gfx
import sokol.sgl
import sokol.sapp
import stbi
import szip

const (
	win_width  = 800
	win_height = 800
	bg_color   = gx.black
	pi_2       = 3.14159265359 / 2.0
	uv         = [f32(0),0,1,0,1,1,0,1]!  // used for zoom icon during rotations
)

struct App {
mut:
	gg             &gg.Context
	pip_3d         C.sgl_pipeline
	texture        C.sg_image
	texture_filler C.sg_image
	init_flag      bool
	frame_count    int
	mouse_x        int = -1
	mouse_y        int = -1
	scroll_y       int
	
	// translation
	tr_flag     bool
	tr_x        f32 = 0.0
	tr_y        f32 = 0.0
	last_tr_x   f32 = 0.0
	last_tr_y   f32 = 0.0
	// scaling
	sc_flag     bool
	scale       f32 = 1.0
	sc_x        f32 = 0.0
	sc_y        f32 = 0.0
	last_sc_x   f32 = 0.0
	last_sc_y   f32 = 0.0
	
	// loaded image
	img_w       int
	img_h       int
	img_ratio   f32 = 1.0
	
	// item list
	item_list   Item_list
	
	// Text info and help
	show_info_flag bool = true
	show_help_flag bool
	
	// zip container 
	zip          &szip.Zip // pointer to the szip structure
	zip_index    int = -1  // index of the zip contaire item
		
	// memory buffer
	mem_buf        voidptr   // buffer used to load items from files/containers
	mem_buf_size   int       // size of the buffer
}

/******************************************************************************
*
* Texture functions
*
******************************************************************************/
fn create_texture(w int, h int, buf &u8) C.sg_image {
	sz := w * h * 4
	mut img_desc := C.sg_image_desc{
		width: w
		height: h
		num_mipmaps: 0
		min_filter: .linear
		mag_filter: .linear
		// usage: .dynamic
		wrap_u: .clamp_to_edge
		wrap_v: .clamp_to_edge
		label: &byte(0)
		d3d11_texture: 0
	}
	// comment if .dynamic is enabled
	img_desc.data.subimage[0][0] = C.sg_range{
		ptr: buf
		size: size_t(sz)
	}

	sg_img := C.sg_make_image(&img_desc)
	return sg_img
}

fn destroy_texture(sg_img C.sg_image) {
	C.sg_destroy_image(sg_img)
}

// Use only if: .dynamic is enabled
fn update_text_texture(sg_img C.sg_image, w int, h int, buf &byte) {
	sz := w * h * 4
	mut tmp_sbc := C.sg_image_data{}
	tmp_sbc.subimage[0][0] = C.sg_range{
		ptr: buf
		size: size_t(sz)
	}
	C.sg_update_image(sg_img, &tmp_sbc)
}

/******************************************************************************
*
* Memory buffer
*
******************************************************************************/
[inline]
fn (mut app App) resize_buf_if_needed(in_size int) {
	// manage the memory buffer
	if app.mem_buf_size < in_size {
		println("Managing FILE memory buffer, allocated [${in_size}]Bytes")
		// free previous buffer if any exist
		if app.mem_buf_size > 0 {
			unsafe{
				free(app.mem_buf)
			}
		}
		// allocate the memory
		unsafe {
			app.mem_buf = malloc(int(in_size))
			app.mem_buf_size = int(in_size)
		}
	}
}

/******************************************************************************
*
* Loading functions
*
******************************************************************************/
// read_bytes from file in `path` in the memory buffer of app.
[manualfree]
fn (mut app App) read_bytes(path string) bool {
	mut fp := os.vfopen(path, 'rb') or {
		eprintln("ERROR: Can not open the file [$path].")
		return false
	}
	defer {
		C.fclose(fp)
	}
	cseek := C.fseek(fp, 0, C.SEEK_END)
	if cseek != 0 {
		eprintln("ERROR: Can not seek in the file [$path].")
		return false
	}
	fsize := C.ftell(fp)
	if fsize < 0 {
		eprintln("ERROR: File [$path] has size is 0.")
		return false
	}
	C.rewind(fp)
	
	app.resize_buf_if_needed(int(fsize))
		
	nr_read_elements := int(C.fread(app.mem_buf, fsize, 1, fp))
	if nr_read_elements == 0 && fsize > 0 {
		eprintln("ERROR: Can not read the file [$path] in the memory buffer.")
		return false
	}
	return true
}

// read a file as []byte
pub fn read_bytes_from_file(file_path string) []byte {
	mut buffer := []byte{}
	buffer = os.read_bytes(file_path) or {
		eprintln('ERROR: Texure file: [$file_path] NOT FOUND.')
		exit(0)
	}
	return buffer
}

fn (mut app App) load_texture_from_buffer(buf voidptr, buf_len int) (C.sg_image, int, int) {
	// load image
	stbi.set_flip_vertically_on_load(true)
	img := stbi.load_from_memory(buf, buf_len) or {
		eprintln('ERROR: Can not load image from buffer, file: [${app.item_list.lst[app.item_list.item_index]}].')
		return app.texture_filler, 256, 256
		//exit(1)
	}
	res := create_texture(int(img.width), int(img.height), img.data)
	unsafe {
		img.free()
	}
	return res, int(img.width), int(img.height)
}

pub fn (mut app App) load_texture_from_file(file_name string) (C.sg_image, int, int) {
	//buffer := read_bytes_from_file(file_name)
	app.read_bytes(file_name)
	return app.load_texture_from_buffer(app.mem_buf, app.mem_buf_size)
}

pub fn load_image(mut app App) {
	clear_modifier_params(mut app)
	destroy_texture(app.texture)
	
	// load from .ZIP file
	if app.item_list.is_inside_a_container() == true {
		app.texture, app.img_w, app.img_h = app.load_texture_from_zip() or {
			eprintln('ERROR: Can not load image from .ZIP file [${app.item_list.lst[app.item_list.item_index]}].')
			return
		}
		app.img_ratio = f32(app.img_w) / f32(app.img_h)
		return
	}

	// if we are out of the zip, close it
	if app.zip_index >= 0 {
		app.zip_index = -1
		app.zip.close()
	}
	
	file_path := app.item_list.get_file_path()
	if file_path.len > 0 {
		//println("${app.item_list.lst[app.item_list.item_index]} $file_path ${app.item_list.lst.len}")
		app.texture, app.img_w, app.img_h = app.load_texture_from_file(file_path)
		app.img_ratio = f32(app.img_w) / f32(app.img_h)
		//println("texture: [${app.img_w},${app.img_h}] ratio: ${app.img_ratio}")
	} else {
		app.texture = app.texture_filler
		app.img_w = 256
		app.img_h = 256
		app.img_ratio = f32(app.img_w) / f32(app.img_h)
		println("texture NOT FOUND: use filler!")
	}
}

/******************************************************************************
*
* Init / Cleanup
*
******************************************************************************/
fn app_init(mut app App) {
	app.init_flag = true

	// 3d pipeline
	mut pipdesc := C.sg_pipeline_desc{}
	unsafe { C.memset(&pipdesc, 0, sizeof(pipdesc)) }

	color_state := C.sg_color_state{
		blend: C.sg_blend_state{
			enabled: true
			src_factor_rgb: gfx.BlendFactor(C.SG_BLENDFACTOR_SRC_ALPHA)
			dst_factor_rgb: gfx.BlendFactor(C.SG_BLENDFACTOR_ONE_MINUS_SRC_ALPHA)
		}
	}
	pipdesc.colors[0] = color_state

	pipdesc.depth = C.sg_depth_state{
		write_enabled: true
		compare: gfx.CompareFunc(C.SG_COMPAREFUNC_LESS_EQUAL)
	}
	pipdesc.cull_mode = .back
	app.pip_3d = sgl.make_pipeline(&pipdesc)

	// create chessboard texture 256*256 RGBA
	w := 256
	h := 256
	sz := w * h * 4
	tmp_txt := unsafe { malloc(sz) }
	mut i := 0
	for i < sz {
		unsafe {
			y := (i >> 0x8) >> 5 // 8 cell
			x := (i & 0xFF) >> 5 // 8 cell
			// upper left corner
			if x == 0 && y == 0 {
				tmp_txt[i] = byte(0xFF)
				tmp_txt[i + 1] = byte(0)
				tmp_txt[i + 2] = byte(0)
				tmp_txt[i + 3] = byte(0xFF)
			}
			// low right corner
			else if x == 7 && y == 7 {
				tmp_txt[i] = byte(0)
				tmp_txt[i + 1] = byte(0xFF)
				tmp_txt[i + 2] = byte(0)
				tmp_txt[i + 3] = byte(0xFF)
			} else {
				col := if ((x + y) & 1) == 1 { 0xFF } else { 0 }
				tmp_txt[i] = byte(col) // red
				tmp_txt[i + 1] = byte(col) // green
				tmp_txt[i + 2] = byte(col) // blue
				tmp_txt[i + 3] = byte(0xFF) // alpha
			}
			i += 4
		}
	}
	unsafe {
		// filler texture
		app.texture_filler = create_texture(w, h, tmp_txt)
		// load the default texture with the chess board
		app.texture = create_texture(w, h, tmp_txt)
		free(tmp_txt)
	}
	
	// init done, load the first image if any
	load_image(mut app)
}

fn cleanup(mut app App) {
	gfx.shutdown()
}

/******************************************************************************
*
* Draw functions
*
******************************************************************************/
[manualfree]
fn frame(mut app App) {
	ws := gg.window_size_real_pixels()
	if ws.width <= 0 || ws.height <= 0 {
		return
	}
	mut ratio := f32(ws.width) / ws.height
	dw := ws.width
	dh := ws.height
	
	app.gg.begin()
	sgl.defaults()

	// set viewport
	sgl.viewport(0, 0, dw, dh, true)
	
	// enable our pipeline
	sgl.load_pipeline(app.pip_3d)
	sgl.enable_texture()
	sgl.texture(app.texture)
	
	// translation
	tr_x := app.tr_x / app.img_w
	tr_y := -app.tr_y / app.img_h
	sgl.push_matrix()
	sgl.translate(tr_x, tr_y, 0.0)
	// scaling/zoom
	sgl.scale(2.0 * app.scale, 2.0  * app.scale, 0.0)
	// roation
	mut rotation := 0
	if app.item_list.n_item > 0 {
		rotation = app.item_list.lst[app.item_list.item_index].rotation
		sgl.rotate( pi_2 * f32(rotation) , 0.0, 0.0, -1.0)
	}
	
	// draw the image
	mut w := f32(0.5)
	mut h := f32(0.5)

	// for 90 and 270 degree invert w and h
	// rotation change image ratio, manage it
	if rotation & 1 == 1 {
		tmp := w
		w = h
		h = tmp
		h /= app.img_ratio  * ratio
	} else {
		h /= app.img_ratio  / ratio
	}
	
	// manage image overflow in case of strange scales
	if h > 0.5 {
		reduction_factor := 0.5 / h
		h = h * reduction_factor
		w = w * reduction_factor
	}
	if w > 0.5 {
		reduction_factor := 0.5 / w
		h = h * reduction_factor
		w = w * reduction_factor
	}
	
	//println("$w,$h")
	// white multiplicator for now
	mut c := [byte(255),255,255]!
	sgl.begin_quads()
	sgl.v2f_t2f_c3b(-w, -h, 0, 0, c[0], c[1], c[2])
	sgl.v2f_t2f_c3b( w, -h, 1, 0, c[0], c[1], c[2])
	sgl.v2f_t2f_c3b( w,  h, 1, 1, c[0], c[1], c[2])
	sgl.v2f_t2f_c3b(-w,  h, 0, 1, c[0], c[1], c[2])
	sgl.end()
	
	// restore all the transformations
	sgl.pop_matrix()
	
	
	// Zoom icon
	if app.show_info_flag == true && app.scale > 1 {
		mut bw := f32(0.25)
		mut bh := f32(0.25 / app.img_ratio)
		mut bx := f32(1 - bw)
		mut by := f32(1 - bh)
		
		// manage the rotations
		if rotation & 1 == 1 {
			bw,bh = bh,bw
			bx,by = by,bx
		}
		r := rotation << 1
		
		bh *= ratio
		
		// draw the zoom icon
		sgl.begin_quads()
		sgl.v2f_t2f_c3b(bx     , by     , uv[(0 + r) & 7] , uv[(1 + r) & 7], c[0], c[1], c[2])
		sgl.v2f_t2f_c3b(bx + bw, by     , uv[(2 + r) & 7] , uv[(3 + r) & 7], c[0], c[1], c[2])
		sgl.v2f_t2f_c3b(bx + bw, by + bh, uv[(4 + r) & 7] , uv[(5 + r) & 7], c[0], c[1], c[2])
		sgl.v2f_t2f_c3b(bx     , by + bh, uv[(6 + r) & 7] , uv[(7 + r) & 7], c[0], c[1], c[2])
		sgl.end()
		
		// draw the zoom rectangle
		sgl.disable_texture()
			
		bw_old := bw
		bh_old := bh
		bw /=  app.scale
		bh /=  app.scale
		bx += (bw_old - bw) / 2 - (tr_x / 8) / app.scale
		by += (bh_old - bh) / 2 - (tr_y / 8) / app.scale
		
		c = [byte(255),255,0]! // yellow
		sgl.begin_line_strip()
		sgl.v2f_c3b(bx     , by     , c[0], c[1], c[2])
		sgl.v2f_c3b(bx + bw, by     , c[0], c[1], c[2])
		sgl.v2f_c3b(bx + bw, by + bh, c[0], c[1], c[2])
		sgl.v2f_c3b(bx     , by + bh, c[0], c[1], c[2])
		sgl.v2f_c3b(bx     , by     , c[0], c[1], c[2])
		sgl.end()
	}
	
	
	sgl.disable_texture()
	
	// print the info text if needed
	if app.show_info_flag == true {
		app.gg.begin() // this other app.gg.begin() is needed to have the text on the textured quad
		if app.item_list.n_item > 0 {
			num := app.item_list.lst[app.item_list.item_index].n_item
			of_num := app.item_list.n_item
			text := "${num}/${of_num} [${app.img_w},${app.img_h}]=>[${int(w*2*app.scale*dw)},${int(h*2*app.scale*dw)}] ${app.item_list.lst[app.item_list.item_index].name} scale: ${app.scale:.2} rotation: ${90 * rotation}"
						
			scale := app.gg.scale
			font_size := int(20 * scale)
			x := int(10 * scale)
			y := int(10 * scale)
				
			mut txt_conf := gx.TextCfg{
				color: gx.white
				align: .left
				size: font_size
			}
			app.gg.draw_text(x + 2, y + 2, text, txt_conf)
			txt_conf = gx.TextCfg{
				color: gx.black
				align: .left
				size: font_size
			}
			app.gg.draw_text(x, y, text, txt_conf)
			
			unsafe{
				text.free()
			}
			
		}
	}
	
	app.gg.end()
	app.frame_count++
}

/******************************************************************************
*
* events management
*
******************************************************************************/
fn clear_modifier_params(mut app App) {
	app.scale = 1.0
	
	app.sc_flag = false
	app.sc_x = 0
	app.sc_y = 0
	app.last_sc_x = 0
	app.last_sc_y = 0
	
	app.tr_flag = false
	app.tr_x = 0
	app.tr_y = 0
	app.last_tr_x = 0
	app.last_tr_y = 0
}

fn my_event_manager(mut ev gg.Event, mut app App) {
	// navigation using the mouse wheel
	app.scroll_y = int(ev.scroll_y)
	if app.scroll_y != 0 {
		inc := int(-1 * app.scroll_y/4)
		if app.item_list.n_item > 0 {
			app.item_list.get_next_item(inc)
			load_image(mut app)
		}
	}
	
	if ev.typ == .mouse_move {
		app.mouse_x = int(ev.mouse_x)
		app.mouse_y = int(ev.mouse_y)
	}
	if ev.typ == .touches_began || ev.typ == .touches_moved {
		if ev.num_touches > 0 {
			touch_point := ev.touches[0]
			app.mouse_x = int(touch_point.pos_x)
			app.mouse_y = int(touch_point.pos_y)
		}
	}
	
	// clear all parameters
	if ev.typ == .mouse_down && ev.mouse_button == .middle {
		clear_modifier_params(mut app)
	}
	
	//ws := gg.window_size_real_pixels()
	//ratio := f32(ws.width) / ws.height
	//dw := ws.width
	//dh := ws.height
	
	// --- translate ---
	if ev.typ == .mouse_down && ev.mouse_button == .left {
		app.tr_flag = true
		app.last_tr_x = app.mouse_x
		app.last_tr_y = app.mouse_y
 	}
	if ev.typ == .mouse_up && ev.mouse_button == .left && app.tr_flag == true {
		app.tr_flag = false
 	}
	if ev.typ == .mouse_move && app.tr_flag == true {
		app.tr_x += (app.mouse_x - app.last_tr_x) * 2
		app.tr_y += (app.mouse_y - app.last_tr_y) * 2
		app.last_tr_x = app.mouse_x
		app.last_tr_y = app.mouse_y
		//println("Translate: ${app.tr_x} ${app.tr_y}")
	}
	
	// --- scaling ---
	if ev.typ == .mouse_down && ev.mouse_button == .right && app.sc_flag == false {
		app.sc_flag = true
		app.last_sc_x = app.mouse_x
		app.last_sc_y = app.mouse_y
 	}
	if ev.typ == .mouse_up && ev.mouse_button == .right && app.sc_flag == true {
		app.sc_flag = false
	}
	if ev.typ == .mouse_move && app.sc_flag == true {
		app.sc_x = app.mouse_x - app.last_sc_x
		app.sc_y = app.mouse_y - app.last_sc_y
		app.last_sc_x = app.mouse_x
		app.last_sc_y = app.mouse_y

		app.scale += f32(app.sc_x / 100 )
		if app.scale < 0.1 {
			app.scale = 0.1
		}
		if app.scale > 32 {
			app.scale = 32
		}
		
	}
	
	if ev.typ == .key_down {
		//println(ev.key_code)
		// Exit using the ESC key or Q key
		if ev.key_code == .escape || ev.key_code == .q {
			exit(0)
		}
		// Toggle info text OSD
		if ev.key_code == .i {
			app.show_info_flag = !app.show_info_flag
		}
		// Toggle help text
		if ev.key_code == .h {
			app.show_help_flag = !app.show_help_flag
		}
		
		// do actions only if there are items in the list
		if app.item_list.n_item > 0 {
			// show previous image
			if ev.key_code == .left {
				app.item_list.get_next_item(-1)
				load_image(mut app)
			}
			// show next image
			if ev.key_code == .right {
				app.item_list.get_next_item(1)
				load_image(mut app)
			}
			
			// jump to the next container if possible
			if ev.key_code == .up {
				app.item_list.go_to_next_container(1)
				load_image(mut app)
			}
			// jump to the previous container if possible
			if ev.key_code == .down {
				app.item_list.go_to_next_container(-1)
				load_image(mut app)
			}
			
			// rotate the image
			if ev.key_code == .r {
				app.item_list.rotate(1)
			}
			
			// full screen
			if ev.key_code == .f {
				println("Full screen state: ${sapp.is_fullscreen()}")
				sapp.toggle_fullscreen()
			}
		}
	}
}

/******************************************************************************
*
* Main
*
******************************************************************************/
// is needed for easier diagnostics on windows
[console]
fn main() {	
	//mut font_path := os.resource_abs_path(os.join_path('../assets/fonts/', 'RobotoMono-Regular.ttf'))
	font_name := 'RobotoMono-Regular.ttf'
	font_path := os.join_path(os.temp_dir(), font_name)
	println("Temporary path for the font file: [$font_path]")
	
	// if the font doesn't exist crate it from the ebedded one
	if os.exists(font_path) == false {
		println("Write font [$font_name] in temp folder.")
		embedded_file := $embed_file('RobotoMono-Regular.ttf')
		os.write_file(font_path, embedded_file.to_string()) or {
			eprintln("ERROR: not able to write font file to [$font_path]")
			exit(1)
		}
	}
	
	// App init
	mut app := &App{
		gg: 0
		// zip fields
		zip: 0
	}
	
	// Scan all the arguments to find images
	app.item_list = Item_list{}
	app.item_list.get_items_list() or {
		eprintln("ERROR loading files!") 
		app.item_list = Item_list{}
	}
	
	app.gg = gg.new_context(
		width: win_width
		height: win_height
		create_window: true
		window_title: 'V Image viewer 0.7'
		user_data: app
		bg_color: bg_color
		frame_fn: frame
		init_fn: app_init
		cleanup_fn: cleanup
		event_fn: my_event_manager
		font_path: font_path
	)

	app.gg.run()
}
