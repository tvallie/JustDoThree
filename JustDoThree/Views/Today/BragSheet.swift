import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct BragSheet: View {
    @Environment(\.dismiss) private var dismiss

    let date: Date
    let completedTasks: [String]
    let completedStretches: [String]

    @State private var renderedImage: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    BragCardView(
                        date: date,
                        completedTasks: completedTasks,
                        completedStretches: completedStretches
                    )
                    .padding(24)
                }

                Divider()

                VStack(spacing: 12) {
                    if let img = renderedImage {
                        ShareLink(
                            item: BragImageTransferable(image: img),
                            preview: SharePreview(
                                "I just did my three!",
                                image: Image(uiImage: img)
                            )
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        ProgressView("Preparing image…")
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .navigationTitle("Share Your Win")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await renderCard() }
    }

    @MainActor
    private func renderCard() async {
        let card = BragCardView(
            date: date,
            completedTasks: completedTasks,
            completedStretches: completedStretches
        )
        .frame(width: 360)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 3.0
        renderedImage = renderer.uiImage
    }
}

// MARK: - Transferable wrapper

struct BragImageTransferable: Transferable {
    let image: UIImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            item.image.pngData() ?? Data()
        }
    }
}

#Preview {
    BragSheet(
        date: Date(),
        completedTasks: ["Morning pages", "30-min workout", "Review project proposal"],
        completedStretches: ["Read 20 min"]
    )
}
