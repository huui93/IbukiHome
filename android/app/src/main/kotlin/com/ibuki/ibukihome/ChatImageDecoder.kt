package com.ibuki.ibukihome

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import java.io.ByteArrayOutputStream
import java.io.File

/** Reads a cached source as a sampled bitmap; full-resolution pixels never cross Flutter's channel. */
internal object ChatImageDecoder {
    private const val targetEdge = 1536
    private const val maxEncodedBytes = 2 * 1024 * 1024

    fun prepare(cacheDir: File, path: String): ByteArray {
        val source = File(path).canonicalFile
        val pickerCache = File(cacheDir, "file_picker").canonicalFile
        require(source.path.startsWith(pickerCache.path + File.separator) && source.isFile)
        try {
            return decode(source)
        } finally {
            // file_picker created this disposable copy. Never touch the original document.
            source.delete()
        }
    }

    private fun decode(source: File): ByteArray {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(source.path, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0)
        var sample = 1
        // Decode at most roughly 3072 x 3072 pixels, then resize once to the chat image size.
        while (maxOf(bounds.outWidth, bounds.outHeight) / sample > targetEdge * 2 && sample < (1 shl 30)) {
            sample *= 2
        }
        val options = BitmapFactory.Options().apply {
            inSampleSize = sample
            inScaled = false
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        var current = requireNotNull(BitmapFactory.decodeFile(source.path, options))
        try {
            val orientation = runCatching {
                ExifInterface(source.path).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL,
                )
            }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
            val matrix = Matrix().apply {
                when (orientation) {
                    ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> setScale(-1f, 1f)
                    ExifInterface.ORIENTATION_ROTATE_180 -> setRotate(180f)
                    ExifInterface.ORIENTATION_FLIP_VERTICAL -> setScale(1f, -1f)
                    ExifInterface.ORIENTATION_TRANSPOSE -> { setRotate(90f); postScale(-1f, 1f) }
                    ExifInterface.ORIENTATION_ROTATE_90 -> setRotate(90f)
                    ExifInterface.ORIENTATION_TRANSVERSE -> { setRotate(-90f); postScale(-1f, 1f) }
                    ExifInterface.ORIENTATION_ROTATE_270 -> setRotate(-90f)
                }
            }
            if (!matrix.isIdentity) {
                val oriented = Bitmap.createBitmap(current, 0, 0, current.width, current.height, matrix, true)
                if (oriented !== current) { current.recycle(); current = oriented }
            }
            if (current.hasAlpha()) {
                val flattened = Bitmap.createBitmap(current.width, current.height, Bitmap.Config.ARGB_8888)
                Canvas(flattened).apply { drawColor(Color.WHITE); drawBitmap(current, 0f, 0f, null) }
                current.recycle()
                current = flattened
            }
            var edge = targetEdge
            while (true) {
                val factor = minOf(1.0, edge.toDouble() / maxOf(current.width, current.height))
                val width = maxOf(1, (current.width * factor).toInt())
                val height = maxOf(1, (current.height * factor).toInt())
                val resized = Bitmap.createScaledBitmap(current, width, height, true)
                if (resized !== current) { current.recycle(); current = resized }
                val png = ByteArrayOutputStream().use { output ->
                    check(current.compress(Bitmap.CompressFormat.JPEG, 88, output))
                    output.toByteArray()
                }
                if (png.size <= maxEncodedBytes) return png
                // Reduce the longest edge again if this JPEG still exceeds the wire budget.
                check(edge > 64)
                edge = edge * 3 / 4
            }
        } finally {
            current.recycle()
        }
    }
}
