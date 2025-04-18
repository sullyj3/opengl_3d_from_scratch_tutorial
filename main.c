#define GL_GLEXT_PROTOTYPES
#include <GLFW/glfw3.h>

#include <stdbool.h>
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <stddef.h>
#include <stdio.h>
#include <math.h>
#include <time.h>

/*typedef struct Vertex*/
/*{*/
/*    float pos[3];*/
/*    float col[3]; // color*/
/*} Vertex;*/

/*static const Vertex vertices[4] =*/
/*{*/
/*    { { -0.5f, -0.5f, 0.0f }, { 0.f, 0.f, 0.f } },*/
/*    { {  0.5f, -0.5f, 0.0f }, { 1.f, 0.f, 0.f } },*/
/*    { { -0.5f,  0.5f, 0.0f }, { 0.f, 1.f, 0.f } },*/
/*    { {  0.5f,  0.5f, 0.0f }, { 1.f, 1.f, 0.f } },*/
/*};*/
/*static const uint32_t indices[6] = {*/
/*    0,1,2,*/
/*    1,3,2*/
/*};*/

struct buffer {
    char* data;
    size_t len;
};

struct buffer load_file(const char* path, struct buffer* buf) {
    FILE* f = fopen(path, "rb");
    assert(f);
    ssize_t read_len = fread(buf->data, 1, buf->len, f);
    assert(read_len >= 0);
    fclose(f);

    struct buffer ret = {buf->data, read_len};
    buf->data += read_len;
    buf->len -= read_len;
    printf("Read %ld bytes from %s.\n", read_len, path);
    return ret;
}

struct model {
    GLuint vao;
    size_t num_indices;
};

struct model load_model(void) {
    size_t BUFSIZE = 32768;
    char buf_data[BUFSIZE];
    struct buffer buf = {buf_data, BUFSIZE};

    struct buffer positions_buf = load_file("positions.bin", &buf);
    float* positions = (float*)positions_buf.data;
    printf("positions:\n");
    for (size_t i=0; i<positions_buf.len/sizeof(float); i+=3) {
        printf("%f %f %f\n", positions[i], positions[i+1], positions[i+2]); 
    }
    printf("\n");

    struct buffer normals_buf = load_file("normals.bin", &buf);
    float* normals = (float*)normals_buf.data;
    printf("normals:\n");
    for (size_t i=0; i<normals_buf.len/sizeof(float); i+=3) {
        printf("%f %f %f\n", normals[i], normals[i+1], normals[i+2]); 
    }
    printf("\n");

    struct buffer index_buf = load_file("indices.bin", &buf);
    uint16_t* indices = (unsigned short*)index_buf.data;
    printf("indices:\n");
    for (size_t i=0; i<index_buf.len / sizeof(uint16_t); i++) {
        printf("%d\n", indices[i]);
    }

    // Create Vertex Array Object (VAO)
    GLuint vertex_array;
    glGenVertexArrays(1, &vertex_array);
    glBindVertexArray(vertex_array);

    // Create and bind a Vertex Buffer Object (VBO)
    // variable to hold the handle to the buffer
    GLuint position_buffer;
    // create the buffer, have gl write its handle into our variable
    glGenBuffers(1, &position_buffer);
    // bind it 
    // (I don't understand in detail what this means, but it
    // represents our intent to use this particular buffer for 
    // vertex data)
    glBindBuffer(GL_ARRAY_BUFFER, position_buffer);
    // Copy vertex data to the VBO
    glBufferData(GL_ARRAY_BUFFER, positions_buf.len, positions_buf.data, GL_STATIC_DRAW);
 
    // Specify the layout of the vertex data
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 0, (void*) 0);
    // glEnableVertexAttribArray(0);
    // glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE,
    //                       sizeof(Vertex), (void*) offsetof(Vertex, col));

    GLuint normals_buffer;
    glGenBuffers(1, &normals_buffer);
    glBindBuffer(GL_ARRAY_BUFFER, normals_buffer);
    glBufferData(GL_ARRAY_BUFFER, normals_buf.len, normals_buf.data, GL_STATIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 0, (void*) 0);

    // Index buffer
    // element buffer object
    GLuint ebo;
    glGenBuffers(1, &ebo);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, index_buf.len, index_buf.data, GL_STATIC_DRAW);

    glBindVertexArray(0);

    return (struct model) {
        .vao = vertex_array,
        .num_indices = index_buf.len / sizeof(uint16_t)
    };
}

static const char* vertex_shader_text =
"#version 460\n"
"layout(location = 0) in vec3 vNorm;\n"
"layout(location = 1) in vec3 vPos;\n"
"layout(location = 0) uniform mat4 world_txfm;\n"
"layout(location = 1) uniform mat4 viewport_txfm;\n"
"out vec3 norm;\n"
"void main()\n"
"{\n"
"    gl_Position = viewport_txfm * world_txfm * vec4(vPos, 1.0);\n"
"    norm = mat3(world_txfm) * vNorm;\n"
"}\n";

static const char* fragment_shader_text =
"#version 460\n"
"in vec3 norm;\n"
"out vec4 fragment;\n"
"void main()\n"
"{\n"
"    vec3 sun_dir = normalize(vec3(0.0, -1.0, -1.0));\n"
"    float diffuse = max(dot(norm, -sun_dir), 0.0);\n"
"    float ambient = 0.2;\n"
"    float light = ambient + diffuse;\n"
"    fragment = vec4(light * vec3(1.0, 1.0, 1.0), 1.0);\n"
"}\n";

struct vec4 {
    float data[4];
};

float vec4_dot(struct vec4 a, struct vec4 b) {
    float ret = 0;
    for (int i=0; i<4; ++i) {
        ret += a.data[i] * b.data[i];
    }
    return ret;
}

struct mat4x4 {
    float data[16];
};

struct vec4 mat4x4_row(struct mat4x4 a, int row) {
    struct vec4 ret;
    int start = row * 4;
    memcpy(ret.data, a.data + start, 4*sizeof(float));
    return ret;
}

struct vec4 mat4x4_col(struct mat4x4 a, int col) {
    struct vec4 ret;
    for (int i=0; i<4; ++i) {
        ret.data[i] = a.data[i*4 + col];
    }
    return ret;
}

struct mat4x4 mat4x4_rot_z(float angle) {
    float c = cos(angle);
    float s = sin(angle);

    return (struct mat4x4) {{
        c, -s, 0, 0,
        s,  c, 0, 0,
        0,  0, 1, 0,
        0,  0, 0, 1
    }};
}

struct mat4x4 mat4x4_rot_x(float angle) {
    float c = cos(angle);
    float s = sin(angle);

    return (struct mat4x4) {{
        1,  0,  0,  0,
        0,  c, -s,  0,
        0,  s,  c,  0,
        0,  0,  0,  1
    }};
}

struct mat4x4 mat4x4_translate(float x, float y, float z) {
    return (struct mat4x4) {{
        1, 0, 0, x,
        0, 1, 0, y,
        0, 0, 1, z,
        0, 0, 0, 1,
    }};
}

void mat4x4_print(struct mat4x4 mat) {
    for (int i=0; i<4; ++i) {
        for (int j=0; j<4; ++j) {
            printf("%f ", mat.data[i*4 + j]);
        }
        printf("\n");
    }
}

struct mat4x4 mat4x4_mul(struct mat4x4 a, struct mat4x4 b) {
    struct mat4x4 ret;
    for (int i=0; i<16; ++i) {
        int row = i / 4;
        int col = i % 4;

        struct vec4 a_row = mat4x4_row(a, row);
        struct vec4 b_col = mat4x4_col(b, col);

        ret.data[i] = vec4_dot(a_row, b_col);
    }
    return ret;
}

// n: near
// f: far
struct mat4x4 perspective(float n, float f) {
    // (an + b)/n = 0
    // (af + b)/f = 1
    // 
    // an + b = 0
    // -an = b
    //
    // (af - an)/f = 1
    // a(f - n)/f = 1
    // a = f/(f-n)
    //
    // b = -fn / (f - n)
    float a = -f / (f-n);
    float b = -f*n / (f-n);

    return (struct mat4x4) {{
        1, 0,  0, 0,
        0, 1,  0, 0,
        0, 0,  a, b,
        0, 0, -1, 0,
    }};
}

static void error_callback(int error, const char* description)
{
    fprintf(stderr, "Error: %s\n", description);
}

// static void key_callback(GLFWwindow* window, int key, int scancode, int action, int mods)
// {
//     if (key == GLFW_KEY_ESCAPE && action == GLFW_PRESS)
//         glfwSetWindowShouldClose(window, GLFW_TRUE);
// }

static float diff_time(struct timespec last, struct timespec now) {
    float ret = now.tv_sec - last.tv_sec;
    ret += (float)(now.tv_nsec - last.tv_nsec) / 1e9;
    return ret;
}


GLuint compile_shader(GLenum shader_type, const char* shader_text) {
    const GLuint shader = glCreateShader(shader_type);
    glShaderSource(shader, 1, &shader_text, NULL);
    glCompileShader(shader);
    GLint compile_status;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &compile_status);
    if (!compile_status) {
        char buf[4096];
        GLsizei n;
        glGetShaderInfoLog(shader, 4096, &n, buf);
        printf("Shader compilation failed.\n");
        printf("%*s\n", n, buf);
    }
    return shader;
}

int main(void)
{
    glfwSetErrorCallback(error_callback);

    if (!glfwInit())
        exit(EXIT_FAILURE);

    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 6);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

    GLFWwindow* window = glfwCreateWindow(500, 500, "OpenGL Triangle", NULL, NULL);
    if (!window)
    {
        glfwTerminate();
        printf("Exiting.\n");
        exit(EXIT_FAILURE);
    }
 
    glfwMakeContextCurrent(window);
    // enable vsync
    glfwSwapInterval(1);
 
    const struct model model = load_model();
 
    const GLuint vertex_shader = compile_shader(GL_VERTEX_SHADER, vertex_shader_text);
    const GLuint fragment_shader = compile_shader(GL_FRAGMENT_SHADER, fragment_shader_text);

    const GLuint program = glCreateProgram();
    glAttachShader(program, vertex_shader);
    glAttachShader(program, fragment_shader);
    glLinkProgram(program);

 
    // Program specific state
    float angle = 0;
    float tslate_y = 0;

    struct timespec last;
    clock_gettime(CLOCK_MONOTONIC, &last);
    struct timespec now;

    glEnable(GL_DEPTH_TEST);

    while (!glfwWindowShouldClose(window))
    {
        // track time since last iteration
        clock_gettime(CLOCK_MONOTONIC, &now);
        float delta_s = diff_time(last, now);

        // get current window size
        int width, height;
        glfwGetFramebufferSize(window, &width, &height);
        // const float ratio = width / (float) height;
 
        // set viewport 
        glViewport(0, 0, width, height);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
 
        glUseProgram(program);
        glBindVertexArray(model.vao);

        struct mat4x4 world_txfm = mat4x4_translate(0, 1, 0);
        world_txfm = mat4x4_mul(mat4x4_rot_x(angle), world_txfm);
        world_txfm = mat4x4_mul(mat4x4_translate(0,0,-5), world_txfm);
        glUniformMatrix4fv(0, 1, true, world_txfm.data);

	struct mat4x4 viewport_txfm = perspective(0.1, 10);

	glUniformMatrix4fv(1, 1, true, viewport_txfm.data);
        glDrawElements(GL_TRIANGLES, model.num_indices, GL_UNSIGNED_SHORT, 0);
 
        glfwSwapBuffers(window);
        glfwPollEvents();

        // radians/sec
        const float ROTATION_RATE = 0.5*M_PI;
        angle += ROTATION_RATE * delta_s;
        angle = fmodf(angle, 2*M_PI);

        const float UP_SPEED = 0.5;
        tslate_y += UP_SPEED * delta_s;

        last = now;
    }

    glfwDestroyWindow(window);

    glfwTerminate();
    exit(EXIT_SUCCESS);
}
