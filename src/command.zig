const std = @import("std");
const Allocator = std.mem.Allocator;

const State = enum {
    Normal,
    InSingleQuote,
    InDoubleQuote,
    InBackslashEscape,
};

// Parses the command line input and returns the command and arguments
pub fn parseCommandLine(allocator: Allocator, input: []const u8) ![][]const u8 {
    var state: State = .Normal;

    var curr_arg = try std.ArrayList(u8).initCapacity(allocator, 100);
    defer curr_arg.deinit(allocator);

    var args = try std.ArrayList([]const u8).initCapacity(allocator, 5);
    defer args.deinit(allocator);

    for (input) |char| {
        switch (state) {
            .Normal => {
                if (char == ' ') {
                    const arg = try curr_arg.toOwnedSlice(allocator);
                    if (arg.len > 0) try args.append(allocator, arg);
                } else if (char == '\'') {
                    state = .InSingleQuote;
                } else if (char == '\"') {
                    state = .InDoubleQuote;
                } else if (char == '\\') {
                    state = .InBackslashEscape;
                } else {
                    try curr_arg.append(allocator, char);
                }
            },
            .InSingleQuote => {
                if (char == '\'') {
                    state = .Normal;
                } else {
                    try curr_arg.append(allocator, char);
                }
            },
            .InDoubleQuote => {
                if (char == '\"') {
                    state = .Normal;
                } else {
                    try curr_arg.append(allocator, char);
                }
            },
            .InBackslashEscape => {
                try curr_arg.append(allocator, char);
                state = .Normal;
            },
        }
    }

    // flush arg
    const arg = try curr_arg.toOwnedSlice(allocator);
    if (arg.len > 0) try args.append(allocator, arg);

    return try args.toOwnedSlice(allocator);
}
