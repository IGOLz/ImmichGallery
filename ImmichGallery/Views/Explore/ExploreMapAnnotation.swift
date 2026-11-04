import SwiftUI

/// MapKit creates independent hosting views; all image dependencies are explicit.
struct ExploreMapAnnotation: View {
    let cluster: ExploreMapCluster
    let pipeline: ImagePipeline
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            RemoteThumbnail(pipeline: pipeline, assetID: cluster.assets.first)
                .frame(width: 52, height: 52).clipShape(.rect(cornerRadius: 8))
                .overlay(alignment: .bottomTrailing) {
                    Text("\(cluster.assets.count)").font(.caption.bold()).padding(3).background(.regularMaterial, in: Capsule())
                }
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white, lineWidth: 2))
        }.buttonStyle(.plain)
    }
}
