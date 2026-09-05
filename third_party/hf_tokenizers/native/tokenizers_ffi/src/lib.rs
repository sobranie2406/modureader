//! Thin C ABI over the HuggingFace `tokenizers` crate.
//!
//! Exposes just enough surface for the Dart `tokenizers` package to load a
//! `tokenizer.json`, encode text to token ids, and decode ids back to text.
//! Every pointer returned here is owned by the caller and must be released with
//! the matching `tk_free_*` function.

use std::ffi::CString;
use std::os::raw::c_char;
use std::ptr;

/// Reads `len` bytes at `ptr` as UTF-8. Unlike a NUL-terminated `CStr`, this
/// carries an explicit length, so an embedded U+0000 byte is part of the text
/// rather than the end of it. Returns `None` if `ptr` is null or the bytes are
/// not valid UTF-8. `unsafe`: the caller guarantees `ptr` points at `len`
/// readable bytes.
unsafe fn str_from_raw<'a>(ptr: *const u8, len: usize) -> Option<&'a str> {
    if ptr.is_null() {
        return None;
    }
    let bytes = std::slice::from_raw_parts(ptr, len);
    std::str::from_utf8(bytes).ok()
}

use tokenizers::Tokenizer;

/// Load a tokenizer from the raw bytes of a `tokenizer.json`. Returns null on
/// failure. Free with [`tk_free`].
#[no_mangle]
pub extern "C" fn tk_from_bytes(data: *const u8, len: usize) -> *mut Tokenizer {
    if data.is_null() {
        return ptr::null_mut();
    }
    let slice = unsafe { std::slice::from_raw_parts(data, len) };
    match Tokenizer::from_bytes(slice) {
        Ok(t) => Box::into_raw(Box::new(t)),
        Err(_) => ptr::null_mut(),
    }
}

/// Encode the `text_len` UTF-8 bytes at `text` into token ids. Writes the id
/// count to `out_len` and returns a heap array of that many `u32`s (null on
/// failure). The length is explicit, so a U+0000 byte inside the text is
/// encoded rather than treated as the end of the string. Free with
/// [`tk_free_ids`].
#[no_mangle]
pub extern "C" fn tk_encode(
    tk: *const Tokenizer,
    text: *const u8,
    text_len: usize,
    add_special_tokens: bool,
    out_len: *mut usize,
) -> *mut u32 {
    if tk.is_null() || text.is_null() || out_len.is_null() {
        return ptr::null_mut();
    }
    let tk = unsafe { &*tk };
    let s = match unsafe { str_from_raw(text, text_len) } {
        Some(s) => s,
        None => return ptr::null_mut(),
    };
    match tk.encode(s, add_special_tokens) {
        Ok(enc) => {
            let ids = enc.get_ids().to_vec();
            unsafe { *out_len = ids.len() };
            let mut boxed = ids.into_boxed_slice();
            let p = boxed.as_mut_ptr();
            std::mem::forget(boxed);
            p
        }
        Err(_) => ptr::null_mut(),
    }
}

/// Encode `text`, returning both the token ids and their offsets into the input.
///
/// Writes the token count to `out_len`, stores a heap array of that many `u32`
/// ids in `*out_ids`, and returns a heap array of `2 * out_len` `u32`s holding
/// each token's `[start, end)` offset pair, flattened (start0, end0, start1,
/// end1, ...). Returns null on failure, in which case `*out_ids` is left
/// untouched. Free BOTH arrays with [`tk_free_ids`] (the offsets array has
/// length `2 * out_len`). The offsets are whatever the underlying tokenizer
/// reports, which for the standard `tokenizer.json` models is a byte range into
/// the input string.
#[no_mangle]
pub extern "C" fn tk_encode_offsets(
    tk: *const Tokenizer,
    text: *const u8,
    text_len: usize,
    add_special_tokens: bool,
    out_len: *mut usize,
    out_ids: *mut *mut u32,
) -> *mut u32 {
    if tk.is_null() || text.is_null() || out_len.is_null() || out_ids.is_null() {
        return ptr::null_mut();
    }
    let tk = unsafe { &*tk };
    let s = match unsafe { str_from_raw(text, text_len) } {
        Some(s) => s,
        None => return ptr::null_mut(),
    };
    match tk.encode(s, add_special_tokens) {
        Ok(enc) => {
            let ids = enc.get_ids().to_vec();
            // Flatten the (start, end) offset pairs into a 2*n u32 array. Offsets
            // for any real text fit comfortably in u32.
            let offsets = enc.get_offsets();
            let mut flat: Vec<u32> = Vec::with_capacity(offsets.len() * 2);
            for &(start, end) in offsets {
                flat.push(start as u32);
                flat.push(end as u32);
            }
            unsafe { *out_len = ids.len() };
            // Hand the ids array out through the out-parameter.
            let mut ids_boxed = ids.into_boxed_slice();
            let ids_ptr = ids_boxed.as_mut_ptr();
            std::mem::forget(ids_boxed);
            unsafe { *out_ids = ids_ptr };
            // Return the offsets array.
            let mut off_boxed = flat.into_boxed_slice();
            let off_ptr = off_boxed.as_mut_ptr();
            std::mem::forget(off_boxed);
            off_ptr
        }
        Err(_) => ptr::null_mut(),
    }
}

/// Decode `ids` back into text. Returns a NUL-terminated UTF-8 string (null on
/// failure). Free with [`tk_free_string`].
#[no_mangle]
pub extern "C" fn tk_decode(
    tk: *const Tokenizer,
    ids: *const u32,
    len: usize,
    skip_special_tokens: bool,
) -> *mut c_char {
    if tk.is_null() || ids.is_null() {
        return ptr::null_mut();
    }
    let tk = unsafe { &*tk };
    let slice = unsafe { std::slice::from_raw_parts(ids, len) };
    match tk.decode(slice, skip_special_tokens) {
        Ok(s) => CString::new(s).map(CString::into_raw).unwrap_or(ptr::null_mut()),
        Err(_) => ptr::null_mut(),
    }
}

/// Number of tokens in the vocabulary (with added tokens).
#[no_mangle]
pub extern "C" fn tk_vocab_size(tk: *const Tokenizer) -> usize {
    if tk.is_null() {
        return 0;
    }
    let tk = unsafe { &*tk };
    tk.get_vocab_size(true)
}

/// Look up the id of a single token string, given as `token_len` UTF-8 bytes at
/// `token`. Writes the id to `out_id` and returns `true`, or returns `false` if
/// the token is not in the vocabulary.
#[no_mangle]
pub extern "C" fn tk_token_to_id(
    tk: *const Tokenizer,
    token: *const u8,
    token_len: usize,
    out_id: *mut u32,
) -> bool {
    if tk.is_null() || token.is_null() || out_id.is_null() {
        return false;
    }
    let tk = unsafe { &*tk };
    let s = match unsafe { str_from_raw(token, token_len) } {
        Some(s) => s,
        None => return false,
    };
    match tk.token_to_id(s) {
        Some(id) => {
            unsafe { *out_id = id };
            true
        }
        None => false,
    }
}

/// Look up the token string for a single id. Returns a NUL-terminated UTF-8
/// string (null if the id is not in the vocabulary). Free with
/// [`tk_free_string`].
#[no_mangle]
pub extern "C" fn tk_id_to_token(tk: *const Tokenizer, id: u32) -> *mut c_char {
    if tk.is_null() {
        return ptr::null_mut();
    }
    let tk = unsafe { &*tk };
    match tk.id_to_token(id) {
        Some(s) => CString::new(s).map(CString::into_raw).unwrap_or(ptr::null_mut()),
        None => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn tk_free_ids(p: *mut u32, len: usize) {
    if !p.is_null() {
        unsafe {
            let slice = std::slice::from_raw_parts_mut(p, len);
            drop(Box::from_raw(slice as *mut [u32]));
        }
    }
}

#[no_mangle]
pub extern "C" fn tk_free_string(p: *mut c_char) {
    if !p.is_null() {
        unsafe { drop(CString::from_raw(p)) };
    }
}

#[no_mangle]
pub extern "C" fn tk_free(tk: *mut Tokenizer) {
    if !tk.is_null() {
        unsafe { drop(Box::from_raw(tk)) };
    }
}

