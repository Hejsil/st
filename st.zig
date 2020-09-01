const std = @import("std");

const ascii = std.ascii;
const base64 = std.base64;
const c = std.c;
const debug = std.debug;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;
const unicode = std.unicode;

const Rune = u32;

const ATTR_NULL = 0;
const ATTR_BOLD = 1 << 0;
const ATTR_FAINT = 1 << 1;
const ATTR_ITALIC = 1 << 2;
const ATTR_UNDERLINE = 1 << 3;
const ATTR_BLINK = 1 << 4;
const ATTR_REVERSE = 1 << 5;
const ATTR_INVISIBLE = 1 << 6;
const ATTR_STRUCK = 1 << 7;
const ATTR_WRAP = 1 << 8;
const ATTR_WIDE = 1 << 9;
const ATTR_WDUMMY = 1 << 10;
const ATTR_BOLD_FAINT = ATTR_BOLD | ATTR_FAINT;

const MODE_WRAP = 1 << 0;
const MODE_INSERT = 1 << 1;
const MODE_ALTSCREEN = 1 << 2;
const MODE_CRLF = 1 << 3;
const MODE_ECHO = 1 << 4;
const MODE_PRINT = 1 << 5;
const MODE_UTF8 = 1 << 6;

const SEL_IDLE = 0;
const SEL_EMPTY = 1;
const SEL_READY = 2;

const SEL_REGULAR = 1;
const SEL_RECTANGULAR = 2;

const SNAP_WORD = 1;
const SNAP_LINE = 2;

const CURSOR_DEFAULT: u8 = 0;
const CURSOR_WRAPNEXT: u8 = 1;
const CURSOR_ORIGIN: u8 = 2;

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

const Line = [*]Glyph;
const Glyph = extern struct {
    u: Rune = 0,
    mode: c_ushort = 0,
    fg: u32 = 0,
    bg: u32 = 0,
};

const TCursor = extern struct {
    attr: Glyph = Glyph{},
    x: c_int = 0,
    y: c_int = 0,
    state: u8 = 0,
};

const histsize = 2000;
const Term = extern struct {
    row: c_int = 0,
    col: c_int = 0,
    line: [*]Line = undefined,
    alt: [*]Line = undefined,
    hist: [histsize]Line = undefined,
    histi: c_int = 0,
    scr: c_int = 0,
    dirty: [*]c_int = undefined,
    c: TCursor = TCursor{},
    ocx: c_int = 0,
    ocy: c_int = 0,
    top: c_int = 0,
    bot: c_int = 0,
    mode: c_int = 0,
    esc: c_int = 0,
    trantbl: [4]u8 = [_]u8{0} ** 4,
    charset: c_int = 0,
    icharset: c_int = 0,
    tabs: [*]c_int = undefined,
    lastc: Rune = 0,
};

export var term: Term = Term{};
export var sel: Selection = Selection{};
export var cmdfd: os.fd_t = 0;
export var iofd: os.fd_t = 1;

export fn xwrite(fd: os.fd_t, str: [*]const u8, len: usize) isize {
    const file = fs.File{ .handle = fd, .io_mode = io.mode };
    file.writeAll(str[0..len]) catch return -1;
    return @intCast(isize, len);
}

export fn xstrdup(s: [*:0]u8) [*:0]u8 {
    const len = mem.lenZ(s);
    const res = heap.c_allocator.allocSentinel(u8, len, 0) catch std.debug.panic("strdup failed", .{});
    mem.copy(u8, res, s[0..len]);
    return res.ptr;
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

export fn base64dec(src: [*:0]const u8) [*:0]u8 {
    const len = mem.lenZ(src);
    const size = base64.standard_decoder.calcSize(src[0..len]) catch unreachable;
    const res = heap.c_allocator.allocSentinel(u8, size, 0) catch std.debug.panic("strdup failed", .{});
    base64.standard_decoder.decode(res, src[0..len]) catch unreachable;
    return res.ptr;
}

fn tline(y: c_int) Line {
    if (y < term.scr)
        return term.hist[@intCast(usize, @mod(y + term.histi - term.scr + histsize + 1, histsize))];
    return term.line[@intCast(usize, y - term.scr)];
}

export fn tlinelen(y: c_int) c_int {
    var i = @intCast(usize, term.col);
    if (tline(y)[i - 1].mode & ATTR_WRAP != 0)
        return @intCast(c_int, i);
    while (i > 0 and tline(y)[i - 1].u == ' ')
        i -= 1;
    return @intCast(c_int, i);
}

export fn tmoveto(x: c_int, y: c_int) void {
    const miny = if (term.c.state & CURSOR_ORIGIN != 0) term.top else 0;
    const maxy = if (term.c.state & CURSOR_ORIGIN != 0) term.bot else term.row - 1;

    term.c.state &= ~CURSOR_WRAPNEXT;
    term.c.x = math.clamp(x, 0, term.col - 1);
    term.c.y = math.clamp(y, miny, maxy);
}

export fn tmoveato(x: c_int, y: c_int) void {
    tmoveto(x, y + if (term.c.state & CURSOR_ORIGIN != 0) term.top else 0);
}

export fn tsetdirt(_top: c_int, _bot: c_int) void {
    const top = math.clamp(_top, 0, term.row - 1);
    const bot = math.clamp(_bot, 0, term.row - 1);
    var i = @intCast(usize, top);
    while (i <= bot) : (i += 1)
        term.dirty[i] = 1;
}

export fn tprinter(s: [*]const u8, len: usize) void {
    if (iofd == 0)
        return;

    const file = fs.File{ .handle = iofd, .io_mode = io.mode };
    file.writeAll(s[0..len]) catch |err| {
        debug.warn("Error writing to output file {}\n", .{err});
        file.close();
        iofd = 0;
    };
}

export fn selclear() void {
    if (sel.ob.x == -1)
        return;
    sel.mode = SEL_IDLE;
    sel.ob.x = -1;
    tsetdirt(sel.nb.y, sel.ne.y);
}

const word_delimiters = [_]u32{' '};

fn isdelim(u: u32) bool {
    return mem.indexOfScalar(u32, &word_delimiters, u) != null;
}

fn between(x: var, a: var, b: var) bool {
    return a <= x and x <= b;
}

export fn selsnap(x: *c_int, y: *c_int, direction: c_int) void {
    switch (sel.snap) {
        // Snap around if the word wraps around at the end or
        // beginning of a line.
        SNAP_WORD => {
            var prevgb = tline(y.*)[@intCast(usize, x.*)];
            var prevdelim = isdelim(prevgb.u);
            while (true) {
                var newx = x.* + direction;
                var newy = y.*;
                if (!between(newx, 0, term.col - 1)) {
                    newy += direction;
                    newx = @mod(newx + term.col, term.col);
                    if (!between(newy, 0, term.row - 1))
                        break;

                    const yt = if (direction > 0) y.* else newy;
                    const xt = if (direction > 0) x.* else newx;
                    if (tline(yt)[@intCast(usize, xt)].mode & ATTR_WRAP == 0)
                        break;
                }

                if (newx >= tlinelen(newy))
                    break;

                const gb = tline(newy)[@intCast(usize, newx)];
                const delim = isdelim(gb.u);
                if (gb.mode & ATTR_WDUMMY == 0 and (delim != prevdelim or
                    (delim and gb.u != prevgb.u)))
                {
                    break;
                }

                x.* = newx;
                y.* = newy;
                prevgb = gb;
                prevdelim = delim;
            }
        },

        // Snap around if the the previous line or the current one
        // has set ATTR_WRAP at its end. Then the whole next or
        // previous line will be selected.
        SNAP_LINE => {
            x.* = if (direction < 0) 0 else term.col - 1;
            if (direction < 0) {
                while (y.* > 0) : (y.* += direction) {
                    if (tline(y.* - 1)[@intCast(usize, term.col - 1)].mode & ATTR_WRAP == 0)
                        break;
                }
            } else if (direction > 0) {
                while (y.* < term.row - 1) : (y.* += direction) {
                    if (tline(y.*)[@intCast(usize, term.col - 1)].mode & ATTR_WRAP == 0)
                        break;
                }
            }
        },
        else => {},
    }
}

export fn selnormalize() void {
    if (sel.type == SEL_REGULAR and sel.ob.y != sel.oe.y) {
        sel.nb.x = if (sel.ob.y < sel.oe.y) sel.ob.x else sel.oe.x;
        sel.ne.x = if (sel.ob.y < sel.oe.y) sel.oe.x else sel.ob.x;
    } else {
        sel.nb.x = math.min(sel.ob.x, sel.oe.x);
        sel.ne.x = math.max(sel.ob.x, sel.oe.x);
    }
    sel.nb.y = math.min(sel.ob.y, sel.oe.y);
    sel.ne.y = math.max(sel.ob.y, sel.oe.y);

    selsnap(&sel.nb.x, &sel.nb.y, -1);
    selsnap(&sel.ne.x, &sel.ne.y, 1);
    // expand selection over line breaks
    if (sel.type == SEL_RECTANGULAR)
        return;

    const i = tlinelen(sel.nb.y);
    if (i < sel.nb.x)
        sel.nb.x = i;
    if (tlinelen(sel.ne.y) <= sel.ne.x)
        sel.ne.x = term.col - 1;
}

export fn selscroll(orig: c_int, n: c_int) void {
    if (sel.ob.x == -1)
        return;

    if (between(sel.nb.y, orig, term.bot) != between(sel.ne.y, orig, term.bot)) {
        selclear();
    } else if (between(sel.nb.y, orig, term.bot)) {
        sel.ob.y += n;
        sel.oe.y += n;
        if (sel.ob.y < term.top or sel.ob.y > term.bot or
            sel.oe.y < term.top or sel.oe.y > term.bot)
        {
            selclear();
        } else {
            selnormalize();
        }
    }
}

fn is_set(flag: var) bool {
    return term.mode & flag != 0;
}

export fn selstart(col: c_int, row: c_int, snap: c_int) void {
    selclear();
    sel.mode = SEL_EMPTY;
    sel.type = SEL_REGULAR;
    sel.alt = @boolToInt(is_set(MODE_ALTSCREEN));
    sel.snap = snap;
    sel.oe.x = col;
    sel.ob.x = col;
    sel.oe.y = row;
    sel.ob.y = row;
    selnormalize();

    if (sel.snap != 0)
        sel.mode = SEL_READY;
    tsetdirt(sel.nb.y, sel.ne.y);
}

export fn selextend(col: c_int, row: c_int, _type: c_int, done: c_int) void {
    if (sel.mode == SEL_IDLE)
        return;
    if (done != 0 and sel.mode == SEL_EMPTY) {
        selclear();
        return;
    }

    const oldey = sel.oe.y;
    const oldex = sel.oe.x;
    const oldsby = sel.nb.y;
    const oldsey = sel.ne.y;
    const oldtype = sel.type;

    sel.oe.x = col;
    sel.oe.y = row;
    selnormalize();
    sel.type = _type;

    if (oldey != sel.oe.y or oldex != sel.oe.x or oldtype != sel.type or sel.mode == SEL_EMPTY)
        tsetdirt(math.min(sel.nb.y, oldsby), math.max(sel.ne.y, oldsey));

    sel.mode = if (done != 0) SEL_IDLE else SEL_READY;
}

export fn selected(x: c_int, y: c_int) c_int {
    if (sel.mode == SEL_EMPTY or sel.ob.x == -1 or
        sel.alt != @boolToInt(is_set(MODE_ALTSCREEN)))
        return 0;

    if (sel.type == SEL_RECTANGULAR)
        return @boolToInt(between(y, sel.nb.y, sel.ne.y) and
            between(x, sel.nb.x, sel.ne.x));

    return @boolToInt(between(y, sel.nb.y, sel.ne.y) and
        (y != sel.nb.y or x >= sel.nb.x) and
        (y != sel.ne.y or x <= sel.ne.x));
}

export fn tputtab(_n: c_int) void {
    var n = _n;
    var x: usize = @intCast(usize, term.c.x);
    if (n > 0) {
        while (x < term.col and n != 0) : (n -= 1) {
            x += 1;
            while (x < term.col and term.tabs[x] == 0) : (x += 1) {}
        }
    } else if (n < 0) {
        while (x > 0 and n != 0) : (n += 1) {
            x -= 1;
            while (x > 0 and term.tabs[x] == 0) : (x -= 1) {}
        }
    }
    term.c.x = math.clamp(@intCast(c_int, x), 0, term.col - 1);
}

export fn tclearregion(_x1: c_int, _y1: c_int, _x2: c_int, _y2: c_int) void {
    const x1 = math.clamp(math.min(_x1, _x2), 0, term.col - 1);
    const x2 = math.clamp(math.max(_x1, _x2), 0, term.col - 1);
    const y1 = math.clamp(math.min(_y1, _y2), 0, term.row - 1);
    const y2 = math.clamp(math.max(_y1, _y2), 0, term.row - 1);

    var y = @intCast(usize, y1);
    while (y <= @intCast(usize, y2)) : (y += 1) {
        term.dirty[y] = 1;
        var x = @intCast(usize, x1);
        while (x <= @intCast(usize, x2)) : (x += 1) {
            const gp = &term.line[y][x];
            if (selected(@intCast(c_int, x), @intCast(c_int, y)) != 0)
                selclear();
            gp.fg = term.c.attr.fg;
            gp.bg = term.c.attr.bg;
            gp.mode = 0;
            gp.u = ' ';
        }
    }
}

export fn tscrolldown(orig: c_int, _n: c_int, copyhist: c_int) void {
    const n = math.clamp(_n, 0, term.bot - orig + 1);

    if (copyhist != 0) {
        term.histi = @mod(term.histi - 1 + histsize, histsize);
        mem.swap(
            Line,
            &term.hist[@intCast(usize, term.histi)],
            &term.line[@intCast(usize, term.bot)],
        );
    }

    tsetdirt(orig, term.bot - n);
    tclearregion(0, term.bot - n + 1, term.col - 1, term.bot);

    var i = term.bot;
    while (i >= orig + n) : (i -= 1) {
        mem.swap(
            Line,
            &term.line[@intCast(usize, i)],
            &term.line[@intCast(usize, i - n)],
        );
    }

    if (term.scr == 0)
        selscroll(orig, n);
}

export fn tscrollup(orig: c_int, _n: c_int, copyhist: c_int) void {
    const n = math.clamp(_n, 0, term.bot - orig + 1);

    if (copyhist != 0) {
        term.histi = @mod(term.histi + 1, histsize);
        mem.swap(
            Line,
            &term.hist[@intCast(usize, term.histi)],
            &term.line[@intCast(usize, orig)],
        );
    }

    if (term.scr > 0 and term.scr < histsize)
        term.scr = math.min(term.scr + n, histsize - 1);

    tclearregion(0, orig, term.col - 1, orig + n - 1);
    tsetdirt(orig + n, term.bot);

    var i = orig;
    while (i <= term.bot - n) : (i += 1) {
        mem.swap(
            Line,
            &term.line[@intCast(usize, i)],
            &term.line[@intCast(usize, i + n)],
        );
    }

    if (term.scr == 0)
        selscroll(orig, -n);
}

export fn tattrset(attr: c_int) c_int {
    var i: usize = 0;
    while (i < term.row - 1) : (i += 1) {
        var j: usize = 0;
        while (j < term.col - 1) : (j += 1) {
            if (term.line[i][j].mode & @intCast(c_ushort, attr) != 0)
                return 1;
        }
    }

    return 0;
}

export fn tsetdirtattr(attr: c_int) void {
    var i: usize = 0;
    while (i < term.row - 1) : (i += 1) {
        var j: usize = 0;
        while (j < term.col - 1) : (j += 1) {
            if (term.line[i][j].mode & @intCast(c_ushort, attr) != 0) {
                tsetdirt(@intCast(c_int, i), @intCast(c_int, i));
                break;
            }
        }
    }
}
