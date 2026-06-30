const std = @import("std");
const builtin = @import("builtin");

const BuiltInCommand = enum {
    exit,
    echo,
    type,
    pwd,
    cd,
};

const MyErrors = error{
    NotFound,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var stdin_buffer: [4096]u8 = undefined;
    var stdin = std.Io.File.stdin().readerStreaming(io, &stdin_buffer);

    var stdout_writer = std.Io.File.stdout().writer(io, &.{});
    const stdout = &stdout_writer.interface;

    var arena_allocator: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    const path_env = try init.minimal.environ.getAlloc(arena, "PATH");
    const home_path = try init.minimal.environ.getAlloc(arena, "HOME");

    while (true) {
        try stdout.print("$ ", .{});
        const input: ?[]u8 = try stdin.interface.takeDelimiter('\n') orelse break;

        var iter = std.mem.splitScalar(u8, input.?, ' ');

        // Get command (first word)
        const command: []const u8 = iter.first();
        if (command.len == 0) continue;

        // Single Quotes
        // TODO: only allowing 5 args for now? expand logic
        var buffer = try std.ArrayList([]const u8).initCapacity(arena, 5);
        defer buffer.deinit(arena);

        // Add the program path as the first argument
        try buffer.append(arena, command);

        const rest: []const u8 = iter.rest();
        var iter2 = std.mem.tokenizeAny(u8, rest, " '");
        // TODO: can I replace this with iter2.rest and appendSlice?
        while (iter2.next()) |value| {
            try buffer.append(arena, value);
        }

        // Check if command is an builtin command
        const command_enum = std.meta.stringToEnum(BuiltInCommand, command) orelse {
            // determine if commnand is an executable
            // if yes -> execute the program (passing arguments from the command line)
            const path: ?[]const u8 = findExecutableFromPATH(io, path_env, command) catch null;
            if (path) |_| {
                const result = std.process.run(arena, io, .{ .argv = buffer.items }) catch {
                    continue;
                };

                try stdout.print("{s}", .{result.stdout});
            } else {
                try stdout.print("{s}: command not found\n", .{input.?});
            }
            continue;
        };
        

        // remove command
        _ = buffer.orderedRemove(0);

        switch (command_enum) {
            .exit => {
                return;
            },
            .echo => {
                const items = buffer.items.len;
                for (0..items) |i| {
                    try stdout.print("{s}", .{buffer.orderedRemove(0)});
                    if (i < items - 1) {
                        try stdout.print(" ", .{});
                    }
                }
                try stdout.print("\n", .{});
            },
            .type => {
                const argument: []const u8 = buffer.pop() orelse continue;
                //TODO: use a cleaner API for this
                _ = std.meta.stringToEnum(BuiltInCommand, argument) orelse {
                    const path: ?[]const u8 = findExecutableFromPATH(io, path_env, argument) catch null;

                    if (path) |p| {
                        try stdout.print("{s} is {s}/{s}\n", .{ argument, p, argument });
                    } else {
                        try stdout.print("{s}: not found\n", .{argument});
                    }

                    continue;
                };
                // If string to enum passes, means it is a builtin command
                try stdout.print("{s} is a shell builtin\n", .{argument});
            },
            .pwd => {
                var buffer2: [std.Io.Dir.max_path_bytes]u8 = undefined;
                const len = getCurrentWorkingDir(io, &buffer2);
                if (len) |length| {
                    try stdout.print("{s}\n", .{buffer2[0..length]});
                }
            },
            .cd => {
                var requested_path: []const u8 = buffer.pop() orelse continue;
                if (requested_path.len == 1 and std.mem.eql(u8, "~", requested_path)) {
                    requested_path = home_path;
                }
                if (!changeDirectory(io, requested_path)) {
                    try stdout.print("cd: {s}: No such file or directory\n", .{requested_path});
                }
            },
        }
    }
}

fn getCurrentWorkingDir(io: anytype, buffer: *[std.Io.Dir.max_path_bytes]u8) ?usize {
    const len = std.Io.Dir.cwd().realPathFile(io, ".", buffer) catch return null;
    return len;
}

fn changeDirectory(io: anytype, name: []const u8) bool {
    var dir: ?std.Io.Dir = null;
    // TODO: clean this up (not use optional
    if (std.fs.path.isAbsolute(name)) {
        dir = std.Io.Dir.openDirAbsolute(io, name, .{}) catch return false;
    } else {
        dir = std.Io.Dir.cwd().openDir(io, name, .{}) catch return false;
    }
    std.process.setCurrentDir(io, dir.?) catch return false;
    defer dir.?.close(io);
    return true;
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
