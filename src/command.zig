const std = @import("std");
const Allocator = std.mem.Allocator;

const State = enum {
    Normal,
    InSingleQuote,
    InDoubleQuote,
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
        }
    }

    // flush arg
    const arg = try curr_arg.toOwnedSlice(allocator);
    if (arg.len > 0) try args.append(allocator, arg);

    return try args.toOwnedSlice(allocator);
}

// const std = @import("std");
//
// const State = enum {
//     Normal,
//     InSingleQuote,
// };
//
// /// Parses the command line input
// pub fn parseCommandLine(allocator: std.mem.Allocator, input: []const u8) ![][]const u8 {
//     var args_list = try std.ArrayList([]const u8).initCapacity(allocator, 5);
//     var current_arg = try std.ArrayList(u8).initCapacity(allocator, 100);
//     var state: State = .Normal;
//
//     // Cleanup if an error happens midway
//     errdefer {
//         for (args_list.items) |arg| {
//             allocator.free(arg);
//         }
//         args_list.deinit(allocator);
//         current_arg.deinit(allocator);
//     }
//
//     for (input) |char| {
//         switch (state) {
//             .Normal => {
//                 if (char == ' ') {
//                     const completed_arg = try current_arg.toOwnedSlice(allocator);
//                     if (completed_arg.len > 0) {
//                         try args_list.append(allocator, completed_arg);
//                     }
//                 } else if (char == '\'') {
//                     state = .InSingleQuote;
//                 } else {
//                     try current_arg.append(allocator, char);
//                 }
//
//             },
//             .InSingleQuote => {
//                 if (char == '\'') {
//                     state = .Normal;
//                 } else {
//                     try current_arg.append(allocator, char);
//                 }
//
//             },
//         }
//
//     }
//
//     if (current_arg.items.len > 0) {
//         const completed_arg = try current_arg.toOwnedSlice(allocator);
//         try args_list.append(allocator, completed_arg);
//     } else {
//         current_arg.deinit(allocator);
//     }
//
//     return try args_list.toOwnedSlice(allocator);
// }
