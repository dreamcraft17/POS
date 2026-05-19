package com.epluse.eepos

import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {
  private var presenter: CustomerDisplayPresenter? = null

  override fun onResume() {
    super.onResume()
    presenter = presenter ?: CustomerDisplayPresenter(this)
    // misal auto-on kalau detect display:
    presenter?.showOnExternalDisplay()
  }

  override fun onPause() {
    presenter?.hide()
    super.onPause()
  }
}

