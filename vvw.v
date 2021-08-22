import os
import szip

fn scan_dir(path string)? {
	mut res := []string{}
	lst := os.ls(path)?
	for x in lst {
		pt := "$path\\$x"
		if os.is_dir(pt) {
			println("$pt is a FOLDER")
			scan_dir(pt)?
		} else {
			res << pt
			println("$pt is a FILE")
		}
	}
}

fn main() {
	args := os.args[1..]
	println("Args: ${args}")
/*
	lst := os.ls(".")?
	println("lst: $lst")
*/
	for x in args {
		if os.is_dir(x) {
			scan_dir(x)?
		}
	}
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
	name := os.input('Enter to exit: ')
}