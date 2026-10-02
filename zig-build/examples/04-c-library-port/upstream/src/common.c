#include "myclib.h"

const char* myclib_version(void) {
    return MYCLIB_VERSION;
}

int myclib_process(int val) {
#ifdef HAVE_FAST_MATH
    return val * 2;
#else
    return val + 1;
#endif
}
