public import DockerKit
public import PhosphorCore
public import SwiftUI

/// Образы, тома и сети — три простые таблицы.
public struct DockerResourcesView: View {
    @Environment(\.style) private var style
    let model: AppModel
    let page: DockerPage

    public init(model: AppModel, page: DockerPage) {
        self.model = model
        self.page = page
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            switch page {
            case .images: images
            case .volumes: volumes
            case .networks: networks
            case .containers: EmptyView()
            }
            Spacer(minLength: 0)
        }
        .task(id: page) { await model.loadResources() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(model.strings(page.key)).font(style.font(15)).foregroundStyle(style.bright)
            Text(count).font(style.font(12)).foregroundStyle(style.muted)
            Spacer()
            if model.session == nil {
                Text("нет подключения").font(style.font(11.5)).foregroundStyle(style.muted)
            } else {
                PhButton("обновить") { Task { await model.loadResources() } }
            }
        }
    }

    private var count: String {
        switch page {
        case .images: "\(model.images.count)"
        case .volumes: "\(model.volumes.count)"
        case .networks: "\(model.networks.count)"
        case .containers: ""
        }
    }

    private var images: some View {
        table(["образ", "id", "создан", "размер"], widths: [nil, 120, 140, 90]) {
            ForEach(model.images) { image in
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Text(image.name)
                            .foregroundStyle(image.isDangling ? style.warning : style.text)
                            .lineLimit(1)
                        // Безымянные образы остаются после пересборки и молча
                        // едят диск — их стоит замечать.
                        if image.isDangling {
                            Text("занимает место зря")
                                .font(style.font(10)).foregroundStyle(style.warning.opacity(0.8))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String(image.id.prefix(12)))
                        .foregroundStyle(style.muted).frame(width: 120, alignment: .leading)
                    Text(image.created)
                        .foregroundStyle(style.muted).frame(width: 140, alignment: .leading)
                    Text(ByteFormat.size(image.size))
                        .foregroundStyle(style.text).frame(width: 90, alignment: .trailing)
                }
                .font(style.font(12))
                .padding(.vertical, 4)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(style.rule.opacity(0.4)).frame(height: 1)
                }
            }
        }
    }

    private var volumes: some View {
        table(["том", "драйвер", "точка монтирования"], widths: [260, 100, nil]) {
            ForEach(model.volumes) { volume in
                HStack(spacing: 10) {
                    Text(volume.name)
                        .foregroundStyle(style.text).frame(width: 260, alignment: .leading)
                        .lineLimit(1)
                    Text(volume.driver)
                        .foregroundStyle(style.muted).frame(width: 100, alignment: .leading)
                    Text(volume.mountpoint)
                        .foregroundStyle(style.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                }
                .font(style.font(12))
                .padding(.vertical, 4)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(style.rule.opacity(0.4)).frame(height: 1)
                }
            }
        }
    }

    private var networks: some View {
        table(["сеть", "id", "драйвер", "область"], widths: [nil, 140, 120, 100]) {
            ForEach(model.networks) { network in
                HStack(spacing: 10) {
                    Text(network.name)
                        .foregroundStyle(style.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String(network.id.prefix(12)))
                        .foregroundStyle(style.muted).frame(width: 140, alignment: .leading)
                    Text(network.driver)
                        .foregroundStyle(style.muted).frame(width: 120, alignment: .leading)
                    Text(network.scope)
                        .foregroundStyle(style.muted).frame(width: 100, alignment: .leading)
                }
                .font(style.font(12))
                .padding(.vertical, 4)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(style.rule.opacity(0.4)).frame(height: 1)
                }
            }
        }
    }

    /// Шапка таблицы плюс её строки.
    private func table(
        _ titles: [String], widths: [CGFloat?], @ViewBuilder rows: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ForEach(Array(zip(titles, widths).enumerated()), id: \.offset) { _, pair in
                    if let width = pair.1 {
                        Label2(pair.0).frame(width: width, alignment: .leading)
                    } else {
                        Label2(pair.0).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.bottom, 5)
            .overlay(alignment: .bottom) { Rule() }

            ScrollView { VStack(alignment: .leading, spacing: 0) { rows() } }
        }
    }
}
