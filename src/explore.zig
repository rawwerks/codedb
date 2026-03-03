const std = @import("std");
const Store = @import("store.zig").Store;
const idx = @import("index.zig");
const WordIndex = idx.WordIndex;
const TrigramIndex = idx.TrigramIndex;

pub const SymbolKind = enum(u8) {
    function,
    struct_def,
    enum_def,
    union_def,
    constant,
    variable,
    import,
    test_decl,
    comment_block,
};

pub const Symbol = struct {
    name: []const u8,
    kind: SymbolKind,
    line_start: u32,
    line_end: u32,
    detail: ?[]const u8 = null,
};

pub const FileOutline = struct {
    path: []const u8,
    language: Language,
    line_count: u32,
    byte_size: u64,
    symbols: std.ArrayList(Symbol) = .{},
    imports: std.ArrayList([]const u8) = .{},
    imported_by: std.ArrayList([]const u8) = .{},
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) FileOutline {
        return .{
            .path = path,
            .language = detectLanguage(path),
            .line_count = 0,
            .byte_size = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FileOutline) void {
        self.symbols.deinit(self.allocator);
        self.imports.deinit(self.allocator);
        self.imported_by.deinit(self.allocator);
    }
};

pub const Language = enum(u8) {
    zig,
    c,
    cpp,
    python,
    javascript,
    typescript,
    rust,
    go_lang,
    markdown,
    json,
    yaml,
    unknown,
};

fn detectLanguage(path: []const u8) Language {
    if (std.mem.endsWith(u8, path, ".zig")) return .zig;
    if (std.mem.endsWith(u8, path, ".c") or std.mem.endsWith(u8, path, ".h")) return .c;
    if (std.mem.endsWith(u8, path, ".cpp") or std.mem.endsWith(u8, path, ".hpp")) return .cpp;
    if (std.mem.endsWith(u8, path, ".py")) return .python;
    if (std.mem.endsWith(u8, path, ".js")) return .javascript;
    if (std.mem.endsWith(u8, path, ".ts") or std.mem.endsWith(u8, path, ".tsx")) return .typescript;
    if (std.mem.endsWith(u8, path, ".rs")) return .rust;
    if (std.mem.endsWith(u8, path, ".go")) return .go_lang;
    if (std.mem.endsWith(u8, path, ".md")) return .markdown;
    if (std.mem.endsWith(u8, path, ".json")) return .json;
    if (std.mem.endsWith(u8, path, ".yaml") or std.mem.endsWith(u8, path, ".yml")) return .yaml;
    return .unknown;
}

pub const SymbolResult = struct {
    path: []const u8,
    symbol: Symbol,
};

pub const SearchResult = struct {
    path: []const u8,
    line_num: u32,
    line_text: []const u8,
};

pub const Explorer = struct {
    outlines: std.StringHashMap(FileOutline),
    dep_graph: std.StringHashMap(std.ArrayList([]const u8)),
    contents: std.StringHashMap([]const u8),
    word_index: WordIndex,
    trigram_index: TrigramIndex,
    allocator: std.mem.Allocator,
    mu: std.Thread.Mutex = .{},

    pub fn init(allocator: std.mem.Allocator) Explorer {
        return .{
            .outlines = std.StringHashMap(FileOutline).init(allocator),
            .dep_graph = std.StringHashMap(std.ArrayList([]const u8)).init(allocator),
            .contents = std.StringHashMap([]const u8).init(allocator),
            .word_index = WordIndex.init(allocator),
            .trigram_index = TrigramIndex.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Explorer) void {
        var iter = self.outlines.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.outlines.deinit();

        var dep_iter = self.dep_graph.iterator();
        while (dep_iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.dep_graph.deinit();

        var content_iter = self.contents.iterator();
        while (content_iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.contents.deinit();

        self.word_index.deinit();
        self.trigram_index.deinit();
    }

    pub fn indexFile(self: *Explorer, path: []const u8, content: []const u8) !void {
        self.mu.lock();
        defer self.mu.unlock();

        const duped_path = try self.allocator.dupe(u8, path);

        var outline = FileOutline.init(self.allocator, duped_path);
        outline.byte_size = content.len;

        var line_num: u32 = 0;
        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            line_num += 1;
            const trimmed = std.mem.trim(u8, line, " \t");

            if (outline.language == .zig) {
                try self.parseZigLine(trimmed, line_num, &outline);
            } else if (outline.language == .python) {
                try self.parsePythonLine(trimmed, line_num, &outline);
            } else if (outline.language == .typescript or outline.language == .javascript) {
                try self.parseTsLine(trimmed, line_num, &outline);
            }
        }
        outline.line_count = line_num;

        if (self.outlines.getPtr(duped_path)) |old| {
            old.deinit();
        }
        try self.outlines.put(duped_path, outline);

        const duped_content = try self.allocator.dupe(u8, content);
        if (self.contents.getPtr(duped_path)) |old_content| {
            self.allocator.free(old_content.*);
        }
        try self.contents.put(duped_path, duped_content);

        // Build search indexes
        try self.word_index.indexFile(duped_path, content);
        try self.trigram_index.indexFile(duped_path, content);

        try self.rebuildDepsFor(duped_path, &outline);
    }

    /// Fast path: index outline + content storage only, skip word/trigram indexes.
    /// Used during initial scan for speed. Search indexes are built lazily on first query.
    pub fn indexFileOutlineOnly(self: *Explorer, path: []const u8, content: []const u8) !void {
        self.mu.lock();
        defer self.mu.unlock();

        const duped_path = try self.allocator.dupe(u8, path);

        var outline = FileOutline.init(self.allocator, duped_path);
        outline.byte_size = content.len;

        var line_num: u32 = 0;
        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            line_num += 1;
            const trimmed = std.mem.trim(u8, line, " \t");

            if (outline.language == .zig) {
                try self.parseZigLine(trimmed, line_num, &outline);
            } else if (outline.language == .python) {
                try self.parsePythonLine(trimmed, line_num, &outline);
            } else if (outline.language == .typescript or outline.language == .javascript) {
                try self.parseTsLine(trimmed, line_num, &outline);
            }
        }
        outline.line_count = line_num;

        if (self.outlines.getPtr(duped_path)) |old| {
            old.deinit();
        }
        try self.outlines.put(duped_path, outline);

        const duped_content = try self.allocator.dupe(u8, content);
        if (self.contents.getPtr(duped_path)) |old_content| {
            self.allocator.free(old_content.*);
        }
        try self.contents.put(duped_path, duped_content);

        try self.rebuildDepsFor(duped_path, &outline);
    }

    pub fn removeFile(self: *Explorer, path: []const u8) void {
        self.mu.lock();
        defer self.mu.unlock();
        if (self.outlines.getPtr(path)) |outline| {
            outline.deinit();
            _ = self.outlines.remove(path);
        }
        if (self.dep_graph.getPtr(path)) |deps| {
            deps.deinit(self.allocator);
            _ = self.dep_graph.remove(path);
        }
        if (self.contents.getPtr(path)) |content| {
            self.allocator.free(content.*);
            _ = self.contents.remove(path);
        }
        self.word_index.removeFile(path);
        self.trigram_index.removeFile(path);
    }

    pub fn getOutline(self: *Explorer, path: []const u8) ?*const FileOutline {
        self.mu.lock();
        defer self.mu.unlock();
        return if (self.outlines.getPtr(path)) |ptr| ptr else null;
    }

    pub fn getTree(self: *Explorer, allocator: std.mem.Allocator) ![]u8 {
        self.mu.lock();
        defer self.mu.unlock();

        var buf: std.ArrayList(u8) = .{};
        const writer = buf.writer(allocator);

        var paths: std.ArrayList([]const u8) = .{};
        defer paths.deinit(allocator);

        var iter = self.outlines.iterator();
        while (iter.next()) |entry| {
            try paths.append(allocator, entry.key_ptr.*);
        }

        std.mem.sort([]const u8, paths.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.order(u8, a, b) == .lt;
            }
        }.lessThan);

        for (paths.items) |path| {
            const outline = self.outlines.get(path) orelse continue;
            const depth = std.mem.count(u8, path, "/");
            for (0..depth) |_| try writer.writeAll("  ");

            try writer.print("{s}  ({s}, {d}L, {d} symbols)\n", .{
                path,
                @tagName(outline.language),
                outline.line_count,
                outline.symbols.items.len,
            });
        }

        return buf.toOwnedSlice(allocator);
    }

    pub fn findSymbol(self: *Explorer, name: []const u8) !?struct { path: []const u8, symbol: Symbol } {
        self.mu.lock();
        defer self.mu.unlock();

        var iter = self.outlines.iterator();
        while (iter.next()) |entry| {
            for (entry.value_ptr.symbols.items) |sym| {
                if (std.mem.eql(u8, sym.name, name)) {
                    return .{ .path = entry.key_ptr.*, .symbol = sym };
                }
            }
        }
        return null;
    }

    pub fn findAllSymbols(self: *Explorer, name: []const u8, allocator: std.mem.Allocator) ![]const SymbolResult {
        self.mu.lock();
        defer self.mu.unlock();

        var result_list: std.ArrayList(SymbolResult) = .{};

        var iter = self.outlines.iterator();
        while (iter.next()) |entry| {
            for (entry.value_ptr.symbols.items) |sym| {
                if (std.mem.eql(u8, sym.name, name)) {
                    try result_list.append(allocator, .{ .path = entry.key_ptr.*, .symbol = sym });
                }
            }
        }
        return result_list.toOwnedSlice(allocator);
    }

    pub fn searchContent(self: *Explorer, query: []const u8, allocator: std.mem.Allocator, max_results: usize) ![]const SearchResult {
        self.mu.lock();
        defer self.mu.unlock();

        var result_list: std.ArrayList(SearchResult) = .{};

        // Try trigram index to narrow candidates (queries >= 3 chars)
        const candidate_paths = self.trigram_index.candidates(query);
        const use_trigram = candidate_paths != null and candidate_paths.?.len > 0;

        if (use_trigram) {
            // Only scan candidate files
            for (candidate_paths.?) |path| {
                const content = self.contents.get(path) orelse continue;
                try searchInContent(path, content, query, allocator, max_results, &result_list);
                if (result_list.items.len >= max_results) break;
            }
        } else {
            // Brute force (short query or no trigram hits)
            var iter = self.contents.iterator();
            while (iter.next()) |entry| {
                try searchInContent(entry.key_ptr.*, entry.value_ptr.*, query, allocator, max_results, &result_list);
                if (result_list.items.len >= max_results) break;
            }
        }

        return result_list.toOwnedSlice(allocator);
    }

    /// Search for a word using the inverted word index. O(1) lookup.
    pub fn searchWord(self: *Explorer, word: []const u8, allocator: std.mem.Allocator) ![]const idx.WordHit {
        self.mu.lock();
        defer self.mu.unlock();
        return self.word_index.searchDeduped(word, allocator);
    }

    pub fn getImportedBy(self: *Explorer, path: []const u8) ![]const []const u8 {
        self.mu.lock();
        defer self.mu.unlock();

        // Extract basename for matching against raw import strings
        // e.g., "src/store.zig" → "store.zig"
        const basename = if (std.mem.lastIndexOfScalar(u8, path, '/')) |pos| path[pos + 1 ..] else path;

        var result: std.ArrayList([]const u8) = .{};

        var iter = self.dep_graph.iterator();
        while (iter.next()) |entry| {
            for (entry.value_ptr.items) |dep| {
                if (std.mem.eql(u8, dep, path) or std.mem.eql(u8, dep, basename)) {
                    try result.append(self.allocator, entry.key_ptr.*);
                    break;
                }
            }
        }
        return result.toOwnedSlice(self.allocator);
    }

    pub fn getHotFiles(self: *Explorer, store: *Store, limit: usize) ![]const []const u8 {
        self.mu.lock();
        defer self.mu.unlock();

        const Entry = struct { path: []const u8, seq: u64 };
        var entries: std.ArrayList(Entry) = .{};
        defer entries.deinit(self.allocator);

        var iter = self.outlines.iterator();
        while (iter.next()) |kv| {
            const latest_ver = store.getLatest(kv.key_ptr.*);
            const seq = if (latest_ver) |v| v.seq else 0;
            try entries.append(self.allocator, .{ .path = kv.key_ptr.*, .seq = seq });
        }

        std.mem.sort(Entry, entries.items, {}, struct {
            fn cmp(_: void, a: Entry, b: Entry) bool {
                return a.seq > b.seq;
            }
        }.cmp);

        const count = @min(limit, entries.items.len);
        var paths: std.ArrayList([]const u8) = .{};
        for (entries.items[0..count]) |e| {
            try paths.append(self.allocator, e.path);
        }
        return paths.toOwnedSlice(self.allocator);
    }

    // ── Language parsers ──────────────────────────────────────

    fn parseZigLine(self: *Explorer, line: []const u8, line_num: u32, outline: *FileOutline) !void {
        const a = self.allocator;
        if (startsWith(line, "pub fn ") or startsWith(line, "fn ")) {
            const start: usize = if (startsWith(line, "pub fn ")) 7 else 3;
            if (extractIdent(line[start..])) |name| {
                try outline.symbols.append(a, .{
                    .name = try a.dupe(u8, name), .kind = .function,
                    .line_start = line_num, .line_end = line_num,
                    .detail = try a.dupe(u8, line),
                });
            }
        } else if (startsWith(line, "pub const ") or startsWith(line, "const ")) {
            const start: usize = if (startsWith(line, "pub const ")) 10 else 6;
            if (extractIdent(line[start..])) |name| {
                const kind: SymbolKind = if (std.mem.indexOf(u8, line, "struct") != null)
                    .struct_def
                else if (std.mem.indexOf(u8, line, "enum") != null)
                    .enum_def
                else if (std.mem.indexOf(u8, line, "union") != null)
                    .union_def
                else if (std.mem.indexOf(u8, line, "@import") != null)
                    .import
                else
                    .constant;

                try outline.symbols.append(a, .{
                    .name = try a.dupe(u8, name), .kind = kind,
                    .line_start = line_num, .line_end = line_num,
                    .detail = try a.dupe(u8, line),
                });

                if (kind == .import) {
                    if (extractStringLiteral(line)) |import_path| {
                        try outline.imports.append(a, try a.dupe(u8, import_path));
                    }
                }
            }
        } else if (startsWith(line, "test ")) {
            try outline.symbols.append(a, .{
                .name = try a.dupe(u8, line), .kind = .test_decl,
                .line_start = line_num, .line_end = line_num,
            });
        }
    }

    fn parsePythonLine(self: *Explorer, line: []const u8, line_num: u32, outline: *FileOutline) !void {
        const a = self.allocator;
        if (startsWith(line, "def ")) {
            if (extractIdent(line[4..])) |name| {
                try outline.symbols.append(a, .{ .name = try a.dupe(u8, name), .kind = .function, .line_start = line_num, .line_end = line_num, .detail = try a.dupe(u8, line) });
            }
        } else if (startsWith(line, "class ")) {
            if (extractIdent(line[6..])) |name| {
                try outline.symbols.append(a, .{ .name = try a.dupe(u8, name), .kind = .struct_def, .line_start = line_num, .line_end = line_num, .detail = try a.dupe(u8, line) });
            }
        } else if (startsWith(line, "import ") or startsWith(line, "from ")) {
            try outline.symbols.append(a, .{ .name = try a.dupe(u8, line), .kind = .import, .line_start = line_num, .line_end = line_num });
            try outline.imports.append(a, try a.dupe(u8, line));
        }
    }

    fn parseTsLine(self: *Explorer, line: []const u8, line_num: u32, outline: *FileOutline) !void {
        const a = self.allocator;
        if (containsAny(line, &.{ "function ", "const ", "export function ", "export const " })) {
            const kind: SymbolKind = if (std.mem.indexOf(u8, line, "function") != null) .function else .constant;
            const trimmed = skipKeywords(line);
            if (extractIdent(trimmed)) |name| {
                try outline.symbols.append(a, .{ .name = try a.dupe(u8, name), .kind = kind, .line_start = line_num, .line_end = line_num, .detail = try a.dupe(u8, line) });
            }
        }
        if (containsAny(line, &.{ "import ", "require(" })) {
            try outline.symbols.append(a, .{ .name = try a.dupe(u8, line), .kind = .import, .line_start = line_num, .line_end = line_num });
            if (extractStringLiteral(line)) |path| {
                try outline.imports.append(a, try a.dupe(u8, path));
            }
        }
    }

    fn rebuildDepsFor(self: *Explorer, path: []const u8, outline: *FileOutline) !void {
        var deps: std.ArrayList([]const u8) = .{};
        for (outline.imports.items) |imp| {
            try deps.append(self.allocator, imp);
        }
        if (self.dep_graph.getPtr(path)) |old| {
            old.deinit(self.allocator);
        }
        try self.dep_graph.put(path, deps);
    }
};

fn searchInContent(path: []const u8, content: []const u8, query: []const u8, allocator: std.mem.Allocator, max_results: usize, result_list: *std.ArrayList(SearchResult)) !void {
    var line_num: u32 = 0;
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        line_num += 1;
        if (std.mem.indexOf(u8, line, query) != null) {
            try result_list.append(allocator, .{
                .path = path,
                .line_num = line_num,
                .line_text = try allocator.dupe(u8, line),
            });
            if (result_list.items.len >= max_results) return;
        }
    }
}

fn startsWith(haystack: []const u8, needle: []const u8) bool {
    return std.mem.startsWith(u8, haystack, needle);
}

fn extractIdent(s: []const u8) ?[]const u8 {
    var end: usize = 0;
    for (s) |ch| {
        if (std.ascii.isAlphanumeric(ch) or ch == '_') {
            end += 1;
        } else break;
    }
    return if (end > 0) s[0..end] else null;
}

fn extractStringLiteral(s: []const u8) ?[]const u8 {
    const quote_chars = [_]u8{ '"', '\'' };
    for (quote_chars) |q| {
        if (std.mem.indexOfScalar(u8, s, q)) |start_pos| {
            if (std.mem.indexOfScalarPos(u8, s, start_pos + 1, q)) |end_pos| {
                return s[start_pos + 1 .. end_pos];
            }
        }
    }
    return null;
}

fn containsAny(s: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| {
        if (std.mem.indexOf(u8, s, needle) != null) return true;
    }
    return false;
}

fn skipKeywords(s: []const u8) []const u8 {
    const keywords = [_][]const u8{ "export ", "async ", "function ", "const ", "let ", "var " };
    var result = s;
    for (keywords) |kw| {
        if (std.mem.startsWith(u8, result, kw)) {
            result = result[kw.len..];
        }
    }
    return result;
}
