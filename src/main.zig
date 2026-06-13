const std = @import("std");

const BuiltinCommand = enum {
    exit,
    echo,
    type,
};

pub fn main(init: std.process.Init) !void {
    var stdin_buffer: [4096]u8 = undefined;
    var stdin = std.Io.File.stdin().readerStreaming(init.io, &stdin_buffer);

    var stdout = std.Io.File.stdout().writer(init.io, &.{});

    var arena_allocator: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    const path_env = try init.minimal.environ.getAlloc(arena, "PATH");
    defer arena.free(path_env);

    while (true) {
        try stdout.interface.print("$ ", .{});
        const input: ?[]u8 = try stdin.interface.takeDelimiter('\n') orelse {
            continue;
        };
        //TODO: need to skip if no input (i.e an enter)

        var iter = std.mem.splitScalar(u8, input.?, ' ');

        const command: []const u8 = iter.first();

        const command_enum = std.meta.stringToEnum(BuiltinCommand, command) orelse {
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
                    while (dirs.peek() != null) {
                        //std.debug.print("{?s}\n", .{dirs.next()});
                        const path: ?[]const u8 = dirs.next() orelse {
                            break;
                        };
                        var dir = try std.Io.Dir.cwd().openDir(init.io, path.?, .{ .iterate = true });
                        defer dir.close(init.io);
                        var dir_iterate = dir.iterate();

                        while (try dir_iterate.next(init.io)) |entry| {
                            if ((entry.kind == .file) and (std.mem.eql(u8, argument, entry.name))) {
                                try stdout.interface.print("{s} is {s}/{s}\n", .{ argument, path.?, entry.name });
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
                try stdout.interface.print("{s} is a shell builtin\n", .{argument});
            },
        }
    }
}
