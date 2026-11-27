//
//  EngineVsop.swift
//  AstronomyKit
//
//  Pure-Swift VSOP87B planetary series evaluator (FMA SIMD2 polynomial
//  cosine/sine in Release and non-Apple builds, thread-local whole-planet
//  Accelerate batching in Apple Debug builds) plus Solar System Barycenter
//  and major-body barycentric states.
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

#if ASTRONOMYKIT_SERIES_ACCELERATE && canImport(Accelerate)
import Accelerate

enum VsopDebugScratch {
    /// Maximum contiguous slot span across all 8 planets is Mars (298); 304 keeps 16-byte alignment.
    static let maxSpan = 304

    private static let key: pthread_key_t? = {
        var k = pthread_key_t()
        guard pthread_key_create(&k, { free($0) }) == 0 else {
            return nil
        }
        return k
    }()

    static func buffer() -> UnsafeMutablePointer<Double>? {
        guard let key else { return nil }
        if let existing = pthread_getspecific(key) {
            return existing.assumingMemoryBound(to: Double.self)
        }
        let count = maxSpan * 3
        guard let raw = malloc(count * MemoryLayout<Double>.stride) else { return nil }
        guard pthread_setspecific(key, raw) == 0 else {
            free(raw)
            return nil
        }
        return raw.bindMemory(to: Double.self, capacity: count)
    }
}
#endif

enum EngineVsop {
    static func bodyIndex(for body: CelestialBody) -> Int? {
        switch body {
        case .mercury: return 0
        case .venus: return 1
        case .earth: return 2
        case .mars: return 3
        case .jupiter: return 4
        case .saturn: return 5
        case .uranus: return 6
        case .neptune: return 7
        default: return nil
        }
    }

    @inline(__always)
    private static func seriesWrapOne(_ x: Double) -> Double {
        let round = 0x1.8p52
        let k = round.addingProduct(x, 0x1.45F306DC9C883p-3) - round
        var y = x.addingProduct(k, -0x1.921FB54400000p+2)
        y = y.addingProduct(k, -0x1.0B4611A600000p-32)
        return y.addingProduct(k, -0x1.3198A2E037073p-67)
    }

    @inline(__always)
    private static func vsopRotate(_ ex: Double, _ ey: Double, _ ez: Double) -> EngineVec3 {
        EngineVec3(
            x: ex + 0.000000440360 * ey - 0.000000190919 * ez,
            y: -0.000000479966 * ex + 0.917482137087 * ey - 0.397776982902 * ez,
            z: 0.397776982902 * ey + 0.917482137087 * ez
        )
    }

    #if !(ASTRONOMYKIT_SERIES_ACCELERATE && canImport(Accelerate))
    @inline(__always)
    private static func seriesWrap(_ x: SIMD2<Double>) -> SIMD2<Double> {
        let vRound = SIMD2<Double>(repeating: 0x1.8p52)
        let k = vRound.addingProduct(x, SIMD2<Double>(repeating: 0x1.45F306DC9C883p-3)) - vRound
        var y = x.addingProduct(k, SIMD2<Double>(repeating: -0x1.921FB54400000p+2))
        y = y.addingProduct(k, SIMD2<Double>(repeating: -0x1.0B4611A600000p-32))
        return y.addingProduct(k, SIMD2<Double>(repeating: -0x1.3198A2E037073p-67))
    }

    @inline(__always)
    static func seriesHalfCos(_ w: SIMD2<Double>) -> SIMD2<Double> {
        var r = SIMD2<Double>(repeating: 0x1.9f23c5f3847cbp-61)
        r = SIMD2<Double>(repeating: -0x1.9350a435543dbp-51).addingProduct(w, r)
        r = SIMD2<Double>(repeating: 0x1.1eecdf3979d83p-41).addingProduct(w, r)
        r = SIMD2<Double>(repeating: -0x1.27e4f97932a13p-32).addingProduct(w, r)
        r = SIMD2<Double>(repeating: 0x1.a01a01994c338p-24).addingProduct(w, r)
        r = SIMD2<Double>(repeating: -0x1.6c16c16c09b4ep-16).addingProduct(w, r)
        r = SIMD2<Double>(repeating: 0x1.55555555553c4p-9).addingProduct(w, r)
        r = SIMD2<Double>(repeating: -0x1.ffffffffffffbp-4).addingProduct(w, r)
        return SIMD2<Double>(repeating: 1.0).addingProduct(w, r)
    }

    @inline(__always)
    static func seriesHalfSinc(_ w: SIMD2<Double>) -> SIMD2<Double> {
        var r = SIMD2<Double>(repeating: 0x1.88386468b9715p-65)
        r = SIMD2<Double>(repeating: -0x1.ae439ef7766b1p-55).addingProduct(w, r)
        r = SIMD2<Double>(repeating: 0x1.6123ccd995369p-45).addingProduct(w, r)
        r = SIMD2<Double>(repeating: -0x1.ae6454d0761e5p-36).addingProduct(w, r)
        r = SIMD2<Double>(repeating: 0x1.71de3a528d198p-27).addingProduct(w, r)
        r = SIMD2<Double>(repeating: -0x1.a01a01a0147f4p-19).addingProduct(w, r)
        r = SIMD2<Double>(repeating: 0x1.11111111110bcp-11).addingProduct(w, r)
        r = SIMD2<Double>(repeating: -0x1.5555555555555p-5).addingProduct(w, r)
        return SIMD2<Double>(repeating: 1.0).addingProduct(w, r)
    }

    @inline(__always)
    private static func seriesSinCos(
        _ x: SIMD2<Double>
    ) -> (sine: SIMD2<Double>, cosine: SIMD2<Double>) {
        let y = seriesWrap(x)
        let w = y * y
        let c = seriesHalfCos(w)
        let s = y * seriesHalfSinc(w) * c
        let c2 = SIMD2<Double>(repeating: -1.0).addingProduct(c + c, c)
        return (s, c2)
    }

    @inline(__always)
    private static func seriesSumCosSIMD(
        amp: UnsafePointer<Double>,
        phase: UnsafePointer<Double>,
        freq: UnsafePointer<Double>,
        evenCount: Int,
        t: Double
    ) -> Double {
        let vNegOne = SIMD2<Double>(repeating: -1.0)
        let vt = SIMD2<Double>(repeating: t)
        var cosPair0 = SIMD2<Double>.zero
        var cosPair1 = SIMD2<Double>.zero
        var i = 0
        while i &+ 3 < evenCount {
            let p0 = UnsafeRawPointer(phase + i).loadUnaligned(as: SIMD2<Double>.self)
            let f0 = UnsafeRawPointer(freq + i).loadUnaligned(as: SIMD2<Double>.self)
            let a0 = UnsafeRawPointer(amp + i).loadUnaligned(as: SIMD2<Double>.self)
            let p1 = UnsafeRawPointer(phase + (i &+ 2)).loadUnaligned(as: SIMD2<Double>.self)
            let f1 = UnsafeRawPointer(freq + (i &+ 2)).loadUnaligned(as: SIMD2<Double>.self)
            let a1 = UnsafeRawPointer(amp + (i &+ 2)).loadUnaligned(as: SIMD2<Double>.self)

            let x0 = p0.addingProduct(vt, f0)
            let x1 = p1.addingProduct(vt, f1)
            let y0 = seriesWrap(x0)
            let y1 = seriesWrap(x1)
            let c0 = seriesHalfCos(y0 * y0)
            let c1 = seriesHalfCos(y1 * y1)
            let cos0 = vNegOne.addingProduct(c0 + c0, c0)
            let cos1 = vNegOne.addingProduct(c1 + c1, c1)
            cosPair0 = cosPair0.addingProduct(a0, cos0)
            cosPair1 = cosPair1.addingProduct(a1, cos1)
            i &+= 4
        }
        if i < evenCount {
            let p = UnsafeRawPointer(phase + i).loadUnaligned(as: SIMD2<Double>.self)
            let f = UnsafeRawPointer(freq + i).loadUnaligned(as: SIMD2<Double>.self)
            let a = UnsafeRawPointer(amp + i).loadUnaligned(as: SIMD2<Double>.self)
            let x = p.addingProduct(vt, f)
            let y = seriesWrap(x)
            let c = seriesHalfCos(y * y)
            let cosVal = vNegOne.addingProduct(c + c, c)
            cosPair0 = cosPair0.addingProduct(a, cosVal)
        }
        let sum = cosPair0 + cosPair1
        return sum.x + sum.y
    }

    @inline(__always)
    private static func seriesSumSinCosSIMD(
        amp: UnsafePointer<Double>,
        ampFreq: UnsafePointer<Double>,
        phase: UnsafePointer<Double>,
        freq: UnsafePointer<Double>,
        evenCount: Int,
        t: Double
    ) -> (cosSum: Double, sinSum: Double) {
        let vNegOne = SIMD2<Double>(repeating: -1.0)
        let vt = SIMD2<Double>(repeating: t)
        var cosPair = SIMD2<Double>.zero
        var sinPair = SIMD2<Double>.zero
        var i = 0
        while i < evenCount {
            let p = UnsafeRawPointer(phase + i).loadUnaligned(as: SIMD2<Double>.self)
            let f = UnsafeRawPointer(freq + i).loadUnaligned(as: SIMD2<Double>.self)
            let a = UnsafeRawPointer(amp + i).loadUnaligned(as: SIMD2<Double>.self)
            let af = UnsafeRawPointer(ampFreq + i).loadUnaligned(as: SIMD2<Double>.self)
            let x = p.addingProduct(vt, f)
            let y = seriesWrap(x)
            let w = y * y
            let c = seriesHalfCos(w)
            let cosVal = vNegOne.addingProduct(c + c, c)
            let sinVal = y * seriesHalfSinc(w) * c
            cosPair = cosPair.addingProduct(a, cosVal)
            sinPair = sinPair.addingProduct(af, sinVal)
            i &+= 2
        }
        return (cosPair.x + cosPair.y, sinPair.x + sinPair.y)
    }

    @inline(__always)
    private static func evalFormulaCos(
        _ fDesc: VsopFormulaDesc,
        table: VsopTableStorage,
        t: Double,
        wrap: Bool
    ) -> Double {
        let ampBase = table.amp
        let phaseBase = table.phase
        let freqBase = table.freq
        let seriesArr = table.series
        var tpower = 1.0
        var acc = 0.0
        var s = 0
        while s < fDesc.seriesCount {
            let sd = seriesArr[fDesc.seriesOffset &+ s]
            if sd.evenCount > 0 {
                var incr =
                    tpower
                    * seriesSumCosSIMD(
                        amp: ampBase + sd.offset,
                        phase: phaseBase + sd.offset,
                        freq: freqBase + sd.offset,
                        evenCount: sd.evenCount,
                        t: t
                    )
                if wrap {
                    incr = seriesWrapOne(incr)
                }
                acc += incr
            }
            tpower *= t
            s &+= 1
        }
        return acc
    }

    @inline(__always)
    private static func evalFormulaSinCos(
        _ fDesc: VsopFormulaDesc,
        table: VsopTableStorage,
        t: Double,
        wrap: Bool
    ) -> (coord: Double, deriv: Double) {
        let ampBase = table.amp
        let ampFreqBase = table.ampFreq
        let phaseBase = table.phase
        let freqBase = table.freq
        let seriesArr = table.series
        var tpower = 1.0
        var dpower = 0.0
        var sAcc = 0.0
        var dAcc = 0.0
        var s = 0
        while s < fDesc.seriesCount {
            let sd = seriesArr[fDesc.seriesOffset &+ s]
            if sd.evenCount > 0 {
                let (cosSum, sinSum) = seriesSumSinCosSIMD(
                    amp: ampBase + sd.offset,
                    ampFreq: ampFreqBase + sd.offset,
                    phase: phaseBase + sd.offset,
                    freq: freqBase + sd.offset,
                    evenCount: sd.evenCount,
                    t: t
                )
                var incr = tpower * cosSum
                if wrap {
                    incr = seriesWrapOne(incr)
                }
                sAcc += incr
                dAcc += (Double(s) * dpower * cosSum) - (tpower * sinSum)
            }
            dpower = tpower
            tpower *= t
            s &+= 1
        }
        return (sAcc, dAcc)
    }
    #endif

    /// Evaluates heliocentric J2000 equatorial position for planet index 0 (Mercury) ... 7 (Neptune).
    static func calcVsop(bodyIndex: Int, tt: Double) -> EngineVec3 {
        let t = tt / 365_250.0
        let table = VsopTableStorage.shared
        let fBase = table.formulas + (bodyIndex &* 3)

        #if ASTRONOMYKIT_SERIES_ACCELERATE && canImport(Accelerate)
        let ampBase = table.amp
        let phaseBase = table.phase
        let freqBase = table.freq
        let seriesArr = table.series
        let span = table.spans[bodyIndex]

        var lon = 0.0
        var lat = 0.0
        var rad = 0.0

        if let scratch = VsopDebugScratch.buffer() {
            let angleBuf = scratch
            let cosBuf = scratch + VsopDebugScratch.maxSpan
            let baseOff = span.offset
            var tVar = t
            var n32 = Int32(truncatingIfNeeded: span.span)
            vDSP_vsmaD(
                freqBase + baseOff,
                1,
                &tVar,
                phaseBase + baseOff,
                1,
                angleBuf,
                1,
                vDSP_Length(bitPattern: span.span)
            )
            vvcos(cosBuf, angleBuf, &n32)

            var k = 0
            while k < 3 {
                let fDesc = fBase[k]
                var tpower = 1.0
                var acc = 0.0
                var s = 0
                while s < fDesc.seriesCount {
                    let sd = seriesArr[fDesc.seriesOffset &+ s]
                    let n = sd.count
                    if n > 0 {
                        let aPtr = ampBase + sd.offset
                        let cPtr = cosBuf + (sd.offset &- baseOff)
                        var cosSum = 0.0
                        if n >= 8 {
                            vDSP_dotprD(aPtr, 1, cPtr, 1, &cosSum, vDSP_Length(bitPattern: n))
                        } else {
                            var i = 0
                            while i < n {
                                cosSum += aPtr[i] * cPtr[i]
                                i &+= 1
                            }
                        }
                        var incr = tpower * cosSum
                        if k == 0 {
                            incr = seriesWrapOne(incr)
                        }
                        acc += incr
                    }
                    tpower *= t
                    s &+= 1
                }
                if k == 0 {
                    lon = acc
                } else if k == 1 {
                    lat = acc
                } else {
                    rad = acc
                }
                k &+= 1
            }
        } else {
            lon = evalFormulaCosScalar(fBase[0], table: table, t: t, wrap: true)
            lat = evalFormulaCosScalar(fBase[1], table: table, t: t, wrap: false)
            rad = evalFormulaCosScalar(fBase[2], table: table, t: t, wrap: false)
        }

        let sinLon = sin(lon)
        let cosLon = cos(lon)
        let sinLat = sin(lat)
        let cosLat = cos(lat)
        let rCosLat = rad * cosLat
        return vsopRotate(rCosLat * cosLon, rCosLat * sinLon, rad * sinLat)
        #else
        let lon = evalFormulaCos(fBase[0], table: table, t: t, wrap: true)
        let lat = evalFormulaCos(fBase[1], table: table, t: t, wrap: false)
        let rad = evalFormulaCos(fBase[2], table: table, t: t, wrap: false)
        let (sine, cosine) = seriesSinCos(SIMD2<Double>(lon, lat))
        let rCosLat = rad * cosine.y
        return vsopRotate(rCosLat * cosine.x, rCosLat * sine.x, rad * sine.y)
        #endif
    }

    /// Evaluates heliocentric J2000 equatorial position and velocity for planet index 0 ... 7.
    static func calcVsopPosVel(bodyIndex: Int, tt: Double) -> EngineBodyState {
        let t = tt / 365_250.0
        let table = VsopTableStorage.shared
        let fBase = table.formulas + (bodyIndex &* 3)

        #if ASTRONOMYKIT_SERIES_ACCELERATE && canImport(Accelerate)
        let ampBase = table.amp
        let ampFreqBase = table.ampFreq
        let phaseBase = table.phase
        let freqBase = table.freq
        let seriesArr = table.series
        let span = table.spans[bodyIndex]

        var lon = 0.0
        var lat = 0.0
        var rad = 0.0
        var dLon = 0.0
        var dLat = 0.0
        var dRad = 0.0

        if let scratch = VsopDebugScratch.buffer() {
            let angleBuf = scratch
            let cosBuf = scratch + VsopDebugScratch.maxSpan
            let sinBuf = cosBuf + VsopDebugScratch.maxSpan
            let baseOff = span.offset
            var tVar = t
            var n32 = Int32(truncatingIfNeeded: span.span)
            vDSP_vsmaD(
                freqBase + baseOff,
                1,
                &tVar,
                phaseBase + baseOff,
                1,
                angleBuf,
                1,
                vDSP_Length(bitPattern: span.span)
            )
            vvsincos(sinBuf, cosBuf, angleBuf, &n32)

            var k = 0
            while k < 3 {
                let fDesc = fBase[k]
                var tpower = 1.0
                var dpower = 0.0
                var sAcc = 0.0
                var dAcc = 0.0
                var s = 0
                while s < fDesc.seriesCount {
                    let sd = seriesArr[fDesc.seriesOffset &+ s]
                    let n = sd.count
                    if n > 0 {
                        let aPtr = ampBase + sd.offset
                        let afPtr = ampFreqBase + sd.offset
                        let rel = sd.offset &- baseOff
                        let cPtr = cosBuf + rel
                        let sPtr = sinBuf + rel
                        var cosSum = 0.0
                        var sinSum = 0.0
                        if n >= 8 {
                            let nLen = vDSP_Length(bitPattern: n)
                            vDSP_dotprD(aPtr, 1, cPtr, 1, &cosSum, nLen)
                            vDSP_dotprD(afPtr, 1, sPtr, 1, &sinSum, nLen)
                        } else {
                            var i = 0
                            while i < n {
                                cosSum += aPtr[i] * cPtr[i]
                                sinSum += afPtr[i] * sPtr[i]
                                i &+= 1
                            }
                        }
                        var incr = tpower * cosSum
                        if k == 0 {
                            incr = seriesWrapOne(incr)
                        }
                        sAcc += incr
                        dAcc += (Double(s) * dpower * cosSum) - (tpower * sinSum)
                    }
                    dpower = tpower
                    tpower *= t
                    s &+= 1
                }
                if k == 0 {
                    lon = sAcc
                    dLon = dAcc
                } else if k == 1 {
                    lat = sAcc
                    dLat = dAcc
                } else {
                    rad = sAcc
                    dRad = dAcc
                }
                k &+= 1
            }
        } else {
            (lon, dLon) = evalFormulaSinCosScalar(fBase[0], table: table, t: t, wrap: true)
            (lat, dLat) = evalFormulaSinCosScalar(fBase[1], table: table, t: t, wrap: false)
            (rad, dRad) = evalFormulaSinCosScalar(fBase[2], table: table, t: t, wrap: false)
        }

        let sinLon = sin(lon)
        let cosLon = cos(lon)
        let sinLat = sin(lat)
        let cosLat = cos(lat)
        #else
        let (lon, dLon) = evalFormulaSinCos(fBase[0], table: table, t: t, wrap: true)
        let (lat, dLat) = evalFormulaSinCos(fBase[1], table: table, t: t, wrap: false)
        let (rad, dRad) = evalFormulaSinCos(fBase[2], table: table, t: t, wrap: false)
        let (sine, cosine) = seriesSinCos(SIMD2<Double>(lon, lat))
        let cosLon = cosine.x
        let sinLon = sine.x
        let cosLat = cosine.y
        let sinLat = sine.y
        #endif

        let r = vsopRotate(rad * cosLat * cosLon, rad * cosLat * sinLon, rad * sinLat)
        let evx =
            (dRad * cosLat * cosLon) - (rad * sinLat * cosLon * dLat)
            - (rad * cosLat * sinLon * dLon)
        let evy =
            (dRad * cosLat * sinLon) - (rad * sinLat * sinLon * dLat)
            + (rad * cosLat * cosLon * dLon)
        let evz = (dRad * sinLat) + (rad * cosLat * dLat)
        let v = vsopRotate(evx, evy, evz)
        let invM = 1.0 / 365_250.0
        return EngineBodyState(
            tt: tt,
            r: r,
            v: EngineVec3(x: v.x * invM, y: v.y * invM, z: v.z * invM)
        )
    }

    /// Evaluates only the radial component (heliocentric distance in AU) for planet index 0 ... 7.
    static func vsopHelioDistance(bodyIndex: Int, tt: Double) -> Double {
        let t = tt / 365_250.0
        let table = VsopTableStorage.shared
        let fDesc = table.formulas[bodyIndex &* 3 &+ 2]

        #if ASTRONOMYKIT_SERIES_ACCELERATE && canImport(Accelerate)
        let ampBase = table.amp
        let phaseBase = table.phase
        let freqBase = table.freq
        let seriesArr = table.series
        let span = table.spans[bodyIndex]

        var distance = 0.0
        var tpower = 1.0

        guard let scratch = VsopDebugScratch.buffer() else {
            return evalFormulaCosScalar(fDesc, table: table, t: t, wrap: false)
        }
        let angleBuf = scratch
        let cosBuf = scratch + VsopDebugScratch.maxSpan
        let baseOff = span.radOffset
        var tVar = t
        var n32 = Int32(truncatingIfNeeded: span.radSpan)
        vDSP_vsmaD(
            freqBase + baseOff,
            1,
            &tVar,
            phaseBase + baseOff,
            1,
            angleBuf,
            1,
            vDSP_Length(bitPattern: span.radSpan)
        )
        vvcos(cosBuf, angleBuf, &n32)

        var s = 0
        while s < fDesc.seriesCount {
            let sd = seriesArr[fDesc.seriesOffset &+ s]
            let n = sd.count
            if n > 0 {
                let aPtr = ampBase + sd.offset
                let cPtr = cosBuf + (sd.offset &- baseOff)
                var cosSum = 0.0
                if n >= 8 {
                    vDSP_dotprD(aPtr, 1, cPtr, 1, &cosSum, vDSP_Length(bitPattern: n))
                } else {
                    var i = 0
                    while i < n {
                        cosSum += aPtr[i] * cPtr[i]
                        i &+= 1
                    }
                }
                distance += tpower * cosSum
            }
            tpower *= t
            s &+= 1
        }
        return distance
        #else
        return evalFormulaCos(fDesc, table: table, t: t, wrap: false)
        #endif
    }

    #if ASTRONOMYKIT_SERIES_ACCELERATE && canImport(Accelerate)
    private static func evalFormulaCosScalar(
        _ fDesc: VsopFormulaDesc,
        table: VsopTableStorage,
        t: Double,
        wrap: Bool
    ) -> Double {
        var tpower = 1.0
        var acc = 0.0
        var s = 0
        while s < fDesc.seriesCount {
            let sd = table.series[fDesc.seriesOffset &+ s]
            let n = sd.count
            if n > 0 {
                let aPtr = table.amp + sd.offset
                let pPtr = table.phase + sd.offset
                let fPtr = table.freq + sd.offset
                var cosSum = 0.0
                var i = 0
                while i < n {
                    cosSum += aPtr[i] * cos(pPtr[i] + t * fPtr[i])
                    i &+= 1
                }
                var incr = tpower * cosSum
                if wrap {
                    incr = seriesWrapOne(incr)
                }
                acc += incr
            }
            tpower *= t
            s &+= 1
        }
        return acc
    }

    private static func evalFormulaSinCosScalar(
        _ fDesc: VsopFormulaDesc,
        table: VsopTableStorage,
        t: Double,
        wrap: Bool
    ) -> (coord: Double, deriv: Double) {
        var tpower = 1.0
        var dpower = 0.0
        var sAcc = 0.0
        var dAcc = 0.0
        var s = 0
        while s < fDesc.seriesCount {
            let sd = table.series[fDesc.seriesOffset &+ s]
            let n = sd.count
            if n > 0 {
                let aPtr = table.amp + sd.offset
                let afPtr = table.ampFreq + sd.offset
                let pPtr = table.phase + sd.offset
                let fPtr = table.freq + sd.offset
                var cosSum = 0.0
                var sinSum = 0.0
                var i = 0
                while i < n {
                    let ang = pPtr[i] + t * fPtr[i]
                    cosSum += aPtr[i] * cos(ang)
                    sinSum += afPtr[i] * sin(ang)
                    i &+= 1
                }
                var incr = tpower * cosSum
                if wrap {
                    incr = seriesWrapOne(incr)
                }
                sAcc += incr
                dAcc += (Double(s) * dpower * cosSum) - (tpower * sinSum)
            }
            dpower = tpower
            tpower *= t
            s &+= 1
        }
        return (sAcc, dAcc)
    }
    #endif

    // MARK: - Solar System Barycenter & Major Body Barycentric States

    static func calcSolarSystemBarycenter(tt: Double) -> EngineVec3 {
        let sunGM = EngineConstants.sunGM
        let jGM = EngineConstants.jupiterGM
        let sGM = EngineConstants.saturnGM
        let uGM = EngineConstants.uranusGM
        let nGM = EngineConstants.neptuneGM

        let j = calcVsop(bodyIndex: 4, tt: tt)
        let s = calcVsop(bodyIndex: 5, tt: tt)
        let u = calcVsop(bodyIndex: 6, tt: tt)
        let n = calcVsop(bodyIndex: 7, tt: tt)

        let jShift = jGM / (jGM + sunGM)
        let sShift = sGM / (sGM + sunGM)
        let uShift = uGM / (uGM + sunGM)
        let nShift = nGM / (nGM + sunGM)

        var x = jShift * j.x
        var y = jShift * j.y
        var z = jShift * j.z
        x += sShift * s.x
        y += sShift * s.y
        z += sShift * s.z
        x += uShift * u.x
        y += uShift * u.y
        z += uShift * u.z
        x += nShift * n.x
        y += nShift * n.y
        z += nShift * n.z
        return EngineVec3(x: x, y: y, z: z)
    }

    static func majorBodyBary(tt: Double) -> EngineMajorBodies {
        let sunGM = EngineConstants.sunGM
        let jGM = EngineConstants.jupiterGM
        let sGM = EngineConstants.saturnGM
        let uGM = EngineConstants.uranusGM
        let nGM = EngineConstants.neptuneGM

        let j = calcVsopPosVel(bodyIndex: 4, tt: tt)
        let s = calcVsopPosVel(bodyIndex: 5, tt: tt)
        let u = calcVsopPosVel(bodyIndex: 6, tt: tt)
        let n = calcVsopPosVel(bodyIndex: 7, tt: tt)

        let jShift = jGM / (jGM + sunGM)
        let sShift = sGM / (sGM + sunGM)
        let uShift = uGM / (uGM + sunGM)
        let nShift = nGM / (nGM + sunGM)

        var sx = jShift * j.r.x
        var sy = jShift * j.r.y
        var sz = jShift * j.r.z
        var svx = jShift * j.v.x
        var svy = jShift * j.v.y
        var svz = jShift * j.v.z

        sx += sShift * s.r.x
        sy += sShift * s.r.y
        sz += sShift * s.r.z
        svx += sShift * s.v.x
        svy += sShift * s.v.y
        svz += sShift * s.v.z

        sx += uShift * u.r.x
        sy += uShift * u.r.y
        sz += uShift * u.r.z
        svx += uShift * u.v.x
        svy += uShift * u.v.y
        svz += uShift * u.v.z

        sx += nShift * n.r.x
        sy += nShift * n.r.y
        sz += nShift * n.r.z
        svx += nShift * n.v.x
        svy += nShift * n.v.y
        svz += nShift * n.v.z

        return EngineMajorBodies(
            sun: EngineBodyState(
                tt: tt,
                r: EngineVec3(x: -sx, y: -sy, z: -sz),
                v: EngineVec3(x: -svx, y: -svy, z: -svz)
            ),
            jupiter: EngineBodyState(
                tt: tt,
                r: EngineVec3(x: j.r.x - sx, y: j.r.y - sy, z: j.r.z - sz),
                v: EngineVec3(x: j.v.x - svx, y: j.v.y - svy, z: j.v.z - svz)
            ),
            saturn: EngineBodyState(
                tt: tt,
                r: EngineVec3(x: s.r.x - sx, y: s.r.y - sy, z: s.r.z - sz),
                v: EngineVec3(x: s.v.x - svx, y: s.v.y - svy, z: s.v.z - svz)
            ),
            uranus: EngineBodyState(
                tt: tt,
                r: EngineVec3(x: u.r.x - sx, y: u.r.y - sy, z: u.r.z - sz),
                v: EngineVec3(x: u.v.x - svx, y: u.v.y - svy, z: u.v.z - svz)
            ),
            neptune: EngineBodyState(
                tt: tt,
                r: EngineVec3(x: n.r.x - sx, y: n.r.y - sy, z: n.r.z - sz),
                v: EngineVec3(x: n.v.x - svx, y: n.v.y - svy, z: n.v.z - svz)
            )
        )
    }
}
