//! Embeds a PSF2 font into the kernel at compile time and translates it for use at run time
//! I should really think about making a Font struct to deal with stuff so switching fonts is easier. But then again that
//! probably needs to wait for a filesystem since I'll have to rewrite a lot of stuff for usermode anyway.
//! https://en.wikipedia.org/wiki/PC_Screen_Font

const Console = @import("../io/io.zig").Console;

/// Potential errors parsing the buitin font
const ParseError = error{
    InvalidPSF2Header,
    InvalidFontFile,
};

/// Static header common to all psf2 files
const PSF2Header = packed struct {
    magic: u32,
    version: u32,
    header_size: u32,
    flags: u32,
    length: u32,
    glyph_size: u32,
    height: u32,
    width: u32,
};

/// Actual font file embedded at compile time
const font_file = @embedFile("console_font");
const font_header: *const PSF2Header = @ptrCast(@alignCast(font_file));
/// Magic number that should always present in the first 4 bytes of a psf2 file
const magic_number = 0x864AB572;

/// Initialize the font structures and perform safety checks
/// Safety checks are strict and don't try very hard to return from a fail state. This code isn't meant to
/// be general purpose, it'll become an emergency backup during boot or kernel panics at some point.
pub fn init() ParseError!void {
    // Error checks and data initialization
    if (font_file.len < 32) return ParseError.InvalidPSF2Header;
    //font_header = @ptrCast(@alignCast(font_file[0..12]));
    // Check magic number
    if (font_header.magic != magic_number) return ParseError.InvalidPSF2Header;
    if (font_header.header_size != 32) return ParseError.InvalidPSF2Header;
    // Needs to support every ascii code
    if (font_header.length < 256) return ParseError.InvalidFontFile;
    if (font_header.glyph_size != 8) return ParseError.InvalidFontFile;
    if (font_header.height != 8) return ParseError.InvalidFontFile;
    if (font_header.width != 8) return ParseError.InvalidFontFile;
}

/// Return the bitmap corresponding to the character 'c'. Always returns an 8 byte array
pub fn getBitmap(c: u8) [8]u8 {
    // Compiler lizard tongue
    const letter_index = font_header.header_size + (c * font_header.glyph_size);
    return font_file[letter_index .. letter_index + 8][0..8].*;
}
