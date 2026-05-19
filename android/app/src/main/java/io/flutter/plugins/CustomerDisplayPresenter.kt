package com.epluse.eepos

import android.app.Presentation
import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.view.Display
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

class CustomerDisplayPresenter(
  private val context: Context
) {
  private var presentation: Presentation? = null
  private var engine: FlutterEngine? = null

  fun showOnExternalDisplay() {
    val dm = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
    val displays = dm.displays
    val ext = displays.firstOrNull { it.displayId != Display.DEFAULT_DISPLAY } ?: return

    // Engine khusus untuk entrypoint 'customerDisplayMain'
    engine = FlutterEngine(context).apply {
      dartExecutor.executeDartEntrypoint(
        DartExecutor.DartEntrypoint.createDefault()
      )
      // ↑ jika pakai default main(). Untuk entrypoint custom:
      // dartExecutor.executeDartEntrypoint(
      //   DartExecutor.DartEntrypoint(context.assets, "customerDisplayMain")
      // )
    }

    val fv = FlutterView(context)
    fv.attachToFlutterEngine(engine!!)
    presentation = object : Presentation(context, ext) {
      override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(fv)
      }
    }
    presentation?.show()
  }

  fun hide() {
    presentation?.dismiss()
    presentation = null
    engine?.destroy()
    engine = null
  }
}
