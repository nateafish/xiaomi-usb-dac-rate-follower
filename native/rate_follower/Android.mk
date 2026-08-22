LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := rate_follower
LOCAL_SRC_FILES := rate_follower.cpp
LOCAL_C_INCLUDES := $(LOCAL_PATH)
LOCAL_CPPFLAGS := -std=c++17 -fno-exceptions -fno-rtti -fvisibility=hidden -fvisibility-inlines-hidden -Wall -Wextra -Werror
LOCAL_LDFLAGS := -Wl,--exclude-libs,ALL
LOCAL_LDLIBS := -llog
LOCAL_STL := c++_static
include $(BUILD_SHARED_LIBRARY)
