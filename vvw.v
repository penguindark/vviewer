/**********************************************************************
*
* Sokol image viewer demo
*
* Copyright (c) 2021 Dario Deledda. All rights reserved.
* Use of this source code is governed by an MIT license
* that can be found in the LICENSE file.
*
* TODO:
* - add instancing
* - add an example with shaders
**********************************************************************/
import os
import gg
import gx
import math
import sokol.sapp
import sokol.gfx
import sokol.sgl

import stbi

const (
	win_width  = 800
	win_height = 800
	bg_color   = gx.white
)

struct App {
mut:
	gg          &gg.Context
	pip_3d      C.sgl_pipeline
	texture     C.sg_image
	init_flag   bool
	frame_count int
	mouse_x     int = -1
	mouse_y     int = -1
	scroll_y    int = 0
	
	// translation
	tr_flag     bool
	tr_x        f32 = 0.0
	tr_y        f32 = 0.0
	last_tr_x   f32 = 0.0
	last_tr_y   f32 = 0.0
	// scaling
	scale       f32 = 1.0
	// loade image
	img_w       int
	img_h       int
	img_ratio   f32 = 1.0
}

/******************************************************************************
*
* Utility functions
*
******************************************************************************/
// read a file as []byte
pub fn read_bytes_from_file(file_path string) []byte {
	mut path := ''
	mut buffer := []byte{}
	$if android {
		path = 'models/' + file_path
		buffer = os.read_apk_asset(path) or {
			eprintln('Texure file: [$path] NOT FOUND!')
			exit(0)
		}
	} $else {
		path = file_path
		//path = os.resource_abs_path('assets/models/' + file_path)
		buffer = os.read_bytes(path) or {
			eprintln('Texure file: [$path] NOT FOUND!')
			exit(0)
		}
	}
	return buffer
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
	// commen if .dynamic is enabled
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

// Use only if usage: .dynamic is enabled
fn update_text_texture(sg_img C.sg_image, w int, h int, buf &byte) {
	sz := w * h * 4
	mut tmp_sbc := C.sg_image_data{}
	tmp_sbc.subimage[0][0] = C.sg_range{
		ptr: buf
		size: size_t(sz)
	}
	C.sg_update_image(sg_img, &tmp_sbc)
}

pub fn load_texture(file_name string) (C.sg_image, int, int) {
	buffer := read_bytes_from_file(file_name)
	stbi.set_flip_vertically_on_load(true)
	img := stbi.load_from_memory(buffer.data, buffer.len) or {
		eprintln('Texure file: [$file_name] ERROR!')
		exit(0)
	}
	buffer.free()
	
	res := create_texture(int(img.width), int(img.height), img.data)
	img.free()
	
	return res, int(img.width), int(img.height)
}

/******************************************************************************
*
* Init / Cleanup
*
******************************************************************************/
fn app_init(mut app App) {
	app.init_flag = true

	// set max vertices,
	// for a large number of the same type of object it is better use the instances!!
	desc := sapp.create_desc()
	gfx.setup(&desc)
	sgl_desc := C.sgl_desc_t{
		max_vertices: 50 * 65536
	}
	sgl.setup(&sgl_desc)

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
		app.texture = create_texture(w, h, tmp_txt)
		free(tmp_txt)
	}
	
	destroy_texture(app.texture)
	app.texture, app.img_w, app.img_h = load_texture("C:\\Dev\\temp\\vwtest\\GiadaENicola.JPG")
	app.img_ratio = f32(app.img_w) / f32(app.img_h)
	println("texture: [${app.img_w},${app.img_h}] rario: ${app.img_ratio}")
}

fn cleanup(mut app App) {
	gfx.shutdown()
}

/******************************************************************************
*
* Draw functions
*
******************************************************************************/
fn frame(mut app App) {
	ws := gg.window_size_real_pixels()
	mut ratio := f32(ws.width) / ws.height
	dw := ws.width
	dh := ws.height
		
	ww := int(dh / 3) // not a bug
	hh := int(dh / 3)
	x0 := int(f32(dw) * 0.05)
	// x1 := dw/2
	y0 := 0
	y1 := int(f32(dh) * 0.5)
	
  app.gg.begin()
	sgl.defaults()

	// set viewport
	sgl.viewport(0, 0, dw, dh, true)
	
	// enable our pipeline
	sgl.load_pipeline(app.pip_3d)
	sgl.enable_texture()
	sgl.texture(app.texture)
	
	// tranformation
	tr_x := app.tr_x / app.img_w
	tr_y := -app.tr_y / app.img_h
	sgl.translate(tr_x, tr_y, 0.0)
	sgl.scale(2.0 * app.scale, 2.0  * app.scale, 0.0)
	
	 
	// draw the image
	mut w := f32(0.5)
	mut h := f32(0.5)
	if dw >= dh {
		h /= app.img_ratio  / ratio
	} else {		
		w *= app.img_ratio / ratio 
	}
	//println("$w,$h")
	c := [byte(0xFF),0xFF,0xFF]!
	sgl.begin_quads()
	sgl.v2f_t2f_c3b(-w, -h, 0, 0, c[0], c[1], c[2])
	sgl.v2f_t2f_c3b( w, -h, 1, 0, c[0], c[1], c[2])
	sgl.v2f_t2f_c3b( w,  h, 1, 1, c[0], c[1], c[2])
	sgl.v2f_t2f_c3b(-w,  h, 0, 1, c[0], c[1], c[2])
	sgl.end()
	
	sgl.disable_texture()
	app.gg.end()

	app.frame_count++
}

/******************************************************************************
*
* event
*
******************************************************************************/
fn my_event_manager(mut ev gg.Event, mut app App) {
	app.scroll_y = int(ev.scroll_y)
	if app.scroll_y != 0 {
		app.scale += f32(app.scroll_y)/32.0
		//println(app.scroll_y)
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
	
	if ev.typ == .mouse_down && ev.mouse_button == .middle {
		app.scale = 1.0
		app.tr_x = 0
		app.tr_y = 0
		app.last_tr_x = 0
		app.last_tr_y = 0
	}
	
	ws := gg.window_size_real_pixels()
	ratio := f32(ws.width) / ws.height
	dw := ws.width
	dh := ws.height
	
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
	
	if ev.typ == .key_down {
		println(ev.key_code)
		if ev.key_code == .escape {
			exit(0)
		}
		if ev.key_code == .left {
			println("left")
		}
		if ev.key_code == .right {
			println("right")
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
	args := os.args[1..]
	println("Args: ${args}")
	
	mut item_list := Item_list{}
	item_list.get_items_list() or {eprintln("ERROR loading files!")}
	println("First: ${item_list.lst[1]}")

	// App init
	mut app := &App{
		gg: 0
	}

	app.gg = gg.new_context(
		width: win_width
		height: win_height
		create_window: true
		window_title: 'Image viewer'
		user_data: app
		bg_color: bg_color
		frame_fn: frame
		init_fn: app_init
		cleanup_fn: cleanup
		event_fn: my_event_manager
	)
	app.gg.scale = 1

	
	app.gg.run()
}