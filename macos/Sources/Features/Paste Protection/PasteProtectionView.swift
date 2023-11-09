import SwiftUI

/// This delegate is notified of the completion result of the paste protection dialog.
protocol PasteProtectionViewDelegate: AnyObject {
    func pasteProtectionComplete(_ action: PasteProtectionView.Action)
}

/// The SwiftUI view for showing a paste protection dialog.
struct PasteProtectionView: View {
    enum Action : String {
        case cancel
        case paste
    }
    
    /// The contents of the paste.
    let contents: String
    
    /// Optional delegate to get results. If this is nil, then this view will never close on its own.
    weak var delegate: PasteProtectionViewDelegate? = nil
    
    var body: some View {
        VStack {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 42))
                    .padding()
                    .frame(alignment: .center)
                
                Text("Pasting this text to the terminal may be dangerous as it looks like " +
                     "some commands may be executed.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            
            TextEditor(text: .constant(contents))
                .textSelection(.enabled)
                .font(.system(.body, design: .monospaced))
                .padding(.all, 4)
            
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Paste") { onPaste() }
                    .keyboardShortcut(.defaultAction)
                Spacer()
            }
            .padding(.bottom)
        }
    }
    
    private func onCancel() {
        delegate?.pasteProtectionComplete(.cancel)
    }
    
    private func onPaste() {
        delegate?.pasteProtectionComplete(.paste)
    }
}