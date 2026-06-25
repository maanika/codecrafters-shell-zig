const std = @import("std");
const builtin = @import("builtin");

const BuiltInCommand = enum {
    exit,
    echo,
    type,
};

const MyErrors = error{
    NotFound,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var stdin_buffer: [4096]u8 = undefined;
    var stdin = std.Io.File.stdin().readerStreaming(io, &stdin_buffer);

    var stdout = std.Io.File.stdout().writer(io, &.{});

    var arena_allocator: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    const path_env = try init.minimal.environ.getAlloc(arena, "PATH");

    while (true) {
        try stdout.interface.print("$ ", .{});
        const input: ?[]u8 = try stdin.interface.takeDelimiter('\n') orelse break;

        var iter = std.mem.splitScalar(u8, input.?, ' ');

        // Get command (first word)
        const command: []const u8 = iter.first();
        if (command.len == 0) continue;

        // Check if command is an builtin command
        const command_enum = std.meta.stringToEnum(BuiltInCommand, command) orelse {
            // determine if commnand is an executable
            // if yes -> execute the program (passing arguments from the command line)
            const path: ?[]const u8 = findExecutableFromPATH(io, path_env, command) catch null;
            if (path) |_| {
                // TODO: only allowing 5 args for now?
                var buffer = try std.ArrayList([]const u8).initCapacity(arena, 5);
                defer buffer.deinit(arena);

                // Add the program path as the first argument
                try buffer.append(arena, command);

                while (iter.next()) |value| {
                    try buffer.append(arena, value);
                }
                const result = std.process.run(arena, io, .{ .argv = buffer.items }) catch {
                    continue;
                };

                try stdout.interface.print("{s}", .{result.stdout});
            } else {
                try stdout.interface.print("{s}: command not found\n", .{input.?});
            }
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
                _ = std.meta.stringToEnum(BuiltInCommand, argument) orelse {
                    const path: ?[]const u8 = findExecutableFromPATH(io, path_env, argument) catch null;

                    if (path) |p| {
                        try stdout.interface.print("{s} is {s}/{s}\n", .{ argument, p, argument });
                    } else {
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

fn canExecute(dir: std.Io.Dir, io: anytype, name: []const u8) bool {
    dir.access(io, name, .{ .execute = true }) catch return false;
    return true;
}

fn findExecutableFromPATH(io: std.Io, path_env: []const u8, find: []const u8) MyErrors![]const u8 {
    const path_sep = if (builtin.os.tag == .windows) ';' else ':';
    var dirs = std.mem.splitScalar(u8, path_env, path_sep);

    while (dirs.next()) |path| {
        var dir = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch continue;
        defer dir.close(io);
        if (canExecute(dir, io, find)) {
            return path;
        }
    }
    return MyErrors.NotFound;
}
