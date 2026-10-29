package com.cybereun.filemoa

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.Settings
import android.webkit.JavascriptInterface
import android.webkit.WebView
import androidx.activity.enableEdgeToEdge
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat

class MainActivity : TauriActivity() {
  private var webView: WebView? = null

  override fun onCreate(savedInstanceState: Bundle?) {
    enableEdgeToEdge()
    super.onCreate(savedInstanceState)
    // Android 15+ always draws edge to edge. Pad the content by the status bar,
    // the navigation bar and the keyboard so nothing hides under them.
    val content = findViewById<android.view.View>(android.R.id.content)
    ViewCompat.setOnApplyWindowInsetsListener(content) { view, insets ->
      val bars = insets.getInsets(
        WindowInsetsCompat.Type.systemBars() or
          WindowInsetsCompat.Type.displayCutout() or
          WindowInsetsCompat.Type.ime()
      )
      view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
      WindowInsetsCompat.CONSUMED
    }
    // FileMoa moves files by path, which needs "All files access". Ask once on
    // a fresh start; the page offers the same button afterwards.
    if (savedInstanceState == null && !hasAllFilesAccess()) {
      openAllFilesAccessSettings()
    }
  }

  override fun onWebViewCreate(webView: WebView) {
    this.webView = webView
    webView.addJavascriptInterface(Bridge(), "FileMoaAndroid")
  }

  override fun onResume() {
    super.onResume()
    // Coming back from the settings screen: let the page check the permission again.
    webView?.evaluateJavascript("window.dispatchEvent(new Event('filemoa-resume'))", null)
  }

  private fun hasAllFilesAccess(): Boolean =
    Build.VERSION.SDK_INT < Build.VERSION_CODES.R || Environment.isExternalStorageManager()

  private fun openAllFilesAccessSettings() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
    val forApp = Intent(
      Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
      Uri.parse("package:$packageName")
    )
    try {
      startActivity(forApp)
    } catch (_: Exception) {
      startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
    }
  }

  /** Called from the page as `window.FileMoaAndroid`. */
  inner class Bridge {
    @JavascriptInterface
    fun hasAllFilesAccess(): Boolean = this@MainActivity.hasAllFilesAccess()

    @JavascriptInterface
    fun openAllFilesAccessSettings() {
      runOnUiThread { this@MainActivity.openAllFilesAccessSettings() }
    }
  }
}
