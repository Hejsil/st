const std = @import("std");

const c = std.c;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;
const unicode = std.unicode;

pub const SEL_IDLE = 0;
pub const SEL_EMPTY = 1;
pub const SEL_READY = 2;

const Selection = extern struct {
    mode: c_int = SEL_IDLE,
    type: c_int = 0,
    snap: c_int = 0,
    nb: Var = Var{},
    ne: Var = Var{},
    ob: Var = Var{ .x = -1 },
    oe: Var = Var{},
    alt: c_int = 0,

    const Var = extern struct { x: c_int = 0, y: c_int = 0 };
};

export var sel: Selection = Selection{};
export var cmdfd: os.fd_t = undefined;

export fn xwrite(fd: os.fd_t, str: [*]const u8, len: usize) isize {
    const file = fs.File{ .handle = fd, .io_mode = io.mode };
    file.writeAll(str[0..len]) catch return -1;
    return @intCast(isize, len);
}

export fn xstrdup(s: [*:0]u8) [*:0]u8 {
    const len = mem.lenZ(s);
    const res = heap.c_allocator.alloc(u8, len + 1) catch std.debug.panic("strdup failed", .{});
    mem.copy(u8, res, s[0 .. len + 1]);
    return res[0 .. res.len - 1 :0].ptr;
}

export fn utf8decode(bytes: [*]const u8, u: *u32, clen: usize) usize {
    const slice = bytes[0..clen];
    u.* = 0xFFFD;

    if (slice.len == 0)
        return 0;

    const len = unicode.utf8ByteSequenceLength(slice[0]) catch return 0;
    if (clen < len)
        return 0;

    u.* = unicode.utf8Decode(slice[0..len]) catch return 0;
    return len;
}

export fn utf8encode(u: u32, out: [*]u8) usize {
    const codepoint = math.cast(u21, u) catch return 0;
    return unicode.utf8Encode(codepoint, out[0..4]) catch return 0;
}

//export fn ttyread() usize {
//    const S = struct {
//        var buf: [1024]u8 = undefined;
//        var buflen: usize = 0;
//    };
//
//    const file = fs.File{ .handle = cwdfd, .io_mode = io.mode };
//    const ret = file.read(S.buf[S.buflen..]) catch debug.panic("couldn't read from shell", .{});
//    if (ret == 0)
//        os.exit(0);
//
//    S.buflen += ret;
//
//    return ret;
//}
