import Photos
import AVFoundation
import UIKit

struct VideoItem: Identifiable {
    var id: String { asset.localIdentifier }
    let asset: PHAsset
    let size: Int64
    let name: String
}

/// التعامل مع مكتبة الصور: البحث، الحفظ بنفس الاسم والتاريخ والموقع والألبومات، والحذف.
/// حاوية لمعرّف الفيديو الجديد (لا يجوز تعديل متغيّر محلّي داخل كتلة performChanges)
final class IdBox: @unchecked Sendable { var value = "" }

enum Library {
    static func authorized() -> Bool {
        let s = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return s == .authorized || s == .limited
    }

    static func requestAccess() async -> Bool {
        let s = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return s == .authorized || s == .limited
    }

    static func info(_ a: PHAsset) -> (Int64, String) {
        let res = PHAssetResource.assetResources(for: a)
        let r = res.first { $0.type == .video } ?? res.first { $0.type == .fullSizeVideo } ?? res.first
        let size = (r?.value(forKey: "fileSize") as? CLong).map { Int64($0) } ?? 0
        return (size, r?.originalFilename ?? "video.mov")
    }

    /// الفيديوهات الأكبر من الحدّ التي لم تُضغط. تُتخطّى: المعدّلة، والتصوير البطيء، والسينمائي
    /// (تأثيراتها محفوظة في الصور نفسها وتضيع عند إنشاء ملف جديد).
    static func candidates() -> [VideoItem] {
        let st = Store.shared
        let limit = Int64(st.thresholdMb) * 1_048_576
        let done = st.done, skipped = st.skipped
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        var out: [VideoItem] = []
        PHAsset.fetchAssets(with: .video, options: opts).enumerateObjects { a, _, _ in
            if done.contains(a.localIdentifier) || skipped.contains(a.localIdentifier) { return }
            if a.mediaSubtypes.contains(.videoHighFrameRate) { return }
            if #available(iOS 15, *), a.mediaSubtypes.contains(.videoCinematic) { return }
            let (size, name) = info(a)
            if size > limit { out.append(VideoItem(asset: a, size: size, name: name)) }
        }
        return out
    }

    /// الملف الأصلي (يُنزَّل من iCloud عند الحاجة)
    static func avAsset(_ a: PHAsset) async throws -> AVAsset {
        try await withCheckedThrowingContinuation { cont in
            let o = PHVideoRequestOptions()
            o.version = .original
            o.deliveryMode = .highQualityFormat
            o.isNetworkAccessAllowed = true
            PHImageManager.default().requestAVAsset(forVideo: a, options: o) { av, _, info in
                if let av { cont.resume(returning: av) }
                else { cont.resume(throwing: CompressError.failed((info?[PHImageErrorKey] as? Error)?.localizedDescription ?? "تعذّر فتح الفيديو")) }
            }
        }
    }

    /// يحفظ المضغوط كفيديو جديد بنفس الاسم والتاريخ والموقع والمفضّلة والألبومات؛ يعيد معرّفه
    static func save(_ url: URL, like a: PHAsset, name: String) async throws -> String {
        let newId = IdBox()
        let albums = PHAssetCollection.fetchAssetCollectionsContaining(a, with: .album, options: nil)
        try await PHPhotoLibrary.shared().performChanges {
            let req = PHAssetCreationRequest.forAsset()
            let o = PHAssetResourceCreationOptions()
            o.originalFilename = name
            o.shouldMoveFile = true
            req.addResource(with: .video, fileURL: url, options: o)
            req.creationDate = a.creationDate
            req.location = a.location
            req.isFavorite = a.isFavorite
            req.isHidden = a.isHidden
            guard let ph = req.placeholderForCreatedAsset else { return }
            newId.value = ph.localIdentifier
            albums.enumerateObjects { col, _, _ in
                if col.canPerform(.addContent) { PHAssetCollectionChangeRequest(for: col)?.addAssets([ph] as NSArray) }
            }
        }
        return newId.value
    }

    /// حذف الأصول دفعة واحدة — iOS يعرض نافذة تأكيد واحدة، والمحذوف يبقى 30 يوماً في «المحذوفة مؤخراً»
    static func delete(_ ids: [String]) async throws {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        if assets.count == 0 { return }
        try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(assets) }
    }

    static func thumbnail(_ id: String, size: CGFloat) async -> UIImage? {
        guard let a = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        return await withCheckedContinuation { cont in
            let o = PHImageRequestOptions()
            o.deliveryMode = .highQualityFormat; o.isNetworkAccessAllowed = true; o.resizeMode = .fast
            PHImageManager.default().requestImage(for: a, targetSize: CGSize(width: size * 3, height: size * 3),
                                                  contentMode: .aspectFill, options: o) { img, _ in cont.resume(returning: img) }
        }
    }

    static func duration(_ id: String) -> TimeInterval {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject?.duration ?? 0
    }
}
