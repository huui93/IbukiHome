package com.ibuki.ibukihome

import java.nio.ByteBuffer
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction

object NovelTextDecoder {
    fun decodeLegacy(bytes: ByteArray): String = Charset.forName("GB18030")
        .newDecoder()
        .onMalformedInput(CodingErrorAction.REPORT)
        .onUnmappableCharacter(CodingErrorAction.REPORT)
        .decode(ByteBuffer.wrap(bytes))
        .toString()
}
