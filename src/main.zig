const std = @import("std");

const BuiltinCommand = enum {
    exit,
    echo,
    type,
};

fn canExecute(path: []const u8, io: std.Io) bool {
    std.Io.Dir.cwd().access(io, path, .{.execute = true }) catch return false;
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

        switch (command_enum) {
            .exit => {
                return;
            },
            .echo => {
                try stdout.interface.print("{s}\n", .{iter.rest()});
            },
            .type => {
                const argument: []const u8 = iter.rest();
                //TODO: use a cleaner API for this
                _ = std.meta.stringToEnum(BuiltinCommand, argument) orelse {
                    var found_file: bool = false;
                    // Linux uses ':', Windows use ';'
                    var dirs = std.mem.splitScalar(u8, path_env, ':');
                    while (dirs.next())  |path| {
                        //std.debug.print("{s}\n", .{path});
                        var dir = try std.Io.Dir.cwd().openDir(init.io, path, .{ .iterate = true });
                        defer dir.close(init.io);
                        var dir_iterate = dir.iterate();

                        while (try dir_iterate.next(init.io)) |entry| {
                            // Add execution check
                            if ((entry.kind == .file) and (std.mem.eql(u8, argument, entry.name)) and canExecute(path, init.io)) {
                                // var file = try std.Io.Dir.cwd().openFile(init.io, path, .{.mode = .read_only});
                                // defer file.close(init.io);
                                // const file_stat = try file.stat(init.io);
                                // const permissions = file_stat.permissions & 0o0001;
                                // if (permissions != 0o0001) {
                                //     continue;
                                // }

                                try stdout.interface.print("{s} is {s}/{s}\n", .{ argument, path, entry.name });
                                found_file = true;
                                break;
                            }
                        }
                        if (found_file) {
                            break;
                        }
                    }

                    if (found_file == false) {
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
