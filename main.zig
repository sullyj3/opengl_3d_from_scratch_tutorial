const std = @import("std");

// ----- C import: GLFW + OpenGL prototypes -----
const c = @cImport({
    @cDefine("GL_GLEXT_PROTOTYPES", "1");
    @cInclude("GLFW/glfw3.h");
    @cInclude("GL/gl.h"); // or your OpenGL loader header
});

const Allocator = std.mem.Allocator;

// ---------- Linear algebra ----------
const Vec4 = struct {
    data: [4]f32,
    fn dot(a: Vec4, b: Vec4) f32 {
        var acc: f32 = 0;
        inline for (0..4) |i| acc += a.data[i] * b.data[i];
        return acc;
    }
};

const Mat4 = struct {
    data: [16]f32,
    fn row(self: Mat4, r: usize) Vec4 {
        return .{ .data = self.data[r * 4 ..][0..4].* };
    }
    fn col(self: Mat4, colIdx: usize) Vec4 {
        var v: Vec4 = undefined;
        inline for (0..4) |i| v.data[i] = self.data[i * 4 + colIdx];
        return v;
    }
    fn mul(a: Mat4, b: Mat4) Mat4 {
        var out: Mat4 = undefined;
        inline for (0..16) |i| {
            const rowIdx = i / 4;
            const colIdx = i % 4;
            out.data[i] = Vec4.dot(a.row(rowIdx), b.col(colIdx));
        }
        return out;
    }
    fn perspective(n: f32, f: f32) Mat4 {
        const a = -f / (f - n);
        const b = -f * n / (f - n);
        return .{ .data = .{
            1, 0, 0,  0,
            0, 1, 0,  0,
            0, 0, a,  b,
            0, 0, -1, 0,
        } };
    }
    fn rotX(theta: f32) Mat4 {
        const cs = std.math.cos(theta);
        const sn = std.math.sin(theta);
        return .{ .data = .{
            1, 0,  0,   0,
            0, cs, -sn, 0,
            0, sn, cs,  0,
            0, 0,  0,   1,
        } };
    }
    fn rotY(theta: f32) Mat4 {
        const cs = std.math.cos(theta);
        const sn = std.math.sin(theta);
        return .{ .data = .{
            cs, 0, -sn, 0,
            0,  1, 0,   0,
            sn, 0, cs,  0,
            0,  0, 0,   1,
        } };
    }
    fn rotZ(theta: f32) Mat4 {
        const cs = std.math.cos(theta);
        const sn = std.math.sin(theta);
        return .{ .data = .{
            cs, -sn, 0, 0,
            sn, cs,  0, 0,
            0,  0,   1, 0,
            0,  0,   0, 1,
        } };
    }
    fn translate(x: f32, y: f32, z: f32) Mat4 {
        return .{ .data = .{
            1, 0, 0, x,
            0, 1, 0, y,
            0, 0, 1, z,
            0, 0, 0, 1,
        } };
    }
};

fn compileShader(kind: c.GLenum, source: [:0]const u8) !c.GLuint {
    const sh = c.glCreateShader(kind);
    const c_source: [*c]const u8 = source.ptr;
    const source_array = [_][*c]const u8{c_source};
    c.glShaderSource(sh, 1, &source_array, null);
    c.glCompileShader(sh);

    var status: c.GLint = 0;
    c.glGetShaderiv(sh, c.GL_COMPILE_STATUS, &status);
    if (status == 0) {
        std.debug.print("Shader compilation failed.\n", .{});
        return error.ShaderCompileFailed;
    }
    return sh;
}

const Model = struct { vao: c.GLuint, num_indices: usize };

fn loadModel(allocator: Allocator) !Model {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var vao: c.GLuint = 0;
    c.glGenVertexArrays(1, &vao);
    c.glBindVertexArray(vao);

    var buffer_handles: [3]c.GLuint = undefined;
    c.glCreateBuffers(3, &buffer_handles);
    const positions_vbo, const normals_vbo, const indices_ebo = buffer_handles;

    const ATTR_POS_IDX = 0;
    const ATTR_NORM_IDX = 1;
    const MAX_BIN_FILE_SIZE: usize = 1e6;

    // upload vertex data
    const positions = try std.fs.cwd().readFileAlloc(alloc, "positions.bin", MAX_BIN_FILE_SIZE);
    c.glNamedBufferData(positions_vbo, @intCast(positions.len), positions.ptr, c.GL_STATIC_DRAW);
    _ = arena.reset(.retain_capacity);
    const normals = try std.fs.cwd().readFileAlloc(alloc, "normals.bin", MAX_BIN_FILE_SIZE);
    c.glNamedBufferData(normals_vbo, @intCast(normals.len), normals.ptr, c.GL_STATIC_DRAW);
    _ = arena.reset(.retain_capacity);
    const indices = try std.fs.cwd().readFileAlloc(alloc, "indices.bin", MAX_BIN_FILE_SIZE);
    const num_indices = indices.len / @sizeOf(u16);
    c.glNamedBufferData(indices_ebo, @intCast(indices.len), indices.ptr, c.GL_STATIC_DRAW);

    // Specify vertex attribute layout
    c.glBindBuffer(c.GL_ARRAY_BUFFER, positions_vbo);
    c.glVertexAttribPointer(ATTR_POS_IDX, 3, c.GL_FLOAT, c.GL_FALSE, 0, null);
    c.glEnableVertexAttribArray(ATTR_POS_IDX);

    c.glBindBuffer(c.GL_ARRAY_BUFFER, normals_vbo);
    c.glVertexAttribPointer(ATTR_NORM_IDX, 3, c.GL_FLOAT, c.GL_FALSE, 0, null);
    c.glEnableVertexAttribArray(ATTR_NORM_IDX);

    c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, indices_ebo);

    c.glBindVertexArray(0);
    return Model{ .vao = vao, .num_indices = num_indices };
}

// ---------- Shader sources ----------
const vs_source =
    \\#version 460
    \\layout(location = 0) in vec3 vPos;
    \\layout(location = 1) in vec3 vNorm;
    \\layout(location = 0) uniform mat4 world_txfm;
    \\layout(location = 1) uniform mat4 viewport_txfm;
    \\out vec3 norm;
    \\void main()
    \\{
    \\    gl_Position = viewport_txfm * world_txfm * vec4(vPos, 1.0);
    \\    norm = mat3(world_txfm) * vNorm;
    \\}
;

const fs_source =
    \\#version 460
    \\in vec3 norm;
    \\out vec4 fragment;
    \\void main()
    \\{
    \\    vec3 sun_dir = normalize(vec3(0.0, -1.0, -1.0));
    \\    float diffuse = max(dot(norm, -sun_dir), 0.0);
    \\    float ambient = 0.2;
    \\    fragment = vec4((ambient + diffuse) * vec3(1.0), 1.0);
    \\}
;

fn errorCallback(code: c_int, desc: [*c]const u8) callconv(.C) void {
    std.debug.print("GLFW error {}: {s}\n", .{ code, std.mem.span(desc) });
}

fn key_callback(window: ?*c.GLFWwindow, key: c_int, scancode: c_int, actions: c_int, mods: c_int) callconv(.C) void {
    _ = window;
    _ = scancode;
    _ = mods;

    switch (actions) {
        c.GLFW_RELEASE => {
            std.debug.print("keycode {} released\n", .{key});
        },
        c.GLFW_PRESS => {
            std.debug.print("keycode {} pressed\n", .{key});
        },
        c.GLFW_REPEAT => {
            std.debug.print("keycode {} repeated\n", .{key});
        },
        else => unreachable,
    }
}

fn opengl_3d_example() !void {
    _ = c.glfwSetErrorCallback(errorCallback);
    if (c.glfwInit() == 0) return error.GlfwInitFailed;
    defer c.glfwTerminate();

    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 4);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 6);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);

    const window = c.glfwCreateWindow(500, 500, "OpenGL Zig", null, null) orelse return error.WindowCreationFailed;
    defer c.glfwDestroyWindow(window);

    _ = c.glfwSetKeyCallback(window, key_callback);

    c.glfwMakeContextCurrent(window);
    c.glfwSwapInterval(1);

    const model = try loadModel(std.heap.page_allocator);

    const vs = try compileShader(c.GL_VERTEX_SHADER, vs_source);
    const fs = try compileShader(c.GL_FRAGMENT_SHADER, fs_source);
    const prog = c.glCreateProgram();
    c.glAttachShader(prog, vs);
    c.glAttachShader(prog, fs);
    c.glLinkProgram(prog);

    c.glEnable(c.GL_DEPTH_TEST);

    var last_ns = std.time.nanoTimestamp();
    var angle: f32 = 0;

    while (c.glfwWindowShouldClose(window) == 0) {
        const NS_IN_S = 1e9;
        const now_ns = std.time.nanoTimestamp();
        const dt_ns = now_ns - last_ns;
        const dt = @as(f32, @floatFromInt(dt_ns)) / NS_IN_S;
        last_ns = now_ns;

        var w: c_int = 0;
        var h: c_int = 0;
        c.glfwGetFramebufferSize(window, &w, &h);
        c.glViewport(0, 0, w, h);
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

        c.glUseProgram(prog);
        c.glBindVertexArray(model.vao);

        var world = Mat4.translate(0, 0, 0);
        world = Mat4.mul(Mat4.rotY(angle), world);
        world = Mat4.mul(Mat4.translate(0, -1.25, -4), world);
        var proj = Mat4.perspective(0.1, 10);

        c.glUniformMatrix4fv(0, 1, c.GL_TRUE, &world.data);
        c.glUniformMatrix4fv(1, 1, c.GL_TRUE, &proj.data);

        const num_indices: i32 = @intCast(model.num_indices);
        c.glDrawElements(c.GL_TRIANGLES, num_indices, c.GL_UNSIGNED_SHORT, null);

        c.glfwSwapBuffers(window);
        c.glfwPollEvents();

        angle = std.math.mod(f32, angle + 0.5 * std.math.pi * dt, 2 * std.math.pi) catch unreachable;
    }
}

pub fn main() !void {
    try opengl_3d_example();
}
