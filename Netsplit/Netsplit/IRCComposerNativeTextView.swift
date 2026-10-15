import AppKit
import Combine

final class IRCComposerNativeTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onTab: (() -> Bool)?
    var onHistory: ((IRCComposerHistoryDirection, String) -> String?)?
    var onDidMoveToWindow: (() -> Void)?

    private var substitutions: IRCComposerSubstitutionPreferences?
    private var substitutionSubscription: AnyCancellable?
    private var isRestoringSubstitutions = false

    func configureSubstitutions(using preferences: IRCComposerSubstitutionPreferences) {
        substitutionSubscription?.cancel()
        substitutions = preferences
        substitutionSubscription = preferences.$overrides.sink { [weak self] overrides in
            guard let self else { return }
            self.isRestoringSubstitutions = true
            defer { self.isRestoringSubstitutions = false }
            for (setting, enabled) in overrides {
                self[keyPath: setting.keyPath] = enabled
            }
        }
    }

    // Observe the setters so both the context menu and the Substitutions panel
    // persist changes. Restoring a preference must not save other defaults or
    // publish another change back to the other open composers.
    override var smartInsertDeleteEnabled: Bool {
        didSet { saveSubstitution(smartInsertDeleteEnabled, for: .smartInsertDelete) }
    }

    override var isAutomaticQuoteSubstitutionEnabled: Bool {
        didSet { saveSubstitution(isAutomaticQuoteSubstitutionEnabled, for: .quotes) }
    }

    override var isAutomaticDashSubstitutionEnabled: Bool {
        didSet { saveSubstitution(isAutomaticDashSubstitutionEnabled, for: .dashes) }
    }

    override var isAutomaticLinkDetectionEnabled: Bool {
        didSet { saveSubstitution(isAutomaticLinkDetectionEnabled, for: .links) }
    }

    override var isAutomaticDataDetectionEnabled: Bool {
        didSet { saveSubstitution(isAutomaticDataDetectionEnabled, for: .dataDetection) }
    }

    override var isAutomaticTextReplacementEnabled: Bool {
        didSet { saveSubstitution(isAutomaticTextReplacementEnabled, for: .textReplacement) }
    }

    private func saveSubstitution(_ enabled: Bool, for setting: IRCComposerSubstitutionPreferences.Setting) {
        guard !isRestoringSubstitutions else { return }
        substitutions?.set(enabled, for: setting)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onDidMoveToWindow?()
    }

    override func keyDown(with event: NSEvent) {
        // Return and Tab belong to the input method while it is converting
        // marked text (for example, choosing a CJK candidate). Let AppKit
        // commit that composition before treating either key as a composer
        // command.
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 36 || event.keyCode == 76 {
            if modifiers.contains(.shift) || modifiers.contains(.option) {
                super.keyDown(with: event)
            } else {
                onSubmit?()
            }
            return
        }
        if event.keyCode == 48, !modifiers.contains(.shift) {
            if onTab?() != true {
                window?.selectNextKeyView(self)
            }
            return
        }
        if event.keyCode == 126 || event.keyCode == 125,
           modifiers.isDisjoint(with: [.shift, .control, .option, .command]) {
            let direction: IRCComposerHistoryDirection = event.keyCode == 126
                ? .previous
                : .next
            if IRCComposerHistoryCaretPolicy.canNavigate(
                direction,
                in: string,
                selectedRange: selectedRange()
            ), let recalledDraft = onHistory?(direction, string) {
                string = recalledDraft
                setSelectedRange(NSRange(
                    location: (recalledDraft as NSString).length,
                    length: 0
                ))
                didChangeText()
                return
            }
        }
        super.keyDown(with: event)
    }
}
