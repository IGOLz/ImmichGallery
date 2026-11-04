#!/bin/sh
# Usage: scripts/check-viewer-responses.sh /path/to/demo-response-fixtures
# Expected files: viewer-buckets.json, viewer-bucket.json, viewer-asset.json,
# viewer-video-asset.json, viewer-preview and viewer-original. No credentials are read.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture_dir=${1:?Provide the directory containing demo response fixtures}
check=$(mktemp -t viewer-check)
trap 'rm -f "$check"' EXIT
cat "$repo/ImmichGallery/API/Models.swift" > "$check"
cat >> "$check" <<'SWIFT'
import ImageIO
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
func data(_ name: String) throws -> Data { try Data(contentsOf: directory.appendingPathComponent(name)) }
let decoder = JSONDecoder()
let buckets = try decoder.decode([TimeBucket].self, from: data("viewer-buckets.json"))
let bucket = try decoder.decode(TimeBucketAssets.self, from: data("viewer-bucket.json"))
let asset = try decoder.decode(AssetResponse.self, from: data("viewer-asset.json"))
let video = try decoder.decode(AssetResponse.self, from: data("viewer-video-asset.json"))
assert(!buckets.isEmpty && bucket.id.contains(asset.id))
let count = bucket.id.count
assert([bucket.isImage.count, bucket.isFavorite.count, bucket.isTrashed.count,
        bucket.thumbhash.count, bucket.ratio.count, bucket.duration.count,
        bucket.fileCreatedAt.count, bucket.livePhotoVideoId.count].allSatisfy { $0 == count })
assert(video.type == .video)
for name in ["viewer-preview", "viewer-original"] {
    let source = CGImageSourceCreateWithData(try data(name) as CFData, nil)!
    assert(CGImageSourceCreateImageAtIndex(source, 0, nil) != nil)
}
print("Viewer response DTO and image decoding checks passed")
SWIFT
swift "$check" "$fixture_dir"
