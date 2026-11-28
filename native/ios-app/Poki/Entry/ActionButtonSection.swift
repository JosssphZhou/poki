import SwiftUI

/// Settings › Models › Voice: where to put Poki on the Action Button, in Control Center and on the Lock Screen.
struct ActionButtonSection: View {
    var body: some View {
        Section {
            Label {
                Text("Settings › Action Button › Shortcut › Poki Anytime", tableName: "Entry")
            } icon: {
                Image(systemName: "button.programmable")
            }
        } header: {
            Group {
                Text("Action Button", tableName: "Entry")
            }
            .settingsHeader()
        } footer: {
            Group {
                Text("Press and hold the Action button to talk with Poki without leaving the app you’re in. Press and hold it again to end the talk. To open Poki and talk there instead, choose Controls, then Talk to Poki. To type a task, choose Shortcut, then Send Task. Control Center and the Lock Screen can hold Talk to Poki too.", tableName: "Entry")
            }
            .settingsFooter()
        }
        Section {
            Text("Settings › Accessibility › Vocal Shortcuts", tableName: "Entry")
            Text("Settings › Accessibility › Touch › Back Tap", tableName: "Entry")
        } header: {
            Group {
                Text("Vocal Shortcuts and Back Tap", tableName: "Entry")
            }
            .settingsHeader()
        } footer: {
            Group {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Create a shortcut with the “Talk to Poki” action in Shortcuts. Select it in Vocal Shortcuts or Back Tap to start or return to a talk. Avoid “Poki Anytime” here because running it again ends the current talk.", tableName: "Entry")
                    Text("With Siri, say “Return to my call in Poki.”", tableName: "Entry")
                }
            }
            .settingsFooter()
        }
    }
}
