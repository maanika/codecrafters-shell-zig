const std = @import("std");
const Allocator = std.mem.Allocator;

const State = enum {
    Normal,
    InSingleQuote,
    InDoubleQuote,
    InBackslashEscapeNormal,
    InBackslashEscapeDoubleQuote,
};

// Parses the command line input and returns the command and arguments
pub fn parseCommandLine(allocator: Allocator, input: []const u8) ![][]const u8 {
    var state: State = .Normal;

    //TODO: 100?
    var curr_arg = try std.ArrayList(u8).initCapacity(allocator, 100);
    defer curr_arg.deinit(allocator);

    //TODO: 5?
    var args = try std.ArrayList([]const u8).initCapacity(allocator, 5);
    defer args.deinit(allocator);

    for (input) |char| {
        switch (state) {
            .Normal => {
                if (char == ' ') {
                    // space acts as delimiters (unless quoted or escaped)
                    const arg = try curr_arg.toOwnedSlice(allocator);
                    if (arg.len > 0) try args.append(allocator, arg);
                } else if (char == '\'') {
                    state = .InSingleQuote;
                } else if (char == '\"') {
                    state = .InDoubleQuote;
                } else if (char == '\\') {
                    state = .InBackslashEscapeNormal;
                } else {
                    try curr_arg.append(allocator, char);
                }
            },
            .InSingleQuote => {
                if (char == '\'') {
                    state = .Normal;
                } else {
                    // Preserves literal values of all characters
                    try curr_arg.append(allocator, char);
                }
            },
            .InDoubleQuote => {
                if (char == '\"') {
                    state = .Normal;
                } else if (char == '\\') {
                    state = .InBackslashEscapeDoubleQuote;
                } else {
                    // preserve most characters (special characters checked above)
                    try curr_arg.append(allocator, char);
                }
            },
            .InBackslashEscapeNormal => {
                // escape the next character
                try curr_arg.append(allocator, char);
                state = .Normal;
            },
            .InBackslashEscapeDoubleQuote => {
                // TODO: only escape ($, `, ", \, and newline)
                try curr_arg.append(allocator, char);
                state = .InDoubleQuote;
            }
        }
    }

    // flush arg
    const arg = try curr_arg.toOwnedSlice(allocator);
    if (arg.len > 0) try args.append(allocator, arg);

    return try args.toOwnedSlice(allocator);
}
