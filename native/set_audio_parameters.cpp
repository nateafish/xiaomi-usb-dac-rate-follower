#include <dlfcn.h>
#include <cstdio>

int main(int argc, char** argv) {
    if (argc != 2) {
        std::fprintf(stderr, "usage: %s key=value\n", argv[0]);
        return 64;
    }
    void* utils = dlopen("libutils.so", RTLD_NOW | RTLD_GLOBAL);
    void* client = dlopen("libaudioclient.so", RTLD_NOW | RTLD_GLOBAL);
    if (!utils || !client) {
        std::fprintf(stderr, "dlopen: %s\n", dlerror());
        return 1;
    }
    using StringCtor = void (*)(void*, const char*);
    using StringDtor = void (*)(void*);
    using SetParameters = int (*)(const void*);
    auto ctor = reinterpret_cast<StringCtor>(dlsym(utils, "_ZN7android7String8C1EPKc"));
    auto dtor = reinterpret_cast<StringDtor>(dlsym(utils, "_ZN7android7String8D1Ev"));
    auto set_parameters = reinterpret_cast<SetParameters>(
            dlsym(client, "_ZN7android11AudioSystem13setParametersERKNS_7String8E"));
    if (!ctor || !dtor || !set_parameters) {
        std::fprintf(stderr, "dlsym: %s\n", dlerror());
        return 2;
    }
    alignas(16) unsigned char value[32]{};
    ctor(value, argv[1]);
    int status = set_parameters(value);
    dtor(value);
    std::printf("status=%d\n", status);
    return status == 0 ? 0 : 3;
}
