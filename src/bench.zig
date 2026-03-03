const std = @import("std");
const Explorer = @import("explore.zig").Explorer;
const WordIndex = @import("index.zig").WordIndex;
const TrigramIndex = @import("index.zig").TrigramIndex;

const FileEntry = struct { name: []const u8, content: []const u8 };

fn generateCode(allocator: std.mem.Allocator, num_files: usize, lines_per_file: usize) ![]const FileEntry {
    var files: std.ArrayList(FileEntry) = .{};
    var prng = std.Random.DefaultPrng.init(42);
    const rand = prng.random();

    const words = [_][]const u8{
        "fn", "pub", "const", "var", "struct", "enum", "union", "return",
        "if", "else", "while", "for", "switch", "break", "continue",
        "try", "catch", "error", "void", "bool", "u8", "u32", "u64",
        "allocator", "self", "result", "value", "index", "count", "size",
        "init", "deinit", "append", "remove", "get", "put", "insert",
        "handleRequest", "processData", "validateInput", "parseConfig",
        "readFile", "writeOutput", "createBuffer", "destroyBuffer",
        "AgentRegistry", "FileVersions", "TrigramIndex", "WordIndex",
        "Explorer", "Store", "Version", "Symbol", "Outline", "Language",
    };

    for (0..num_files) |i| {
        var buf: std.ArrayList(u8) = .{};
        const w = buf.writer(allocator);
        for (0..lines_per_file) |_| {
            const num_words = 5 + rand.intRangeAtMost(usize, 0, 10);
            for (0..num_words) |wi| {
                if (wi > 0) w.writeByte(' ') catch {};
                const word = words[rand.intRangeAtMost(usize, 0, words.len - 1)];
                w.writeAll(word) catch {};
            }
            w.writeByte('\n') catch {};
        }
        var name_buf: [64]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "src/gen_{d}.zig", .{i}) catch unreachable;
        try files.append(allocator, .{
            .name = try allocator.dupe(u8, name),
            .content = try buf.toOwnedSlice(allocator),
        });
    }
    return files.toOwnedSlice(allocator);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const num_files = 500;
    const lines_per = 200;
    const total_lines = num_files * lines_per;

    std.debug.print("Generating {d} files × {d} lines = {d} total lines...\n", .{ num_files, lines_per, total_lines });

    const files = try generateCode(allocator, num_files, lines_per);
    defer {
        for (files) |f| {
            allocator.free(f.name);
            allocator.free(f.content);
        }
        allocator.free(files);
    }

    var total_bytes: usize = 0;
    for (files) |f| total_bytes += f.content.len;
    std.debug.print("Total content: {d} KB\n\n", .{total_bytes / 1024});

    // ── Index directly into WordIndex + TrigramIndex ──
    var wi = WordIndex.init(allocator);
    defer wi.deinit();
    var ti = TrigramIndex.init(allocator);
    defer ti.deinit();

    // Also store content for brute force comparison
    var contents = std.StringHashMap([]const u8).init(allocator);
    defer contents.deinit();

    var timer = try std.time.Timer.start();
    for (files) |f| {
        try wi.indexFile(f.name, f.content);
        try ti.indexFile(f.name, f.content);
        try contents.put(f.name, f.content);
    }
    const index_ns = timer.read();
    std.debug.print("Index {d} files:           {d:.1} ms\n", .{ num_files, @as(f64, @floatFromInt(index_ns)) / 1_000_000.0 });

    // ── Bench: raw word index lookup (zero-alloc) ──
    const word_queries = [_][]const u8{ "handleRequest", "AgentRegistry", "allocator", "Explorer", "TrigramIndex" };

    timer.reset();
    const word_iters: usize = 100_000;
    var total_hits: usize = 0;
    for (0..word_iters) |_| {
        for (word_queries) |q| {
            const hits = wi.search(q);
            total_hits += hits.len;
        }
    }
    const word_ns = timer.read();
    const word_total = word_iters * word_queries.len;
    std.debug.print("Word lookup ×{d}:    {d:.1} ms total, {d:.0} ns/query ({d} hits)\n", .{
        word_total,
        @as(f64, @floatFromInt(word_ns)) / 1_000_000.0,
        @as(f64, @floatFromInt(word_ns)) / @as(f64, @floatFromInt(word_total)),
        total_hits / word_iters,
    });

    // ── Bench: trigram candidate lookup (no verify) ──
    const tri_queries = [_][]const u8{ "handleRequest", "processData", "AgentRegistry", "pub fn init", "TrigramIndex" };

    timer.reset();
    const tri_iters: usize = 10_000;
    for (0..tri_iters) |_| {
        for (tri_queries) |q| {
            const cands = ti.candidates(q);
            if (cands) |c| allocator.free(c);
        }
    }
    const tri_ns = timer.read();
    const tri_total = tri_iters * tri_queries.len;
    std.debug.print("Trigram candidates ×{d}: {d:.1} ms total, {d:.0} ns/query\n", .{
        tri_total,
        @as(f64, @floatFromInt(tri_ns)) / 1_000_000.0,
        @as(f64, @floatFromInt(tri_ns)) / @as(f64, @floatFromInt(tri_total)),
    });

    // ── Bench: brute force substring search ──
    timer.reset();
    const brute_iters: usize = 1_000;
    for (0..brute_iters) |_| {
        for (tri_queries) |q| {
            var iter = contents.iterator();
            while (iter.next()) |entry| {
                _ = std.mem.indexOf(u8, entry.value_ptr.*, q);
            }
        }
    }
    const brute_ns = timer.read();
    const brute_total = brute_iters * tri_queries.len;
    std.debug.print("Brute force ×{d}:      {d:.1} ms total, {d:.0} ns/query\n", .{
        brute_total,
        @as(f64, @floatFromInt(brute_ns)) / 1_000_000.0,
        @as(f64, @floatFromInt(brute_ns)) / @as(f64, @floatFromInt(brute_total)),
    });

    std.debug.print("\n── Summary ({d} files, {d}K lines, {d} KB) ──\n", .{ num_files, total_lines / 1000, total_bytes / 1024 });
    std.debug.print("Word index:    {d:.0} ns/query  (zero-alloc hash lookup)\n", .{@as(f64, @floatFromInt(word_ns)) / @as(f64, @floatFromInt(word_total))});
    std.debug.print("Trigram:       {d:.0} ns/query  (candidate set intersection)\n", .{@as(f64, @floatFromInt(tri_ns)) / @as(f64, @floatFromInt(tri_total))});
    std.debug.print("Brute force:   {d:.0} ns/query  (linear scan all content)\n", .{@as(f64, @floatFromInt(brute_ns)) / @as(f64, @floatFromInt(brute_total))});
    const speedup_word = @as(f64, @floatFromInt(brute_ns)) / @as(f64, @floatFromInt(brute_total)) / (@as(f64, @floatFromInt(word_ns)) / @as(f64, @floatFromInt(word_total)));
    const speedup_tri = @as(f64, @floatFromInt(brute_ns)) / @as(f64, @floatFromInt(brute_total)) / (@as(f64, @floatFromInt(tri_ns)) / @as(f64, @floatFromInt(tri_total)));
    std.debug.print("Word vs brute: {d:.0}× faster\n", .{speedup_word});
    std.debug.print("Tri vs brute:  {d:.1}× faster\n", .{speedup_tri});
}
