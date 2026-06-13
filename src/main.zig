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

    while (true) {
        try stdout.interface.print("\n$ ", .{});
        const input: ?[]u8 = try stdin.interface.takeDelimiter('\n') orelse {
            continue;
        };

        var iter = std.mem.splitScalar(u8, input.?, ' ');

        const command: []const u8 = iter.first();

        const command_enum = std.meta.stringToEnum(BuiltinCommand, command) orelse {
            try stdout.interface.print("{s}: command not found", .{input.?});
            continue;
        };

        switch (command_enum) {
            .exit => {
                return;
            },
            .echo => {
                try stdout.interface.print("{s}", .{iter.rest()});
                continue;
            },
            .type => {
                const argument: []const u8 = iter.rest();
                _ = std.meta.stringToEnum(BuiltinCommand, argument) orelse {
                    try stdout.interface.print("{s}: not found", .{argument});
                    continue;
                };
                try stdout.interface.print("{s} is a shell builtin", .{argument});
            },
        }
    }
}
