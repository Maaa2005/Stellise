import Foundation

/// デバッグビルド限定のログ。リリースでは何も出力しない（コンパイル時に空になる）。
@inline(__always)
func debugLog(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    #if DEBUG
    let output = items.map { "\($0)" }.joined(separator: separator)
    print(output, terminator: terminator)
    #endif
}
