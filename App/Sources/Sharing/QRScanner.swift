// Reading a QR code (Phase 7 H1, PHASE7_PLAN decision 3).
//   Camera   VisionKit `DataScannerViewController` when `isSupported` (A12 and later) and `isAvailable` (camera not
//            denied or restricted). The first `startScanning()` triggers the system camera prompt
//            (NSCameraUsageDescription); a denial arrives as `dataScanner(_:becameUnavailableWithError:)`.
//   Photo    `PhotosPicker` (no photo-library permission: the picker runs out of process) + Vision
//            `DetectBarcodesRequest` with `.qr` (the Swift API for VNDetectBarcodesRequest, iOS 18; Sendable value type,
//            so no VNRequest handler juggling under Swift 6).
// API names checked in iPhoneOS27.0.sdk (VisionKit/Vision .swiftinterface, 2026-10-31): DataScannerViewController
//   init(recognizedDataTypes:qualityLevel:recognizesMultipleItems:isHighFrameRateTrackingEnabled:isPinchToZoomEnabled:
//   isGuidanceEnabled:isHighlightingEnabled:), RecognizedDataType.barcode(symbologies: [VNBarcodeSymbology]),
//   class var isSupported / isAvailable, startScanning() throws, stopScanning(), DataScannerViewControllerDelegate
//   didAdd(_:allItems:) / becameUnavailableWithError(_: ScanningUnavailable), RecognizedItem.barcode(Barcode),
//   Barcode.payloadStringValue; Vision DetectBarcodesRequest.symbologies [BarcodeSymbology] (.qr),
//   perform(on: Data, orientation:) async throws -> [BarcodeObservation], BarcodeObservation.payloadString.
// Docs: https://developer.apple.com/documentation/visionkit/scanning-data-with-the-camera ("If the user doesn't deny
// your app access to the camera ... isAvailable ... is true"), …/visionkit/datascannerviewcontroller/isavailable.
import SwiftUI
import Vision
import VisionKit

enum QRScanning {
    /// The live scanner can run on this device and the camera is not denied or restricted.
    @MainActor static var isScannerUsable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    /// The live scanner exists on this device (the camera may still be denied).
    @MainActor static var isScannerSupported: Bool { DataScannerViewController.isSupported }

    /// The payloads of the QR codes in an image file's bytes (empty when none is found or the image is unreadable).
    static func payloads(inImageData data: Data) async -> [String] {
        var request = DetectBarcodesRequest()
        request.symbologies = [.qr]
        let observations = (try? await request.perform(on: data)) ?? []
        return observations.compactMap(\.payloadString)
    }
}

/// The live camera scanner. `onPayload` gets each new QR payload; `onUnavailable` fires when the camera is denied,
/// restricted or stops working.
struct QRScannerView: UIViewControllerRepresentable {
    let onPayload: @MainActor (String) -> Void
    let onUnavailable: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPayload: onPayload, onUnavailable: onUnavailable)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
                                                recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
                                                isPinchToZoomEnabled: true, isGuidanceEnabled: true,
                                                isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        guard !context.coordinator.started else { return }
        context.coordinator.started = true
        do {
            try scanner.startScanning()
        } catch {
            onUnavailable()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onPayload: @MainActor (String) -> Void
        let onUnavailable: @MainActor () -> Void
        var started = false

        init(onPayload: @escaping @MainActor (String) -> Void, onUnavailable: @escaping @MainActor () -> Void) {
            self.onPayload = onPayload
            self.onUnavailable = onUnavailable
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    onPayload(payload)
                    return
                }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            onUnavailable()
        }
    }
}
