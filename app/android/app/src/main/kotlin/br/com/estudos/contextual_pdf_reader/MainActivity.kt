package br.com.estudos.contextual_pdf_reader

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.net.ConnectivityManager
import android.net.NetworkCapabilities

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "br.com.estudos.reader/diagnostics")
            .setMethodCallHandler { call, result ->
                if (call.method == "networkStatus") {
                    val manager = getSystemService(ConnectivityManager::class.java)
                    val caps = manager.getNetworkCapabilities(manager.activeNetwork)
                    result.success(mapOf("connected" to (caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true),
                        "validated" to (caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true)))
                } else result.notImplemented()
            }
    }
}
