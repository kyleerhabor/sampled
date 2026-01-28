//
//  LibraryInfoView.swift
//  Sampled
//
//  Created by Kyle Erhabor on 10/12/24.
//

import SwiftUI

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
  let item: LibraryInfoTrackModelProperty<Int?>

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
  let number: LibraryInfoTrackModelProperty<Int?>
  let total: LibraryInfoTrackModelProperty<Int?>

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

  let property: LibraryInfoTrackModelProperty<Value>
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
    property: LibraryInfoTrackModelProperty<Value>,
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
    property: LibraryInfoTrackModelProperty<Value>,
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
  @Environment(LibraryInfoTrackModel.self) private var libraryInfoTrack

  var body: some View {
    VStack(spacing: 0) {
      let image = switch libraryInfoTrack.albumArtwork {
        case .empty, .mixed: NSImage()
        case let .value(artwork): artwork?.image ?? NSImage()
      }

      ZStack {
        // Blurred background for small images or to fill space
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .blur(radius: 40)
          .opacity(0.6)
        
        // Main image - scales down large images, centers small ones
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fit)
      }
      .frame(height: 320)
      .clipped()
      .shadow(color: .black.opacity(0.2), radius: 8, y: 2)

      ScrollView(showsIndicators: false) {
        Grid(alignment: .centerFirstTextBaseline, verticalSpacing: 0) {
        Divider()
          .ignoresSafeArea(edges: .horizontal)

        LibraryInfoTagView {
          LibraryInfoTagNameView {
            Text("LibraryInfo.Tag.Title.Name")
          }

          LibraryInfoTagValueView {
            LibraryInfoTagValueContentView(property: libraryInfoTrack.title) { title in
              Text(title ?? "")
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
            LibraryInfoTagValueContentView(property: libraryInfoTrack.artistName) { artist in
              Text(artist ?? "")
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
            LibraryInfoTagValueContentView(property: libraryInfoTrack.albumName) { albumName in
              Text(albumName ?? "")
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
            LibraryInfoTagValueContentView(property: libraryInfoTrack.albumArtistName) { albumArtistName in
              Text(albumArtistName ?? "")
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
            LibraryInfoTagValueContentView(property: libraryInfoTrack.albumDate) { albumDate in
              LibraryAlbumYearView(albumDate: albumDate ?? .distantFuture)
                .visible(albumDate != nil)
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
            LibraryInfoPositionTagView(number: libraryInfoTrack.trackNumber, total: libraryInfoTrack.trackTotal)
          }
        }

        LibraryInfoTagView {
          LibraryInfoTagNameView {
            Text("LibraryInfo.Tag.Duration.Name")
          }

          LibraryInfoTagValueView {
            LibraryInfoTagValueContentView(property: libraryInfoTrack.duration) { duration in
              LibraryTrackDurationView(duration: duration)
            } mixed: {
              if let total = libraryInfoTrack.totalDuration, let average = libraryInfoTrack.averageDuration {
                VStack(alignment: .leading, spacing: 2) {
                  HStack(spacing: 4) {
                    Text("Total:")
                      .foregroundStyle(.secondary)
                    LibraryTrackDurationView(duration: total)
                  }
                  HStack(spacing: 4) {
                    Text("Avg:")
                      .foregroundStyle(.secondary)
                    LibraryTrackDurationView(duration: average)
                  }
                }
                .font(.caption2)
              } else {
                LibraryInfoTagValueMixedNumberView()
              }
            }
          }
        }
      }
      .safeAreaPadding(.horizontal, 12)
      .safeAreaPadding(.vertical, 8)
      }
    }
    .background(.ultraThickMaterial)
  }
}
