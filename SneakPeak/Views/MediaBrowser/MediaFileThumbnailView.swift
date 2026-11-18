//
//  MediaFileThumbnailView.swift
//  SneakPeak
//
//  Thumbnail for a playable file-source video, loaded through
//  FileThumbnailService (disk-cached). Falls back to the file-type
//  icon while loading or when no thumbnail is available.
//

import SwiftUI

struct MediaFileThumbnailView: View {
    let file: MediaFile

    @Environment(\.appEnvironment) private var appEnvironment
    @State private var imageData: Data?

    private static let side: CGFloat = {
        #if os(macOS)
        28
        #else
        44
        #endif
    }()

    var body: some View {
        Group {
            if let imageData,
               let image = Self.platformImage(from: imageData) {
                thumbnailContent(image)
            } else {
                placeholder
            }
        }
        .frame(width: Self.side, height: Self.side)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true) // Decorative: the row text carries the info.
        .task(id: file.id) {
            await loadThumbnail()
        }
    }

    @ViewBuilder
    private func thumbnailContent(_ image: Self.PlatformImage) -> some View {
        #if os(macOS)
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
        #else
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
        #endif
    }

    private var placeholder: some View {
        Image(systemName: file.systemImage)
            // Mirror MediaFileRow's icon font so the 28-pt macOS frame is
            // not oversized by a title2 glyph.
            .font(Self.iconFont)
            .foregroundStyle(iconColor)
    }

    private static let iconFont: Font = {
        #if os(macOS)
        .title3
        #else
        .title2
        #endif
    }()

    private var iconColor: Color {
        file.isDirectory ? .blue : file.isVideo ? .purple : .secondary
    }

    // MARK: - Loading

    @MainActor
    private func loadThumbnail() async {
        let password = appEnvironment?.mediaSourcesManager.password(for: file.source)
        imageData = await FileThumbnailService.shared.imageData(for: file, password: password)
    }

    // MARK: - Platform image decoding

    #if os(macOS)
    private typealias PlatformImage = NSImage
    #else
    private typealias PlatformImage = UIImage
    #endif

    private static func platformImage(from data: Data) -> PlatformImage? {
        #if os(macOS)
        NSImage(data: data)
        #else
        UIImage(data: data)
        #endif
    }
}
