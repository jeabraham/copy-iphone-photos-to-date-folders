import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Photo Copier - Date Folders").font(.title)
                Text("Copies photos from memory cards and iPhones into YYYY/YYYY-MM-DD folders. Nothing is ever deleted from a card or phone, and files already imported are skipped, so it is safe to run again.")

                section("Getting started", [
                    "Choose an import destination. Its settings, memory cards and iPhones are saved in a hidden database inside that folder.",
                    "Set From / To to limit the dates copied (inclusive). Leave them off to copy everything.",
                    "Use Settings to choose the defaults: include videos, overwrite, dry run. A dry run lists what would be copied without copying.",
                    "Each card or phone can override those defaults with its own Settings.",
                ])
                section("Memory cards", [
                    "Press + and choose the card's DCIM folder. All subfolders are included.",
                    "Insert the card, then press Import. Show opens the card in Finder.",
                    "Card imports use the destination inventory. Previously imported photos stay deleted unless Redownload deleted photos is enabled in destination Settings.",
                    "Keep a separate source row for each card. Use Update location if its mount name changes, so its import history stays linked.",
                    "If the card is mounted under another name, use Update location. Delete only removes the row, never any photos.",
                ])
                section("iPhones", [
                    "Press + and follow the checklist: connect by USB, unlock, tap Trust, and close Lightroom, Image Capture and Photos import windows.",
                    "Import directly uses the same transfer as Image Capture.",
                    "Import via app pulls originals from the Photo Import Companion app. Keep it open on the phone and allow Full Access to Photos there.",
                    "Only plug in one phone or camera at a time.",
                    "If a photo is still downloading from iCloud, stay on Wi-Fi and try again.",
                ])
                VStack(alignment: .leading, spacing: 6) {
                    Text("Beta feedback").font(.headline)
                    if let feedbackURL = URL(string: "https://github.com/jeabraham/copy-iphone-photos-to-date-folders/issues/new") {
                        Link("Report a bug or suggest an improvement on GitHub", destination: feedbackURL)
                    }
                    Text("Include the app version, macOS version, source device, and steps to reproduce. GitHub reports are public; remove personal details from screenshots and logs.")
                }

                section("While importing", [
                    "The import window shows progress. Cancel stops the import; Done is available once it has finished.",
                    "After importing, use Next steps in Lightroom to add the folder to your catalog.",
                ])
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .frame(minWidth: 520, minHeight: 480)
    }

    private func section(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            ForEach(items, id: \.self) { Text("• \($0)") }
        }
    }
}
