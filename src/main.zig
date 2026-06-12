const std = @import("std");

const Command = enum {
    exit,
    echo,
};

pub fn main(init: std.process.Init) !void {
    var stdin_buffer: [4096]u8 = undefined;
    var stdin = std.Io.File.stdin().readerStreaming(init.io, &stdin_buffer);

    var stdout = std.Io.File.stdout().writer(init.io, &.{});

    while (true) {
        try stdout.interface.print("$ ", .{});
        const input: ?[]u8 = try stdin.interface.takeDelimiter('\n');

        var iter = std.mem.splitScalar(u8, input.?, ' ');

        const command: []const u8 = iter.first();
        const command_enum = std.meta.stringToEnum(Command, command) orelse continue;
        switch (command_enum) {
            .exit => {
                return;
            },
            .echo => {
                try stdout.interface.print("{s}\n", .{iter.rest()});
                continue;
            },
        }

        try stdout.interface.print("{s}: command not found\n", .{input orelse ""});
    }
}
