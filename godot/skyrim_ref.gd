class_name SkyrimRef
## The editor's text form of a Skyrim record reference: "<master>:0xFORMID"
## (e.g. "Skyrim.esm:0x018199"). Both fetchers take one straight from a user-typed LineEdit and
## turn it into a cache filename AND into CLI arguments, so validation is a security boundary,
## not a nicety: a ref containing "/" or ".." would otherwise escape res://texcache / res://modelcache.
##
## TexFetch and ModelFetch had byte-identical private copies of these two rules. One copy means a
## ref accepted by the texture path can never disagree with the model path.

## True when `ref` is a well-formed "<master>:0xFORMID" that is safe to use as a filename stem and
## as a CLI argument. Rejects an empty master, path separators, ".." and any non-hex FormID, and
## caps the FormID at the 24 bits Skyrim's text form carries (the load-order byte is not part of it).
static func is_valid(ref: String) -> bool:
	var i := ref.findn(":0x")
	if i <= 0:
		return false
	var master := ref.substr(0, i)
	var formid := ref.substr(i + 3)
	if master == "" or master.contains("/") or master.contains("\\") or master.contains(".."):
		return false
	if formid.length() < 1 or formid.length() > 8:
		return false
	for j in range(formid.length()):
		if "0123456789abcdefABCDEF".find(formid.substr(j, 1)) < 0:
			return false
	return formid.hex_to_int() <= 0xFFFFFF


## One spelling per record, so "Skyrim.esm:0x18199" and "Skyrim.esm:0x018199" share a cache entry.
## Only call this on a ref that is_valid() already accepted.
static func canonical(ref: String) -> String:
	var i := ref.findn(":0x")
	return ref.substr(0, i) + ":0x%06X" % ref.substr(i + 3).hex_to_int()
