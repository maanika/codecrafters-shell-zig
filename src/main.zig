const std = @import("std");
const builtin = @import("builtin");

const BuiltinCommand = enum {
    exit,
    echo,
    type,
};

fn fileExists(dir: std.Io.Dir, io: anytype, name: []const u8) bool {
    dir.access(io, name, .{}) catch return false;
    return true;
}

fn canExecute(dir: std.Io.Dir, io: anytype, name: []const u8) bool {
    dir.access(io, name, .{ .execute = true }) catch return false;
    return true;
}

pub fn main(init: std.process.Init) !void {
    var stdin_buffer: [4096]u8 = undefined;
    var stdin = std.Io.File.stdin().readerStreaming(init.io, &stdin_buffer);

    var stdout = std.Io.File.stdout().writer(init.io, &.{});

    var arena_allocator: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    const path_env = try init.minimal.environ.getAlloc(arena, "PATH");

    while (true) {
        try stdout.interface.print("$ ", .{});
        const input: ?[]u8 = try stdin.interface.takeDelimiter('\n') orelse {
            // This needs to continue if input is NULL (seel below todo) ?
            continue;
        };
        //TODO: need to skip if no input (i.e an enter)

        var iter = std.mem.splitScalar(u8, input.?, ' ');

        // Get command (first word)
        const command: []const u8 = iter.first();

        // Check if command is an in-build command
        const command_enum = std.meta.stringToEnum(BuiltinCommand, command) orelse {
            // Only supporting in-built commands right now
            try stdout.interface.print("{s}: command not found\n", .{input.?});
            continue;
        };

        const argument: []const u8 = iter.rest();

        switch (command_enum) {
            .exit => {
                return;
            },
            .echo => {
                try stdout.interface.print("{s}\n", .{iter.rest()});
            },
            .type => {
                //TODO: use a cleaner API for this
                _ = std.meta.stringToEnum(BuiltinCommand, argument) orelse {
                    const path_sep = if (builtin.os.tag == .windows) ';' else ':';
                    var dirs = std.mem.splitScalar(u8, path_env, path_sep);
                    
                    const found: bool = iterate_dirs: while (dirs.next()) |path| {
                        var dir = try std.Io.Dir.cwd().openDir(init.io, path, .{ .iterate = true });
                        defer dir.close(init.io);
                        // var dir_iterate = dir.iterate();
                        //
                        // while (try dir_iterate.next(init.io)) |entry| {
                        //     if (entry.kind == .file and std.mem.eql(u8, argument, entry.name) and canExecute(dir, init.io, entry.name)) {
                        //         try stdout.interface.print("{s} is {s}/{s}\n", .{ argument, path, entry.name });
                        //         break :iterate_dirs true;
                        //     }
                        // }
                        if (fileExists(dir, init.io, argument) and canExecute(dir, init.io, argument)) {
                            try stdout.interface.print("{s} is {s}/{s}\n", .{ argument, path, argument });
                            break :iterate_dirs true;
                        }
                    } else false;

                    if (!found) {
                        try stdout.interface.print("{s}: not found\n", .{argument});
                    }
                    continue;
                };
                // If string to enum passes, means it is a builtin command
                try stdout.interface.print("{s} is a shell builtin\n", .{argument});
            },
        }
    }
}
