import PhotosUI
import SwiftUI

/// An avatar you can tap to choose a profile photo. Uses the system photo
/// picker, which runs outside the app, so BUMP never needs photo-library
/// access and only ever sees the one image you pick.
struct PhotoPickerAvatar: View {
    @Binding var photo: Data?
    let name: String
    var size: CGFloat = 64

    @State private var selection: PhotosPickerItem?
    @State private var loading = false
    @State private var failed = false

    var body: some View {
        VStack(spacing: Space.xs) {
            PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
                ZStack(alignment: .bottomTrailing) {
                    Avatar(name: name, size: size, photo: photo)
                        .overlay {
                            if loading {
                                Circle().fill(.black.opacity(0.3))
                                ProgressView().tint(.white)
                            }
                        }
                    Image(systemName: photo == nil ? "camera.fill" : "pencil")
                        .font(.system(size: size * 0.16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: size * 0.34, height: size * 0.34)
                        .background(Circle().fill(BumpColor.action))
                        .overlay(Circle().strokeBorder(BumpColor.background, lineWidth: 2))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(photo == nil ? "Add a profile photo" : "Change profile photo")

            if failed {
                Text("Couldn't use that photo")
                    .font(.caption2)
                    .foregroundStyle(BumpColor.negative)
            } else if photo != nil {
                Button("Remove") { photo = nil }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BumpColor.secondaryText)
                    .accessibilityLabel("Remove profile photo")
            }
        }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            load(item)
        }
    }

    private func load(_ item: PhotosPickerItem) {
        loading = true
        failed = false
        Task {
            let raw = try? await item.loadTransferable(type: Data.self)
            // Resize off the main thread; it's a full-size photo until then.
            let prepared = await Task.detached { raw.flatMap(ProfilePhoto.prepare) }.value
            loading = false
            selection = nil
            if let prepared { photo = prepared } else { failed = true }
        }
    }
}
