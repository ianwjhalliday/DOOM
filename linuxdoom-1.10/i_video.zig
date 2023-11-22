const c = @cImport({
    @cDefine("GLFW_INCLUDE_GLCOREARB", {});
    if (builtin.target.isDarwin()) {
        @cDefine("GL_SILENCE_DEPRECATION", {});
    }
    @cInclude("GLFW/glfw3.h");
    @cInclude("signal.h");
});

const builtin = @import("builtin");
const std = @import("std");
const D_PostEvent = @import("d_main.zig").D_PostEvent;
const Event = @import("d_main.zig").Event;
const I_Quit = @import("i_system.zig").I_Quit;
const doomdef = @import("doomdef.zig");
const v_video = @import("v_video.zig");
const SCREENWIDTH = doomdef.SCREENWIDTH;
const SCREENHEIGHT = doomdef.SCREENHEIGHT;

const screenVertexShaderSource = [1][*]const u8{
    \\#version 330 core
    \\layout (location = 0) in vec4 vertex;
    \\
    \\out vec2 TexCoords;
    \\
    \\uniform mat4 projection;
    \\
    \\void main()
    \\{
    \\   TexCoords = vertex.zw;
    \\   gl_Position = projection * vec4(vertex.xy, 0.0, 1.0);
    \\}
};

const screenFragmentShaderSource = [1][*]const u8{
    \\#version 330 core
    \\in vec2 TexCoords;
    \\out vec4 color;
    \\
    \\uniform usampler2D screen;
    \\uniform sampler1D palette;
    \\
    \\void main()
    \\{
    \\   uint paletteIndex = texture(screen, TexCoords).r;
    \\   color = texelFetch(palette, int(paletteIndex), 0);
    \\}
};

var shaderProgram: c.GLuint = undefined;

const projectionMatrix = [_]f32{
    2.0, 0.0, 0.0, -1.0,
    0.0, -2.0, 0.0, 1.0,
    0.0, 0.0, 0.5, 0.0,
    0.0, 0.0, 0.0, 1.0,
};

var screenTexture: c.GLuint = undefined;
var paletteTexture: c.GLuint = undefined;
var screenQuadVAO: c.GLuint = undefined;

var mainWindow: ?*c.GLFWwindow = undefined;

const GLFWCallback = struct {
    pub fn Error(err: c_int, description: [*c]const u8) callconv(.C) void {
        const stderr = std.io.getStdErr().writer();
        stderr.print("I_GLFWErrorCallback: {} {s}\n", .{err, description}) catch {};
    }

    pub fn Key(window: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
        _ = mods;
        _ = scancode;
        _ = window;
        const doom_event = Event{
            .type = switch (action) {
                c.GLFW_PRESS, c.GLFW_REPEAT => .KeyDown,
                else => .KeyUp,
            },
            .data1 = translateKey(key),
            .data2 = 0,
            .data3 = 0,
        };

        D_PostEvent(&doom_event);
    }

    pub fn MouseButton(window: ?*c.GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(.C) void {
        _ = mods;
        _ = action;
        _ = button;
        const mb_left: c_int = if (c.glfwGetMouseButton(window, c.GLFW_MOUSE_BUTTON_LEFT) == c.GLFW_PRESS) 1 else 0;
        const mb_right: c_int = if (c.glfwGetMouseButton(window, c.GLFW_MOUSE_BUTTON_RIGHT) == c.GLFW_PRESS) 2 else 0;
        const mb_middle: c_int = if (c.glfwGetMouseButton(window, c.GLFW_MOUSE_BUTTON_MIDDLE) == c.GLFW_PRESS) 4 else 0;

        const doom_event = Event{
            .type = .Mouse,
            .data1 = mb_left | mb_right | mb_middle,
            .data2 = 0,
            .data3 = 0,
        };

        D_PostEvent(&doom_event);
    }

    pub var validLastCursorPos = false;
    var last_x: f64 = 0;
    var last_y: f64 = 0;

    pub fn CursorPosition(window: ?*c.GLFWwindow, xpos: f64, ypos: f64) callconv(.C) void {
        const MOUSE_SENSITIVITY_FACTOR = 4.0;

        const dx = xpos - last_x;
        const dy = ypos - last_y;

        last_x = xpos;
        last_y = ypos;

        if (!validLastCursorPos) {
            validLastCursorPos = true;
            return; // skip this dx, dy because it is bogus
        }

        const mb_left: c_int = if (c.glfwGetMouseButton(window, c.GLFW_MOUSE_BUTTON_LEFT) == c.GLFW_PRESS) 1 else 0;
        const mb_right: c_int = if (c.glfwGetMouseButton(window, c.GLFW_MOUSE_BUTTON_RIGHT) == c.GLFW_PRESS) 2 else 0;
        const mb_middle: c_int = if (c.glfwGetMouseButton(window, c.GLFW_MOUSE_BUTTON_MIDDLE) == c.GLFW_PRESS) 4 else 0;

        const doom_event = Event{
            .type = .Mouse,
            .data1 = mb_left | mb_right | mb_middle,
            .data2 = @intFromFloat(dx * MOUSE_SENSITIVITY_FACTOR),
            .data3 = @intFromFloat(-dy * MOUSE_SENSITIVITY_FACTOR),
        };

        D_PostEvent(&doom_event);
    }
};

fn sigint_handler(_: c_int) callconv(.C) void {
    I_Quit();
}

pub fn I_InitGraphics() void {
    const stderr = std.io.getStdErr().writer();
    stderr.print("I_InitGraphics\n", .{}) catch {};

    // TODO: SIGINT handler should be somewhere else since not specific to graphics.
    _ = c.signal(c.SIGINT, &sigint_handler);

    if (c.glfwInit() == c.GLFW_FALSE) {
        stderr.print("I_InitGraphics: Could not initialize GLFW\n", .{}) catch {};
        I_Quit();
    }

    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);

    if (builtin.target.isDarwin()) {
        c.glfwWindowHint(c.GLFW_OPENGL_FORWARD_COMPAT, c.GL_TRUE);
    }

    _ = c.glfwSetErrorCallback(&GLFWCallback.Error);

    const window = c.glfwCreateWindow(3 * SCREENWIDTH, 3 * SCREENWIDTH * 3 / 4, "Doom", null, null);
    if (window == null) {
        stderr.print("I_InitGraphics: Could not create window\n", .{}) catch {};
        c.glfwTerminate();
        I_Quit();
    }
    mainWindow = window;

    c.glfwSetWindowSizeLimits(window, SCREENWIDTH, SCREENWIDTH * 3 / 4, c.GLFW_DONT_CARE, c.GLFW_DONT_CARE);
    c.glfwSetWindowAspectRatio(window, 4, 3);
    c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);

    _ = c.glfwSetKeyCallback(window, &GLFWCallback.Key);
    _ = c.glfwSetMouseButtonCallback(window, &GLFWCallback.MouseButton);
    _ = c.glfwSetCursorPosCallback(window, &GLFWCallback.CursorPosition);

    c.glfwMakeContextCurrent(window);


    // Load and compile shaders
    const vertexShader = c.glCreateShader(c.GL_VERTEX_SHADER);
    c.glShaderSource(vertexShader, 1, &screenVertexShaderSource, null);
    c.glCompileShader(vertexShader);

    var success: c.GLint = undefined;
    var infoLog: [511:0]u8 = undefined;
    c.glGetShaderiv(vertexShader, c.GL_COMPILE_STATUS, &success);
    if (success == c.GL_FALSE) {
        c.glGetShaderInfoLog(vertexShader, 512, null, &infoLog);
        stderr.print("I_InitGraphics: Failed to compile vertex shader\n\t{s}\n", .{infoLog}) catch {};
        c.glfwTerminate();
        I_Quit();
    }

    const fragmentShader = c.glCreateShader(c.GL_FRAGMENT_SHADER);
    c.glShaderSource(fragmentShader, 1, &screenFragmentShaderSource, null);
    c.glCompileShader(fragmentShader);

    c.glGetShaderiv(fragmentShader, c.GL_COMPILE_STATUS, &success);
    if (success == c.GL_FALSE) {
        c.glGetShaderInfoLog(fragmentShader, 512, null, &infoLog);
        stderr.print("I_InitGraphics: Failed to compile fragment shader\n\t{s}\n", .{infoLog}) catch {};
        c.glfwTerminate();
        I_Quit();
    }

    shaderProgram = c.glCreateProgram();
    c.glAttachShader(shaderProgram, vertexShader);
    c.glAttachShader(shaderProgram, fragmentShader);
    c.glLinkProgram(shaderProgram);

    c.glGetProgramiv(shaderProgram, c.GL_LINK_STATUS, &success);
    if (success == c.GL_FALSE) {
        c.glGetProgramInfoLog(shaderProgram, 512, null, &infoLog);
        stderr.print("I_InitGraphics: Failed to link shader program\n\t{s}\n", .{infoLog}) catch {};
        c.glfwTerminate();
        I_Quit();
    }

    c.glDeleteShader(vertexShader);
    c.glDeleteShader(fragmentShader);

    // Set up screen quad for rendering screen texture to ortho projected quad
    var VBO: c.GLuint = undefined;
    const vertices = [_]f32{
        // pos      // tex
        0.0, 1.0, 0.0, 1.0,
        1.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 0.0, 

        0.0, 1.0, 0.0, 1.0,
        1.0, 1.0, 1.0, 1.0,
        1.0, 0.0, 1.0, 0.0,
    };

    c.glGenVertexArrays(1, &screenQuadVAO);
    c.glGenBuffers(1, &VBO);

    c.glBindBuffer(c.GL_ARRAY_BUFFER, VBO);
    c.glBufferData(c.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), &vertices, c.GL_STATIC_DRAW);

    c.glBindVertexArray(screenQuadVAO);
    c.glEnableVertexAttribArray(0);
    c.glVertexAttribPointer(0, 4, c.GL_FLOAT, c.GL_FALSE, 4 * @sizeOf(f32), null);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
    c.glBindVertexArray(0);

    // Set up screen and palette textures
    c.glGenTextures(1, &screenTexture);
    c.glBindTexture(c.GL_TEXTURE_2D, screenTexture);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);

    c.glGenTextures(1, &paletteTexture);
    c.glBindTexture(c.GL_TEXTURE_1D, paletteTexture);
    c.glTexParameteri(c.GL_TEXTURE_1D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
    c.glTexParameteri(c.GL_TEXTURE_1D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);

    // Shader uses screen as texture 0 and palette as texture 1
    c.glUseProgram(shaderProgram);
    c.glUniform1i(c.glGetUniformLocation(shaderProgram, "screen"), 0);
    c.glUniform1i(c.glGetUniformLocation(shaderProgram, "palette"), 1);
    c.glUniformMatrix4fv(c.glGetUniformLocation(shaderProgram, "projection"), 1, c.GL_TRUE, &projectionMatrix);
}

pub fn I_ShutdownGraphics() void {
    c.glfwTerminate();
}

pub export fn I_PauseMouseCapture() void {
    c.glfwSetInputMode(mainWindow, c.GLFW_CURSOR, c.GLFW_CURSOR_NORMAL);
    _ = c.glfwSetMouseButtonCallback(mainWindow, null);
    _ = c.glfwSetCursorPosCallback(mainWindow, null);
}

pub export fn I_ResumeMouseCapture() void {
    GLFWCallback.validLastCursorPos = false;
    c.glfwSetInputMode(mainWindow, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);
    _ = c.glfwSetMouseButtonCallback(mainWindow, GLFWCallback.MouseButton);
    _ = c.glfwSetCursorPosCallback(mainWindow, GLFWCallback.CursorPosition);
}


//
// I_StartFrame
//
pub fn I_StartFrame() void {
    // er?
}

//
// I_StartTic
//
pub fn I_StartTic() void {
    if (mainWindow == null) {
        return;
    }

    if (c.glfwWindowShouldClose(mainWindow) == c.GLFW_TRUE) {
        I_Quit();
    }

    c.glfwPollEvents();
}

//
// I_UpdateNoBlit
//
pub fn I_UpdateNoBlit() void {
    // what is this?
}

//
// I_FinishUpdate
//
pub fn I_FinishUpdate() void {
    c.glUseProgram(shaderProgram);

    c.glActiveTexture(c.GL_TEXTURE0);
    c.glBindTexture(c.GL_TEXTURE_2D, screenTexture);
    c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RED, SCREENWIDTH, SCREENHEIGHT, 0, c.GL_RED, c.GL_UNSIGNED_BYTE, v_video.screens[0]);
    c.glActiveTexture(c.GL_TEXTURE1);
    c.glBindTexture(c.GL_TEXTURE_1D, paletteTexture);

    c.glBindVertexArray(screenQuadVAO);
    c.glDrawArrays(c.GL_TRIANGLES, 0, 6);
    c.glBindVertexArray(0);

    c.glfwSwapBuffers(mainWindow);
}

//
// I_ReadScreen
//
pub export fn I_ReadScreen(scr: [*]u8) void {
    @memcpy(scr, v_video.screens[0][0..SCREENWIDTH*SCREENHEIGHT]);
}

//
// I_SetPalette
//
var palette: [3*256]u8 = undefined;
pub fn I_SetPalette(pal: [*]u8) void {
    var i: usize = 0;
    while (i < 3*256) : (i += 3) {
        palette[i+0] = v_video.gammatable[@intCast(v_video.usegamma)][pal[i+0]];
        palette[i+1] = v_video.gammatable[@intCast(v_video.usegamma)][pal[i+1]];
        palette[i+2] = v_video.gammatable[@intCast(v_video.usegamma)][pal[i+2]];
    }

    c.glBindTexture(c.GL_TEXTURE_1D, paletteTexture);
    c.glTexImage1D(c.GL_TEXTURE_1D, 0, c.GL_RGBA, 256, 0, c.GL_RGB, c.GL_UNSIGNED_BYTE, &palette);
    c.glTexParameteri(c.GL_TEXTURE_1D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
    c.glTexParameteri(c.GL_TEXTURE_1D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
}

fn translateKey(glfw_key: c_int) c_int {
    return switch (glfw_key) {
        // Function keys
        c.GLFW_KEY_ESCAPE => doomdef.KEY_ESCAPE,
        c.GLFW_KEY_ENTER => doomdef.KEY_ENTER,
        c.GLFW_KEY_TAB => doomdef.KEY_TAB,
        c.GLFW_KEY_BACKSPACE => doomdef.KEY_BACKSPACE,
        c.GLFW_KEY_INSERT => 0, // Unsupported key
        c.GLFW_KEY_DELETE => 0, // Unsupported key
        c.GLFW_KEY_RIGHT => doomdef.KEY_RIGHTARROW,
        c.GLFW_KEY_LEFT => doomdef.KEY_LEFTARROW,
        c.GLFW_KEY_DOWN => doomdef.KEY_DOWNARROW,
        c.GLFW_KEY_UP => doomdef.KEY_UPARROW,
        c.GLFW_KEY_PAGE_UP => 0, // Unsupported key
        c.GLFW_KEY_PAGE_DOWN => 0, // Unsupported key
        c.GLFW_KEY_HOME => 0, // Unsupported key
        c.GLFW_KEY_END => 0, // Unsupported key
        c.GLFW_KEY_CAPS_LOCK => 0, // Unsupported key
        c.GLFW_KEY_SCROLL_LOCK => 0, // Unsupported key
        c.GLFW_KEY_NUM_LOCK => 0, // Unsupported key
        c.GLFW_KEY_PRINT_SCREEN => 0, // Unsupported key
        c.GLFW_KEY_PAUSE => doomdef.KEY_PAUSE,
        c.GLFW_KEY_F1 => doomdef.KEY_F1,
        c.GLFW_KEY_F2 => doomdef.KEY_F2,
        c.GLFW_KEY_F3 => doomdef.KEY_F3,
        c.GLFW_KEY_F4 => doomdef.KEY_F4,
        c.GLFW_KEY_F5 => doomdef.KEY_F5,
        c.GLFW_KEY_F6 => doomdef.KEY_F6,
        c.GLFW_KEY_F7 => doomdef.KEY_F7,
        c.GLFW_KEY_F8 => doomdef.KEY_F8,
        c.GLFW_KEY_F9 => doomdef.KEY_F9,
        c.GLFW_KEY_F10 => doomdef.KEY_F10,
        c.GLFW_KEY_F11 => doomdef.KEY_F11,
        c.GLFW_KEY_F12 => doomdef.KEY_F12,
        c.GLFW_KEY_F13 => 0, // Unsupported key
        c.GLFW_KEY_F14 => 0, // Unsupported key
        c.GLFW_KEY_F15 => 0, // Unsupported key
        c.GLFW_KEY_F16 => 0, // Unsupported key
        c.GLFW_KEY_F17 => 0, // Unsupported key
        c.GLFW_KEY_F18 => 0, // Unsupported key
        c.GLFW_KEY_F19 => 0, // Unsupported key
        c.GLFW_KEY_F20 => 0, // Unsupported key
        c.GLFW_KEY_F21 => 0, // Unsupported key
        c.GLFW_KEY_F22 => 0, // Unsupported key
        c.GLFW_KEY_F23 => 0, // Unsupported key
        c.GLFW_KEY_F24 => 0, // Unsupported key
        c.GLFW_KEY_F25 => 0, // Unsupported key
        c.GLFW_KEY_KP_0 => '0',
        c.GLFW_KEY_KP_1 => '1',
        c.GLFW_KEY_KP_2 => '2',
        c.GLFW_KEY_KP_3 => '3',
        c.GLFW_KEY_KP_4 => '4',
        c.GLFW_KEY_KP_5 => '5',
        c.GLFW_KEY_KP_6 => '6',
        c.GLFW_KEY_KP_7 => '7',
        c.GLFW_KEY_KP_8 => '8',
        c.GLFW_KEY_KP_9 => '9',
        c.GLFW_KEY_KP_DECIMAL => '.',
        c.GLFW_KEY_KP_DIVIDE => '/',
        c.GLFW_KEY_KP_MULTIPLY => '*',
        c.GLFW_KEY_KP_SUBTRACT => doomdef.KEY_MINUS,
        c.GLFW_KEY_KP_ADD => '+',
        c.GLFW_KEY_KP_ENTER => '\n',
        c.GLFW_KEY_KP_EQUAL => doomdef.KEY_EQUALS,
        c.GLFW_KEY_LEFT_SHIFT => doomdef.KEY_RSHIFT, // Doom uses right shift key code for both shifts
        c.GLFW_KEY_LEFT_CONTROL => doomdef.KEY_RCTRL, // Doom uses right control key code for both controls
        c.GLFW_KEY_LEFT_ALT => doomdef.KEY_RALT, // Doom uses right alt key code for both alts
        c.GLFW_KEY_LEFT_SUPER => 0, // Unsupported key
        c.GLFW_KEY_RIGHT_SHIFT => doomdef.KEY_RSHIFT,
        c.GLFW_KEY_RIGHT_CONTROL => doomdef.KEY_RCTRL,
        c.GLFW_KEY_RIGHT_ALT => doomdef.KEY_LALT,
        c.GLFW_KEY_RIGHT_SUPER => 0, // Unsupported key
        c.GLFW_KEY_MENU => 0, // Unsupported key

        // Printable keys -- Doom uses the same value
        c.GLFW_KEY_SPACE,
        c.GLFW_KEY_APOSTROPHE,
        c.GLFW_KEY_COMMA,
        c.GLFW_KEY_MINUS,
        c.GLFW_KEY_PERIOD,
        c.GLFW_KEY_SLASH,
        c.GLFW_KEY_0,
        c.GLFW_KEY_1,
        c.GLFW_KEY_2,
        c.GLFW_KEY_3,
        c.GLFW_KEY_4,
        c.GLFW_KEY_5,
        c.GLFW_KEY_6,
        c.GLFW_KEY_7,
        c.GLFW_KEY_8,
        c.GLFW_KEY_9,
        c.GLFW_KEY_SEMICOLON,
        c.GLFW_KEY_EQUAL,
        c.GLFW_KEY_A,
        c.GLFW_KEY_B,
        c.GLFW_KEY_C,
        c.GLFW_KEY_D,
        c.GLFW_KEY_E,
        c.GLFW_KEY_F,
        c.GLFW_KEY_G,
        c.GLFW_KEY_H,
        c.GLFW_KEY_I,
        c.GLFW_KEY_J,
        c.GLFW_KEY_K,
        c.GLFW_KEY_L,
        c.GLFW_KEY_M,
        c.GLFW_KEY_N,
        c.GLFW_KEY_O,
        c.GLFW_KEY_P,
        c.GLFW_KEY_Q,
        c.GLFW_KEY_R,
        c.GLFW_KEY_S,
        c.GLFW_KEY_T,
        c.GLFW_KEY_U,
        c.GLFW_KEY_V,
        c.GLFW_KEY_W,
        c.GLFW_KEY_X,
        c.GLFW_KEY_Y,
        c.GLFW_KEY_Z,
        c.GLFW_KEY_LEFT_BRACKET,
        c.GLFW_KEY_BACKSLASH,
        c.GLFW_KEY_RIGHT_BRACKET,
        c.GLFW_KEY_GRAVE_ACCENT,
        c.GLFW_KEY_WORLD_1,
        c.GLFW_KEY_WORLD_2,
            => std.ascii.toLower(@intCast(glfw_key)),

        else => 0, // Unknown or unsupported key
    };
}
