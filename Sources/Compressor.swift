import AVFoundation
import VideoToolbox

/// الضغط بمُرمِّز العتاد في الآيفون: HEVC بدقّة FHD، بنفس عدد الإطارات، والصوت يُنسخ كما هو،
/// وتُنقل البيانات الوصفية (الموقع، تاريخ التصوير، طراز الجهاز) إلى الملف الجديد.
enum CompressError: LocalizedError {
    case noVideo, failed(String), cancelled
    var errorDescription: String? {
        switch self {
        case .noVideo: return "لا يحوي مسار فيديو"
        case .failed(let s): return s
        case .cancelled: return "أُلغي"
        }
    }
}

final class Compressor {
    /// بتّات لكل بكسل لكل إطار — نفس قيم نسخة أندرويد
    static func bpp(_ quality: Int) -> Double { [0.2025, 0.15, 0.1125][max(0, min(2, quality))] }

    private static func even(_ v: CGFloat) -> Int { max(2, Int((v / 2).rounded()) * 2) }

    static func compress(_ asset: AVAsset, quality: Int, isCancelled: @escaping () -> Bool,
                         progress: @escaping (Double) -> Void) async throws -> URL {
        guard let vTrack = try await asset.loadTracks(withMediaType: .video).first else { throw CompressError.noVideo }
        let aTracks = try await asset.loadTracks(withMediaType: .audio)
        let (size, transform, fps, rate) = try await vTrack.load(.naturalSize, .preferredTransform, .nominalFrameRate, .estimatedDataRate)
        let duration = try await asset.load(.duration).seconds
        let hdr = (try? await vTrack.load(.mediaCharacteristics))?.contains(.containsHDRVideo) ?? false

        let short = min(abs(size.width), abs(size.height))
        let scale: CGFloat = short > 1080 ? 1080 / short : 1
        let w = even(abs(size.width) * scale), h = even(abs(size.height) * scale)
        let frameRate = fps > 0 ? Double(fps) : 30
        var bitrate = bpp(quality) * Double(w * h) * frameRate
        if hdr { bitrate *= 1.25 }
        if rate > 0 { bitrate = min(bitrate, Double(rate) * 0.65) }   // لا نتجاوز 65% من الأصل
        bitrate = max(bitrate, 2_000_000)

        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: out, fileType: .mov)

        // ── الفيديو ──
        let pix = hdr ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        let vOut = AVAssetReaderTrackOutput(track: vTrack, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: pix])
        vOut.alwaysCopiesSampleData = false
        guard reader.canAdd(vOut) else { throw CompressError.failed("تعذّر قراءة الفيديو") }
        reader.add(vOut)

        var props: [String: Any] = [
            AVVideoAverageBitRateKey: Int(bitrate),
            AVVideoExpectedSourceFrameRateKey: Int(frameRate.rounded()),
            AVVideoAllowFrameReorderingKey: true,
            AVVideoProfileLevelKey: (hdr ? kVTProfileLevel_HEVC_Main10_AutoLevel : kVTProfileLevel_HEVC_Main_AutoLevel) as String,
        ]
        props[AVVideoMaxKeyFrameIntervalKey] = Int(frameRate.rounded()) * 2
        var vSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: w, AVVideoHeightKey: h,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
            AVVideoCompressionPropertiesKey: props,
        ]
        if hdr, let fmt = try await vTrack.load(.formatDescriptions).first {
            func ext(_ k: CFString) -> String? { CMFormatDescriptionGetExtension(fmt, extensionKey: k) as? String }
            if let p = ext(kCMFormatDescriptionExtension_ColorPrimaries),
               let t = ext(kCMFormatDescriptionExtension_TransferFunction),
               let m = ext(kCMFormatDescriptionExtension_YCbCrMatrix) {
                vSettings[AVVideoColorPropertiesKey] = [AVVideoColorPrimariesKey: p, AVVideoTransferFunctionKey: t, AVVideoYCbCrMatrixKey: m]
            }
        }
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: vSettings)
        vIn.transform = transform              // الاتجاه (عمودي/أفقي) كما في الأصل
        vIn.expectsMediaDataInRealTime = false
        guard writer.canAdd(vIn) else { throw CompressError.failed("المُرمِّز لا يقبل الإعدادات") }
        writer.add(vIn)

        // ── الصوت: نسخ مباشر بلا إعادة ترميز ──
        var audio: [(AVAssetReaderTrackOutput, AVAssetWriterInput)] = []
        for t in aTracks {
            let fmt = try await t.load(.formatDescriptions).first
            let o = AVAssetReaderTrackOutput(track: t, outputSettings: nil)
            let i = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: fmt)
            i.expectsMediaDataInRealTime = false
            if reader.canAdd(o) && writer.canAdd(i) { reader.add(o); writer.add(i); audio.append((o, i)) }
        }

        // ── البيانات الوصفية + علامة «مضغوط» ──
        var meta = (try? await asset.load(.metadata)) ?? []
        let mark = AVMutableMetadataItem()
        mark.keySpace = .quickTimeMetadata
        mark.key = "com.squeeze.compressed" as NSString
        mark.value = "1" as NSString
        meta.append(mark)
        writer.metadata = meta

        guard writer.startWriting() else { throw CompressError.failed(writer.error?.localizedDescription ?? "فشل بدء الكتابة") }
        guard reader.startReading() else { throw CompressError.failed(reader.error?.localizedDescription ?? "فشل بدء القراءة") }
        writer.startSession(atSourceTime: .zero)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let group = DispatchGroup()
            func pump(_ input: AVAssetWriterInput, _ output: AVAssetReaderOutput, _ label: String, isVideo: Bool) {
                group.enter()
                var finished = false
                input.requestMediaDataWhenReady(on: DispatchQueue(label: label)) {
                    while input.isReadyForMoreMediaData && !finished {
                        if isCancelled() { reader.cancelReading(); finished = true; input.markAsFinished(); group.leave(); return }
                        if let sb = output.copyNextSampleBuffer() {
                            if isVideo, duration > 0 {
                                progress(min(1, CMSampleBufferGetPresentationTimeStamp(sb).seconds / duration))
                            }
                            if !input.append(sb) { finished = true; input.markAsFinished(); group.leave(); return }
                        } else {
                            finished = true; input.markAsFinished(); group.leave(); return
                        }
                    }
                }
            }
            pump(vIn, vOut, "sq.video", isVideo: true)
            for (n, (o, i)) in audio.enumerated() { pump(i, o, "sq.audio\(n)", isVideo: false) }
            group.notify(queue: .global()) {
                if isCancelled() { writer.cancelWriting(); cont.resume(throwing: CompressError.cancelled); return }
                if reader.status == .failed {
                    writer.cancelWriting(); cont.resume(throwing: CompressError.failed(reader.error?.localizedDescription ?? "فشل القراءة")); return
                }
                writer.finishWriting {
                    if writer.status == .completed { cont.resume() }
                    else { cont.resume(throwing: CompressError.failed(writer.error?.localizedDescription ?? "فشل الكتابة")) }
                }
            }
        }
        return out
    }
}
