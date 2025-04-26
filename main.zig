const std = @import("std");

// ----- C import: GLFW + OpenGL prototypes -----
const c = @cImport({
    @cDefine("GL_GLEXT_PROTOTYPES", "1");
    @cInclude("GLFW/glfw3.h");
    @cInclude("GL/gl.h");
});

const Allocator = std.mem.Allocator;
const math = std.math;
const print = std.debug.print;
const assert = std.debug.assert;

// ---------- Linear algebra ----------
const Vec4 = struct {
    data: [4]f32,
    fn dot(a: Vec4, b: Vec4) f32 {
        var acc: f32 = 0;
        inline for (0..4) |i| acc += a.data[i] * b.data[i];
        return acc;
    }
};

// Row Major
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

    fn rot_x(theta: f32) Mat4 {
        const cs = math.cos(theta);
        const sn = math.sin(theta);
        return .{ .data = .{
            1, 0,  0,   0,
            0, cs, -sn, 0,
            0, sn, cs,  0,
            0, 0,  0,   1,
        } };
    }

    fn rot_y(theta: f32) Mat4 {
        const cs = math.cos(theta);
        const sn = math.sin(theta);
        return .{ .data = .{
            cs, 0, -sn, 0,
            0,  1, 0,   0,
            sn, 0, cs,  0,
            0,  0, 0,   1,
        } };
    }

    fn rot_z(theta: f32) Mat4 {
        const cs = math.cos(theta);
        const sn = math.sin(theta);
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

fn compile_shader(kind: c.GLenum, source: [:0]const u8, alloc: Allocator) !c.GLuint {
    const sh = c.glCreateShader(kind);
    const c_source: [*c]const u8 = source.ptr;
    const source_array = [_][*c]const u8{c_source};
    c.glShaderSource(sh, 1, &source_array, null);
    c.glCompileShader(sh);

    var status: c.GLint = 0;
    c.glGetShaderiv(sh, c.GL_COMPILE_STATUS, &status);
    if (status == 0) {
        var log_length: c.GLsizei = -1;
        c.glGetShaderiv(sh, c.GL_INFO_LOG_LENGTH, &log_length);

        assert(log_length >= 0);
        const log_buf: []u8 = try alloc.alloc(u8, @intCast(log_length));
        defer alloc.free(log_buf);

        var len: c.GLsizei = -1;
        c.glGetShaderInfoLog(sh, @intCast(log_buf.len), &len, log_buf.ptr);

        print("Shader compilation failed:\n\n    {s}\n", .{log_buf});
        return error.ShaderCompileFailed;
    }
    return sh;
}

fn link_prog(prog: c.GLuint, alloc: Allocator) !void {
    c.glLinkProgram(prog);
    var status: c.GLint = 0;
    c.glGetProgramiv(prog, c.GL_LINK_STATUS, &status);
    if (status == 0) {
        var log_length: c.GLsizei = -1;
        c.glGetProgramiv(prog, c.GL_INFO_LOG_LENGTH, &log_length);

        assert(log_length >= 0);
        const log_buf: []u8 = try alloc.alloc(u8, @intCast(log_length));
        defer alloc.free(log_buf);

        var len: c.GLsizei = -1;
        c.glGetProgramInfoLog(prog, @intCast(log_buf.len), &len, log_buf.ptr);

        print("error linking shader:\n\n    {s}\n", .{log_buf});
        return error.GlProgLinkFailed;
    }
}

const Node = extern struct {
    position: [3]f32,
    rotation: [4]f32,
    scale: [3]f32,
    parent: u32,
};

const Model = struct {
    vao: c.GLuint,
    positions_vbo: c.GLuint,
    normals_vbo: c.GLuint,
    indices_ebo: c.GLuint,
    num_vertices: usize,
    num_indices: usize,

    fn load() !Model {
        const MAX_BIN_FILE_SIZE = 50 * 1024;
        var buf: [MAX_BIN_FILE_SIZE]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);
        const alloc = fba.allocator();

        var vao: c.GLuint = 0;
        c.glGenVertexArrays(1, &vao);
        c.glBindVertexArray(vao);

        var buffer_handles: [3]c.GLuint = undefined;
        c.glCreateBuffers(3, &buffer_handles);
        const positions_vbo, const normals_vbo, const indices_ebo = buffer_handles;

        const ATTR_POS_IDX = 0;
        const ATTR_NORM_IDX = 1;

        // upload vertex data
        const positions = try std.fs.cwd().readFileAlloc(alloc, "positions.bin", buf.len);
        const num_positions = positions.len / (3 * @sizeOf(f32));
        c.glNamedBufferData(positions_vbo, @intCast(positions.len), positions.ptr, c.GL_STATIC_DRAW);
        fba.reset();
        const normals = try std.fs.cwd().readFileAlloc(alloc, "normals.bin", buf.len);
        const num_normals = normals.len / (3 * @sizeOf(f32));
        c.glNamedBufferData(normals_vbo, @intCast(normals.len), normals.ptr, c.GL_STATIC_DRAW);
        fba.reset();
        const indices = try std.fs.cwd().readFileAlloc(alloc, "indices.bin", buf.len);
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

        fba.reset();

        const nodes_data = try std.fs.cwd().readFileAllocOptions(
            alloc,
            "nodes.bin",
            buf.len,
            null,
            @alignOf(Node),
            null,
        );
        if (nodes_data.len % @sizeOf(Node) != 0) return error.InvalidLength;
        const nodes: []Node = std.mem.bytesAsSlice(Node, nodes_data);
        print("{} nodes loaded:\n", .{nodes.len});

        for (nodes) |node| print("{any}\n", .{node});

        fba.reset();

        assert(num_positions == num_normals);
        return Model{
            .vao = vao,
            .positions_vbo = positions_vbo,
            .normals_vbo = normals_vbo,
            .indices_ebo = indices_ebo,
            .num_vertices = num_positions,
            .num_indices = num_indices,
        };
    }

    fn deinit(self: Model) void {
        const buffer_objects = [_]c.GLuint{ self.positions_vbo, self.normals_vbo, self.indices_ebo };
        c.glDeleteBuffers(3, &buffer_objects);
        c.glDeleteVertexArrays(1, &self.vao);
    }
};

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

fn error_callback(code: c_int, desc: [*c]const u8) callconv(.C) void {
    print("GLFW error {}: {s}\n", .{ code, std.mem.span(desc) });
}

fn key_callback(
    window: ?*c.GLFWwindow,
    key: c_int,
    scancode: c_int,
    actions: c_int,
    mods: c_int,
) callconv(.C) void {
    _ = scancode;
    _ = mods;

    switch (actions) {
        c.GLFW_RELEASE => {
            print("keycode {} released\n", .{key});
        },
        c.GLFW_PRESS => {
            switch (key) {
                c.GLFW_KEY_Q => {
                    c.glfwSetWindowShouldClose(window, c.GL_TRUE);
                },
                else => {
                    print("keycode {} pressed\n", .{key});
                },
            }
        },
        c.GLFW_REPEAT => {
            print("keycode {} repeated\n", .{key});
        },
        else => unreachable,
    }
}

const DeltaTimer = struct {
    last_ns: i128,

    fn init() DeltaTimer {
        return .{ .last_ns = std.time.nanoTimestamp() };
    }

    // return time in nanoseconds since init or last lap call
    fn lap_ns(self: *DeltaTimer) i128 {
        const now_ns = std.time.nanoTimestamp();
        const dt_ns = now_ns - self.last_ns;
        self.last_ns = now_ns;
        return dt_ns;
    }

    // return time in seconds since init or last lap call
    fn lap_s(self: *DeltaTimer) f32 {
        const NS_IN_S = 1_000_000_000;
        const dt_ns = self.lap_ns();
        return @as(f32, @floatFromInt(dt_ns)) / NS_IN_S;
    }
};

fn opengl_3d_example() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    _ = c.glfwSetErrorCallback(error_callback);
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

    const model = try Model.load();
    defer model.deinit();

    const prog: c.GLuint = c.glCreateProgram();
    defer c.glDeleteProgram(prog);

    const vs = try compile_shader(c.GL_VERTEX_SHADER, vs_source, alloc);
    const fs = try compile_shader(c.GL_FRAGMENT_SHADER, fs_source, alloc);
    c.glAttachShader(prog, vs);
    c.glAttachShader(prog, fs);
    defer {
        c.glDetachShader(prog, vs);
        c.glDetachShader(prog, fs);
        c.glDeleteShader(vs);
        c.glDeleteShader(fs);
    }

    try link_prog(prog, alloc);

    c.glEnable(c.GL_DEPTH_TEST);

    var state = State.new();

    while (c.glfwWindowShouldClose(window) == 0) {
        const dt: f32 = state.timer.lap_s();
        state.angle =
            math.mod(f32, state.angle + 0.5 * math.pi * dt, 2 * math.pi) catch unreachable;

        draw(window, prog, model, state);

        c.glfwPollEvents();
    }
}

const State = struct {
    timer: DeltaTimer,
    angle: f32,

    fn new() State {
        return .{
            .timer = DeltaTimer.init(),
            .angle = 0,
        };
    }
};

fn draw(window: *c.GLFWwindow, prog: c.GLuint, model: Model, state: State) void {
    var w: c_int = 0;
    var h: c_int = 0;

    c.glfwGetFramebufferSize(window, &w, &h);
    c.glViewport(0, 0, w, h);
    c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

    c.glUseProgram(prog);
    c.glBindVertexArray(model.vao);

    var world = Mat4.translate(0, 0, 0);
    world = Mat4.mul(Mat4.rot_y(state.angle), world);
    world = Mat4.mul(Mat4.translate(0, -1.25, -4), world);
    var proj = Mat4.perspective(0.1, 10);

    c.glUniformMatrix4fv(0, 1, c.GL_TRUE, &world.data);
    c.glUniformMatrix4fv(1, 1, c.GL_TRUE, &proj.data);

    const num_indices: i32 = @intCast(model.num_indices);
    c.glDrawElements(c.GL_TRIANGLES, num_indices, c.GL_UNSIGNED_SHORT, null);

    c.glfwSwapBuffers(window);
}

pub fn main() !void {
    try opengl_3d_example();
}
