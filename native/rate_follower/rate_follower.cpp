#include <android/log.h>
#include <jni.h>
#include <cstring>

#include "zygisk.hpp"

namespace {

constexpr const char *kLogTag = "XiaomiUsbRateFollower";
constexpr const char *kAudioTrackClass = "android/media/AudioTrack";
constexpr const char *kNativeSetupSignature =
        "(Ljava/lang/Object;Ljava/lang/Object;[ILjava/lang/Object;III[ILandroid/os/Parcel;"
        "JZILjava/lang/Object;Ljava/lang/String;Ljava/lang/String;)I";

using NativeSetup = jint (*)(JNIEnv *, jobject, jobject, jobject, jintArray, jobject,
                             jint, jint, jint, jintArray, jobject, jlong, jboolean,
                             jint, jobject, jstring, jstring);

NativeSetup gOriginalNativeSetup = nullptr;
char gProcessName[192] = {};
thread_local bool gApplyingPreference = false;

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, kLogTag, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, kLogTag, __VA_ARGS__)

bool clearException(JNIEnv *env, const char *stage) {
    if (!env->ExceptionCheck()) return false;
    env->ExceptionClear();
    LOGW("Java call failed at %s; continuing with the original AudioTrack setup", stage);
    return true;
}

bool isTargetProcess(const char *name) {
    constexpr const char *targets[] = {
            "com.apple.android.music",
            "com.netease.cloudmusic",
    };
    for (const char *target : targets) {
        const size_t length = std::strlen(target);
        if (std::strncmp(name, target, length) == 0 &&
            (name[length] == '\0' || name[length] == ':')) {
            return true;
        }
    }
    return false;
}

bool isPcmEncoding(jint encoding) {
    // AudioFormat: PCM_16BIT=2, PCM_8BIT=3, PCM_FLOAT=4,
    // PCM_24BIT_PACKED=21, PCM_32BIT=22.
    return encoding == 2 || encoding == 3 || encoding == 4 ||
           encoding == 21 || encoding == 22;
}

jobject getAudioManager(JNIEnv *env) {
    jclass activityThread = env->FindClass("android/app/ActivityThread");
    if (clearException(env, "ActivityThread class") || activityThread == nullptr) return nullptr;

    jmethodID currentApplication = env->GetStaticMethodID(
            activityThread, "currentApplication", "()Landroid/app/Application;");
    if (clearException(env, "currentApplication lookup") || currentApplication == nullptr) {
        env->DeleteLocalRef(activityThread);
        return nullptr;
    }

    jobject application = env->CallStaticObjectMethod(activityThread, currentApplication);
    env->DeleteLocalRef(activityThread);
    if (clearException(env, "currentApplication") || application == nullptr) return nullptr;

    jclass contextClass = env->FindClass("android/content/Context");
    jmethodID getSystemService = contextClass == nullptr ? nullptr : env->GetMethodID(
            contextClass, "getSystemService", "(Ljava/lang/String;)Ljava/lang/Object;");
    if (clearException(env, "getSystemService lookup") || getSystemService == nullptr) {
        if (contextClass != nullptr) env->DeleteLocalRef(contextClass);
        env->DeleteLocalRef(application);
        return nullptr;
    }

    jstring audio = env->NewStringUTF("audio");
    jobject manager = env->CallObjectMethod(application, getSystemService, audio);
    env->DeleteLocalRef(audio);
    env->DeleteLocalRef(contextClass);
    env->DeleteLocalRef(application);
    if (clearException(env, "getSystemService(audio)")) return nullptr;
    return manager;
}

jobject findUsbOutputDevice(JNIEnv *env, jobject audioManager) {
    jclass managerClass = env->FindClass("android/media/AudioManager");
    jmethodID getDevices = managerClass == nullptr ? nullptr : env->GetMethodID(
            managerClass, "getDevices", "(I)[Landroid/media/AudioDeviceInfo;");
    if (clearException(env, "AudioManager.getDevices lookup") || getDevices == nullptr) {
        if (managerClass != nullptr) env->DeleteLocalRef(managerClass);
        return nullptr;
    }

    // AudioManager.GET_DEVICES_OUTPUTS = 2.
    auto devices = static_cast<jobjectArray>(env->CallObjectMethod(audioManager, getDevices, 2));
    env->DeleteLocalRef(managerClass);
    if (clearException(env, "AudioManager.getDevices") || devices == nullptr) return nullptr;

    jclass deviceClass = env->FindClass("android/media/AudioDeviceInfo");
    jmethodID getType = deviceClass == nullptr ? nullptr : env->GetMethodID(deviceClass, "getType", "()I");
    jmethodID isSink = deviceClass == nullptr ? nullptr : env->GetMethodID(deviceClass, "isSink", "()Z");
    if (clearException(env, "AudioDeviceInfo lookup") || getType == nullptr || isSink == nullptr) {
        if (deviceClass != nullptr) env->DeleteLocalRef(deviceClass);
        env->DeleteLocalRef(devices);
        return nullptr;
    }

    jobject result = nullptr;
    const jsize count = env->GetArrayLength(devices);
    for (jsize i = 0; i < count; ++i) {
        jobject device = env->GetObjectArrayElement(devices, i);
        const jint type = env->CallIntMethod(device, getType);
        const jboolean sink = env->CallBooleanMethod(device, isSink);
        if (clearException(env, "AudioDeviceInfo query")) {
            env->DeleteLocalRef(device);
            break;
        }
        // USB_DEVICE=11, USB_ACCESSORY=12, USB_HEADSET=22.
        if (sink && (type == 11 || type == 12 || type == 22)) {
            result = device;
            break;
        }
        env->DeleteLocalRef(device);
    }

    env->DeleteLocalRef(deviceClass);
    env->DeleteLocalRef(devices);
    return result;
}

jint getPositionChannelMask(JNIEnv *env, jobject channelMasks) {
    if (channelMasks == nullptr) return 12;  // CHANNEL_OUT_STEREO
    jclass masksClass = env->GetObjectClass(channelMasks);
    jfieldID positionMask = masksClass == nullptr ? nullptr :
            env->GetFieldID(masksClass, "mPositionMask", "I");
    jint value = 0;
    const bool lookupFailed = clearException(env, "ChannelMasks.mPositionMask lookup");
    if (positionMask != nullptr && !lookupFailed) {
        value = env->GetIntField(channelMasks, positionMask);
    } else {
        clearException(env, "ChannelMasks fallback");
    }
    if (masksClass != nullptr) env->DeleteLocalRef(masksClass);
    return value != 0 ? value : 12;
}

jobject buildAudioFormat(JNIEnv *env, jint sampleRate, jint encoding, jint channelMask) {
    jclass builderClass = env->FindClass("android/media/AudioFormat$Builder");
    if (clearException(env, "AudioFormat.Builder class") || builderClass == nullptr) return nullptr;

    jmethodID constructor = env->GetMethodID(builderClass, "<init>", "()V");
    jmethodID setSampleRate = env->GetMethodID(
            builderClass, "setSampleRate", "(I)Landroid/media/AudioFormat$Builder;");
    jmethodID setEncoding = env->GetMethodID(
            builderClass, "setEncoding", "(I)Landroid/media/AudioFormat$Builder;");
    jmethodID setChannelMask = env->GetMethodID(
            builderClass, "setChannelMask", "(I)Landroid/media/AudioFormat$Builder;");
    jmethodID build = env->GetMethodID(
            builderClass, "build", "()Landroid/media/AudioFormat;");
    if (clearException(env, "AudioFormat.Builder methods") || constructor == nullptr ||
        setSampleRate == nullptr || setEncoding == nullptr || setChannelMask == nullptr ||
        build == nullptr) {
        env->DeleteLocalRef(builderClass);
        return nullptr;
    }

    jobject builder = env->NewObject(builderClass, constructor);
    if (clearException(env, "AudioFormat.Builder constructor") || builder == nullptr) {
        env->DeleteLocalRef(builderClass);
        return nullptr;
    }
    env->CallObjectMethod(builder, setSampleRate, sampleRate);
    env->CallObjectMethod(builder, setEncoding, encoding);
    env->CallObjectMethod(builder, setChannelMask, channelMask);
    jobject format = env->CallObjectMethod(builder, build);
    if (clearException(env, "AudioFormat build")) format = nullptr;
    env->DeleteLocalRef(builder);
    env->DeleteLocalRef(builderClass);
    return format;
}

jobject buildBitPerfectMixerAttributes(JNIEnv *env, jobject format) {
    jclass builderClass = env->FindClass("android/media/AudioMixerAttributes$Builder");
    if (clearException(env, "AudioMixerAttributes.Builder class") || builderClass == nullptr) return nullptr;
    jmethodID constructor = env->GetMethodID(
            builderClass, "<init>", "(Landroid/media/AudioFormat;)V");
    jmethodID setBehavior = env->GetMethodID(
            builderClass, "setMixerBehavior", "(I)Landroid/media/AudioMixerAttributes$Builder;");
    jmethodID build = env->GetMethodID(
            builderClass, "build", "()Landroid/media/AudioMixerAttributes;");
    if (clearException(env, "AudioMixerAttributes.Builder methods") || constructor == nullptr ||
        setBehavior == nullptr || build == nullptr) {
        env->DeleteLocalRef(builderClass);
        return nullptr;
    }

    jobject builder = env->NewObject(builderClass, constructor, format);
    if (clearException(env, "AudioMixerAttributes.Builder constructor") || builder == nullptr) {
        env->DeleteLocalRef(builderClass);
        return nullptr;
    }
    // AudioMixerAttributes.MIXER_BEHAVIOR_BIT_PERFECT = 1.
    env->CallObjectMethod(builder, setBehavior, 1);
    jobject attributes = env->CallObjectMethod(builder, build);
    if (clearException(env, "AudioMixerAttributes build")) attributes = nullptr;
    env->DeleteLocalRef(builder);
    env->DeleteLocalRef(builderClass);
    return attributes;
}

jobject buildPreferenceAudioAttributes(JNIEnv *env, jobject sourceAttributes) {
    jclass attributesClass = env->FindClass("android/media/AudioAttributes");
    jmethodID getUsage = attributesClass == nullptr ? nullptr :
            env->GetMethodID(attributesClass, "getUsage", "()I");
    jmethodID getContentType = attributesClass == nullptr ? nullptr :
            env->GetMethodID(attributesClass, "getContentType", "()I");
    if (clearException(env, "AudioAttributes getters") || getUsage == nullptr ||
        getContentType == nullptr) {
        if (attributesClass != nullptr) env->DeleteLocalRef(attributesClass);
        return nullptr;
    }
    const jint usage = env->CallIntMethod(sourceAttributes, getUsage);
    const jint contentType = env->CallIntMethod(sourceAttributes, getContentType);
    env->DeleteLocalRef(attributesClass);
    if (clearException(env, "AudioAttributes read")) return nullptr;

    jclass builderClass = env->FindClass("android/media/AudioAttributes$Builder");
    jmethodID constructor = builderClass == nullptr ? nullptr :
            env->GetMethodID(builderClass, "<init>", "()V");
    jmethodID setUsage = builderClass == nullptr ? nullptr : env->GetMethodID(
            builderClass, "setUsage", "(I)Landroid/media/AudioAttributes$Builder;");
    jmethodID setContentType = builderClass == nullptr ? nullptr : env->GetMethodID(
            builderClass, "setContentType", "(I)Landroid/media/AudioAttributes$Builder;");
    jmethodID build = builderClass == nullptr ? nullptr : env->GetMethodID(
            builderClass, "build", "()Landroid/media/AudioAttributes;");
    if (clearException(env, "AudioAttributes.Builder methods") || constructor == nullptr ||
        setUsage == nullptr || setContentType == nullptr || build == nullptr) {
        if (builderClass != nullptr) env->DeleteLocalRef(builderClass);
        return nullptr;
    }

    jobject builder = env->NewObject(builderClass, constructor);
    if (clearException(env, "AudioAttributes.Builder constructor") || builder == nullptr) {
        env->DeleteLocalRef(builderClass);
        return nullptr;
    }
    env->CallObjectMethod(builder, setUsage, usage);
    env->CallObjectMethod(builder, setContentType, contentType);
    jobject result = env->CallObjectMethod(builder, build);
    if (clearException(env, "preference AudioAttributes build")) result = nullptr;
    env->DeleteLocalRef(builder);
    env->DeleteLocalRef(builderClass);
    return result;
}

bool applyBitPerfectPreference(JNIEnv *env, jobject audioAttributes, jintArray sampleRates,
                               jobject channelMasks, jint encoding, jboolean offloaded) {
    if (audioAttributes == nullptr || sampleRates == nullptr || offloaded || !isPcmEncoding(encoding)) {
        return false;
    }

    jclass attributesClass = env->FindClass("android/media/AudioAttributes");
    jmethodID getUsage = attributesClass == nullptr ? nullptr :
            env->GetMethodID(attributesClass, "getUsage", "()I");
    if (clearException(env, "AudioAttributes.getUsage lookup") || getUsage == nullptr) {
        if (attributesClass != nullptr) env->DeleteLocalRef(attributesClass);
        return false;
    }
    const jint usage = env->CallIntMethod(audioAttributes, getUsage);
    env->DeleteLocalRef(attributesClass);
    if (clearException(env, "AudioAttributes.getUsage") || usage != 1) return false; // USAGE_MEDIA

    if (env->GetArrayLength(sampleRates) < 1) return false;
    jint sampleRate = 0;
    env->GetIntArrayRegion(sampleRates, 0, 1, &sampleRate);
    if (clearException(env, "sample rate read") || sampleRate < 8000 || sampleRate > 768000) {
        return false;
    }

    jobject audioManager = getAudioManager(env);
    if (audioManager == nullptr) return false;
    jobject usbDevice = findUsbOutputDevice(env, audioManager);
    if (usbDevice == nullptr) {
        env->DeleteLocalRef(audioManager);
        return false;
    }

    const jint channelMask = getPositionChannelMask(env, channelMasks);
    // USB Audio exposes integer PCM. Keep the app's source AudioTrack untouched and
    // let AudioFlinger perform its existing float/16/24 -> PCM32 conversion.
    constexpr jint kPcm32Encoding = 22;  // AudioFormat.ENCODING_PCM_32BIT
    jobject preferenceAttributes = buildPreferenceAudioAttributes(env, audioAttributes);
    jobject format = buildAudioFormat(env, sampleRate, kPcm32Encoding, channelMask);
    jobject mixerAttributes = format == nullptr ? nullptr :
            buildBitPerfectMixerAttributes(env, format);
    bool success = false;
    if (preferenceAttributes != nullptr && mixerAttributes != nullptr) {
        jclass managerClass = env->FindClass("android/media/AudioManager");
        jmethodID setPreferred = managerClass == nullptr ? nullptr : env->GetMethodID(
                managerClass, "setPreferredMixerAttributes",
                "(Landroid/media/AudioAttributes;Landroid/media/AudioDeviceInfo;"
                "Landroid/media/AudioMixerAttributes;)Z");
        const bool lookupFailed = clearException(env, "setPreferredMixerAttributes lookup");
        if (setPreferred != nullptr && !lookupFailed) {
            success = env->CallBooleanMethod(
                    audioManager, setPreferred, preferenceAttributes, usbDevice, mixerAttributes);
            if (clearException(env, "setPreferredMixerAttributes")) success = false;
        }
        if (managerClass != nullptr) env->DeleteLocalRef(managerClass);
    }

    LOGI("process=%s rate=%d sourceEncoding=%d outputEncoding=%d channelMask=0x%x preferred=%s",
         gProcessName, sampleRate, encoding, kPcm32Encoding, channelMask,
         success ? "accepted" : "rejected");

    if (mixerAttributes != nullptr) env->DeleteLocalRef(mixerAttributes);
    if (format != nullptr) env->DeleteLocalRef(format);
    if (preferenceAttributes != nullptr) env->DeleteLocalRef(preferenceAttributes);
    env->DeleteLocalRef(usbDevice);
    env->DeleteLocalRef(audioManager);
    return success;
}

jint replacementNativeSetup(JNIEnv *env, jobject thiz, jobject weakThis, jobject audioAttributes,
                            jintArray sampleRates, jobject channelMasks, jint audioFormat,
                            jint bufferSize, jint mode, jintArray sessionId, jobject attributionParcel,
                            jlong nativeTrack, jboolean offloaded, jint encapsulationMode,
                            jobject tunerConfiguration, jstring opPackageName,
                            jstring codecProvenance) {
    if (!gApplyingPreference) {
        gApplyingPreference = true;
        applyBitPerfectPreference(env, audioAttributes, sampleRates, channelMasks,
                                  audioFormat, offloaded);
        gApplyingPreference = false;
    }

    return gOriginalNativeSetup(
            env, thiz, weakThis, audioAttributes, sampleRates, channelMasks, audioFormat,
            bufferSize, mode, sessionId, attributionParcel, nativeTrack, offloaded,
            encapsulationMode, tunerConfiguration, opPackageName, codecProvenance);
}

class RateFollowerModule final : public zygisk::ModuleBase {
public:
    void onLoad(zygisk::Api *api, JNIEnv *env) override {
        api_ = api;
        env_ = env;
    }

    void preAppSpecialize(zygisk::AppSpecializeArgs *args) override {
        const char *process = env_->GetStringUTFChars(args->nice_name, nullptr);
        const bool target = process != nullptr && isTargetProcess(process);
        if (target) {
            std::strncpy(gProcessName, process, sizeof(gProcessName) - 1);
        }
        if (process != nullptr) env_->ReleaseStringUTFChars(args->nice_name, process);
        clearException(env_, "process name read");

        if (!target) {
            api_->setOption(zygisk::Option::DLCLOSE_MODULE_LIBRARY);
            return;
        }

        JNINativeMethod method = {
                const_cast<char *>("native_setup"),
                const_cast<char *>(kNativeSetupSignature),
                reinterpret_cast<void *>(replacementNativeSetup),
        };
        api_->hookJniNativeMethods(env_, kAudioTrackClass, &method, 1);
        gOriginalNativeSetup = reinterpret_cast<NativeSetup>(method.fnPtr);
        if (gOriginalNativeSetup == nullptr) {
            LOGW("native_setup hook was not installed in %s", gProcessName);
            api_->setOption(zygisk::Option::DLCLOSE_MODULE_LIBRARY);
        } else {
            LOGI("native_setup hook installed in %s", gProcessName);
        }
    }

private:
    zygisk::Api *api_ = nullptr;
    JNIEnv *env_ = nullptr;
};

}  // namespace

REGISTER_ZYGISK_MODULE(RateFollowerModule)
