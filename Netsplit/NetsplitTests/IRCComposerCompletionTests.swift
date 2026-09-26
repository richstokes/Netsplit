import Foundation
import Testing
@testable import Netsplit

struct IRCComposerCompletionTests {
    @Test("First-word nickname completion appends the configured suffix and one space", arguments: [":", ",", ">", "→", ": "])
    func appendsAddressingSuffix(suffix: String) throws {
        let completion = try #require(IRCComposerCompletion.recipientCompletion(
            in: "aLi",
            nicknames: ["Bob", "Alice"],
            suffix: suffix
        ))
        #expect(completion.completedDraft == "Alice" + suffix.trimmingCharacters(in: .whitespacesAndNewlines) + " ")
    }

    @Test("An empty suffix preserves nickname-only completion", arguments: ["", " "])
    func disablesSuffix(suffix: String) throws {
        let completion = try #require(IRCComposerCompletion.recipientCompletion(
            in: "ali", nicknames: ["Alice"], suffix: suffix
        ))
        #expect(completion.completedDraft == "Alice")
    }

    @Test("Repeated Tab cycles the original matches without duplicating punctuation or spaces", arguments: [":", ",", "", "→"])
    func cyclesOriginalMatches(suffix: String) throws {
        var completion = try #require(IRCComposerCompletion.recipientCompletion(
            in: "al", nicknames: ["Alina", "Bob", "Al", "Alice"], suffix: suffix
        ))
        let ending = suffix.isEmpty ? "" : suffix + " "
        #expect(completion.completedDraft == "Al" + ending)

        for expected in ["Alice", "Alina", "Al", "Alice"] {
            completion = try #require(IRCComposerCompletion.recipientCompletion(
                in: completion.completedDraft,
                nicknames: ["Bob"],
                suffix: suffix,
                continuing: completion
            ))
            #expect(completion.completedDraft == expected + ending)
        }
    }

    @Test("Cycling one match leaves the completed message unchanged")
    func cyclesSingleMatch() throws {
        var completion = try #require(IRCComposerCompletion.recipientCompletion(
            in: "ali", nicknames: ["Alice"], suffix: ":"
        ))
        for _ in 0..<3 {
            completion = try #require(IRCComposerCompletion.recipientCompletion(
                in: completion.completedDraft,
                nicknames: ["Alice"],
                suffix: ":",
                continuing: completion
            ))
            #expect(completion.completedDraft == "Alice: ")
        }
    }

    @Test("Mid-message and command recipient completions stay unpunctuated while cycling", arguments: [
        "hello al", "👋 café al", "hello ", "/msg al", "/notice al", "/op al",
        "/op #swift al", "/kick #swift al", "/msg al "
    ])
    func preservesRecipientContexts(input: String) throws {
        let context = try #require(IRCComposerCompletion.recipientContext(in: input))
        var completion = try #require(IRCComposerCompletion.recipientCompletion(
            in: input, nicknames: ["Alina", "Alice"], suffix: ":"
        ))
        #expect(completion.completedDraft == input.replacingCharacters(in: context.range, with: "Alice"))

        completion = try #require(IRCComposerCompletion.recipientCompletion(
            in: completion.completedDraft,
            nicknames: ["Alina", "Alice"],
            suffix: ":",
            continuing: completion
        ))
        #expect(completion.completedDraft == input.replacingCharacters(in: context.range, with: "Alina"))
    }

    @Test("Typing after completion starts a fresh completion at the new word")
    func resetsAfterEditing() throws {
        let previous = try #require(IRCComposerCompletion.recipientCompletion(
            in: "ali", nicknames: ["Alice", "Alina"], suffix: ":"
        ))
        let completion = try #require(IRCComposerCompletion.recipientCompletion(
            in: previous.completedDraft + "hello bo",
            nicknames: ["Alice", "Bob"],
            suffix: ":",
            continuing: previous
        ))
        #expect(completion.completedDraft == "Alice: hello Bob")

        let restarted = try #require(IRCComposerCompletion.recipientCompletion(
            in: "bo", nicknames: ["Alice", "Bob"], suffix: ",", continuing: previous
        ))
        #expect(restarted.completedDraft == "Bob, ")
    }

    @Test("Unmatched nicknames and unsupported contexts do not complete", arguments: ["", "zz", "/", "/join #swift", "/msg Alice hello"])
    func leavesNonMatchesAlone(input: String) {
        #expect(IRCComposerCompletion.recipientCompletion(
            in: input, nicknames: ["Alice"], suffix: ":"
        ) == nil)
    }

    @Test("Nickname completion suffix defaults to a colon and persists custom and empty values")
    @MainActor
    func persistsSuffixPreference() throws {
        let suiteName = "Netsplit.CompletionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentials = IRCInMemoryCredentialStore()
        let state = IRCAppState(defaults: defaults, credentialStore: credentials)
        #expect(state.nicknameCompletionSuffix == ":")

        for suffix in [",", ">", "", ":"] {
            state.nicknameCompletionSuffix = suffix
            let reloaded = IRCAppState(defaults: defaults, credentialStore: credentials)
            #expect(reloaded.nicknameCompletionSuffix == suffix)
        }
    }
}
