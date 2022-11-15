const std = @import("std");
const Allocator = std.mem.Allocator;
const font = @import("../font/main.zig");

const log = std.log.scoped(.renderer_size);

/// The dimensions of a single "cell" in the terminal grid.
///
/// The dimensions are dependent on the current loaded set of font glyphs.
/// We calculate the width based on the widest character and the height based
/// on the height requirement for an underscore (the "lowest" -- visually --
/// character).
///
/// The units for the width and height are in world space. They have to
/// be normalized for any renderer implementation.
pub const CellSize = struct {
    width: f32,
    height: f32,

    /// Initialize the cell size information from a font group. This ensures
    /// that all renderers use the same cell sizing information for the same
    /// fonts.
    pub fn init(alloc: Allocator, group: *font.GroupCache) !CellSize {
        // Get our cell metrics based on a regular font ascii 'M'. Why 'M'?
        // Doesn't matter, any normal ASCII will do we're just trying to make
        // sure we use the regular font.
        const metrics = metrics: {
            const index = (try group.indexForCodepoint(alloc, 'M', .regular, .text)).?;
            const face = try group.group.faceFromIndex(index);
            break :metrics face.metrics;
        };
        log.debug("cell dimensions={}", .{metrics});

        return CellSize{
            .width = metrics.cell_width,
            .height = metrics.cell_height,
        };
    }
};

/// The dimensions of the screen that the grid is rendered to. This is the
/// terminal screen, so it is likely a subset of the window size. The dimensions
/// should be in pixels.
pub const ScreenSize = struct {
    width: u32,
    height: u32,

    /// Subtract padding from the screen size.
    pub fn subPadding(self: ScreenSize, padding: Padding) ScreenSize {
        return .{
            .width = self.width -| @floatToInt(u32, padding.left + padding.right),
            .height = self.height -| @floatToInt(u32, padding.top + padding.bottom),
        };
    }
};

/// The dimensions of the grid itself, in rows/columns units.
pub const GridSize = struct {
    const Unit = u32;

    columns: Unit = 0,
    rows: Unit = 0,

    /// Initialize a grid size based on a screen and cell size.
    pub fn init(screen: ScreenSize, cell: CellSize) GridSize {
        var result: GridSize = undefined;
        result.update(screen, cell);
        return result;
    }

    /// Update the columns/rows for the grid based on the given screen and
    /// cell size.
    pub fn update(self: *GridSize, screen: ScreenSize, cell: CellSize) void {
        self.columns = @max(1, @floatToInt(Unit, @intToFloat(f32, screen.width) / cell.width));
        self.rows = @max(1, @floatToInt(Unit, @intToFloat(f32, screen.height) / cell.height));
    }
};

/// The padding to add to a screen.
pub const Padding = struct {
    top: f32 = 0,
    bottom: f32 = 0,
    right: f32 = 0,
    left: f32 = 0,

    /// Returns padding that balances the whitespace around the screen
    /// for the given grid and cell sizes.
    pub fn balanced(screen: ScreenSize, grid: GridSize, cell: CellSize) Padding {
        // The size of our full grid
        const grid_width = @intToFloat(f32, grid.columns) * cell.width;
        const grid_height = @intToFloat(f32, grid.rows) * cell.height;

        // The empty space to the right of a line and bottom of the last row
        const space_right = @intToFloat(f32, screen.width) - grid_width;
        const space_bot = @intToFloat(f32, screen.height) - grid_height;

        // The left/right padding is just an equal split.
        const padding_right = @floor(space_right / 2);
        const padding_left = padding_right;

        // The top/bottom padding is interesting. Subjectively, lots of padding
        // at the top looks bad. So instead of always being equal (like left/right),
        // we force the top padding to be at most equal to the left, and the bottom
        // padding is the difference thereafter.
        const padding_top = @min(padding_left, @floor(space_bot / 2));
        const padding_bot = space_bot - padding_top;

        return .{
            .top = padding_top,
            .bottom = padding_bot,
            .right = padding_right,
            .left = padding_left,
        };
    }

    /// Add another padding to ths one
    pub fn add(self: Padding, other: Padding) Padding {
        return .{
            .top = self.top + other.top,
            .bottom = self.bottom + other.bottom,
            .right = self.right + other.right,
            .left = self.left + other.left,
        };
    }
};

test "GridSize update exact" {
    const testing = std.testing;

    var grid: GridSize = .{};
    grid.update(.{
        .width = 100,
        .height = 40,
    }, .{
        .width = 5,
        .height = 10,
    });

    try testing.expectEqual(@as(GridSize.Unit, 20), grid.columns);
    try testing.expectEqual(@as(GridSize.Unit, 4), grid.rows);
}

test "GridSize update rounding" {
    const testing = std.testing;

    var grid: GridSize = .{};
    grid.update(.{
        .width = 20,
        .height = 40,
    }, .{
        .width = 6,
        .height = 15,
    });

    try testing.expectEqual(@as(GridSize.Unit, 3), grid.columns);
    try testing.expectEqual(@as(GridSize.Unit, 2), grid.rows);
}
