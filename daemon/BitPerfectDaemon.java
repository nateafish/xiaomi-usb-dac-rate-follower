import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStreamReader;
import java.io.PrintStream;
import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Root-side controller for Android's hidden preferred mixer attributes API.
 *
 * This is deliberately conservative: it only targets the two configured music
 * UIDs, only acts while an ALSA USB card is present, and leaves the framework
 * untouched when the USB/Bit Perfect capability is not available.
 */
public final class BitPerfectDaemon {
    private static final String[] TARGET_PACKAGES = {
            "com.netease.cloudmusic",
            "com.apple.android.music"
    };
    private static final int[] DEFAULT_RATES = {
            44100, 48000, 88200, 96000, 176400, 192000, 384000
    };
    // AudioFormat.Builder uses Java encoding constants, not native
    // audio_format_t values printed by dumpsys media.audio_flinger.
    private static final int JAVA_PCM_16 = 2;
    private static final int JAVA_PCM_32 = 22;
    private static final int DEFAULT_PREARM_RATE = 44100;
    private static final Pattern PACKAGE_UID = Pattern.compile("uid:(\\d+)");
    private static final Pattern UID_STATE = Pattern.compile("^(\\d+)");
    private static final Pattern USB_DEVICE_PORT = Pattern.compile(
            "Port ID: (\\d+); \\\"usb_(?:headset|device_out)\\\"");
    private static final Pattern TRACK = Pattern.compile(
            "\\b\\d+\\s*/\\s*(\\d+)\\s+\\d+\\s+\\d+\\s+([A-Za-z])\\s+\\S+\\s+"
                    + "([0-9A-Fa-f]+)\\s+([0-9A-Fa-f]+)\\s+(\\d+)\\b");
    private static int lastOwner = -1;
    private static String lastRequest;
    private static String lastAttempt;
    private static long lastAttemptMs;

    private static Class<?> audioSystem;
    private static Method getSupportedMixerAttributes;
    private static Method setPreferredMixerAttributes;
    private static Constructor<?> audioFormatBuilder;
    private static Constructor<?> audioAttributesBuilder;
    private static Constructor<?> mixerAttributesBuilder;

    private static void log(String message) {
        System.out.println("[BitPerfectDaemon] " + message);
    }

    private static Object invoke(Object receiver, String name, Class<?>[] types, Object... args)
            throws Exception {
        Method method = receiver instanceof Class
                ? ((Class<?>) receiver).getDeclaredMethod(name, types)
                : receiver.getClass().getDeclaredMethod(name, types);
        method.setAccessible(true);
        return method.invoke(receiver instanceof Class ? null : receiver, args);
    }

    private static Object construct(Constructor<?> constructor, Object... args) throws Exception {
        constructor.setAccessible(true);
        return constructor.newInstance(args);
    }

    private static void initializeReflection() throws Exception {
        audioSystem = Class.forName("android.media.AudioSystem");
        getSupportedMixerAttributes = audioSystem.getDeclaredMethod(
                "getSupportedMixerAttributes", int.class, List.class);
        getSupportedMixerAttributes.setAccessible(true);
        setPreferredMixerAttributes = audioSystem.getDeclaredMethod(
                "setPreferredMixerAttributes",
                Class.forName("android.media.AudioAttributes"), int.class, int.class,
                Class.forName("android.media.AudioMixerAttributes"));
        setPreferredMixerAttributes.setAccessible(true);

        audioFormatBuilder = Class.forName("android.media.AudioFormat$Builder")
                .getDeclaredConstructor();
        audioAttributesBuilder = Class.forName("android.media.AudioAttributes$Builder")
                .getDeclaredConstructor();
        Class<?> mixerType = Class.forName("android.media.AudioMixerAttributes$Builder");
        mixerAttributesBuilder = mixerType.getDeclaredConstructor(
                Class.forName("android.media.AudioFormat"));
    }

    private static Object buildMixerAttributes(int rate, int encoding) throws Exception {
        Object formatBuilder = construct(audioFormatBuilder);
        invoke(formatBuilder, "setSampleRate", new Class<?>[] {int.class}, rate);
        invoke(formatBuilder, "setEncoding", new Class<?>[] {int.class}, encoding);
        // AudioFormat.CHANNEL_OUT_STEREO is the Java position mask 0xC.
        invoke(formatBuilder, "setChannelMask", new Class<?>[] {int.class}, 0xC);
        Object format = invoke(formatBuilder, "build", new Class<?>[] {});

        Object mixerBuilder = construct(mixerAttributesBuilder, format);
        // AudioMixerAttributes.MIXER_BEHAVIOR_BIT_PERFECT.
        invoke(mixerBuilder, "setMixerBehavior", new Class<?>[] {int.class}, 1);
        return invoke(mixerBuilder, "build", new Class<?>[] {});
    }

    private static Object buildMediaAttributes() throws Exception {
        Object builder = construct(audioAttributesBuilder);
        // AudioAttributes.USAGE_MEDIA.
        invoke(builder, "setUsage", new Class<?>[] {int.class}, 1);
        return invoke(builder, "build", new Class<?>[] {});
    }

    private static String run(String... command) {
        StringBuilder output = new StringBuilder();
        try {
            Process process = new ProcessBuilder(command).redirectErrorStream(true).start();
            try (BufferedReader reader = new BufferedReader(
                    new InputStreamReader(process.getInputStream()))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    output.append(line).append('\n');
                }
            }
            process.waitFor();
        } catch (Throwable error) {
            log("command failed: " + error);
        }
        return output.toString();
    }

    private static boolean hasUsbCard() {
        String cards = run("/system/bin/cat", "/proc/asound/cards");
        return cards.toLowerCase().contains("usb");
    }

    private static Set<Integer> findTargetUids() {
        Set<Integer> result = new HashSet<>();
        for (String packageName : TARGET_PACKAGES) {
            String output = run("/system/bin/cmd", "package", "list", "packages", "-U",
                    packageName);
            Matcher matcher = PACKAGE_UID.matcher(output);
            if (matcher.find()) {
                result.add(Integer.parseInt(matcher.group(1)));
            }
        }
        return result;
    }

    private static int getUidState(int uid) {
        String output = run("/system/bin/cmd", "activity", "get-uid-state",
                Integer.toString(uid));
        Matcher matcher = UID_STATE.matcher(output.trim());
        return matcher.find() ? Integer.parseInt(matcher.group(1)) : Integer.MAX_VALUE;
    }

    private static int findForegroundTarget(Set<Integer> targetUids) {
        int selectedUid = -1;
        int selectedState = Integer.MAX_VALUE;
        for (int uid : targetUids) {
            int state = getUidState(uid);
            // TOP, BOUND_TOP, FOREGROUND_SERVICE and similarly visible states.
            if (state <= 4 && state < selectedState) {
                selectedUid = uid;
                selectedState = state;
            }
        }
        return selectedUid;
    }

    private static Set<Integer> findUsbPortIds(String policyDump) {
        Set<Integer> result = new HashSet<>();
        String[] lines = policyDump.split("\\n");
        for (String line : lines) {
            Matcher port = USB_DEVICE_PORT.matcher(line);
            if (port.find()) {
                result.add(Integer.parseInt(port.group(1)));
            }
        }
        return result;
    }

    private static final class TrackInfo {
        final int rate;
        final int encoding;

        TrackInfo(int rate, int encoding) {
            this.rate = rate;
            this.encoding = encoding;
        }
    }

    private static Map<Integer, TrackInfo> findActiveTracks(String flingerDump) {
        Map<Integer, TrackInfo> result = new HashMap<>();
        Matcher matcher = TRACK.matcher(flingerDump);
        while (matcher.find()) {
            if (!"A".equals(matcher.group(2))) {
                continue;
            }
            int uid = Integer.parseInt(matcher.group(1));
            int encoding;
            try {
                encoding = (int) Long.parseLong(matcher.group(3), 16);
            } catch (NumberFormatException error) {
                encoding = JAVA_PCM_16;
            }
            int rate = Integer.parseInt(matcher.group(5));
            if (rate > 0) {
                result.put(uid, new TrackInfo(rate, encoding));
            }
        }
        return result;
    }

    private static int normalizeRate(int requested) {
        for (int rate : DEFAULT_RATES) {
            if (rate == requested) {
                return requested;
            }
        }
        return 0;
    }

    private static void request(int portId, int uid, int rate, int encoding) {
        String key = portId + ":" + uid + ":" + rate + ":" + encoding;
        if (key.equals(lastRequest) && uid == lastOwner) {
            return;
        }
        long now = System.currentTimeMillis();
        if (key.equals(lastAttempt) && now - lastAttemptMs < 5000) {
            return;
        }
        lastAttempt = key;
        lastAttemptMs = now;
        try {
            List<Object> supported = new ArrayList<>();
            Object status = getSupportedMixerAttributes.invoke(null, portId, supported);
            if (!(status instanceof Integer) || ((Integer) status) != 0) {
                return;
            }
            Object attributes = buildMediaAttributes();
            Object mixer = buildMixerAttributes(rate, encoding);
            Object setStatus = setPreferredMixerAttributes.invoke(
                    null, attributes, portId, uid, mixer);
            log("set port=" + portId + " uid=" + uid + " rate=" + rate
                    + " encoding=" + encoding + " status=" + setStatus
                    + " supported=" + supported.size());
            if (setStatus instanceof Integer && ((Integer) setStatus) == 0) {
                lastOwner = uid;
                lastRequest = key;
            }
        } catch (Throwable error) {
            log("mixer request failed port=" + portId + " uid=" + uid + ": " + error);
        }
    }

    private static void loop() throws Exception {
        initializeReflection();
        log("started; target packages=com.netease.cloudmusic,com.apple.android.music");
        while (true) {
            if (!hasUsbCard()) {
                lastOwner = -1;
                lastRequest = null;
                lastAttempt = null;
                lastAttemptMs = 0;
                Thread.sleep(1500);
                continue;
            }

            String policy = run("/system/bin/dumpsys", "media.audio_policy");
            Set<Integer> ports = findUsbPortIds(policy);
            if (ports.isEmpty()) {
                Thread.sleep(1000);
                continue;
            }
            Map<Integer, TrackInfo> tracks = findActiveTracks(
                    run("/system/bin/dumpsys", "media.audio_flinger"));
            Set<Integer> targetUids = findTargetUids();
            int selectedUid = -1;
            if (tracks.containsKey(lastOwner)) {
                selectedUid = lastOwner;
            } else {
                for (int uid : targetUids) {
                    if (tracks.containsKey(uid)) {
                        selectedUid = uid;
                        break;
                    }
                }
            }
            boolean prearmed = false;
            if (selectedUid < 0) {
                selectedUid = findForegroundTarget(targetUids);
                prearmed = selectedUid >= 0;
            }
            if (selectedUid >= 0) {
                TrackInfo track = tracks.get(selectedUid);
                int rate = prearmed ? DEFAULT_PREARM_RATE : normalizeRate(track.rate);
                if (rate == 0) {
                    log("skip unsupported track rate uid=" + selectedUid
                            + " rate=" + track.rate);
                } else {
                    for (int port : ports) {
                        // The dynamic Qualcomm hifi profile is exposed as PCM32.
                        // AudioFlinger widens PCM16 input without changing samples.
                        request(port, selectedUid, rate, JAVA_PCM_32);
                    }
                }
            }
            Thread.sleep(750);
        }
    }

    public static void main(String[] args) throws Exception {
        String logPath = args.length > 0 ? args[0] : "/data/adb/bitperfect-daemon.log";
        File logFile = new File(logPath);
        File parent = logFile.getParentFile();
        if (parent != null) {
            parent.mkdirs();
        }
        System.setOut(new PrintStream(new FileOutputStream(logFile, true), true));
        System.setErr(System.out);
        loop();
    }
}
