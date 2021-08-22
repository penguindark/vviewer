import os
import szip

const (
	//path_sep = '\\' 
	supported_type = ['.jpg','jpeg','.bmp','.png','.gif']
)

enum Item_type {
	file = 0
	folder
	// archive format
	zip
	archive_file
	// graphic format
	bmp
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
}

struct Item_list {
pub mut:
	lst []Item
	path_sep string 
}

fn get_extension(x string) Item_type {
	if x.len > 4 {
		ext4 := x[x.len-4..].to_lower()
		match ext4 {
			'.jpg' { return .jpg }
			'.png' { return .png }
			'.bmp' { return .bmp }
			'.gif' { return .gif }
			else{}
		}
		ext5 := x[x.len-4..].to_lower()
		if ext5 == '.jpeg' {
			{ return .jpg }
		}
	}
	return .file
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
			img_type := get_extension(name)
			if img_type != .file {
				mut item := Item{
					path: path
					name: "$name" // generate a copy
					container_index: in_index
					container_item_index: index
					i_type: img_type
				}
				il.lst << item
			}
		}
		
		// IMPORTANT NOTE: don't close before used all teh items!!
		zp.close_entry()
		
	}
	zp.close()
}

fn (mut il Item_list ) scan_dir(path string)? {
	//println("Scanning [$path]")
	mut folder_list := []string{}
	lst := os.ls(path)?
	
	// manage the single files
	for x in lst {
		pt := "${path}${il.path_sep}${x}"
		mut item := Item{
			path: path
			name: x
		}
		if os.is_dir(pt) {
			folder_list << x
		} else {
			// check .zip file
			if x.len > 4 {
				ext4 := x[x.len-4..].to_lower()
				if ext4 == '.zip' {
					item.i_type = .zip
					il.lst << item
					il.scan_zip(pt, il.lst.len-1)?
					continue
				}
				else if ext4 in supported_type {
					il.lst << item
					continue
				}
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
		il.scan_dir(pt)?
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
		println("${x.path} => ${x.name}")
	}
}

fn main() {
	args := os.args[1..]
	println("Args: ${args}")

	mut item_list := Item_list{}
	item_list.path_sep = $if windows { '\\' } $else { '/' }
	
	for x in args {
		if os.is_dir(x) {
			item_list.scan_dir(x)?
		}
	}
	
	item_list.print_list()
/*	
	mut zp := szip.open(args[0],szip.CompressionLevel.no_compression , szip.OpenMode.read_only)?
	n_entries := zp.total()?
	println(n_entries)
	
	for index in 0..n_entries {
		zp.open_entry_by_index(index)?
		is_dir := zp.is_dir()?
		name   := zp.name()
		size   := zp.size()
		println("$index ${name:40s} ${size:10} $is_dir")
		zp.close_entry()
		
	}
	zp.close()
*/	
	os.input('Enter to exit: ')
}