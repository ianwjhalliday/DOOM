// libc headers used by i_system.zig. Kept apart from doom.h because Doom's
// headers define names that collide with libc (e.g. the `close` enum value
// in p_spec.h vs close() in unistd.h).
#include <stdio.h>
#include <unistd.h>
#include <sys/time.h>
