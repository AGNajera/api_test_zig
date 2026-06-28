const std = @import("std");

const Io = std.Io;
const net = Io.net;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const address = try net.IpAddress.parse(
        "127.0.0.1",
        6969,
    );
    var server = try address.listen(
        Io,
        .{ .reuse_address = true },
    );
    defer server.deinit(io);

    std.debug.print("Escuchando desde http://127.0.0.1:6969\n", .{});
    while (true) {
        // Esto no va a ser la mejor API del mundo,
        // la que mejor vaya en rendimiento, pero es un comienzo viniendo de
        // Frontend :D
        const stream = try server.accept(io);
        handleConnection(io, stream, &app);
    }
}

fn handleConnection(io: Io, strems: net.Stream, app: *App) void {
    defer strems.close(io);
    var read_buffer: [4096]u8 = undefined;
    var write_buffer: [4096]u8 = undefined;
    var connection_reader = stream.reader(
        io,
        &read_buffer,
    );
    var connection_writer = stream.writer(
        io,
        &write_buffer,
    );

    var server = std.http.Server.init(
        &connection_reader.interface,
        &connection_writer.interface,
    );

    while (server.reader.state == .ready) {
        var request = server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => return,
            else => {
                std.debug.print("ERROR: algo falló en la request {t}\n", .{err});
                return;
            },
        };
        // TODO: Redirigirlo a la request que hagay saber que quiere hacer
        // Escribir app
    }
}
