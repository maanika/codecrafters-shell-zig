const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;

const command_parser = @import("command.zig");

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

    //TODO: can I use a faster allocator in release mode?
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer assert(debug_allocator.deinit() == .ok);
    const gpa = debug_allocator.allocator();

    const path_env = try init.minimal.environ.getAlloc(gpa, "PATH");
    defer gpa.free(path_env);

    const home_path = try init.minimal.environ.getAlloc(gpa, "HOME");
    defer gpa.free(home_path);

    while (true) {
        // Use arena allocator within loop, no need to call free,
        // cleans itself with defer after every iteration/command.
        // TODO: Use page allocator in release mode.
        var arena_allocator: std.heap.ArenaAllocator = .init(gpa);
        defer arena_allocator.deinit();
        const arena = arena_allocator.allocator();

        try stdout.print("$ ", .{});

        const input: ?[]u8 = try stdin.interface.takeDelimiter('\n') orelse break;
        if (input.?.len == 0) continue;

        const args: [][]const u8 = try command_parser.parseCommandLine(arena, input.?);
        if (args.len == 0) continue;

        const command = args[0];

        // check for redirection
        // Redirections needs to be GLOBAL work for all commands
        // TODO: Need to think of abrstrating printing and redirecting 
        var redirect: bool = false;
        var redirect_index: usize = args.len;
        for (args, 0..args.len) |arg, index| {
            if ((std.mem.eql(u8, arg, ">")) or std.mem.eql(u8, arg, "1>")) {
                redirect_index = if (index + 1 < args.len) index else break;
                redirect = true;
            }
        }

        // Check if command is an builtin command
        const command_enum = std.meta.stringToEnum(BuiltInCommand, command) orelse {
            const path: ?[]const u8 = findExecutableFromPATH(io, path_env, command) catch null;
            // Thinking ...
            // TODO: we cannot pass the full args here, because it may have a redirect
            // we need to pass upto a redirect and then execute the redirect
            // should we change the command args return to include a redirect flag?
            // can we split the args into two before and after redirect (0> or >) ?
            if (path) |_| {
                const result = std.process.run(arena, io, .{ .argv = args[0..redirect_index]}) catch {
                    continue;
                };
                // if we have a stdout and it is a redirect we sent it to a file
                // create file if not existsing , else overwrite existing file
                try stdout.print("{s}", .{result.stdout});
                // > or 1> only redirects stdout so we can still print stderr
                try stdout.print("{s}", .{result.stderr});
            } else {
                try stdout.print("{s}: command not found\n", .{input.?});
            }
            continue;
        };

        switch (command_enum) {
            .exit => {
                return;
            },
            .echo => {
                for (1..args.len) |index| {
                    try stdout.print("{s}", .{args[index]});
                    if (index < args.len - 1) {
                        try stdout.print(" ", .{});
                    }
                }
                try stdout.print("\n", .{});
            },
            .type => {
                const argument: []const u8 = args[1];
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
                if (args.len < 2) continue;
                var requested_path: []const u8 = args[1];
                if (std.mem.eql(u8, "~", requested_path)) {
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
    // TODO: clean this up (not use optional)
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
