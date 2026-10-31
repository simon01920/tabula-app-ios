// Sharing glue that needs Apple frameworks (Phase 7 H1): the share-service client (URLSession) and the QR renderer
// (CoreImage). The decisions (links, plan, contract, problems) are pure in TimetableUI/Sharing/ShareFlow.swift.
// Privacy: an ephemeral session (no cookies, no cache, no credential storage); only the envelope is sent.
// APIs: URLSession(configuration: .ephemeral), URLSession.data(for:) (async), URLError codes, CIFilter.qrCodeGenerator()
//       (CIFilterBuiltins: `message` Data, `correctionLevel` "L"/"M"/"Q"/"H"; iPhoneOS27.0.sdk CIFilterBuiltins.h
//       `@protocol CIQRCodeGenerator`), CIContext.createCGImage(_:from:). The generator emits one pixel per module; the
//       view scales it with `.interpolation(.none)`, so the code stays crisp at any size.
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import TimetableCore
import TimetableUI
import UIKit

enum ShareServiceClient {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = ShareService.requestTimeout
        configuration.timeoutIntervalForResource = ShareService.requestTimeout * 2
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    /// Stores `envelope` for 30 days and returns its code.
    static func upload(envelope: String) async -> Result<ShortCode, ShareServiceProblem> {
        var request = URLRequest(url: ShareService.uploadURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = ShareService.uploadBody(envelope: envelope)
        return await send(request).flatMap { ShareService.decodeUpload(status: $0.status, data: $0.data) }
    }

    /// The envelope stored under `code`.
    static func fetch(code: ShortCode) async -> Result<String, ShareServiceProblem> {
        var request = URLRequest(url: ShareService.fetchURL(for: code))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return await send(request).flatMap { ShareService.decodeFetch(status: $0.status, data: $0.data) }
    }

    private static func send(_ request: URLRequest) async -> Result<(status: Int, data: Data), ShareServiceProblem> {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failure(.invalidResponse) }
            return .success((http.statusCode, data))
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                return .failure(.offline)
            case .timedOut:
                return .failure(.timedOut)
            default:
                return .failure(.unavailable)   // e.g. cannotFindHost while the placeholder domain is not deployed
            }
        } catch {
            return .failure(.unavailable)
        }
    }
}

enum QRCodeRenderer {
    /// A QR code of `text` (one pixel per module), or `nil` when it does not fit one code.
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        // M (15 % recovery) whenever it fits (2331 bytes at version 40), else L (2953 bytes, SharePlan.qrByteCapacity).
        filter.correctionLevel = text.utf8.count <= 2331 ? "M" : "L"
        guard let output = filter.outputImage,
              let cgImage = CIContext(options: [.useSoftwareRenderer: false]).createCGImage(output, from: output.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
