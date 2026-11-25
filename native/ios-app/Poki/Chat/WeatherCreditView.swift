import SwiftUI

/// Apple Weather's required mark and legal link, shown under the chat's latest forecast. WeatherKit's
/// attribution URLs are used as they come from the service; the text is a fallback if the mark cannot
/// load.
struct WeatherCreditView: View {
    let credit: PlaceTools.WeatherCredit
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 7) {
            AsyncImage(url: colorScheme == .dark ? credit.markDark : credit.markLight) { image in
                image.resizable().scaledToFit().frame(height: 17)
            } placeholder: {
                Image(systemName: "apple.logo").font(.caption)
            }
            Link(destination: credit.legal) {
                Text("Weather data by \(credit.service)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .underline()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: 720)
    }
}
