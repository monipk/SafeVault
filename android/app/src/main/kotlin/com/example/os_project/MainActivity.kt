package com.example.os_project

import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
        io.flutter.plugin.common.MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "safe_vault/privacy").setMethodCallHandler { call, result ->
            if (call.method == "secure") {
                if (call.arguments == true) window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                else window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                result.success(null)
            } else result.notImplemented()
        }
    }
}