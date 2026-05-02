package com.example.flut_bt_dual_scanner_1

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.UUID

class MainActivity : FlutterActivity() {

    private val channelName = "classic_bluetooth_scanner"
    private val bluetoothAdapter: BluetoothAdapter? = BluetoothAdapter.getDefaultAdapter()

    private val foundDevices = mutableListOf<Map<String, String>>()
    private var classicSocket: BluetoothSocket? = null

    private val sppUuid: UUID =
        UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == BluetoothDevice.ACTION_FOUND) {
                val device: BluetoothDevice? =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(
                            BluetoothDevice.EXTRA_DEVICE,
                            BluetoothDevice::class.java
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                    }

                device?.let {
                    if (!hasConnectPermission()) return

                    val name = it.name ?: "Unknown Classic Device"
                    val address = it.address ?: "No address"

                    if (foundDevices.none { d -> d["address"] == address }) {
                        foundDevices.add(
                            mapOf(
                                "name" to name,
                                "address" to address,
                                "type" to "Classic"
                            )
                        )
                    }
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                "getPairedDevices" -> {
                    result.success(getPairedDevices())
                }

                "startClassicScan" -> {
                    foundDevices.clear()
                    startClassicDiscovery()
                    result.success(true)
                }

                "getClassicScanResults" -> {
                    result.success(foundDevices)
                }

                "stopClassicScan" -> {
                    stopClassicDiscovery()
                    result.success(true)
                }

                "connectClassic" -> {
                    val address = call.argument<String>("address")
                    if (address == null) {
                        result.success(
                            mapOf(
                                "success" to false,
                                "message" to "No Bluetooth address provided."
                            )
                        )
                    } else {
                        result.success(connectClassic(address))
                    }
                }

                "disconnectClassic" -> {
                    disconnectClassic()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun hasConnectPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                ActivityCompat.checkSelfPermission(
                    this,
                    Manifest.permission.BLUETOOTH_CONNECT
                ) == PackageManager.PERMISSION_GRANTED
    }

    private fun hasScanPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                ActivityCompat.checkSelfPermission(
                    this,
                    Manifest.permission.BLUETOOTH_SCAN
                ) == PackageManager.PERMISSION_GRANTED
    }

    private fun getPairedDevices(): List<Map<String, String>> {
        if (bluetoothAdapter == null) return emptyList()
        if (!hasConnectPermission()) return emptyList()

        return bluetoothAdapter.bondedDevices.map {
            mapOf(
                "name" to (it.name ?: "Unknown Paired Device"),
                "address" to it.address,
                "type" to "Classic Paired"
            )
        }
    }

    private fun startClassicDiscovery() {
        if (bluetoothAdapter == null) return
        if (!hasScanPermission()) return

        try {
            val filter = IntentFilter(BluetoothDevice.ACTION_FOUND)
            registerReceiver(receiver, filter)
        } catch (_: Exception) {
        }

        try {
            if (bluetoothAdapter.isDiscovering) {
                bluetoothAdapter.cancelDiscovery()
            }

            bluetoothAdapter.startDiscovery()
        } catch (_: Exception) {
        }
    }

    private fun stopClassicDiscovery() {
        try {
            if (hasScanPermission()) {
                bluetoothAdapter?.cancelDiscovery()
            }
        } catch (_: Exception) {
        }

        try {
            unregisterReceiver(receiver)
        } catch (_: Exception) {
        }
    }

    private fun connectClassic(address: String): Map<String, Any> {
        if (bluetoothAdapter == null) {
            return mapOf(
                "success" to false,
                "message" to "Bluetooth adapter not available."
            )
        }

        if (!hasConnectPermission()) {
            return mapOf(
                "success" to false,
                "message" to "Missing BLUETOOTH_CONNECT permission."
            )
        }

        return try {
            stopClassicDiscovery()
            disconnectClassic()

            val device = bluetoothAdapter.getRemoteDevice(address)
            val socket = device.createRfcommSocketToServiceRecord(sppUuid)

            socket.connect()
            classicSocket = socket

            mapOf(
                "success" to true,
                "message" to "Classic Bluetooth connection successful."
            )

        } catch (e: IOException) {
            tryReflectionFallback(address, e.message ?: "Classic connection failed.")
        } catch (e: Exception) {
            mapOf(
                "success" to false,
                "message" to "Classic connection failed: ${e.message}"
            )
        }
    }

    private fun tryReflectionFallback(address: String, originalError: String): Map<String, Any> {
        return try {
            val device = bluetoothAdapter!!.getRemoteDevice(address)

            val method = device.javaClass.getMethod(
                "createRfcommSocket",
                Int::class.javaPrimitiveType
            )

            val socket = method.invoke(device, 1) as BluetoothSocket
            socket.connect()
            classicSocket = socket

            mapOf(
                "success" to true,
                "message" to "Classic Bluetooth connection successful using fallback socket."
            )

        } catch (e: Exception) {
            mapOf(
                "success" to false,
                "message" to "Classic connection failed. Main error: $originalError. Fallback error: ${e.message}"
            )
        }
    }

    private fun disconnectClassic() {
        try {
            classicSocket?.close()
            classicSocket = null
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        stopClassicDiscovery()
        disconnectClassic()
        super.onDestroy()
    }
}