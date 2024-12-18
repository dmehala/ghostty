const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const args = @import("args.zig");
const Action = @import("action.zig").Action;
const Config = @import("../config.zig").Config;
const crash = @import("../crash/main.zig");

pub const Options = struct {
    /// This is set by the CLI parser for deinit.
    _arena: ?ArenaAllocator = null,

    /// Path of the report to inspect.
    path: ?[:0]const u8 = null,

    pub fn deinit(self: *Options) void {
        if (self._arena) |arena| arena.deinit();
        self.* = undefined;
    }

    /// Enables "-h" and "--help" to work.
    pub fn help(self: Options) !void {
        _ = self;
        return Action.help_error;
    }
};

/// The `crash-report` command is used to inspect and send crash reports.
///
/// When executed without any arguments, this will list existing crash reports.
///
/// This command currently only supports listing crash reports. Viewing
/// and sending crash reports is unimplemented and will be added in the future.
pub fn run(alloc_gpa: Allocator) !u8 {
    // Use an arena for the whole command to avoid manual memory management.
    var arena = ArenaAllocator.init(alloc_gpa);
    defer arena.deinit();
    const alloc = arena.allocator();

    var opts: Options = .{};
    defer opts.deinit();

    var iter = try args.argsIterator(alloc_gpa);
    defer iter.deinit();
    try args.parse(Options, alloc_gpa, &opts, &iter);

    if (opts.path) |report_path| {
        return inspectReport(alloc, report_path);
    } else {
        return listReports(alloc);
    }
}

fn inspectReport(alloc: Allocator, report_id: [:0]const u8) !u8 {
    const stdout = std.io.getStdOut();
    const fs = std.fs;

    const crash_dir = try crash.defaultDir(alloc);
    const report = try fs.path.join(alloc, &.{ crash_dir.path, report_id });

    var file = try fs.openFileAbsolute(report, .{ .mode = .read_only });
    defer file.close();

    const parsed: crash.Envelope = parsed: {
        break :parsed try crash.Envelope.parse(alloc, file.reader());
    };

    var iter = parsed.headers.iterator();
    while (iter.next()) |e| {
        try stdout.writer().print("{s}: {any}\n", .{ e.key_ptr.*, e.value_ptr.* });
    }

    const writer = stdout.writer();
    for (parsed.items.items) |item| {
        switch (item) {
            .encoded => |encoded_item| {
                switch (encoded_item.type) {
                    .event => {
                        var parsed_json = parsed: {
                            break :parsed try std.json.parseFromSlice(std.json.Value, alloc, encoded_item.payload, .{});
                        };

                        iter = parsed_json.value.object.iterator();
                        while (iter.next()) |j| {
                            try writer.print("{s}: {any}\n", .{ j.key_ptr.*, j.value_ptr.* });
                        }
                    },
                    else => {},
                }
            },
            .attachment => {},
        }
    }

    return 0;
}

fn listReports(alloc: Allocator) !u8 {
    const crash_dir = try crash.defaultDir(alloc);
    var reports = std.ArrayList(crash.Report).init(alloc);

    var it = try crash_dir.iterator();
    while (try it.next()) |report| try reports.append(.{
        .name = try alloc.dupe(u8, report.name),
        .mtime = report.mtime,
    });

    const stdout = std.io.getStdOut();

    // If we have no reports, then we're done. If we have a tty then we
    // print a message, otherwise we do nothing.
    if (reports.items.len == 0) {
        if (std.posix.isatty(stdout.handle)) {
            try stdout.writeAll("No crash reports! 👻");
        }
        return 0;
    }

    std.mem.sort(crash.Report, reports.items, {}, lt);

    const writer = stdout.writer();
    for (reports.items) |report| {
        var buf: [128]u8 = undefined;
        const now = std.time.nanoTimestamp();
        const diff = now - report.mtime;
        const since = if (diff <= 0) "now" else s: {
            const d = Config.Duration{ .duration = @intCast(diff) };
            break :s try std.fmt.bufPrint(&buf, "{s} ago", .{d.round(std.time.ns_per_s)});
        };
        try writer.print("{s} ({s})\n", .{ report.name, since });
    }

    return 0;
}

fn lt(_: void, lhs: crash.Report, rhs: crash.Report) bool {
    return lhs.mtime > rhs.mtime;
}
