//
//  LibraryInfoView.swift
//  Sampled
//
//  Created by Kyle Erhabor on 10/12/24.
//

import SwiftUI

enum LibraryInfoTrackProperty<Value> {
  case empty
  case value(Value)
  case mixed
}

extension LibraryInfoTrackProperty: Equatable where Value: Equatable {
  init(values: some Sequence<Value>) {
    self = .empty

    values.forEach { value in
      switch self {
        case .empty:
          self = .value(value)
        case .value(let val):
          if val != value {
            self = .mixed
          }
        case .mixed:
          break
      }
    }
  }
}

@Observable
class LibraryInfoTrackModel {
  var title: LibraryInfoTrackProperty<String>
  var artistName: LibraryInfoTrackProperty<String?>
  var albumName: LibraryInfoTrackProperty<String?>
  var albumArtistName: LibraryInfoTrackProperty<String?>
  var yearDate: LibraryInfoTrackProperty<Date?>
  var trackNumber: LibraryInfoTrackProperty<Int?>
  var trackTotal: LibraryInfoTrackProperty<Int?>
  var discNumber: LibraryInfoTrackProperty<Int?>
  var discTotal: LibraryInfoTrackProperty<Int?>
  var duration: LibraryInfoTrackProperty<Duration>
  // TODO: Refactor.
  //
  // We only need the image.
  var artwork: LibraryInfoTrackProperty<LibraryTrackArtwork?>

  init(
    title: LibraryInfoTrackProperty<String> = .empty,
    artistName: LibraryInfoTrackProperty<String?> = .empty,
    albumName: LibraryInfoTrackProperty<String?> = .empty,
    albumArtistName: LibraryInfoTrackProperty<String?> = .empty,
    yearDate: LibraryInfoTrackProperty<Date?> = .empty,
    trackNumber: LibraryInfoTrackProperty<Int?> = .empty,
    trackTotal: LibraryInfoTrackProperty<Int?> = .empty,
    discNumber: LibraryInfoTrackProperty<Int?> = .empty,
    discTotal: LibraryInfoTrackProperty<Int?> = .empty,
    duration: LibraryInfoTrackProperty<Duration> = .empty,
    artwork: LibraryInfoTrackProperty<LibraryTrackArtwork?> = .empty,
  ) {
    self.title = title
    self.artistName = artistName
    self.albumName = albumName
    self.albumArtistName = albumArtistName
    self.yearDate = yearDate
    self.trackNumber = trackNumber
    self.trackTotal = trackTotal
    self.discNumber = discNumber
    self.discTotal = discTotal
    self.duration = duration
    self.artwork = artwork
  }
}

struct LibraryInfoTagSeparatorView: View {
  var body: some View {
    Line()
      .stroke(style: StrokeStyle(dash: [1]))
      .foregroundStyle(.quaternary)
      .frame(height: 1)
  }
}

struct LibraryInfoTagValueMixedTextView: View {
  var body: some View {
    Text("LibraryInfo.Mixed.Text")
  }
}

struct LibraryInfoTagValueMixedNumberView: View {
  var body: some View {
    Text("LibraryInfo.Mixed.Number")
  }
}

struct LibraryInfoPositionTagItemView: View {
  let item: LibraryInfoTrackProperty<Int?>

  var body: some View {
    VStack {
      LibraryInfoTagValueContentView(property: item) { item in
        LibraryTrackPositionItemView(item: item ?? 0)
          .visible(item != nil)
      } mixed: {
        LibraryInfoTagValueMixedNumberView()
      }
    }
    // 24 - 32
    //
    // This displays the position item up to 9,999 without truncating.
    .frame(width: 28, alignment: .leading)
  }
}

struct LibraryInfoPositionTagView: View {
  let number: LibraryInfoTrackProperty<Int?>
  let total: LibraryInfoTrackProperty<Int?>

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      LibraryInfoPositionTagItemView(item: number)

      Text("LibraryInfo.PositionSeparator")
        .foregroundStyle(.secondary)

      LibraryInfoPositionTagItemView(item: total)
    }
  }
}

struct LibraryInfoTagNameView<Content>: View where Content: View {
  let content: Content

  var body: some View {
    content
      .gridColumnAlignment(.trailing)
      .foregroundStyle(.secondary)
  }

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }
}

struct LibraryInfoTagValueContentView<Value, EmptyView, ValueView, MixedView>: View where EmptyView: View,
                                                                                          ValueView: View,
                                                                                          MixedView: View {
  typealias ValueViewBuilder = (Value) -> ValueView

  let property: LibraryInfoTrackProperty<Value>
  let emptyView: EmptyView
  let valueView: ValueViewBuilder
  let mixedView: MixedView

  var body: some View {
    switch property {
      case .empty:
        emptyView
      case .value(let value):
        valueView(value)
      case .mixed:
        mixedView
          .foregroundStyle(.tertiary)
    }
  }

  init(
    property: LibraryInfoTrackProperty<Value>,
    @ViewBuilder value valueView: @escaping ValueViewBuilder,
    @ViewBuilder empty emptyView: () -> EmptyView,
    @ViewBuilder mixed mixedView: () -> MixedView,
  ) {
    self.property = property
    self.emptyView = emptyView()
    self.valueView = valueView
    self.mixedView = mixedView()
  }
}

extension LibraryInfoTagValueContentView where EmptyView == SwiftUI.EmptyView {
  init(
    property: LibraryInfoTrackProperty<Value>,
    @ViewBuilder value valueView: @escaping ValueViewBuilder,
    @ViewBuilder mixed mixedView: () -> MixedView,
  ) {
    self.init(
      property: property,
      value: valueView,
      empty: { EmptyView() },
      mixed: mixedView,
    )
  }
}

struct LibraryInfoTagValueView<Content>: View where Content: View {
  let content: Content

  var body: some View {
    ZStack {
      content

      // https://github.com/kyleerhabor/sampled/pull/1
      //
      // This isn't necessary for non-empty content (e.g., Track No.).
      Text(verbatim: " ")
    }
    .gridColumnAlignment(.leading)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }
}

struct LibraryInfoTagView<Content>: View where Content: View {
  let content: Content

  var body: some View {
    GridRow {
      content
    }
    .font(.caption)
    .lineLimit(1, reservesSpace: true)
    .padding(.vertical, 8)

    LibraryInfoTagSeparatorView()
      .ignoresSafeArea()
  }

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }
}

struct LibraryInfoView: View {
  @Environment(LibraryInfoTrackModel.self) private var track

  var body: some View {
    VStack(spacing: 0) {
      // TODO: Configure to scale to fill while respecting bounds.
      //
      // For some reason, setting contentMode to .fill causes square images to extend past the bounds. This doesn't
      // occur for .fit, but won't act appropriately at different dimensions (or if space is reduced).
      let image = switch track.artwork {
        case .empty, .mixed: NSImage()
        case let .value(artwork): artwork?.image ?? NSImage()
      }

      Image(nsImage: image)
        .resizable()
        .aspectRatio(1, contentMode: .fit)


      Grid(alignment: .centerFirstTextBaseline, verticalSpacing: 0) {
        Divider()
          .ignoresSafeArea(edges: .horizontal)

        LibraryInfoTagView {
          LibraryInfoTagNameView {
            Text("LibraryInfo.Tag.Title.Name")
          }

          LibraryInfoTagValueView {
            LibraryInfoTagValueContentView(property: track.title) { title in
              Text(verbatim: title)
            } mixed: {
              LibraryInfoTagValueMixedTextView()
            }
          }
        }

        LibraryInfoTagView {
          LibraryInfoTagNameView {
            Text("LibraryInfo.Tag.Artist.Name")
          }

          LibraryInfoTagValueView {
            LibraryInfoTagValueContentView(property: track.artistName) { artist in
              Text(verbatim: artist ?? "")
            } mixed: {
              LibraryInfoTagValueMixedTextView()
            }
          }
        }

        LibraryInfoTagView {
          LibraryInfoTagNameView {
            Text("LibraryInfo.Tag.Album.Name")
          }

          LibraryInfoTagValueView {
            LibraryInfoTagValueContentView(property: track.albumName) { albumName in
              Text(verbatim: albumName ?? "")
            } mixed: {
              LibraryInfoTagValueMixedTextView()
            }
          }
        }

        LibraryInfoTagView {
          LibraryInfoTagNameView {
            Text("LibraryInfo.Tag.AlbumArtist.Name")
          }

          LibraryInfoTagValueView {
            LibraryInfoTagValueContentView(property: track.albumArtistName) { albumArtistName in
              Text(verbatim: albumArtistName ?? "")
            } mixed: {
              LibraryInfoTagValueMixedTextView()
            }
          }
        }

        LibraryInfoTagView {
          LibraryInfoTagNameView {
            Text("LibraryInfo.Tag.Year.Name")
          }

          LibraryInfoTagValueView {
            LibraryInfoTagValueContentView(property: track.yearDate) { date in
              Text(date ?? .distantFuture, format: .dateTime.year())
                .monospacedDigit()
                .visible(date != nil)
                .environment(\.timeZone, .gmt)
            } mixed: {
              LibraryInfoTagValueMixedNumberView()
            }
          }
        }

        LibraryInfoTagView {
          LibraryInfoTagNameView {
            Text("LibraryInfo.Tag.TrackNumber.Name")
          }

          LibraryInfoTagValueView {
            LibraryInfoPositionTagView(number: track.trackNumber, total: track.trackTotal)
          }
        }

        LibraryInfoTagView {
          LibraryInfoTagNameView {
            Text("LibraryInfo.Tag.DiscNumber.Name")
          }

          LibraryInfoTagValueView {
            LibraryInfoPositionTagView(number: track.discNumber, total: track.discTotal)
          }
        }

        LibraryInfoTagView {
          LibraryInfoTagNameView {
            Text("LibraryInfo.Tag.Duration.Name")
          }

          LibraryInfoTagValueView {
            // It may be required to move away from this empty-value-mixed structure to display a mixed duration. We can
            // compose it (e.g., having another property for mixed data), but I'm not sure if that's the best way to
            // represent this. We could represent it like how Toggle's isMixed property is just an add-on to the general
            // data.
            LibraryInfoTagValueContentView(property: track.duration) { duration in
              LibraryTrackDurationView(duration: duration)
            } mixed: {
              LibraryInfoTagValueMixedNumberView()
            }
          }
        }
      }
      .safeAreaPadding(.horizontal, 12)
    }
    .containerBackground(.ultraThickMaterial, for: .window)
  }
}
