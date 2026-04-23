import SwiftUI
import DesignSystem

/// Full blog-post detail view. Renders the post body as plain text —
/// the source JSON stores unformatted content, so fancy rendering
/// (MarkdownUI) would be overkill and add a dependency.
struct BlogPostDetailView: View {
    let post: BlogPost

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.md) {
                Text(post.category.uppercased())
                    .font(BrandFont.caption)
                    .tracking(1.4)
                    .foregroundStyle(BrandColor.accent)
                Text(post.title)
                    .font(BrandFont.title)
                    .foregroundStyle(BrandColor.text)
                Text("\(post.author) • \(formattedPostDate(post.date))")
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                Text(post.summary)
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(BrandColor.text)
                    .padding(.top, BrandSpacing.sm)
                Divider().overlay(BrandColor.border)
                Text(post.content)
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.text)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BrandSpacing.lg)
        }
        .background(BrandColor.background)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .navigationTitle(post.category.capitalized)
    }
}

private func formattedPostDate(_ raw: String) -> String {
    let parser = DateFormatter()
    parser.dateFormat = "yyyy-MM-dd"
    parser.timeZone = TimeZone(identifier: "UTC")
    guard let date = parser.date(from: raw) else { return raw }

    let out = DateFormatter()
    out.dateFormat = "MMMM d, yyyy"
    out.timeZone = .current
    return out.string(from: date)
}
