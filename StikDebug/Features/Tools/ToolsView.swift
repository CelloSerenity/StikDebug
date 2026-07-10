//
//  ToolsView.swift
//  StikDebug
//
//  Created by Stephen on 2/23/26.
//

import SwiftUI

struct ToolsView: View {
    @ObservedObject private var pairingImport = PairingFileImportCoordinator.shared
    @State private var searchText = ""

    private var filteredTools: [AppFeature] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return AppFeature.toolList }

        return AppFeature.toolList.filter { tool in
            tool.toolTitle.localizedCaseInsensitiveContains(query)
                || tool.detail.localizedCaseInsensitiveContains(query)
                || tool.title.localizedCaseInsensitiveContains(query)
        }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    searchResultsSection
                } else {
                    hubSections
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("StikDebug")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search tools")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        pairingImport.requestImport()
                    } label: {
                        Image(systemName: "doc.badge.plus")
                    }
                    .accessibilityLabel("Import Pairing File")
                }
            }
        }
    }

    @ViewBuilder
    private var hubSections: some View {
        ForEach(ToolHubSection.allCases) { section in
            let tools = section.tools
            if !tools.isEmpty {
                Section(section.title) {
                    ForEach(tools) { tool in
                        toolNavigationLink(tool)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var searchResultsSection: some View {
        Section {
            if filteredTools.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(filteredTools) { tool in
                    toolNavigationLink(tool)
                }
            }
        } header: {
            Text("Results")
        }
    }

    private func toolNavigationLink(_ tool: AppFeature) -> some View {
        NavigationLink {
            tool.destination
        } label: {
            ToolHubRow(tool: tool)
        }
    }
}

private struct ToolHubRow: View {
    let tool: AppFeature

    var body: some View {
        HStack(spacing: 14) {
            HubIconBadge(systemImage: tool.systemImage, style: .palette(tool.hubPalette))

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.toolTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(tool.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tool.toolTitle). \(tool.detail)")
    }
}

#Preview {
    ToolsView()
}
