//
//  PlayerBarView.swift
//  Sampled
//
//  Created by GitHub Copilot on 11/13/25.
//

import SwiftUI

struct PlayerBarView: View {
  let track: LibraryInfoTrackModel
  
  var body: some View {
    HStack(spacing: 16) {
      // Album artwork
      let image = switch track.albumArtwork {
        case .empty, .mixed: NSImage()
        case let .value(artwork): artwork?.image ?? NSImage()
      }
      
      Image(nsImage: image)
        .resizable()
        .aspectRatio(contentMode: .fill)
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
      
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
      .frame(maxWidth: .infinity, alignment: .leading)
      
      Spacer()
      
      // Playback controls (centered)
      HStack(spacing: 20) {
        Button(action: {}) {
          Image(systemName: "backward.fill")
            .font(.title3)
        }
        .buttonStyle(.plain)
        .help("Previous track")
        
        Button(action: {}) {
          Image(systemName: "play.fill")
            .font(.title2)
        }
        .buttonStyle(.plain)
        .help("Play/Pause")
        
        Button(action: {}) {
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
            if let total = track.totalDuration {
              HStack(spacing: 4) {
                Text("Total:")
                  .foregroundStyle(.tertiary)
                LibraryTrackDurationView(duration: total)
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
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(.ultraThinMaterial)
  }
}

#Preview {
  PlayerBarView(track: LibraryInfoTrackModel())
    .frame(height: 80)
}
