// GLFW with the OpenGL core profile header, used by i_video.zig.
#define GLFW_INCLUDE_GLCOREARB
#ifdef __APPLE__
#define GL_SILENCE_DEPRECATION
#endif
#include <GLFW/glfw3.h>
#include <signal.h>
