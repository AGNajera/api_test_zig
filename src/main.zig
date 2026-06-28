const std = @import("std");

const Io = std.Io;
const net = Io.net;
const json = std.json;

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
        route(&request, app) catch |err| {
            std.debug.print("ERROR: algo falló {s}: {t}", .{
                request.head.target,
                err,
            });
        };
    }
}

fn route(request: *std.http.Server.Request, app: *App) !void {
    const method = request.head.method;
    const path = request.head.target;

    if (std.mem.eql(u8, path, "/notes")) {
        // TODO: Hacer el resto de metodos
        // Leer los anteriores TODO´S
        // Después haré un servidor en Go para ver cual es mejor.
        // La IA lo puede escribir, pero que chiste tiene todo en la vida, no?
        return switch (method) {
            else => respondJson(request, .method_not_allowed, "{\"error\":\"no permitido\"}"),
        };
    }

    if (std.mem.startsWith(u8, path, "/notes")) {
        const id_text = path["/notes/".len..];
        const id = std.fmt.parseInt(u32, id_text, 10) catch {
            return respondJson(request, .bad_request, "{\"error\":\"id de nota inválida\"}");
        };

        return switch (method) {
            else => respondJson(request, .method_not_allowed, "{\"error\":\"no permitido\"}"),
        };
    }
    return respondJson(request, .not_found, "{\"error\":\"no se encontró\"}");
}

fn respondJson(
    request: *std.http.Server.Request,
    status: std.http.Status,
    body: []const u8,
) !void {
    try request.respond(body, .{ .status = status, .extra_headers = &.{.{
        .name = "content-type",
        .value = "aplication/json",
    }} });
}
