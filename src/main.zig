// Quedó terminado, pero falta agregar DB para que se mantengan los datos ya que ahora lo hago desde memoria

const std = @import("std");

const Io = std.Io;
const net = Io.net;
const json = std.json;

const Note = struct {
    id: u32,
    text: []u8,
};

const App = struct {
    allocator: std.mem.Allocator,
    notes: std.ArrayList(Note) = .empty,
    next_id: u32 = 1,

    fn deinit(app: *App) void {
        for (app.notes.items) |note| {
            app.allocator.free(note.text);
        }
        app.notes.deinit(app.allocator);
    }

    fn createNote(app: *App, text: []const u8) !Note {
        const note: Note = .{
            .id = app.next_id,
            .text = try app.allocator.dupe(u8, text),
        };
        app.next_id += 1;
        try app.notes.append(app.allocator, note);
        return note;
    }

    fn findNote(app: *App, id: u32) ?*Note {
        for (app.notes.items) |*note| {
            if (note.id == id) return note;
        }
        return null;
    }

    fn deleteNote(app: *App, id: u32) bool {
        for (app.notes.items, 0..) |note, i| {
            if (note.id == id) {
                app.allocator.free(note.text);
                _ = app.notes.orderedRemove(i);
                return true;
            }
        }
        return false;
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var app: App = .{ .allocator = init.gpa };
    defer app.deinit();

    const address = try net.IpAddress.parse(
        "127.0.0.1",
        6969,
    );
    var server = try address.listen(
        io,
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

fn handleConnection(io: Io, stream: net.Stream, app: *App) void {
    defer stream.close(io);
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
            .GET => listNotes(request, app),
            .POST => createNote(request, app),
            else => respondJson(request, .method_not_allowed, "{\"error\":\"no permitido\"}"),
        };
    }

    if (std.mem.startsWith(u8, path, "/notes")) {
        const id_text = path["/notes/".len..];
        const id = std.fmt.parseInt(u32, id_text, 10) catch {
            return respondJson(request, .bad_request, "{\"error\":\"id de nota inválida\"}");
        };

        return switch (method) {
            .GET => getNote(request, app, id),
            .PUT => updateNote(request, app, id),
            .DELETE => deleteNote(request, app, id),
            else => respondJson(request, .method_not_allowed, "{\"error\":\"no permitido\"}"),
        };
    }
    return respondJson(
        request,
        .not_found,
        "{\"error\":\"no se encontró\"}",
    );
}

fn listNotes(request: *std.http.Server.Request, app: *App) !void {
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(app.allocator);

    try body.print(app.allocator, "{f}", .{json.fmt(app.notes.items, .{})});
    try respondJson(request, .ok, body.items);
}

fn getNote(request: *std.http.Server.Request, app: *App, id: u32) !void {
    const note = app.findNote(id) orelse {
        return respondJson(
            request,
            .not_found,
            "{\"error\":\"Nota no encontrada\"}",
        );
    };
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(app.allocator);

    try body.print(app.allocator, "{f}", .{json.fmt(note.*, .{})});
    try respondJson(request, .ok, body.items);
}

fn createNote(request: *std.http.Server.Request, app: *App) !void {
    const text = try readBody(request, app.allocator);
    defer app.allocator.free(text);

    if (text.len == 0) {
        return respondJson(
            request,
            .bad_request,
            "{\"error\":\"Cuerpo de la request está vacio\"}",
        );
    }

    const note = try app.createNote(text);

    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(app.allocator);

    try body.print(app.allocator, "{f}", .{json.fmt(note, .{})});
    try respondJson(request, .created, body.items);
}

fn updateNote(request: *std.http.Server.Request, app: *App, id: u32) !void {
    const note = app.findNote(id) orelse {
        return respondJson(
            request,
            .not_found,
            "{\"error\":\"Nota no encontrada\"}",
        );
    };
    const text = try readBody(request, app.allocator);
    defer app.allocator.free(text);

    if (text.len == 0) {
        return respondJson(
            request,
            .bad_request,
            "{\"error\":\"Cuerpo de la request está vacio\"}",
        );
    }

    app.allocator.free(note.text);
    note.text = try app.allocator.dupe(u8, text);

    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(app.allocator);

    try body.print(app.allocator, "{f}", .{json.fmt(note.*, .{})});
    try respondJson(request, .ok, body.items);
}

fn deleteNote(request: *std.http.Server.Request, app: *App, id: u32) !void {
    if (!app.deleteNote(id)) {
        return respondJson(
            request,
            .not_found,
            "{\"error\":\"Nota no encontrada\"}",
        );
    }

    try respondJson(request, .ok, "{\"deleted\":true}");
}

fn readBody(request: *std.http.Server.Request, allocator: std.mem.Allocator) ![]u8 {
    const length = request.head.content_length orelse return allocator.dupe(u8, "");
    if (length > 1024) {
        return error.BodyTooLarge;
    }

    var body_buffer: [1024]u8 = undefined;
    var reader = try request.readerExpectContinue(&body_buffer);
    return reader.readAlloc(allocator, @intCast(length));
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
