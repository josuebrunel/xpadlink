package com.example.xpadlink

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.input.InputManager
import android.media.AudioAttributes
import android.os.Build
import android.os.Bundle
import android.os.CombinedVibration
import android.os.Handler
import android.os.Looper
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.Surface
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs
import kotlin.math.max

/** Button bits, Xbox 360 layout. Same values as server/proto/proto.go and app/lib/protocol.dart. */
private object Btn {
    const val A = 1 shl 0
    const val B = 1 shl 1
    const val X = 1 shl 2
    const val Y = 1 shl 3
    const val LB = 1 shl 4
    const val RB = 1 shl 5
    const val BACK = 1 shl 6
    const val START = 1 shl 7
    const val GUIDE = 1 shl 8
    const val L3 = 1 shl 9
    const val R3 = 1 shl 10
    const val D_UP = 1 shl 11
    const val D_DOWN = 1 shl 12
    const val D_LEFT = 1 shl 13
    const val D_RIGHT = 1 shl 14
}

/**
 * Bridges a physical gamepad (Bluetooth or USB) to Dart. Flutter does not
 * deliver joystick axes, so we intercept key and motion events here, keep the
 * full state, and push it over the "xpadlink/gamepad" EventChannel.
 *
 * Button bits match server/proto/proto.go and app/lib/protocol.dart.
 */
class MainActivity : FlutterActivity() {
    private companion object {
        const val TAG = "xpadlink"
        const val LOG_EVERY_MS = 2000L
        const val REQ_BT = 4177
    }

    private var sink: EventChannel.EventSink? = null
    private var btSink: EventChannel.EventSink? = null
    private var bt: BtLink? = null
    private var btPermission: ((Boolean) -> Unit)? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var motionSink: EventChannel.EventSink? = null
    private var volumeSink: EventChannel.EventSink? = null
    private var interceptVolUp = false
    private var interceptVolDown = false
    private var volUpHeld = false
    private var volDownHeld = false
    private var volUpConsumedDown = false
    private var volDownConsumedDown = false
    private val accel = FloatArray(3)
    private var prevQ: FloatArray? = null
    private var prevQNs = 0L

    private var faceBits = 0
    private var keyDpad = 0
    private var hatDpad = 0
    private var lx = 0f
    private var ly = 0f
    private var rx = 0f
    private var ry = 0f
    private var ltAxis = 0f
    private var rtAxis = 0f
    private var ltKey = false
    private var ltHasAxis = false
    private var rtHasAxis = false
    private var rtKey = false
    private var deviceName = "gamepad"

    /** Last physical pad that sent input: rumble goes there if it has motors. */
    private var padDeviceId = -1

    private val seenDevices = HashSet<Int>()
    private val lastLog = HashMap<String, Long>()

    private val deviceListener = object : InputManager.InputDeviceListener {
        override fun onInputDeviceAdded(id: Int) = logDevice("added", InputDevice.getDevice(id))
        override fun onInputDeviceRemoved(id: Int) {
            Log.i(TAG, "input device removed id=$id")
            seenDevices.remove(id)
        }
        override fun onInputDeviceChanged(id: Int) = logDevice("changed", InputDevice.getDevice(id))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        applyImmersiveMode()
        Log.i(TAG, "MainActivity created")
        val im = getSystemService(INPUT_SERVICE) as InputManager
        im.registerInputDeviceListener(deviceListener, null)
        for (id in InputDevice.getDeviceIds()) logDevice("present", InputDevice.getDevice(id))
    }

    override fun onPause() {
        releaseHeldVolumeKeys()
        super.onPause()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            applyImmersiveMode()
        } else {
            releaseHeldVolumeKeys()
        }
    }

    private fun releaseHeldVolumeKeys() {
        if (volUpHeld) {
            volUpHeld = false
            volumeSink?.success(mapOf("key" to "up", "down" to false))
        }
        if (volDownHeld) {
            volDownHeld = false
            volumeSink?.success(mapOf("key" to "down", "down" to false))
        }
        volUpConsumedDown = false
        volDownConsumedDown = false
    }

    private fun applyImmersiveMode() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            val controller = window.insetsController
            if (controller != null) {
                controller.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                or View.SYSTEM_UI_FLAG_FULLSCREEN
                or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            )
        }
    }

    /** BLUETOOTH_CONNECT is a runtime permission from Android 12. */
    private fun withBtPermission(then: (Boolean) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
        ) {
            then(true)
            return
        }
        btPermission = then
        requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), REQ_BT)
    }

    override fun onRequestPermissionsResult(code: Int, perms: Array<out String>, results: IntArray) {
        if (code == REQ_BT) {
            btPermission?.invoke(results.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            btPermission = null
        } else {
            super.onRequestPermissionsResult(code, perms, results)
        }
    }

    private fun btConnect(address: String, result: MethodChannel.Result) {
        btClose()
        val link = BtLink(
            // Ignore a link we already replaced: its late events would hit the new session.
            onPacket = { l, pkt -> mainHandler.post { if (bt === l) btSink?.success(pkt) } },
            onClosed = { l -> mainHandler.post { if (bt === l) btSink?.success("closed") } },
        )
        bt = link
        Thread({
            try {
                link.connect(address)
                mainHandler.post { result.success(null) }
            } catch (e: Exception) {
                Log.w(TAG, "bt connect failed: ${e.message}")
                mainHandler.post { result.error("connect", e.message ?: "connect failed", null) }
            }
        }, "bt-connect").start()
    }

    private fun btClose() {
        bt?.close()
        bt = null
    }

    override fun onDestroy() {
        releaseHeldVolumeKeys()
        btClose()
        stopMotion()
        (getSystemService(INPUT_SERVICE) as InputManager).unregisterInputDeviceListener(deviceListener)
        Log.i(TAG, "MainActivity destroyed")
        super.onDestroy()
    }

    /** Logs a device once per change with the details needed to debug mappings. */
    private fun logDevice(event: String, d: InputDevice?) {
        if (d == null) return
        val axes = d.motionRanges.joinToString(",") { MotionEvent.axisToString(it.axis).removePrefix("AXIS_") }
        Log.i(
            TAG,
            "input device $event id=${d.id} name='${d.name}' vendor=${d.vendorId} product=${d.productId} " +
                "sources=0x${Integer.toHexString(d.sources)} pad=${isPad(d.sources)} " +
                "vibrators=${padVibratorCount(d)} axes=[$axes]"
        )
    }

    /** Rate-limited log so a held button or stick doesn't flood logcat. */
    private fun logLimited(key: String, msg: String) {
        val now = System.currentTimeMillis()
        if (now - (lastLog[key] ?: 0L) < LOG_EVERY_MS) return
        lastLog[key] = now
        Log.w(TAG, msg)
    }

    private fun noteDevice(e: android.view.InputEvent) {
        if (seenDevices.add(e.deviceId)) logDevice("first event", e.device)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "xpadlink/rumble")
            .setMethodCallHandler { call, result ->
                if (call.method == "vibrate") {
                    vibrate(call.argument<Int>("strong") ?: 0, call.argument<Int>("weak") ?: 0, call.argument<Int>("ms") ?: 0)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "xpadlink/bt")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "paired" -> withBtPermission { ok ->
                        if (ok) result.success(BtLink.paired()) else result.error("permission", "Bluetooth permission denied", null)
                    }
                    "connect" -> withBtPermission { ok ->
                        if (ok) btConnect(call.argument<String>("address") ?: "", result)
                        else result.error("permission", "Bluetooth permission denied", null)
                    }
                    "send" -> {
                        call.argument<ByteArray>("data")?.let { bt?.send(it) }
                        result.success(null)
                    }
                    "close" -> {
                        btClose()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // Packets from the server, and the String "closed" when the link ends.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "xpadlink/bt/rx")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                    btSink = events
                }

                override fun onCancel(args: Any?) {
                    btSink = null
                }
            })

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "xpadlink/motion")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                    motionSink = events
                    startMotion()
                }

                override fun onCancel(args: Any?) {
                    stopMotion()
                    motionSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "xpadlink/motion_config")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setFallbackEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        useAccelFallback = enabled
                        if (motionSink != null) {
                            stopMotion()
                            startMotion()
                        }
                        result.success(true)
                    }
                    "hasGyroscope" -> {
                        val sm = getSystemService(Context.SENSOR_SERVICE) as SensorManager
                        result.success(sm.getDefaultSensor(Sensor.TYPE_GYROSCOPE) != null)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "xpadlink/gamepad")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                    Log.i(TAG, "gamepad channel: Dart listening")
                    sink = events
                }

                override fun onCancel(args: Any?) {
                    Log.i(TAG, "gamepad channel: Dart stopped listening")
                    sink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "xpadlink/volume_config")
            .setMethodCallHandler { call, result ->
                if (call.method == "setConfig") {
                    val up = call.argument<Boolean>("interceptUp") ?: false
                    val down = call.argument<Boolean>("interceptDown") ?: false
                    if (!up && volUpHeld) {
                        volUpHeld = false
                        volumeSink?.success(mapOf("key" to "up", "down" to false))
                    }
                    if (!down && volDownHeld) {
                        volDownHeld = false
                        volumeSink?.success(mapOf("key" to "down", "down" to false))
                    }
                    interceptVolUp = up
                    interceptVolDown = down
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "xpadlink/volume_keys")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                    volumeSink = events
                }

                override fun onCancel(args: Any?) {
                    releaseHeldVolumeKeys()
                    interceptVolUp = false
                    interceptVolDown = false
                    volumeSink = null
                }
            })
    }

    /**
     * Sends [ax, ay, az] in g and [gx, gy, gz] in deg/s, rotated into the pad frame
     * (x right, y up the screen, z out of the screen) for the current screen
     * rotation, so a phone held like a GamePad reports like one. Emitted on each
     * gyro sample; the accelerometer value is the latest one.
     */
    private val motionListener = object : SensorEventListener {
        override fun onSensorChanged(e: SensorEvent) {
            if (e.sensor.type == Sensor.TYPE_ACCELEROMETER) {
                System.arraycopy(e.values, 0, accel, 0, 3)
                return
            }
            val gyro = if (e.sensor.type == Sensor.TYPE_GYROSCOPE) {
                floatArrayOf(e.values[0], e.values[1], e.values[2])
            } else {
                angularVelocity(e.values, e.timestamp) ?: return
            }
            val a = toPadFrame(accel[0], accel[1], accel[2])
            val g = toPadFrame(gyro[0], gyro[1], gyro[2])
            val k = (180.0 / Math.PI).toFloat()
            val gs = 1f / SensorManager.GRAVITY_EARTH
            motionSink?.success(
                listOf(a[0] * gs, a[1] * gs, a[2] * gs, g[0] * k, g[1] * k, g[2] * k).map { it.toDouble() }
            )
        }

        override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {}
    }

    /**
     * For phones without a gyroscope: turn rate (rad/s, device axes) from the change
     * between two rotation-vector samples (accelerometer + magnetometer fusion).
     */
    private fun angularVelocity(values: FloatArray, ns: Long): FloatArray? {
        val q = FloatArray(4)
        SensorManager.getQuaternionFromVector(q, values) // w, x, y, z
        val p = prevQ
        val dt = (ns - prevQNs) / 1e9f
        prevQ = q
        prevQNs = ns
        if (p == null || dt <= 0f || dt > 0.2f) return null
        // rel = conj(p) * q: the rotation from the previous pose to this one, in device axes.
        val w = p[0] * q[0] + p[1] * q[1] + p[2] * q[2] + p[3] * q[3]
        val x = p[0] * q[1] - p[1] * q[0] - p[2] * q[3] + p[3] * q[2]
        val y = p[0] * q[2] + p[1] * q[3] - p[2] * q[0] - p[3] * q[1]
        val z = p[0] * q[3] - p[1] * q[2] + p[2] * q[1] - p[3] * q[0]
        val sign = if (w < 0f) -1f else 1f // shortest way round
        val s = kotlin.math.sqrt(x * x + y * y + z * z)
        if (s < 1e-6f) return floatArrayOf(0f, 0f, 0f)
        val angle = 2f * kotlin.math.atan2(s, w * sign)
        val k = sign * angle / s / dt
        return floatArrayOf(x * k, y * k, z * k)
    }

    /** Device axes are fixed to the portrait body; rotate them to what the user sees. */
    private fun toPadFrame(x: Float, y: Float, z: Float): FloatArray {
        @Suppress("DEPRECATION")
        return when (windowManager.defaultDisplay.rotation) {
            Surface.ROTATION_90 -> floatArrayOf(-y, x, z)
            Surface.ROTATION_180 -> floatArrayOf(-x, -y, z)
            Surface.ROTATION_270 -> floatArrayOf(y, -x, z)
            else -> floatArrayOf(x, y, z)
        }
    }

    private var useAccelFallback = false

    private fun startMotion() {
        val sm = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val acc = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        val hardwareGyro = sm.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
        val gyro = if (!useAccelFallback && hardwareGyro != null) {
            hardwareGyro
        } else if (useAccelFallback) {
            hardwareGyro
                ?: sm.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)
                ?: sm.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        } else {
            hardwareGyro
        }
        if (gyro == null || acc == null) {
            Log.w(TAG, "motion unavailable: hardwareGyro=${hardwareGyro != null} fallback=$useAccelFallback accel=${acc != null}")
            return
        }
        prevQ = null
        val us = 10000 // ~100 Hz for low latency in Cemu/BotW
        sm.registerListener(motionListener, acc, us)
        sm.registerListener(motionListener, gyro, us)
        Log.i(TAG, "motion started (turn rate from '${gyro.name}' [accelFallback=$useAccelFallback], accel='${acc.name}')")
    }

    private fun stopMotion() {
        (getSystemService(Context.SENSOR_SERVICE) as SensorManager).unregisterListener(motionListener)
        Log.i(TAG, "motion stopped")
    }

    private fun padVibratorCount(d: InputDevice): Int = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) d.vibratorManager.vibratorIds.size
        else @Suppress("DEPRECATION") if (d.vibrator.hasVibrator()) 1 else 0
    } catch (e: Exception) {
        0
    }

    private fun phoneVibrator(): Vibrator =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION") getSystemService(VIBRATOR_SERVICE) as Vibrator
        }

    /** Rumble from a game: strong and weak motors, 0..65535; ms 0 means "until stopped". */
    private fun vibrate(strong: Int, weak: Int, ms: Int) {
        val pad = if (padDeviceId >= 0) InputDevice.getDevice(padDeviceId) else null
        if (strong == 0 && weak == 0) {
            try {
                pad?.let { cancelPad(it) }
                phoneVibrator().cancel()
            } catch (e: Exception) {
                Log.w(TAG, "cancel vibration failed: $e")
            }
            return
        }
        val dur = (if (ms == 0) 2000 else ms).coerceIn(1, 10000).toLong()
        val s = strong * 255 / 65535
        val w = weak * 255 / 65535
        if (pad != null && padVibratorCount(pad) > 0 && vibratePad(pad, s, w, dur)) {
            Log.i(TAG, "rumble strong=$strong weak=$weak ms=$ms -> pad '${pad.name}'")
            return
        }
        try {
            val v = phoneVibrator()
            val amp = if (v.hasAmplitudeControl()) maxOf(s, w).coerceIn(1, 255) else VibrationEffect.DEFAULT_AMPLITUDE
            vibrateAsMedia(v, VibrationEffect.createOneShot(dur, amp))
            Log.i(TAG, "rumble strong=$strong weak=$weak ms=$ms -> phone")
        } catch (e: Exception) {
            Log.w(TAG, "phone vibration failed: $e")
        }
    }

    /**
     * A game's rumble is not touch feedback. Without attributes Android files a
     * vibration under TOUCH and drops it when "touch vibration" is off in the
     * phone settings, so the buzz silently never happens.
     */
    private fun vibrateAsMedia(v: Vibrator, effect: VibrationEffect) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            v.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_MEDIA))
        } else {
            @Suppress("DEPRECATION")
            v.vibrate(effect, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).build())
        }
    }

    private fun vibratePad(d: InputDevice, s: Int, w: Int, dur: Long): Boolean = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vm = d.vibratorManager
            val ids = vm.vibratorIds
            val combo = CombinedVibration.startParallel()
            var added = 0
            ids.forEachIndexed { i, id ->
                // Two motors: first is the strong one. One motor: use the louder value.
                val amp = if (ids.size > 1) (if (i == 0) s else w) else maxOf(s, w)
                if (amp > 0) {
                    combo.addVibrator(id, VibrationEffect.createOneShot(dur, amp.coerceIn(1, 255)))
                    added++
                }
            }
            if (added > 0) vm.vibrate(combo.combine())
            true
        } else {
            @Suppress("DEPRECATION")
            d.vibrator.vibrate(VibrationEffect.createOneShot(dur, maxOf(s, w).coerceIn(1, 255)))
            true
        }
    } catch (e: Exception) {
        Log.w(TAG, "pad vibration failed: $e")
        false
    }

    private fun cancelPad(d: InputDevice) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) d.vibratorManager.cancel()
        else @Suppress("DEPRECATION") d.vibrator.cancel()
    }

    private fun isPad(source: Int) =
        (source and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD ||
            (source and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK

    private fun faceBit(code: Int): Int = when (code) {
        KeyEvent.KEYCODE_BUTTON_A -> Btn.A
        KeyEvent.KEYCODE_BUTTON_B -> Btn.B
        KeyEvent.KEYCODE_BUTTON_X -> Btn.X
        KeyEvent.KEYCODE_BUTTON_Y -> Btn.Y
        KeyEvent.KEYCODE_BUTTON_L1 -> Btn.LB
        KeyEvent.KEYCODE_BUTTON_R1 -> Btn.RB
        KeyEvent.KEYCODE_BUTTON_SELECT -> Btn.BACK
        KeyEvent.KEYCODE_BUTTON_START -> Btn.START
        KeyEvent.KEYCODE_BUTTON_MODE -> Btn.GUIDE
        KeyEvent.KEYCODE_BUTTON_THUMBL -> Btn.L3
        KeyEvent.KEYCODE_BUTTON_THUMBR -> Btn.R3
        else -> 0
    }

    private fun dpadBit(code: Int): Int = when (code) {
        KeyEvent.KEYCODE_DPAD_UP -> Btn.D_UP
        KeyEvent.KEYCODE_DPAD_DOWN -> Btn.D_DOWN
        KeyEvent.KEYCODE_DPAD_LEFT -> Btn.D_LEFT
        KeyEvent.KEYCODE_DPAD_RIGHT -> Btn.D_RIGHT
        else -> 0
    }

    private fun setBit(bits: Int, bit: Int, on: Boolean) =
        if (on) bits or bit else bits and bit.inv()

    private fun handleVolumeKey(isUp: Boolean, down: Boolean, repeatCount: Int): Boolean {
        val intercept = if (isUp) interceptVolUp else interceptVolDown
        val consumedDown = if (isUp) volUpConsumedDown else volDownConsumedDown
        val held = if (isUp) volUpHeld else volDownHeld
        val name = if (isUp) "up" else "down"

        if (down && intercept) {
            if (repeatCount > 0) return true
            if (isUp) volUpConsumedDown = true else volDownConsumedDown = true
            if (!held) {
                if (isUp) volUpHeld = true else volDownHeld = true
                volumeSink?.success(mapOf("key" to name, "down" to true))
            }
            return true
        }
        if (!down && (intercept || consumedDown)) {
            if (isUp) volUpConsumedDown = false else volDownConsumedDown = false
            if (held) {
                if (isUp) volUpHeld = false else volDownHeld = false
                volumeSink?.success(mapOf("key" to name, "down" to false))
            }
            return true
        }
        return false
    }

    override fun dispatchKeyEvent(e: KeyEvent): Boolean {
        if (e.action != KeyEvent.ACTION_DOWN && e.action != KeyEvent.ACTION_UP) {
            return super.dispatchKeyEvent(e)
        }
        val down = e.action == KeyEvent.ACTION_DOWN

        if (e.keyCode == KeyEvent.KEYCODE_VOLUME_UP || e.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            val isUp = e.keyCode == KeyEvent.KEYCODE_VOLUME_UP
            return if (handleVolumeKey(isUp, down, e.repeatCount)) true else super.dispatchKeyEvent(e)
        }

        val pad = isPad(e.source)
        if (pad) padDeviceId = e.deviceId
        noteDevice(e)
        val face = faceBit(e.keyCode)
        val dpad = if (pad) dpadBit(e.keyCode) else 0

        when {
            face != 0 -> faceBits = setBit(faceBits, face, down)
            dpad != 0 -> keyDpad = setBit(keyDpad, dpad, down)
            pad && e.keyCode == KeyEvent.KEYCODE_BUTTON_L2 -> ltKey = down
            pad && e.keyCode == KeyEvent.KEYCODE_BUTTON_R2 -> rtKey = down
            else -> {
                if (pad) {
                    logLimited(
                        "key${e.keyCode}",
                        "unmapped pad key ${KeyEvent.keyCodeToString(e.keyCode)} from '${e.device?.name}'"
                    )
                }
                return super.dispatchKeyEvent(e)
            }
        }
        if (e.repeatCount > 0) return true
        e.device?.name?.let { deviceName = it }
        emit()
        return true
    }

    override fun dispatchGenericMotionEvent(e: MotionEvent): Boolean {
        val joystick = (e.source and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK
        if (!joystick || e.action != MotionEvent.ACTION_MOVE) {
            if (e.source != 0 && e.action != MotionEvent.ACTION_HOVER_MOVE) {
                logLimited(
                    "motion${e.source}-${e.action}",
                    "ignored motion event source=0x${Integer.toHexString(e.source)} action=${e.action}"
                )
            }
            return super.dispatchGenericMotionEvent(e)
        }
        noteDevice(e)
        padDeviceId = e.deviceId
        lx = e.getAxisValue(MotionEvent.AXIS_X)
        ly = e.getAxisValue(MotionEvent.AXIS_Y)
        // Xbox and PS4 pads on Android: right stick is Z/RZ, triggers are LTRIGGER/RTRIGGER.
        rx = e.getAxisValue(MotionEvent.AXIS_Z)
        ry = e.getAxisValue(MotionEvent.AXIS_RZ)
        ltAxis = max(e.getAxisValue(MotionEvent.AXIS_LTRIGGER), e.getAxisValue(MotionEvent.AXIS_BRAKE))
        rtAxis = max(e.getAxisValue(MotionEvent.AXIS_RTRIGGER), e.getAxisValue(MotionEvent.AXIS_GAS))
        ltHasAxis = hasAxis(e, MotionEvent.AXIS_LTRIGGER, MotionEvent.AXIS_BRAKE)
        rtHasAxis = hasAxis(e, MotionEvent.AXIS_RTRIGGER, MotionEvent.AXIS_GAS)

        val hx = e.getAxisValue(MotionEvent.AXIS_HAT_X)
        val hy = e.getAxisValue(MotionEvent.AXIS_HAT_Y)
        hatDpad = (if (hy < -0.5f) Btn.D_UP else 0) or
            (if (hy > 0.5f) Btn.D_DOWN else 0) or
            (if (hx < -0.5f) Btn.D_LEFT else 0) or
            (if (hx > 0.5f) Btn.D_RIGHT else 0)

        e.device?.name?.let { deviceName = it }
        emit()
        return true
    }

    private fun i16(v: Float) = (v.coerceIn(-1f, 1f) * 32767f).toInt()

    private fun hasAxis(e: MotionEvent, vararg axes: Int) =
        axes.any { e.device?.getMotionRange(it, e.source) != null }

    // The L2/R2 key is only a fallback for pads with no analog axis. Pads with
    // analog (Hall effect) triggers can also send the key at a small pull, which
    // would pin the trigger to full.
    private fun trigger(axis: Float, key: Boolean, hasAxis: Boolean) =
        if (hasAxis) (axis.coerceIn(0f, 1f) * 255f).toInt()
        else if (key) 255 else (axis.coerceIn(0f, 1f) * 255f).toInt()

    private fun emit() {
        val s = sink
        if (s == null) {
            logLimited("nosink", "pad event dropped: Dart is not listening on the gamepad channel")
            return
        }
        s.success(
            mapOf(
                "name" to deviceName,
                "buttons" to (faceBits or keyDpad or hatDpad),
                "lx" to i16(lx),
                "ly" to i16(ly),
                "rx" to i16(rx),
                "ry" to i16(ry),
                "lt" to trigger(ltAxis, ltKey, ltHasAxis),
                "rt" to trigger(rtAxis, rtKey, rtHasAxis),
            )
        )
    }
}
