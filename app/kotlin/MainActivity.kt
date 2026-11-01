package com.example.xpadlink

import android.hardware.input.InputManager
import android.os.Bundle
import android.util.Log
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import kotlin.math.abs
import kotlin.math.max

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
    }

    private var sink: EventChannel.EventSink? = null

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
    private var rtKey = false
    private var deviceName = "gamepad"

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
        Log.i(TAG, "MainActivity created")
        val im = getSystemService(INPUT_SERVICE) as InputManager
        im.registerInputDeviceListener(deviceListener, null)
        for (id in InputDevice.getDeviceIds()) logDevice("present", InputDevice.getDevice(id))
    }

    override fun onDestroy() {
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
                "sources=0x${Integer.toHexString(d.sources)} pad=${isPad(d.sources)} axes=[$axes]"
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
    }

    private fun isPad(source: Int) =
        (source and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD ||
            (source and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK

    private fun faceBit(code: Int): Int = when (code) {
        KeyEvent.KEYCODE_BUTTON_A -> 1 shl 0
        KeyEvent.KEYCODE_BUTTON_B -> 1 shl 1
        KeyEvent.KEYCODE_BUTTON_X -> 1 shl 2
        KeyEvent.KEYCODE_BUTTON_Y -> 1 shl 3
        KeyEvent.KEYCODE_BUTTON_L1 -> 1 shl 4
        KeyEvent.KEYCODE_BUTTON_R1 -> 1 shl 5
        KeyEvent.KEYCODE_BUTTON_SELECT -> 1 shl 6
        KeyEvent.KEYCODE_BUTTON_START -> 1 shl 7
        KeyEvent.KEYCODE_BUTTON_MODE -> 1 shl 8
        KeyEvent.KEYCODE_BUTTON_THUMBL -> 1 shl 9
        KeyEvent.KEYCODE_BUTTON_THUMBR -> 1 shl 10
        else -> 0
    }

    private fun dpadBit(code: Int): Int = when (code) {
        KeyEvent.KEYCODE_DPAD_UP -> 1 shl 11
        KeyEvent.KEYCODE_DPAD_DOWN -> 1 shl 12
        KeyEvent.KEYCODE_DPAD_LEFT -> 1 shl 13
        KeyEvent.KEYCODE_DPAD_RIGHT -> 1 shl 14
        else -> 0
    }

    private fun setBit(bits: Int, bit: Int, on: Boolean) =
        if (on) bits or bit else bits and bit.inv()

    override fun dispatchKeyEvent(e: KeyEvent): Boolean {
        if (e.action != KeyEvent.ACTION_DOWN && e.action != KeyEvent.ACTION_UP) {
            return super.dispatchKeyEvent(e)
        }
        val down = e.action == KeyEvent.ACTION_DOWN
        val pad = isPad(e.source)
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
        lx = deadzone(e.getAxisValue(MotionEvent.AXIS_X))
        ly = deadzone(e.getAxisValue(MotionEvent.AXIS_Y))
        // Xbox and PS4 pads on Android: right stick is Z/RZ, triggers are LTRIGGER/RTRIGGER.
        rx = deadzone(e.getAxisValue(MotionEvent.AXIS_Z))
        ry = deadzone(e.getAxisValue(MotionEvent.AXIS_RZ))
        ltAxis = max(e.getAxisValue(MotionEvent.AXIS_LTRIGGER), e.getAxisValue(MotionEvent.AXIS_BRAKE))
        rtAxis = max(e.getAxisValue(MotionEvent.AXIS_RTRIGGER), e.getAxisValue(MotionEvent.AXIS_GAS))

        val hx = e.getAxisValue(MotionEvent.AXIS_HAT_X)
        val hy = e.getAxisValue(MotionEvent.AXIS_HAT_Y)
        hatDpad = (if (hy < -0.5f) 1 shl 11 else 0) or
            (if (hy > 0.5f) 1 shl 12 else 0) or
            (if (hx < -0.5f) 1 shl 13 else 0) or
            (if (hx > 0.5f) 1 shl 14 else 0)

        e.device?.name?.let { deviceName = it }
        emit()
        return true
    }

    private fun deadzone(v: Float) = if (abs(v) < 0.08f) 0f else v

    private fun i16(v: Float) = (v.coerceIn(-1f, 1f) * 32767f).toInt()

    private fun trigger(axis: Float, key: Boolean) =
        max((axis.coerceIn(0f, 1f) * 255f).toInt(), if (key) 255 else 0)

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
                "lt" to trigger(ltAxis, ltKey),
                "rt" to trigger(rtAxis, rtKey),
            )
        )
    }
}
