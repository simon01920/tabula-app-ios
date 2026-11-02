import Foundation

/// Geometric clustering of loose OCR lines into grid cells (fallback when Vision finds no table).
public enum LineClustering {
    /// Cells built from `lines`.
    public static func cells(from lines: [RecognizedLine]) -> [RecognizedCell] {
        [] // I1 step 1b fills this in
    }
}
