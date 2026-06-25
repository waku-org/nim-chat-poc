// Force libchat's rlib into this staticlib.
// Its #[no_mangle] pub extern "C" symbols are exported from librust_bundle.a.
// rln is now linked separately via MIX_LIBRLN_FILE (librln_mix v2.0.2 stateless)
// so importing it here would duplicate `ffi_c_string_free` (defined by both
// libchat/double_ratchets and zerokit/rln).
extern crate libchat;
