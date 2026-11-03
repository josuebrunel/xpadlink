package com.example.xpadlink

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothSocket
import android.util.Log
import java.io.DataInputStream
import java.io.IOException
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * One RFCOMM connection to xpadlinkd. Packets are the UDP ones with a u16
 * little endian length prefix (server/bt/bt.go). Needs BLUETOOTH_CONNECT.
 *
 * Writes go through one thread. A blocking write on a congested link must not
 * pile up seconds of old input, so only the newest state and the newest motion
 * packet wait for it. Hello and bye are never dropped.
 */
@SuppressLint("MissingPermission")
class BtLink(
    private val onPacket: (BtLink, ByteArray) -> Unit,
    private val onClosed: (BtLink) -> Unit,
) {
    companion object {
        private const val TAG = "xpadlink"

        /** Same as bt.ServiceUUID in server/bt/bt.go. */
        val SERVICE: UUID = UUID.fromString("6f1d8a52-3c1e-4b7a-9e0d-5a7c2f4b8d11")

        private const val MAGIC: Byte = 0xA7.toByte()
        private const val TYPE_STATE: Byte = 4
        private const val TYPE_MOTION: Byte = 10
        private const val MAX_PACKET = 512

        /** Paired devices as name and address. */
        fun paired(): List<Map<String, String>> =
            (BluetoothAdapter.getDefaultAdapter()?.bondedDevices ?: emptySet())
                .map { mapOf("name" to (it.name ?: it.address), "address" to it.address) }
                .sortedBy { it["name"] }
    }

    private val lock = ReentrantLock()
    private val wake = lock.newCondition()
    private val control = ArrayDeque<ByteArray>()
    private var state: ByteArray? = null
    private var motion: ByteArray? = null
    @Volatile private var closed = false
    private var socket: BluetoothSocket? = null

    /** Blocks until connected. Call from a background thread. */
    fun connect(address: String) {
        val adapter = BluetoothAdapter.getDefaultAdapter() ?: throw IOException("No Bluetooth adapter")
        if (!adapter.isEnabled) throw IOException("Bluetooth is off")
        val device = adapter.getRemoteDevice(address)
        adapter.cancelDiscovery() // discovery slows a connect down a lot
        val s = device.createRfcommSocketToServiceRecord(SERVICE)
        try {
            s.connect()
        } catch (e: IOException) {
            s.close()
            throw e
        }
        if (closed) { // closed while we were connecting
            s.close()
            throw IOException("cancelled")
        }
        socket = s
        Log.i(TAG, "bt connected to $address")
        Thread({ readLoop(s) }, "bt-read").start()
        Thread({ writeLoop(s.outputStream) }, "bt-write").start()
    }

    fun send(pkt: ByteArray) {
        lock.withLock {
            if (closed) return
            when {
                pkt.size > 1 && pkt[0] == MAGIC && pkt[1] == TYPE_STATE -> state = pkt
                pkt.size > 1 && pkt[0] == MAGIC && pkt[1] == TYPE_MOTION -> motion = pkt
                else -> control.addLast(pkt)
            }
            wake.signalAll()
        }
    }

    /** Stops accepting packets, flushes what is queued (a bye), then closes the socket. */
    fun close() {
        lock.withLock {
            if (closed) return
            closed = true
            wake.signalAll()
        }
    }

    private fun readLoop(s: BluetoothSocket) {
        try {
            val input = DataInputStream(s.inputStream.buffered())
            while (true) {
                val n = (input.readUnsignedByte()) or (input.readUnsignedByte() shl 8)
                if (n == 0 || n > MAX_PACKET) throw IOException("bad frame length $n")
                val pkt = ByteArray(n)
                input.readFully(pkt)
                onPacket(this, pkt)
            }
        } catch (e: IOException) {
            if (!closed) Log.w(TAG, "bt read ended: ${e.message}")
        } finally {
            close()
            onClosed(this)
        }
    }

    private fun writeLoop(out: OutputStream) {
        try {
            while (true) {
                val pkt = next() ?: return
                out.write(byteArrayOf(pkt.size.toByte(), (pkt.size shr 8).toByte()) + pkt)
                out.flush()
            }
        } catch (e: IOException) {
            if (!closed) Log.w(TAG, "bt write failed: ${e.message}")
            close()
        } finally {
            try { socket?.close() } catch (_: IOException) {} // wakes the reader, which reports it
        }
    }

    /** Next packet to write: control first, then the freshest state, then motion. Null once closed and flushed. */
    private fun next(): ByteArray? = lock.withLock {
        while (true) {
            control.removeFirstOrNull()?.let { return it }
            if (closed) return null
            state?.let { state = null; return it }
            motion?.let { motion = null; return it }
            wake.await()
        }
        @Suppress("UNREACHABLE_CODE") null
    }
}
