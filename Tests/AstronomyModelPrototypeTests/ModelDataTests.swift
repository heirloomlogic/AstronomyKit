import AstronomyModelPrototype
import Testing

@Suite("Complete Swift model prototype")
struct ModelDataTests {
    @Test("Every frozen table row and disabled segment is present")
    func completeInventory() {
        #expect(PrototypeModelData.polynomialMetadata.map(\.coefficientCount).reduce(0, +) == 1_431_768)
        #expect(PrototypeModelData.polynomialMetadata.map(\.segments).reduce(0, +) == 36_712)
        #expect(PrototypeModelData.disabledPolynomialSegmentCount == 413)
        #expect(PrototypeModelData.vsopTermCount == 35_080)
        #expect(PrototypeModelData.vsopSeries.count == 135)
        #expect(PrototypeModelData.nutationRowCount == 77)
    }

    @Test("Compiled tables retain the frozen whole-model checksum")
    func wholeModelChecksum() {
        #expect(PrototypeModelData.wholeModelFNV64() == 0x0cd4_295b_c6da_4d62)
    }

    @Test("Accessors reject indexes outside generated metadata")
    func accessBounds() {
        #expect(PrototypeModelData.polynomialBitPattern(body: .mercury, index: -1) == nil)
        #expect(PrototypeModelData.polynomialBitPattern(body: .neptune, index: 178_971) == nil)
        #expect(PrototypeModelData.polynomialValidity(body: .earth, segment: 9_177) == nil)
        #expect(PrototypeModelData.vsopTermBitPatterns(at: 35_080) == nil)
        #expect(PrototypeModelData.nutationRow(at: 77) == nil)
    }
}
