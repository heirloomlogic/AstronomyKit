import Foundation

extension Engine {
    /// Decodes a compiled base64 table once, retaining its packed bytes without widening each element.
    static func unpackBytes(count: Int, _ text: StaticString) -> Data {
        // A string literal lives for the whole process, so its bytes need no copy.
        let data = text.withUTF8Buffer { utf8 -> Data? in
            guard let base = utf8.baseAddress else { return Data() }
            let literal = Data(
                bytesNoCopy: UnsafeMutableRawPointer(mutating: base), count: utf8.count, deallocator: .none)
            return Data(base64Encoded: literal, options: .ignoreUnknownCharacters)
        }
        guard let data, data.count == count else {
            preconditionFailure("A generated table does not hold \(count) bytes")
        }
        return data
    }
}
