extends RefCounted
# Finds character / map files in a folder (works for .tscn and imported .glb).


static func list(dir: String) -> Array:
	var out: Array = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for f in da.get_files():
		var n: String = f
		if n.ends_with(".remap") or n.ends_with(".import"):
			n = n.get_basename()
		var ext := n.get_extension().to_lower()
		if ext in ["tscn", "scn", "glb", "gltf"]:
			var p := dir.path_join(n)
			if not out.has(p):
				out.append(p)
	out.sort()
	return out
