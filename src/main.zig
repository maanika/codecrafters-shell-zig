const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const File = std.Io.File;
const Dir = std.Io.Dir;
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
    var stdin = File.stdin().readerStreaming(io, &stdin_buffer);

    var stdout_writer = File.stdout().writer(io, &.{});
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

        const parsed_input: [][]const u8 = try command_parser.parseCommandLine(arena, input.?);
        if (parsed_input.len == 0) continue;

        var args: [][]const u8 = parsed_input;
        var redirect_file: ?[]const u8 = null;
        for (parsed_input, 0..parsed_input.len) |arg, index| {
            if ((std.mem.eql(u8, arg, ">")) or std.mem.eql(u8, arg, "1>")) {
                args = parsed_input[0..index];
                redirect_file = if (index + 1 < parsed_input.len) parsed_input[index + 1] else continue;
                break;
            }
        }

        var writer: *std.Io.Writer = @constCast(stdout);
        var output_file: ?File = null;
        if (redirect_file != null) {
            output_file = Dir.createFile(Dir.cwd(), io, redirect_file.?, .{}) catch continue;
            var output_file_writer = output_file.?.writer(io, &.{});
            writer = &output_file_writer.interface;
        }
        defer if (output_file != null) output_file.?.close(io);

        const command = args[0];
        const command_enum = std.meta.stringToEnum(BuiltInCommand, command) orelse {
            const path: ?[]const u8 = findExecutableFromPATH(io, path_env, command) catch null;
            if (path) |_| {
                const result = std.process.run(arena, io, .{ .argv = args }) catch {
                    continue;
                };
                try writer.print("{s}", .{result.stdout});
                try stdout.print("{s}", .{result.stderr});
            } else {
                try stdout.print("{s}: command not found\n", .{input.?});
            }
            continue;
        };

        handleBuiltinCommand(io, command_enum, args, writer, home_path, path_env, stdout) catch {};

        //     switch (command_enum) {
        //         .exit => {
        //             return;
        //         },
        //         .echo => {
        //             for (1..args.len) |index| {
        //                 try writer.print("{s}", .{args[index]});
        //                 if (index < args.len - 1) {
        //                     try writer.print(" ", .{});
        //                 }
        //             }
        //             try writer.print("\n", .{});
        //         },
        //         .type => {
        //             const argument: []const u8 = args[1];
        //             //TODO: use a cleaner API for this
        //             _ = std.meta.stringToEnum(BuiltInCommand, argument) orelse {
        //                 const path: ?[]const u8 = findExecutableFromPATH(io, path_env, argument) catch null;
        //
        //                 if (path) |p| {
        //                     try writer.print("{s} is {s}/{s}\n", .{ argument, p, argument });
        //                 } else {
        //                     try stdout.print("{s}: not found\n", .{argument});
        //                 }
        //
        //                 continue;
        //             };
        //             // If string to enum passes, means it is a builtin command
        //             try writer.print("{s} is a shell builtin\n", .{argument});
        //         },
        //         .pwd => {
        //             var buffer2: [Dir.max_path_bytes]u8 = undefined;
        //             const len = getCurrentWorkingDir(io, &buffer2);
        //             if (len) |length| {
        //                 try writer.print("{s}\n", .{buffer2[0..length]});
        //             }
        //         },
        //         .cd => {
        //             if (args.len < 2) continue;
        //             var requested_path: []const u8 = args[1];
        //             if (std.mem.eql(u8, "~", requested_path)) {
        //                 requested_path = home_path;
        //             }
        //             if (!changeDirectory(io, requested_path)) {
        //                 try stdout.print("cd: {s}: No such file or directory\n", .{requested_path});
        //             }
        //         },
        //     }
    }
}

fn handleBuiltinCommand(io: std.Io, command: BuiltInCommand, args: [][]const u8, writer: *std.Io.Writer, home_path: []const u8, path_env: []const u8, stdout: *std.Io.Writer) !void {
    switch (command) {
        .exit => {
            return;
        },
        .echo => {
            for (1..args.len) |index| {
                try writer.print("{s}", .{args[index]});
                if (index < args.len - 1) {
                    try writer.print(" ", .{});
                }
            }
            try writer.print("\n", .{});
        },
        .type => {
            const argument: []const u8 = args[1];
            //TODO: use a cleaner API for this
            _ = std.meta.stringToEnum(BuiltInCommand, argument) orelse {
                const path: ?[]const u8 = findExecutableFromPATH(io, path_env, argument) catch null;

                if (path) |p| {
                    try writer.print("{s} is {s}/{s}\n", .{ argument, p, argument });
                } else {
                    try stdout.print("{s}: not found\n", .{argument});
                }

                return;
            };
            // If string to enum passes, means it is a builtin command
            try writer.print("{s} is a shell builtin\n", .{argument});
        },
        .pwd => {
            var buffer2: [Dir.max_path_bytes]u8 = undefined;
            const len = getCurrentWorkingDir(io, &buffer2);
            if (len) |length| {
                try writer.print("{s}\n", .{buffer2[0..length]});
            }
        },
        .cd => {
            if (args.len < 2) return;
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

fn getCurrentWorkingDir(io: anytype, buffer: *[Dir.max_path_bytes]u8) ?usize {
    const len = Dir.cwd().realPathFile(io, ".", buffer) catch return null;
    return len;
}

fn changeDirectory(io: anytype, name: []const u8) bool {
    var dir: ?Dir = null;
    // TODO: clean this up (not use optional)
    if (std.fs.path.isAbsolute(name)) {
        dir = Dir.openDirAbsolute(io, name, .{}) catch return false;
    } else {
        dir = Dir.cwd().openDir(io, name, .{}) catch return false;
    }
    std.process.setCurrentDir(io, dir.?) catch return false;
    defer dir.?.close(io);
    return true;
}

fn canExecute(dir: Dir, io: anytype, name: []const u8) bool {
    dir.access(io, name, .{ .execute = true }) catch return false;
    return true;
}

fn findExecutableFromPATH(io: std.Io, path_env: []const u8, find: []const u8) MyErrors![]const u8 {
    const path_sep = if (builtin.os.tag == .windows) ';' else ':';
    var dirs = std.mem.splitScalar(u8, path_env, path_sep);

    while (dirs.next()) |path| {
        var dir = Dir.cwd().openDir(io, path, .{ .iterate = true }) catch continue;
        defer dir.close(io);
        if (canExecute(dir, io, find)) {
            return path;
        }
    }
    return MyErrors.NotFound;
}
