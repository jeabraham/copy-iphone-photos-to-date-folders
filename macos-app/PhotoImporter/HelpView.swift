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
                    "Press +, choose the card's DCIM folder, and give the card a recognizable name such as Egypt Card #1. All subfolders are included.",
                    "Write the same name on the physical card to help identify it. Rename a saved card in Settings without changing its import history.",
                    "Insert the card, then press Import. Show opens the card in Finder.",
                    "Card imports use the destination inventory. Previously imported photos stay deleted unless Redownload deleted photos is enabled in destination Settings.",
                    "The app writes a visible PhotoImporter-Card-ID.txt file beside DCIM to recognize the card independently of its volume name or path. Leave this file on the card.",
                    "If the identifier is missing, choose Same Card — Retain History only if the marker was accidentally deleted from the same, unformatted card. The app restores its saved identifier if possible. Choose New Card after formatting or replacing a card; you can then mark the old location obsolete.",
                    "For cards that cannot store an identifier, confirm Same Card or New Card each time. Choose New Card after formatting or replacing an unmarked card.",
                    "Use Update location when a card moves or to reactivate an obsolete row. Delete only removes the row, never any photos.",
                ])
                section("iPhones", [
                    "Press + and follow the checklist: connect by USB, unlock, tap Trust, and close Lightroom, Image Capture and Photos import windows.",
                    "Import directly uses the same transfer as Image Capture.",
                    "Import via app requires Photo Import Companion, a very simple iPhone app that is not yet publicly available.",
                    "The companion is currently only useful for photos whose originals have already been offloaded from the phone by iCloud Photos. Use Import directly for photos stored on the phone.",
                    "Contact the author using the GitHub feedback link below if you would like a copy of the companion app.",
                    "If you have the companion app, keep it open on the phone and allow Full Access to Photos there.",
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
