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

    std.log.info("contains HOME: {any}", .{std.process.Init.Minimal.environ.contains(arena, "PATH")});

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
                continue;
            },
            .type => {
                const argument: []const u8 = iter.rest();
                //TODO: use a cleaner API for this
                _ = std.meta.stringToEnum(BuiltinCommand, argument) orelse {

                    // Get the PATH environment variable


                    // const dirs = std.mem.splitScalar(u8, path_env, ':');
                    // while (dirs) |dir| {
                    //     std.debug.print("Directory: {s}\n", .{dir});
                    // }

                    continue;
                };
                try stdout.interface.print("{s} is a shell builtin\n", .{argument});
            },
        }
    }
}
