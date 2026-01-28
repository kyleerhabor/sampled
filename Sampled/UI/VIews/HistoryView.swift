//
//  HistoryView.swift
//  Sampled
//
//  Created by GitHub Copilot on 11/13/25.
//

import SwiftUI

struct HistoryItemModel: Identifiable {
  let id: UUID = UUID()
  let title: String
  let artist: String
  let album: String
  let playedAt: Date
  let duration: Duration
}

struct HistoryView: View {
  @State private var historyItems: [HistoryItemModel] = []
  
  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Text("Play History")
          .font(.largeTitle.bold())
        
        Spacer()
        
        Button("Clear History") {
          historyItems.removeAll()
        }
        .controlSize(.large)
      }
      .padding()
      .background(.ultraThinMaterial)
      
      Divider()
      
      if historyItems.isEmpty {
        ContentUnavailableView {
          Label("No History", systemImage: "clock")
        } description: {
          Text("Your recently played tracks will appear here")
        }
      } else {
        ScrollView {
          LazyVStack(spacing: 8) {
            ForEach(historyItems) { item in
              HistoryItemView(item: item)
            }
          }
          .padding()
        }
      }
    }
  }
}

struct HistoryItemView: View {
  let item: HistoryItemModel
  
  var body: some View {
    HStack(spacing: 12) {
      // Time badge
      VStack(alignment: .leading, spacing: 4) {
        Text(item.playedAt, style: .time)
          .font(.caption.bold())
          .foregroundStyle(.primary)
        Text(item.playedAt, style: .date)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .frame(width: 80, alignment: .leading)
      
      Divider()
        .frame(height: 40)
      
      // Track info
      VStack(alignment: .leading, spacing: 4) {
        Text(item.title)
          .font(.headline)
          .lineLimit(1)
        
        HStack(spacing: 4) {
          Text(item.artist)
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Text("•")
            .foregroundStyle(.quaternary)
          Text(item.album)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      
      // Duration
      LibraryTrackDurationView(duration: item.duration)
        .font(.caption)
        .foregroundStyle(.tertiary)
      
      // Actions
      Button {
        // Play again
      } label: {
        Image(systemName: "play.fill")
          .font(.title3)
      }
      .buttonStyle(.plain)
      .help("Play again")
    }
    .padding()
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
  }
}

#Preview {
  HistoryView()
    .frame(width: 800, height: 600)
}
