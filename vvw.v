import os
import szip

enum Item_type {
	file = 0
	folder
	zip
}

pub 
struct Item {
pub mut:
	path string
	name string
	size u64
	i_type Item_type = .file
}

struct Item_list {
pub mut:
	lst []Item
}

fn (mut il Item_list )scan_dir(path string)? {
	mut folder_list := []string{}
	lst := os.ls(path)?
	
	// manage the single files
	for x in lst {
		pt := "$path\\$x"
		mut item := Item{
			path: path
			name: x
		}
		if os.is_dir(pt) {
			folder_list << x
		} else {
			il.lst << item
		} 
	}
	
	// manage the folders
	for x in folder_list {
		pt := "$path\\$x"
		item := Item{
			path: path
			name: x
			i_type: .folder
		}
		il.lst << item
		il.scan_dir(pt)?
	}
	
}

fn (il Item_list )print_list() {
	for x in il.lst {
		if x.i_type == .folder {
			print("[]")
		}
		println("${x.path} => ${x.name}")
	}
}

fn main() {
	args := os.args[1..]
	println("Args: ${args}")
/*
	lst := os.ls(".")?
	println("lst: $lst")
*/

	mut item_list := Item_list{}
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