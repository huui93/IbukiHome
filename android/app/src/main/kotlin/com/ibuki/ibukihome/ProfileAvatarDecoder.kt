package com.ibuki.ibukihome

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import java.io.ByteArrayOutputStream
import java.io.File

/** Reads a cached source as a sampled bitmap; full-resolution pixels never cross Flutter's channel. */
internal object ProfileAvatarDecoder {
    private const val targetEdge = 256
    private const val maxEncodedBytes = 256 * 1024

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
        // Decode at most roughly 512 x 512 pixels, then resize once to the avatar size.
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
            var edge = targetEdge
            while (true) {
                val factor = minOf(1.0, edge.toDouble() / maxOf(current.width, current.height))
                val width = maxOf(1, (current.width * factor).toInt())
                val height = maxOf(1, (current.height * factor).toInt())
                val resized = Bitmap.createScaledBitmap(current, width, height, true)
                if (resized !== current) { current.recycle(); current = resized }
                val png = ByteArrayOutputStream().use { output ->
                    check(current.compress(Bitmap.CompressFormat.PNG, 100, output))
                    output.toByteArray()
                }
                if (png.size <= maxEncodedBytes) return png
                // Incompressible alpha images can exceed 256 KiB by PNG overhead alone.
                check(edge > 64)
                edge = edge * 3 / 4
            }
        } finally {
            current.recycle()
        }
    }
}
