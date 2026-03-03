const std = @import("std");
const testing = std.testing;

const Store = @import("store.zig").Store;
const ChangeEntry = @import("store.zig").ChangeEntry;
const AgentRegistry = @import("agent.zig").AgentRegistry;
const Explorer = @import("explore.zig").Explorer;
const SearchResult = @import("explore.zig").SearchResult;
const WordIndex = @import("index.zig").WordIndex;
const TrigramIndex = @import("index.zig").TrigramIndex;
const WordTokenizer = @import("index.zig").WordTokenizer;
const version = @import("version.zig");

// ── Store tests ─────────────────────────────────────────────

test "store: record and retrieve snapshots" {
    var store = Store.init(testing.allocator);
    defer store.deinit();

    const seq1 = try store.recordSnapshot("foo.zig", 100, 0xABC);
    const seq2 = try store.recordSnapshot("bar.zig", 200, 0xDEF);

    try testing.expect(seq1 == 1);
    try testing.expect(seq2 == 2);
    try testing.expect(store.currentSeq() == 2);
}

test "store: getLatest returns most recent version" {
    var store = Store.init(testing.allocator);
    defer store.deinit();

    _ = try store.recordSnapshot("foo.zig", 100, 0x111);
    _ = try store.recordSnapshot("foo.zig", 200, 0x222);

    const latest = store.getLatest("foo.zig").?;
    try testing.expect(latest.seq == 2);
    try testing.expect(latest.size == 200);
    try testing.expect(latest.hash == 0x222);
}

test "store: getLatest returns null for unknown file" {
    var store = Store.init(testing.allocator);
    defer store.deinit();

    try testing.expect(store.getLatest("nope.zig") == null);
}

test "store: changesSince counts correctly" {
    var store = Store.init(testing.allocator);
    defer store.deinit();

    _ = try store.recordSnapshot("a.zig", 10, 0);
    _ = try store.recordSnapshot("b.zig", 20, 0);
    _ = try store.recordSnapshot("c.zig", 30, 0);

    try testing.expect(store.changesSince(0) == 3);
    try testing.expect(store.changesSince(1) == 2);
    try testing.expect(store.changesSince(3) == 0);
}

test "store: changesSinceDetailed" {
    var store = Store.init(testing.allocator);
    defer store.deinit();

    _ = try store.recordSnapshot("a.zig", 10, 0);
    _ = try store.recordSnapshot("b.zig", 20, 0);
    _ = try store.recordSnapshot("a.zig", 15, 0);

    const changes = try store.changesSinceDetailed(1, testing.allocator);
    defer testing.allocator.free(changes);

    try testing.expect(changes.len == 2); // a.zig and b.zig both changed
}

test "store: recordDelete creates tombstone" {
    var store = Store.init(testing.allocator);
    defer store.deinit();

    _ = try store.recordSnapshot("del.zig", 50, 0);
    _ = try store.recordDelete("del.zig", 0);

    const latest = store.getLatest("del.zig").?;
    try testing.expect(latest.op == .tombstone);
    try testing.expect(latest.size == 0);
}

test "store: getAtCursor" {
    var store = Store.init(testing.allocator);
    defer store.deinit();

    _ = try store.recordSnapshot("f.zig", 10, 0x10);
    _ = try store.recordSnapshot("f.zig", 20, 0x20);
    _ = try store.recordSnapshot("f.zig", 30, 0x30);

    const at1 = store.getAtCursor("f.zig", 1).?;
    try testing.expect(at1.size == 10);

    const at2 = store.getAtCursor("f.zig", 2).?;
    try testing.expect(at2.size == 20);

    const at3 = store.getAtCursor("f.zig", 99).?;
    try testing.expect(at3.size == 30);
}

// ── Agent tests ─────────────────────────────────────────────

test "agent: register and heartbeat" {
    var agents = AgentRegistry.init(testing.allocator);
    defer agents.deinit();

    const id = try agents.register("test-agent");
    try testing.expect(id == 1);

    agents.heartbeat(id);
    // No crash = success
}

test "agent: register multiple agents" {
    var agents = AgentRegistry.init(testing.allocator);
    defer agents.deinit();

    const a = try agents.register("alpha");
    const b = try agents.register("beta");
    try testing.expect(a == 1);
    try testing.expect(b == 2);
}

test "agent: lock and unlock" {
    var agents = AgentRegistry.init(testing.allocator);
    defer agents.deinit();

    const id = try agents.register("locker");

    const got = try agents.tryLock(id, "file.zig", 60_000);
    try testing.expect(got == true);

    agents.releaseLock(id, "file.zig");
}

test "agent: lock contention between agents" {
    var agents = AgentRegistry.init(testing.allocator);
    defer agents.deinit();

    const a = try agents.register("agent-a");
    const b = try agents.register("agent-b");

    // A locks the file
    const got_a = try agents.tryLock(a, "shared.zig", 60_000);
    try testing.expect(got_a == true);

    // B should be denied
    const got_b = try agents.tryLock(b, "shared.zig", 60_000);
    try testing.expect(got_b == false);

    // A releases
    agents.releaseLock(a, "shared.zig");

    // B can now lock
    const got_b2 = try agents.tryLock(b, "shared.zig", 60_000);
    try testing.expect(got_b2 == true);
}

// ── Word index tests ────────────────────────────────────────

test "word tokenizer" {
    var tok = WordTokenizer{ .buf = "pub fn main() !void {" };
    const w1 = tok.next().?;
    try testing.expectEqualStrings("pub", w1);
    const w2 = tok.next().?;
    try testing.expectEqualStrings("fn", w2);
    const w3 = tok.next().?;
    try testing.expectEqualStrings("main", w3);
    const w4 = tok.next().?;
    try testing.expectEqualStrings("void", w4);
    try testing.expect(tok.next() == null);
}

test "word index: index and search" {
    var wi = WordIndex.init(testing.allocator);
    defer wi.deinit();

    try wi.indexFile("src/foo.zig", "pub fn hello() void {\n    const x = 42;\n}\n");

    const hits = wi.search("hello");
    try testing.expect(hits.len > 0);
    try testing.expectEqualStrings("src/foo.zig", hits[0].path);
    try testing.expect(hits[0].line_num == 1);

    // "x" is only 1 char, should be skipped
    const x_hits = wi.search("x");
    try testing.expect(x_hits.len == 0);

    // "const" should be found
    const const_hits = wi.search("const");
    try testing.expect(const_hits.len > 0);
    try testing.expect(const_hits[0].line_num == 2);
}

test "word index: re-index clears old entries" {
    var wi = WordIndex.init(testing.allocator);
    defer wi.deinit();

    try wi.indexFile("f.zig", "fn old_func() void {}");
    try testing.expect(wi.search("old_func").len > 0);

    try wi.indexFile("f.zig", "fn new_func() void {}");
    try testing.expect(wi.search("old_func").len == 0);
    try testing.expect(wi.search("new_func").len > 0);
}

test "word index: removeFile" {
    var wi = WordIndex.init(testing.allocator);
    defer wi.deinit();

    try wi.indexFile("a.zig", "fn hello() void {}");
    try testing.expect(wi.search("hello").len > 0);

    wi.removeFile("a.zig");
    try testing.expect(wi.search("hello").len == 0);
}

test "word index: deduped search" {
    var wi = WordIndex.init(testing.allocator);
    defer wi.deinit();

    // "hello" appears twice on the same line — should dedup
    try wi.indexFile("f.zig", "hello hello world");

    const hits = try wi.searchDeduped("hello", testing.allocator);
    defer testing.allocator.free(hits);
    try testing.expect(hits.len == 1);
}

// ── Trigram index tests ─────────────────────────────────────

test "trigram index: index and candidate lookup" {
    var ti = TrigramIndex.init(testing.allocator);
    defer ti.deinit();

    try ti.indexFile("src/store.zig", "pub fn recordSnapshot(self: *Store) void {}");
    try ti.indexFile("src/agent.zig", "pub fn register(self: *Agent) void {}");

    const cands = ti.candidates("recordSnapshot");
    defer if (cands) |c| testing.allocator.free(c);
    try testing.expect(cands != null);
    try testing.expect(cands.?.len == 1);
    try testing.expectEqualStrings("src/store.zig", cands.?[0]);
}

test "trigram index: short query returns null" {
    var ti = TrigramIndex.init(testing.allocator);
    defer ti.deinit();

    try ti.indexFile("f.zig", "hello world");
    const cands = ti.candidates("hi");
    try testing.expect(cands == null);
}

test "trigram index: no match returns empty" {
    var ti = TrigramIndex.init(testing.allocator);
    defer ti.deinit();

    try ti.indexFile("f.zig", "hello world");
    const cands = ti.candidates("zzzzz");
    try testing.expect(cands != null);
    try testing.expect(cands.?.len == 0);
}

test "trigram index: re-index removes old trigrams" {
    var ti = TrigramIndex.init(testing.allocator);
    defer ti.deinit();

    try ti.indexFile("f.zig", "uniqueOldContent");
    const c1 = ti.candidates("uniqueOld");
    defer if (c1) |c| testing.allocator.free(c);
    try testing.expect(c1 != null and c1.?.len == 1);

    try ti.indexFile("f.zig", "brandNewStuff");
    const c2 = ti.candidates("uniqueOld");
    defer if (c2) |c| testing.allocator.free(c);
    try testing.expect(c2 != null and c2.?.len == 0);

    const c3 = ti.candidates("brandNew");
    defer if (c3) |c| testing.allocator.free(c);
    try testing.expect(c3 != null and c3.?.len == 1);
}

// ── Explorer tests ──────────────────────────────────────────

test "explorer: index file and get outline" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var explorer = Explorer.init(arena.allocator());

    try explorer.indexFile("test.zig",
        \\const std = @import("std");
        \\pub fn main() !void {}
        \\pub const Store = struct {};
    );

    const outline = explorer.getOutline("test.zig").?;
    try testing.expect(outline.line_count == 3);
    try testing.expect(outline.symbols.items.len == 3);
}

test "explorer: findSymbol" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var explorer = Explorer.init(arena.allocator());

    try explorer.indexFile("a.zig", "pub fn alpha() void {}");
    try explorer.indexFile("b.zig", "pub fn beta() void {}");

    const result = try explorer.findSymbol("alpha");
    try testing.expect(result != null);
    try testing.expectEqualStrings("a.zig", result.?.path);
}

test "explorer: findAllSymbols returns multiple" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var explorer = Explorer.init(arena.allocator());

    try explorer.indexFile("a.zig", "const Store = @import(\"store.zig\").Store;");
    try explorer.indexFile("b.zig", "pub const Store = struct {};");

    const results = try explorer.findAllSymbols("Store", testing.allocator);
    defer testing.allocator.free(results);
    try testing.expect(results.len == 2);
}

test "explorer: searchContent with trigram acceleration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var explorer = Explorer.init(arena.allocator());

    try explorer.indexFile("store.zig", "pub fn recordSnapshot(self: *Store) void {}\npub fn init() void {}");
    try explorer.indexFile("agent.zig", "pub fn register(self: *Agent) void {}");

    const results = try explorer.searchContent("recordSnapshot", testing.allocator, 50);
    defer {
        for (results) |r| testing.allocator.free(r.line_text);
        testing.allocator.free(results);
    }

    try testing.expect(results.len == 1);
    try testing.expectEqualStrings("store.zig", results[0].path);
    try testing.expect(results[0].line_num == 1);
}

test "explorer: searchWord via inverted index" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var explorer = Explorer.init(arena.allocator());

    try explorer.indexFile("math.zig", "pub fn add(a: i32, b: i32) i32 { return a + b; }");

    const hits = try explorer.searchWord("add", testing.allocator);
    defer testing.allocator.free(hits);
    try testing.expect(hits.len > 0);
    try testing.expectEqualStrings("math.zig", hits[0].path);
}

test "explorer: removeFile cleans up everything" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var explorer = Explorer.init(arena.allocator());

    try explorer.indexFile("gone.zig", "pub fn doStuff() void {}");
    try testing.expect(explorer.getOutline("gone.zig") != null);

    explorer.removeFile("gone.zig");
    try testing.expect(explorer.getOutline("gone.zig") == null);
    try testing.expect((try explorer.findSymbol("doStuff")) == null);
}

test "explorer: python parser" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var explorer = Explorer.init(arena.allocator());

    try explorer.indexFile("app.py",
        \\import os
        \\class Server:
        \\    def handle(self):
        \\        pass
    );

    const outline = explorer.getOutline("app.py").?;
    try testing.expect(outline.symbols.items.len == 3); // import, class, def
}

test "explorer: typescript parser" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var explorer = Explorer.init(arena.allocator());

    try explorer.indexFile("index.ts",
        \\import { foo } from './foo';
        \\export function handleRequest() {}
        \\export const PORT = 3000;
    );

    const outline = explorer.getOutline("index.ts").?;
    try testing.expect(outline.symbols.items.len >= 3);
}

// ── Version tests ───────────────────────────────────────────

test "file versions: append and latest" {
    var fv = version.FileVersions.init(testing.allocator, "test.zig");
    defer fv.deinit();

    try fv.versions.append(testing.allocator, .{
        .seq = 1, .agent = 0, .timestamp = 0, .op = .snapshot, .hash = 0x11, .size = 100,
    });
    try fv.versions.append(testing.allocator, .{
        .seq = 2, .agent = 0, .timestamp = 0, .op = .replace, .hash = 0x22, .size = 150,
    });

    const latest = fv.latest().?;
    try testing.expect(latest.seq == 2);
    try testing.expect(latest.size == 150);
}

test "file versions: countSince" {
    var fv = version.FileVersions.init(testing.allocator, "test.zig");
    defer fv.deinit();

    try fv.versions.append(testing.allocator, .{
        .seq = 1, .agent = 0, .timestamp = 0, .op = .snapshot, .hash = 0, .size = 0,
    });
    try fv.versions.append(testing.allocator, .{
        .seq = 5, .agent = 0, .timestamp = 0, .op = .replace, .hash = 0, .size = 0,
    });
    try fv.versions.append(testing.allocator, .{
        .seq = 10, .agent = 0, .timestamp = 0, .op = .delete, .hash = 0, .size = 0,
    });

    try testing.expect(fv.countSince(0) == 3);
    try testing.expect(fv.countSince(1) == 2);
    try testing.expect(fv.countSince(5) == 1);
    try testing.expect(fv.countSince(10) == 0);
}
