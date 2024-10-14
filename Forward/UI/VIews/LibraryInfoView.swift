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
  let tracks: [LibraryTrack]?

  private var track: LibraryTrack? {
    tracks?.first
  }

  var body: some View {
    VStack(spacing: 0) {
      Image(nsImage: track?.coverImage ?? NSImage())
        .resizable()
        .scaledToFit()

      // FIXME: Field heights slightly shift when selecting item.
      Grid(alignment: .centerFirstTextBaseline, verticalSpacing: 0) {
        Divider()
          .ignoresSafeArea(edges: .horizontal)

        GridRow {
          Text("Title")
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
          Text("Artist")
            .foregroundStyle(.secondary)

          Text(track?.artist ?? "")
        }
        .font(.caption)
        .lineLimit(1, reservesSpace: true)
        .padding(.vertical, 8)

        LibraryInfoDividerView()
          .ignoresSafeArea()

        GridRow {
          Text("Album")
            .foregroundStyle(.secondary)

          Text(track?.album ?? "")
        }
        .font(.caption)
        .lineLimit(1, reservesSpace: true)
        .padding(.vertical, 8)

        LibraryInfoDividerView()
          .ignoresSafeArea()

        GridRow {
          Text("Album Artist")
            .foregroundStyle(.secondary)

          Text(track?.albumArtist ?? "")
        }
        .font(.caption)
        .lineLimit(1, reservesSpace: true)
        .padding(.vertical, 8)

        LibraryInfoDividerView()
          .ignoresSafeArea()

        GridRow {
          Text("Year")
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
          Text("Track №")
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
          Text("Disc №")
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
          Text("Duration")
            .foregroundStyle(.secondary)

          let duration = track?.duration ?? Duration.zero

          Text(
            duration,
            format: .time(
              pattern: duration >= .hour
              ? .hourMinuteSecond(padHourToLength: 2, roundFractionalSeconds: .towardZero)
              : .minuteSecond(padMinuteToLength: 2, roundFractionalSeconds: .towardZero)
            )
          )
          .monospacedDigit()
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
