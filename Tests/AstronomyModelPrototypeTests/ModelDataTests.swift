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

    @Test("VSOP term triplets preserve bits across every storage seam")
    func vsopTripletSeams() throws {
        // Literal expectations come from the frozen pre-partition VSOP source at e231373c.
        let fixtures: [(Int, UInt64, UInt64, UInt64)] = [
            (0, 0x4011_9c2a_d254_5ec7, 0x0000_0000_0000_0000, 0x0000_0000_0000_0000),
            (5460, 0x3dd0_7e1f_e91b_0b70, 0x4012_4ab6_2d03_df55, 0x40e1_316f_5b50_18cb),
            (5461, 0x3dd0_7e1f_e91b_0b70, 0x4015_7caf_8cfe_893b, 0x40e9_ecb7_91f9_6cad),
            (5462, 0x3dd0_7e1f_e91b_0b70, 0x3fff_f2a2_f06e_0655, 0x40ff_d83a_2663_cacc),
            (10921, 0x3dfd_8ca3_d6fb_1f29, 0x4015_1f09_512e_392d, 0x40d1_613d_62fd_161b),
            (10922, 0x3e02_8de3_e63e_6cde, 0x4004_bbec_4f93_4aff, 0x40d6_5f9c_97cd_c5c5),
            (10923, 0x3e02_e5d9_e5c4_5270, 0x3fb4_73a9_5ab8_d06f, 0x40f4_60b2_806c_057e),
            (16383, 0x3e12_35ed_e6b8_874c, 0x4010_c777_f429_7059, 0x40c1_c13c_b25d_4537),
            (16384, 0x3e0a_ccf3_dacb_f296, 0x4011_2d54_98e1_cc58, 0x4067_7d9a_cf7b_0ab5),
            (16385, 0x3e0a_ccf3_dacb_f296, 0x4015_8aeb_d78b_6102, 0x40a4_bf23_01b7_85d6),
            (21844, 0x3e59_7ada_4ca1_482c, 0x400b_95f1_f3e3_102a, 0x406e_3bde_710f_275e),
            (21845, 0x3e57_5259_1fa0_3e2c, 0x3ff6_aa8c_ed97_5047, 0x4037_936c_6dab_b0f2),
            (21846, 0x3e58_d8ac_bd82_68e6, 0x4007_6c95_5c57_a0a4, 0x4065_5858_af51_1ea8),
            (27305, 0x3e76_121d_895c_c664, 0x4010_2fa9_6fbb_7cd6, 0x409b_f094_5fce_4a3a),
            (27306, 0x3e73_455f_093f_b9bd, 0x4000_1318_6bea_0373, 0x4060_6ced_2847_0e35),
            (27307, 0x3e74_9828_8369_6ff3, 0x400d_8ee7_c1e7_06dd, 0x408a_70a9_a544_1b03),
            (32767, 0x3e95_1ed9_32ae_777b, 0x4012_535a_a950_9230, 0x4062_8284_e916_8b5b),
            (32768, 0x3e95_1e55_41af_2ea3, 0x4002_16ed_9f45_7723, 0x4068_6479_a2e0_5753),
            (32769, 0x3e92_3881_9bb4_f385, 0x400c_4277_fb96_bc28, 0x406a_2bbd_fd84_16ff),
            (35079, 0x3e58_a472_adca_e897, 0x4016_b607_110a_fc1d, 0x4065_01ae_2f52_816c),
        ]
        for (index, amplitude, phase, frequency) in fixtures {
            let actual = try #require(PrototypeModelData.vsopTermBitPatterns(at: index))
            #expect(actual.amplitude == amplitude)
            #expect(actual.phase == phase)
            #expect(actual.frequency == frequency)
        }
    }

    @Test("Accessors reject indexes outside generated metadata")
    func accessBounds() {
        #expect(PrototypeModelData.polynomialBitPattern(body: .mercury, index: -1) == nil)
        #expect(PrototypeModelData.polynomialBitPattern(body: .neptune, index: 178_971) == nil)
        #expect(PrototypeModelData.polynomialValidity(body: .earth, segment: 9_177) == nil)
        #expect(PrototypeModelData.vsopTermBitPatterns(at: Int.min) == nil)
        #expect(PrototypeModelData.vsopTermBitPatterns(at: Int.max) == nil)
        #expect(PrototypeModelData.vsopTermBitPatterns(at: 35_080) == nil)
        #expect(PrototypeModelData.nutationRow(at: Int.min) == nil)
        #expect(PrototypeModelData.nutationRow(at: Int.max) == nil)
        #expect(PrototypeModelData.nutationRow(at: 77) == nil)
    }

    @Test("Polynomial metadata retains the TT grid bounds")
    func polynomialGridBounds() {
        for metadata in PrototypeModelData.polynomialMetadata {
            #expect(metadata.startTT == -36_524.5)
            #expect(metadata.stopTT == 36_889.5)
        }
    }
}
