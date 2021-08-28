import os
import szip

/******************************************************************************
*
* Struct and Enums
*
******************************************************************************/
enum Item_type {
	file = 0
	folder
	// archive format
	zip = 16
	archive_file
	// graphic format, MUST stay after the other types!!
	bmp = 32
	jpg
	png
	gif
}

pub 
struct Item {
pub mut:
	path string
	name string
	size u64
	i_type Item_type = .file
	container_index int  // used if the item is in a container (.zip, .rar, etc)
	container_item_index int // index in the container if the item is contained
	need_extract bool // if true need to extraction from the container
	drawable bool // if true the image can be showed
	n_item int = 0
}

struct Item_list {
pub mut:
	lst         []Item
	path_sep    string
	item_index  int = -1
	n_item      int = 0
}

/******************************************************************************
*
* Scan functions
*
******************************************************************************/
fn get_extension(x string) Item_type {
	if x.len > 4 {
		ext4 := x[x.len-4..].to_lower()
		match ext4 {
			'.jpg' { return .jpg }
			'.png' { return .png }
			'.bmp' { return .bmp }
			'.gif' { return .gif }
			// containers
			'.zip' { return .zip }
			else{}
		}
	}
	if x.len > 5 {
		ext5 := x[x.len-4..].to_lower()
		if ext5 == '.jpeg' {
			{ return .jpg }
		}
	}
	return .file
}

fn is_image(x Item_type) bool {
	if int(x) >= int(Item_type.bmp) {
		return true
	}
	return false
}

fn (mut il Item_list ) scan_zip(path string, in_index int)? {
	mut zp := szip.open(path,szip.CompressionLevel.no_compression , szip.OpenMode.read_only)?
	n_entries := zp.total()?
	println(n_entries)
	for index in 0..n_entries {
		zp.open_entry_by_index(index)?
		is_dir := zp.is_dir()?
		name   := zp.name()
		//size   := zp.size()
		//println("$index ${name} ${size:10} $is_dir")
		
		if !is_dir {
			ext := get_extension(name)
			if is_image(ext) == true {
				il.n_item += 1
				mut item := Item{
					need_extract: true
					path: path
					name: "$name" // generate a copy
					container_index: in_index
					container_item_index: index
					i_type: ext
					n_item: il.n_item
					drawable: true
				}
				il.lst << item
			}
		}
		
		// IMPORTANT NOTE: don't close the zip file before heve used all the items!!
		zp.close_entry()
		
	}
	zp.close()
}

fn (mut il Item_list ) scan_folder(path string, in_index int)? {
	//println("Scanning [$path]")
	mut folder_list := []string{}
	lst := os.ls(path)?
	
	// manage the single files
	for c, x in lst {
		pt := "${path}${il.path_sep}${x}"
		mut item := Item{
			path: path
			name: x
			container_index: in_index
			container_item_index: c
		}
		if os.is_dir(pt) {
			folder_list << x
		} else {
			ext := get_extension(x)
			if ext == .zip {
				item.i_type = .zip
				il.lst << item
				il.scan_zip(pt, il.lst.len-1)?
				continue
			}
			if is_image(ext) == true {
				il.n_item += 1
				item.n_item = il.n_item
				item.i_type = ext
				item.drawable = true
				il.lst << item
				continue
			}
		} 
	}
	
	// manage the folders
	for x in folder_list {
		pt := "${path}${il.path_sep}${x}"
		item := Item{
			path: path
			name: x
			i_type: .folder
		}
		il.lst << item
		il.scan_folder(pt, il.lst.len - 1 )?
	}
	
	//println(il.lst.len)
	//println("==================================")
}

fn (il Item_list )print_list() {
	for x in il.lst {
		if x.i_type == .folder {
			print("[]")
		}
		if x.i_type == .zip {
			print("[ZIP]")
		}
		println("${x.path} => ${x.container_index} ${x.container_item_index} ${x.name} ne:${x.need_extract}")
	}
}

fn (mut item_list Item_list ) get_items_list()? {
	args := os.args[1..]
	println("Args: ${args}")
	
	item_list.path_sep = $if windows { '\\' } $else { '/' }
	for x in args {
		// scan folder
		if os.is_dir(x) {
			mut item := Item{
				path: x
				name: x
				container_index: item_list.lst.len
				i_type: .folder
			}
			item_list.lst << item
			item_list.scan_folder(x, item_list.lst.len - 1)?
		} else {
			
			mut item := Item{
				path: x
				name: x
				container_index: -1
			}
			ext := get_extension(x)
			// scan .zip
			if ext == .zip {
				item.i_type = .zip
				item_list.lst << item
				item_list.scan_zip(x, item_list.lst.len-1)?
				continue
			}
			// single images
			if is_image(ext) == true {
				item_list.n_item += 1
				item.n_item = item_list.n_item
				item.i_type = ext
				item.drawable = true
				item_list.lst << item
				continue
			}
			
		}
	}
	
	item_list.get_next_item(1)
	
	//item_list.print_list()
}

/******************************************************************************
*
* Navigation functions
*
******************************************************************************/
fn (mut il Item_list ) get_next_item(in_inc int) {
	if il.lst.len <= 0 || il.n_item <= 0 {
		return
	}
	
	inc := if in_inc > 0 {1} else {-1}
	mut i := il.item_index + in_inc
	println("i0: $i")
	if i < 0 {
		i = il.lst.len + i
	} else if i >= il.lst.len {
		i = i % il.lst.len
	}
  
	println("i1: $i")
	for {
		if il.lst[i].drawable == true && il.lst[i].need_extract == false {
			il.item_index = i
			break
		}
		i = i + inc
		if i < 0 {
			i = il.lst.len + i
		}	else if i >= il.lst.len {
			i = i % il.lst.len
		}
	}
	//println("Found: ${il.item_index}")
}

fn (il Item_list ) get_file_path() string {
	return "${il.lst[il.item_index].path}${il.path_sep}${il.lst[il.item_index].name}"
}