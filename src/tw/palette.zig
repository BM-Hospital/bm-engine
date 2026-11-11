//! Tailwind v4 default palette exactly as takumi bakes it (`takumi-core/src/style/properties/color.rs`):
//! sRGB bytes, 26 hues x 11 shades, packed 3 bytes per colour (858 bytes in the binary).

pub const names = "slate gray zinc neutral stone taupe mauve mist olive red orange amber yellow lime green emerald teal cyan sky blue indigo violet purple fuchsia pink rose ";
pub const shades = [11]u16{ 50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950 };

/// Packed RGB, hue-major then shade.
pub const rgb: *const [26 * 11 * 3]u8 = &hexDecode("f8fafcf1f5f9e2e8f0cad5e290a1b962748e45556c3141581d293d0f172b020618" ++
    "f9fafbf3f4f6e5e7ebd1d5dc99a1af6a72824a55653641531e2939101828030712" ++
    "fafafaf4f4f5e4e4e7d4d4d89f9fa971717b52525c3f3f4627272a18181b09090b" ++
    "fafafaf5f5f5e5e5e5d4d4d4a1a1a17373735252524040402626261717170a0a0a" ++
    "fafaf9f5f5f4e7e5e4d6d3d1a6a09b79716b57534d44403b2925241c19170c0a09" ++
    "fbfaf9f3f1f1e8e4e3d8d2d0aba09c7c6d675b4f4b473c392b24221d18160c0a09" ++
    "fafafaf3f1f3e7e4e7d7d0d7a89ea979697b594c5b4639472a212c1d161e0c090c" ++
    "f9fbfbf1f3f3e3e7e8d0d6d89ca8ab67787c4b585b39444722292b161b1d090b0c" ++
    "fbfbf9f4f4f0e8e8e3d8d8d0abab9c7c7c675b5b4b4747392b2b221d1d160c0c09" ++
    "fef2f2ffe2e2ffc9c9ffa2a2ff6467fb2c36e7000bc100079f071282181a460809" ++
    "fff7edffedd4ffd6a7ffb86aff8904ff6900f54900ca35009f2d007e2a0c441306" ++
    "fffbebfef3c6fee685ffd230fcbb00f99c00e17100bb4d00973c007b3306461901" ++
    "fefce8fef9c2fff085ffdf20fac800edb200d08700a65f00894b00733e0a432004" ++
    "f7fee7ecfccad8f999bbf4519ae6007ccf005ea500497d003c630035530e192e03" ++
    "f0fdf4dcfce7b9f8cf7bf1a805df7200c95000a63e0082360166300d542b032e15" ++
    "ecfdf5d0fae5a4f4cf5ee9b500d49200bc7d009966007a55006045004f3b002c22" ++
    "f0fdfacbfbf196f7e446ecd500d5be00bba700968900786f005f5a0b4f4a022f2e" ++
    "ecfeffcefafea2f4fd53eafd00d3f200b8db0092b8007595005f78104e64053345" ++
    "f0f9ffdff2feb8e6fe74d4ff00bcff00a6f40084d10069a800598a024a70052f4a" ++
    "eff6ffdbeafebedbff8ec5ff51a2ff2b7fff155dfc1447e6193cb81c398e162456" ++
    "eef2ffe0e7ffc6d2ffa3b3ff7c86ff615fff4f39f6432dd7372aac312c851e1a4d" ++
    "f5f3ffede9feddd6ffc4b4ffa684ff8e51ff7f22fe7008e75d0ec04d179a2f0d68" ++
    "faf5fff3e8ffe9d4ffdab2ffc27affad46ff9810fa8200db6e11b059168b3c0366" ++
    "fdf4fffae8fff6cffff4a8ffed6affe12afbc800dea800b78a01947213784b004f" ++
    "fdf2f8fce7f3fccee8fda5d5fb64b6f6339ae60076c6005ca3004c861043510424" ++
    "fff1f2ffe4e6ffccd3ffa1adff637eff2056ec003fc70036a500368b08364d0218");

fn hexDecode(comptime hex: []const u8) [hex.len / 2]u8 {
    @setEvalBranchQuota(100_000);
    var out: [hex.len / 2]u8 = undefined;
    for (&out, 0..) |*b, i| {
        b.* = (nib(hex[2 * i]) << 4) | nib(hex[2 * i + 1]);
    }
    return out;
}

fn nib(c: u8) u8 {
    return if (c <= '9') c - '0' else c - 'a' + 10;
}

/// Looks up `<hue>-<shade>` (hue case-insensitive). Returns 0xRRGGBB.
pub fn lookup(hue: []const u8, shade: u16) ?u32 {
    var si: usize = 0;
    while (si < shades.len and shades[si] != shade) si += 1;
    if (si == shades.len) return null;
    var hi: usize = 0;
    var it: usize = 0;
    while (it < names.len) : (hi += 1) {
        const end = @import("std").mem.indexOfScalarPos(u8, names, it, ' ') orelse names.len;
        if (@import("std").ascii.eqlIgnoreCase(names[it..end], hue)) {
            const o = (hi * 11 + si) * 3;
            return (@as(u32, rgb[o]) << 16) | (@as(u32, rgb[o + 1]) << 8) | rgb[o + 2];
        }
        it = end + 1;
    }
    return null;
}
