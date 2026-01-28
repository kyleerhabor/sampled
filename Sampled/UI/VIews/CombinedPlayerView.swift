//
//  CombinedPlayerView.swift
//  Sampled
//
//  Created by GitHub Copilot on 11/13/25.
//

import SwiftUI

struct CombinedPlayerView: View {
  let track: LibraryInfoTrackModel
  let isPlaying: Bool
  let onPlayTapped: () -> Void
  let onPrevious: () -> Void
  let onNext: () -> Void
  @State private var showFullInfo = false
  @FocusState private var isFocused: Bool
  
  var body: some View {
    VStack(spacing: 0) {
      // Player bar
      HStack(spacing: 16) {
        // Album artwork
        let image = switch track.albumArtwork {
          case .empty, .mixed: NSImage()
          case let .value(artwork): artwork?.image ?? NSImage()
        }
        
        Button {
          withAnimation(.snappy(duration: 0.25)) {
            showFullInfo.toggle()
          }
        } label: {
          Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            .overlay(alignment: .bottomTrailing) {
              Image(systemName: showFullInfo ? "chevron.down.circle.fill" : "info.circle.fill")
                .font(.caption)
                .padding(4)
                .background(.ultraThinMaterial, in: Circle())
                .padding(2)
            }
        }
        .buttonStyle(.plain)
        .help("Show/hide track details")
        
        // Track info
        VStack(alignment: .leading, spacing: 4) {
          switch track.title {
            case .empty:
              Text("No track selected")
                .font(.headline)
                .foregroundStyle(.secondary)
            case .value(let title):
              Text(title ?? "Unknown")
                .font(.headline)
                .lineLimit(1)
            case .mixed:
              Text("Multiple tracks")
                .font(.headline)
                .foregroundStyle(.secondary)
          }
          
          HStack(spacing: 4) {
            switch track.artistName {
              case .empty:
                EmptyView()
              case .value(let artist):
                Text(artist ?? "Unknown Artist")
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              case .mixed:
                Text("Various Artists")
                  .font(.subheadline)
                  .foregroundStyle(.tertiary)
                  .lineLimit(1)
            }
            
            if case .value(let albumName) = track.albumName, let name = albumName {
              Text("•")
                .foregroundStyle(.quaternary)
              Text(name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
        }
        .frame(width: 250, alignment: .leading)
        
        Spacer()
        
        // Playback controls (centered)
        HStack(spacing: 20) {
          Button(action: onPrevious) {
            Image(systemName: "backward.fill")
              .font(.title3)
          }
          .buttonStyle(.plain)
          .help("Previous track")
          
          Button(action: onPlayTapped) {
            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
              .font(.system(size: 36))
          }
          .buttonStyle(.plain)
          .help(isPlaying ? "Pause" : "Play")
          
          Button(action: onNext) {
            Image(systemName: "forward.fill")
              .font(.title3)
          }
          .buttonStyle(.plain)
          .help("Next track")
        }
        .frame(maxWidth: 200)
        
        Spacer()
        
        // Duration and controls
        HStack(spacing: 12) {
          switch track.duration {
            case .empty:
              EmptyView()
            case .value(let duration):
              LibraryTrackDurationView(duration: duration)
                .font(.caption)
                .foregroundStyle(.secondary)
            case .mixed:
              if let total = track.totalDuration, let average = track.averageDuration {
                VStack(alignment: .trailing, spacing: 2) {
                  HStack(spacing: 4) {
                    Text("Total:")
                      .foregroundStyle(.tertiary)
                    LibraryTrackDurationView(duration: total)
                  }
                  HStack(spacing: 4) {
                    Text("Avg:")
                      .foregroundStyle(.tertiary)
                    LibraryTrackDurationView(duration: average)
                  }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
              }
          }
          
          Divider()
            .frame(height: 20)
          
          Button(action: {}) {
            Image(systemName: "speaker.wave.2.fill")
          }
          .buttonStyle(.plain)
          .help("Volume")
        }
        .frame(width: 150, alignment: .trailing)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .frame(height: 80)
      
      // Full info panel (expandable)
      if showFullInfo {
        Divider()
        
        ScrollView(showsIndicators: false) {
          Grid(alignment: .centerFirstTextBaseline, verticalSpacing: 0) {
            LibraryInfoTagView {
              LibraryInfoTagNameView {
                Text("LibraryInfo.Tag.Title.Name")
              }
              
              LibraryInfoTagValueView {
                LibraryInfoTagValueContentView(property: track.title) { title in
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
                LibraryInfoTagValueContentView(property: track.artistName) { artist in
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
                LibraryInfoTagValueContentView(property: track.albumName) { albumName in
                  Text(albumName ?? "")
                } mixed: {
                  LibraryInfoTagValueMixedTextView()
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
          }
          .safeAreaPadding(.horizontal, 12)
          .safeAreaPadding(.vertical, 8)
        }
        .frame(maxHeight: 200)
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .background(.ultraThinMaterial)
    .focusable()
    .focused($isFocused)
    .onKeyPress { press in
      if press.characters == "i" && press.modifiers.contains(.command) {
        withAnimation(.snappy(duration: 0.25)) {
          showFullInfo.toggle()
        }
        return .handled
      }
      return .ignored
    }
    .onAppear {
      isFocused = true
    }
  }
}

#Preview {
  CombinedPlayerView(
    track: LibraryInfoTrackModel(),
    isPlaying: false,
    onPlayTapped: {},
    onPrevious: {},
    onNext: {}
  )
  .frame(width: 800)
}
