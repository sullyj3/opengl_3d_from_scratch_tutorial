#define GL_GLEXT_PROTOTYPES
#include <GLFW/glfw3.h>

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <stddef.h>
#include <stdio.h>
#include <math.h>
#include <time.h>

typedef struct Vertex
{
    float pos[3];
    float col[3];
} Vertex;

static const Vertex vertices[3] =
{
    { { -0.6f, -0.4f, 0.0f }, { 1.f, 0.f, 0.f } },
    { {  0.6f, -0.4f, 0.0f }, { 0.f, 1.f, 0.f } },
    { {   0.f,  0.6f, 0.0f }, { 0.f, 0.f, 1.f } }
};

static const char* vertex_shader_text =
"#version 460\n"
"layout(location = 0) in vec3 vCol;\n"
"layout(location = 1) in vec3 vPos;\n"
"layout(location = 0) uniform mat4 txfm;\n"
"out vec3 color;\n"
"void main()\n"
"{\n"
"    gl_Position = txfm * vec4(vPos, 1.0);\n"
"    color = vCol;\n"
"}\n";

static const char* fragment_shader_text =
"#version 460\n"
"in vec3 color;\n"
"out vec4 fragment;\n"
"void main()\n"
"{\n"
"    fragment = vec4(color, 1.0);\n"
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
 
    // NOTE: OpenGL error checks have been omitted for brevity
 
    // Create and bind a Vertex Buffer Object (VBO)
    // variable to hold the handle to the buffer
    GLuint vertex_buffer;
    // create the buffer, have gl write its handle into our variable
    glGenBuffers(1, &vertex_buffer);
    // bind it 
    // (I don't understand in detail what this means, but it
    // represents our intent to use this particular buffer for 
    // vertex data)
    glBindBuffer(GL_ARRAY_BUFFER, vertex_buffer);

    // Copy vertex data to the VBO
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
 
    // Create shaders
    const GLuint vertex_shader = glCreateShader(GL_VERTEX_SHADER);
    glShaderSource(vertex_shader, 1, &vertex_shader_text, NULL);
    glCompileShader(vertex_shader);
 
    const GLuint fragment_shader = glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource(fragment_shader, 1, &fragment_shader_text, NULL);
    glCompileShader(fragment_shader);
 

    const GLuint program = glCreateProgram();
    glAttachShader(program, vertex_shader);
    glAttachShader(program, fragment_shader);
    glLinkProgram(program);
 
    // Create Vertex Array Object (VAO)
    GLuint vertex_array;
    glGenVertexArrays(1, &vertex_array);
    glBindVertexArray(vertex_array);

    // Specify the layout of the vertex data
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE,
                          sizeof(Vertex), (void*) offsetof(Vertex, pos));
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE,
                          sizeof(Vertex), (void*) offsetof(Vertex, col));
 
    // Program specific state
    float angle = 0;
    float tslate_y = 0;

    struct timespec last;
    clock_gettime(CLOCK_MONOTONIC, &last);
    struct timespec now;

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
        glClear(GL_COLOR_BUFFER_BIT);
 
        glUseProgram(program);
        glBindVertexArray(vertex_array);

        struct mat4x4 txfm = mat4x4_translate(0, 1, 0);
        txfm = mat4x4_mul(mat4x4_rot_x(angle), txfm);
        txfm = mat4x4_mul(mat4x4_translate(0,0,-5), txfm);
        txfm = mat4x4_mul(perspective(0.1, 10), txfm);
        glUniformMatrix4fv(0, 1, true, txfm.data);
        glDrawArrays(GL_TRIANGLES, 0, 3);
 
        glfwSwapBuffers(window);
        glfwPollEvents();

        // radians/sec
        const float ROTATION_RATE = 1*M_PI;
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
