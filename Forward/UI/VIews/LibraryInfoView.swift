//
//  LibraryInfoView.swift
//  Forward
//
//  Created by Kyle Erhabor on 10/12/24.
//

import SwiftUI

struct Line: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: 0, y: 0))
    path.addLine(to: CGPoint(x: rect.width, y: 0))

    return path
  }
}

struct LibraryInfoDividerView: View {
  var body: some View {
    Line()
      .stroke(style: StrokeStyle(dash: [1]))
      .foregroundStyle(.quaternary)
      .frame(height: 1)
  }
}

struct LibraryInfoPositionItemView: View {
  let item: Int?

  var body: some View {
    LibraryTrackPositionView(item: item)
      // 24 - 32
      //
      // This displays the position item up to 9,999 without truncating.
      .frame(width: 28, alignment: .leading)
  }
}

struct LibraryInfoPositionView: View {
  let pos: LibraryTrackPosition?

  var body: some View {
    LibraryInfoPositionItemView(item: pos?.number)

    Text(verbatim: "of")
      .foregroundStyle(.secondary)

    LibraryInfoPositionItemView(item: pos?.total)
  }
}

struct LibraryInfoView: View {
  @AppStorage(StorageKeys.preferArtistsDisplay.name) private var preferArtistsDisplay = StorageKeys.preferArtistsDisplay.defaultValue

  let tracks: [LibraryTrack]?

  private var track: LibraryTrack? {
    tracks?.first
  }

  var body: some View {
    VStack(spacing: 0) {
      // TODO: Configure to scale to fill while respecting bounds.
      //
      // For some reason, setting contentMode to .fill causes square images to extend past the bounds. This doesn't
      // occur for .fit, but won't act appropriately at different dimensions (or if space is reduced).
      Image(nsImage: track?.coverImage.map { NSImage(cgImage: $0, size: .zero) } ?? NSImage())
        .resizable()
        .aspectRatio(1, contentMode: .fit)

      // FIXME: Field heights slightly shift when selecting item.
      Grid(alignment: .centerFirstTextBaseline, verticalSpacing: 0) {
        Divider()
          .ignoresSafeArea(edges: .horizontal)

        GridRow {
          Text("Track.Column.Title")
            .gridColumnAlignment(.trailing)
            .foregroundStyle(.secondary)

          Text(track?.title ?? "")
            .gridColumnAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .lineLimit(1, reservesSpace: true)
        .padding(.vertical, 8)

        LibraryInfoDividerView()
          .ignoresSafeArea()

        GridRow {
          Text(preferArtistsDisplay ? "Track.Column.Artists" : "Track.Column.Artist")
            .foregroundStyle(.secondary)

          LibraryTrackArtistContentView(artists: track?.artists ?? [], artist: track?.artist)
        }
        .font(.caption)
        .lineLimit(1, reservesSpace: true)
        .padding(.vertical, 8)

        LibraryInfoDividerView()
          .ignoresSafeArea()

        GridRow {
          Text("Track.Column.Album")
            .foregroundStyle(.secondary)

          Text(track?.album ?? "")
        }
        .font(.caption)
        .lineLimit(1, reservesSpace: true)
        .padding(.vertical, 8)

        LibraryInfoDividerView()
          .ignoresSafeArea()

        GridRow {
          Text("Track.Column.AlbumArtist")
            .foregroundStyle(.secondary)

          Text(track?.albumArtist ?? "")
        }
        .font(.caption)
        .lineLimit(1, reservesSpace: true)
        .padding(.vertical, 8)

        LibraryInfoDividerView()
          .ignoresSafeArea()

        GridRow {
          Text("Track.Column.Track.Year")
            .foregroundStyle(.secondary)

          Text(track?.date ?? Date.epoch, format: .dateTime.year())
            .monospacedDigit()
            .visible(track?.date != nil)
            .environment(\.timeZone, .gmt)
        }
        .font(.caption)
        .lineLimit(1, reservesSpace: true)
        .padding(.vertical, 8)

        LibraryInfoDividerView()
          .ignoresSafeArea()

        GridRow {
          Text("Track.Column.Track")
            .foregroundStyle(.secondary)

          HStack(alignment: .firstTextBaseline) {
            LibraryInfoPositionView(pos: track?.track)
          }
        }
        .font(.caption)
        .lineLimit(1, reservesSpace: true)
        .padding(.vertical, 8)

        LibraryInfoDividerView()
          .ignoresSafeArea()

        GridRow {
          Text("Track.Column.Disc")
            .foregroundStyle(.secondary)

          HStack(alignment: .firstTextBaseline) {
            LibraryInfoPositionView(pos: track?.disc)
          }
        }
        .font(.caption)
        .lineLimit(1, reservesSpace: true)
        .padding(.vertical, 8)

        LibraryInfoDividerView()
          .ignoresSafeArea()

        GridRow {
          Text("Track.Column.Duration")
            .foregroundStyle(.secondary)

          LibraryTrackDurationView(duration: track?.duration ?? Duration.zero)
            .visible(track?.duration != nil)
        }
        .font(.caption)
        .lineLimit(1, reservesSpace: true)
        .padding(.vertical, 8)
      }
      .safeAreaPadding(.horizontal, 12)
    }
    .containerBackground(.ultraThickMaterial, for: .window)
  }
}
