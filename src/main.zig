const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var stdin_buffer: [4096]u8 = undefined;
    var stdin = std.Io.File.stdin().readerStreaming(init.io, &stdin_buffer);

    var stdout = std.Io.File.stdout().writer(init.io, &.{});

    while (true) {
        try stdout.interface.print("$ ", .{});
        const input: ?[]u8 = try stdin.interface.takeDelimiter('\n');

        var iter = std.mem.splitScalar(u8, input.?, ' ');

        const command: []const u8 = iter.first();

        if (std.mem.eql(u8, command, "exit")) {
            return;
        }

        if (std.mem.eql(u8, command, "echo")) {
            try stdout.interface.print("{s}\n", .{iter.rest()});
            continue;
        }

        try stdout.interface.print("{s}: command not found\n", .{input orelse ""});
    }
}
